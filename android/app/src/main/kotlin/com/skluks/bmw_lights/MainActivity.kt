package com.skluks.bmw_lights

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.os.Build
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/** Bluetooth Classic SPP bridge for adapters without BLE (see lib/transport/spp_link.dart). */
class MainActivity : FlutterActivity() {
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    @Volatile
    private var socket: BluetoothSocket? = null
    private var sink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private val permissionRequestCode = 4711

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "bmw_lights/spp/data").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        MethodChannel(messenger, "bmw_lights/spp").setMethodCallHandler { call, result ->
            when (call.method) {
                "permissions" -> requestBtPermissions(result)
                "bonded" -> bonded(result)
                "connect" -> connect(call.argument<String>("address")!!, result)
                "write" -> write(call.arguments as ByteArray, result)
                "disconnect" -> {
                    closeSocket()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun btPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun requestBtPermissions(result: MethodChannel.Result) {
        val missing = btPermissions().filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        permissionResult?.success(false)
        permissionResult = result
        requestPermissions(missing.toTypedArray(), permissionRequestCode)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        permissionResult?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
        permissionResult = null
    }

    private fun adapter() = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    @SuppressLint("MissingPermission")
    private fun bonded(result: MethodChannel.Result) {
        try {
            val list = adapter()?.bondedDevices?.map {
                mapOf("name" to (it.name ?: it.address), "address" to it.address)
            }
            result.success(list ?: emptyList<Map<String, String>>())
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String, result: MethodChannel.Result) {
        closeSocket()
        io.execute {
            try {
                val bt = adapter() ?: throw IOException("Bluetooth недоступен")
                bt.cancelDiscovery()
                val device = bt.getRemoteDevice(address)
                val s = try {
                    device.createRfcommSocketToServiceRecord(sppUuid).also { it.connect() }
                } catch (e: IOException) {
                    // Some cheap adapters only accept an insecure socket.
                    device.createInsecureRfcommSocketToServiceRecord(sppUuid).also { it.connect() }
                }
                socket = s
                startReader(s)
                main.post { result.success(null) }
            } catch (e: Exception) {
                main.post { result.error("connect", e.message, null) }
            }
        }
    }

    private fun startReader(s: BluetoothSocket) {
        Thread {
            val buf = ByteArray(1024)
            try {
                val input = s.inputStream
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    val chunk = buf.copyOf(n)
                    main.post { if (socket === s) sink?.success(chunk) }
                }
            } catch (_: IOException) {
            }
            // Only report the end of the socket that is still current (not one we replaced/closed).
            main.post { if (socket === s) sink?.endOfStream() }
        }.apply {
            isDaemon = true
            start()
        }
    }

    private fun write(data: ByteArray, result: MethodChannel.Result) {
        val s = socket
        if (s == null) {
            result.error("write", "not connected", null)
            return
        }
        io.execute {
            try {
                s.outputStream.write(data)
                s.outputStream.flush()
                main.post { result.success(null) }
            } catch (e: IOException) {
                main.post { result.error("write", e.message, null) }
            }
        }
    }

    private fun closeSocket() {
        val s = socket
        socket = null
        try {
            s?.close()
        } catch (_: IOException) {
        }
    }

    override fun onDestroy() {
        closeSocket()
        io.shutdown()
        super.onDestroy()
    }
}

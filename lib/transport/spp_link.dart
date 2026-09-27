import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'byte_link.dart';

class SppDevice {
  const SppDevice(this.name, this.address);
  final String name;
  final String address;
}

/// Bluetooth Classic (SPP / RFCOMM) link, Android only.
/// Native side: android/app/src/main/kotlin/.../MainActivity.kt
class SppLink implements ByteLink {
  SppLink._(this.device);

  static const _methods = MethodChannel('bmw_lights/spp');
  static const _events = EventChannel('bmw_lights/spp/data');

  static bool get supported => Platform.isAndroid;

  final SppDevice device;
  final _input = StreamController<List<int>>.broadcast();
  final _done = Completer<void>();
  StreamSubscription<dynamic>? _sub;

  /// Asks for the Bluetooth runtime permissions (Android). Returns true when granted.
  static Future<bool> requestPermissions() async {
    if (!supported) return true;
    return await _methods.invokeMethod<bool>('permissions') ?? false;
  }

  /// Paired devices (pair the adapter in Android Bluetooth settings first).
  static Future<List<SppDevice>> bondedDevices() async {
    if (!supported) return const [];
    final list = await _methods.invokeListMethod<Map<dynamic, dynamic>>('bonded') ?? const [];
    return [for (final m in list) SppDevice(m['name'] as String? ?? '?', m['address'] as String)];
  }

  static Future<SppLink> connect(SppDevice device) async {
    final link = SppLink._(device);
    link._sub = _events.receiveBroadcastStream().listen(
      (data) => link._input.add(data as Uint8List),
      onError: (Object _) => link._finish(),
      onDone: link._finish,
    );
    try {
      await _methods.invokeMethod<void>('connect', {'address': device.address});
    } catch (_) {
      await link.close();
      rethrow;
    }
    return link;
  }

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  String get name => '${device.name} (Bluetooth)';

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> write(List<int> data) => _methods.invokeMethod<void>('write', Uint8List.fromList(data));

  @override
  Future<void> close() async {
    try {
      await _methods.invokeMethod<void>('disconnect');
    } catch (_) {}
    await _sub?.cancel();
    _finish();
    await _input.close();
  }
}

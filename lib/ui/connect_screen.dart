import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/app_controller.dart';
import '../core/hex.dart';
import '../transport/ble_link.dart';
import '../transport/spp_link.dart';
import 'home.dart';
import 'terminal_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.app, required this.onConnected});
  final AppController app;
  final VoidCallback onConnected;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  List<ScanResult> _ble = [];
  List<SppDevice> _bonded = [];
  bool _scanning = false;
  StreamSubscription<List<ScanResult>>? _scanSub;

  AppController get app => widget.app;

  static bool _looksLikeAdapter(String name) =>
      RegExp(r'vlink|obd|elm|vgate|bm\+|icar|v-link|carly|bimmer', caseSensitive: false).hasMatch(name);

  @override
  void dispose() {
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<bool> _permissions() async {
    if (!Platform.isAndroid) return true;
    final r = await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    final denied = r.entries.where((e) => e.value.isPermanentlyDenied).toList();
    if (denied.isNotEmpty && mounted) {
      showSnack(context, 'Разрешите Bluetooth в настройках приложения');
      await openAppSettings();
      return false;
    }
    return true;
  }

  Future<void> _scan() async {
    if (!await _permissions()) return;
    if (SppLink.supported) {
      try {
        _bonded = await SppLink.bondedDevices();
      } catch (e) {
        if (mounted) showSnack(context, 'Сопряжённые устройства: $e');
      }
    }
    setState(() {
      _scanning = true;
      _ble = [];
    });
    try {
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((r) {
        if (mounted) setState(() => _ble = r.where((x) => x.device.platformName.isNotEmpty).toList());
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (e) {
      if (mounted) showSnack(context, 'Поиск BLE: $e');
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(Future<void> Function() body) async {
    await FlutterBluePlus.stopScan();
    await body();
    if (!mounted) return;
    if (app.connected) {
      showSnack(context, 'Подключено: ${app.linkName}');
      widget.onConnected();
    } else if (app.error != null) {
      showSnack(context, app.error!);
    }
  }

  Future<void> _connectBle(BluetoothDevice d) => _connect(() => app.connectWith(() => BleLink.connect(d), 'BLE'));

  Future<void> _connectSpp(SppDevice d) =>
      _connect(() => app.connectWith(() => SppLink.connect(d), 'Bluetooth'));

  Future<void> _editHex(String title, int? value, int maxLen, Future<void> Function(int?) save,
      {bool allowEmpty = false}) async {
    final ctl = TextEditingController(text: value == null ? '' : hexByte(value));
    final r = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(hintText: allowEmpty ? 'пусто = не открывать' : 'hex, например 70'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('OK')),
        ],
      ),
    );
    if (r == null) return;
    final bytes = tryParseHex(r);
    if (bytes == null || bytes.length > maxLen || (bytes.isEmpty && !allowEmpty)) {
      if (mounted) showSnack(context, 'Неверное значение');
      return;
    }
    await save(bytes.isEmpty ? null : bytes.first);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final busy = app.state == LinkState.connecting;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Подключение', style: t.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(
                  app.connected ? Icons.check_circle : Icons.link_off,
                  color: app.connected ? Colors.greenAccent : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    switch (app.state) {
                      LinkState.connected => app.linkName,
                      LinkState.connecting => 'Подключаюсь…',
                      LinkState.disconnected => 'Не подключено',
                    },
                    style: t.titleMedium,
                  ),
                ),
                if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              if (app.adapterVersion != null) Text('Адаптер: ${app.adapterVersion}'),
              if (app.moduleStatus != null) Text(app.moduleStatus!),
              if (app.error != null)
                Text(app.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (app.connected) ...[
                  OutlinedButton.icon(
                    onPressed: () => app.checkModule(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Проверить модуль'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => app.disconnect(),
                    icon: const Icon(Icons.close),
                    label: const Text('Отключиться'),
                  ),
                ] else
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : () => _connect(app.connectDemo),
                    icon: const Icon(Icons.directions_car),
                    label: const Text('Демо без машины'),
                  ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => TerminalScreen(app: app))),
                  icon: const Icon(Icons.terminal),
                  label: const Text('Терминал / лог'),
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Адаптеры', style: t.titleMedium)),
          FilledButton.icon(
            onPressed: _scanning || busy ? null : _scan,
            icon: _scanning
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: const Text('Искать'),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Вставьте vLinker в OBD, включите зажигание. BimmerCode/BimmerLink должны быть закрыты — '
            'к адаптеру может подключиться только одно приложение.',
          ),
        ),
        if (_bonded.isNotEmpty) ...[
          Text('Сопряжённые (Bluetooth Classic)', style: t.labelLarge),
          for (final d in _bonded)
            ListTile(
              leading: Icon(Icons.bluetooth, color: _looksLikeAdapter(d.name) ? Colors.lightBlueAccent : null),
              title: Text(d.name),
              subtitle: Text(d.address),
              onTap: busy ? null : () => _connectSpp(d),
            ),
        ],
        if (_ble.isNotEmpty) ...[
          Text('Bluetooth LE', style: t.labelLarge),
          for (final r in (_ble.toList()
            ..sort((a, b) =>
                (_looksLikeAdapter(b.device.platformName) ? 1 : 0) - (_looksLikeAdapter(a.device.platformName) ? 1 : 0))))
            ListTile(
              leading: Icon(Icons.bluetooth_searching,
                  color: _looksLikeAdapter(r.device.platformName) ? Colors.lightBlueAccent : null),
              title: Text(r.device.platformName),
              subtitle: Text('${r.device.remoteId.str}  ${r.rssi} dBm'),
              onTap: busy ? null : () => _connectBle(r.device),
            ),
        ],
        if (!_scanning && _ble.isEmpty && _bonded.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Нажмите «Искать». Если адаптер не виден по BLE — сопрягите его в настройках Bluetooth '
                'телефона, он появится в списке «Сопряжённые».'),
          ),
        const Divider(height: 32),
        Text('Настройки диагностики', style: t.titleMedium),
        ListTile(
          title: const Text('Адрес модуля света'),
          subtitle: const Text('E60: LM = 70'),
          trailing: Text(hexByte(app.ecu), style: t.titleMedium),
          onTap: () => _editHex('Адрес модуля (hex)', app.ecu, 1, (v) => app.setEcu(v!)),
        ),
        ListTile(
          title: const Text('Диагностическая сессия'),
          subtitle: const Text('Пусто — не открывать. Если сканер скажет «нужна сессия», попробуйте 86 или 89'),
          trailing: Text(app.session == null ? '—' : hexByte(app.session!), style: t.titleMedium),
          onTap: () => _editHex('Сессия (hex)', app.session, 1, app.setSession, allowEmpty: true),
        ),
      ],
    );
  }
}

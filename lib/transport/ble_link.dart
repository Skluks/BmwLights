import 'dart:async';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'byte_link.dart';

/// Serial-over-BLE link (vLinker BM+, OBDLink CX, Vgate iCar and most ELM clones).
/// Picks the vendor service that offers a notify and a write characteristic.
class BleLink implements ByteLink {
  BleLink._(this.device, this._rx, this._tx);

  final BluetoothDevice device;
  final BluetoothCharacteristic _rx;
  final BluetoothCharacteristic _tx;
  final _input = StreamController<List<int>>.broadcast();
  final _done = Completer<void>();
  final List<StreamSubscription<Object?>> _subs = [];

  static const _standardServices = {'1800', '1801', '180a', '180f', '1805'};
  static const _preferredServices = {'fff0', 'ffe0', '18f0', 'e7810a71-73ae-499d-8c15-faa9aef0c3f2'};

  static Future<BleLink> connect(BluetoothDevice device) async {
    await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
    final services = await device.discoverServices();
    services.sort((a, b) {
      int rank(BluetoothService s) => _preferredServices.contains(s.uuid.str.toLowerCase()) ? 0 : 1;
      return rank(a) - rank(b);
    });
    for (final s in services) {
      if (_standardServices.contains(s.uuid.str.toLowerCase())) continue;
      BluetoothCharacteristic? rx, tx;
      for (final c in s.characteristics) {
        final p = c.properties;
        if (rx == null && (p.notify || p.indicate)) rx = c;
        if (tx == null && (p.write || p.writeWithoutResponse)) tx = c;
      }
      if (rx != null && tx != null) {
        final link = BleLink._(device, rx, tx);
        await link._start();
        return link;
      }
    }
    await device.disconnect();
    throw StateError('У адаптера не найден последовательный BLE-сервис');
  }

  Future<void> _start() async {
    _subs.add(_rx.onValueReceived.listen(_input.add));
    device.cancelWhenDisconnected(_subs.last);
    await _rx.setNotifyValue(true);
    _subs.add(device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && !_done.isCompleted) _done.complete();
    }));
  }

  @override
  String get name => '${device.platformName.isEmpty ? device.remoteId.str : device.platformName} (BLE)';

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> write(List<int> data) async {
    final noResp = _tx.properties.writeWithoutResponse;
    final chunk = max(20, device.mtuNow - 3);
    for (var i = 0; i < data.length; i += chunk) {
      await _tx.write(data.sublist(i, min(i + chunk, data.length)), withoutResponse: noResp);
    }
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    try {
      await device.disconnect();
    } catch (_) {}
    if (!_done.isCompleted) _done.complete();
    await _input.close();
  }
}

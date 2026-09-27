import 'dart:async';

import '../core/hex.dart';
import '../model/lamp.dart';
import '../model/lamp_map.dart';
import '../protocol/diag.dart';

/// Minimal interface of [DiagClient] used by the engine (lets tests fake it).
abstract class DiagPort {
  /// Raw answer, positive or negative (7F ..). Throws [NoResponse] on silence.
  Future<List<int>> request(int ecu, List<int> payload);

  /// Throws [NegativeResponse] unless the answer is positive.
  Future<List<int>> requestPositive(int ecu, List<int> payload);
}

class DiagClientPort implements DiagPort {
  DiagClientPort(this.client);
  final DiagClient client;
  @override
  Future<List<int>> request(int ecu, List<int> payload) => client.request(ecu, payload);
  @override
  Future<List<int>> requestPositive(int ecu, List<int> payload) => client.requestPositive(ecu, payload);
}

/// Turns "these lamps should be lit" into the minimum number of diagnostic requests.
class LightController {
  LightController(this.port, this.map, {this.onError});

  final DiagPort port;
  final LampMap map;
  final void Function(Object error)? onError;

  /// Last state sent per (ecu, lid).
  final Map<(int, int), List<int>> _ioSent = {};
  final Set<Lamp> _rawOn = {};
  Set<Lamp> _lit = {};

  Set<Lamp> get lit => _lit;

  /// Lamps that can actually be driven.
  Set<Lamp> get controllable => map.bindings.keys.toSet();

  /// Computes the IO-control state for every LID touched by the lamp map.
  Map<(int, int), List<int>> _ioTarget(Set<Lamp> on) {
    final target = <(int, int), List<int>>{};
    for (final e in map.bindings.entries) {
      final b = e.value;
      if (b is! IoBinding) continue;
      final key = (b.ecu, b.lid);
      final cur = target[key] ?? <int>[];
      if (cur.length < b.onState.length) cur.addAll(List.filled(b.onState.length - cur.length, 0));
      if (on.contains(e.key)) {
        for (var i = 0; i < b.onState.length; i++) {
          cur[i] |= b.onState[i];
        }
      }
      target[key] = cur;
    }
    return target;
  }

  /// Drives the car so that exactly [on] (of the mapped lamps) is lit.
  Future<void> apply(Set<Lamp> on) async {
    for (final e in _ioTarget(on).entries) {
      if (bytesEqual(_ioSent[e.key], e.value)) continue;
      final (ecu, lid) = e.key;
      await _send(ecu, IoControl.set(lid, e.value));
      _ioSent[e.key] = e.value;
    }
    for (final e in map.bindings.entries) {
      final b = e.value;
      if (b is! RawBinding) continue;
      final want = on.contains(e.key);
      if (want == _rawOn.contains(e.key)) continue;
      await _send(b.ecu, want ? b.onRequest : b.offRequest);
      want ? _rawOn.add(e.key) : _rawOn.remove(e.key);
    }
    _lit = on.intersection(controllable);
  }

  Future<void> _send(int ecu, List<int> req) async {
    try {
      await port.requestPositive(ecu, req);
    } catch (e) {
      onError?.call(e);
      rethrow;
    }
  }

  /// Gives every touched output back to the light module. Never throws.
  Future<void> releaseAll() async {
    for (final key in _ioSent.keys.toList()) {
      final (ecu, lid) = key;
      try {
        await port.requestPositive(ecu, IoControl.release(lid));
      } catch (e) {
        onError?.call(e);
      }
    }
    _ioSent.clear();
    for (final lamp in _rawOn.toList()) {
      final b = map.bindings[lamp];
      if (b is RawBinding) {
        try {
          await port.requestPositive(b.ecu, b.offRequest);
        } catch (e) {
          onError?.call(e);
        }
      }
    }
    _rawOn.clear();
    _lit = {};
  }

  String describe() => [
        for (final e in _ioSent.entries) 'ECU ${hexByte(e.key.$1)} LID ${hexByte(e.key.$2)} = ${toHex(e.value)}',
      ].join('\n');
}

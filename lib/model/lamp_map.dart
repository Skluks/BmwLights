import 'dart:convert';

import '../core/hex.dart';
import 'lamp.dart';

/// How to switch one lamp.
sealed class LampBinding {
  const LampBinding();

  Map<String, Object?> toJson();

  static LampBinding? fromJson(Map<String, Object?> j) {
    switch (j['type']) {
      case 'io':
        return IoBinding(
          ecu: j['ecu'] as int,
          lid: j['lid'] as int,
          onState: (j['on'] as List).cast<int>(),
        );
      case 'raw':
        return RawBinding(
          ecu: j['ecu'] as int,
          onRequest: (j['on'] as List).cast<int>(),
          offRequest: (j['off'] as List).cast<int>(),
        );
    }
    return null;
  }
}

/// Lamp is (part of) an output controlled with `30 <lid> 07 <state>`.
/// Several lamps can share one [lid]; their [onState] bytes are OR-ed together.
class IoBinding extends LampBinding {
  const IoBinding({required this.ecu, required this.lid, required this.onState});
  final int ecu;
  final int lid;
  final List<int> onState;

  @override
  Map<String, Object?> toJson() => {'type': 'io', 'ecu': ecu, 'lid': lid, 'on': onState};

  @override
  String toString() => 'LID ${hexByte(lid)} = ${toHex(onState)}';
}

/// Arbitrary requests (e.g. copied from a Deep OBD / Tool32 trace).
class RawBinding extends LampBinding {
  const RawBinding({required this.ecu, required this.onRequest, required this.offRequest});
  final int ecu;
  final List<int> onRequest;
  final List<int> offRequest;

  @override
  Map<String, Object?> toJson() => {'type': 'raw', 'ecu': ecu, 'on': onRequest, 'off': offRequest};

  @override
  String toString() => 'вкл ${toHex(onRequest)} / выкл ${toHex(offRequest)}';
}

class LampMap {
  LampMap([Map<Lamp, LampBinding>? bindings]) : bindings = {...?bindings};

  final Map<Lamp, LampBinding> bindings;

  bool get isEmpty => bindings.isEmpty;

  String encode() => jsonEncode({for (final e in bindings.entries) e.key.name: e.value.toJson()});

  static LampMap decode(String text) {
    final map = LampMap();
    final j = jsonDecode(text) as Map<String, Object?>;
    for (final e in j.entries) {
      final lamp = Lamp.byName(e.key);
      final b = LampBinding.fromJson((e.value as Map).cast<String, Object?>());
      if (lamp != null && b != null) map.bindings[lamp] = b;
    }
    return map;
  }
}

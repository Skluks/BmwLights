import 'dart:convert';

import 'lamp.dart';

class EffectFrame {
  EffectFrame(Set<Lamp> lamps, this.durationMs) : lamps = {...lamps};

  final Set<Lamp> lamps;
  int durationMs;

  EffectFrame copy() => EffectFrame(lamps, durationMs);

  Map<String, Object?> toJson() => {'l': [for (final l in lamps) l.name], 'ms': durationMs};

  static EffectFrame fromJson(Map<String, Object?> j) => EffectFrame(
        {for (final n in (j['l'] as List).cast<String>()) ?Lamp.byName(n)},
        j['ms'] as int,
      );
}

enum EffectCategory {
  show('Шоу'),
  classic('Классика'),
  custom('Мои эффекты');

  const EffectCategory(this.title);
  final String title;
}

class Effect {
  Effect({
    required this.id,
    required this.name,
    required this.frames,
    this.loops = 1,
    this.builtIn = false,
    this.category = EffectCategory.custom,
  });

  final String id;
  String name;
  final List<EffectFrame> frames;

  /// How many times the frame list is played; 0 = until stopped.
  int loops;
  final bool builtIn;
  final EffectCategory category;

  int get cycleMs => frames.fold(0, (s, f) => s + f.durationMs);

  Set<Lamp> get usedLamps => {for (final f in frames) ...f.lamps};

  Effect copyAs({required String id, String? name}) => Effect(
        id: id,
        name: name ?? this.name,
        frames: [for (final f in frames) f.copy()],
        loops: loops,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'loops': loops,
        'frames': [for (final f in frames) f.toJson()],
      };

  static Effect fromJson(Map<String, Object?> j) => Effect(
        id: j['id'] as String,
        name: j['name'] as String,
        loops: j['loops'] as int? ?? 1,
        frames: [for (final f in (j['frames'] as List)) EffectFrame.fromJson((f as Map).cast())],
      );

  static String encodeList(List<Effect> list) => jsonEncode([for (final e in list) e.toJson()]);

  static List<Effect> decodeList(String text) =>
      [for (final e in jsonDecode(text) as List) Effect.fromJson((e as Map).cast())];
}

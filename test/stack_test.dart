import 'package:bmw_lights/core/hex.dart';
import 'package:bmw_lights/effects/presets.dart';
import 'package:bmw_lights/engine/effect_player.dart';
import 'package:bmw_lights/engine/light_controller.dart';
import 'package:bmw_lights/engine/scanner.dart';
import 'package:bmw_lights/model/effect.dart';
import 'package:bmw_lights/model/lamp.dart';
import 'package:bmw_lights/model/lamp_map.dart';
import 'package:bmw_lights/protocol/diag.dart';
import 'package:bmw_lights/protocol/elm.dart';
import 'package:bmw_lights/sim/sim_car.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sink implements LampSink {
  _Sink(this.ctl);
  final LightController ctl;
  @override
  Future<void> show(Set<Lamp> lamps) => ctl.apply(lamps);
  @override
  Future<void> finish() => ctl.releaseAll();
}

void main() {
  late SimCar car;
  late ElmSession elm;
  late DiagClient diag;

  setUp(() async {
    car = SimCar(stScale: 0.05, frameDelay: const Duration(milliseconds: 2));
    elm = ElmSession(car);
    diag = DiagClient(elm);
    await elm.init();
  });

  tearDown(() async {
    await elm.dispose();
    await car.close();
  });

  test('init configures BMW D-CAN raw mode', () {
    expect(car.received, containsAllInOrder(['ATZ', 'ATD', 'ATE0', 'ATSH6F1', 'ATCF600', 'ATCM700', 'ATPBC001', 'ATSPB']));
    expect(elm.version, contains('ELM327'));
  });

  test('single frame request/response', () async {
    expect(await diag.request(0x70, [0x3E]), [0x7E]);
    expect(car.received.last, '70013E0000000000');
  });

  test('multi-frame response uses flow control', () async {
    final r = await diag.requestPositive(0x70, [0x1A, 0x80]);
    expect(String.fromCharCodes(r.sublist(2)), 'SIM LM E60 LCI 0001');
    expect(car.received, contains('7030000000000000'));
  });

  test('multi-frame request', () async {
    // 30 10 07 + 2 bytes fits a single frame; force a long request via raw 1A with padding.
    final r = await diag.request(0x70, [0x1A, 0x80, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(r.first, 0x5A);
        final seq = car.received.map((c) => c.startsWith('70') ? c.substring(0, 4) : c).toList();
    expect(seq, containsAllInOrder(['7010', 'ATST01', '7021', 'ATSTFF', '7022', '7030']));
  });

  test('negative response and silence', () async {
    await expectLater(diag.requestPositive(0x70, [0x30, 0x55, 0x01]),
        throwsA(isA<NegativeResponse>().having((e) => e.code, 'code', 0x31)));
    await expectLater(diag.request(0x40, [0x3E], timeout: const Duration(milliseconds: 300)), throwsA(isA<NoResponse>()));
  });

  test('scanner discovers outputs read-only', () async {
    final found = await OutputScanner(DiagClientPort(diag), 0x70).discover(from: 0x0E, to: 0x22);
    expect(found.map((f) => f.lid), [0x10, 0x11, 0x12, 0x20]);
    expect(found.first.length, 2);
    expect(found.last.nrc, 0x12);
    expect(car.module.lit, isEmpty);
  });

  test('controller groups lamps per LID and releases everything', () async {
    final map = LampMap({
      Lamp.angelEyeL: const IoBinding(ecu: 0x70, lid: 0x10, onState: [0x80, 0x00]),
      Lamp.angelEyeR: const IoBinding(ecu: 0x70, lid: 0x10, onState: [0x40, 0x00]),
      Lamp.tailL: const IoBinding(ecu: 0x70, lid: 0x11, onState: [0x80, 0x00]),
    });
    final ctl = LightController(DiagClientPort(diag), map);
    await ctl.apply({Lamp.angelEyeL, Lamp.angelEyeR});
    expect(car.module.lit, {Lamp.angelEyeL, Lamp.angelEyeR});
    final sent = car.received.length;
    await ctl.apply({Lamp.angelEyeL, Lamp.angelEyeR});
    expect(car.received.length, sent, reason: 'unchanged state sends nothing');
    await ctl.apply({Lamp.tailL});
    expect(car.module.lit, {Lamp.tailL});
    await ctl.releaseAll();
    expect(car.module.lit, isEmpty);
    expect(car.module.outputs[0x10]!.override, isNull);
    expect(car.module.outputs[0x11]!.override, isNull);
  });

  test('player runs an effect and always releases', () async {
    final map = LampMap({
      for (final l in Lamps.front.toList().asMap().entries)
        l.value: IoBinding(ecu: 0x70, lid: 0x10, onState: [
          l.key < 8 ? 0x80 >> l.key : 0,
          l.key >= 8 ? 0x80 >> (l.key - 8) : 0,
        ]),
    });
    final ctl = LightController(DiagClientPort(diag), map);
    final seen = <Set<Lamp>>[];
    final player = EffectPlayer(_Sink(ctl), onFrame: (_, l) => seen.add(l));
    final wave = builtInEffects().firstWhere((e) => e.id == 'cascade')..loops = 1;
    await player.play(wave, speed: () => 20);
    expect(seen, hasLength(wave.frames.length));
    expect(car.module.lit, isEmpty);
  });

  test('json round trips', () {
    final map = LampMap({
      Lamp.fogFrontL: const IoBinding(ecu: 0x70, lid: 0x10, onState: [0x08, 0x00]),
      Lamp.plate: const RawBinding(ecu: 0x70, onRequest: [0x30, 0x40, 0x07, 0x01], offRequest: [0x30, 0x40, 0x00]),
    });
    final back = LampMap.decode(map.encode());
    expect(back.bindings[Lamp.fogFrontL].toString(), map.bindings[Lamp.fogFrontL].toString());
    expect(back.bindings[Lamp.plate], isA<RawBinding>());
    final effects = builtInEffects();
    final decoded = Effect.decodeList(Effect.encodeList(effects));
    expect(decoded.map((e) => e.frames.length), effects.map((e) => e.frames.length));
    expect(toHex(parseHex('30 1a,07')), '30 1A 07');
  });
}

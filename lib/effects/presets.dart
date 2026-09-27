import '../model/effect.dart';
import '../model/lamp.dart';

EffectFrame _f(int ms, Iterable<Lamp> lamps) => EffectFrame(lamps.toSet(), ms);

const _show = EffectCategory.show;
const _classic = EffectCategory.classic;

// Lamp "rings" from the middle of the car outwards, used by several effects.
const _eyes = [Lamp.angelEyeL, Lamp.angelEyeR];
const _low = [Lamp.lowBeamL, Lamp.lowBeamR];
const _high = [Lamp.highBeamL, Lamp.highBeamR];
const _fog = [Lamp.fogFrontL, Lamp.fogFrontR];
const _turnF = [Lamp.turnFrontL, Lamp.turnFrontR];
const _side = [Lamp.turnSideL, Lamp.turnSideR];
const _tail = [Lamp.tailL, Lamp.tailR];
const _brake = [Lamp.brakeL, Lamp.brakeR, Lamp.brakeCenter];
const _turnR = [Lamp.turnRearL, Lamp.turnRearR];
const _rev = [Lamp.reverseL, Lamp.reverseR];

const _rearRow = [Lamp.turnRearL, Lamp.tailL, Lamp.brakeL, Lamp.brakeCenter, Lamp.brakeR, Lamp.tailR, Lamp.turnRearR];

/// Built-in effects. Timings assume ~100 ms per diagnostic command,
/// so very short frames only make sense for effects that touch few outputs.
List<Effect> builtInEffects() => [
      Effect(id: 'bounce', name: 'Bounce', category: _show, builtIn: true, loops: 0, frames: [
        _f(300, [..._eyes, ..._low, ..._fog]),
        _f(120, []),
        _f(300, [..._tail, ..._brake]),
        _f(120, []),
      ]),
      Effect(id: 'center_burst', name: 'Center Burst', category: _show, builtIn: true, loops: 0, frames: [
        _f(200, [Lamp.brakeCenter, ..._fog]),
        _f(200, [..._low, ..._brake]),
        _f(200, [..._eyes, ..._high, ..._tail]),
        _f(250, [..._turnF, ..._side, ..._turnR]),
        _f(350, []),
      ]),
      Effect(id: 'front_to_back', name: 'Front to Back', category: _show, builtIn: true, loops: 0, frames: [
        _f(250, [..._eyes, ..._low, ..._high, ..._fog]),
        _f(250, [..._turnF, ..._side]),
        _f(250, [..._tail, ..._brake, ..._turnR]),
        _f(250, [..._rev, Lamp.plate, Lamp.fogRear]),
        _f(300, []),
      ]),
      Effect(id: 'cascade', name: 'Cascade Wave', category: _show, builtIn: true, loops: 0, frames: [
        _f(180, [..._fog]),
        _f(180, [..._fog, ..._low]),
        _f(180, [..._low, ..._eyes]),
        _f(180, [..._eyes, ..._high]),
        _f(180, [..._high, ..._turnF]),
        _f(180, [..._turnF, ..._side]),
        _f(180, [..._side, ..._tail]),
        _f(180, [..._tail, ..._brake]),
        _f(180, [..._brake, ..._turnR]),
        _f(250, [..._turnR]),
        _f(300, []),
      ]),
      Effect(id: 'build_up', name: 'Build Up', category: _show, builtIn: true, frames: [
        _f(400, [..._eyes]),
        _f(400, [..._eyes, ..._tail]),
        _f(400, [..._eyes, ..._tail, ..._low]),
        _f(400, [..._eyes, ..._tail, ..._low, ..._fog]),
        _f(400, [..._eyes, ..._tail, ..._low, ..._fog, ..._brake]),
        _f(400, [..._eyes, ..._tail, ..._low, ..._fog, ..._brake, ..._turnF, ..._side, ..._turnR]),
        for (var i = 0; i < 3; i++) ...[
          _f(150, Lamps.all),
          _f(150, []),
        ],
        _f(1200, Lamps.all),
      ]),
      Effect(id: 'welcome', name: 'Приветствие', category: _classic, builtIn: true, frames: [
        _f(400, _eyes),
        _f(400, [..._eyes, ..._tail, Lamp.plate]),
        _f(500, [..._eyes, ..._tail, Lamp.plate, ..._low]),
        _f(500, [..._eyes, ..._tail, Lamp.plate, ..._low, ..._fog]),
        _f(250, [..._eyes, ..._tail, Lamp.plate, ..._low, ..._fog, ..._high]),
        _f(250, [..._eyes, ..._tail, Lamp.plate, ..._low, ..._fog]),
        _f(250, [..._eyes, ..._tail, Lamp.plate, ..._low, ..._fog, ..._high]),
        _f(1500, [..._eyes, ..._tail, Lamp.plate, ..._low, ..._fog]),
      ]),
      Effect(id: 'goodbye', name: 'Прощание', category: _classic, builtIn: true, frames: [
        _f(600, [..._eyes, ..._tail, ..._low, ..._fog]),
        _f(500, [..._eyes, ..._tail, ..._low]),
        _f(500, [..._eyes, ..._tail]),
        _f(250, Lamps.turns),
        _f(250, []),
        _f(250, Lamps.turns),
        _f(700, _eyes),
        _f(300, []),
      ]),
      Effect(id: 'police', name: 'Полиция', category: _show, builtIn: true, loops: 0, frames: [
        _f(120, [Lamp.turnFrontL, Lamp.fogFrontL, Lamp.turnRearL]),
        _f(80, []),
        _f(120, [Lamp.turnFrontL, Lamp.fogFrontL, Lamp.turnRearL]),
        _f(150, []),
        _f(120, [Lamp.turnFrontR, Lamp.fogFrontR, Lamp.turnRearR]),
        _f(80, []),
        _f(120, [Lamp.turnFrontR, Lamp.fogFrontR, Lamp.turnRearR]),
        _f(150, []),
      ]),
      Effect(id: 'knight', name: 'Knight Rider', category: _show, builtIn: true, loops: 0, frames: [
        for (final l in _rearRow) _f(150, [l]),
        for (final l in _rearRow.reversed.skip(1).take(_rearRow.length - 2)) _f(150, [l]),
      ]),
      Effect(id: 'sequential', name: 'Бегущие поворотники', category: _classic, builtIn: true, loops: 0, frames: [
        _f(200, _turnF),
        _f(200, [..._turnF, ..._side]),
        _f(300, Lamps.turns),
        _f(400, []),
      ]),
      Effect(id: 'strobe', name: 'Стробоскоп', category: _show, builtIn: true, loops: 0, frames: [
        _f(120, [..._fog, ..._high]),
        _f(120, []),
      ]),
      Effect(id: 'heartbeat', name: 'Пульс стопов', category: _classic, builtIn: true, loops: 0, frames: [
        _f(150, _brake),
        _f(120, []),
        _f(150, _brake),
        _f(700, []),
      ]),
      Effect(id: 'pingpong', name: 'Лево-право', category: _classic, builtIn: true, loops: 0, frames: [
        _f(350, Lamps.left),
        _f(350, Lamps.right),
      ]),
    ];

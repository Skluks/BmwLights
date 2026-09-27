import 'dart:ui';

enum LampColor { white, amber, red }

/// Lamps of an E60/E61 LCI, with their place on the top-down car drawing.
/// [pos] is in a 0..1 box: x left→right, y front(0)→rear(1).
enum Lamp {
  angelEyeL('Ангельские глазки Л', LampColor.white, Offset(0.20, 0.05)),
  angelEyeR('Ангельские глазки П', LampColor.white, Offset(0.80, 0.05)),
  lowBeamL('Ближний Л', LampColor.white, Offset(0.27, 0.035)),
  lowBeamR('Ближний П', LampColor.white, Offset(0.73, 0.035)),
  highBeamL('Дальний Л', LampColor.white, Offset(0.13, 0.04)),
  highBeamR('Дальний П', LampColor.white, Offset(0.87, 0.04)),
  fogFrontL('ПТФ Л', LampColor.white, Offset(0.22, 0.015)),
  fogFrontR('ПТФ П', LampColor.white, Offset(0.78, 0.015)),
  turnFrontL('Поворотник перед Л', LampColor.amber, Offset(0.07, 0.07)),
  turnFrontR('Поворотник перед П', LampColor.amber, Offset(0.93, 0.07)),
  turnSideL('Повторитель Л', LampColor.amber, Offset(0.02, 0.22)),
  turnSideR('Повторитель П', LampColor.amber, Offset(0.98, 0.22)),
  tailL('Габарит зад Л', LampColor.red, Offset(0.14, 0.96)),
  tailR('Габарит зад П', LampColor.red, Offset(0.86, 0.96)),
  brakeL('Стоп Л', LampColor.red, Offset(0.24, 0.965)),
  brakeR('Стоп П', LampColor.red, Offset(0.76, 0.965)),
  brakeCenter('Третий стоп', LampColor.red, Offset(0.50, 0.90)),
  turnRearL('Поворотник зад Л', LampColor.amber, Offset(0.07, 0.94)),
  turnRearR('Поворотник зад П', LampColor.amber, Offset(0.93, 0.94)),
  reverseL('Задний ход Л', LampColor.white, Offset(0.33, 0.985)),
  reverseR('Задний ход П', LampColor.white, Offset(0.67, 0.985)),
  fogRear('Задний туман', LampColor.red, Offset(0.40, 0.985)),
  plate('Подсветка номера', LampColor.white, Offset(0.50, 0.995));

  const Lamp(this.title, this.color, this.pos);
  final String title;
  final LampColor color;
  final Offset pos;

  static Lamp? byName(String name) {
    for (final l in values) {
      if (l.name == name) return l;
    }
    return null;
  }
}

/// Handy groups for effects and the editor.
abstract final class Lamps {
  static const front = {
    Lamp.angelEyeL, Lamp.angelEyeR, Lamp.lowBeamL, Lamp.lowBeamR, Lamp.highBeamL, Lamp.highBeamR, //
    Lamp.fogFrontL, Lamp.fogFrontR, Lamp.turnFrontL, Lamp.turnFrontR,
  };
  static const rear = {
    Lamp.tailL, Lamp.tailR, Lamp.brakeL, Lamp.brakeR, Lamp.brakeCenter, Lamp.turnRearL, Lamp.turnRearR, //
    Lamp.reverseL, Lamp.reverseR, Lamp.fogRear, Lamp.plate,
  };
  static const left = {
    Lamp.angelEyeL, Lamp.lowBeamL, Lamp.highBeamL, Lamp.fogFrontL, Lamp.turnFrontL, Lamp.turnSideL, //
    Lamp.tailL, Lamp.brakeL, Lamp.turnRearL, Lamp.reverseL,
  };
  static const right = {
    Lamp.angelEyeR, Lamp.lowBeamR, Lamp.highBeamR, Lamp.fogFrontR, Lamp.turnFrontR, Lamp.turnSideR, //
    Lamp.tailR, Lamp.brakeR, Lamp.turnRearR, Lamp.reverseR,
  };
  static const turns = {
    Lamp.turnFrontL, Lamp.turnFrontR, Lamp.turnSideL, Lamp.turnSideR, Lamp.turnRearL, Lamp.turnRearR,
  };
  static const all = {...front, ...rear, Lamp.turnSideL, Lamp.turnSideR};
}

import 'package:bmw_lights/app/app_controller.dart';
import 'package:bmw_lights/main.dart';
import 'package:bmw_lights/model/lamp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('demo: connect, open party mode, play an effect on the simulated car', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final app = AppController();
    await tester.runAsync(app.load);
    await tester.pumpWidget(BmwLightsApp(app: app));

    expect(find.text('Демо без машины'), findsOneWidget);
    // Real timers drive the simulated adapter, so connect outside the fake test clock.
    await tester.runAsync(app.connectDemo);
    expect(app.connected, isTrue, reason: '${app.error}');
    await tester.tap(find.text('Эффекты'));
    await tester.pumpAndSettle();
    expect(find.text('Party Mode'), findsOneWidget);
    expect(find.text('Bounce'), findsOneWidget);
    expect(find.text('Cascade Wave'), findsOneWidget);

    // Play "Bounce" through the whole stack: UI -> controller -> ELM -> simulated light module.
    await tester.runAsync(() async {
      final bounce = app.effects.firstWhere((e) => e.id == 'bounce');
      final done = app.play(bounce);
      var sawFront = false;
      for (var i = 0; i < 100 && !sawFront; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        sawFront = app.simLit.contains(Lamp.lowBeamL);
      }
      expect(sawFront, isTrue, reason: 'simulated car lit the low beam');
      await app.stop();
      await done;
      expect(app.simLit, isEmpty, reason: 'outputs returned to the car');
      await app.disconnect();
    });
    await tester.pump();
  });
}

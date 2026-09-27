import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import 'connect_screen.dart';
import 'effects_screen.dart';
import 'lamps_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.app});
  final AppController app;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never leave the car's lights under our control when the app goes away.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      widget.app.stop();
      widget.app.releaseAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final pages = [
          EffectsScreen(app: app),
          LampsScreen(app: app),
          ConnectScreen(app: app, onConnected: () => setState(() => _tab = 0)),
        ];
        return Scaffold(
          body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Эффекты'),
              const NavigationDestination(icon: Icon(Icons.lightbulb_outline), label: 'Лампы'),
              NavigationDestination(
                icon: Icon(
                  app.connected ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: app.connected ? Colors.greenAccent : null,
                ),
                label: 'Подключение',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Asks once for the "car is parked" confirmation before touching the lights.
Future<bool> confirmSafety(BuildContext context, AppController app) async {
  if (app.safetyAccepted || app.isDemo) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.warning_amber, size: 40),
      title: const Text('Только на стоянке'),
      content: const Text(
        'Приложение управляет светом через диагностику.\n\n'
        '• Машина должна стоять, на ручнике/в P.\n'
        '• Мигание фарами и ПТФ в движении запрещено и опасно.\n'
        '• Включено только зажигание — следите за аккумулятором.\n'
        '• При выходе из приложения свет возвращается под управление машины.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Понятно, машина стоит')),
      ],
    ),
  );
  if (ok == true) await app.acceptSafety();
  return ok == true;
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

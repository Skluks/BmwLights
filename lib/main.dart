import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'ui/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppController();
  app.load();
  runApp(BmwLightsApp(app: app));
}

class BmwLightsApp extends StatelessWidget {
  const BmwLightsApp({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BMW Lights',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1C69D4), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: HomeShell(app: app),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../core/hex.dart';

/// Raw diagnostic requests plus the adapter log.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, required this.app});
  final AppController app;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final _ecu = TextEditingController(text: hexByte(widget.app.ecu));
  final _req = TextEditingController(text: '3E');
  bool _busy = false;

  Future<void> _send() async {
    final ecu = tryParseHex(_ecu.text);
    final req = tryParseHex(_req.text);
    if (ecu == null || ecu.length != 1 || req == null || req.isEmpty) return;
    setState(() => _busy = true);
    final r = await widget.app.sendRaw(ecu.first, req);
    widget.app.addLog('= $r');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Терминал'),
        actions: [
          IconButton(
            tooltip: 'Копировать лог',
            onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: app.log.join('\n')))),
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: 'Очистить',
            onPressed: () => setState(app.log.clear),
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SizedBox(
              width: 64,
              child: TextField(controller: _ecu, decoration: const InputDecoration(labelText: 'Блок')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _req,
                decoration: const InputDecoration(labelText: 'Запрос (hex)', hintText: '30 10 01'),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton.filled(
              onPressed: app.connected && !_busy ? _send : null,
              icon: const Icon(Icons.send),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListenableBuilder(
            listenable: app,
            builder: (context, _) => ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: app.log.length,
              itemBuilder: (context, i) => Text(
                app.log[app.log.length - 1 - i],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

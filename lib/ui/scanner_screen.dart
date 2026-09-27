import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/hex.dart';
import '../engine/scanner.dart';
import '../model/lamp.dart';
import '../model/lamp_map.dart';
import 'home.dart';

/// Step 1: read-only discovery of IO outputs. Step 2: switch outputs one pattern
/// at a time and let the user say which lamp lit up.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.app});
  final AppController app;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  OutputScanner? _scanner;
  List<FoundOutput> _found = [];
  bool _discovering = false;
  bool _cancel = false;
  int _progress = 0;
  String? _error;

  FoundOutput? _out;
  int _pattern = 0;
  bool _forced = false;
  bool _busy = false;

  AppController get app => widget.app;

  @override
  void initState() {
    super.initState();
    final port = app.port;
    if (port != null) _scanner = OutputScanner(port, app.ecu);
  }

  @override
  void dispose() {
    _cancel = true;
    final out = _out;
    if (_forced && out != null) _scanner?.release(out.lid);
    super.dispose();
  }

  Future<void> _discover() async {
    final s = _scanner;
    if (s == null) return;
    await app.stop();
    setState(() {
      _discovering = true;
      _cancel = false;
      _error = null;
      _found = [];
    });
    try {
      final found = await s.discover(
        cancelled: () => _cancel,
        onProgress: (lid, f) {
          if (mounted) setState(() => _progress = lid);
        },
      );
      if (mounted) setState(() => _found = found);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _discovering = false);
  }

  List<List<int>> get _patterns => OutputScanner.patterns(_out!.length);

  String _patternName(int i) {
    final p = _patterns[i];
    if (i == 0) return 'Все биты (${toHex(p)})';
    final bit = i - 1;
    return 'Байт ${bit ~/ 8 + 1}, бит ${7 - bit % 8}  (${toHex(p)})';
  }

  Future<void> _select(FoundOutput o) async {
    if (_forced && _out != null) await _scanner!.release(_out!.lid);
    setState(() {
      _out = o;
      _pattern = 0;
      _forced = false;
    });
  }

  Future<void> _force() async {
    if (!await confirmSafety(context, app)) return;
    setState(() => _busy = true);
    final err = await _scanner!.force(_out!.lid, _patterns[_pattern]);
    setState(() {
      _busy = false;
      _forced = err == null;
    });
    if (err != null && mounted) showSnack(context, err);
  }

  Future<void> _next({required bool advance}) async {
    setState(() => _busy = true);
    await _scanner!.release(_out!.lid);
    setState(() {
      _busy = false;
      _forced = false;
      if (advance && _pattern < _patterns.length - 1) _pattern++;
    });
  }

  Future<void> _assign() async {
    final lamps = await showDialog<Set<Lamp>>(context: context, builder: (_) => const _LampPicker());
    if (lamps == null || lamps.isEmpty) return;
    for (final l in lamps) {
      await app.setBinding(l, IoBinding(ecu: app.ecu, lid: _out!.lid, onState: _patterns[_pattern]));
    }
    if (mounted) showSnack(context, 'Сохранено: ${lamps.map((l) => l.title).join(', ')}');
    // "All bits" lit several lamps? Keep going bit by bit to separate them.
    await _next(advance: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Сканер выходов')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Модуль ${hexByte(app.ecu)}', style: t.titleMedium),
          const Text(
            '1. «Найти выходы» только читает состояние — ничего не включает.\n'
            '2. Выберите выход и нажимайте «Включить»: посмотрите на машину и отметьте, что загорелось. '
            'После каждой проверки выход возвращается машине.',
          ),
          const SizedBox(height: 12),
          if (_discovering) ...[
            LinearProgressIndicator(value: _progress / 255),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('LID ${hexByte(_progress)} из FF · найдено ${_found.length}')),
              TextButton(onPressed: () => _cancel = true, child: const Text('Стоп')),
            ]),
          ] else
            FilledButton.icon(onPressed: _discover, icon: const Icon(Icons.radar), label: const Text('Найти выходы')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (!_discovering && _found.isEmpty && _error == null && _progress > 0)
            const Text('Выходы не найдены. Проверьте адрес модуля или задайте диагностическую сессию.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in _found)
              ChoiceChip(
                label: Text(o.summary),
                selected: _out?.lid == o.lid,
                onSelected: (_) => _select(o),
              ),
          ]),
          if (_out != null) ...[
            const Divider(height: 32),
            Text('Выход LID ${hexByte(_out!.lid)}', style: t.titleMedium),
            Text('Проверка ${_pattern + 1} из ${_patterns.length}: ${_patternName(_pattern)}'),
            const SizedBox(height: 8),
            Row(children: [
              IconButton(
                onPressed: _busy || _forced || _pattern == 0 ? null : () => setState(() => _pattern--),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: _busy || _forced || _pattern >= _patterns.length - 1 ? null : () => setState(() => _pattern++),
                icon: const Icon(Icons.chevron_right),
              ),
              const SizedBox(width: 8),
              if (!_forced)
                FilledButton.icon(
                  onPressed: _busy ? null : _force,
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Включить'),
                ),
            ]),
            if (_forced) ...[
              const Card(
                child: ListTile(
                  leading: Icon(Icons.visibility),
                  title: Text('Выход включён — что загорелось на машине?'),
                ),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _assign,
                  icon: const Icon(Icons.lightbulb),
                  label: const Text('Загорелось…'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _next(advance: true),
                  child: const Text('Ничего, дальше'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _next(advance: false),
                  child: const Text('Выключить'),
                ),
              ]),
            ],
          ],
        ],
      ),
    );
  }
}

class _LampPicker extends StatefulWidget {
  const _LampPicker();

  @override
  State<_LampPicker> createState() => _LampPickerState();
}

class _LampPickerState extends State<_LampPicker> {
  final Set<Lamp> _sel = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Что загорелось?'),
      content: SingleChildScrollView(
        child: Wrap(spacing: 6, runSpacing: 2, children: [
          for (final l in Lamp.values)
            FilterChip(
              label: Text(l.title),
              selected: _sel.contains(l),
              onSelected: (v) => setState(() => v ? _sel.add(l) : _sel.remove(l)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, _sel), child: const Text('Сохранить')),
      ],
    );
  }
}

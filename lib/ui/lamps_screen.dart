import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../core/hex.dart';
import '../model/lamp.dart';
import '../model/lamp_map.dart';
import 'car_view.dart';
import 'home.dart';
import 'scanner_screen.dart';

class LampsScreen extends StatefulWidget {
  const LampsScreen({super.key, required this.app});
  final AppController app;

  @override
  State<LampsScreen> createState() => _LampsScreenState();
}

class _LampsScreenState extends State<LampsScreen> {
  final Set<Lamp> _testing = {};

  AppController get app => widget.app;

  Future<void> _toggleTest(Lamp l) async {
    if (!app.connected) {
      showSnack(context, 'Сначала подключитесь');
      return;
    }
    if (!await confirmSafety(context, app)) return;
    await app.stop();
    setState(() => _testing.contains(l) ? _testing.remove(l) : _testing.add(l));
    final err = await app.testLamps({..._testing});
    if (err != null && mounted) showSnack(context, err);
  }

  Future<void> _releaseAll() async {
    setState(_testing.clear);
    await app.releaseAll();
    if (mounted) showSnack(context, 'Свет возвращён машине');
  }

  Future<void> _edit(Lamp lamp) async {
    final b = app.lampMap.bindings[lamp];
    final result = await showDialog<(bool, LampBinding?)>(
      context: context,
      builder: (_) => _BindingDialog(lamp: lamp, binding: b, defaultEcu: app.ecu),
    );
    if (result == null) return;
    await app.setBinding(lamp, result.$2);
  }

  Future<void> _export() async {
    await Clipboard.setData(ClipboardData(text: app.lampMap.encode()));
    if (mounted) showSnack(context, 'Карта ламп скопирована в буфер обмена');
  }

  Future<void> _import() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    try {
      final map = LampMap.decode(data?.text ?? '');
      await app.replaceMap(map);
      if (mounted) showSnack(context, 'Загружено ламп: ${map.bindings.length}');
    } catch (e) {
      if (mounted) showSnack(context, 'В буфере нет карты ламп');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final map = app.lampMap;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: Text('Лампы', style: t.headlineSmall)),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'export' ? _export() : _import(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Скопировать карту')),
              PopupMenuItem(value: 'import', child: Text('Вставить карту из буфера')),
            ],
          ),
        ]),
        Text(
          'Настроено ${map.bindings.length} из ${Lamp.values.length}. '
          'Найдите выходы сканером и отметьте, какая лампа загорается. Нажатие на лампу — вкл/выкл для проверки.',
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: app.connected
                ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen(app: app)))
                : null,
            icon: const Icon(Icons.radar),
            label: const Text('Сканер выходов'),
          ),
          OutlinedButton.icon(
            onPressed: app.connected ? _releaseAll : null,
            icon: const Icon(Icons.power_settings_new),
            label: const Text('Вернуть свет машине'),
          ),
        ]),
        const SizedBox(height: 8),
        CarView(
          lit: app.isDemo ? app.simLit : _testing,
          available: map.bindings.keys.toSet(),
          height: 220,
          onTapLamp: (l) => map.bindings.containsKey(l) ? _toggleTest(l) : _edit(l),
        ),
        for (final l in Lamp.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _testing.contains(l) ? Icons.lightbulb : Icons.lightbulb_outline,
              color: map.bindings.containsKey(l) ? lampColor(l.color) : Theme.of(context).disabledColor,
            ),
            title: Text(l.title),
            subtitle: Text(map.bindings[l]?.toString() ?? 'не настроено'),
            trailing: map.bindings.containsKey(l)
                ? Switch(value: _testing.contains(l), onChanged: (_) => _toggleTest(l))
                : null,
            onTap: () => _edit(l),
          ),
      ],
    );
  }
}

class _BindingDialog extends StatefulWidget {
  const _BindingDialog({required this.lamp, required this.binding, required this.defaultEcu});
  final Lamp lamp;
  final LampBinding? binding;
  final int defaultEcu;

  @override
  State<_BindingDialog> createState() => _BindingDialogState();
}

class _BindingDialogState extends State<_BindingDialog> {
  late bool _raw = widget.binding is RawBinding;
  late final _ecu = TextEditingController(
      text: hexByte(switch (widget.binding) {
    IoBinding b => b.ecu,
    RawBinding b => b.ecu,
    null => widget.defaultEcu,
  }));
  late final _lid = TextEditingController(text: widget.binding is IoBinding ? hexByte((widget.binding as IoBinding).lid) : '');
  late final _state =
      TextEditingController(text: widget.binding is IoBinding ? toHex((widget.binding as IoBinding).onState) : '');
  late final _on =
      TextEditingController(text: widget.binding is RawBinding ? toHex((widget.binding as RawBinding).onRequest) : '');
  late final _off =
      TextEditingController(text: widget.binding is RawBinding ? toHex((widget.binding as RawBinding).offRequest) : '');
  String? _err;

  void _save() {
    final ecu = tryParseHex(_ecu.text);
    if (ecu == null || ecu.length != 1) return setState(() => _err = 'Адрес блока: один байт, например 70');
    if (_raw) {
      final on = tryParseHex(_on.text), off = tryParseHex(_off.text);
      if (on == null || off == null || on.isEmpty || off.isEmpty) return setState(() => _err = 'Нужны оба запроса в hex');
      Navigator.pop(context, (true, RawBinding(ecu: ecu.first, onRequest: on, offRequest: off)));
    } else {
      final lid = tryParseHex(_lid.text), st = tryParseHex(_state.text);
      if (lid == null || lid.length != 1) return setState(() => _err = 'LID: один байт');
      if (st == null || st.isEmpty) return setState(() => _err = 'Состояние «вкл»: hex байты');
      Navigator.pop(context, (true, IoBinding(ecu: ecu.first, lid: lid.first, onState: st)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.lamp.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Выход (30)')),
              ButtonSegment(value: true, label: Text('Свои запросы')),
            ],
            selected: {_raw},
            onSelectionChanged: (s) => setState(() => _raw = s.first),
          ),
          TextField(controller: _ecu, decoration: const InputDecoration(labelText: 'Адрес блока (hex)')),
          if (!_raw) ...[
            TextField(controller: _lid, decoration: const InputDecoration(labelText: 'LID выхода (hex)')),
            TextField(
              controller: _state,
              decoration: const InputDecoration(labelText: 'Состояние «вкл» (hex)', hintText: 'например 80 00'),
            ),
          ] else ...[
            TextField(
              controller: _on,
              decoration: const InputDecoration(labelText: 'Запрос «вкл» (hex)', hintText: '30 xx 07 ..'),
            ),
            TextField(
              controller: _off,
              decoration: const InputDecoration(labelText: 'Запрос «выкл» (hex)', hintText: '30 xx 00'),
            ),
          ],
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        if (widget.binding != null)
          TextButton(onPressed: () => Navigator.pop(context, (true, null)), child: const Text('Сбросить')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}

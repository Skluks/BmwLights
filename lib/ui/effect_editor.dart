import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../model/effect.dart';
import '../model/lamp.dart';
import 'car_view.dart';

/// Edits a copy of an effect; pops with the edited effect on save.
class EffectEditor extends StatefulWidget {
  const EffectEditor({super.key, required this.app, required this.effect});
  final AppController app;
  final Effect effect;

  @override
  State<EffectEditor> createState() => _EffectEditorState();
}

class _EffectEditorState extends State<EffectEditor> {
  late final Effect _e = widget.effect.copyAs(id: widget.effect.id);
  late final _name = TextEditingController(text: _e.name);
  int _sel = 0;

  EffectFrame get _frame => _e.frames[_sel];

  @override
  void dispose() {
    widget.app.stop();
    _name.dispose();
    super.dispose();
  }

  void _toggle(Lamp l) => setState(() => _frame.lamps.contains(l) ? _frame.lamps.remove(l) : _frame.lamps.add(l));

  void _setGroup(Set<Lamp> group, bool on) => setState(() => on ? _frame.lamps.addAll(group) : _frame.lamps.removeAll(group));

  void _addFrame({bool copy = true}) => setState(() {
        _e.frames.insert(_sel + 1, copy ? _frame.copy() : EffectFrame({}, 300));
        _sel++;
      });

  void _deleteFrame() {
    if (_e.frames.length == 1) return;
    setState(() {
      _e.frames.removeAt(_sel);
      if (_sel >= _e.frames.length) _sel = _e.frames.length - 1;
    });
  }

  void _move(int d) {
    final to = _sel + d;
    if (to < 0 || to >= _e.frames.length) return;
    setState(() {
      final f = _e.frames.removeAt(_sel);
      _e.frames.insert(to, f);
      _sel = to;
    });
  }

  Future<void> _preview() async {
    final app = widget.app;
    if (app.playing != null) {
      await app.stop();
    } else {
      _e.name = _name.text;
      await app.play(_e.copyAs(id: '__preview'), previewOnly: !app.connected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final previewing = app.playing != null;
        final lit = previewing ? (app.isDemo ? app.simLit : app.preview) : _frame.lamps;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Редактор'),
            actions: [
              IconButton(
                tooltip: previewing ? 'Стоп' : 'Проиграть',
                onPressed: _preview,
                icon: Icon(previewing ? Icons.stop : Icons.play_arrow),
              ),
              IconButton(
                tooltip: 'Сохранить',
                onPressed: () {
                  _e.name = _name.text.trim().isEmpty ? 'Без названия' : _name.text.trim();
                  Navigator.pop(context, _e);
                },
                icon: const Icon(Icons.check),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Название')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Повторять по кругу'),
                value: _e.loops == 0,
                onChanged: (v) => setState(() => _e.loops = v ? 0 : 1),
              ),
              Text(previewing ? 'Предпросмотр…' : 'Кадр ${_sel + 1} — нажимайте на лампы', style: t.labelLarge),
              CarView(lit: lit, height: 260, onTapLamp: previewing ? null : _toggle),
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _e.frames.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    if (i == _e.frames.length) {
                      return ActionChip(avatar: const Icon(Icons.add), label: const Text('Кадр'), onPressed: () {
                        _sel = _e.frames.length - 1;
                        _addFrame(copy: false);
                      });
                    }
                    final f = _e.frames[i];
                    return ChoiceChip(
                      selected: i == _sel,
                      label: Text('${i + 1} · ${f.durationMs} мс'),
                      avatar: f.lamps.isEmpty ? const Icon(Icons.dark_mode, size: 16) : null,
                      onSelected: (_) => setState(() => _sel = i),
                    );
                  },
                ),
              ),
              Row(children: [
                IconButton(tooltip: 'Влево', onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
                IconButton(tooltip: 'Вправо', onPressed: () => _move(1), icon: const Icon(Icons.chevron_right)),
                IconButton(tooltip: 'Дублировать', onPressed: _addFrame, icon: const Icon(Icons.copy)),
                IconButton(tooltip: 'Удалить кадр', onPressed: _deleteFrame, icon: const Icon(Icons.delete_outline)),
                const Spacer(),
                Text('${(_e.cycleMs / 1000).toStringAsFixed(1)} с'),
              ]),
              Row(children: [
                const Text('Длительность'),
                Expanded(
                  child: Slider(
                    value: _frame.durationMs.toDouble().clamp(50, 3000),
                    min: 50,
                    max: 3000,
                    divisions: 59,
                    label: '${_frame.durationMs} мс',
                    onChanged: (v) => setState(() => _frame.durationMs = v.round()),
                  ),
                ),
                SizedBox(width: 64, child: Text('${_frame.durationMs} мс')),
              ]),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final (name, group) in [
                  ('Весь перед', Lamps.front),
                  ('Весь зад', Lamps.rear),
                  ('Левая сторона', Lamps.left),
                  ('Правая сторона', Lamps.right),
                  ('Поворотники', Lamps.turns),
                ])
                  FilterChip(
                    label: Text(name),
                    selected: _frame.lamps.containsAll(group),
                    onSelected: (v) => _setGroup(group, v),
                  ),
                ActionChip(label: const Text('Всё выкл'), onPressed: () => setState(_frame.lamps.clear)),
              ]),
              const Divider(height: 24),
              Wrap(spacing: 6, runSpacing: 2, children: [
                for (final l in Lamp.values)
                  FilterChip(
                    label: Text(l.title),
                    selected: _frame.lamps.contains(l),
                    selectedColor: lampColor(l.color).withValues(alpha: 0.35),
                    onSelected: (_) => _toggle(l),
                  ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

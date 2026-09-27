import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../model/effect.dart';
import '../model/lamp.dart';
import 'car_view.dart';
import 'effect_editor.dart';
import 'home.dart';

const _tileColors = [
  Color(0xFF3FA9F5), // light blue
  Color(0xFFF57C00), // orange
  Color(0xFF1565E8), // blue
  Color(0xFF1E6FF0),
  Color(0xFF1558D6),
  Color(0xFFF2A516), // yellow
  Color(0xFF5AB0F7),
  Color(0xFFE8A317),
];

const _icons = <String, IconData>{
  'bounce': Icons.swap_vert,
  'center_burst': Icons.flare,
  'front_to_back': Icons.south,
  'cascade': Icons.waves,
  'build_up': Icons.trending_up,
  'police': Icons.local_police,
  'knight': Icons.linear_scale,
  'strobe': Icons.flash_on,
  'welcome': Icons.waving_hand,
  'goodbye': Icons.nightlight_round,
  'sequential': Icons.double_arrow,
  'heartbeat': Icons.favorite,
  'pingpong': Icons.compare_arrows,
};

class EffectsScreen extends StatelessWidget {
  const EffectsScreen({super.key, required this.app});
  final AppController app;

  Future<void> _play(BuildContext context, Effect e) async {
    if (app.playing?.id == e.id) {
      await app.stop();
      return;
    }
    if (app.connected && !await confirmSafety(context, app)) return;
    if (app.connected && app.lampMap.isEmpty && context.mounted) {
      showSnack(context, 'Лампы не настроены — эффект только на экране. Откройте вкладку «Лампы».');
    }
    await app.play(e);
    if (app.error != null && context.mounted) showSnack(context, app.error!);
  }

  Future<void> _edit(BuildContext context, Effect e) async {
    final result = await Navigator.push<Effect>(
      context,
      MaterialPageRoute(builder: (_) => EffectEditor(app: app, effect: e)),
    );
    if (result != null) await app.saveEffect(result);
  }

  Future<void> _menu(BuildContext context, Effect e) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(e.name, style: Theme.of(context).textTheme.titleMedium)),
          ListTile(
            leading: const Icon(Icons.visibility),
            title: const Text('Показать только на экране'),
            onTap: () => Navigator.pop(context, 'preview'),
          ),
          if (!e.builtIn)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Изменить'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Копировать и изменить'),
            onTap: () => Navigator.pop(context, 'copy'),
          ),
          if (!e.builtIn)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (v) {
      case 'preview':
        await app.play(e, previewOnly: true);
      case 'edit':
        await _edit(context, e);
      case 'copy':
        await _edit(context, e.copyAs(id: app.newEffectId(), name: '${e.name} (копия)'));
      case 'delete':
        await app.deleteEffect(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final shownLamps = app.isDemo ? app.simLit : app.preview;
    final available = app.connected ? app.lampMap.bindings.keys.toSet() : null;
    final sections = [
      for (final c in EffectCategory.values)
        (c, app.effects.where((e) => (e.builtIn ? e.category : EffectCategory.custom) == c).toList()),
    ];
    var colorIndex = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Party Mode'),
        actions: [
          IconButton(
            tooltip: 'Стоп',
            onPressed: app.playing == null ? null : app.stop,
            icon: Icon(Icons.stop_rounded, color: app.playing == null ? null : Colors.pinkAccent),
          ),
          IconButton(
            tooltip: 'Повтор',
            onPressed: app.toggleRepeat,
            icon: Icon(Icons.repeat_rounded, color: app.repeat ? Colors.redAccent : null),
          ),
          IconButton(
            tooltip: 'Новый эффект',
            onPressed: () => _edit(
              context,
              Effect(id: app.newEffectId(), name: 'Мой эффект', frames: [EffectFrame({Lamp.angelEyeL, Lamp.angelEyeR}, 300)]),
            ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              if (!app.connected)
                const _Banner(icon: Icons.visibility, text: 'Нет подключения — эффекты только на экране'),
              if (app.isDemo) const _Banner(icon: Icons.science, text: 'Демо: симулятор модуля света'),
              CarView(lit: shownLamps, available: available, height: 200),
              Row(children: [
                const Icon(Icons.speed, size: 20),
                Expanded(
                  child: Slider(
                    value: app.speed,
                    min: 0.25,
                    max: 3,
                    divisions: 11,
                    label: '×${app.speed.toStringAsFixed(2)}',
                    onChanged: app.setSpeed,
                  ),
                ),
                SizedBox(width: 52, child: Text('×${app.speed.toStringAsFixed(2)}')),
              ]),
            ]),
          ),
        ),
        for (final (cat, list) in sections)
          if (list.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(cat.title.toUpperCase(), style: t.labelMedium?.copyWith(letterSpacing: 1.2)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.0,
                children: [
                  for (final e in list)
                    _EffectTile(
                      effect: e,
                      color: _tileColors[colorIndex++ % _tileColors.length],
                      playing: app.playing?.id == e.id,
                      onTap: () => _play(context, e),
                      onMenu: () => _menu(context, e),
                    ),
                ],
              ),
            ),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}

class _EffectTile extends StatelessWidget {
  const _EffectTile({
    required this.effect,
    required this.color,
    required this.playing,
    required this.onTap,
    required this.onMenu,
  });

  final Effect effect;
  final Color color;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: playing ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 18, spreadRadius: 1)] : null,
        border: playing ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: onMenu,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Stack(children: [
              Align(
                alignment: Alignment.topLeft,
                child: Icon(_icons[effect.id] ?? Icons.auto_awesome, color: Colors.white),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  effect.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: playing ? onTap : onMenu,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.white,
                    child: Icon(playing ? Icons.stop_rounded : Icons.more_horiz, size: 18, color: color),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(dense: true, leading: Icon(icon), title: Text(text)),
      );
}

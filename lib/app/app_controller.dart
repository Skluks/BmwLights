import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/hex.dart';
import '../effects/presets.dart';
import '../engine/effect_player.dart';
import '../engine/light_controller.dart';
import '../model/effect.dart';
import '../model/lamp.dart';
import '../model/lamp_map.dart';
import '../protocol/diag.dart';
import '../protocol/elm.dart';
import '../sim/sim_car.dart';
import '../transport/byte_link.dart';

enum LinkState { disconnected, connecting, connected }

class _CarSink implements LampSink {
  _CarSink(this.app);
  final AppController app;

  @override
  Future<void> show(Set<Lamp> lamps) async {
    app._setPreview(lamps);
    await app.controller?.apply(lamps);
  }

  @override
  Future<void> finish() async {
    await app.controller?.releaseAll();
    app._setPreview(const {});
  }
}

class _PreviewSink implements LampSink {
  _PreviewSink(this.app);
  final AppController app;

  @override
  Future<void> show(Set<Lamp> lamps) async => app._setPreview(lamps);

  @override
  Future<void> finish() async => app._setPreview(const {});
}

/// App-wide state: settings, lamp map, effects, the adapter connection and playback.
class AppController extends ChangeNotifier {
  static const _kMap = 'lamp_map';
  static const _kEffects = 'effects';
  static const _kEcu = 'ecu';
  static const _kSession = 'session';
  static const _kSpeed = 'speed';
  static const _kSafety = 'safety_ok';

  SharedPreferences? _prefs;

  // Settings
  int ecu = 0x70;
  int? session;
  double speed = 1.0;

  /// Loop every effect until stopped.
  bool repeat = false;
  bool safetyAccepted = false;

  // Data
  LampMap _carMap = LampMap();
  LampMap? _demoMap;
  final List<Effect> effects = builtInEffects();

  // Connection
  LinkState state = LinkState.disconnected;
  ByteLink? _link;
  ElmSession? _elm;
  DiagClient? diag;
  LightController? controller;
  SimCar? sim;
  String? adapterVersion;
  String? moduleStatus;
  String? error;
  Timer? _keepAlive;
  StreamSubscription<Set<Lamp>>? _simSub;

  // Playback
  EffectPlayer? _player;
  Effect? playing;
  Set<Lamp> preview = {};
  Set<Lamp> simLit = {};

  final List<String> log = [];

  bool get isDemo => sim != null;
  bool get connected => state == LinkState.connected;
  String get linkName => _link?.name ?? '';

  /// The lamp map in use: the demo one while the simulator is connected.
  LampMap get lampMap => _demoMap ?? _carMap;

  DiagPort? get port => diag == null ? null : DiagClientPort(diag!);

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    ecu = p.getInt(_kEcu) ?? 0x70;
    session = p.getInt(_kSession);
    speed = p.getDouble(_kSpeed) ?? 1.0;
    safetyAccepted = p.getBool(_kSafety) ?? false;
    try {
      final m = p.getString(_kMap);
      if (m != null) _carMap = LampMap.decode(m);
      final e = p.getString(_kEffects);
      if (e != null) effects.addAll(Effect.decodeList(e));
    } catch (e) {
      addLog('Ошибка чтения настроек: $e');
    }
    notifyListeners();
  }

  void addLog(String line) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    log.add('${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')} $line');
    if (log.length > 500) log.removeRange(0, log.length - 500);
  }

  void _setPreview(Set<Lamp> lamps) {
    preview = lamps;
    notifyListeners();
  }

  // ---------------- settings ----------------

  Future<void> setEcu(int value) async {
    ecu = value;
    await _prefs?.setInt(_kEcu, value);
    notifyListeners();
  }

  Future<void> setSession(int? value) async {
    session = value;
    if (value == null) {
      await _prefs?.remove(_kSession);
    } else {
      await _prefs?.setInt(_kSession, value);
    }
    notifyListeners();
  }

  Future<void> setSpeed(double value) async {
    speed = value;
    notifyListeners();
    await _prefs?.setDouble(_kSpeed, value);
  }

  void toggleRepeat() {
    repeat = !repeat;
    notifyListeners();
  }

  Future<void> acceptSafety() async {
    safetyAccepted = true;
    await _prefs?.setBool(_kSafety, true);
    notifyListeners();
  }

  // ---------------- lamp map ----------------

  Future<void> setBinding(Lamp lamp, LampBinding? binding) async {
    if (binding == null) {
      lampMap.bindings.remove(lamp);
    } else {
      lampMap.bindings[lamp] = binding;
    }
    await _saveMap();
  }

  Future<void> replaceMap(LampMap map) async {
    lampMap.bindings
      ..clear()
      ..addAll(map.bindings);
    await _saveMap();
  }

  Future<void> _saveMap() async {
    if (_demoMap == null) await _prefs?.setString(_kMap, _carMap.encode());
    notifyListeners();
  }

  // ---------------- effects ----------------

  Future<void> saveEffect(Effect effect) async {
    final i = effects.indexWhere((e) => e.id == effect.id);
    if (i >= 0) {
      effects[i] = effect;
    } else {
      effects.add(effect);
    }
    await _saveEffects();
  }

  Future<void> deleteEffect(Effect effect) async {
    effects.removeWhere((e) => e.id == effect.id && !e.builtIn);
    await _saveEffects();
  }

  Future<void> _saveEffects() async {
    await _prefs?.setString(_kEffects, Effect.encodeList(effects.where((e) => !e.builtIn).toList()));
    notifyListeners();
  }

  String newEffectId() => 'u${DateTime.now().microsecondsSinceEpoch}';

  // ---------------- connection ----------------

  Future<void> connectDemo() async {
    final car = SimCar();
    sim = car;
    _demoMap = _buildDemoMap(car.module);
    _simSub = car.module.litStream.listen((l) {
      simLit = l;
      notifyListeners();
    });
    await connect(car);
  }

  static LampMap _buildDemoMap(SimLightModule m) {
    final map = LampMap();
    m.outputs.forEach((lid, out) {
      out.bits.forEach((bit, lamp) {
        final state = List.filled(out.length, 0);
        state[bit ~/ 8] = 0x80 >> (bit % 8);
        map.bindings[lamp] = IoBinding(ecu: m.address, lid: lid, onState: state);
      });
    });
    return map;
  }

  /// Opens a link (BLE/SPP) and connects over it, reporting errors in [error].
  Future<void> connectWith(Future<ByteLink> Function() open, String what) async {
    await disconnect();
    state = LinkState.connecting;
    notifyListeners();
    final ByteLink link;
    try {
      link = await open();
    } catch (e) {
      error = '$what: $e';
      addLog(error!);
      state = LinkState.disconnected;
      notifyListeners();
      return;
    }
    await connect(link);
  }

  Future<void> connect(ByteLink link) async {
    await disconnect();
    _link = link;
    state = LinkState.connecting;
    error = null;
    moduleStatus = null;
    notifyListeners();
    try {
      final elm = _elm = ElmSession(link, log: addLog);
      await elm.init();
      adapterVersion = elm.version;
      diag = DiagClient(elm);
      controller = LightController(DiagClientPort(diag!), lampMap, onError: (e) => addLog('Ошибка: $e'));
      state = LinkState.connected;
      unawaited(link.done.then((_) {
        if (_link == link) {
          error = 'Связь с адаптером потеряна';
          unawaited(disconnect());
        }
      }));
      notifyListeners();
      await checkModule();
    } catch (e) {
      error = 'Не удалось подключиться: $e';
      addLog(error!);
      await disconnect(keepError: true);
    }
  }

  /// Checks that the light module answers and opens the configured session.
  Future<bool> checkModule() async {
    final d = diag;
    if (d == null) return false;
    try {
      if (session != null) {
        await d.startSession(ecu, session!);
        _startKeepAlive();
      } else {
        await d.testerPresent(ecu);
      }
      moduleStatus = 'Модуль света ${hexByte(ecu)} отвечает';
      notifyListeners();
      return true;
    } catch (e) {
      moduleStatus = 'Модуль ${hexByte(ecu)}: $e';
      notifyListeners();
      return false;
    }
  }

  void _startKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        await diag?.testerPresent(ecu);
      } catch (_) {}
    });
  }

  Future<void> disconnect({bool keepError = false}) async {
    await stop();
    _keepAlive?.cancel();
    _keepAlive = null;
    final link = _link;
    _link = null;
    await _elm?.dispose();
    _elm = null;
    diag = null;
    controller = null;
    await link?.close();
    await _simSub?.cancel();
    _simSub = null;
    sim = null;
    simLit = {};
    _demoMap = null;
    adapterVersion = null;
    moduleStatus = null;
    if (!keepError) error = null;
    state = LinkState.disconnected;
    notifyListeners();
  }

  // ---------------- playback ----------------

  /// Plays on the car when connected, otherwise only on the screen.
  Future<void> play(Effect effect, {bool previewOnly = false}) async {
    await stop();
    final LampSink sink = (!previewOnly && connected) ? _CarSink(this) : _PreviewSink(this);
    final player = _player = EffectPlayer(sink);
    playing = effect;
    notifyListeners();
    try {
      final run = repeat ? (effect.copyAs(id: effect.id)..loops = 0) : effect;
      await player.play(run, speed: () => speed);
    } catch (e) {
      error = 'Эффект остановлен: $e';
    } finally {
      if (_player == player) {
        _player = null;
        playing = null;
      }
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final p = _player;
    if (p == null) return;
    p.stop();
    // Wait until the player released the outputs.
    while (p.running) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Switches single lamps from the lamp screen.
  Future<String?> testLamps(Set<Lamp> on) async {
    final c = controller;
    if (c == null) return 'Нет подключения';
    try {
      await c.apply(on);
      _setPreview(on);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> releaseAll() async {
    await controller?.releaseAll();
    _setPreview(const {});
  }

  // ---------------- terminal ----------------

  Future<String> sendRaw(int ecu, List<int> payload) async {
    final d = diag;
    if (d == null) return 'Нет подключения';
    try {
      final r = await d.request(ecu, payload);
      if (r.isNotEmpty && r[0] == 0x7F && r.length > 2) {
        return '${toHex(r)}  (${nrcDescriptions[r[2]] ?? 'отказ'})';
      }
      return toHex(r);
    } catch (e) {
      return e.toString();
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(disconnect());
    super.dispose();
  }
}

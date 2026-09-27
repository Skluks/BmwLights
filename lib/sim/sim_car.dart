import 'dart:async';
import 'dart:convert';

import '../core/hex.dart';
import '../model/lamp.dart';
import '../transport/byte_link.dart';

/// One simulated IO-control output of the light module.
class SimOutput {
  SimOutput(this.length, this.bits, {this.readable = true});

  final int length;

  /// bit index (byte * 8 + bit, bit 7 = MSB) -> lamp.
  final Map<int, Lamp> bits;
  final bool readable;
  List<int>? override;

  List<int> get normal => List.filled(length, 0);
  List<int> get effective => override ?? normal;
}

/// Simulated E60 light module on D-CAN (answers on 0x600 + [address]).
class SimLightModule {
  SimLightModule({this.address = 0x70, Map<int, SimOutput>? outputs}) : outputs = outputs ?? defaultOutputs();

  final int address;
  final Map<int, SimOutput> outputs;
  final _lit = StreamController<Set<Lamp>>.broadcast();

  Stream<Set<Lamp>> get litStream => _lit.stream;

  Set<Lamp> get lit {
    final on = <Lamp>{};
    for (final o in outputs.values) {
      final s = o.effective;
      o.bits.forEach((bit, lamp) {
        if (s[bit ~/ 8] & (0x80 >> (bit % 8)) != 0) on.add(lamp);
      });
    }
    return on;
  }

  /// Made-up layout: LID 0x10 front, 0x11 rear, 0x12 the rest, 0x20 exists but isn't readable.
  static Map<int, SimOutput> defaultOutputs() {
    Map<int, Lamp> seq(List<Lamp> lamps) => {for (var i = 0; i < lamps.length; i++) i: lamps[i]};
    return {
      0x10: SimOutput(2, seq(Lamps.front.toList())),
      0x11: SimOutput(2, seq(Lamps.rear.toList())),
      0x12: SimOutput(1, seq([Lamp.turnSideL, Lamp.turnSideR])),
      0x20: SimOutput(1, {}, readable: false),
    };
  }

  List<int> handle(List<int> req) {
    if (req.isEmpty) return [0x7F, 0x00, 0x13];
    final sid = req[0];
    switch (sid) {
      case 0x3E:
        return [0x7E];
      case 0x10:
        return req.length == 2 ? [0x50, req[1]] : [0x7F, sid, 0x13];
      case 0x1A:
        return [0x5A, if (req.length > 1) req[1], ...ascii.encode('SIM LM E60 LCI 0001')];
      case 0x30:
        if (req.length < 3) return [0x7F, sid, 0x13];
        final lid = req[1];
        final out = outputs[lid];
        if (out == null) return [0x7F, sid, 0x31];
        switch (req[2]) {
          case 0x00:
            out.override = null;
            _lit.add(lit);
            return [0x70, lid, 0x00];
          case 0x01:
            if (!out.readable) return [0x7F, sid, 0x12];
            return [0x70, lid, 0x01, ...out.effective];
          case 0x07:
            final state = req.sublist(3);
            if (state.length != out.length) return [0x7F, sid, 0x13];
            out.override = state;
            _lit.add(lit);
            return [0x70, lid, 0x07, ...state];
          default:
            return [0x7F, sid, 0x12];
        }
      default:
        return [0x7F, sid, 0x11];
    }
  }

  Future<void> dispose() => _lit.close();
}

/// Simulated ELM327 (vLinker) in the raw CAN mode [ElmSession] uses, with one light module behind it.
class SimCar implements ByteLink {
  SimCar({SimLightModule? module, this.frameDelay = const Duration(milliseconds: 15), this.stScale = 1.0})
      : module = module ?? SimLightModule();

  final SimLightModule module;
  final Duration frameDelay;

  /// Scales the ATST listen timeout (tests use a small value).
  final double stScale;

  final _in = StreamController<List<int>>();
  final _done = Completer<void>();
  final StringBuffer _line = StringBuffer();
  final List<String> received = [];

  int _header = 0x7DF;
  int _st = 0x32;
  bool _listening = false;
  Timer? _promptTimer;

  // ISO-TP state (tester -> module)
  List<int> _rxBuf = [];
  int _rxTotal = 0;
  // ISO-TP state (module -> tester)
  List<int> _txPending = [];
  int _txSeq = 0;

  @override
  String get name => 'Симулятор E60';

  @override
  Stream<List<int>> get input => _in.stream;

  @override
  Future<void> get done => _done.future;

  void _emit(String s) {
    if (!_in.isClosed) _in.add(latin1.encode(s));
  }

  void _prompt() {
    _listening = false;
    _promptTimer?.cancel();
    _emit('\r>');
  }

  void _armPromptTimer() {
    _promptTimer?.cancel();
    final ms = (_st == 0 ? 0x32 : _st) * 4 * stScale;
    _promptTimer = Timer(Duration(microseconds: (ms * 1000).round()), () {
      if (_listening) _prompt();
    });
  }

  @override
  Future<void> write(List<int> data) async {
    for (final ch in latin1.decode(data).split('')) {
      if (_listening) {
        // Any character interrupts listening; it is swallowed.
        _listening = false;
        _promptTimer?.cancel();
        _emit('STOPPED\r\r>');
        continue;
      }
      if (ch == '\r') {
        final cmd = _line.toString().replaceAll(' ', '').toUpperCase();
        _line.clear();
        received.add(cmd);
        _command(cmd);
      } else {
        _line.write(ch);
      }
    }
  }

  void _command(String cmd) {
    if (cmd.isEmpty) {
      _emit('\r>');
      return;
    }
    if (cmd.startsWith('AT')) {
      final a = cmd.substring(2);
      if (a == 'Z') {
        _emit('\r\rELM327 v2.3\r\r>');
      } else if (a == 'I') {
        _emit('ELM327 v2.3\r\r>');
      } else if (a.startsWith('SH')) {
        _header = int.parse(a.substring(2), radix: 16);
        _emit('OK\r\r>');
      } else if (a.startsWith('ST')) {
        _st = int.parse(a.substring(2), radix: 16);
        _emit('OK\r\r>');
      } else if (a == 'MA') {
        _listening = true; // until interrupted
      } else {
        _emit('OK\r\r>');
      }
      return;
    }
    final bytes = tryParseHex(cmd);
    if (bytes == null || bytes.isEmpty || bytes.length > 8) {
      _emit('?\r\r>');
      return;
    }
    _listening = true;
    _armPromptTimer();
    if (_header == 0x6F1 && bytes[0] == module.address) {
      Future<void>.delayed(frameDelay, () => _onTesterFrame(bytes));
    }
  }

  void _sendFrame(List<int> data) {
    if (!_listening) return; // adapter isn't listening -> frame is lost, like the real thing
    final id = 0x600 + module.address;
    _emit('${id.toRadixString(16).toUpperCase()}${toHex(data, sep: '')}\r');
    _armPromptTimer();
  }

  void _onTesterFrame(List<int> f) {
    if (f.length < 2) return;
    final pci = f[1];
    switch (pci >> 4) {
      case 0:
        final len = pci & 0x0F;
        _respond(module.handle(f.sublist(2, 2 + len)));
      case 1:
        _rxTotal = ((pci & 0x0F) << 8) | f[2];
        _rxBuf = f.sublist(3).toList();
        _sendFrame([0xF1, 0x30, 0x00, 0x00, 0, 0, 0, 0]);
      case 2:
        _rxBuf.addAll(f.sublist(2));
        if (_rxBuf.length >= _rxTotal) {
          _respond(module.handle(_rxBuf.sublist(0, _rxTotal)));
          _rxTotal = 0;
        }
      case 3:
        _sendConsecutive();
    }
  }

  void _respond(List<int> payload) {
    if (payload.length <= 6) {
      _sendFrame([0xF1, payload.length, ...payload]);
      return;
    }
    _sendFrame([0xF1, 0x10 | (payload.length >> 8), payload.length & 0xFF, ...payload.sublist(0, 5)]);
    _txPending = payload.sublist(5);
    _txSeq = 1;
  }

  Future<void> _sendConsecutive() async {
    while (_txPending.isNotEmpty) {
      await Future<void>.delayed(frameDelay);
      final n = _txPending.length < 6 ? _txPending.length : 6;
      _sendFrame([0xF1, 0x20 | (_txSeq++ & 0x0F), ..._txPending.sublist(0, n)]);
      _txPending = _txPending.sublist(n);
    }
  }

  @override
  Future<void> close() async {
    _promptTimer?.cancel();
    if (!_done.isCompleted) _done.complete();
    await _in.close();
  }
}

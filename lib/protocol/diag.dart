import '../core/hex.dart';
import 'elm.dart';

/// Negative response (7F sid nrc) from an ECU.
class NegativeResponse implements Exception {
  NegativeResponse(this.service, this.code);
  final int service;
  final int code;

  String get description => nrcDescriptions[code] ?? 'неизвестный код';

  @override
  String toString() => 'Отказ блока: 7F ${hexByte(service)} ${hexByte(code)} — $description';
}

class NoResponse implements Exception {
  NoResponse(this.ecu);
  final int ecu;
  @override
  String toString() => 'Блок ${hexByte(ecu)} не ответил';
}

const nrcDescriptions = <int, String>{
  0x10: 'общий отказ',
  0x11: 'сервис не поддерживается',
  0x12: 'подфункция/формат не поддерживается',
  0x13: 'неверная длина/формат',
  0x21: 'занят, повторите',
  0x22: 'условия не выполнены (зажигание? скорость?)',
  0x31: 'значение вне диапазона (нет такого идентификатора)',
  0x33: 'нужен доступ безопасности',
  0x78: 'ответ задерживается',
  0x7F: 'сервис не поддерживается в текущей сессии',
  0x80: 'сервис не поддерживается в текущей сессии',
};

/// Reassembles an ISO-TP answer with BMW extended addressing:
/// ECU -> tester frames have CAN id 0x600 + ecu and data[0] == tester address.
class IsoTpResponse extends FrameCollector {
  IsoTpResponse(this.ecu, {this.tester = 0xF1});
  final int ecu;
  final int tester;

  List<int>? payload;
  List<int> _buf = [];
  int _total = 0;
  int _seq = 0;
  bool _pending = false;

  @override
  bool get keepListening => _pending;

  @override
  List<int> get flowControl => [ecu, 0x30, 0x00, 0x00, 0, 0, 0, 0];

  @override
  Feed feed(CanFrame f) {
    if (f.id != 0x600 + ecu || f.data.length < 2 || f.data[0] != tester) return Feed.more;
    final pci = f.data[1];
    switch (pci >> 4) {
      case 0: // single frame
        final len = pci & 0x0F;
        if (len == 0 || f.data.length < 2 + len) return Feed.more;
        final p = f.data.sublist(2, 2 + len);
        if (p.length >= 3 && p[0] == 0x7F && p[2] == 0x78) {
          _pending = true;
          return Feed.more;
        }
        payload = p;
        return Feed.done;
      case 1: // first frame
        _total = ((pci & 0x0F) << 8) | f.data[2];
        _buf = f.data.sublist(3).toList();
        _seq = 1;
        return Feed.flowControl;
      case 2: // consecutive frame
        if (_total == 0 || (pci & 0x0F) != (_seq & 0x0F)) return Feed.more;
        _seq++;
        _buf.addAll(f.data.sublist(2));
        if (_buf.length >= _total) {
          payload = _buf.sublist(0, _total);
          return Feed.done;
        }
        return Feed.more;
      default:
        return Feed.more;
    }
  }
}

/// Waits for a flow control frame from the ECU while we send a multi-frame request.
class _FlowControlWait extends FrameCollector {
  _FlowControlWait(this.ecu, this.tester);
  final int ecu;
  final int tester;
  int blockSize = 0;
  int sepTime = 0;
  bool ok = false;

  @override
  Feed feed(CanFrame f) {
    if (f.id != 0x600 + ecu || f.data.length < 5 || f.data[0] != tester) return Feed.more;
    if (f.data[1] == 0x30) {
      blockSize = f.data[2];
      sepTime = f.data[3];
      ok = true;
      return Feed.done;
    }
    return Feed.more; // 0x31 = wait, anything else ignored
  }
}

class _Nothing extends FrameCollector {
  @override
  Feed feed(CanFrame frame) => Feed.more;
}

/// BMW KWP2000-over-D-CAN diagnostic client.
class DiagClient {
  DiagClient(this.elm, {this.tester = 0xF1});
  final ElmSession elm;
  final int tester;

  static List<int> _pad(List<int> d) => [...d, for (var i = d.length; i < 8; i++) 0x00];

  /// Sends [payload] to [ecu] and returns the raw response payload
  /// (positive or negative). Throws [NoResponse] on silence.
  Future<List<int>> request(int ecu, List<int> payload, {Duration timeout = const Duration(seconds: 3)}) async {
    final rx = IsoTpResponse(ecu, tester: tester);
    bool ok;
    if (payload.length <= 6) {
      ok = await elm.transmit(_pad([ecu, payload.length, ...payload]), rx, timeout: timeout);
    } else {
      ok = await elm.locked(() => _sendMulti(ecu, payload, rx, timeout));
    }
    if (!ok || rx.payload == null) throw NoResponse(ecu);
    return rx.payload!;
  }

  Future<bool> _sendMulti(int ecu, List<int> payload, IsoTpResponse rx, Duration timeout) async {
    if (payload.length > 0xFFF) throw ArgumentError('слишком длинный запрос');
    final fc = _FlowControlWait(ecu, tester);
    await elm.transmitUnlocked(
        [ecu, 0x10 | (payload.length >> 8), payload.length & 0xFF, ...payload.sublist(0, 5)], fc, timeout);
    if (!fc.ok) return false;
    var offset = 5;
    var seq = 1;
    var inBlock = 0;
    var fastTimeout = false;
    try {
      while (offset < payload.length) {
        final chunk = payload.sublist(offset, (offset + 6).clamp(0, payload.length));
        offset += chunk.length;
        final frame = _pad([ecu, 0x20 | (seq & 0x0F), ...chunk]);
        seq++;
        inBlock++;
        final last = offset >= payload.length;
        final needFc = !last && fc.blockSize > 0 && inBlock >= fc.blockSize;
        if (last || needFc) {
          if (fastTimeout) {
            await elm.commandUnlocked('ATSTFF');
            fastTimeout = false;
          }
          if (last) return await elm.transmitUnlocked(frame, rx, timeout);
          fc.ok = false;
          await elm.transmitUnlocked(frame, fc, timeout);
          if (!fc.ok) return false;
          inBlock = 0;
        } else {
          if (!fastTimeout) {
            // Don't let the adapter sit for a full second after frames that get no answer.
            await elm.commandUnlocked('ATST01');
            fastTimeout = true;
          }
          await elm.transmitUnlocked(frame, _Nothing(), timeout);
          if (fc.sepTime > 0 && fc.sepTime <= 0x7F) {
            await Future<void>.delayed(Duration(milliseconds: fc.sepTime));
          }
        }
      }
      return false;
    } finally {
      if (fastTimeout) await elm.commandUnlocked('ATSTFF');
    }
  }

  /// Like [request] but throws [NegativeResponse] unless the answer is positive.
  Future<List<int>> requestPositive(int ecu, List<int> payload,
      {Duration timeout = const Duration(seconds: 3)}) async {
    final r = await request(ecu, payload, timeout: timeout);
    if (r.isNotEmpty && r[0] == 0x7F) {
      throw NegativeResponse(r.length > 1 ? r[1] : payload[0], r.length > 2 ? r[2] : 0);
    }
    if (r.isEmpty || r[0] != (payload[0] | 0x40)) {
      throw NegativeResponse(payload[0], 0x10);
    }
    return r;
  }

  Future<void> testerPresent(int ecu) => requestPositive(ecu, const [0x3E]);

  Future<void> startSession(int ecu, int session) => requestPositive(ecu, [0x10, session]);
}

/// KWP2000 InputOutputControlByLocalIdentifier (service 0x30) helpers.
abstract final class IoControl {
  static const returnControl = 0x00;
  static const reportState = 0x01;
  static const shortTermAdjust = 0x07;

  static List<int> read(int lid) => [0x30, lid, reportState];
  static List<int> set(int lid, List<int> state) => [0x30, lid, shortTermAdjust, ...state];
  static List<int> release(int lid) => [0x30, lid, returnControl];
}

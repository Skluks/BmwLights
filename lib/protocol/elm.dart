import 'dart:async';
import 'dart:convert';

import '../core/hex.dart';
import '../transport/byte_link.dart';

class ElmException implements Exception {
  ElmException(this.message);
  final String message;
  @override
  String toString() => 'ELM: $message';
}

class CanFrame {
  const CanFrame(this.id, this.data);
  final int id;
  final List<int> data;

  @override
  String toString() => '${id.toRadixString(16).toUpperCase().padLeft(3, '0')} ${toHex(data)}';
}

/// What a frame collector wants [ElmSession.transmit] to do next.
enum Feed {
  /// Keep listening.
  more,

  /// Collected everything; stop listening.
  done,

  /// A multi-frame answer started: stop listening and send [FrameCollector.flowControl].
  flowControl,
}

abstract class FrameCollector {
  Feed feed(CanFrame frame);

  /// If the adapter stops listening (prompt) before [Feed.done]: should we re-arm with ATMA?
  /// True while the ECU said "response pending" (NRC 0x78).
  bool get keepListening => false;

  /// Flow control frame data to send when [feed] returned [Feed.flowControl].
  List<int> get flowControl => const [];
}

/// Serializes async sections.
class AsyncLock {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() body) {
    final prev = _last;
    final done = Completer<void>();
    _last = done.future;
    return prev.then((_) => body()).whenComplete(done.complete);
  }
}

/// Talks to an ELM327-compatible adapter (vLinker BM/BM+, OBDLink, ...) in raw CAN mode,
/// set up for BMW D-CAN (11 bit, 500 kbit/s, tester 0x6F1, ECU answers on 0x600 + address).
///
/// The init sequence mirrors EdiabasLib/Deep OBD ("EdElmInterface"): a user CAN protocol
/// without ISO-TP formatting, so ISO-TP with BMW extended addressing is done by us.
class ElmSession {
  ElmSession(this.link, {this.log}) {
    _sub = link.input.listen(_onData, onError: (Object _) => _signal());
  }

  final ByteLink link;
  final void Function(String line)? log;

  final StringBuffer _rx = StringBuffer();
  Completer<void>? _dataSignal;
  late final StreamSubscription<List<int>> _sub;
  final AsyncLock _lock = AsyncLock();

  String? version;

  static const _initCommands = [
    'ATD',
    'ATE0',
    'ATSH6F1',
    'ATCF600',
    'ATCM700',
    'ATPBC001', // user protocol B: 11 bit ID, variable DLC, no ISO-TP formatting, 500 kbit/s
    'ATSPB',
    'ATAT0',
    'ATSTFF',
    'ATAL',
    'ATH1',
    'ATS0',
    'ATL0',
  ];

  // Not supported by every clone; failures are ignored.
  static const _optionalCommands = ['ATCSM0', 'ATCTM5'];

  static const commandTimeout = Duration(milliseconds: 2500);

  void _onData(List<int> data) {
    // Some adapters emit NUL bytes; drop them.
    _rx.write(latin1.decode(data.where((b) => b != 0).toList(), allowInvalid: true));
    _signal();
  }

  void _signal() {
    final s = _dataSignal;
    _dataSignal = null;
    s?.complete();
  }

  Future<void> _awaitData(Duration timeout) {
    final s = _dataSignal ??= Completer<void>();
    return s.future.timeout(timeout, onTimeout: () {});
  }

  Future<void> _write(String text) {
    log?.call('> ${text.trim().isEmpty ? '(stop)' : text.trim()}');
    return link.write(latin1.encode(text));
  }

  /// Waits for the '>' prompt and returns everything received before it.
  Future<String> _readUntilPrompt(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final text = _rx.toString();
      final i = text.indexOf('>');
      if (i >= 0) {
        _rx.clear();
        _rx.write(text.substring(i + 1));
        return text.substring(0, i);
      }
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) throw ElmException('нет ответа от адаптера');
      await _awaitData(left);
    }
  }

  Future<String> _command(String cmd, Duration timeout) async {
    _rx.clear();
    await _write('$cmd\r');
    final answer = await _readUntilPrompt(timeout);
    log?.call('< ${answer.replaceAll(RegExp(r'[\r\n]+'), ' ').trim()}');
    return answer;
  }

  /// Sends an AT command and returns the raw answer.
  Future<String> command(String cmd, {Duration timeout = commandTimeout}) =>
      _lock.run(() => _command(cmd, timeout));

  Future<void> _commandOk(String cmd) async {
    final answer = await _command(cmd, commandTimeout);
    if (!answer.contains('OK')) throw ElmException('$cmd -> ${answer.trim()}');
  }

  /// Resets the adapter and configures it for BMW D-CAN.
  Future<void> init() => _lock.run(() async {
        // A lone space stops a monitor mode left over from an earlier session
        // (a lone CR would repeat the adapter's last command). Then reset.
        await _write(' ');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        _rx.clear();
        try {
          await _command('ATZ', const Duration(seconds: 4));
        } on ElmException {
          // Some clones stay silent after ATZ; carry on and let ATD/ATE0 decide.
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        for (final cmd in _initCommands) {
          await _commandOk(cmd);
        }
        for (final cmd in _optionalCommands) {
          try {
            await _command(cmd, const Duration(milliseconds: 800));
          } on ElmException {
            // ignore
          }
        }
        version = (await _command('ATI', commandTimeout)).trim();
      });

  static CanFrame? parseFrameLine(String line) {
    final s = line.replaceAll(' ', '').toUpperCase();
    if (s.length < 3 || s.length.isEven || s.length > 19) return null;
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(s)) return null;
    final id = int.parse(s.substring(0, 3), radix: 16);
    return CanFrame(id, [for (var i = 3; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
  }

  /// Sends one CAN frame (id 0x6F1) and feeds every received frame to [collector]
  /// until it reports [Feed.done], the adapter times out, or [timeout] expires.
  /// Returns false if the collector never finished.
  Future<bool> transmit(List<int> frame, FrameCollector collector, {Duration timeout = const Duration(seconds: 3)}) =>
      _lock.run(() => _transmit(frame, collector, timeout));

  /// Same as [transmit] but the caller already holds the lock (used for multi-frame requests).
  Future<bool> transmitUnlocked(List<int> frame, FrameCollector collector, Duration timeout) =>
      _transmit(frame, collector, timeout);

  Future<String> commandUnlocked(String cmd) => _command(cmd, commandTimeout);

  Future<T> locked<T>(Future<T> Function() body) => _lock.run(body);

  Future<bool> _transmit(List<int> frame, FrameCollector collector, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    _rx.clear();
    await _write('${toHex(frame, sep: '')}\r');
    var consumed = 0; // chars of _rx already parsed as lines
    var listening = true;

    Future<void> stopListening() async {
      if (!listening) return;
      if (!_rx.toString().contains('>')) await _write(' ');
      await _readUntilPrompt(commandTimeout);
      listening = false;
      consumed = 0;
    }

    loop:
    while (true) {
      final text = _rx.toString();
      final promptAt = text.indexOf('>');
      final limit = promptAt >= 0 ? promptAt : text.length;
      final lastBreak = text.substring(0, limit).lastIndexOf(RegExp(r'[\r\n]'));
      final end = promptAt >= 0 ? promptAt : lastBreak + 1;
      if (end > consumed) {
        for (final line in text.substring(consumed, end).split(RegExp(r'[\r\n]+'))) {
          final f = parseFrameLine(line.trim());
          if (f == null) {
            if (line.trim().isNotEmpty) log?.call('< ${line.trim()}');
            continue;
          }
          log?.call('< $f');
          switch (collector.feed(f)) {
            case Feed.more:
              break;
            case Feed.done:
              await stopListening();
              return true;
            case Feed.flowControl:
              await stopListening();
              _rx.clear();
              await _write('${toHex(collector.flowControl, sep: '')}\r');
              listening = true;
              continue loop;
          }
        }
        consumed = end;
      }
      if (listening && promptAt >= 0) {
        // Adapter gave up listening (ATST timeout).
        _rx.clear();
        consumed = 0;
        if (collector.keepListening && DateTime.now().isBefore(deadline)) {
          await _write('ATMA\r');
          continue;
        }
        return false;
      }
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        await stopListening();
        return false;
      }
      await _awaitData(left);
    }
  }

  Future<void> dispose() async {
    await _sub.cancel();
  }
}

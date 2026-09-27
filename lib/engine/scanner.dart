import '../core/hex.dart';
import '../protocol/diag.dart';
import 'light_controller.dart';

class FoundOutput {
  FoundOutput(this.lid, {this.state, this.nrc});

  final int lid;

  /// Current state from `30 lid 01` (report current state); null if not reported.
  final List<int>? state;

  /// Set when the module knows the LID but refused to report it.
  final int? nrc;

  /// Byte count to use for `30 lid 07 <state>`; guessed as 1 when unknown.
  int get length => (state == null || state!.isEmpty) ? 1 : state!.length;

  String get summary => state != null
      ? 'LID ${hexByte(lid)}: ${toHex(state!)}'
      : 'LID ${hexByte(lid)}: ${nrc != null ? nrcDescriptions[nrc] ?? hexByte(nrc!) : '?'}';
}

class ScanAborted implements Exception {
  ScanAborted(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Finds the IO-control outputs of a module and lets the user test them one by one.
///
/// Discovery only uses "report current state" (30 lid 01), which does not change anything.
/// Tests always end with "return control to ECU" (30 lid 00).
class OutputScanner {
  OutputScanner(this.port, this.ecu);

  final DiagPort port;
  final int ecu;

  Future<List<FoundOutput>> discover({
    int from = 0x00,
    int to = 0xFF,
    void Function(int lid, List<FoundOutput> found)? onProgress,
    bool Function()? cancelled,
  }) async {
    final found = <FoundOutput>[];
    var silent = 0;
    var sessionRefusals = 0;
    for (var lid = from; lid <= to; lid++) {
      if (cancelled?.call() ?? false) break;
      onProgress?.call(lid, found);
      List<int> r;
      try {
        r = await port.request(ecu, IoControl.read(lid));
        silent = 0;
      } on NoResponse {
        if (++silent >= 3) throw ScanAborted('Блок ${hexByte(ecu)} не отвечает. Зажигание включено? Верный адрес?');
        continue;
      }
      if (r.length >= 3 && r[0] == 0x70 && r[1] == lid) {
        found.add(FoundOutput(lid, state: r.length > 3 ? r.sublist(3) : const []));
      } else if (r.length >= 3 && r[0] == 0x7F) {
        final nrc = r[2];
        if (nrc == 0x11) throw ScanAborted('Блок не поддерживает управление выходами (сервис 30).');
        if (nrc == 0x7F || nrc == 0x80) {
          if (++sessionRefusals >= 3) {
            throw ScanAborted('Блок требует диагностическую сессию. Укажите её в настройках (например 86) и повторите.');
          }
        } else if (nrc != 0x31) {
          // LID exists but can't be read (e.g. 12/13/22): still worth testing.
          found.add(FoundOutput(lid, nrc: nrc));
        }
      }
    }
    onProgress?.call(to, found);
    return found;
  }

  /// Forces [lid] to [state] (30 lid 07 state). Returns the error text or null on success.
  Future<String?> force(int lid, List<int> state) async {
    try {
      await port.requestPositive(ecu, IoControl.set(lid, state));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> release(int lid) async {
    try {
      await port.requestPositive(ecu, IoControl.release(lid));
    } catch (_) {
      // best effort
    }
  }

  /// Test patterns for an output: everything on, then each single bit.
  static List<List<int>> patterns(int length) => [
        List.filled(length, 0xFF),
        for (var byte = 0; byte < length; byte++)
          for (var bit = 7; bit >= 0; bit--) [for (var i = 0; i < length; i++) i == byte ? 1 << bit : 0],
      ];
}

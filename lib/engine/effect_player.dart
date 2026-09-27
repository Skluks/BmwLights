import 'dart:async';

import '../model/effect.dart';
import '../model/lamp.dart';

/// Where a playing effect sends its frames: the real car or just the on-screen preview.
abstract class LampSink {
  Future<void> show(Set<Lamp> lamps);
  Future<void> finish();
}

/// Plays an [Effect] frame by frame. Command latency is absorbed into the frame time,
/// so the effect runs as close to its nominal tempo as the bus allows.
class EffectPlayer {
  EffectPlayer(this.sink, {this.onFrame});

  final LampSink sink;
  final void Function(int index, Set<Lamp> lamps)? onFrame;

  bool _stop = false;
  Completer<void>? _wake;
  bool _running = false;

  bool get running => _running;

  void stop() {
    _stop = true;
    _wake?.complete();
    _wake = null;
  }

  /// [speed] 2.0 = twice as fast. Returns when finished or stopped; always calls [LampSink.finish].
  Future<void> play(Effect effect, {double Function()? speed}) async {
    if (_running) throw StateError('already playing');
    _running = true;
    _stop = false;
    try {
      var loop = 0;
      while (!_stop && (effect.loops == 0 || loop < effect.loops) && effect.frames.isNotEmpty) {
        for (var i = 0; i < effect.frames.length && !_stop; i++) {
          final frame = effect.frames[i];
          final started = DateTime.now();
          onFrame?.call(i, frame.lamps);
          await sink.show(frame.lamps);
          final factor = (speed?.call() ?? 1.0).clamp(0.1, 10.0);
          final target = Duration(milliseconds: (frame.durationMs / factor).round());
          final left = target - DateTime.now().difference(started);
          if (left > Duration.zero && !_stop) {
            final wake = _wake = Completer<void>();
            await wake.future.timeout(left, onTimeout: () {});
            _wake = null;
          }
        }
        loop++;
      }
    } finally {
      _running = false;
      await sink.finish();
    }
  }
}

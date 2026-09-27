import 'dart:async';

/// A raw, bidirectional byte pipe to the OBD adapter
/// (Bluetooth LE, Bluetooth Classic SPP, or the built-in simulator).
abstract class ByteLink {
  /// Human readable name, e.g. "vLinker BM+ (BLE)".
  String get name;

  /// Bytes arriving from the adapter.
  Stream<List<int>> get input;

  Future<void> write(List<int> data);

  /// Completes when the link drops (either side).
  Future<void> get done;

  Future<void> close();
}

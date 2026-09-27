/// Hex helpers shared by the protocol layers and the UI.
library;

String hexByte(int b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();

/// `[0x30, 0x1A]` -> `"30 1A"` (or `"301A"` with [sep] = '').
String toHex(Iterable<int> bytes, {String sep = ' '}) => bytes.map(hexByte).join(sep);

/// Parses `"30 1a 07"`, `"301A07"` or `"30,1A,07"`. Throws [FormatException].
List<int> parseHex(String text) {
  final clean = text.replaceAll(RegExp(r'[\s,:;]|0x', caseSensitive: false), '');
  if (clean.isEmpty) return const [];
  if (clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
    throw FormatException('Неверная hex-строка: "$text"');
  }
  return [for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16)];
}

/// Like [parseHex] but returns null instead of throwing.
List<int>? tryParseHex(String text) {
  try {
    return parseHex(text);
  } on FormatException {
    return null;
  }
}

bool bytesEqual(List<int>? a, List<int>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Small formatting and id helpers. Ported from site/assets/js/util.js.
library;

/// `83` -> `01:23`, `3725` -> `1:02:05`. Anything invalid -> `00:00`.
String formatTime(num? seconds) {
  if (seconds == null || !seconds.isFinite || seconds < 0) return '00:00';
  final s = seconds.floor();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  String pad(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${pad(m)}:${pad(r)}' : '${pad(m)}:${pad(r)}';
}

String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// Stable short id from a string (djb2), identical to the web build's `slugId`.
String slugId(String s) {
  var h = 5381;
  for (final unit in s.codeUnits) {
    h = ((h << 5) + h + unit) & 0xFFFFFFFF;
  }
  return h.toRadixString(36);
}

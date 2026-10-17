/// LRC and TTML parsers. Ported 1:1 from site/assets/js/lyrics.js.
library;

import '../data/models.dart';

final _lrcTimeTag = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

/// `[mm:ss.xx] line`, `[mm:ss.xxx] line`, `[mm:ss] line`. Untimed lines are dropped.
List<LyricLine> parseLrc(String? source) {
  if (source == null || source.isEmpty) return [];
  final lines = <LyricLine>[];
  for (final raw in source.split(RegExp(r'\r?\n'))) {
    final text = raw.replaceAll(_lrcTimeTag, '').trim();
    for (final m in _lrcTimeTag.allMatches(raw)) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final fracRaw = m.group(3) ?? '0';
      final frac = int.parse(fracRaw) / _pow10(fracRaw.length);
      lines.add(LyricLine(min * 60 + sec + frac, text.isEmpty ? '♪' : text));
    }
  }
  lines.sort((a, b) => a.t.compareTo(b.t));
  return lines;
}

double _pow10(int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// TTML time expression -> seconds. Handles `27.395`, `27.395s`, `1234ms`,
/// `3:14.571`, `00:03:14.571`.
double? parseTtmlTime(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;

  if (RegExp(r'^-?\d+(\.\d+)?ms$').hasMatch(value)) return double.parse(value.substring(0, value.length - 2)) / 1000;
  if (RegExp(r'^-?\d+(\.\d+)?s$').hasMatch(value)) return double.parse(value.substring(0, value.length - 1));
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) return double.parse(value);

  final parts = value.split(':').map((p) => p.trim()).toList();
  if (parts.length < 2 || parts.length > 3) return null;
  var total = 0.0;
  for (final part in parts) {
    final n = double.tryParse(part);
    if (n == null) return null;
    total = total * 60 + n;
  }
  return total;
}

const _ttmlEntities = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&#39;': "'",
  '&#34;': '"',
  '&nbsp;': ' ',
};

String _decodeTtmlText(String raw) {
  var out = raw.replaceAll(RegExp(r'<[^>]+>'), '');
  out = out.replaceAllMapped(RegExp(r'&[a-zA-Z#0-9]+;'), (m) => _ttmlEntities[m.group(0)] ?? ' ');
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// TTML `<p begin="..." end="...">...</p>` -> lines.
List<LyricLine> parseTtml(String? source) {
  if (source == null || source.isEmpty) return [];
  final lines = <LyricLine>[];
  final para = RegExp(r'<p\b([^>]*)>([\s\S]*?)</p>', caseSensitive: false);
  final beginRe = RegExp(r'''\bbegin\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  final endRe = RegExp(r'''\bend\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  final durRe = RegExp(r'''\bdur\s*=\s*["']([^"']+)["']''', caseSensitive: false);

  for (final m in para.allMatches(source)) {
    final attrs = m.group(1) ?? '';
    final inner = m.group(2) ?? '';
    final begin = beginRe.firstMatch(attrs);
    if (begin == null) continue;
    final t = parseTtmlTime(begin.group(1));
    if (t == null) continue;

    final end = endRe.firstMatch(attrs);
    final dur = durRe.firstMatch(attrs);
    double? tEnd;
    if (end != null) {
      tEnd = parseTtmlTime(end.group(1));
    } else if (dur != null) {
      final d = parseTtmlTime(dur.group(1));
      tEnd = d == null ? null : t + d;
    }
    final text = _decodeTtmlText(inner);
    lines.add(LyricLine(t, text.isEmpty ? '♪' : text, tEnd: tEnd));
  }
  lines.sort((a, b) => a.t.compareTo(b.t));
  return lines;
}

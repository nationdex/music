/// Lyrics lookup across providers. Ported from site/assets/js/lyrics.js; calls
/// the providers directly (they are keyless) instead of through nginx.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../data/models.dart';

class LyricsQuery {
  const LyricsQuery({
    required this.title,
    required this.artist,
    this.album = '',
    this.duration = 0,
    this.prefer = 'word',
    this.provider = 'auto',
  });

  final String title;
  final String artist;
  final String album;
  final double duration;
  final String prefer;
  final String provider;
}

class LyricsService {
  LyricsService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  Future<dynamic> _getJson(Uri uri) async {
    try {
      final res = await _http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      return res.statusCode == 200
          ? jsonDecode(utf8.decode(res.bodyBytes))
          : null;
    } catch (_) {
      return null;
    }
  }

  String? _blank(Object? v) => v is String && v.isNotEmpty ? v : null;

  LyricsRecord? _normalize(Object? best, String source) {
    if (best is! Map) return null;
    final rec = LyricsRecord(
      plain: _blank(best['plainLyrics']),
      synced: _blank(best['syncedLyrics']),
      ttml: _blank(best['ttml']),
      provider: best['provider'] as String?,
      syncLevel: best['syncLevel'] as String?,
      source: source,
    );
    if (rec.plain == null && rec.synced == null && rec.ttml == null) {
      return null;
    }
    return rec;
  }

  Future<LyricsRecord?> _adi(LyricsQuery o) async {
    final q = {
      'track': o.title,
      'artist': o.artist,
      if (o.album.isNotEmpty) 'album': o.album,
      if (o.duration > 0) 'duration': o.duration.floor().toString(),
      if (const ['word', 'line', 'plain', 'best'].contains(o.prefer))
        'prefer': o.prefer,
      if (adiProviders.contains(o.provider)) 'provider': o.provider,
    };
    final data = await _getJson(
      Uri.parse('${Endpoints.adi}/api/lyrics').replace(queryParameters: q),
    );
    if (data is Map && data['found'] == true) {
      return _normalize(data['best'], 'adi-lyrics');
    }
    return null;
  }

  Future<LyricsRecord?> _lrclib(LyricsQuery o) async {
    final q = {
      'track_name': o.title,
      'artist_name': o.artist,
      if (o.duration > 0) 'duration': o.duration.floor().toString(),
      if (o.album.isNotEmpty) 'album_name': o.album,
    };
    final d = await _getJson(
      Uri.parse('${Endpoints.lrclib}/api/get').replace(queryParameters: q),
    );
    if (d is! Map) return null;
    final synced = _blank(d['syncedLyrics']);
    return _normalize({
      'plainLyrics': d['plainLyrics'],
      'syncedLyrics': synced,
      'syncLevel': synced != null ? 'line' : 'plain',
      'provider': 'lrclib',
    }, 'lrclib-direct');
  }

  Future<LyricsRecord?> _lrcmux(LyricsQuery o) async {
    final d = await _getJson(
      Uri.parse('${Endpoints.lrcmux}/compat/kpoe/v2/lyrics/get')
          .replace(queryParameters: {'title': o.title, 'artist': o.artist}),
    );
    if (d is! Map) return null;
    final inner = d['data'] is Map
        ? d['data']
        : (d['best'] is Map ? d['best'] : d);
    return _normalize(inner, 'lrcmux-direct');
  }

  /// provider: `auto` -> aggregator, LRCLIB, LRC Mux | `adi` | `lrclib` | `lrcmux` | an adapter id (pinned aggregator).
  Future<LyricsRecord?> resolve(LyricsQuery o) async {
    var steps = const ['adi', 'lrclib', 'lrcmux'];
    if (const ['adi', 'lrclib', 'lrcmux'].contains(o.provider)) {
      steps = [o.provider];
    } else if (adiProviders.contains(o.provider)) {
      steps = const ['adi'];
    }
    for (final step in steps) {
      final rec = switch (step) {
        'adi' => await _adi(o),
        'lrclib' => await _lrclib(o),
        _ => await _lrcmux(o),
      };
      if (rec != null) return rec;
    }
    return null;
  }
}

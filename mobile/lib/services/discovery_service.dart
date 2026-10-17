/// Discovery search. Ported from site/assets/js/sources.js.
///
/// YouTube goes through an Adi Music server (the nginx in `deploy/`), which adds
/// the API key; the key never ships in the app. Apple previews are keyless and
/// are called directly.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../data/models.dart';

/// Thrown when YouTube is unavailable (no server, no key, quota spent) so the
/// caller can fall back to Apple previews.
class YouTubeUnavailable implements Exception {
  const YouTubeUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'YouTubeUnavailable: $reason';
}

/// `PT3M25S` -> 205.
int isoSeconds(String? iso) {
  int part(String unit) {
    final m = RegExp('(\\d+)$unit').firstMatch(iso ?? '');
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  return part('H') * 3600 + part('M') * 60 + part('S');
}

/// "Michael Jackson - Bad (Official Video)" + "michaeljacksonVEVO" -> (Bad, Michael Jackson).
({String name, String artist}) cleanYouTubeMeta(String title, String channel) {
  var name = title.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '').trim();
  var artist = channel.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').replaceAll(RegExp(r'VEVO$', caseSensitive: false), '').trim();
  final m = RegExp(r'^(.+?)\s+[-–]\s+(.+)$').firstMatch(name);
  if (m != null) {
    artist = m.group(1)!.trim();
    name = m.group(2)!.trim();
  }
  return (name: name.isEmpty ? title : name, artist: artist);
}

class DiscoveryService {
  DiscoveryService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  Future<dynamic> _getJson(Uri uri) async {
    try {
      final res = await _http.get(uri).timeout(const Duration(seconds: 15));
      return res.statusCode == 200 ? jsonDecode(utf8.decode(res.bodyBytes)) : null;
    } catch (_) {
      return null;
    }
  }

  /// Full-length tracks from YouTube via [serverUrl].
  Future<List<DiscoveryItem>> youtubeSearch(String serverUrl, String term, {int limit = 24}) async {
    final base = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw const YouTubeUnavailable('no server configured');

    final http.Response res;
    try {
      res = await _http
          .get(
            Uri.parse('$base/up/youtube/search').replace(
              queryParameters: {'part': 'snippet', 'type': 'video', 'videoCategoryId': '10', 'videoEmbeddable': 'true', 'maxResults': '${limit.clamp(1, 50)}', 'q': term},
            ),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw YouTubeUnavailable('$e');
    }
    if (res.statusCode != 200) throw YouTubeUnavailable('HTTP ${res.statusCode}');

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final rows = <({String id, String title, String channel, String? artwork})>[];
    for (final i in (data['items'] as List? ?? const [])) {
      final id = (i as Map)['id'];
      final videoId = id is Map ? id['videoId'] as String? : null;
      if (videoId == null) continue;
      final sn = (i['snippet'] as Map?) ?? const {};
      final th = (sn['thumbnails'] as Map?) ?? const {};
      final pick = (th['high'] ?? th['medium'] ?? th['default']) as Map?;
      rows.add((id: videoId, title: (sn['title'] as String?) ?? '', channel: (sn['channelTitle'] as String?) ?? '', artwork: pick?['url'] as String?));
    }

    final durations = <String, int>{};
    final blocked = <String>{};
    if (rows.isNotEmpty) {
      final det = await _getJson(
        Uri.parse('$base/up/youtube/videos').replace(queryParameters: {'part': 'contentDetails,status', 'id': rows.map((r) => r.id).join(',')}),
      );
      for (final d in (det is Map ? det['items'] as List? : null) ?? const []) {
        final m = d as Map;
        final id = m['id'] as String;
        durations[id] = isoSeconds((m['contentDetails'] as Map?)?['duration'] as String?);
        // The uploader blocked embedding: the iframe would fail with error 150.
        if (((m['status'] as Map?)?['embeddable']) == false) blocked.add(id);
      }
    }

    // Drop Shorts; keep relevance order, with edits and reactions after the originals.
    final real = rows.where((r) {
      final d = durations[r.id] ?? 0;
      return !blocked.contains(r.id) && !(d > 0 && d < 60);
    });
    bool derivative(String title) => derivativeTitles.any(title.toLowerCase().contains);
    final ordered = [...real.where((r) => !derivative(r.title)), ...real.where((r) => derivative(r.title))];

    return [
      for (final r in ordered)
        () {
          final meta = cleanYouTubeMeta(r.title, r.channel);
          return DiscoveryItem(
            id: r.id,
            videoId: r.id,
            name: meta.name,
            artist: meta.artist,
            album: 'YouTube',
            artwork: r.artwork,
            duration: (durations[r.id] ?? 0).toDouble(),
            source: TrackSource.youtube,
          );
        }(),
    ];
  }

  /// 30-second Apple previews.
  Future<List<DiscoveryItem>> itunesSearch(String term, {int limit = 24}) async {
    final res = await _http
        .get(Uri.parse('${Endpoints.itunes}/search').replace(queryParameters: {'term': term, 'media': 'music', 'entity': 'song', 'limit': '$limit'}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Search failed');
    final results = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['results'] as List? ?? const [];
    return [
      for (final r in results.cast<Map<String, dynamic>>())
        if ((r['previewUrl'] as String?)?.isNotEmpty ?? false)
          DiscoveryItem(
            id: '${r['trackId']}',
            name: (r['trackName'] as String?) ?? '',
            artist: (r['artistName'] as String?) ?? '',
            album: (r['collectionName'] as String?) ?? '',
            artwork: ((r['artworkUrl100'] as String?) ?? '').replaceFirst('100x100', '600x600'),
            duration: ((r['trackTimeMillis'] as num?) ?? 0) / 1000,
            source: TrackSource.remote,
            previewUrl: r['previewUrl'] as String,
          ),
    ];
  }
}

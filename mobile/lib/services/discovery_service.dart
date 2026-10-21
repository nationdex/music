/// Discovery search. Ported from site/assets/js/sources.js.
///
/// YouTube goes through an Adi Music server (the nginx in `deploy/`), which adds
/// the API key; the key never ships in the app. When that is unavailable, quota-spent or
/// not configured, the app asks Innertube directly. Apple previews are keyless and
/// are called directly.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../data/models.dart';

/// Thrown when YouTube search fails on every source (Data API through the server, then Innertube).
/// The caller falls back to Apple previews.
class YouTubeUnavailable implements Exception {
  const YouTubeUnavailable(this.reason, {this.status});
  final String reason;

  /// HTTP status of the failing source, when there was one.
  final int? status;
  @override
  String toString() => 'YouTubeUnavailable: $reason';
}

/// One YouTube search hit before it becomes a [DiscoveryItem].
typedef YouTubeRow = ({
  String id,
  String title,
  String channel,
  String? artwork,
  int duration,
});

/// "4:08" / "1:02:03" -> seconds.
int clockSeconds(String? text) {
  if (text == null || text.isEmpty) return 0;
  return text
      .split(':')
      .fold(0, (total, part) => total * 60 + (int.tryParse(part) ?? 0));
}

/// Videos from an Innertube search response. Live streams (no length) are dropped.
List<YouTubeRow> parseInnertubeSearch(Object? data) {
  final out = <YouTubeRow>[];
  if (data is! Map) return out;
  final sections =
      (((data['contents'] as Map?)?['twoColumnSearchResultsRenderer']
              as Map?)?['primaryContents']
          as Map?)?['sectionListRenderer'];
  for (final section
      in ((sections as Map?)?['contents'] as List?) ?? const []) {
    for (final entry
        in (((section as Map)['itemSectionRenderer'] as Map?)?['contents']
                as List?) ??
            const []) {
      final v = (entry as Map)['videoRenderer'];
      if (v is! Map || v['videoId'] is! String) continue;
      final length = (v['lengthText'] as Map?)?['simpleText'] as String?;
      if (length == null) continue;
      String join(Object? runs) =>
          [for (final r in (runs as List?) ?? const []) (r as Map)['text']]
              .join();
      final id = v['videoId'] as String;
      out.add((
        id: id,
        title: join((v['title'] as Map?)?['runs']),
        channel: join(
          (((v['ownerText'] ?? v['longBylineText']) as Map?)?['runs'] as List?)
              ?.take(1)
              .toList(),
        ),
        artwork: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        duration: clockSeconds(length),
      ));
    }
  }
  return out;
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
  var artist = channel
      .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
      .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
      .trim();
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
      return res.statusCode == 200
          ? jsonDecode(utf8.decode(res.bodyBytes))
          : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ YouTube

  /// Uploads that failed in the player with "embedding not allowed" (101 / 150). Hidden from search.
  final Set<String> blockedVideos = {};

  DateTime? _dataApiCooldownUntil;
  static const _cooldown = Duration(minutes: 15);
  static final _innertubeUrl = Uri.parse(
    'https://www.youtube.com/youtubei/v1/search?prettyPrint=false',
  );

  bool get dataApiCoolingDown =>
      _dataApiCooldownUntil != null &&
      DateTime.now().isBefore(_dataApiCooldownUntil!);

  /// Full-length tracks from YouTube. Two sources, in order: the Data API through the Adi Music
  /// server (key and daily quota live there), then Innertube, the internal API youtube.com
  /// itself uses (no key, no quota). The Data API is skipped for 15 minutes after it reports a
  /// spent quota or a rate limit. Throws [YouTubeUnavailable] only when both sources fail.
  Future<List<DiscoveryItem>> youtubeSearch(
    String serverUrl,
    String term, {
    int limit = 24,
  }) async {
    final base = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    List<YouTubeRow>? fromApi;
    if (base.isNotEmpty && !dataApiCoolingDown) {
      try {
        fromApi = await _dataApiSearch(base, term, limit);
      } on YouTubeUnavailable catch (e) {
        if (e.status == 403 || e.status == 429) {
          _dataApiCooldownUntil = DateTime.now().add(_cooldown);
        }
      }
    }
    final rows = fromApi ?? await _innertubeSearch(term, limit);

    // Drop Shorts and videos that already failed to embed; keep relevance order, with edits
    // and reactions after the originals.
    final real = rows.where(
      (r) =>
          !blockedVideos.contains(r.id) && !(r.duration > 0 && r.duration < 60),
    );
    bool derivative(String title) =>
        derivativeTitles.any(title.toLowerCase().contains);
    final ordered = [
      ...real.where((r) => !derivative(r.title)),
      ...real.where((r) => derivative(r.title)),
    ];
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
            duration: r.duration.toDouble(),
            source: TrackSource.youtube,
          );
        }(),
    ];
  }

  Future<List<YouTubeRow>> _innertubeSearch(String term, int limit) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            _innertubeUrl,
            headers: const {
              'Content-Type': 'application/json',
              'Origin': 'https://www.youtube.com',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB',
                  'clientVersion': '2.20260101.00.00',
                  'hl': 'en',
                  'gl': 'US',
                },
              },
              'query': term,
              'params': 'EgIQAQ%3D%3D', // type = video
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw YouTubeUnavailable('Innertube: $e');
    }
    if (res.statusCode != 200) {
      throw YouTubeUnavailable(
        'Innertube HTTP ${res.statusCode}',
        status: res.statusCode,
      );
    }
    final rows = parseInnertubeSearch(jsonDecode(utf8.decode(res.bodyBytes)));
    if (rows.isEmpty) {
      throw const YouTubeUnavailable(
        'Innertube returned no videos',
        status: 502,
      );
    }
    return rows.take(limit).toList();
  }

  Future<List<YouTubeRow>> _dataApiSearch(
    String base,
    String term,
    int limit,
  ) async {
    final http.Response res;
    try {
      res = await _http
          .get(
            Uri.parse('$base/up/youtube/search').replace(
              queryParameters: {
                'part': 'snippet',
                'type': 'video',
                'videoCategoryId': '10',
                'videoEmbeddable': 'true',
                'maxResults': '${limit.clamp(1, 50)}',
                'q': term,
              },
            ),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw YouTubeUnavailable('$e');
    }
    if (res.statusCode != 200) {
      throw YouTubeUnavailable(
        'HTTP ${res.statusCode}',
        status: res.statusCode,
      );
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final found =
        <({String id, String title, String channel, String? artwork})>[];
    for (final i in (data['items'] as List? ?? const [])) {
      final id = (i as Map)['id'];
      final videoId = id is Map ? id['videoId'] as String? : null;
      if (videoId == null) continue;
      final sn = (i['snippet'] as Map?) ?? const {};
      final th = (sn['thumbnails'] as Map?) ?? const {};
      final pick = (th['high'] ?? th['medium'] ?? th['default']) as Map?;
      found.add((
        id: videoId,
        title: (sn['title'] as String?) ?? '',
        channel: (sn['channelTitle'] as String?) ?? '',
        artwork: pick?['url'] as String?,
      ));
    }

    final durations = <String, int>{};
    final blocked = <String>{};
    if (found.isNotEmpty) {
      final det = await _getJson(
        Uri.parse('$base/up/youtube/videos').replace(
          queryParameters: {
            'part': 'contentDetails,status',
            'id': found.map((r) => r.id).join(','),
          },
        ),
      );
      for (final d in (det is Map ? det['items'] as List? : null) ?? const []) {
        final m = d as Map;
        final id = m['id'] as String;
        durations[id] = isoSeconds(
          (m['contentDetails'] as Map?)?['duration'] as String?,
        );
        // The uploader blocked embedding: the iframe would fail with error 150.
        if (((m['status'] as Map?)?['embeddable']) == false) blocked.add(id);
      }
    }
    return [
      for (final r in found)
        if (!blocked.contains(r.id))
          (
            id: r.id,
            title: r.title,
            channel: r.channel,
            artwork: r.artwork,
            duration: durations[r.id] ?? 0,
          ),
    ];
  }

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Other uploads of the same song, best first. Used when a video cannot be embedded: labels
  /// often block the official upload but allow the "Topic" or lyric one.
  Future<List<DiscoveryItem>> alternativesFor(
    Track track,
    String serverUrl, {
    Set<String> exclude = const {},
  }) async {
    final wantName = _normalize(track.name),
        wantArtist = _normalize(track.artist);
    final List<DiscoveryItem> rows;
    try {
      rows = await youtubeSearch(
        serverUrl,
        '${track.artist} ${track.name}'.trim(),
        limit: 15,
      );
    } on YouTubeUnavailable {
      return const [];
    }
    final scored = <(DiscoveryItem, int)>[];
    for (final r in rows) {
      if (r.id == track.videoId || exclude.contains(r.id)) continue;
      final name = _normalize(r.name);
      var score = 0;
      if (name == wantName) {
        score += 4;
      } else if (name.isNotEmpty &&
          wantName.isNotEmpty &&
          (name.contains(wantName) || wantName.contains(name))) {
        score += 2;
      }
      if (score == 0) continue; // a different song, whatever else matches
      if (wantArtist.isNotEmpty && _normalize(r.artist).contains(wantArtist)) {
        score += 2;
      }
      if (track.duration > 0 &&
          r.duration > 0 &&
          (r.duration - track.duration).abs() / track.duration < 0.12) {
        score += 2;
      }
      if (score >= 4) scored.add((r, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (item, _) in scored.take(3)) item];
  }

  /// 30-second Apple previews.
  Future<List<DiscoveryItem>> itunesSearch(
    String term, {
    int limit = 24,
  }) async {
    final res = await _http
        .get(
          Uri.parse('${Endpoints.itunes}/search').replace(
            queryParameters: {
              'term': term,
              'media': 'music',
              'entity': 'song',
              'limit': '$limit',
            },
          ),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Search failed');
    final results =
        (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['results'] as List? ??
        const [];
    return [
      for (final r in results.cast<Map<String, dynamic>>())
        if ((r['previewUrl'] as String?)?.isNotEmpty ?? false)
          DiscoveryItem(
            id: '${r['trackId']}',
            name: (r['trackName'] as String?) ?? '',
            artist: (r['artistName'] as String?) ?? '',
            album: (r['collectionName'] as String?) ?? '',
            artwork: ((r['artworkUrl100'] as String?) ?? '').replaceFirst(
              '100x100',
              '600x600',
            ),
            duration: ((r['trackTimeMillis'] as num?) ?? 0) / 1000,
            source: TrackSource.remote,
            previewUrl: r['previewUrl'] as String,
          ),
    ];
  }
}

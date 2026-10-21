import 'dart:convert';

import 'package:adi_music/data/models.dart';
import 'package:adi_music/data/settings.dart';
import 'package:adi_music/services/discovery_service.dart';
import 'package:adi_music/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_helpers.dart';

void main() {
  innertubeTests();
  group('YouTube metadata cleanup', () {
    test('splits "Artist - Title (Official Video)"', () {
      final m = cleanYouTubeMeta(
        'Michael Jackson - Bad (Official Video)',
        'michaeljacksonVEVO',
      );
      expect(m.name, 'Bad');
      expect(m.artist, 'Michael Jackson');
    });

    test('falls back to channel when the title has no separator', () {
      final m = cleanYouTubeMeta('Bad [HD]', 'Michael Jackson - Topic');
      expect(m.name, 'Bad');
      expect(m.artist, 'Michael Jackson');
    });

    test('isoSeconds parses ISO 8601 durations', () {
      expect(isoSeconds('PT3M25S'), 205);
      expect(isoSeconds('PT1H2M3S'), 3723);
      expect(isoSeconds('PT45S'), 45);
      expect(isoSeconds(null), 0);
    });
  });

  group('DiscoveryService', () {
    test(
      'YouTube: drops Shorts, orders edits after originals, reads durations',
      () async {
        final requested = <Uri>[];
        final client = MockClient((req) async {
          requested.add(req.url);
          if (req.url.path.endsWith('/up/youtube/search')) {
            return jsonResponse({
              'items': [
                {
                  'id': {'videoId': 'short1'},
                  'snippet': {'title': 'Quick clip', 'channelTitle': 'A'},
                },
                {
                  'id': {'videoId': 'rev1'},
                  'snippet': {
                    'title': 'Artist - Song (slowed + reverb)',
                    'channelTitle': 'B',
                  },
                },
                {
                  'id': {'videoId': 'orig1'},
                  'snippet': {
                    'title': 'Artist - Song (Official Audio)',
                    'channelTitle': 'ArtistVEVO',
                    'thumbnails': {
                      'high': {'url': 'https://i/h.jpg'},
                    },
                  },
                },
                {
                  'id': {'kind': 'youtube#channel'},
                  'snippet': {'title': 'ignored'},
                },
              ],
            });
          }
          return jsonResponse({
            'items': [
              {
                'id': 'short1',
                'contentDetails': {'duration': 'PT30S'},
              },
              {
                'id': 'rev1',
                'contentDetails': {'duration': 'PT4M'},
              },
              {
                'id': 'orig1',
                'contentDetails': {'duration': 'PT3M25S'},
              },
            ],
          });
        });

        final items = await DiscoveryService(client: client)
            .youtubeSearch('https://music.example.com/', 'artist song');
        expect(items.map((i) => i.videoId), [
          'orig1',
          'rev1',
        ], reason: 'short dropped, reverb edit last');
        expect(items.first.name, 'Song');
        expect(items.first.artist, 'Artist');
        expect(items.first.duration, 205);
        expect(items.first.artwork, 'https://i/h.jpg');
        expect(items.first.source, TrackSource.youtube);
        expect(items.first.trackId, 'yt_orig1');

        final search = requested.first;
        expect(search.host, 'music.example.com');
        expect(search.queryParameters['q'], 'artist song');
        expect(search.queryParameters['videoCategoryId'], '10');
        expect(
          search.queryParameters.containsKey('key'),
          isFalse,
          reason: 'the API key lives on the server, never in the app',
        );
      },
    );

    test(
      'YouTube unavailable: no server, HTTP error, network failure',
      () async {
        final svc = DiscoveryService(
          client: MockClient((_) async => jsonResponse({}, 503)),
        );
        expect(
          () => svc.youtubeSearch('', 'x'),
          throwsA(isA<YouTubeUnavailable>()),
        );
        expect(
          () => svc.youtubeSearch('https://m', 'x'),
          throwsA(isA<YouTubeUnavailable>()),
        );
        final broken = DiscoveryService(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        );
        expect(
          () => broken.youtubeSearch('https://m', 'x'),
          throwsA(isA<YouTubeUnavailable>()),
        );
      },
    );

    test('iTunes: maps previews and skips results without one', () async {
      final client = MockClient((req) async {
        expect(req.url.host, 'itunes.apple.com');
        expect(req.url.queryParameters['entity'], 'song');
        return jsonResponse({
          'results': [
            {
              'trackId': 1,
              'trackName': 'One',
              'artistName': 'A',
              'collectionName': 'Alb',
              'artworkUrl100': 'https://i/100x100bb.jpg',
              'previewUrl': 'https://p/1.m4a',
              'trackTimeMillis': 215000,
            },
            {'trackId': 2, 'trackName': 'Two', 'artistName': 'B'},
          ],
        });
      });
      final items = await DiscoveryService(client: client).itunesSearch('one');
      expect(items, hasLength(1));
      expect(items.single.artwork, 'https://i/600x600bb.jpg');
      expect(items.single.duration, 215);
      expect(items.single.toTrack().url, 'https://p/1.m4a');
      expect(items.single.toTrack().id, 'rm_1');
      expect(items.single.toTrack().stored, isFalse);
    });
  });

  group('LyricsService', () {
    const query = LyricsQuery(
      title: 'Song',
      artist: 'Artist',
      album: 'Alb',
      duration: 200.7,
    );

    test('auto: falls through aggregator -> LRCLIB -> LRC Mux', () async {
      final hosts = <String>[];
      final client = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'lrclib.net') {
          return jsonResponse({'error': 'nope'}, 404);
        }
        if (req.url.host == 'api.lrcmux.dev') {
          return jsonResponse({
            'data': {'plainLyrics': 'la la', 'provider': 'mux'},
          });
        }
        return jsonResponse({'found': false});
      });
      final rec = await LyricsService(client: client).resolve(query);
      expect(hosts, ['lyrics.adi.rest', 'lrclib.net', 'api.lrcmux.dev']);
      expect(rec!.plain, 'la la');
      expect(rec.source, 'lrcmux-direct');
    });

    test('aggregator hit wins and sends duration as whole seconds', () async {
      late Uri sent;
      final client = MockClient((req) async {
        sent = req.url;
        return jsonResponse({
          'found': true,
          'best': {
            'syncedLyrics': '[00:01.00] hi',
            'syncLevel': 'line',
            'provider': 'lrclib',
          },
        });
      });
      final rec = await LyricsService(client: client).resolve(
        const LyricsQuery(
          title: 'Song',
          artist: 'Artist',
          duration: 200.7,
          prefer: 'line',
        ),
      );
      expect(rec!.synced, '[00:01.00] hi');
      expect(rec.source, 'adi-lyrics');
      expect(sent.queryParameters['duration'], '200');
      expect(sent.queryParameters['prefer'], 'line');
    });

    test('pinned provider only asks that provider', () async {
      final hosts = <String>[];
      final client = MockClient((req) async {
        hosts.add(req.url.host);
        return jsonResponse({
          'syncedLyrics': '[00:02.00] x',
          'plainLyrics': 'x',
        });
      });
      final rec = await LyricsService(
        client: client,
      ).resolve(const LyricsQuery(title: 'S', artist: 'A', provider: 'lrclib'));
      expect(hosts, ['lrclib.net']);
      expect(rec!.syncLevel, 'line');

      hosts.clear();
      await LyricsService(
        client: MockClient((r) async {
          hosts.add(r.url.host);
          return jsonResponse({'found': false});
        }),
      ).resolve(const LyricsQuery(title: 'S', artist: 'A', provider: 'popcat'));
      expect(hosts, [
        'lyrics.adi.rest',
      ], reason: 'adapter ids pin the aggregator');
    });

    test('network errors resolve to null', () async {
      final client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      expect(await LyricsService(client: client).resolve(query), isNull);
    });
  });

  group('AppSettings', () {
    test('round-trips and tolerates junk', () {
      const s = AppSettings(
        theme: 'dark',
        accent: '#112233',
        volume: 0.4,
        serverUrl: 'https://m',
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.theme, 'dark');
      expect(back.accent, '#112233');
      expect(back.volume, 0.4);
      expect(back.serverUrl, 'https://m');

      final junk = AppSettings.fromJson({
        'theme': 5,
        'volume': 99,
        'pickColorFromArtwork': 'yes',
      });
      expect(junk.theme, 'auto');
      expect(junk.volume, 1.0, reason: 'clamped');
      expect(junk.pickColorFromArtwork, isTrue);
    });
  });
}

// ------------------------------------------------------------------ Innertube fallback

void innertubeTests() {
  group('Innertube', () {
    test('parses videos, drops live streams, reads clock durations', () {
      final rows = parseInnertubeSearch(
        innertubeJson([
          (
            'a1',
            'Michael Jackson - Bad (Official Video)',
            'Michael Jackson',
            '4:08',
          ),
          ('live', 'Radio 24/7', 'Radio', null),
          ('long', 'Bad (full album)', 'n', '1:02:03'),
        ]),
      );
      expect(rows.map((r) => r.id), ['a1', 'long']);
      expect(rows.first.duration, 248);
      expect(rows.last.duration, 3723);
      expect(rows.first.channel, 'Michael Jackson');
      expect(rows.first.artwork, 'https://i.ytimg.com/vi/a1/hqdefault.jpg');
      expect(parseInnertubeSearch(null), isEmpty);
      expect(parseInnertubeSearch({'contents': {}}), isEmpty);
      expect(clockSeconds('0:45'), 45);
    });

    test(
      'no server configured: Innertube answers directly, with no key involved',
      () async {
        late http.Request seen;
        final client = MockClient((req) async {
          seen = req;
          return jsonResponse(
            innertubeJson([
              ('a1', 'Michael Jackson - Bad', 'Michael Jackson', '4:08'),
              ('short', 'clip', 'x', '0:30'),
            ]),
          );
        });
        final items = await DiscoveryService(client: client)
            .youtubeSearch('', 'michael jackson bad');
        expect(seen.url.host, 'www.youtube.com');
        expect(seen.method, 'POST');
        expect(jsonDecode(seen.body)['query'], 'michael jackson bad');
        expect(seen.url.queryParameters.containsKey('key'), isFalse);
        expect(items.map((i) => i.videoId), [
          'a1',
        ], reason: 'the 30 s Short is dropped');
        expect(items.single.name, 'Bad');
        expect(items.single.artist, 'Michael Jackson');
        expect(items.single.duration, 248);
      },
    );

    test('Data API quota spent (403): falls back, then skips the Data API for a while', () async {
      var apiCalls = 0, innertubeCalls = 0;
      final client = MockClient((req) async {
        if (req.url.host == 'youtube.com' ||
            req.url.host == 'www.youtube.com') {
          innertubeCalls++;
          return jsonResponse(
            innertubeJson([('a1', 'Artist - Song', 'Artist', '3:00')]),
          );
        }
        apiCalls++;
        return jsonResponse({
          'error': {
            'errors': [
              {'reason': 'quotaExceeded'},
            ],
          },
        }, 403);
      });
      final svc = DiscoveryService(client: client);
      expect(
        (await svc.youtubeSearch(
          'https://music.example.com',
          'one',
        )).single.videoId,
        'a1',
      );
      expect(svc.dataApiCoolingDown, isTrue);
      await svc.youtubeSearch('https://music.example.com', 'two');
      expect(
        apiCalls,
        1,
        reason: 'cooldown: the second search does not touch the Data API',
      );
      expect(innertubeCalls, 2);
    });

    test('Data API 503 (no key) and network errors also fall back, without a cooldown', () async {
      var apiCalls = 0;
      final client = MockClient((req) async {
        if (req.url.host.endsWith('youtube.com')) {
          return jsonResponse(
            innertubeJson([('a1', 'Artist - Song', 'Artist', '3:00')]),
          );
        }
        apiCalls++;
        return jsonResponse({}, 503);
      });
      final svc = DiscoveryService(client: client);
      await svc.youtubeSearch('https://music.example.com', 'one');
      await svc.youtubeSearch('https://music.example.com', 'two');
      expect(
        apiCalls,
        2,
        reason: 'a missing key may be fixed any moment, so it is retried',
      );
      expect(svc.dataApiCoolingDown, isFalse);
    });

    test(
      'both sources failing throws, so the caller can use Apple previews',
      () async {
        final svc = DiscoveryService(
          client: MockClient((_) async => jsonResponse({}, 500)),
        );
        expect(
          () => svc.youtubeSearch('https://m', 'x'),
          throwsA(isA<YouTubeUnavailable>()),
        );
      },
    );

    test('blocked uploads are hidden from search', () async {
      final client = MockClient(
        (_) async => jsonResponse(
          innertubeJson([
            ('bad1', 'Artist - Song', 'Artist', '3:00'),
            ('ok2', 'Artist - Song (Lyrics)', 'Lyrics', '3:01'),
          ]),
        ),
      );
      final svc = DiscoveryService(client: client)..blockedVideos.add('bad1');
      expect((await svc.youtubeSearch('', 'x')).map((i) => i.videoId), ['ok2']);
    });

    test('alternativesFor ranks other uploads of the same song and skips excluded ones', () async {
      final client = MockClient(
        (_) async => jsonResponse(
          innertubeJson([
            (
              'orig',
              'Michael Jackson - Bad (Official Video)',
              'Michael Jackson',
              '4:08',
            ),
            ('topic', 'Bad', 'Michael Jackson - Topic', '4:08'),
            ('cover', 'Bad (guitar cover)', 'Someone', '3:00'),
            ('other', 'Smooth Criminal', 'Michael Jackson', '4:17'),
            ('lyrics', 'Michael Jackson - Bad (Lyrics)', 'LyricLandia', '4:10'),
          ]),
        ),
      );
      final svc = DiscoveryService(client: client);
      final track = Track(
        id: 'yt_orig',
        name: 'Bad',
        artist: 'Michael Jackson',
        source: TrackSource.youtube,
        videoId: 'orig',
        duration: 248,
        stored: false,
      );
      final alts = await svc.alternativesFor(track, '');
      expect(
        alts.map((a) => a.videoId),
        isNot(contains('orig')),
        reason: 'never the failing upload',
      );
      expect(
        alts.map((a) => a.videoId),
        isNot(contains('other')),
        reason: 'a different song',
      );
      expect(
        alts.first.videoId,
        'topic',
        reason: 'same title, artist and length ranks first',
      );
      expect(alts.map((a) => a.videoId), contains('lyrics'));

      final without = await svc.alternativesFor(track, '', exclude: {'topic'});
      expect(without.map((a) => a.videoId), isNot(contains('topic')));
    });
  });
}

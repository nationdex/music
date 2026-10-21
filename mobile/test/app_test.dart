import 'dart:convert';
import 'dart:io';

import 'package:adi_music/app.dart';
import 'package:adi_music/data/models.dart';
import 'package:adi_music/data/storage.dart';
import 'package:adi_music/services/discovery_service.dart';
import 'package:adi_music/state/eq_engine.dart';
import 'package:adi_music/state/library_controller.dart';
import 'package:adi_music/state/player_controller.dart';
import 'package:adi_music/state/settings_controller.dart';
import 'package:adi_music/ui/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_audio_player.dart';

class Harness {
  Harness(this.settings, this.library, this.player, this.audio, this.storage);
  final SettingsController settings;
  final LibraryController library;
  final PlayerController player;
  final FakeAudioPlayer audio;
  final Storage storage;

  Widget app({GlassTier tier = GlassTier.solid}) => AdiMusicApp(
    settings: settings,
    library: library,
    player: player,
    glassTier: tier,
    discovery: DiscoveryService(
      client: MockClient((req) async {
        if (req.url.host == 'itunes.apple.com') {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'trackId': 7,
                  'trackName': 'Preview Song',
                  'artistName': 'Preview Artist',
                  'collectionName': 'Alb',
                  'previewUrl': 'https://p/7.m4a',
                  'trackTimeMillis': 30000,
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 503);
      }),
    ),
  );
}

Future<Harness> harness(
  WidgetTester tester, {
  List<Track> tracks = const [],
  EqEngine? eqEngine,
}) async {
  late Harness h;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = Storage(
      root: Directory.systemTemp.createTempSync('adi_ui'),
      prefs: await SharedPreferences.getInstance(),
    );
    if (tracks.isNotEmpty) await storage.writeLibrary(tracks);
    final settings = SettingsController(storage);
    final library = LibraryController(storage);
    await library.load();
    final audio = FakeAudioPlayer();
    h = Harness(
      settings,
      library,
      PlayerController(
        library: library,
        settings: settings,
        player: audio,
        eqEngine: eqEngine,
      ),
      audio,
      storage,
    );
  });
  return h;
}

Track song(String id, String name, String artist, String album, {int no = 0}) =>
    Track(
      id: id,
      name: name,
      artist: artist,
      album: album,
      trackNo: no,
      duration: 200,
      source: TrackSource.remote,
      stored: false,
      url: 'https://x/$id.m4a',
    );

Future<void> pumpApp(
  WidgetTester tester,
  Harness h, {
  GlassTier tier = GlassTier.solid,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(h.app(tier: tier));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Real font metrics, so overflow bugs show up here instead of on a device.
    final loader = FontLoader('MPlusRounded1c');
    for (final w in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/MPLUSRounded1c-$w.ttf'));
    }
    await loader.load();
  });

  testWidgets(
    'empty library shows the empty state, mini player and navigation',
    (tester) async {
      final h = await harness(tester);
      await pumpApp(tester, h);

      expect(find.text('Your library is empty'), findsOneWidget);
      expect(find.text('Import tracks'), findsOneWidget);
      expect(find.text('Nothing playing'), findsOneWidget);
      for (final label in [
        'Tracks',
        'Albums',
        'Artists',
        'Playlists',
        'Discovery',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(
        find.text('Library'),
        findsNothing,
        reason: 'Library overview is not a phone tab (same as the web build)',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lists tracks, filters by search, and plays on tap', (
    tester,
  ) async {
    final h = await harness(
      tester,
      tracks: [
        song('1', 'Midnight Drive', 'Neon Harbor', 'Afterglow'),
        song('2', 'Salt Air', 'Ivy and the Wire', 'Greenhouse'),
        song('3', 'Window Seat', 'Hollow Pines', 'Quiet Rooms'),
      ],
    );
    await pumpApp(tester, h);

    expect(find.text('Midnight Drive'), findsOneWidget);
    expect(find.text('Salt Air'), findsOneWidget);
    expect(find.text('Window Seat'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hollow');
    await tester.pump();
    expect(find.text('Window Seat'), findsOneWidget);
    expect(find.text('Salt Air'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(find.text('No tracks found'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('Salt Air'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.player.currentTrack!.name, 'Salt Air');
    expect(h.player.queue, hasLength(3));
    // The mini player now names the track.
    expect(find.text('Nothing playing'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favouriting from the list updates the library', (tester) async {
    final h = await harness(
      tester,
      tracks: [song('1', 'Midnight Drive', 'Neon Harbor', 'Afterglow')],
    );
    await pumpApp(tester, h);
    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pump();
    expect(h.library.favoriteIds, ['1']);
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
  });

  testWidgets('tabs: albums, artists, playlists and album detail', (
    tester,
  ) async {
    final h = await harness(
      tester,
      tracks: [
        song('1', 'Midnight Drive', 'Neon Harbor', 'Afterglow', no: 2),
        song('2', 'Static Bloom', 'Neon Harbor', 'Afterglow', no: 1),
        song('3', 'Salt Air', 'Ivy and the Wire', 'Greenhouse'),
      ],
    );
    await pumpApp(tester, h);

    await tester.tap(find.text('Albums').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Afterglow'), findsOneWidget);
    expect(find.text('Greenhouse'), findsOneWidget);

    await tester.tap(find.text('Afterglow'));
    await tester.pumpAndSettle();
    expect(find.text('Album'), findsOneWidget);
    expect(find.text('2 tracks'), findsOneWidget);
    // Ordered by track number: Static Bloom (1) before Midnight Drive (2).
    expect(
      tester.getTopLeft(find.text('Static Bloom')).dy,
      lessThan(tester.getTopLeft(find.text('Midnight Drive')).dy),
    );

    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.player.currentTrack!.name, 'Static Bloom');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Artists').last);
    await tester.pump(const Duration(milliseconds: 300));
    final grid = find.byType(GridView);
    expect(
      find.descendant(of: grid, matching: find.text('Neon Harbor')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: grid, matching: find.text('Ivy and the Wire')),
      findsOneWidget,
    );

    await tester.tap(find.text('Playlists').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('New playlist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creating a playlist', (tester) async {
    final h = await harness(
      tester,
      tracks: [song('1', 'Midnight Drive', 'Neon Harbor', 'Afterglow')],
    );
    await pumpApp(tester, h);
    await tester.tap(find.text('Playlists').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('New playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Road trip');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(h.library.customPlaylists.single.name, 'Road trip');
    expect(find.text('Road trip'), findsOneWidget);
  });

  testWidgets('Discovery falls back to Apple previews without a server', (
    tester,
  ) async {
    final h = await harness(tester);
    await pumpApp(tester, h);
    await tester.tap(find.text('Discovery').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Preview Song'), findsOneWidget);
    expect(find.text('30-second Apple previews'), findsOneWidget);

    await tester.tap(find.byTooltip('Add to library'));
    await tester.pump();
    expect(h.library.tracks.single.name, 'Preview Song');
    expect(h.library.tracks.single.stored, isFalse);
    expect(find.byTooltip('In your library'), findsOneWidget);
  });

  testWidgets(
    'the full player opens from the mini player and shows queue and controls',
    (tester) async {
      final h = await harness(
        tester,
        tracks: [
          song('1', 'Midnight Drive', 'Neon Harbor', 'Afterglow'),
          song('2', 'Salt Air', 'Ivy', 'Greenhouse'),
        ],
      );
      await pumpApp(tester, h);
      await tester.tap(find.text('Midnight Drive'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Next').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.player.currentTrack!.name, 'Salt Air');

      await tester.tap(find.text('Salt Air').last);
      await tester.pumpAndSettle();
      expect(find.text('Player'), findsOneWidget);
      expect(find.byTooltip('Toggle mute'), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);

      await tester.tap(find.text('Queue'));
      await tester.pumpAndSettle();
      expect(find.text('Midnight Drive'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings: theme, accent reset, volume row and library actions', (
    tester,
  ) async {
    final h = await harness(
      tester,
      tracks: [song('1', 'Midnight Drive', 'Neon Harbor', 'Afterglow')],
    );
    await pumpApp(tester, h);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Application theme'), findsOneWidget);
    expect(find.text('1 track'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(h.settings.settings.theme, 'dark');
    expect(h.settings.themeMode, ThemeMode.dark);

    await tester.scrollUntilVisible(
      find.text('Equalizer'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Open equalizer'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('available on Android only'),
      findsOneWidget,
      reason: 'the test host is not Android, so the sheet explains why',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a track from the menu asks first', (tester) async {
    final h = await harness(
      tester,
      tracks: [song('1', 'Midnight Drive', 'Neon Harbor', 'Afterglow')],
    );
    await pumpApp(tester, h);
    await tester.tap(find.byTooltip('Track options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from library'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from library?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.library.tracks, hasLength(1));

    await tester.tap(find.byTooltip('Track options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from library'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Remove'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(h.library.tracks, isEmpty);
  });

  testWidgets('wide layout uses a navigation rail and keeps working', (
    tester,
  ) async {
    final h = await harness(
      tester,
      tracks: [song('1', 'Midnight Drive', 'Neon Harbor', 'Afterglow')],
    );
    tester.view.physicalSize = const Size(1200 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(h.app());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.text('Library'),
      findsOneWidget,
      reason: 'rail includes the Library overview',
    );
    await tester.tap(find.byIcon(Icons.album_outlined));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Select something from the list to be shown here'),
      findsOneWidget,
    );
    expect(find.text('Play'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(GridView),
        matching: find.text('Afterglow'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Select something from the list to be shown here'),
      findsNothing,
    );
    expect(
      find.text('Play'),
      findsOneWidget,
      reason: 'detail opens in the second pane',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('frosted glass tier renders without errors', (tester) async {
    final h = await harness(
      tester,
      tracks: [song('1', 'Midnight Drive', 'Neon Harbor', 'Afterglow')],
    );
    await pumpApp(tester, h, tier: GlassTier.frosted);
    expect(find.text('Midnight Drive'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('equalizer sheet: presets, bands, preamp and saving a preset', (
    tester,
  ) async {
    final engine = FakeEqEngine();
    final h = await harness(
      tester,
      tracks: [song('1', 'Midnight Drive', 'Neon Harbor', 'Afterglow')],
      eqEngine: engine,
    );
    await pumpApp(tester, h);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Open equalizer'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Open equalizer'));
    await tester.pumpAndSettle();

    expect(
      find.text('Equalizer'),
      findsNWidgets(2),
      reason: 'the settings row and the sheet title',
    );
    expect(find.text('Bass Boost'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Slider),
      ),
      findsNWidgets(11),
      reason: 'ten bands plus the preamp',
    );
    expect(find.textContaining('5 bands your device offers'), findsOneWidget);

    await tester.ensureVisible(find.text('Rock'));
    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();
    expect(h.player.eq.preset, 'Rock');
    expect(
      find.text('-6.0 dB'),
      findsOneWidget,
      reason: 'auto preamp for Rock',
    );
    expect(engine.gains, isNotEmpty);

    await tester.tap(find.text('Save preset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Night');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(h.player.eq.custom.keys, ['Night']);
    expect(find.widgetWithText(ChoiceChip, 'Night'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.player.eq.enabled, isFalse);
    expect(engine.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });
}

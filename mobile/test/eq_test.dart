import 'dart:io';
import 'dart:math';

import 'package:adi_music/core/eq_math.dart';
import 'package:adi_music/data/storage.dart';
import 'package:adi_music/state/library_controller.dart';
import 'package:adi_music/state/player_controller.dart';
import 'package:adi_music/state/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_audio_player.dart';

Future<(PlayerController, FakeEqEngine, FakeAudioPlayer, Storage)> make({
  Storage? storage,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final st =
      storage ??
      Storage(
        root: Directory.systemTemp.createTempSync('adi_eq'),
        prefs: await SharedPreferences.getInstance(),
      );
  final engine = FakeEqEngine();
  final audio = FakeAudioPlayer();
  final p = PlayerController(
    library: LibraryController(st),
    settings: SettingsController(st),
    player: audio,
    eqEngine: engine,
    random: Random(1),
  );
  await Future<void>.delayed(
    const Duration(milliseconds: 20),
  ); // device bands are read asynchronously
  return (p, engine, audio, st);
}

void main() {
  // Reference numbers computed with site/assets/js/eq.js `responseDb`; the two ports must agree.
  group('response maths match the web build', () {
    final probe = <double>[40, 100, 250, 1000, 3000, 9000, 15000];

    test('Rock at 44.1 kHz', () {
      final got = responseDb(eqPresets['Rock']!, probe);
      const want = [
        2.985778,
        2.848866,
        -0.820004,
        0.156915,
        3.471577,
        4.732297,
        2.471149,
      ];
      for (var i = 0; i < want.length; i++) {
        expect(got[i], closeTo(want[i], 1e-5), reason: '${probe[i]} Hz');
      }
    });

    test('Bass Boost with -7 dB preamp at 48 kHz', () {
      final got = responseDb(
        eqPresets['Bass Boost']!,
        probe,
        preamp: -7,
        fs: 48000,
      );
      const want = [
        -2.413428,
        -0.751138,
        -2.625932,
        -6.652371,
        -6.968871,
        -6.997297,
        -6.999462,
      ];
      for (var i = 0; i < want.length; i++) {
        expect(got[i], closeTo(want[i], 1e-5), reason: '${probe[i]} Hz');
      }
    });

    test('flat is 0 dB, and the end bands are shelves', () {
      expect(
        responseDb(eqPresets['Flat']!, logFreqs()).every((d) => d.abs() < 1e-9),
        isTrue,
      );
      final g = List.of(eqPresets['Flat']!)
        ..[0] = 8
        ..[9] = -8;
      final r = responseDb(g, [20, 20000]);
      expect(r[0], greaterThan(6.5));
      expect(r[1], lessThan(-6.5));
    });
  });

  group('EqState', () {
    test('seventeen presets, ten bands each, inside the range', () {
      expect(eqPresets.length, 17);
      for (final e in eqPresets.entries) {
        expect(e.value, hasLength(10), reason: e.key);
        expect(e.value.every((g) => g.abs() <= eqRange), isTrue, reason: e.key);
      }
    });

    test('auto preamp drops by the largest boost and never boosts', () {
      expect(autoPreamp(eqPresets['Bass Boost']!), -7);
      expect(autoPreamp([-4.0, -2]), 0);
      final eq = EqState(gains: eqPresets['Bass Boost']);
      expect(eq.effectivePreamp, -7);
      expect(
        (eq
              ..auto = false
              ..preamp = -3)
            .effectivePreamp,
        -3,
      );
      expect((eq..enabled = false).effectivePreamp, 0);
    });

    test('isActive', () {
      expect(EqState().isActive, isFalse);
      expect(EqState(gains: eqPresets['Rock']).isActive, isTrue);
      expect(
        EqState(gains: eqPresets['Rock'], enabled: false).isActive,
        isFalse,
      );
      expect(EqState(auto: false, preamp: -2).isActive, isTrue);
      expect(EqState(auto: true, preamp: -2).isActive, isFalse);
    });

    test('matchPreset names built-in and custom presets', () {
      expect(EqState(gains: eqPresets['Jazz']).matchPreset(), 'Jazz');
      expect(
        EqState(gains: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]).matchPreset(),
        'Custom',
      );
      final eq = EqState(
        gains: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        custom: {
          'Mine': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        },
      );
      expect(eq.matchPreset(), 'Mine');
    });

    test('fromJson repairs corrupt data', () {
      expect(EqState.fromJson(null).gains, eqPresets['Flat']);
      expect(EqState.fromJson('x').enabled, isTrue);
      final fixed = EqState.fromJson({
        'enabled': false,
        'gains': [99, -99, 'a', 0, 0, 0, 0, 0, 0, 0],
        'preamp': 50,
        'custom': {
          'Bad': [1],
          'Good': eqPresets['Rock'],
          'Flat': eqPresets['Vocal'],
        },
      });
      expect(fixed.enabled, isFalse);
      expect(fixed.gains.take(3), [12, -12, 0]);
      expect(fixed.preamp, 12);
      expect(fixed.custom.keys, ['Good']);
      expect(
        EqState.fromJson({
          'gains': [1, 2],
        }).gains,
        eqPresets['Flat'],
      );
    });

    test('toJson and fromJson round-trip', () {
      final eq = EqState(
        preset: 'Mine',
        gains: eqPresets['Pop'],
        preamp: -2.5,
        auto: false,
        custom: {'Mine': eqPresets['Pop']!},
      );
      final back = EqState.fromJson(eq.toJson());
      expect(back.gains, eq.gains);
      expect(back.preamp, -2.5);
      expect(back.auto, isFalse);
      expect(back.custom['Mine'], eq.custom['Mine']);
    });

    test(
      'interpolation hits the preset gain at each of the ten frequencies',
      () {
        final rock = eqPresets['Rock']!;
        for (var i = 0; i < eqFrequencies.length; i++) {
          expect(
            interpolateGains(rock, eqFrequencies[i]),
            closeTo(rock[i], 1e-9),
          );
        }
        expect(
          interpolateGains(rock, sqrt(32 * 64)),
          closeTo((rock[0] + rock[1]) / 2, 1e-9),
        );
        expect(interpolateGains(rock, 20), rock.first);
        expect(interpolateGains(rock, 20000), rock.last);
      },
    );
  });

  group('player equalizer', () {
    test('a preset is mapped onto the device bands and clamped', () async {
      final (p, engine, _, _) = await make();
      await p.applyEqPreset('Bass Boost');
      expect(p.eqSupported, isTrue);
      expect(engine.gains, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(
          engine.gains[i],
          closeTo(
            interpolateGains(
              eqPresets['Bass Boost']!,
              const <double>[60, 230, 910, 3600, 14000][i],
            ),
            1e-9,
          ),
        );
      }
      expect(
        engine.gains.first,
        greaterThan(engine.gains.last),
        reason: 'a bass boost is loudest at the bottom',
      );
    });

    test('auto headroom lowers the volume instead of boosting', () async {
      final (p, engine, audio, _) = await make();
      await p.applyEqPreset('Bass Boost');
      expect(audio.volume, closeTo(dbToGain(-7), 1e-9));
      expect(engine.boost, 0);
      await p.applyEqPreset('Flat');
      expect(audio.volume, 1);
    });

    test('a manual positive preamp uses the loudness boost, a negative one the volume', () async {
      final (p, engine, audio, _) = await make();
      await p.setEqPreamp(6);
      expect(p.eq.auto, isFalse);
      expect(engine.boost, 6);
      expect(audio.volume, 1);
      await p.setEqPreamp(-4);
      expect(engine.boost, 0);
      expect(audio.volume, closeTo(dbToGain(-4), 1e-9));
    });

    test('bypass neutralizes everything but keeps the settings', () async {
      final (p, engine, audio, _) = await make();
      await p.applyEqPreset('Rock');
      await p.setEqEnabled(false);
      expect(engine.enabled, isFalse);
      expect(engine.boost, 0);
      expect(audio.volume, 1);
      expect(p.eq.gains, eqPresets['Rock']);
      await p.setEqEnabled(true);
      expect(engine.enabled, isTrue);
      expect(audio.volume, closeTo(dbToGain(-6), 1e-9));
    });

    test(
      'moving a band makes the preset Custom, and the mapping follows',
      () async {
        final (p, engine, _, _) = await make();
        await p.applyEqPreset('Flat');
        await p.setEqBand(5, 9);
        expect(p.eq.preset, 'Custom');
        expect(
          engine.gains[2],
          greaterThan(0),
          reason: '910 Hz sits next to the 1 kHz band',
        );
        await p.setEqBand(5, 99);
        expect(p.eq.gains[5], 12, reason: 'clamped to the slider range');
      },
    );

    test(
      'custom presets: save, recall, refuse built-in names, delete',
      () async {
        final (p, _, _, _) = await make();
        await p.setEqBand(3, 7);
        expect(await p.saveEqPreset('  My mix  '), isNull);
        expect(p.eq.preset, 'My mix');
        expect(p.eq.custom.keys, ['My mix']);
        await p.applyEqPreset('Jazz');
        await p.applyEqPreset('My mix');
        expect(p.eq.gains[3], 7);
        expect(await p.saveEqPreset('Rock'), contains('built-in'));
        expect(await p.saveEqPreset(''), isNull);
        expect(p.eq.custom.keys, ['My mix']);
        await p.deleteEqPreset();
        expect(p.eq.custom, isEmpty);
        expect(
          p.eq.preset,
          'Custom',
          reason: 'the gains no longer match a named preset',
        );
      },
    );

    test('settings survive a restart', () async {
      final (p, _, _, storage) = await make();
      await p.applyEqPreset('Vocal');
      await p.setEqPreamp(-2);
      await p.setEqBand(0, 4);
      await p.saveEqPreset('Night');

      final (q, engine, _, _) = await make(storage: storage);
      expect(q.eq.gains, p.eq.gains);
      expect(q.eq.preamp, -2);
      expect(q.eq.auto, isFalse);
      expect(q.eq.custom.keys, ['Night']);
      expect(
        engine.gains,
        isNotEmpty,
        reason: 'the stored curve is applied to the device on start',
      );
    });

    test('without a device equalizer nothing breaks', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final st = Storage(
        root: Directory.systemTemp.createTempSync('adi_eq2'),
        prefs: await SharedPreferences.getInstance(),
      );
      final p = PlayerController(
        library: LibraryController(st),
        settings: SettingsController(st),
        player: FakeAudioPlayer(),
      );
      expect(p.eqPlatformSupported, isFalse);
      expect(p.eqSupported, isFalse);
      await p.applyEqPreset('Rock'); // state still updates and persists
      expect(p.eq.preset, 'Rock');
    });
  });
}

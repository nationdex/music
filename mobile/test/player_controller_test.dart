import 'dart:io';
import 'dart:math';

import 'package:adi_music/core/config.dart';
import 'package:just_audio/just_audio.dart';
import 'package:adi_music/data/models.dart';
import 'package:adi_music/data/storage.dart';
import 'package:adi_music/state/library_controller.dart';
import 'package:adi_music/state/player_controller.dart';
import 'package:adi_music/state/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_audio_player.dart';

Track t(String id, {String? url}) => Track(id: id, name: 'Song $id', artist: 'A', source: TrackSource.remote, stored: false, url: url, duration: 100);

Future<(PlayerController, LibraryController)> make({FakeAudioPlayer? audio}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final storage = Storage(root: Directory.systemTemp.createTempSync('adi_player'), prefs: await SharedPreferences.getInstance());
  final lib = LibraryController(storage);
  final player = PlayerController(library: lib, settings: SettingsController(storage), player: audio ?? FakeAudioPlayer(), random: Random(3));
  return (player, lib);
}

/// Lets fire-and-forget playback futures finish.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('playFromList builds the queue at the chosen index', () async {
    final (p, _) = await make();
    final list = [t('a'), t('b'), t('c'), t('d')];
    p.playFromList(list, 2);
    expect(p.queue.map((x) => x.id), ['a', 'b', 'c', 'd']);
    expect(p.queuePos, 2);
    expect(p.currentTrack!.id, 'c');
    p.playFromList(list, 9);
    expect(p.queuePos, 2, reason: 'out of range is ignored');
  });

  test('shuffle keeps the chosen track first and the same members', () async {
    final (p, _) = await make();
    p.shuffle = true;
    final list = [for (var i = 0; i < 12; i++) t('t$i')];
    p.playFromList(list, 5);
    expect(p.queue.first.id, 't5');
    expect(p.queuePos, 0);
    expect(p.queue.map((x) => x.id).toSet(), list.map((x) => x.id).toSet());
    expect(p.queue.map((x) => x.id).toList(), isNot(list.map((x) => x.id).toList()), reason: 'actually shuffled');
  });

  test('toggleShuffle restores the original order around the current track', () async {
    final (p, _) = await make();
    final list = [for (var i = 0; i < 8; i++) t('t$i')];
    p.playFromList(list, 3);
    p.toggleShuffle();
    expect(p.shuffle, isTrue);
    expect(p.queue.first.id, 't3');
    p.toggleShuffle();
    expect(p.shuffle, isFalse);
    expect(p.queue.map((x) => x.id), list.map((x) => x.id));
    expect(p.queuePos, 3);
  });

  test('queue editing', () async {
    final (p, _) = await make();
    p.playFromList([t('a'), t('b'), t('c')], 0);
    expect(p.playNext(t('n')), isTrue);
    expect(p.queue.map((x) => x.id), ['a', 'n', 'b', 'c']);
    expect(p.addToQueue(t('z')), isTrue);
    expect(p.queue.last.id, 'z');

    p.removeFromQueue(0);
    expect(p.queue.first.id, 'a', reason: 'the playing track cannot be removed');
    p.removeFromQueue(1);
    expect(p.queue.map((x) => x.id), ['a', 'b', 'c', 'z']);

    p.queuePos = 2;
    p.removeFromQueue(0);
    expect(p.queuePos, 1, reason: 'position follows the current track');
  });

  test('playNext/addToQueue on an empty queue start playing', () async {
    final (p, _) = await make();
    expect(p.playNext(t('a')), isFalse);
    expect(p.currentTrack!.id, 'a');
    final (q, _) = await make();
    expect(q.addToQueue(t('b')), isFalse);
    expect(q.queue.single.id, 'b');
  });

  test('repeat cycles off -> all -> one -> off', () async {
    final (p, _) = await make();
    expect(p.repeat, RepeatSetting.off);
    p.cycleRepeat();
    expect(p.repeat, RepeatSetting.all);
    p.cycleRepeat();
    expect(p.repeat, RepeatSetting.one);
    p.cycleRepeat();
    expect(p.repeat, RepeatSetting.off);
  });

  test('a track whose audio is missing reports a message instead of crashing', () async {
    final (p, _) = await make();
    final missing = Track(id: 'gone', name: 'Gone', artist: 'A', audioFile: 'nope.mp3');
    p.playFromList([missing], 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(p.isPlaying, isFalse);
    expect(p.takeMessage(), contains('audio is missing'));
    expect(p.takeMessage(), isNull, reason: 'messages are delivered once');
  });

  test('removing the playing track clears the player', () async {
    final (p, lib) = await make();
    final a = lib.addRemoteTrack(t('a', url: 'https://x/a.m4a'))!;
    lib.addRemoteTrack(t('b', url: 'https://x/b.m4a'));
    p.playFromList(lib.tracks.toList(), 0);
    expect(p.currentTrack, isNotNull);
    await lib.removeTrack(a);
    expect(p.currentTrack, isNull);
    expect(p.queue.map((x) => x.id), ['b']);
    expect(p.position.value, Duration.zero);
  });

  test('history records played tracks', () async {
    final (p, lib) = await make();
    p.playFromList([t('a'), t('b')], 1);
    expect(lib.history.first.id, 'b');
  });

  group('playback flow', () {
    test('plays a remote URL, sets duration, volume and speed', () async {
      final audio = FakeAudioPlayer()..loadedDuration = const Duration(seconds: 215);
      final (p, _) = await make(audio: audio);
      p.playFromList([t('a', url: 'https://x/a.m4a')], 0);
      await settle();
      expect(audio.calls, containsAllInOrder(['url:https://x/a.m4a', 'volume:1.0', 'play']));
      expect(p.duration.value, const Duration(seconds: 215));
      expect(p.isPlaying, isTrue);
    });

    test('state stream drives isPlaying and the loading flag', () async {
      final audio = FakeAudioPlayer();
      final (p, _) = await make(audio: audio);
      p.playFromList([t('a', url: 'https://x/a.m4a')], 0);
      await settle();
      audio.emit(playing: true, processing: ProcessingState.buffering);
      await settle();
      expect(p.isLoading, isTrue);
      audio.emit(playing: true);
      await settle();
      expect(p.isLoading, isFalse);
      expect(p.isPlaying, isTrue);
      audio.emit(playing: false);
      await settle();
      expect(p.isPlaying, isFalse);
    });

    test('position stream updates the notifier and the active lyric line', () async {
      final audio = FakeAudioPlayer();
      final (p, _) = await make(audio: audio);
      p.playFromList([t('a', url: 'https://x/a.m4a')], 0);
      await settle();
      p.lyricLines = const [LyricLine(1, 'one'), LyricLine(5, 'two'), LyricLine(9, 'three')];
      audio.pos.add(const Duration(seconds: 6));
      await settle();
      expect(p.position.value, const Duration(seconds: 6));
      expect(p.activeLyricIndex.value, 1);
      audio.pos.add(const Duration(milliseconds: 500));
      await settle();
      expect(p.activeLyricIndex.value, -1, reason: 'before the first line');
    });

    test('completion advances to the next track', () async {
      final audio = FakeAudioPlayer();
      final (p, _) = await make(audio: audio);
      p.playFromList([t('a', url: 'https://x/a.m4a'), t('b', url: 'https://x/b.m4a')], 0);
      await settle();
      audio.emit(playing: false, processing: ProcessingState.completed);
      await settle();
      expect(p.currentTrack!.id, 'b');
      expect(audio.calls.where((c) => c.startsWith('url:')), ['url:https://x/a.m4a', 'url:https://x/b.m4a']);
    });

    test('end of queue stops, repeat all wraps, repeat one restarts', () async {
      final audio = FakeAudioPlayer();
      final (p, _) = await make(audio: audio);
      p.playFromList([t('a', url: 'https://x/a.m4a')], 0);
      await settle();
      await p.nextTrack();
      expect(p.isPlaying, isFalse, reason: 'stopped at the end');
      expect(p.currentTrack!.id, 'a');

      p.cycleRepeat();
      await p.nextTrack();
      await settle();
      expect(audio.calls.where((c) => c.startsWith('url:')).length, 2, reason: 'repeat all reloads the first track');

      p.cycleRepeat();
      audio.calls.clear();
      await p.nextTrack();
      expect(audio.calls, contains('seek:0'));
      expect(audio.calls.any((c) => c.startsWith('url:')), isFalse, reason: 'repeat one only seeks');
    });

    test('previous restarts the track after 3 s, otherwise goes back', () async {
      final audio = FakeAudioPlayer();
      final (p, _) = await make(audio: audio);
      p.playFromList([t('a', url: 'https://x/a.m4a'), t('b', url: 'https://x/b.m4a')], 1);
      await settle();
      p.position.value = const Duration(seconds: 10);
      await p.previousTrack();
      expect(p.currentTrack!.id, 'b');
      expect(audio.calls, contains('seek:0'));
      p.position.value = const Duration(seconds: 1);
      await p.previousTrack();
      await settle();
      expect(p.currentTrack!.id, 'a');
    });

    test('seek clamps to the track length', () async {
      final audio = FakeAudioPlayer()..loadedDuration = const Duration(seconds: 100);
      final (p, _) = await make(audio: audio);
      p.playFromList([t('a', url: 'https://x/a.m4a')], 0);
      await settle();
      await p.seekTo(const Duration(seconds: 500));
      expect(audio.calls.last, 'seek:100000');
      await p.seekTo(const Duration(seconds: -5));
      expect(audio.calls.last, 'seek:0');
    });

    test('load failure is reported and playback stays off', () async {
      final audio = FakeAudioPlayer()..failLoad = true;
      final (p, _) = await make(audio: audio);
      p.playFromList([t('a', url: 'https://x/a.m4a')], 0);
      await settle();
      expect(p.isPlaying, isFalse);
      expect(p.takeMessage(), contains('Could not play'));
    });

    test('volume, mute and speed reach the player', () async {
      final audio = FakeAudioPlayer();
      final (p, _) = await make(audio: audio);
      await p.setVolume(0.4);
      expect(audio.volume, 0.4);
      await p.toggleMute();
      expect(audio.volume, 0);
      await p.setVolume(0.8);
      expect(p.muted, isFalse, reason: 'raising the volume unmutes');
      expect(audio.volume, 0.8);
      await p.setSpeed(1.25);
      expect(audio.speed, 1.25);
      expect(p.speed, 1.25);
    });

    test('togglePlay with nothing loaded starts the library', () async {
      final audio = FakeAudioPlayer();
      final (p, lib) = await make(audio: audio);
      lib.addRemoteTrack(t('a', url: 'https://x/a.m4a'));
      await p.togglePlay();
      await settle();
      expect(p.currentTrack!.id, 'a');
    });
  });

  group('equalizer preset mapping', () {
    final rock = eqPresets['Rock']!;

    test('exact centre frequencies return the preset gain', () {
      for (var i = 0; i < eqBandFrequencies.length; i++) {
        expect(interpolatePreset(rock, eqBandFrequencies[i]), closeTo(rock[i], 1e-9));
      }
    });

    test('in-between frequencies interpolate on a log axis and clamp at the ends', () {
      final mid = interpolatePreset(rock, sqrt(32 * 64));
      expect(mid, closeTo((rock[0] + rock[1]) / 2, 1e-9));
      expect(interpolatePreset(rock, 20), rock.first);
      expect(interpolatePreset(rock, 20000), rock.last);
    });

    test('presets all have ten bands', () {
      for (final e in eqPresets.entries) {
        expect(e.value, hasLength(10), reason: e.key);
      }
    });
  });
}

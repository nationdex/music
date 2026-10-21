import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:adi_music/state/eq_engine.dart';
import 'package:just_audio/just_audio.dart';

/// A just_audio player that records calls and lets a test drive its streams.
class FakeAudioPlayer extends Fake implements AudioPlayer {
  final state = StreamController<PlayerState>.broadcast();
  final pos = StreamController<Duration>.broadcast();
  final dur = StreamController<Duration?>.broadcast();
  final events = StreamController<PlaybackEvent>.broadcast();

  final calls = <String>[];
  Duration? loadedDuration = const Duration(seconds: 100);
  bool failLoad = false;
  @override
  double speed = 1;
  @override
  double volume = 1;

  @override
  Stream<PlayerState> get playerStateStream => state.stream;
  @override
  Stream<Duration> get positionStream => pos.stream;
  @override
  Stream<Duration?> get durationStream => dur.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;

  Future<Duration?> _load(String what) async {
    calls.add(what);
    if (failLoad) throw PlayerException(0, 'load failed', null);
    return loadedDuration;
  }

  @override
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) => _load('file:$filePath');
  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) => _load('url:$url');

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration? position, {int? index}) async =>
      calls.add('seek:${position?.inMilliseconds}');
  @override
  Future<void> setSpeed(double speed) async {
    this.speed = speed;
    calls.add('speed:$speed');
  }

  @override
  Future<void> setPitch(double pitch) async => calls.add('pitch:$pitch');
  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
    calls.add('volume:$volume');
  }

  @override
  Future<void> dispose() async => calls.add('dispose');

  /// Emulates the platform reporting playback state.
  void emit({
    required bool playing,
    ProcessingState processing = ProcessingState.ready,
  }) => state.add(PlayerState(playing, processing));
}

/// Records what the player asks of the device's equalizer.
class FakeEqEngine implements EqEngine {
  @override
  final pipeline = AudioPipeline();
  @override
  double minDb = -15, maxDb = 15;
  List<double> gains = const [];
  bool enabled = true;
  double boost = 0;

  @override
  Future<List<double>?> init() async => const [60, 230, 910, 3600, 14000];
  @override
  Future<void> setBandGains(List<double> g) async => gains = g;
  @override
  Future<void> setEnabled(bool on) async => enabled = on;
  @override
  Future<void> setBoostDb(double db) async => boost = db;
}

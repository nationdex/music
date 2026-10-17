/// Playback: queue, shuffle, repeat, transport, volume, speed, equalizer,
/// lyrics, YouTube tracks and the OS media session. Ported from the playback,
/// equalizer and lyrics sections of site/assets/js/app.js.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt;

import '../core/config.dart';
import '../data/models.dart';
import '../services/lyrics_parser.dart';
import '../services/lyrics_service.dart';
import 'audio_handler.dart';
import 'library_controller.dart';
import 'settings_controller.dart';
import 'youtube_bridge.dart';

enum RepeatSetting { off, all, one }

/// One band of the equalizer as the device reports it.
class EqBand {
  EqBand({required this.frequency, required this.gain, required this.apply});

  final double frequency;
  double gain;
  final Future<void> Function(double gain) apply;

  String get label => frequency >= 1000 ? '${(frequency / 1000).toStringAsFixed(frequency % 1000 == 0 ? 0 : 1)}kHz' : '${frequency.round()}Hz';
}

class PlayerController extends ChangeNotifier implements PlaybackActions {
  PlayerController({
    required this.library,
    required this.settings,
    LyricsService? lyricsService,
    AdiAudioHandler? handler,
    AudioPlayer? player,
    Random? random,
  }) : _lyrics = lyricsService ?? LyricsService(),
       _handler = handler,
       _random = random ?? Random() {
    final eq = Platform.isAndroid ? AndroidEqualizer() : null;
    _androidEq = eq;
    _player = player ?? AudioPlayer(audioPipeline: eq == null ? null : AudioPipeline(androidAudioEffects: [eq]));
    _youtube = YoutubeBridge(onState: _onYouTubeState, onTick: _onYouTubeTick, onError: _onYouTubeError);
    _handler?.bind(this);
    library.onTracksRemoved = _onTracksRemoved;
    volume = settings.settings.volume;
    _listen();
  }

  final LibraryController library;
  final SettingsController settings;
  final LyricsService _lyrics;
  final AdiAudioHandler? _handler;
  final Random _random;

  late final AudioPlayer _player;
  late final YoutubeBridge _youtube;
  AndroidEqualizer? _androidEq;

  ValueListenable<yt.YoutubePlayerController?> get youtubeController => _youtube.controller;

  // ------------------------------------------------------------------ state

  List<Track> queue = [];
  List<Track> _queueOriginal = [];
  int queuePos = -1;

  bool shuffle = false;
  RepeatSetting repeat = RepeatSetting.off;

  Track? currentTrack;
  bool isPlaying = false;
  bool isLoading = false;
  bool ytMode = false;

  /// Position and duration change many times a second, so they are separate
  /// notifiers: only the seek bars and lyrics rebuild on each tick.
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<int> activeLyricIndex = ValueNotifier(-1);

  double volume = 1;
  bool muted = false;
  double speed = 1;

  /// Last error to show as a snackbar; the UI clears it with [takeMessage].
  String? _message;
  String? takeMessage() {
    final m = _message;
    _message = null;
    return m;
  }

  void _say(String message) {
    _message = message;
    notifyListeners();
  }

  // ----------------------------------------------------------------- lyrics

  LyricsStatus lyricsStatus = LyricsStatus.idle;
  List<LyricLine> lyricLines = const [];
  String lyricsContent = '';
  String lyricsProvider = '';
  int _lyricsToken = 0;

  // -------------------------------------------------------------- equalizer

  /// Android only: the OS equalizer, with the bands the device offers.
  List<EqBand> eqBands = const [];
  double eqMinDb = -12, eqMaxDb = 12;
  String eqPreset = 'Flat';
  bool get eqSupported => _androidEq != null && eqBands.isNotEmpty;
  bool get eqPlatformSupported => _androidEq != null;

  // ----------------------------------------------------------------- engine

  int _playToken = 0;
  final List<StreamSubscription<dynamic>> _subs = [];

  void _listen() {
    _subs.add(
      _player.playerStateStream.listen((s) {
        if (ytMode) return;
        final playing = s.playing && s.processingState != ProcessingState.completed;
        final loading = s.processingState == ProcessingState.loading || s.processingState == ProcessingState.buffering;
        if (playing != isPlaying || loading != isLoading) {
          isPlaying = playing;
          isLoading = loading;
          _publishState();
          notifyListeners();
        }
        if (s.processingState == ProcessingState.completed) _onEnded();
      }),
    );
    _subs.add(
      _player.positionStream.listen((p) {
        if (ytMode) return;
        position.value = p;
        _syncLyricHighlight(p.inMilliseconds / 1000);
      }),
    );
    _subs.add(
      _player.durationStream.listen((d) {
        if (ytMode || d == null || d == Duration.zero) return;
        duration.value = d;
        final t = currentTrack;
        if (t != null && t.duration == 0) t.duration = d.inMilliseconds / 1000;
      }),
    );
    _subs.add(
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object e, StackTrace st) {
          if (ytMode || currentTrack == null) return;
          isPlaying = false;
          _say('Could not play “${currentTrack!.name}”');
          _publishState();
        },
      ),
    );
    _initEqualizer();
  }

  Future<void> _initEqualizer() async {
    final eq = _androidEq;
    if (eq == null) return;
    try {
      await eq.setEnabled(true);
      final params = await eq.parameters.timeout(const Duration(seconds: 10));
      eqMinDb = params.minDecibels;
      eqMaxDb = params.maxDecibels;
      eqBands = [for (final b in params.bands) EqBand(frequency: b.centerFrequency, gain: b.gain, apply: b.setGain)];
      notifyListeners();
    } catch (e) {
      debugPrint('Equalizer unavailable: $e');
    }
  }

  // -------------------------------------------------------------- transport

  bool isCurrent(Track? t) => currentTrack != null && t != null && currentTrack!.id == t.id;

  double get timelineFraction {
    final d = duration.value.inMilliseconds;
    return d == 0 ? 0 : (position.value.inMilliseconds / d).clamp(0.0, 1.0);
  }

  void playFromList(List<Track> list, int index) {
    if (index < 0 || index >= list.length) return;
    _queueOriginal = list.toList();
    if (shuffle) {
      final rest = [for (var i = 0; i < list.length; i++) if (i != index) list[i]]..shuffle(_random);
      queue = [list[index], ...rest];
      queuePos = 0;
    } else {
      queue = list.toList();
      queuePos = index;
    }
    playTrack(queue[queuePos]);
  }

  void playShuffled(List<Track> list) {
    if (list.isEmpty) return;
    shuffle = true;
    playFromList(list, _random.nextInt(list.length));
  }

  void playQueueIndex(int i) {
    if (i < 0 || i >= queue.length) return;
    queuePos = i;
    playTrack(queue[i]);
  }

  void removeFromQueue(int i) {
    if (i == queuePos || i < 0 || i >= queue.length) return;
    queue.removeAt(i);
    if (i < queuePos) queuePos -= 1;
    notifyListeners();
  }

  /// Returns true when the track was queued (false: it started playing because the queue was empty).
  bool playNext(Track track) {
    if (queue.isEmpty) {
      playFromList([track], 0);
      return false;
    }
    queue.insert(queuePos + 1, track);
    notifyListeners();
    return true;
  }

  bool addToQueue(Track track) {
    if (queue.isEmpty) {
      playFromList([track], 0);
      return false;
    }
    queue.add(track);
    notifyListeners();
    return true;
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    if (queue.isNotEmpty) {
      final cur = queue[queuePos];
      if (shuffle) {
        _queueOriginal = queue.toList();
        final rest = [for (var i = 0; i < queue.length; i++) if (i != queuePos) queue[i]]..shuffle(_random);
        queue = [cur, ...rest];
        queuePos = 0;
      } else {
        if (_queueOriginal.isNotEmpty) queue = _queueOriginal.toList();
        queuePos = max(0, queue.indexWhere((t) => t.id == cur.id));
      }
    }
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = switch (repeat) {
      RepeatSetting.off => RepeatSetting.all,
      RepeatSetting.all => RepeatSetting.one,
      RepeatSetting.one => RepeatSetting.off,
    };
    notifyListeners();
  }

  Future<void> playTrack(Track track) async {
    final token = ++_playToken;
    currentTrack = track;
    position.value = Duration.zero;
    duration.value = Duration(milliseconds: (track.duration * 1000).round());
    lyricsStatus = LyricsStatus.idle;
    lyricLines = const [];
    lyricsContent = '';
    activeLyricIndex.value = -1;
    isLoading = true;
    library.addToHistory(track);
    notifyListeners();
    _publishItem(track);

    if (track.isYouTube) {
      await _startYouTube(track, token);
    } else {
      await _stopYouTube();
      final Duration? loaded;
      try {
        final path = _audioPath(track);
        if (path != null) {
          loaded = await _player.setFilePath(path);
        } else if (track.url != null) {
          loaded = await _player.setUrl(track.url!);
        } else {
          throw const FileSystemException('Missing audio');
        }
      } catch (e) {
        if (token != _playToken) return;
        isPlaying = false;
        isLoading = false;
        _say(track.isLocal ? 'This track’s audio is missing. Import it again.' : 'Could not play “${track.name}”');
        _publishState();
        return;
      }
      if (token != _playToken) return;
      if (loaded != null && loaded > Duration.zero) duration.value = loaded;
      await _applySpeed();
      await _applyVolume();
      isPlaying = true;
      isLoading = false;
      notifyListeners();
      unawaited(_player.play());
    }
    _publishState();
    unawaited(fetchLyrics());
    unawaited(_updateArtworkAccent(track));
  }

  String? _audioPath(Track t) {
    if (t.audioFile == null) return null;
    final f = library.audioFileFor(t);
    return f != null && f.existsSync() ? f.path : null;
  }

  Future<void> togglePlay() async {
    if (currentTrack == null) {
      final list = library.tracksMatching('');
      if (list.isNotEmpty) playFromList(list, 0);
      return;
    }
    if (ytMode) {
      if (isPlaying) {
        await _youtube.pause();
        isPlaying = false;
      } else {
        await _youtube.play();
        isPlaying = true;
      }
    } else if (isPlaying) {
      await _player.pause();
      isPlaying = false;
    } else {
      isPlaying = true;
      notifyListeners();
      unawaited(_player.play());
    }
    _publishState();
    notifyListeners();
  }

  Future<void> nextTrack() async {
    if (queue.isEmpty) return;
    if (repeat == RepeatSetting.one) {
      await seekTo(Duration.zero);
      if (!isPlaying) await togglePlay();
      return;
    }
    var pos = queuePos + 1;
    if (pos >= queue.length) {
      if (repeat == RepeatSetting.all) {
        pos = 0;
      } else {
        await _stopAtEnd();
        return;
      }
    }
    queuePos = pos;
    await playTrack(queue[pos]);
  }

  Future<void> previousTrack() async {
    if (queue.isEmpty) return;
    if (position.value.inSeconds > 3) {
      await seekTo(Duration.zero);
      return;
    }
    var pos = queuePos - 1;
    if (pos < 0) pos = repeat == RepeatSetting.all ? queue.length - 1 : 0;
    queuePos = pos;
    await playTrack(queue[pos]);
  }

  Future<void> _stopAtEnd() async {
    isPlaying = false;
    if (ytMode) {
      await _youtube.pause();
    } else {
      await _player.pause();
    }
    await seekTo(Duration.zero);
    _publishState();
    notifyListeners();
  }

  void _onEnded() => unawaited(nextTrack());

  Future<void> seekTo(Duration to) async {
    final d = duration.value;
    if (d > Duration.zero && to > d) to = d;
    if (to < Duration.zero) to = Duration.zero;
    if (ytMode) {
      await _youtube.seek(to.inMilliseconds / 1000);
    } else {
      await _player.seek(to);
    }
    position.value = to;
    _syncLyricHighlight(to.inMilliseconds / 1000);
    _publishState();
  }

  Future<void> seekToLine(LyricLine line) => seekTo(Duration(milliseconds: (line.t * 1000).round()));

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    if (muted && volume > 0) muted = false;
    await _applyVolume();
    await settings.setVolume(volume);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    muted = !muted;
    await _applyVolume();
    notifyListeners();
  }

  Future<void> _applyVolume() async {
    await _player.setVolume(muted ? 0 : volume);
    await _youtube.setVolume(muted ? 0 : volume);
    await _youtube.setMuted(muted);
  }

  Future<void> setSpeed(double s) async {
    speed = (s * 100).round() / 100;
    await _applySpeed();
    _publishState();
    notifyListeners();
  }

  /// Applies speed and, when "preserve pitch" is off, shifts pitch with it. Pitch
  /// control exists only on Android; iOS always preserves pitch.
  Future<void> applyPlaybackSettings() => _applySpeed();

  Future<void> _applySpeed() async {
    try {
      await _player.setSpeed(speed);
      if (Platform.isAndroid) await _player.setPitch(settings.settings.preservePitch ? 1 : speed);
    } catch (e) {
      debugPrint('Speed not applied: $e');
    }
  }

  // ---------------------------------------------------------------- YouTube

  Future<void> _startYouTube(Track track, int token) async {
    await _player.pause();
    ytMode = true;
    isPlaying = true;
    notifyListeners();
    try {
      await _youtube.loadVideo(track.videoId!);
      if (!ytMode || token != _playToken) return;
      await _youtube.setVolume(muted ? 0 : volume);
      isLoading = false;
    } catch (e) {
      debugPrint('YouTube playback failed: $e');
      _onYouTubeError('$e');
    }
  }

  Future<void> _stopYouTube() async {
    if (!ytMode) return;
    await _youtube.stop();
    ytMode = false;
  }

  void _onYouTubeState(yt.PlayerState state) {
    if (!ytMode) return;
    switch (state) {
      case yt.PlayerState.playing:
        isPlaying = true;
        isLoading = false;
      case yt.PlayerState.paused:
        isPlaying = false;
      case yt.PlayerState.ended:
        _onEnded();
        return;
      default:
        return;
    }
    _publishState();
    notifyListeners();
  }

  void _onYouTubeTick(double t, double d) {
    if (!ytMode) return;
    position.value = Duration(milliseconds: (t * 1000).round());
    if (d > 0 && duration.value.inMilliseconds != (d * 1000).round()) duration.value = Duration(milliseconds: (d * 1000).round());
    _syncLyricHighlight(t);
  }

  /// Error 101 and 150 both mean the uploader blocked embedding. Skip to the next track
  /// rather than stopping the queue.
  void _onYouTubeError(String reason) {
    final blockedByOwner = reason == '101' || reason == '150';
    ytMode = false;
    isPlaying = false;
    isLoading = false;
    if (blockedByOwner && queue.length > 1 && repeat != RepeatSetting.one) {
      _say('Skipped: the uploader does not allow this video to play outside YouTube.');
      unawaited(nextTrack());
      return;
    }
    _say(blockedByOwner ? 'The uploader does not allow this video to play outside YouTube.' : 'This video cannot be played here ($reason)');
    _publishState();
  }

  // ----------------------------------------------------------------- lyrics

  void _syncLyricHighlight(double now) {
    if (lyricLines.isEmpty) {
      if (activeLyricIndex.value != -1) activeLyricIndex.value = -1;
      return;
    }
    var idx = -1;
    for (var i = 0; i < lyricLines.length; i++) {
      if (lyricLines[i].t <= now) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx != activeLyricIndex.value) activeLyricIndex.value = idx;
  }

  void _applyLyrics(LyricsRecord data) {
    lyricsProvider = data.provider ?? data.source;
    var parsed = parseLrc(data.synced);
    if (parsed.isEmpty && data.ttml != null) parsed = parseTtml(data.ttml);
    final plain = data.plain ?? '';
    if (parsed.isNotEmpty) {
      lyricLines = parsed;
      lyricsContent = parsed.map((l) => l.text).join('\n');
    } else {
      lyricLines = const [];
      lyricsContent = plain;
    }
    lyricsStatus = lyricLines.isNotEmpty ? LyricsStatus.synced : (plain.isNotEmpty ? LyricsStatus.plain : LyricsStatus.none);
    _syncLyricHighlight(position.value.inMilliseconds / 1000);
  }

  Future<void> fetchLyrics() async {
    final track = currentTrack;
    if (track == null || track.name.isEmpty) return;
    final token = ++_lyricsToken;
    lyricsStatus = LyricsStatus.loading;
    lyricsContent = '';
    lyricLines = const [];
    activeLyricIndex.value = -1;
    notifyListeners();
    final record = await _lyrics.resolve(
      LyricsQuery(
        title: track.name,
        artist: track.artist,
        album: track.album,
        duration: duration.value.inMilliseconds > 0 ? duration.value.inMilliseconds / 1000 : track.duration,
        prefer: settings.settings.lyricsPrefer,
        provider: settings.settings.lyricsProvider,
      ),
    );
    if (token != _lyricsToken || currentTrack != track) return;
    if (record != null) {
      _applyLyrics(record);
    } else {
      lyricsStatus = LyricsStatus.none;
      lyricsContent = '';
    }
    notifyListeners();
  }

  // --------------------------------------------------------------- equalizer

  Future<void> setEqBand(int index, double gain) async {
    if (index < 0 || index >= eqBands.length) return;
    final g = gain.clamp(eqMinDb, eqMaxDb).toDouble();
    eqBands[index].gain = g;
    await eqBands[index].apply(g);
    notifyListeners();
  }

  /// Maps the 10-band preset onto the device's bands by interpolating on a log-frequency axis.
  Future<void> applyEqPreset(String name) async {
    eqPreset = name;
    final gains = eqPresets[name] ?? eqPresets['Flat']!;
    for (var i = 0; i < eqBands.length; i++) {
      await setEqBand(i, interpolatePreset(gains, eqBands[i].frequency));
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- media session

  Uri? _artUri(Track t) {
    if (t.artworkFile != null) {
      final f = library.artworkFileFor(t);
      if (f != null) return f.uri;
    }
    return t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null;
  }

  void _publishItem(Track t) => _handler?.publishItem(
    id: t.id,
    title: t.name,
    artist: t.artist,
    album: t.album,
    duration: t.duration > 0 ? Duration(milliseconds: (t.duration * 1000).round()) : null,
    artUri: _artUri(t),
  );

  void _publishState() => _handler?.publishState(playing: isPlaying, loading: isLoading, position: position.value, speed: ytMode ? 1 : speed);

  @override
  Future<void> remotePlay() async {
    if (!isPlaying) await togglePlay();
  }

  @override
  Future<void> remotePause() async {
    if (isPlaying) await togglePlay();
  }

  @override
  Future<void> remoteStop() async {
    if (isPlaying) await togglePlay();
  }

  @override
  Future<void> remoteNext() => nextTrack();

  @override
  Future<void> remotePrevious() => previousTrack();

  @override
  Future<void> remoteSeek(Duration p) => seekTo(p);

  // ---------------------------------------------------------------- artwork

  Future<Uint8List?> _artworkBytes(Track t) async {
    try {
      final f = library.artworkFileFor(t);
      if (f != null && await f.exists()) return await f.readAsBytes();
      if (t.artworkUrl != null && t.artworkUrl!.isNotEmpty) {
        final res = await http.get(Uri.parse(t.artworkUrl!)).timeout(const Duration(seconds: 10));
        return res.statusCode == 200 ? res.bodyBytes : null;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _updateArtworkAccent(Track track) async {
    if (!settings.settings.pickColorFromArtwork) return;
    final bytes = await _artworkBytes(track);
    if (currentTrack == track) await settings.setArtworkAccentFromBytes(bytes);
  }

  // ----------------------------------------------------------------- removal

  void _onTracksRemoved(Set<String> ids) {
    queue.removeWhere((t) => ids.contains(t.id));
    _queueOriginal.removeWhere((t) => ids.contains(t.id));
    queuePos = queue.isEmpty ? -1 : queuePos.clamp(0, queue.length - 1);
    if (currentTrack != null && ids.contains(currentTrack!.id)) {
      _playToken++;
      unawaited(_player.stop());
      unawaited(_stopYouTube());
      currentTrack = null;
      isPlaying = false;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      lyricLines = const [];
      lyricsStatus = LyricsStatus.idle;
      _handler?.clearItem();
      _handler?.publishIdle();
      settings.clearArtworkAccent();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _youtube.dispose();
    position.dispose();
    duration.dispose();
    activeLyricIndex.dispose();
    super.dispose();
  }
}

/// Gain for [frequency] from a 10-band preset, interpolated linearly in log-frequency.
@visibleForTesting
double interpolatePreset(List<double> gains, double frequency) {
  final f = eqBandFrequencies;
  if (frequency <= f.first) return gains.first;
  if (frequency >= f.last) return gains.last;
  for (var i = 0; i < f.length - 1; i++) {
    if (frequency <= f[i + 1]) {
      final t = (log(frequency) - log(f[i])) / (log(f[i + 1]) - log(f[i]));
      return gains[i] + (gains[i + 1] - gains[i]) * t;
    }
  }
  return gains.last;
}

/// YouTube IFrame Player bridge. Full-length tracks play inside YouTube's own
/// iframe (a WebView), exactly like the web build; the equalizer and just_audio
/// do not apply to them. Ported from `YTBridge` in site/assets/js/sources.js.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class YoutubeBridge {
  YoutubeBridge({required this.onState, required this.onTick, required this.onError});

  /// Raw YouTube player state code: 1 playing, 2 paused, 0 ended.
  final void Function(PlayerState state) onState;
  final void Function(double position, double duration) onTick;
  final void Function(String reason) onError;

  /// Mounted by the app root as a hidden 1x1 widget once a YouTube track is first played.
  final ValueNotifier<YoutubePlayerController?> controller = ValueNotifier(null);

  StreamSubscription<YoutubePlayerValue>? _valueSub;
  StreamSubscription<YoutubeVideoState>? _stateSub;
  double _duration = 0;

  YoutubePlayerController _ensure() {
    final existing = controller.value;
    if (existing != null) return existing;
    final c = YoutubePlayerController(
      params: const YoutubePlayerParams(showControls: false, showFullscreenButton: false, enableKeyboard: false, playsInline: true),
    );
    _valueSub = c.stream.listen((v) {
      if (v.metaData.duration.inMilliseconds > 0) _duration = v.metaData.duration.inMilliseconds / 1000;
      if (v.error != YoutubeError.none) {
        onError('${v.error.code}');
        return;
      }
      onState(v.playerState);
    });
    _stateSub = c.videoStateStream.listen((s) => onTick(s.position.inMilliseconds / 1000, _duration));
    controller.value = c;
    return c;
  }

  Future<void> loadVideo(String videoId) async {
    _duration = 0;
    await _ensure().loadVideoById(videoId: videoId);
  }

  Future<void> play() async => controller.value?.playVideo();
  Future<void> pause() async => controller.value?.pauseVideo();
  Future<void> stop() async => controller.value?.stopVideo();
  Future<void> seek(double seconds) async => controller.value?.seekTo(seconds: seconds, allowSeekAhead: true);
  Future<void> setVolume(double volume) async => controller.value?.setVolume((volume * 100).round());
  Future<void> setMuted(bool muted) async => muted ? controller.value?.mute() : controller.value?.unMute();

  Future<void> dispose() async {
    await _valueSub?.cancel();
    await _stateSub?.cancel();
    await controller.value?.close();
    controller.dispose();
  }
}

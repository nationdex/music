/// Bridges the player to the OS media session (Android media notification and
/// lock screen, iOS Control Center and lock screen, headset buttons, Bluetooth
/// and car controls). Replaces the web build's Media Session API code.
library;

import 'package:audio_service/audio_service.dart';

/// What the OS can ask of the player. Implemented by `PlayerController`.
abstract interface class PlaybackActions {
  Future<void> remotePlay();
  Future<void> remotePause();
  Future<void> remoteStop();
  Future<void> remoteNext();
  Future<void> remotePrevious();
  Future<void> remoteSeek(Duration position);
}

class AdiAudioHandler extends BaseAudioHandler with SeekHandler {
  PlaybackActions? _actions;

  void bind(PlaybackActions actions) => _actions = actions;

  /// Publishes what is playing. Called when the track changes.
  void publishItem({required String id, required String title, required String artist, required String album, Duration? duration, Uri? artUri}) {
    mediaItem.add(MediaItem(id: id, title: title, artist: artist, album: album, duration: duration, artUri: artUri));
  }

  void clearItem() => mediaItem.add(null);

  /// Publishes transport state. The OS extrapolates the position from
  /// [position] and [speed], so this is only called on state changes.
  void publishState({required bool playing, required bool loading, required Duration position, required double speed}) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: loading ? AudioProcessingState.loading : AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
        speed: speed,
      ),
    );
  }

  void publishIdle() {
    playbackState.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
  }

  @override
  Future<void> play() async => _actions?.remotePlay();

  @override
  Future<void> pause() async => _actions?.remotePause();

  @override
  Future<void> stop() async {
    await _actions?.remoteStop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => _actions?.remoteNext();

  @override
  Future<void> skipToPrevious() async => _actions?.remotePrevious();

  @override
  Future<void> seek(Duration position) async => _actions?.remoteSeek(position);
}

/// The part of the equalizer that talks to the operating system. Android has an audio effect for it
/// (through just_audio); iOS does not let apps process the system player's audio, so there it is null.
library;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

abstract class EqEngine {
  /// Effects to hand to just_audio when it is created.
  AudioPipeline get pipeline;

  /// Center frequencies (Hz) of the bands the device offers, or null when it has no equalizer.
  Future<List<double>?> init();

  double get minDb;
  double get maxDb;

  /// One gain (dB) per device band, in the order [init] returned them.
  Future<void> setBandGains(List<double> gains);

  /// Off means the effect is bypassed entirely.
  Future<void> setEnabled(bool enabled);

  /// Extra loudness in dB (0 to 12), for when the preamp is above zero.
  Future<void> setBoostDb(double db);
}

class AndroidEqEngine implements EqEngine {
  AndroidEqEngine()
    : _eq = AndroidEqualizer(),
      _loudness = AndroidLoudnessEnhancer() {
    pipeline = AudioPipeline(androidAudioEffects: [_eq, _loudness]);
  }

  final AndroidEqualizer _eq;
  final AndroidLoudnessEnhancer _loudness;
  List<AndroidEqualizerBand> _bands = const [];

  @override
  late final AudioPipeline pipeline;

  @override
  double minDb = -12, maxDb = 12;

  @override
  Future<List<double>?> init() async {
    try {
      await _eq.setEnabled(true);
      final params = await _eq.parameters.timeout(const Duration(seconds: 10));
      minDb = params.minDecibels;
      maxDb = params.maxDecibels;
      _bands = params.bands;
      return [for (final b in _bands) b.centerFrequency];
    } catch (e) {
      debugPrint('Equalizer unavailable: $e');
      return null;
    }
  }

  @override
  Future<void> setBandGains(List<double> gains) async {
    for (var i = 0; i < _bands.length && i < gains.length; i++) {
      await _bands[i].setGain(gains[i].clamp(minDb, maxDb).toDouble());
    }
  }

  @override
  Future<void> setEnabled(bool enabled) => _eq.setEnabled(enabled);

  @override
  Future<void> setBoostDb(double db) async {
    try {
      await _loudness.setEnabled(db > 0);
      await _loudness.setTargetGain(db);
    } catch (e) {
      debugPrint('Loudness boost unavailable: $e');
    }
  }
}

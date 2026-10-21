/// Equalizer presets, state and the response-curve maths. Ported from site/assets/js/eq.js: keep the
/// two in step (the tests compare both against the same reference numbers).
library;

import 'dart:math' as math;

const eqFrequencies = <double>[
  32,
  64,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];
const eqLabels = [
  '32Hz',
  '64Hz',
  '125Hz',
  '250Hz',
  '500Hz',
  '1kHz',
  '2kHz',
  '4kHz',
  '8kHz',
  '16kHz',
];
const eqRange = 12.0; // dB, either side
const eqQ = 1.4;
const eqMaxCustom = 20;

/// Gains in dB for the ten bands above.
const eqPresets = <String, List<double>>{
  'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Bass Boost': [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
  'Bass Reducer': [-6, -5, -4, -2, -1, 0, 0, 0, 0, 0],
  'Treble Boost': [-1, -1, 0, 0, 1, 2, 4, 6, 7, 8],
  'Treble Reducer': [0, 0, 0, 0, 0, -1, -3, -5, -6, -7],
  'Vocal': [-2, -1, 1, 3, 4, 4, 3, 1, 0, -1],
  'Podcast': [-4, -3, -1, 2, 4, 4, 3, 1, -1, -3],
  'Acoustic': [4, 4, 3, 1, 1, 1, 2, 3, 3, 2],
  'Classical': [4, 3, 3, 2, -1, -1, 0, 2, 3, 3],
  'Jazz': [3, 2, 1, 2, -1, -1, 0, 1, 2, 3],
  'Pop': [-1, 1, 3, 4, 3, 0, -1, -1, -1, -1],
  'Rock': [5, 4, 2, -1, -2, 0, 2, 4, 5, 6],
  'Hip-Hop': [5, 4, 2, 3, -1, -1, 2, 0, 2, 3],
  'Dance': [6, 5, 3, 0, 1, 3, 4, 3, 2, 0],
  'Electronic': [6, 5, 2, 0, -2, 2, 1, 3, 5, 6],
  'Loudness': [6, 4, 0, 0, -1, 0, -1, -4, 5, 1],
  'Late Night': [2, 2, 1, 0, 0, -1, -2, -3, -3, -3],
};

double clampDb(num v) => v.isFinite ? v.clamp(-eqRange, eqRange).toDouble() : 0;
double dbToGain(double db) => math.pow(10, db / 20).toDouble();

/// Headroom: boosting a band can push the signal past full scale, so the preamp drops by the largest boost.
double autoPreamp(List<double> gains) => -math.max(0.0, gains.reduce(math.max));

class EqState {
  EqState({
    this.enabled = true,
    this.preset = 'Flat',
    List<double>? gains,
    this.preamp = 0,
    this.auto = true,
    Map<String, List<double>>? custom,
  }) : gains = gains ?? List.of(eqPresets['Flat']!),
       custom = custom ?? {};

  bool enabled;
  String preset;
  List<double> gains;
  double preamp;
  bool auto;
  Map<String, List<double>> custom;

  EqState copy() => EqState(
    enabled: enabled,
    preset: preset,
    gains: List.of(gains),
    preamp: preamp,
    auto: auto,
    custom: {for (final e in custom.entries) e.key: List.of(e.value)},
  );

  /// The preamp in dB that is actually applied (0 while bypassed).
  double get effectivePreamp =>
      enabled ? (auto ? autoPreamp(gains) : preamp) : 0;

  /// True when the equalizer would change the sound at all.
  bool get isActive =>
      enabled && (gains.any((g) => g != 0) || (!auto && preamp != 0));

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'preset': preset,
    'gains': gains,
    'preamp': preamp,
    'auto': auto,
    'custom': custom,
  };

  /// Repairs whatever was stored, so the rest of the code can trust its shape.
  factory EqState.fromJson(Object? raw) {
    if (raw is! Map) return EqState();
    List<double>? bands(Object? v) =>
        v is List && v.length == eqFrequencies.length
        ? [for (final x in v) clampDb(x is num ? x : 0)]
        : null;
    final custom = <String, List<double>>{};
    final c = raw['custom'];
    if (c is Map) {
      for (final e in c.entries) {
        final g = bands(e.value);
        if (e.key is String && g != null && !eqPresets.containsKey(e.key)) {
          custom[e.key as String] = g;
        }
      }
    }
    final p = raw['preamp'];
    return EqState(
      enabled: raw['enabled'] != false,
      preset: raw['preset'] is String ? raw['preset'] as String : 'Custom',
      gains: bands(raw['gains']),
      preamp: p is num ? clampDb(p) : 0,
      auto: raw['auto'] != false,
      custom: custom,
    );
  }

  /// Name of the preset whose gains equal [gains], or 'Custom'. Custom presets count too.
  String matchPreset() {
    bool same(List<double> a) {
      for (var i = 0; i < a.length; i++) {
        if (a[i] != gains[i]) return false;
      }
      return a.length == gains.length;
    }

    for (final e in eqPresets.entries) {
      if (same(e.value)) return e.key;
    }
    for (final e in custom.entries) {
      if (same(e.value)) return e.key;
    }
    return 'Custom';
  }
}

/// Gain for [frequency] from the ten band gains, interpolated linearly in log-frequency. Used to
/// map the ten-band curve onto the bands a device's equalizer offers.
double interpolateGains(List<double> gains, double frequency) {
  const f = eqFrequencies;
  if (frequency <= f.first) return gains.first;
  if (frequency >= f.last) return gains.last;
  for (var i = 0; i < f.length - 1; i++) {
    if (frequency <= f[i + 1]) {
      final t =
          (math.log(frequency) - math.log(f[i])) /
          (math.log(f[i + 1]) - math.log(f[i]));
      return gains[i] + (gains[i + 1] - gains[i]) * t;
    }
  }
  return gains.last;
}

// --------------------------------------------------------------- response curve
// RBJ "Audio EQ Cookbook" biquads, the same filters Web Audio uses.

List<double> _coefficients(int band, double db, double fs) {
  final type = band == 0
      ? 'lowshelf'
      : (band == eqFrequencies.length - 1 ? 'highshelf' : 'peaking');
  final a = math.pow(10, db / 40).toDouble();
  final w0 = 2 * math.pi * eqFrequencies[band] / fs;
  final cos = math.cos(w0), sin = math.sin(w0);
  if (type == 'peaking') {
    final alpha = sin / (2 * eqQ);
    return [
      1 + alpha * a,
      -2 * cos,
      1 - alpha * a,
      1 + alpha / a,
      -2 * cos,
      1 - alpha / a,
    ];
  }
  final alpha = sin / 2 * math.sqrt2; // shelf slope S = 1
  final k = 2 * math.sqrt(a) * alpha;
  if (type == 'lowshelf') {
    return [
      a * (a + 1 - (a - 1) * cos + k),
      2 * a * (a - 1 - (a + 1) * cos),
      a * (a + 1 - (a - 1) * cos - k),
      a + 1 + (a - 1) * cos + k,
      -2 * (a - 1 + (a + 1) * cos),
      a + 1 + (a - 1) * cos - k,
    ];
  }
  return [
    a * (a + 1 + (a - 1) * cos + k),
    -2 * a * (a - 1 + (a + 1) * cos),
    a * (a + 1 + (a - 1) * cos - k),
    a + 1 - (a - 1) * cos + k,
    2 * (a - 1 - (a + 1) * cos),
    a + 1 - (a - 1) * cos - k,
  ];
}

double _magnitude(List<double> c, double w) {
  final c1 = math.cos(w),
      s1 = math.sin(w),
      c2 = math.cos(2 * w),
      s2 = math.sin(2 * w);
  final nr = c[0] + c[1] * c1 + c[2] * c2, ni = -(c[1] * s1 + c[2] * s2);
  final dr = c[3] + c[4] * c1 + c[5] * c2, di = -(c[4] * s1 + c[5] * s2);
  return math.sqrt((nr * nr + ni * ni) / (dr * dr + di * di));
}

/// Combined response in dB of the ten bands (plus [preamp] dB) at each frequency in [freqs].
List<double> responseDb(
  List<double> gains,
  List<double> freqs, {
  double preamp = 0,
  double fs = 44100,
}) {
  final filters = [
    for (var i = 0; i < eqFrequencies.length; i++)
      _coefficients(i, i < gains.length ? gains[i] : 0, fs),
  ];
  return [
    for (final hz in freqs)
      () {
        final w = 2 * math.pi * hz / fs;
        var mag = 1.0;
        for (final c in filters) {
          mag *= _magnitude(c, w);
        }
        return 20 * math.log(mag) / math.ln10 + preamp;
      }(),
  ];
}

/// [count] frequencies spaced evenly on a log axis from [lo] to [hi] Hz.
List<double> logFreqs({int count = 96, double lo = 20, double hi = 20000}) => [
  for (var i = 0; i < count; i++)
    lo * math.pow(hi / lo, i / (count - 1)).toDouble(),
];

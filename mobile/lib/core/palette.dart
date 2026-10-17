/// Material 3 palette. Ported from site/assets/js/palette.js and the tokens in
/// site/assets/app.css: the same light/dark pairs, and the same re-hue for a
/// custom accent or the current cover art.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Token name -> (light, dark).
const Map<String, (int, int)> defaultTokens = {
  'primary': (0xFFC0000C, 0xFFFFB4AA),
  'onPrimary': (0xFFFFFFFF, 0xFF690003),
  'primaryContainer': (0xFFFFDAD5, 0xFF930006),
  'onPrimaryContainer': (0xFF410001, 0xFFFFDAD5),
  'secondary': (0xFF80543E, 0xFFF4B99F),
  'onSecondary': (0xFFFFFFFF, 0xFF4B2715),
  'secondaryContainer': (0xFFFFDBCC, 0xFF653D29),
  'onSecondaryContainer': (0xFF311304, 0xFFFFDBCC),
  'tertiary': (0xFF845325, 0xFFFAB981),
  'onTertiary': (0xFFFFFFFF, 0xFF4C2700),
  'tertiaryContainer': (0xFFFFDCC1, 0xFF683C0F),
  'onTertiaryContainer': (0xFF2E1500, 0xFFFFDCC1),
  'surface': (0xFFFFF8F7, 0xFF271816),
  'onSurface': (0xFF271816, 0xFFF9DCD8),
  'surfaceVariant': (0xFFFDDBD6, 0xFF58413E),
  'onSurfaceVariant': (0xFF58413E, 0xFFDFBFBB),
  'surfaceContainerHighest': (0xFFF9DCD8, 0xFF42302E),
  'surfaceContainerHigh': (0xFFFFE2DE, 0xFF372624),
  'surfaceContainer': (0xFFFFE9E6, 0xFF2B1C1A),
  'surfaceContainerLow': (0xFFFFF0EE, 0xFF271816),
  'surfaceContainerLowest': (0xFFFFFFFF, 0xFF180B09),
  'outline': (0xFF8C716D, 0xFFA78A86),
  'outlineVariant': (0xFFDFBFBB, 0xFF58413E),
  'inverseSurface': (0xFF3D2C2A, 0xFFF9DCD8),
  'onInverseSurface': (0xFFFFEDEA, 0xFF271816),
  'inversePrimary': (0xFFFFB4AA, 0xFFC0000C),
};

/// Hue of the built-in dark primary (#ffb4aa).
const double defaultSeedHue = 6;

const _error = (0xFFBA1A1A, 0xFFFFB4AB);
const _onError = (0xFFFFFFFF, 0xFF690005);
const _errorContainer = (0xFFFFDAD6, 0xFF93000A);
const _onErrorContainer = (0xFF410002, 0xFFFFDAD6);

class Hsl {
  const Hsl(this.h, this.s, this.l);

  /// Degrees, 0..360.
  final double h;

  /// Percent, 0..100.
  final double s;

  /// Percent, 0..100.
  final double l;
}

Hsl colorToHsl(Color c) {
  final r = c.r, g = c.g, b = c.b;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2;
  double h = 0, s = 0;
  if (mx != mn) {
    final d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h *= 60;
  }
  return Hsl(h, s * 100, l * 100);
}

Color hslToColor(double h, double s, double l) {
  h = ((h % 360) + 360) % 360;
  s = s.clamp(0, 100) / 100;
  l = l.clamp(0, 100) / 100;
  final a = s * math.min(l, 1 - l);
  double f(int n) {
    final k = (n + h / 30) % 12;
    return l - a * math.max(-1, math.min(math.min(k - 3, 9 - k), 1));
  }

  return Color.from(alpha: 1, red: f(0), green: f(8), blue: f(4));
}

Color rotateColor(Color c, double delta) {
  final hsl = colorToHsl(c);
  return hslToColor(hsl.h + delta, hsl.s, hsl.l);
}

/// Parses `#rrggbb` (the `#` is optional). Returns null on anything else.
Color? parseHex(String? hex) {
  if (hex == null) return null;
  final t = hex.trim().replaceFirst('#', '');
  if (t.length != 6) return null;
  final n = int.tryParse(t, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}

String colorToHex(Color c) {
  String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}';
}

/// The Material 3 color scheme for [brightness]. With [accent] set, every token
/// is rotated by the hue distance between the accent and the built-in primary.
ColorScheme buildColorScheme(Brightness brightness, {Color? accent}) {
  final dark = brightness == Brightness.dark;
  final delta = accent == null ? 0.0 : colorToHsl(accent).h - defaultSeedHue;

  Color pick((int, int) pair) {
    final c = Color(dark ? pair.$2 : pair.$1);
    return accent == null ? c : rotateColor(c, delta);
  }

  Color t(String name) => pick(defaultTokens[name]!);
  // Error colors keep their own hue so a green accent never turns errors green.
  Color fixed((int, int) pair) => Color(dark ? pair.$2 : pair.$1);

  return ColorScheme(
    brightness: brightness,
    primary: t('primary'),
    onPrimary: t('onPrimary'),
    primaryContainer: t('primaryContainer'),
    onPrimaryContainer: t('onPrimaryContainer'),
    secondary: t('secondary'),
    onSecondary: t('onSecondary'),
    secondaryContainer: t('secondaryContainer'),
    onSecondaryContainer: t('onSecondaryContainer'),
    tertiary: t('tertiary'),
    onTertiary: t('onTertiary'),
    tertiaryContainer: t('tertiaryContainer'),
    onTertiaryContainer: t('onTertiaryContainer'),
    error: fixed(_error),
    onError: fixed(_onError),
    errorContainer: fixed(_errorContainer),
    onErrorContainer: fixed(_onErrorContainer),
    surface: t('surface'),
    onSurface: t('onSurface'),
    surfaceDim: t('surfaceContainerLow'),
    surfaceBright: t('surfaceContainerHighest'),
    surfaceContainerLowest: t('surfaceContainerLowest'),
    surfaceContainerLow: t('surfaceContainerLow'),
    surfaceContainer: t('surfaceContainer'),
    surfaceContainerHigh: t('surfaceContainerHigh'),
    surfaceContainerHighest: t('surfaceContainerHighest'),
    onSurfaceVariant: t('onSurfaceVariant'),
    outline: t('outline'),
    outlineVariant: t('outlineVariant'),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: t('inverseSurface'),
    onInverseSurface: t('onInverseSurface'),
    inversePrimary: t('inversePrimary'),
    surfaceTint: t('primary'),
  );
}

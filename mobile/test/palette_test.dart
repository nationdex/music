import 'dart:ui';

import 'package:adi_music/core/format.dart';
import 'package:adi_music/core/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('built-in scheme uses the web build tokens', () {
    final light = buildColorScheme(Brightness.light);
    final dark = buildColorScheme(Brightness.dark);
    expect(light.primary, const Color(0xFFC0000C));
    expect(dark.primary, const Color(0xFFFFB4AA));
    expect(dark.surface, const Color(0xFF271816));
    expect(light.surfaceContainerHigh, const Color(0xFFFFE2DE));
    expect(dark.inverseSurface, const Color(0xFFF9DCD8));
  });

  test('default seed hue is the dark primary hue', () {
    expect(colorToHsl(const Color(0xFFFFB4AA)).h, closeTo(defaultSeedHue, 1.5));
  });

  test('hex parsing and formatting round-trip', () {
    expect(parseHex('#c0000c'), const Color(0xFFC0000C));
    expect(parseHex('c0000c'), const Color(0xFFC0000C));
    expect(parseHex('#fff'), isNull);
    expect(parseHex('zzzzzz'), isNull);
    expect(parseHex(null), isNull);
    expect(colorToHex(const Color(0xFF0A1B2C)), '#0a1b2c');
  });

  test('a custom accent re-hues tokens and keeps lightness and saturation', () {
    const accent = Color(0xFF2E7D32); // green
    final scheme = buildColorScheme(Brightness.dark, accent: accent);
    final base = buildColorScheme(Brightness.dark);
    final delta = colorToHsl(accent).h - defaultSeedHue;

    final a = colorToHsl(base.primary), b = colorToHsl(scheme.primary);
    expect(b.h, closeTo((a.h + delta) % 360, 1.5));
    expect(b.l, closeTo(a.l, 1.0));
    expect(b.s, closeTo(a.s, 1.5));
    // Errors keep their own colour so a green accent never turns them green.
    expect(scheme.error, base.error);
  });

  test('rotating by 360 degrees is the identity', () {
    const c = Color(0xFFC0000C);
    final r = rotateColor(c, 360);
    expect((r.r * 255).round(), (c.r * 255).round());
    expect((r.g * 255).round(), (c.g * 255).round());
    expect((r.b * 255).round(), (c.b * 255).round());
  });

  group('format helpers', () {
    test('formatTime matches the web build', () {
      expect(formatTime(0), '00:00');
      expect(formatTime(83.9), '01:23');
      expect(formatTime(3725), '1:02:05');
      expect(formatTime(null), '00:00');
      expect(formatTime(-3), '00:00');
      expect(formatTime(double.nan), '00:00');
    });

    test('slugId equals the web build for the same input', () {
      // Reference values computed with site/assets/js/util.js.
      expect(slugId('abc'), '3772q3');
      expect(slugId('Afterglow\u0000Neon Harbor'), '1dkj51a');
      expect(slugId('Ünïcode ☃'), 'q2jl8c');
    });

    test('plural', () {
      expect(plural(1, 'track'), '1 track');
      expect(plural(2, 'track'), '2 tracks');
      expect(plural(0, 'album'), '0 albums');
    });
  });
}

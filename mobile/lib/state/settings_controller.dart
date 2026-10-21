/// Settings and theming state. Ported from the settings and theme parts of
/// site/assets/js/app.js (`applyTheme`, `effectiveAccent`, `extractArtworkColor`).
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/eq_math.dart';
import '../core/palette.dart';
import '../data/settings.dart';
import '../data/storage.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._storage) : settings = _storage.readSettings();

  final Storage _storage;
  AppSettings settings;

  /// Colour of the current cover art. Wins over the manual accent when enabled.
  Color? _artworkAccent;

  ThemeMode get themeMode => switch (settings.theme) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };

  /// Reduced motion by setting, or by the OS when set to auto (the platform
  /// reports it through `MediaQuery.disableAnimations`).
  bool reducedMotion(BuildContext context) => switch (settings.motion) {
    'reduced' => true,
    'full' => false,
    _ => MediaQuery.disableAnimationsOf(context),
  };

  Color? get effectiveAccent {
    if (settings.pickColorFromArtwork && _artworkAccent != null) {
      return _artworkAccent;
    }
    return parseHex(settings.accent);
  }

  String get serverUrl => settings.serverUrl.trim().isNotEmpty
      ? settings.serverUrl.trim()
      : AppConfig.defaultServerUrl;

  Future<void> update(AppSettings next) async {
    settings = next;
    notifyListeners();
    await _storage.writeSettings(next);
  }

  EqState loadEq() {
    try {
      final raw = _storage.getString('adimusic:eq');
      if (raw != null) return EqState.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('Equalizer settings unreadable: $e');
    }
    return EqState();
  }

  Future<void> saveEq(EqState eq) =>
      _storage.setString('adimusic:eq', jsonEncode(eq.toJson()));

  Future<void> setVolume(double v) async {
    settings = settings.copyWith(volume: v);
    await _storage.writeSettings(settings);
  }

  /// A manual accent turns artwork colours off, like the web build.
  Future<void> setAccent(Color color) => update(
    settings.copyWith(accent: colorToHex(color), pickColorFromArtwork: false),
  );

  /// Average colour of the artwork, used only when it is saturated enough (>= 12%).
  Future<void> setArtworkAccentFromBytes(Uint8List? bytes) async {
    Color? next;
    if (bytes != null) {
      try {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 1,
          targetHeight: 1,
        );
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        frame.image.dispose();
        codec.dispose();
        if (data != null) {
          final c = Color.fromARGB(
            255,
            data.getUint8(0),
            data.getUint8(1),
            data.getUint8(2),
          );
          next = colorToHsl(c).s >= 12 ? c : null;
        }
      } catch (e) {
        debugPrint('Artwork colour skipped: $e');
      }
    }
    if (next != _artworkAccent) {
      _artworkAccent = next;
      notifyListeners();
    }
  }

  void clearArtworkAccent() {
    if (_artworkAccent != null) {
      _artworkAccent = null;
      notifyListeners();
    }
  }
}

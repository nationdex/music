/// User settings. Same keys as the web build's `DEFAULT_SETTINGS`, plus the two
/// that only make sense on a phone (server URL, glass effects).
library;

class AppSettings {
  const AppSettings({
    this.lyricsProvider = 'auto',
    this.lyricsPrefer = 'word',
    this.theme = 'auto',
    this.pickColorFromArtwork = true,
    this.accent = '',
    this.motion = 'auto',
    this.volumeInPlayer = true,
    this.preservePitch = true,
    this.discoverySource = 'youtube',
    this.volume = 1,
    this.serverUrl = '',
    this.glass = 'auto',
  });

  /// `auto` | `adi` | `lrclib` | `lrcmux` | an Adi Lyrics adapter id.
  final String lyricsProvider;

  /// `word` | `line` | `plain` | `best`.
  final String lyricsPrefer;

  /// `auto` (follow the OS) | `dark` | `light`.
  final String theme;
  final bool pickColorFromArtwork;

  /// `''` = built-in palette, otherwise `#rrggbb`.
  final String accent;

  /// `auto` | `reduced` | `full`.
  final String motion;
  final bool volumeInPlayer;
  final bool preservePitch;

  /// `youtube` (full tracks) | `itunes` (30 s previews).
  final String discoverySource;
  final double volume;

  /// Adi Music server that holds the YouTube key. Empty: use the build-time default.
  final String serverUrl;

  /// `auto` (Liquid Glass on iOS 26+) | `off`.
  final String glass;

  AppSettings copyWith({
    String? lyricsProvider,
    String? lyricsPrefer,
    String? theme,
    bool? pickColorFromArtwork,
    String? accent,
    String? motion,
    bool? volumeInPlayer,
    bool? preservePitch,
    String? discoverySource,
    double? volume,
    String? serverUrl,
    String? glass,
  }) => AppSettings(
    lyricsProvider: lyricsProvider ?? this.lyricsProvider,
    lyricsPrefer: lyricsPrefer ?? this.lyricsPrefer,
    theme: theme ?? this.theme,
    pickColorFromArtwork: pickColorFromArtwork ?? this.pickColorFromArtwork,
    accent: accent ?? this.accent,
    motion: motion ?? this.motion,
    volumeInPlayer: volumeInPlayer ?? this.volumeInPlayer,
    preservePitch: preservePitch ?? this.preservePitch,
    discoverySource: discoverySource ?? this.discoverySource,
    volume: volume ?? this.volume,
    serverUrl: serverUrl ?? this.serverUrl,
    glass: glass ?? this.glass,
  );

  Map<String, dynamic> toJson() => {
    'lyricsProvider': lyricsProvider,
    'lyricsPrefer': lyricsPrefer,
    'theme': theme,
    'pickColorFromArtwork': pickColorFromArtwork,
    'accent': accent,
    'motion': motion,
    'volumeInPlayer': volumeInPlayer,
    'preservePitch': preservePitch,
    'discoverySource': discoverySource,
    'volume': volume,
    'serverUrl': serverUrl,
    'glass': glass,
  };

  /// Tolerant of missing keys and of backups exported by the web build.
  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    String s(String k, String fallback) => j[k] is String ? j[k] as String : fallback;
    bool b(String k, bool fallback) => j[k] is bool ? j[k] as bool : fallback;
    return AppSettings(
      lyricsProvider: s('lyricsProvider', d.lyricsProvider),
      lyricsPrefer: s('lyricsPrefer', d.lyricsPrefer),
      theme: s('theme', d.theme),
      pickColorFromArtwork: b('pickColorFromArtwork', d.pickColorFromArtwork),
      accent: s('accent', d.accent),
      motion: s('motion', d.motion),
      volumeInPlayer: b('volumeInPlayer', d.volumeInPlayer),
      preservePitch: b('preservePitch', d.preservePitch),
      discoverySource: s('discoverySource', d.discoverySource),
      volume: j['volume'] is num ? (j['volume'] as num).toDouble().clamp(0.0, 1.0) : d.volume,
      serverUrl: s('serverUrl', d.serverUrl),
      glass: s('glass', d.glass),
    );
  }
}

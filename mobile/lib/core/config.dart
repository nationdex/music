/// Constants shared across the app. Ported from site/assets/js/config.js.
library;

/// Upstream endpoints. Lyrics providers and iTunes are keyless, so the app
/// calls them directly. YouTube needs an API key, which must never ship inside
/// an app binary: the app talks to a server (see [AppConfig.defaultServerUrl])
/// that appends the key, exactly like the web build's `/up/youtube` proxy.
class Endpoints {
  const Endpoints._();

  static const adi = 'https://lyrics.imreallyadi.space';
  static const lrclib = 'https://lrclib.net';
  static const lrcmux = 'https://api.lrcmux.dev';
  static const itunes = 'https://itunes.apple.com';
}

class AppConfig {
  const AppConfig._();

  /// Base URL of an Adi Music server (the nginx deployment in `deploy/`).
  /// Set at build time with `--dart-define=ADI_SERVER_URL=https://music.example.com`
  /// or at runtime in Settings. Empty disables YouTube and falls back to Apple previews.
  static const defaultServerUrl = String.fromEnvironment('ADI_SERVER_URL');

  static const sourceUrl = 'https://github.com/nationdex/music';

  /// Library entries that stop at this many items in the "recently played" lists.
  static const historyLimit = 100;
}

const adiProviders = <String>[
  'lrclib',
  'betterlyrics',
  'unison',
  'amll-ttml-db',
  'lrc-red',
  'vgjr-spotify',
  'vgjr-kugou',
  'vgjr-shazam',
  'vgjr-tidal',
  'vgjr-deezer',
  'popcat',
];

/// Titles that are commentary or edits of a song rather than the song itself.
const derivativeTitles = <String>[
  'shorten',
  'reaction',
  'cover',
  'karaoke',
  'tutorial',
  'lesson',
  'slowed',
  'reverb',
  'mashup',
  '1 hour',
  '10 hour',
  'loop',
  'sped up',
  'nightcore',
];

/// 10-band equalizer presets, in dB.
const eqPresets = <String, List<double>>{
  'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Bass Boost': [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
  'Vocal': [-2, -1, 1, 3, 4, 4, 3, 1, 0, -1],
  'Treble': [-1, -1, 0, 0, 1, 2, 4, 6, 7, 8],
  'Rock': [5, 4, 2, -1, -2, 0, 2, 4, 5, 6],
  'Electronic': [6, 5, 2, 0, -2, 2, 1, 3, 5, 6],
};

/// Centre frequencies (Hz) of the 10 preset bands.
const eqBandFrequencies = <double>[32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

const sortKeys = <(String, String)>[
  ('name', 'Name'),
  ('artist', 'Artist'),
  ('album', 'Album'),
  ('duration', 'Duration'),
  ('addedAt', 'Date added'),
];

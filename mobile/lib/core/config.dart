/// Constants shared across the app. Ported from site/assets/js/config.js.
library;

/// Upstream endpoints. Lyrics providers and iTunes are keyless, so the app
/// calls them directly. YouTube needs an API key, which must never ship inside
/// an app binary: the app talks to a server (see [AppConfig.defaultServerUrl])
/// that appends the key, exactly like the web build's `/up/youtube` proxy.
class Endpoints {
  const Endpoints._();

  static const adi = 'https://lyrics.adi.rest';
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

const sortKeys = <(String, String)>[
  ('name', 'Name'),
  ('artist', 'Artist'),
  ('album', 'Album'),
  ('duration', 'Duration'),
  ('addedAt', 'Date added'),
];

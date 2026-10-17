export const DEFAULT_SETTINGS = {
  lyricsProvider: 'auto',
  lyricsPrefer: 'word',
  theme: 'auto', // 'auto' (follow the OS) | 'dark' | 'light'
  pickColorFromArtwork: true,
  accent: '', // '' = built-in palette, otherwise '#rrggbb'
  motion: 'auto', // 'auto' | 'reduced' | 'full'
  volumeInPlayer: true,
  preservePitch: true,
  discoverySource: 'youtube', // 'youtube' (full tracks) | 'itunes' (30 s previews)
  volume: 1
};

// --------------------------------------------------------------- equalizer

export const EQ_PRESETS = {
  Flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Bass Boost': [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
  Vocal: [-2, -1, 1, 3, 4, 4, 3, 1, 0, -1],
  Treble: [-1, -1, 0, 0, 1, 2, 4, 6, 7, 8],
  Rock: [5, 4, 2, -1, -2, 0, 2, 4, 5, 6],
  Electronic: [6, 5, 2, 0, -2, 2, 1, 3, 5, 6]
};

// ------------------------------------------------------------ upstream APIs
// nginx proxies these prefixes (see deploy/nginx.conf); the YouTube key is
// injected there and never reaches the browser.

export const API = { adi: '/up/adi', lrclib: '/up/lrclib', lrcmux: '/up/lrcmux', itunes: '/up/itunes', youtube: '/up/youtube' };
export const ADI_PROVIDERS = [
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
  'popcat'
];

// Titles that are commentary or edits of a song rather than the song itself.
export const DERIVATIVE_TITLES = [
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
  'nightcore'
];

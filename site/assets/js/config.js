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
  volume: 1,
  discordRpc: false, // show what is playing on Discord (needs tools/discord-rpc running)
  discordClientId: '' // Discord application id (discord.com/developers)
};

// ------------------------------------------------------------ upstream APIs
// nginx proxies these prefixes (see deploy/nginx.conf); the YouTube key is
// injected there and never reaches the browser.

export const API = {
  adi: '/up/adi',
  lrclib: '/up/lrclib',
  lrcmux: '/up/lrcmux',
  itunes: '/up/itunes',
  youtube: '/up/youtube',
  innertube: '/up/innertube'
};
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

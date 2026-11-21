import { API, DERIVATIVE_TITLES } from './config.js';

// ---------------------------------------------------------------------------- Search
// Keyless sources, in order: Innertube (the internal API youtube.com itself uses), then Audius
// (open music network; full tracks streamed over plain HTTP). Apple previews (itunesSearch) are
// the last resort, chosen by the caller. Audius rows carry `stream`, a URL for an <audio> element,
// and ids "au:<id>"; they play through the same audio path as Apple previews.

const BLOCKED_KEY = 'adimusic:ytBlocked';
const BLOCKED_MAX = 300;
export const AUDIUS_PREFIX = 'au:';

const memory = new Map();
function readStore(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return memory.get(key) ?? null;
  }
}
function writeStore(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch {
    memory.set(key, value);
  }
}

/** Video ids that failed in the player with "embedding not allowed" (101 / 150). Hidden from search. */
export const blockedVideos = {
  list() {
    try {
      return JSON.parse(readStore(BLOCKED_KEY) || '[]');
    } catch {
      return [];
    }
  },
  has(id) {
    return this.list().includes(id);
  },
  add(id) {
    if (!id || this.has(id)) return;
    writeStore(BLOCKED_KEY, JSON.stringify([...this.list(), id].slice(-BLOCKED_MAX)));
  }
};

const nonMusic = /\b(?:game[\s-]*plays?|walk[\s-]*throughs?|play[\s-]*throughs?|play sessions?|no commentary|let['’]s play|tutorial|how to|reaction|review|podcast|unboxing)\b/i;
const ageNotice = /\b(?:age[- ]restricted|18\+|adults only|nsfw)(?=\W|$)/i;
const explicitNotice = /(?:\[|\()\s*(?:explicit|uncensored|dirty version)\s*(?:\]|\))/i;

function allowedRating(rating, mode) {
  if (rating === 'restricted') return false;
  if (mode === 'clean') return rating === 'clean';
  return rating !== 'explicit' || mode === 'all';
}

function musicResult(title, description = '') {
  if (ageNotice.test(title || '')) return 'restricted';
  return explicitNotice.test(title) || explicitNotice.test(description) ? 'explicit' : 'unknown';
}

/** Maps an Audius /v1/tracks/search response to search rows. Non-streamable tracks are dropped. */
export function parseAudiusSearch(data, base = '', content = 'music') {
  return ((data && data.data) || [])
    .filter((t) => t && t.id && t.is_streamable !== false && !(t.access && t.access.stream === false))
    .filter((t) => content !== 'music' || (!nonMusic.test(t.title || '') && !/^(?:podcast|audiobook|spoken word|comedy)$/i.test(t.genre || '')))
    .map((t) => ({
      rating: t.is_age_restricted === true || musicResult(t.title) === 'restricted' ? 'restricted'
        : t.is_explicit === true || musicResult(t.title) === 'explicit' ? 'explicit'
        : t.is_explicit === false ? 'clean' : 'unknown',
      id: AUDIUS_PREFIX + t.id,
      title: t.title || '',
      channel: (t.user && t.user.name) || '',
      artwork: (t.artwork && (t.artwork['480x480'] || t.artwork['1000x1000'] || t.artwork['150x150'])) || undefined,
      duration: Number(t.duration) || 0,
      stream: base + API.audius + '/v1/tracks/' + encodeURIComponent(t.id) + '/stream'
    }));
}

async function audiusSearch(term, limit, _mode, content) {
  const q = new URLSearchParams({ query: term, limit: String(Math.min(limit, 50)) });
  const res = await fetch(API.audius + '/v1/tracks/search?' + q);
  if (!res.ok) throw Object.assign(new Error('Audius search failed'), { status: res.status });
  const rows = parseAudiusSearch(await res.json(), location.origin, content);
  return rows;
}

// "4:08" / "1:02:03" -> seconds.
export function clockSeconds(text) {
  if (!text) return 0;
  return String(text)
    .split(':')
    .reduce((total, part) => total * 60 + (parseInt(part, 10) || 0), 0);
}

/** Pulls videos out of an Innertube search response. Live streams (no length) are dropped. */
export function parseInnertubeSearch(data, content = 'music') {
  const sections = data?.contents?.twoColumnSearchResultsRenderer?.primaryContents?.sectionListRenderer?.contents || [];
  const out = [];
  for (const section of sections) {
    for (const entry of section.itemSectionRenderer?.contents || []) {
      const v = entry.videoRenderer;
      if (!v || !v.videoId) continue;
      const length = v.lengthText?.simpleText;
      if (!length) continue;
      const title = (v.title?.runs || []).map((r) => r.text).join('');
      const channel = v.ownerText?.runs?.[0]?.text || v.longBylineText?.runs?.[0]?.text || '';
      const labels = [...(v.badges || []), ...(v.ownerBadges || [])]
        .map((b) => b.metadataBadgeRenderer?.label || '').join(' ');
      // Titles alone can falsely label gameplay as music. Require an artist channel.
      const artistChannel = / - Topic$|VEVO$/i.test(channel) ||
        (v.ownerBadges || []).some((badge) =>
          badge.metadataBadgeRenderer?.style === 'BADGE_STYLE_TYPE_VERIFIED_ARTIST');
      if (content === 'music' && (nonMusic.test(title) || !artistChannel)) continue;
      const rating = v.isAgeRestricted === true || ageNotice.test(labels) ? 'restricted' : (/\bexplicit\b/i.test(labels) ? 'explicit' : musicResult(title));
      const thumbs = v.thumbnail?.thumbnails || [];
      out.push({
        id: v.videoId,
        title,
        channel,
        rating,
        // The hq720 thumbnail URL has tracking query parameters; the stable one is enough.
        artwork: 'https://i.ytimg.com/vi/' + v.videoId + '/hqdefault.jpg',
        thumbnail: thumbs.length ? thumbs[thumbs.length - 1].url : undefined,
        duration: clockSeconds(length)
      });
    }
  }
  return out;
}

async function innertubeSearch(term, _limit, mode, content) {
  const res = await fetch(API.innertube + '/search', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      context: {
        client: { clientName: 'WEB', clientVersion: '2.20260101.00.00', hl: 'en', gl: 'US' },
        user: { lockedSafetyMode: mode !== 'all' }
      },
      query: content === 'music' ? term + ' music' : term,
      params: 'EgIQAQ%3D%3D' // type = video
    })
  });
  if (!res.ok) throw Object.assign(new Error('Innertube search failed'), { status: res.status });
  const rows = parseInnertubeSearch(await res.json(), content);
  return rows;
}

// Try the next provider when no playable rows pass the current filter.
export async function youtubeSearch(term, limit = 24, mode = 'standard', content = 'music') {
  let answered = false;
  const searches = mode === 'clean' ? [audiusSearch] : [innertubeSearch, audiusSearch];
  for (const search of searches) {
    try {
      const rows = await search(term, limit, mode, content);
      answered = true;
      const real = rows.filter((row) => allowedRating(row.rating, mode) &&
        (row.stream || (!blockedVideos.has(row.id) && row.duration >= 60)));
      if (!real.length) continue;
      const derivative = (row) => DERIVATIVE_TITLES.some((word) => row.title.toLowerCase().includes(word));
      return [...real.filter((row) => !derivative(row)), ...real.filter(derivative)].slice(0, limit);
    } catch {
      // Try the next source.
    }
  }
  if (answered) return [];
  throw Object.assign(new Error('Search failed'), { status: 502 });
}

const normalize = (s) =>
  String(s || '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();

/**
 * Other uploads of the same song, best first. Used when a video cannot be embedded
 * (labels often block the official upload but allow the "Topic" or lyric one).
 */
export async function findYouTubeAlternatives(track, exclude = [], mode = 'standard') {
  const wantName = normalize(track.name);
  const wantArtist = normalize(track.artist);
  let rows = [];
  try {
    rows = await youtubeSearch((track.artist + ' ' + track.name).trim(), 15, mode);
  } catch {
    return [];
  }
  return rows
    .filter((r) => !r.stream && r.id !== track.videoId && !exclude.includes(r.id))
    .map((r) => {
      const meta = cleanYouTubeMeta(r.title, r.channel);
      const name = normalize(meta.name);
      let score = 0;
      if (name === wantName) score += 4;
      else if (name && wantName && (name.includes(wantName) || wantName.includes(name))) score += 2;
      if (score === 0) return { ...r, score: 0 }; // a different song, whatever else matches
      if (wantArtist && (normalize(meta.artist).includes(wantArtist) || normalize(r.channel).includes(wantArtist))) score += 2;
      if (track.duration > 0 && r.duration > 0 && Math.abs(r.duration - track.duration) / track.duration < 0.12) score += 2;
      return { ...r, score };
    })
    .filter((r) => r.score >= 4)
    .sort((a, b) => b.score - a.score)
    .slice(0, 3);
}

export async function itunesSearch(term, limit = 24, mode = 'standard', content = 'music') {
  const q = new URLSearchParams({ term, media: 'music', entity: 'song', explicit: mode === 'all' ? 'Yes' : 'No', limit: String(Math.min(limit * 2, 200)) });
  const res = await fetch(API.itunes + '/search?' + q);
  if (!res.ok) throw new Error('Search failed');
  return ((await res.json()).results || []).filter((row) => {
    if (row.kind !== 'song' || !row.previewUrl || !row.trackName || (content === 'music' && nonMusic.test(row.trackName))) return false;
    const trackRating = row.trackExplicitness?.toLowerCase();
    const signal = musicResult(row.trackName);
    const rating = signal === 'restricted' ? 'restricted'
      : trackRating === 'explicit' || signal === 'explicit' ? 'explicit'
      : ['cleaned', 'notexplicit'].includes(trackRating) ? 'clean'
      : row.collectionExplicitness?.toLowerCase() === 'explicit' ? 'explicit' : 'unknown';
    return allowedRating(rating, mode);
  }).slice(0, limit);
}

// YouTube IFrame Player bridge. Full-length tracks; the player store routes here
// when a track's source is 'youtube'. Audio plays inside YouTube's iframe, so the
// EQ graph and <audio> element do not apply to these tracks.
export const YTBridge = {
  player: null,
  store: null,
  ready: null,
  timer: null,

  attach(store) {
    this.store = store;
  },

  load() {
    if (this.ready) return this.ready;
    this.ready = new Promise((resolve, reject) => {
      const create = () => {
        const host = document.getElementById('yt-player');
        if (!host) return reject(new Error('missing #yt-player host'));
        this.player = new window.YT.Player(host, {
          width: 1,
          height: 1,
          playerVars: { playsinline: 1, controls: 0, rel: 0, modestbranding: 1 },
          events: {
            onReady: () => {
              if (this.store) this.setVolume(Math.round(this.store.outputVolume * 100));
              resolve();
            },
            onStateChange: (e) => {
              if (this.store) this.store.onYTState(e.data);
            },
            onError: (e) => {
              if (this.store) this.store.onYTError(e.data);
            }
          }
        });
      };
      if (window.YT && window.YT.Player) return create();
      const prev = window.onYouTubeIframeAPIReady;
      window.onYouTubeIframeAPIReady = () => {
        if (prev) prev();
        create();
      };
      const s = document.createElement('script');
      s.src = 'https://www.youtube.com/iframe_api';
      s.async = true;
      s.onerror = () => {
        this.ready = null;
        reject(new Error('YouTube IFrame API blocked'));
      };
      document.head.appendChild(s);
    });
    return this.ready;
  },

  loadVideo(videoId) {
    this.player.loadVideoById(videoId);
    this.startTimer();
  },
  play() {
    if (this.player) {
      this.player.playVideo();
      this.startTimer();
    }
  },
  pause() {
    if (this.player) this.player.pauseVideo();
  },
  stop() {
    if (this.player) this.player.stopVideo();
    this.stopTimer();
  },
  seek(t) {
    if (this.player) this.player.seekTo(t, true);
  },
  setVolume(v) {
    if (this.player) this.player.setVolume(v);
  },
  setMuted(m) {
    if (this.player) m ? this.player.mute() : this.player.unMute();
  },

  // True when the player is really at the end. YouTube also reports ENDED when a pre-roll ad
  // finishes, and treating that as the end of the song would skip the track.
  nearEnd(expectedSeconds = 0) {
    try {
      const t = this.player.getCurrentTime();
      const d = this.player.getDuration();
      const total = expectedSeconds > 0 ? Math.max(expectedSeconds, d || 0) : d;
      return !(total > 0) || t >= total - 3;
    } catch {
      return true;
    }
  },

  startTimer() {
    if (this.timer) return;
    this.timer = setInterval(() => {
      if (!this.player || !this.store || !this.player.getCurrentTime) return;
      this.store.onYTTick({ t: this.player.getCurrentTime(), d: this.player.getDuration() });
    }, 500);
  },
  stopTimer() {
    clearInterval(this.timer);
    this.timer = null;
  }
};

// "Michael Jackson - Bad (Official Video)" + "michaeljacksonVEVO" -> { name: 'Bad', artist: 'Michael Jackson' }
export function cleanYouTubeMeta(title, channel) {
  let name = (title || '').replace(/\s*[\(\[][^\)\]]*[\)\]]/g, '').trim();
  let artist = (channel || '')
    .replace(/\s*-\s*Topic$/i, '')
    .replace(/VEVO$/i, '')
    .trim();
  const m = name.match(/^(.+?)\s+[-–]\s+(.+)$/);
  if (m) {
    artist = m[1].trim();
    name = m[2].trim();
  }
  return { name: name || title, artist };
}

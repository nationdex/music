import { API, DERIVATIVE_TITLES } from './config.js';
import { getJson } from './util.js';

function isoSeconds(iso) {
  const n = (u) => parseInt((String(iso || '').match(new RegExp('(\\d+)' + u)) || [0, 0])[1], 10) || 0;
  return n('H') * 3600 + n('M') * 60 + n('S');
}

// ---------------------------------------------------------------------------- YouTube search
// Two sources, in order: the Data API (needs a key, has a daily quota) and Innertube, the
// internal API youtube.com itself uses (no key, no quota). The Data API is skipped for
// QUOTA_COOLDOWN_MS after it reports a spent quota or a rate limit, so a dead key does not
// slow down every search.

const QUOTA_KEY = 'adimusic:ytQuotaUntil';
const BLOCKED_KEY = 'adimusic:ytBlocked';
const QUOTA_COOLDOWN_MS = 15 * 60 * 1000;
const BLOCKED_MAX = 300;

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

export function dataApiCoolingDown() {
  return Number(readStore(QUOTA_KEY) || 0) > Date.now();
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

async function dataApiSearch(term, limit) {
  const q = new URLSearchParams({
    part: 'snippet',
    type: 'video',
    videoCategoryId: '10',
    // Only videos whose owner allows embedding; the rest fail in the player with error 150.
    videoEmbeddable: 'true',
    maxResults: String(Math.min(limit, 50)),
    q: term
  });
  const res = await fetch(API.youtube + '/search?' + q);
  if (!res.ok) throw Object.assign(new Error('YouTube search failed'), { status: res.status });
  const data = await res.json();
  const items = (data.items || [])
    .filter((i) => i.id && i.id.videoId)
    .map((i) => {
      const sn = i.snippet || {},
        th = sn.thumbnails || {};
      return {
        id: i.id.videoId,
        title: sn.title || '',
        channel: sn.channelTitle || '',
        artwork: (th.high || th.medium || th.default || {}).url,
        duration: 0
      };
    });
  if (items.length) {
    const det = await getJson(
      API.youtube + '/videos?' + new URLSearchParams({ part: 'contentDetails,status', id: items.map((i) => i.id).join(',') })
    );
    const dur = {};
    const blocked = new Set();
    ((det && det.items) || []).forEach((d) => {
      dur[d.id] = isoSeconds(d.contentDetails && d.contentDetails.duration);
      if (d.status && d.status.embeddable === false) blocked.add(d.id);
    });
    items.forEach((i) => {
      i.duration = dur[i.id] || 0;
      i.blocked = blocked.has(i.id);
    });
  }
  return items.filter((i) => !i.blocked);
}

// "4:08" / "1:02:03" -> seconds.
export function clockSeconds(text) {
  if (!text) return 0;
  return String(text)
    .split(':')
    .reduce((total, part) => total * 60 + (parseInt(part, 10) || 0), 0);
}

/** Pulls videos out of an Innertube search response. Live streams (no length) are dropped. */
export function parseInnertubeSearch(data) {
  const sections = data?.contents?.twoColumnSearchResultsRenderer?.primaryContents?.sectionListRenderer?.contents || [];
  const out = [];
  for (const section of sections) {
    for (const entry of section.itemSectionRenderer?.contents || []) {
      const v = entry.videoRenderer;
      if (!v || !v.videoId) continue;
      const length = v.lengthText?.simpleText;
      if (!length) continue;
      const thumbs = v.thumbnail?.thumbnails || [];
      out.push({
        id: v.videoId,
        title: (v.title?.runs || []).map((r) => r.text).join(''),
        channel: v.ownerText?.runs?.[0]?.text || v.longBylineText?.runs?.[0]?.text || '',
        // The hq720 thumbnail URL has tracking query parameters; the stable one is enough.
        artwork: 'https://i.ytimg.com/vi/' + v.videoId + '/hqdefault.jpg',
        thumbnail: thumbs.length ? thumbs[thumbs.length - 1].url : undefined,
        duration: clockSeconds(length)
      });
    }
  }
  return out;
}

async function innertubeSearch(term, limit) {
  const res = await fetch(API.innertube + '/search', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      context: { client: { clientName: 'WEB', clientVersion: '2.20260101.00.00', hl: 'en', gl: 'US' } },
      query: term,
      params: 'EgIQAQ%3D%3D' // type = video
    })
  });
  if (!res.ok) throw Object.assign(new Error('Innertube search failed'), { status: res.status });
  const rows = parseInnertubeSearch(await res.json());
  if (!rows.length) throw Object.assign(new Error('Innertube returned no videos'), { status: 502 });
  return rows.slice(0, limit);
}

// Full-length tracks from YouTube. Throws {status} only when both sources fail.
export async function youtubeSearch(term, limit = 24) {
  let items = null;
  if (!dataApiCoolingDown()) {
    try {
      items = await dataApiSearch(term, limit);
    } catch (e) {
      // 403 = quota spent (or key restricted), 429 = rate limited. Anything else (no key, 5xx,
      // offline) just falls through to Innertube for this search.
      if (e.status === 403 || e.status === 429) writeStore(QUOTA_KEY, String(Date.now() + QUOTA_COOLDOWN_MS));
    }
  }
  if (!items) {
    try {
      items = await innertubeSearch(term, limit);
    } catch (e) {
      throw Object.assign(new Error('YouTube search failed'), { status: e.status || 502 });
    }
  }
  // Drop Shorts and videos that already failed to embed; keep relevance order, with
  // edits/reactions after the originals.
  const real = items.filter((i) => !blockedVideos.has(i.id) && !(i.duration > 0 && i.duration < 60));
  const derivative = (i) => DERIVATIVE_TITLES.some((w) => i.title.toLowerCase().includes(w));
  return [...real.filter((i) => !derivative(i)), ...real.filter(derivative)];
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
export async function findYouTubeAlternatives(track, exclude = []) {
  const wantName = normalize(track.name);
  const wantArtist = normalize(track.artist);
  let rows = [];
  try {
    rows = await youtubeSearch((track.artist + ' ' + track.name).trim(), 15);
  } catch {
    return [];
  }
  return rows
    .filter((r) => r.id !== track.videoId && !exclude.includes(r.id))
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

export async function itunesSearch(term, limit = 24) {
  const q = new URLSearchParams({ term, media: 'music', entity: 'song', limit: String(limit) });
  const res = await fetch(API.itunes + '/search?' + q);
  if (!res.ok) throw new Error('Search failed');
  return (await res.json()).results || [];
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
              if (this.store) this.setVolume(Math.round(this.store.volume * 100));
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

import { API, DERIVATIVE_TITLES } from './config.js';
import { getJson } from './util.js';

function isoSeconds(iso) {
  const n = (u) => parseInt((String(iso || '').match(new RegExp('(\\d+)' + u)) || [0, 0])[1], 10) || 0;
  return n('H') * 3600 + n('M') * 60 + n('S');
}

// Full-length tracks from YouTube. Throws {status} when the key is missing (503) or the quota is spent.
export async function youtubeSearch(term, limit = 24) {
  const q = new URLSearchParams({
    part: 'snippet',
    type: 'video',
    videoCategoryId: '10',
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
      API.youtube + '/videos?' + new URLSearchParams({ part: 'contentDetails', id: items.map((i) => i.id).join(',') })
    );
    const dur = {};
    ((det && det.items) || []).forEach((d) => {
      dur[d.id] = isoSeconds(d.contentDetails && d.contentDetails.duration);
    });
    items.forEach((i) => {
      i.duration = dur[i.id] || 0;
    });
  }
  // Drop Shorts; keep relevance order, with edits/reactions after the originals.
  const real = items.filter((i) => !(i.duration > 0 && i.duration < 60));
  const derivative = (i) => DERIVATIVE_TITLES.some((w) => i.title.toLowerCase().includes(w));
  return [...real.filter((i) => !derivative(i)), ...real.filter(derivative)];
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

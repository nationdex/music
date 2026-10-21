// Discord Rich Presence. A browser cannot reach Discord, so the page posts to a small bridge
// that runs on the same computer as Discord: tools/discord-rpc/adi-discord-rpc.py.

export const BRIDGE = 'http://127.0.0.1:6480';

/** Builds the payload the bridge turns into a "Listening to" activity. */
export function buildPresence(clientId, track, { playing, position, duration }, now = Date.now()) {
  const art = track.artwork && /^https?:/i.test(track.artwork) ? track.artwork : 'logo';
  const payload = {
    clientId,
    details: track.name,
    state: playing ? 'by ' + (track.artist || 'Unknown artist') : (track.artist || 'Unknown artist') + ' · Paused',
    largeImage: art,
    largeText: track.album || track.name
  };
  // A progress bar only while playing and only when the length is known.
  if (playing && duration > 0) {
    const start = now - Math.round((position || 0) * 1000);
    payload.startTimestamp = start;
    payload.endTimestamp = start + Math.round(duration * 1000);
  }
  return payload;
}

async function post(path, body) {
  const res = await fetch(BRIDGE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {})
  });
  let data = {};
  try {
    data = await res.json();
  } catch {}
  return { ok: res.ok, error: data.error || '' };
}

export const presence = {
  /** 'off' | 'connected' | 'no-bridge' | 'no-discord' | 'error' */
  status: 'off',
  onStatus: null,
  _last: '',

  _set(status) {
    if (this.status === status) return;
    this.status = status;
    if (this.onStatus) this.onStatus(status);
  },

  /** Asks the bridge whether it is up and whether Discord is connected. */
  async check() {
    try {
      const res = await fetch(BRIDGE + '/ping');
      const data = await res.json();
      this._set(data.discord ? 'connected' : 'no-discord');
    } catch {
      this._set('no-bridge');
    }
    return this.status;
  },

  async update(payload) {
    const key = JSON.stringify([payload.details, payload.state, payload.startTimestamp && Math.round(payload.startTimestamp / 2000)]);
    if (key === this._last && this.status === 'connected') return;
    try {
      const r = await post('/presence', payload);
      if (r.ok) {
        this._last = key;
        this._set('connected');
      } else {
        this._set(/not running/i.test(r.error) ? 'no-discord' : 'error');
      }
    } catch {
      this._set('no-bridge');
    }
  },

  async clear() {
    this._last = '';
    try {
      await post('/clear');
    } catch {
      /* the bridge is not running: nothing to clear */
    }
  }
};

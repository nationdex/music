import { ADI_PROVIDERS, API } from './config.js';
import { blank, getJson } from './util.js';

// Flatten an upstream lyrics record into the envelope the player consumes.
function normalizeLyrics(best, source) {
  if (!best || typeof best !== 'object') return null;
  const rec = {
    plainLyrics: blank(best.plainLyrics),
    syncedLyrics: blank(best.syncedLyrics),
    ttml: blank(best.ttml),
    syncLyrics: blank(best.syncLyrics),
    lyricsfile: blank(best.lyricsfile),
    format: best.format || null,
    syncLevel: best.syncLevel || null,
    provider: best.provider || null,
    source
  };
  if (!rec.plainLyrics && !rec.syncedLyrics && !rec.ttml && !rec.syncLyrics && !rec.lyricsfile) return null;
  return rec;
}

async function fetchAdiLyrics(o) {
  const q = new URLSearchParams({ track: o.title || '', artist: o.artist || '' });
  if (o.album) q.set('album', o.album);
  if (o.duration) q.set('duration', String(Math.floor(o.duration)));
  if (o.isrc) q.set('isrc', o.isrc);
  if (['word', 'line', 'plain', 'best'].includes(o.prefer)) q.set('prefer', o.prefer);
  if (ADI_PROVIDERS.includes(o.provider)) q.set('provider', o.provider);
  const data = await getJson(API.adi + '/api/lyrics?' + q);
  return data && data.found ? normalizeLyrics(data.best, 'adi-lyrics') : null;
}

async function fetchLrclibLyrics(o) {
  const q = new URLSearchParams({ track_name: o.title || '', artist_name: o.artist || '' });
  if (o.duration) q.set('duration', String(Math.floor(o.duration)));
  if (o.album) q.set('album_name', o.album);
  const d = await getJson(API.lrclib + '/api/get?' + q);
  if (!d) return null;
  return normalizeLyrics(
    {
      plainLyrics: d.plainLyrics,
      syncedLyrics: d.syncedLyrics,
      format: d.syncedLyrics ? 'lrc' : 'plain',
      syncLevel: d.syncedLyrics ? 'line' : 'plain',
      provider: 'lrclib'
    },
    'lrclib-direct'
  );
}

async function fetchLrcmuxLyrics(o) {
  const q = new URLSearchParams({ title: o.title || '', artist: o.artist || '' });
  const d = await getJson(API.lrcmux + '/compat/kpoe/v2/lyrics/get?' + q);
  if (!d) return null;
  return normalizeLyrics(
    d.data && typeof d.data === 'object' ? d.data : d.best && typeof d.best === 'object' ? d.best : d,
    'lrcmux-direct'
  );
}

// provider: auto -> aggregator, LRCLIB, LRC Mux | adi | lrclib | lrcmux | <adapter id> (pinned aggregator)
export async function resolveLyrics(o) {
  const w = o.provider;
  let steps = ['adi', 'lrclib', 'lrcmux'];
  if (['adi', 'lrclib', 'lrcmux'].includes(w)) steps = [w];
  else if (ADI_PROVIDERS.includes(w)) steps = ['adi'];
  for (const step of steps) {
    const rec = step === 'adi' ? await fetchAdiLyrics(o) : step === 'lrclib' ? await fetchLrclibLyrics(o) : await fetchLrcmuxLyrics(o);
    if (rec) return rec;
  }
  return null;
}

// "[mm:ss.xx] line" / "[mm:ss.xxx] line" / "[mm:ss] line" -> [{t, text}]
export function parseLRC(source) {
  if (!source) return [];
  const lines = [];
  const timeTag = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g;

  for (const raw of String(source).split(/\r?\n/)) {
    const text = raw.replace(timeTag, '').trim();
    const stamps = [...raw.matchAll(timeTag)];

    for (const match of stamps) {
      const min = Number(match[1]);
      const sec = Number(match[2]);
      const fracRaw = match[3] || '0';
      const frac = Number(fracRaw) / Math.pow(10, fracRaw.length);
      lines.push({ t: min * 60 + sec + frac, text: text || '♪' });
    }

    if (stamps.length === 0 && text) {
      lines.push({ t: null, text });
    }
  }

  return lines.filter((l) => l.t !== null).sort((a, b) => a.t - b.t);
}

// TTML time expression -> seconds.
// Handles "27.395", "27.395s", "1234ms", "3:14.571", "00:03:14.571".
function parseTTMLTime(raw) {
  if (raw === undefined || raw === null) return null;
  const value = String(raw).trim();
  if (!value) return null;

  if (/^-?\d+(\.\d+)?ms$/.test(value)) return parseFloat(value) / 1000;
  if (/^-?\d+(\.\d+)?s$/.test(value)) return parseFloat(value);
  if (/^-?\d+(\.\d+)?$/.test(value)) return parseFloat(value);

  const parts = value.split(':').map((p) => p.trim());
  if (parts.length < 2 || parts.length > 3) return null;
  let total = 0;
  for (const part of parts) {
    const n = parseFloat(part);
    if (Number.isNaN(n)) return null;
    total = total * 60 + n;
  }
  return total;
}

const TTML_ENTITIES = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&#39;': "'",
  '&#34;': '"',
  '&nbsp;': ' '
};

function decodeTTMLText(raw) {
  let out = String(raw);
  out = out.replace(/<[^>]+>/g, '');
  out = out.replace(/&[a-zA-Z#0-9]+;/g, (entity) => TTML_ENTITIES[entity] ?? ' ');
  return out.replace(/\s+/g, ' ').trim();
}

// TTML <p begin="..." end="..."> ... </p> -> [{t, tEnd, text}]
export function parseTTML(source) {
  if (!source) return [];
  const lines = [];
  const para = /<p\b([^>]*)>([\s\S]*?)<\/p>/gi;

  for (const match of String(source).matchAll(para)) {
    const attrs = match[1] || '';
    const inner = match[2] || '';

    const begin = /\bbegin\s*=\s*["']([^"']+)["']/i.exec(attrs);
    if (!begin) continue;
    const t = parseTTMLTime(begin[1]);
    if (t === null) continue;

    const end = /\bend\s*=\s*["']([^"']+)["']/i.exec(attrs);
    const dur = /\bdur\s*=\s*["']([^"']+)["']/i.exec(attrs);

    const tEnd = end ? parseTTMLTime(end[1]) : dur ? t + parseTTMLTime(dur[1]) : null;
    const text = decodeTTMLText(inner) || '♪';

    lines.push({ t, tEnd, text });
  }

  return lines.sort((a, b) => a.t - b.t);
}

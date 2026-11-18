// Equalizer: presets, the maths behind the response curve, and the Web Audio graph.
//
//   <audio> -> preamp -> 10 band filters -> limiter -> analyser -> speakers
//
// The graph is built lazily (see Equalizer.connect): routing an <audio> element through Web Audio
// is irreversible and costs battery, so a flat equalizer never touches it.

export const EQ_FREQS = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
export const EQ_LABELS = ['32Hz', '64Hz', '125Hz', '250Hz', '500Hz', '1kHz', '2kHz', '4kHz', '8kHz', '16kHz'];
export const EQ_RANGE = 12; // dB, either side
export const EQ_Q = 1.4;
export const EQ_MAX_CUSTOM = 20;

/** Gains in dB for the ten bands above. */
export const EQ_PRESETS = {
  Flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Bass Boost': [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
  'Bass Reducer': [-6, -5, -4, -2, -1, 0, 0, 0, 0, 0],
  'Treble Boost': [-1, -1, 0, 0, 1, 2, 4, 6, 7, 8],
  'Treble Reducer': [0, 0, 0, 0, 0, -1, -3, -5, -6, -7],
  Vocal: [-2, -1, 1, 3, 4, 4, 3, 1, 0, -1],
  Podcast: [-4, -3, -1, 2, 4, 4, 3, 1, -1, -3],
  Acoustic: [4, 4, 3, 1, 1, 1, 2, 3, 3, 2],
  Classical: [4, 3, 3, 2, -1, -1, 0, 2, 3, 3],
  Jazz: [3, 2, 1, 2, -1, -1, 0, 1, 2, 3],
  Pop: [-1, 1, 3, 4, 3, 0, -1, -1, -1, -1],
  Rock: [5, 4, 2, -1, -2, 0, 2, 4, 5, 6],
  'Hip-Hop': [5, 4, 2, 3, -1, -1, 2, 0, 2, 3],
  Dance: [6, 5, 3, 0, 1, 3, 4, 3, 2, 0],
  Electronic: [6, 5, 2, 0, -2, 2, 1, 3, 5, 6],
  Loudness: [6, 4, 0, 0, -1, 0, -1, -4, 5, 1],
  'Late Night': [2, 2, 1, 0, 0, -1, -2, -3, -3, -3]
};

export function defaultEq() {
  return { enabled: true, preset: 'Flat', gains: EQ_PRESETS.Flat.slice(), preamp: 0, auto: true, custom: {} };
}

const num = (v, fallback = 0) => (Number.isFinite(Number(v)) ? Number(v) : fallback);
export const clampDb = (v) => Math.max(-EQ_RANGE, Math.min(EQ_RANGE, num(v)));
export const dbToGain = (db) => Math.pow(10, db / 20);

/** Repairs whatever came out of localStorage so the rest of the code can trust its shape. */
export function normalizeEq(raw) {
  const base = defaultEq();
  if (!raw || typeof raw !== 'object') return base;
  const gains = Array.isArray(raw.gains) && raw.gains.length === EQ_FREQS.length ? raw.gains.map(clampDb) : base.gains;
  const custom = {};
  for (const [name, g] of Object.entries(raw.custom && typeof raw.custom === 'object' ? raw.custom : {})) {
    if (Array.isArray(g) && g.length === EQ_FREQS.length && !(name in EQ_PRESETS)) custom[name] = g.map(clampDb);
  }
  return {
    enabled: raw.enabled !== false,
    preset: typeof raw.preset === 'string' ? raw.preset : 'Custom',
    gains,
    preamp: Math.max(-EQ_RANGE, Math.min(EQ_RANGE, num(raw.preamp))),
    auto: raw.auto !== false,
    custom
  };
}

/** Name of the preset whose gains equal [gains], or 'Custom'. Custom presets count too. */
export function matchPreset(gains, custom = {}) {
  const same = (a) => a.length === gains.length && a.every((v, i) => v === gains[i]);
  for (const [name, g] of Object.entries(EQ_PRESETS)) if (same(g)) return name;
  for (const [name, g] of Object.entries(custom)) if (same(g)) return name;
  return 'Custom';
}

/** Headroom: boosting a band can push the signal past full scale, so the preamp drops by the largest boost. */
export const autoPreamp = (gains) => -Math.max(0, ...gains);

/** The preamp in dB that is actually applied. */
export const effectivePreamp = (eq) => (eq.enabled ? (eq.auto ? autoPreamp(eq.gains) : eq.preamp) : 0);

/** True when the equalizer would change the sound at all. */
export const eqIsActive = (eq) => eq.enabled && (eq.gains.some((g) => g !== 0) || (!eq.auto && eq.preamp !== 0));

// --------------------------------------------------------------- response curve
// RBJ "Audio EQ Cookbook" biquads, the same filters Web Audio uses, so the drawn curve matches what is heard.

function coefficients(type, f0, db, fs, q) {
  const A = Math.pow(10, db / 40);
  const w0 = (2 * Math.PI * f0) / fs;
  const cos = Math.cos(w0);
  const sin = Math.sin(w0);
  if (type === 'peaking') {
    const alpha = sin / (2 * q);
    return [1 + alpha * A, -2 * cos, 1 - alpha * A, 1 + alpha / A, -2 * cos, 1 - alpha / A];
  }
  const alpha = (sin / 2) * Math.SQRT2; // shelf slope S = 1
  const k = 2 * Math.sqrt(A) * alpha;
  if (type === 'lowshelf') {
    return [
      A * (A + 1 - (A - 1) * cos + k),
      2 * A * (A - 1 - (A + 1) * cos),
      A * (A + 1 - (A - 1) * cos - k),
      A + 1 + (A - 1) * cos + k,
      -2 * (A - 1 + (A + 1) * cos),
      A + 1 + (A - 1) * cos - k
    ];
  }
  return [
    A * (A + 1 + (A - 1) * cos + k),
    -2 * A * (A - 1 + (A + 1) * cos),
    A * (A + 1 + (A - 1) * cos - k),
    A + 1 - (A - 1) * cos + k,
    2 * (A - 1 - (A + 1) * cos),
    A + 1 - (A - 1) * cos - k
  ];
}

function magnitude([b0, b1, b2, a0, a1, a2], w) {
  const c1 = Math.cos(w),
    s1 = Math.sin(w),
    c2 = Math.cos(2 * w),
    s2 = Math.sin(2 * w);
  const nr = b0 + b1 * c1 + b2 * c2,
    ni = -(b1 * s1 + b2 * s2);
  const dr = a0 + a1 * c1 + a2 * c2,
    di = -(a1 * s1 + a2 * s2);
  return Math.sqrt((nr * nr + ni * ni) / (dr * dr + di * di));
}

/** Combined response in dB of the ten bands (plus [preamp] dB) at each frequency in [freqs]. */
export function responseDb(gains, freqs, preamp = 0, fs = 44100, q = EQ_Q) {
  const filters = EQ_FREQS.map((f, i) =>
    coefficients(i === 0 ? 'lowshelf' : i === EQ_FREQS.length - 1 ? 'highshelf' : 'peaking', f, gains[i] || 0, fs, q)
  );
  return freqs.map((hz) => {
    const w = (2 * Math.PI * hz) / fs;
    let mag = 1;
    for (const c of filters) mag *= magnitude(c, w);
    return 20 * Math.log10(mag) + preamp;
  });
}

/** [count] frequencies spaced evenly on a log axis from [lo] to [hi] Hz. */
export function logFreqs(count = 96, lo = 20, hi = 20000) {
  return Array.from({ length: count }, (_, i) => lo * Math.pow(hi / lo, i / (count - 1)));
}

/** SVG path for the curve inside a [w] x [h] box, with ±[range] dB mapped top to bottom. */
export function curvePath(dbs, w, h, range = EQ_RANGE) {
  return dbs
    .map((db, i) => {
      const x = (i / (dbs.length - 1)) * w;
      const y = h / 2 - (Math.max(-range, Math.min(range, db)) / range) * (h / 2);
      return (i ? 'L' : 'M') + x.toFixed(1) + ' ' + y.toFixed(1);
    })
    .join(' ');
}

// -------------------------------------------------------------------- Web Audio

export class Equalizer {
  constructor(audioEl) {
    this.audioEl = audioEl;
    this.ctx = null;
  }

  get connected() {
    return !!this.ctx;
  }

  /** Builds the graph. Call from a user gesture's call stack when possible (iOS starts contexts suspended). */
  connect() {
    if (this.ctx) return true;
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return false;
    try {
      this.ctx = new Ctx();
      this.source = this.ctx.createMediaElementSource(this.audioEl);
      this.preamp = this.ctx.createGain();
      this.filters = EQ_FREQS.map((f, i) => {
        const node = this.ctx.createBiquadFilter();
        node.type = i === 0 ? 'lowshelf' : i === EQ_FREQS.length - 1 ? 'highshelf' : 'peaking';
        node.frequency.value = f;
        if (node.type === 'peaking') node.Q.value = EQ_Q;
        return node;
      });
      // A limiter, not a compressor: it only acts near full scale, to catch what the preamp headroom misses.
      this.limiter = this.ctx.createDynamicsCompressor();
      this.limiter.threshold.value = -2;
      this.limiter.knee.value = 0;
      this.limiter.ratio.value = 20;
      this.limiter.attack.value = 0.003;
      this.limiter.release.value = 0.1;
      this.analyser = this.ctx.createAnalyser();
      this.analyser.fftSize = 1024;
      this.analyser.smoothingTimeConstant = 0.8;
      const chain = [this.source, this.preamp, ...this.filters, this.limiter, this.analyser, this.ctx.destination];
      for (let i = 0; i < chain.length - 1; i++) chain[i].connect(chain[i + 1]);
      return true;
    } catch (e) {
      console.warn('Web Audio equalizer unavailable:', e);
      this.ctx = null;
      return false;
    }
  }

  resume() {
    if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});
  }

  /** Pushes an eq state (see defaultEq) into the graph. Gains glide over 30 ms, so dragging a slider never clicks. */
  apply(eq) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const on = eq.enabled;
    this.filters.forEach((node, i) => node.gain.setTargetAtTime(on ? clampDb(eq.gains[i]) : 0, t, 0.03));
    this.preamp.gain.setTargetAtTime(dbToGain(effectivePreamp(eq)), t, 0.03);
  }

  /** Current spectrum as 0..255 bars, or null before the graph exists. */
  spectrum(buffer) {
    if (!this.analyser) return null;
    this.analyser.getByteFrequencyData(buffer);
    return buffer;
  }

  get binCount() {
    return this.analyser ? this.analyser.frequencyBinCount : 0;
  }
}

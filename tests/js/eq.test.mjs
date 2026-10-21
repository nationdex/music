// Pure-logic tests for site/assets/js/eq.js. Run: node --test tests/js/
import assert from 'node:assert/strict';
import test from 'node:test';
import { EQ_FREQS, EQ_PRESETS, autoPreamp, clampDb, curvePath, defaultEq, effectivePreamp, eqIsActive, logFreqs, matchPreset, normalizeEq, responseDb } from '../../site/assets/js/eq.js';

test('every preset has ten bands inside the slider range', () => {
  for (const [name, gains] of Object.entries(EQ_PRESETS)) {
    assert.equal(gains.length, EQ_FREQS.length, name);
    assert.ok(gains.every((g) => g >= -12 && g <= 12), name);
  }
});

test('a flat curve is 0 dB everywhere; a boost peaks at its band', () => {
  const flat = responseDb(EQ_PRESETS.Flat, logFreqs());
  assert.ok(flat.every((db) => Math.abs(db) < 1e-9));
  const gains = EQ_PRESETS.Flat.slice();
  gains[5] = 6; // 1 kHz
  const dbs = responseDb(gains, [1000, 100, 10000]);
  assert.ok(Math.abs(dbs[0] - 6) < 0.05, 'full boost at the centre');
  assert.ok(dbs[1] < 1.5 && dbs[2] < 1.5, 'far away barely moves');
});

test('end bands are shelves: they keep their gain out to the edge', () => {
  const g = EQ_PRESETS.Flat.slice();
  g[0] = 8;
  g[9] = -8;
  const [low, high] = responseDb(g, [20, 20000]);
  assert.ok(low > 6.5, `low shelf at 20 Hz: ${low}`);
  assert.ok(high < -6.5, `high shelf at 20 kHz: ${high}`);
});

test('auto preamp drops by the largest boost and never boosts', () => {
  assert.equal(autoPreamp([0, 0, 0]), -0);
  assert.equal(autoPreamp([7, 6, 5, 3, 1, 0, 0, 0, 0, 0]), -7);
  assert.equal(autoPreamp([-4, -2]), -0);
  const eq = { ...defaultEq(), gains: EQ_PRESETS['Bass Boost'] };
  assert.equal(effectivePreamp(eq), -7);
  assert.equal(effectivePreamp({ ...eq, auto: false, preamp: -3 }), -3);
  assert.equal(effectivePreamp({ ...eq, enabled: false }), 0, 'bypassed means untouched');
});

test('the equalizer is inactive when flat or switched off', () => {
  assert.equal(eqIsActive(defaultEq()), false);
  assert.equal(eqIsActive({ ...defaultEq(), gains: EQ_PRESETS.Rock }), true);
  assert.equal(eqIsActive({ ...defaultEq(), gains: EQ_PRESETS.Rock, enabled: false }), false);
  assert.equal(eqIsActive({ ...defaultEq(), auto: false, preamp: -2 }), true, 'manual preamp alone changes the level');
  assert.equal(eqIsActive({ ...defaultEq(), auto: true, preamp: -2 }), false, 'a stale manual value is ignored under auto');
});

test('matchPreset names built-in and custom presets, otherwise Custom', () => {
  assert.equal(matchPreset(EQ_PRESETS.Jazz), 'Jazz');
  assert.equal(matchPreset([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), 'Custom');
  assert.equal(matchPreset([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], { Mine: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }), 'Mine');
});

test('normalizeEq repairs corrupt stored data', () => {
  assert.deepEqual(normalizeEq(null), defaultEq());
  assert.deepEqual(normalizeEq('x'), defaultEq());
  const fixed = normalizeEq({ enabled: false, gains: [99, -99, 'a', 0, 0, 0, 0, 0, 0, 0], preamp: 50, custom: { Bad: [1], Good: EQ_PRESETS.Rock, Flat: EQ_PRESETS.Vocal } });
  assert.equal(fixed.enabled, false);
  assert.equal(fixed.gains[0], 12);
  assert.equal(fixed.gains[1], -12);
  assert.equal(fixed.gains[2], 0, 'junk becomes 0');
  assert.equal(fixed.preamp, 12);
  assert.deepEqual(Object.keys(fixed.custom), ['Good'], 'wrong length and built-in names are dropped');
  assert.deepEqual(normalizeEq({ gains: [1, 2] }).gains, defaultEq().gains, 'wrong length falls back to flat');
});

test('clampDb and curvePath', () => {
  assert.equal(clampDb(40), 12);
  assert.equal(clampDb(-40), -12);
  assert.equal(clampDb('3'), 3);
  assert.equal(clampDb(undefined), 0);
  const d = curvePath([0, 12, -12], 200, 100);
  assert.equal(d, 'M0.0 50.0 L100.0 0.0 L200.0 100.0');
  assert.equal(logFreqs(3, 20, 20000).map(Math.round).join(), '20,632,20000');
});

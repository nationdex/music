// ------------------------------------------------------------------ palette
// The stylesheet owns the exact Material 3 tokens. A custom primary color
// re-hues that same palette (same lightness and saturation structure), so
// every accent keeps the original M3 relationships.

export const DEFAULT_TOKENS = {
  primary: ['#c0000c', '#ffb4aa'],
  onPrimary: ['#ffffff', '#690003'],
  primaryContainer: ['#ffdad5', '#930006'],
  onPrimaryContainer: ['#410001', '#ffdad5'],
  secondary: ['#80543e', '#f4b99f'],
  onSecondary: ['#ffffff', '#4b2715'],
  secondaryContainer: ['#ffdbcc', '#653d29'],
  secondaryContainerVariant: ['#e5ac92', '#3e1d0b'],
  onSecondaryContainer: ['#311304', '#ffdbcc'],
  tertiary: ['#845325', '#fab981'],
  onTertiary: ['#ffffff', '#4c2700'],
  tertiaryContainer: ['#ffdcc1', '#683c0f'],
  onTertiaryContainer: ['#2e1500', '#ffdcc1'],
  surface: ['#fff8f7', '#271816'],
  onSurface: ['#271816', '#f9dcd8'],
  surfaceVariant: ['#fddbd6', '#58413e'],
  onSurfaceVariant: ['#58413e', '#dfbfbb'],
  surfaceContainerHighest: ['#f9dcd8', '#42302e'],
  surfaceContainerHigh: ['#ffe2de', '#372624'],
  surfaceContainer: ['#ffe9e6', '#2b1c1a'],
  surfaceContainerLow: ['#fff0ee', '#271816'],
  surfaceContainerLowest: ['#ffffff', '#180b09'],
  outline: ['#8c716d', '#a78a86'],
  outlineVariant: ['#dfbfbb', '#58413e'],
  inverseSurface: ['#3d2c2a', '#f9dcd8'],
  inverseOnSurface: ['#ffedea', '#271816'],
  inversePrimary: ['#ffb4aa', '#c0000c']
};
export const DEFAULT_SEED_HUE = 6; // hue of the built-in dark primary (#ffb4aa)

export function hexToHsl(hex) {
  const n = parseInt(String(hex).replace('#', ''), 16) || 0;
  const r = ((n >> 16) & 255) / 255,
    g = ((n >> 8) & 255) / 255,
    b = (n & 255) / 255;
  const max = Math.max(r, g, b),
    min = Math.min(r, g, b),
    l = (max + min) / 2;
  let h = 0,
    s = 0;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
  }
  return { h, s: s * 100, l: l * 100 };
}

function hslToHex(h, s, l) {
  h = ((h % 360) + 360) % 360;
  s = Math.max(0, Math.min(100, s)) / 100;
  l = Math.max(0, Math.min(100, l)) / 100;
  const a = s * Math.min(l, 1 - l);
  const f = (n) => {
    const k = (n + h / 30) % 12;
    return l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1));
  };
  const hex = (x) =>
    Math.round(x * 255)
      .toString(16)
      .padStart(2, '0');
  return '#' + hex(f(0)) + hex(f(8)) + hex(f(4));
}

export function rotateHex(hex, delta) {
  const c = hexToHsl(hex);
  return hslToHex(c.h + delta, c.s, c.l);
}

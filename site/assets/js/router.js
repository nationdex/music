// ------------------------------------------------------------------ routes

const ROUTES = [
  { re: /^\/library\/?$/, name: () => 'home', fragment: 'home' },
  { re: /^\/library\/tracks\/?$/, name: () => 'tracks', fragment: 'tracks' },
  {
    re: /^\/library\/(albums|artists|playlists)(?:\/([^/]+))?\/?$/,
    name: (m) => m[1],
    id: (m) => m[2] && decodeURIComponent(m[2]),
    fragment: 'collection'
  },
  { re: /^\/discovery\/?$/, name: () => 'discovery', fragment: 'discovery' },
  { re: /^\/settings\/?$/, name: () => 'settings', fragment: 'settings' },
  { re: /^\/player\/?$/, name: () => 'player', fragment: 'player' }
];

export function resolveRoute(path) {
  const clean = String(path).split(/[?#]/)[0];
  for (const r of ROUTES) {
    const m = clean.match(r.re);
    if (m) return { name: r.name(m), id: r.id ? r.id(m) || null : null, fragment: r.fragment, path: clean };
  }
  return null;
}

# 🎵 Adi Music

A free, open-source music player for the browser. Play your own files, follow synced
lyrics, shape the sound with an equalizer, and organize playlists. The interface uses
Material 3.

## ✨ Features

- 📂 **Your files.** Drop audio, or a ZIP of an album, on the page. Tags, duration and cover art are read in
  the browser and stored locally. Nothing is uploaded.
- 🗂️ **Library views.** Tracks, albums, artists and playlists, all built from your tags.
- 🎤 **Synced lyrics.** Line-level and word-level timing from several providers.
- 🎚️ **10-band equalizer.** 17 presets, a live response curve and spectrum, preamp with automatic
  headroom, a limiter against clipping, on/off, and your own saved presets. It remembers its settings.
  Works with local files and previews.
- ▶️ **Full-length tracks.** Search YouTube in Discovery. When YouTube has no match,
  iTunes 30-second previews are the fallback.
- 📲 **Installable.** Runs as an app on Android, iOS, Windows, macOS and Linux. Works
  offline, with media keys and lock-screen controls. See [Install as an app](#-install-as-an-app).
- 💬 **Discord Rich Presence.** Show the track you are playing as "Listening to" on your Discord
  profile. See [Discord Rich Presence](#-discord-rich-presence).
- 🎨 **Themes.** Light, dark, or automatic. Choose an accent color, or let the cover art
  set the palette.

## 🧰 Stack

| Layer | Tool |
| --- | --- |
| 🧩 UI and logic | HTMX for route fragments and Alpine.js 3.14.9 with the Persist, Anchor, Focus and Intersect plugins |
| 🎨 Styling | Plain CSS. No build step, no Node |
| 🌐 Serving | nginx, configuration only: static files, SSI partials, cached API proxies |
| 💾 Storage | IndexedDB for audio, tags and cover art. localStorage for settings and playlists |
| 📝 Lyrics | [Adi Lyrics](https://lyrics.adi.rest), with LRCLIB and LRC Mux as fallbacks |
| ▶️ Full tracks | YouTube IFrame Player API. Search needs no API key: Innertube first, then Audius (plain audio element), then Apple previews |
| 🍎 Previews | iTunes Search API, 30-second clips |

The browser cannot serve HTTP or keep an API key secret. nginx does both, through a
config file. The project has no custom server code.

## 📁 Structure

```
site/                 everything nginx serves
  index.html          landing page
  app.html            player shell (served for /library/*, /discovery, /settings, /player)
  components/         page fragments fetched by the router
  partials/           SSI includes: icon sprite, select control
  assets/
    css/              shared tokens, utilities, motion, and landing styles
  sw.js               service worker (offline shell)
  manifest.webmanifest  PWA manifest: icons, shortcuts, file handlers, screenshots
    js/               ES modules: app.js (Alpine component), tags, db, lyrics,
                      sources, palette, router, config, util, theme, pwa
    vendor/           pinned HTMX, Alpine and plugins, checked in
  fonts/ images/      M PLUS Rounded 1c subsets, icons, logo, screenshots
deploy/               nginx config, systemd unit, env file, install and prepare scripts
tools/discord-rpc/    optional Discord presence bridge (runs on your computer, not on the server)
mobile/               Flutter app for Android and iOS
tests/smoke.sh        route, header and proxy checks against a running instance
THIRD_PARTY.md        licenses of vendored code
```

## 📱 Mobile app

`mobile/` is a Flutter port for Android and iOS, with Liquid Glass on iOS 26. See
[mobile/README.md](mobile/README.md).

## 💬 Discord Rich Presence

A browser cannot talk to Discord, so a small bridge runs on the same computer as the Discord
desktop app. The page posts what is playing to `http://127.0.0.1:6480`, and the bridge hands it
to Discord as a "Listening to" activity with a progress bar and cover art.

1. Create an application at [discord.com/developers](https://discord.com/developers/applications)
   and copy its **Application ID**. Optionally upload an art asset named `logo` (Rich Presence,
   Art Assets) for tracks without cover art.
2. Start the bridge on the computer that runs Discord. It needs only Python 3.8 or newer:

   ```bash
   python3 tools/discord-rpc/adi-discord-rpc.py
   python3 tools/discord-rpc/adi-discord-rpc.py --origin https://music.example.com   # a public URL
   ```

3. In Settings, turn on Discord, paste the Application ID, and press **Test connection**.

The bridge listens on `127.0.0.1` only. It accepts pages from loopback and private-network
addresses (`localhost`, `192.168.x.x`, `10.x.x.x`, ...) and any `--origin` you add. A page
served from another network than the bridge's computer needs a recent Chrome or Edge, which
asks once for permission to reach local devices. Presence is cleared when the tab closes or
the setting is turned off. The mobile app has no Discord presence: Discord on a phone offers
no local connection for apps to use.

Tests (a fake Discord on a temporary socket): `python3 -m unittest tools/discord-rpc/test_bridge.py`.

## 📲 Install as an app

Adi Music is a PWA: a web app manifest, a service worker, and install prompts.

| Platform | Browser | How |
| --- | --- | --- |
| 🤖 Android | Chrome, Edge, Samsung Internet | Install prompt, or menu, Install app. Settings has an Install button |
| 🤖 Android | Firefox | Menu, Install |
| 🍏 iOS, iPadOS | Safari | Share, Add to Home Screen. iOS has no install prompt API |
| 🪟 Windows | Chrome, Edge | Install icon in the address bar, or Settings, Install |
| 🍎 macOS | Chrome, Edge | Same as Windows |
| 🍎 macOS | Safari 17+ | File, Add to Dock |
| 🐧 Linux | Chrome, Edge, other Chromium browsers | Same as Windows |
| 🦊 Desktop | Firefox | Cannot install web apps |

**HTTPS is required.** Browsers register service workers and offer install only on
`https://` or `localhost`. Over plain HTTP on a LAN address the site works but is not
installable. Put Caddy, or nginx with certificates, in front (see Run).

What the app provides:

- 📴 **Offline.** `site/sw.js` precaches the shell. Your library lives in IndexedDB, so
  local tracks play with no network. Lyrics, Discovery and YouTube need a connection.
- 🔄 **Updates.** Code files load network-first and refresh the cache. When you add or
  remove a file in `SHELL`, bump `CACHE` in `sw.js`.
- 🎛️ **Media controls.** Media Session gives play, pause, previous, next, seek and track
  info to the lock screen, notification shade, media keys and OS overlays.
- 📂 **Open with.** The installed desktop app (Chromium) appears in "Open with" for audio
  files and plays the file you open.
- 🧭 **Shortcuts.** Long-press or right-click the app icon for Tracks, Albums, Playlists
  and Discovery.
- 🎭 **Icons.** Standard and maskable PNGs, an iOS touch icon, and a favicon.

Not included: iOS splash images (iOS shows a plain screen while launching) and Web Share
Target (the nginx proxies are GET-only).

## 🎨 Styling

Edit the stylesheets in `site/assets/css/` directly. `app.css` owns Material 3 tokens and
component styles. `utilities.css` holds shared layout and type classes. `motion.css`
holds entrance and feedback animations.

- **Older Safari.** `light-dark()` needs Safari 17.5. Below that, `app.css` carries a generated
  fallback (`python3 tools/css-compat/fallback.py` regenerates it, `--check` verifies it), the
  accent re-hue in `app.js` resolves the colors itself, and the utility stylesheet includes `-webkit-` prefixes.
  Inputs stay at 16px on touch screens so iOS does not zoom on focus.
- Blobs: Safari can refuse to store a Blob in IndexedDB (private browsing, Lockdown Mode, older
  iOS). `db.js` retries with an ArrayBuffer, so importing keeps working.

## 🚀 Run

```bash
sh deploy/install-service.sh       # installs the user unit (needs nginx)
systemctl --user restart adimusic
journalctl --user -u adimusic -f
sh tests/smoke.sh http://127.0.0.1:3030
```

Settings live in `deploy/adimusic.env`:

| Variable | Default | Effect |
| --- | --- | --- |
| `ADI_HTTP_HOST` | `127.0.0.1` | Bind address. Use `0.0.0.0` for the LAN |
| `ADI_HTTP_PORT` | `3000` | Listen port |

`deploy/prepare.sh` writes these into `run/listen.conf` before nginx starts. TLS is not
handled here. Put Caddy, or nginx with certificates, in front for HTTPS.

## 🛣️ Routes

| Route | Purpose |
| --- | --- |
| `/` | landing page |
| `/library`, `/library/{tracks,albums,artists,playlists}[/id]`, `/discovery`, `/settings`, `/player` | the player: one shell, routed in the browser |
| `/components/*` | HTML fragments, `noindex` |
| `/up/adi/api/lyrics`, `/up/lrclib/api/get`, `/up/lrcmux/compat/kpoe/v2/lyrics/get` | lyrics providers. GET only, cached 6 h |
| `/up/itunes/search` | iTunes previews, cached 30 min |
| `/up/audius/v1/tracks/search`, `/up/audius/v1/tracks/<id>/stream` | Audius public API (GET, no key). Search cached 30 min; the stream is followed through the 302 to a content node, uncached |
| `/up/innertube/search` | YouTube's own web API, the primary search source. The only POST endpoint; body capped at 2 KB, cached 30 min |

Only these exact endpoints are proxied. Anything else under `/up/` returns 404.

## ⚙️ How it works

- **📥 Library.** `js/tags.js` reads ID3v2 (MP3), MP4 atoms (M4A/AAC), and Vorbis comments
  with pictures (FLAC). It has no dependencies. Duration comes from an `<audio>` element,
  and covers are shrunk to 512 px JPEG. Everything is stored in IndexedDB.
- **🧭 Router.** `go(path)` pushes history, loads and caches `/components/<name>` with HTMX, then lets Alpine
  wire up the new markup. The player and its audio element stay alive across pages.
- **🎨 Theme.** The tokens in `app.css` are the single source. A custom accent, or the
  current cover art, re-hues the same palette. Settings persist through Alpine's `$persist`.
- **🔊 Playback.** Local files play through an `<audio>` element routed into a 10-band Web
  Audio equalizer. YouTube tracks play inside YouTube's iframe, so the equalizer does not
  reach them.

## ⚡ Performance and SEO

Measured on a throttled phone profile (1.6 Mbps, 150 ms latency, 4x slower CPU), first visit, against
the version before this work:

| | Before | Now |
| --- | --- | --- |
| Home page, first paint | 1988 ms | 640 ms |
| Home page, transferred | 259 KB | 135 KB |
| Player, first paint | 1996 ms | 604 ms |
| Player, transferred | 200 KB | 158 KB |

What changed:

- **Cache forever, update instantly.** Asset URLs carry `?v=<content hash>` (`deploy/prepare.sh`) and are
  served `immutable`. Pages, the worker and the manifest always revalidate.
- **No request waterfall.** The player's ES modules are `modulepreload`ed, and the CSS reset is inlined
  in `app.css` instead of an `@import`.
- **Smaller files.** The landing screenshot is WebP (24 KB instead of 96 KB), served with `<picture>`.
- **Precompression** (optional): `sh deploy/optimize.sh` builds `dist/` with `.gz` and `.br` copies. nginx
  serves them without compressing per request, and Brotli works without the nginx brotli module.

```bash
sh deploy/optimize.sh               # builds dist/; needs gzip, with optional brotli for .br
systemctl --user restart adimusic   # serves dist/ while it matches site/
```

Every compressed file is decompressed and compared before it is kept.
`dist/` is ignored by Git and served only while it matches `site/`.

**SEO.** Every page includes `partials/seo.html`, which sets the title, description, canonical URL, Open
Graph and Twitter card from a few variables. Set `ADI_PUBLIC_URL` in `deploy/adimusic.env` to the real
https address: it feeds the canonical links, `sitemap.xml`, `robots.txt` and `llms.txt`. The home page
carries JSON-LD (WebSite, SoftwareApplication, FAQPage that mirrors the visible questions); `/privacy`
is a real page; the player routes are `noindex` by meta tag and by header. Unknown URLs return a real 404.

## 🔒 Security

- The CSP allows scripts only from this origin and `www.youtube.com`. `'unsafe-eval'` is
  required by Alpine's standard build. Frames come from YouTube. Media comes from this
  origin and the iTunes preview host.
- No API key is required. `deploy/adimusic.env` (git-ignored, mode 600) only holds optional
  bind settings.
- The proxies accept GET only, except `/up/innertube/search` (POST, one exact endpoint, small
  body). All are rate-limited and cache only 200 and 404 responses. The Innertube request uses
  the public key youtube.com ships in its own pages, so it is not a secret.
- The CSP lets the page connect to `127.0.0.1:6480` for the Discord bridge, and nowhere else
  outside this origin.

## 🧪 Tests

```bash
sh tests/smoke.sh http://127.0.0.1:3030   # routes, SSI, headers, SEO, caching, encodings, PWA assets, node tests
node --test tests/js/                     # equalizer maths and the ZIP reader
python3 -m unittest tools/discord-rpc/test_bridge.py
```

## 📜 Notes

- Lyrics are copyrighted works owned by their rights holders. Check each upstream
  source's terms before a public deployment.
- Licenses for vendored code are in [THIRD_PARTY.md](THIRD_PARTY.md).

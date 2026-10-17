# 🎵 Adi Music

A free, open-source music player for the browser. Play your own files, follow synced
lyrics, shape the sound with an equalizer, and organize playlists. The interface uses
Material 3.

## ✨ Features

- 📂 **Your files.** Drop audio on the page. Tags, duration and cover art are read in
  the browser and stored locally. Nothing is uploaded.
- 🗂️ **Library views.** Tracks, albums, artists and playlists, all built from your tags.
- 🎤 **Synced lyrics.** Line-level and word-level timing from several providers.
- 🎚️ **10-band equalizer.** Includes presets. Works with local files.
- ▶️ **Full-length tracks.** Search YouTube in Discovery. When YouTube has no match,
  iTunes 30-second previews are the fallback.
- 📲 **Installable.** Runs as an app on Android, iOS, Windows, macOS and Linux. Works
  offline, with media keys and lock-screen controls. See [Install as an app](#-install-as-an-app).
- 🎨 **Themes.** Light, dark, or automatic. Choose an accent color, or let the cover art
  set the palette.

## 🧰 Stack

| Layer | Tool |
| --- | --- |
| 🧩 UI and logic | Alpine.js 3.14.9 with the Persist, Anchor, Focus and Intersect plugins |
| 🎨 Styling | [UnoCSS](https://unocss.dev) runtime with `preset-wind4` (Tailwind v4 class names), generated in the browser. No build step, no Node |
| 🌐 Serving | nginx, configuration only: static files, SSI partials, cached API proxies |
| 💾 Storage | IndexedDB for audio, tags and cover art. localStorage for settings and playlists |
| 📝 Lyrics | [Adi Lyrics](https://lyrics.imreallyadi.space), with LRCLIB and LRC Mux as fallbacks |
| ▶️ Full tracks | YouTube IFrame Player API. Search uses the YouTube Data API; the key stays in nginx |
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
    app.css           Material 3 tokens and component CSS
    uno.config.js     UnoCSS config: colors, type scale, breakpoints
  sw.js               service worker (offline shell)
  manifest.webmanifest  PWA manifest: icons, shortcuts, file handlers, screenshots
    js/               ES modules: app.js (Alpine component), tags, db, lyrics,
                      sources, palette, router, config, util, theme, pwa
    vendor/           pinned Alpine, plugins and UnoCSS, checked in
  fonts/ images/      M PLUS Rounded 1c subsets, icons, logo, screenshots
deploy/               nginx config, systemd unit, env file, install and prepare scripts
tests/smoke.sh        route, header and proxy checks against a running instance
THIRD_PARTY.md        licenses of vendored code
```

## 📱 Mobile app

`mobile/` is a Flutter port for Android and iOS, with Liquid Glass on iOS 26. See
[mobile/README.md](mobile/README.md).

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

There is no build step. `site/assets/app.css` holds the Material 3 tokens as
`light-dark()` pairs, plus component CSS for buttons, sliders, switches and dialogs.
Utility classes such as `flex`, `bg-surfaceContainer` and `text-title-md` are generated
in the browser by the vendored UnoCSS runtime.

- The reset is Tailwind v4's preflight (`unocss-reset.css`), placed in `@layer base`.
- The Material 3 type scale (`text-body-md`, `text-title-lg`, ...) is a small preset in
  `uno.config.js`.
- `<html un-cloak>` hides the page until the first stylesheet exists. The router generates
  a page's styles before inserting it, so navigation never flashes unstyled content.
- Tailwind's `max-w-(--var)` shorthand is not supported. Write `max-w-[var(--var)]`.

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
| `YOUTUBE_API_KEY` | empty | Enables full-length Discovery. Never sent to the browser |

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
| `/up/youtube/{search,videos}` | YouTube Data API with the key added server-side, cached 1 h |

Only these exact endpoints are proxied. Anything else under `/up/` returns 404.

## ⚙️ How it works

- **📥 Library.** `js/tags.js` reads ID3v2 (MP3), MP4 atoms (M4A/AAC), and Vorbis comments
  with pictures (FLAC). It has no dependencies. Duration comes from an `<audio>` element,
  and covers are shrunk to 512 px JPEG. Everything is stored in IndexedDB.
- **🧭 Router.** `go(path)` pushes history, fetches `/components/<name>`, and lets Alpine
  wire up the new markup. The player and its audio element stay alive across pages.
- **🎨 Theme.** The tokens in `app.css` are the single source. A custom accent, or the
  current cover art, re-hues the same palette. Settings persist through Alpine's `$persist`.
- **🔊 Playback.** Local files play through an `<audio>` element routed into a 10-band Web
  Audio equalizer. YouTube tracks play inside YouTube's iframe, so the equalizer does not
  reach them.

## 🔒 Security

- The CSP allows scripts only from this origin and `www.youtube.com`. `'unsafe-eval'` is
  required by Alpine's standard build. Frames come from YouTube. Media comes from this
  origin and the iTunes preview host.
- `deploy/adimusic.env` holds the API key. It is git-ignored and set to mode 600. Restrict
  the key to the YouTube Data API in Google Cloud.
- The proxies accept GET only, are rate-limited, and cache only 200 and 404 responses.

## 🧪 Tests

```bash
sh tests/smoke.sh http://127.0.0.1:3030   # routes, SSI, headers, key leakage, proxy allow-list, module syntax, PWA assets
```

## 📜 Notes

- Lyrics are copyrighted works owned by their rights holders. Check each upstream
  source's terms before a public deployment.
- Licenses for vendored code are in [THIRD_PARTY.md](THIRD_PARTY.md).

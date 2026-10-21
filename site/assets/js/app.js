// Adi Music: Alpine.js app (library, router, player) and audio controller.
// Lyrics source: Adi Lyrics aggregator (https://lyrics.adi.rest)

import { DEFAULT_SETTINGS } from './config.js';
import {
  EQ_LABELS,
  EQ_MAX_CUSTOM,
  EQ_PRESETS,
  EQ_RANGE,
  Equalizer,
  autoPreamp,
  clampDb,
  curvePath,
  defaultEq,
  effectivePreamp,
  eqIsActive,
  logFreqs,
  matchPreset,
  normalizeEq,
  responseDb
} from './eq.js';
import { idbAll, idbClear, idbDelete, idbGet, idbPut } from './db.js';
import { parseLRC, parseTTML, resolveLyrics } from './lyrics.js';
import { DEFAULT_SEED_HUE, DEFAULT_TOKENS, hexToHsl, rotateHex } from './palette.js';
import { buildPresence, presence } from './presence.js';
import { pwa } from './pwa.js';
import { resolveRoute } from './router.js';
import { YTBridge, blockedVideos, cleanYouTubeMeta, findYouTubeAlternatives, itunesSearch, youtubeSearch } from './sources.js';
import { compressArtwork, probeDuration, readTags } from './tags.js';
import { slugId } from './util.js';
import { ZipReader, baseName, isZipFile, mimeFor } from './zip.js';

// Object URLs for stored audio blobs, created on first play.
const fileUrls = new Map();

const LIGHT_DARK = typeof CSS !== 'undefined' && CSS.supports('color', 'light-dark(red, blue)');

// Per-track state for finding another upload when a YouTube video cannot be embedded.
let equalizer = null; // not reactive on purpose: Alpine would wrap the AudioNodes in proxies
let spectrumFrame = 0;

const ytFallback = { tried: new Set(), alts: null, altsFor: null, notified: false };

function initAlpineApp() {
  if (!window.Alpine || window.Alpine._adiInitialized) return;
  window.Alpine._adiInitialized = true;

  window.Alpine.data('m3Select', (cfg) => ({
    open: false,
    options: cfg.options,
    get value() {
      return cfg.get();
    },
    get label() {
      const o = this.options.find((x) => x[0] === this.value);
      return o ? o[1] : '';
    },
    toggle() {
      this.open = !this.open;
      if (this.open) this.$nextTick(() => this.focusOption(this.options.findIndex((o) => o[0] === this.value)));
    },
    items() {
      return this.$refs.list ? [...this.$refs.list.querySelectorAll('[role=option]')] : [];
    },
    focusOption(i) {
      const b = this.items();
      (b[Math.max(0, i)] || b[0] || this.$refs.trigger).focus();
    },
    move(d) {
      const b = this.items();
      if (!b.length) return;
      b[(b.indexOf(document.activeElement) + d + b.length) % b.length].focus();
    },
    close() {
      this.open = false;
      this.$refs.trigger.focus();
    },
    choose(v) {
      cfg.set(v);
      this.close();
    }
  }));

  window.Alpine.data('playerApp', () => ({
    // ---- routing / layout
    route: { name: 'tracks', id: null, path: '/library/tracks', fragment: 'tracks' },
    prevPath: '',
    narrow: false,
    dragging: false,
    nav: [
      { path: '/library', name: 'home', icon: 'home', label: 'Library' },
      { path: '/library/tracks', name: 'tracks', icon: 'musicNote', label: 'Tracks' },
      { path: '/library/albums', name: 'albums', icon: 'album', label: 'Albums' },
      { path: '/library/artists', name: 'artists', icon: 'person', label: 'Artists' },
      { path: '/library/playlists', name: 'playlists', icon: 'playlist', label: 'Playlists' },
      { path: '/discovery', name: 'discovery', icon: 'compass', label: 'Discovery' }
    ],

    // ---- library
    tracks: [],
    favoriteIds: [],
    customPlaylists: [],
    history: [],
    searchFilter: '',
    sortKey: Alpine.$persist('name').as('adimusic:sortKey'),
    sortAsc: Alpine.$persist(true).as('adimusic:sortAsc'),

    // ---- playback
    queue: [],
    queueOrig: [],
    queuePos: -1,
    shuffle: Alpine.$persist(false).as('adimusic:shuffle'),
    repeat: Alpine.$persist('off').as('adimusic:repeat'),
    currentTrack: null,
    isPlaying: false,
    currentTime: 0,
    duration: 0,
    volume: 1,
    muted: false,
    playbackSpeed: 1,
    audioEl: null,
    ytMode: false,
    artworkAccent: '',

    // ---- equalizer
    EQ_PRESETS,
    EQ_LABELS,
    EQ_RANGE,
    eq: Alpine.$persist(defaultEq()).as('adimusic:eq'),
    eqCustomName: '',
    eqNaming: false,

    // ---- lyrics
    lyricsContent: '',
    lyricLines: [],
    activeLyricIndex: -1,
    lyricsProvider: '',
    lyricsSyncLevel: '',
    lyricsStatus: 'idle',

    // ---- ui
    settings: Alpine.$persist({ ...DEFAULT_SETTINGS }).as('adimusic:settings'),
    menu: { open: false, ready: false, anchor: null, items: [] },
    snackbars: [],
    dialog: { type: null },

    // =================================================================== boot
    async boot() {
      this.settings = { ...DEFAULT_SETTINGS, ...this.settings }; // fill keys added since the stored copy
      this.audioEl = document.getElementById('audio-player');
      if (typeof this.settings.volume === 'number') this.volume = this.settings.volume;
      if (this.audioEl) {
        this.audioEl.volume = this.volume;
        this.audioEl.preservesPitch = this.settings.preservePitch !== false;
      }
      YTBridge.attach(this);
      this.applyTheme();
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => this.applyTheme());
      window.matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', () => this.applyTheme());

      const mq = window.matchMedia('(max-width: 63.99rem)');
      this.narrow = mq.matches;
      mq.addEventListener('change', (e) => {
        this.narrow = e.matches;
      });

      // Content below the fixed player overlay must never hide under it.
      const overlay = this.$refs.overlay;
      if (overlay && window.ResizeObserver) {
        new ResizeObserver(() => {
          document.documentElement.style.setProperty(
            '--bottom-overlay-height',
            (this.route.name === 'player' ? 0 : overlay.offsetHeight) + 'px'
          );
        }).observe(overlay);
      }

      window.addEventListener('popstate', () => this.go(location.pathname + location.search, { replace: true, fromPop: true }));

      this.setupEqualizer();
      this.setupMediaSession();
      this.setupInstall();
      this.setupPresence();
      this.setupFileLaunch();
      await this.loadLibrary();

      const start = resolveRoute(location.pathname) || resolveRoute('/library/tracks');
      if (!resolveRoute(location.pathname)) history.replaceState({}, '', start.path);
      this.route = start;
      await this.loadFragment(start.fragment);
      this.prewarmStyles();
    },

    // ================================================================= routing
    isNavActive(item) {
      return this.route.name === item.name;
    },
    isNarrow() {
      return this.narrow;
    },

    // Pages are plain HTML fragments; Alpine's mutation observer wires them up.
    async loadFragment(name) {
      const host = document.getElementById('main-view');
      let html;
      try {
        const res = await fetch('/components/' + name);
        html = res.ok ? await res.text() : null;
      } catch {
        html = null;
      }
      html =
        html ||
        '<div class="m-auto p-8 text-center text-title-lg text-error">Could not load this page. Check your connection and reload.</div>';
      // Generate the fragment's utility CSS first so it never paints unstyled.
      await this.styleFor(html);
      host.innerHTML = html;
    },

    // UnoCSS runtime: resolves once the classes found in `html` have been written to the stylesheet.
    styleFor(html) {
      const rt = window.__unocss_runtime;
      return rt && rt.extract ? rt.extract(html).catch(() => {}) : Promise.resolve();
    },

    // Fetch every page once so classes Alpine toggles later (active states, etc.) are already generated.
    prewarmStyles() {
      ['home', 'tracks', 'collection', 'discovery', 'settings', 'player'].forEach((name) => {
        fetch('/components/' + name)
          .then((r) => (r.ok ? r.text() : ''))
          .then((t) => t && this.styleFor(t))
          .catch(() => {});
      });
    },

    async go(path, opts = {}) {
      const next = resolveRoute(path) || resolveRoute('/library/tracks');
      if (!opts.replace && next.path !== location.pathname) history.pushState({}, '', next.path);
      else if (opts.replace && !opts.fromPop) history.replaceState({}, '', next.path);
      const changed = next.fragment !== this.route.fragment;
      this.prevPath = this.route.path;
      this.route = next;
      this.closeMenu();
      document.documentElement.style.setProperty(
        '--bottom-overlay-height',
        next.name === 'player' ? '0px' : (this.$refs.overlay ? this.$refs.overlay.offsetHeight : 0) + 'px'
      );
      if (changed) {
        await this.loadFragment(next.fragment);
        window.scrollTo(0, 0);
      }
    },

    goBack() {
      if (this.prevPath && history.length > 1) history.back();
      else this.go('/library/tracks');
    },

    closeDetail() {
      const base = '/library/' + this.route.name;
      this.go(base);
    },

    // ================================================================ library
    async loadLibrary() {
      try {
        const rows = await idbAll('tracks');
        this.tracks = rows.map((r) => this.hydrateTrack(r));
      } catch (e) {
        console.warn('Library unavailable (IndexedDB):', e);
        this.tracks = [];
      }
      try {
        const lists = JSON.parse(localStorage.getItem('adimusic:lists') || 'null');
        if (lists) {
          this.favoriteIds = lists.favorites || [];
          this.customPlaylists = lists.custom || [];
        }
        const hist = JSON.parse(localStorage.getItem('adimusic:history') || '[]');
        this.history = hist.map((h) => this.tracks.find((t) => t.id === h.id) || h.snapshot).filter(Boolean);
      } catch (e) {
        console.warn('Failed to load playlists/history:', e);
      }
      this.migrateLegacyLibrary();
    },

    // Tracks saved by the previous build lived in localStorage; keep the remote ones.
    migrateLegacyLibrary() {
      try {
        const raw = localStorage.getItem('adimusic:tracks');
        if (!raw) return;
        const legacy = JSON.parse(raw);
        let added = 0;
        for (const t of legacy) {
          const remote = t.source === 'youtube' || (t.url && /^https?:/.test(t.url));
          if (!remote) continue;
          const id = (t.source === 'youtube' ? 'yt_' : 'rm_') + (t.videoId || slugId(t.name + t.artist));
          if (this.tracks.some((x) => x.id === id)) continue;
          this.addRemoteTrack({
            id,
            name: t.name,
            artist: t.artist,
            album: t.album || 'YouTube',
            artwork: t.artwork || null,
            duration: t.duration || 0,
            source: t.source || 'remote',
            videoId: t.videoId || null,
            url: t.url || null
          });
          added++;
        }
        localStorage.removeItem('adimusic:tracks');
        if (added) this.snackbar(added + ' saved track' + (added === 1 ? '' : 's') + ' carried over');
      } catch (e) {
        console.warn('Legacy migration skipped:', e);
      }
    },

    hydrateTrack(row) {
      const t = { ...row };
      if (row.artworkBlob) t.artwork = URL.createObjectURL(row.artworkBlob);
      delete t.artworkBlob;
      return t;
    },

    persistTrack(track, extra = {}) {
      const row = { ...track, ...extra };
      if (row.artwork && row.artwork.startsWith('blob:')) row.artwork = null;
      return idbPut('tracks', row).catch((e) => console.warn('Could not persist track:', e));
    },

    saveLists() {
      try {
        localStorage.setItem('adimusic:lists', JSON.stringify({ favorites: this.favoriteIds, custom: this.customPlaylists }));
        localStorage.setItem(
          'adimusic:history',
          JSON.stringify(this.history.slice(0, 100).map((t) => ({ id: t.id, snapshot: t.stored === false ? t : undefined })))
        );
      } catch (e) {
        console.warn('Failed to save lists:', e);
      }
    },

    // Turns what the user picked into import jobs. Audio files are jobs as they are; a .zip becomes one
    // job per audio member, and a member is only extracted when its turn comes (see zip.js).
    async importJobs(fileList) {
      const exts = /\.(mp3|m4a|m4b|aac|flac|ogg|oga|opus|wav|webm|mp4)$/i;
      const jobs = [];
      for (const f of Array.from(fileList || [])) {
        if (isZipFile(f)) {
          try {
            const zip = await ZipReader.open(f);
            for (const entry of zip.audioEntries()) {
              const name = baseName(entry.name);
              jobs.push({
                key: f.name + '!' + entry.name + ':' + entry.size + ':' + f.lastModified,
                name,
                load: async () => new File([await zip.read(entry)], name, { type: mimeFor(name), lastModified: entry.mtime.getTime() })
              });
            }
          } catch (e) {
            this.snackbar('Could not read “' + f.name + '”: ' + (e.message || 'not a valid ZIP file'));
          }
        } else if ((f.type || '').startsWith('audio/') || exts.test(f.name)) {
          jobs.push({ key: f.name + ':' + f.size + ':' + f.lastModified, name: f.name, load: async () => f });
        }
      }
      return jobs;
    },

    async importFiles(fileList) {
      const jobs = await this.importJobs(fileList);
      if (!jobs.length) {
        this.snackbar('No audio files found');
        return;
      }
      const sid = 'import';
      let added = 0;
      for (let i = 0; i < jobs.length; i++) {
        const job = jobs[i];
        this.snackbar('Importing ' + (i + 1) + ' of ' + jobs.length + '…', { id: sid, duration: 0 });
        const fileKey = job.key;
        if (this.tracks.some((t) => t.fileKey === fileKey)) continue;
        let f;
        try {
          f = await job.load();
        } catch (e) {
          this.snackbar('Skipped “' + job.name + '”: ' + (e.message || 'could not be unzipped'));
          continue;
        }
        const tags = await readTags(f);
        const duration = await probeDuration(f);
        const artwork = tags.picture ? await compressArtwork(tags.picture) : null;
        const artist = (tags.artist || '').trim();
        const track = {
          id: 't_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36),
          fileKey,
          name: tags.title || f.name.replace(/\.[^/.]+$/, ''),
          artist: artist || 'Unknown artist',
          artists: artist ? artist.split(/\s*[,&;]\s*/).filter(Boolean) : ['Unknown artist'],
          albumArtist: tags.albumArtist || '',
          album: tags.album || 'Unknown album',
          year: tags.year || '',
          trackNo: tags.trackNo || 0,
          duration,
          source: 'local',
          stored: true,
          addedAt: Date.now() + i
        };
        try {
          await idbPut('files', { id: track.id, blob: f });
          await this.persistTrack(track, { artworkBlob: artwork });
        } catch (e) {
          console.warn('Could not store file:', e);
          this.snackbar('Storage is full or unavailable');
          break;
        }
        this.tracks.push(this.hydrateTrack({ ...track, artworkBlob: artwork }));
        added++;
      }
      this.dismissSnackbar(sid);
      this.snackbar(added ? added + ' track' + (added === 1 ? '' : 's') + ' added' : 'Nothing new to add');
    },

    onDrop(e) {
      this.dragging = false;
      if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length) this.importFiles(e.dataTransfer.files);
    },

    addRemoteTrack(item) {
      if (this.tracks.some((t) => t.id === item.id)) return;
      const track = {
        id: item.id,
        name: item.name,
        artist: item.artist,
        artists: [item.artist],
        album: item.album || 'Discovery',
        year: '',
        trackNo: 0,
        duration: item.duration || 0,
        artwork: item.artwork || null,
        source: item.source,
        videoId: item.videoId || null,
        url: item.url || null,
        stored: false,
        addedAt: Date.now()
      };
      this.tracks.push(track);
      this.persistTrack(track);
      return track;
    },

    async removeTrack(track) {
      if (this.currentTrack && this.currentTrack.id === track.id) {
        this.audioEl && this.audioEl.pause();
        this.stopYouTube();
        this.currentTrack = null;
        this.isPlaying = false;
        this.currentTime = 0;
        this.duration = 0;
      }
      this.tracks = this.tracks.filter((t) => t.id !== track.id);
      this.queue = this.queue.filter((t) => t.id !== track.id);
      this.queueOrig = this.queueOrig.filter((t) => t.id !== track.id);
      this.history = this.history.filter((t) => t.id !== track.id);
      this.favoriteIds = this.favoriteIds.filter((id) => id !== track.id);
      this.customPlaylists.forEach((p) => {
        p.trackIds = p.trackIds.filter((id) => id !== track.id);
      });
      if (track.artwork && track.artwork.startsWith('blob:')) URL.revokeObjectURL(track.artwork);
      if (fileUrls.has(track.id)) {
        URL.revokeObjectURL(fileUrls.get(track.id));
        fileUrls.delete(track.id);
      }
      await idbDelete('tracks', track.id).catch(() => {});
      await idbDelete('files', track.id).catch(() => {});
      this.saveLists();
      this.snackbar('Removed “' + track.name + '”');
    },

    async clearLibrary() {
      this.audioEl && this.audioEl.pause();
      this.stopYouTube();
      this.currentTrack = null;
      this.isPlaying = false;
      this.queue = [];
      this.queueOrig = [];
      this.queuePos = -1;
      this.tracks.forEach((t) => {
        if (t.artwork && t.artwork.startsWith('blob:')) URL.revokeObjectURL(t.artwork);
      });
      fileUrls.forEach((u) => URL.revokeObjectURL(u));
      fileUrls.clear();
      this.tracks = [];
      this.history = [];
      this.favoriteIds = [];
      this.customPlaylists.forEach((p) => {
        p.trackIds = [];
      });
      await idbClear('tracks').catch(() => {});
      await idbClear('files').catch(() => {});
      this.saveLists();
      this.snackbar('Library cleared');
    },

    // ---- derived collections
    sortValue(t, key) {
      if (key === 'duration' || key === 'addedAt') return t[key] || 0;
      return String(t[key] || '').toLowerCase();
    },

    get filteredTracks() {
      let list = this.tracks.slice();
      const q = (this.searchFilter || '').toLowerCase().trim();
      if (q) list = list.filter((t) => (t.name + ' ' + t.artist + ' ' + t.album).toLowerCase().includes(q));
      const dir = this.sortAsc ? 1 : -1;
      return list.sort((a, b) => {
        const x = this.sortValue(a, this.sortKey),
          y = this.sortValue(b, this.sortKey);
        return (x < y ? -1 : x > y ? 1 : 0) * dir;
      });
    },

    get albums() {
      const map = new Map();
      for (const t of this.tracks) {
        const key = t.album + '\u0000' + (t.albumArtist || t.artist);
        let a = map.get(key);
        if (!a) {
          a = { id: slugId(key), name: t.album, artist: t.albumArtist || t.artist, year: t.year, artwork: null, tracks: [] };
          map.set(key, a);
        }
        a.tracks.push(t);
        if (!a.artwork && t.artwork) a.artwork = t.artwork;
        if (!a.year && t.year) a.year = t.year;
      }
      const dir = this.sortAsc ? 1 : -1;
      return [...map.values()]
        .map((a) => {
          a.tracks.sort((x, y) => (x.trackNo || 999) - (y.trackNo || 999) || x.name.localeCompare(y.name));
          return a;
        })
        .sort((a, b) => a.name.localeCompare(b.name) * dir);
    },

    get artists() {
      const map = new Map();
      for (const t of this.tracks) {
        for (const name of t.artists && t.artists.length ? t.artists : [t.artist]) {
          let a = map.get(name);
          if (!a) {
            a = { id: slugId(name), name, artwork: null, tracks: [], albums: new Set() };
            map.set(name, a);
          }
          a.tracks.push(t);
          a.albums.add(t.album);
          if (!a.artwork && t.artwork) a.artwork = t.artwork;
        }
      }
      const dir = this.sortAsc ? 1 : -1;
      return [...map.values()].sort((a, b) => a.name.localeCompare(b.name) * dir);
    },

    get playlistsView() {
      const resolve = (ids) => ids.map((id) => this.tracks.find((t) => t.id === id)).filter(Boolean);
      const mk = (id, name, ids) => {
        const list = resolve(ids);
        return {
          id,
          name,
          tracks: list,
          artwork: (list.find((t) => t.artwork) || {}).artwork || null,
          meta: list.length + (list.length === 1 ? ' track' : ' tracks')
        };
      };
      return [mk('favorites', 'Favorites', this.favoriteIds), ...this.customPlaylists.map((p) => mk(p.id, p.name, p.trackIds))];
    },

    matchesSearch(text) {
      const q = (this.searchFilter || '').toLowerCase().trim();
      return !q || String(text).toLowerCase().includes(q);
    },
    get filteredAlbums() {
      return this.albums.filter((a) => this.matchesSearch(a.name + ' ' + a.artist));
    },
    get filteredArtists() {
      return this.artists.filter((a) => this.matchesSearch(a.name));
    },
    get filteredPlaylists() {
      return this.playlistsView.filter((p) => this.matchesSearch(p.name));
    },

    collectionDetail() {
      const id = this.route.id;
      if (!id) return null;
      if (this.route.name === 'albums') {
        const a = this.albums.find((x) => x.id === id);
        return (
          a && {
            id,
            name: a.name,
            artist: a.artist,
            artwork: a.artwork,
            tracks: a.tracks,
            meta: (a.year ? a.year + ' • ' : '') + a.tracks.length + (a.tracks.length === 1 ? ' track' : ' tracks')
          }
        );
      }
      if (this.route.name === 'artists') {
        const a = this.artists.find((x) => x.id === id);
        return (
          a && {
            id,
            name: a.name,
            artist: '',
            artwork: a.artwork,
            tracks: a.tracks,
            meta:
              a.albums.size +
              (a.albums.size === 1 ? ' album' : ' albums') +
              ' • ' +
              a.tracks.length +
              (a.tracks.length === 1 ? ' track' : ' tracks')
          }
        );
      }
      const p = this.playlistsView.find((x) => x.id === id);
      return p && { id, name: p.name, artist: '', artwork: p.artwork, tracks: p.tracks, meta: p.meta, playlist: true };
    },

    // ---- favorites / playlists
    isFavorite(track) {
      return !!track && this.favoriteIds.includes(track.id);
    },
    toggleFavorite(track) {
      if (!this.tracks.some((t) => t.id === track.id)) this.addRemoteTrack(track);
      if (this.isFavorite(track)) this.favoriteIds = this.favoriteIds.filter((id) => id !== track.id);
      else this.favoriteIds = [track.id, ...this.favoriteIds];
      this.saveLists();
    },

    createPlaylist(name) {
      const id = 'pl_' + Math.random().toString(36).slice(2, 9);
      this.customPlaylists.push({ id, name: name.trim(), trackIds: [] });
      this.saveLists();
      return id;
    },

    submitNewPlaylist() {
      const name = (this.dialog.name || '').trim();
      if (!name) return;
      const id = this.createPlaylist(name);
      const track = this.dialog.track;
      this.closeDialog();
      if (track) {
        this.addTrackToPlaylist(track, id);
      } else this.snackbar('Playlist “' + name + '” created');
    },

    addTrackToPlaylist(track, plId) {
      const pl = this.customPlaylists.find((p) => p.id === plId);
      if (!pl) return;
      if (!this.tracks.some((t) => t.id === track.id)) this.addRemoteTrack(track);
      if (!pl.trackIds.includes(track.id)) pl.trackIds.push(track.id);
      this.saveLists();
      this.closeDialog();
      this.snackbar('Added to “' + pl.name + '”');
    },

    deletePlaylist(id) {
      this.customPlaylists = this.customPlaylists.filter((p) => p.id !== id);
      this.saveLists();
      if (this.route.id === id) this.closeDetail();
    },

    // =============================================================== playback
    isCurrent(track) {
      return !!this.currentTrack && !!track && this.currentTrack.id === track.id;
    },
    get timelineFrac() {
      return this.duration ? Math.min(1, Math.max(0, this.currentTime / this.duration)) : 0;
    },

    playFromList(list, index) {
      if (!list || !list[index]) return;
      this.queueOrig = list.slice();
      if (this.shuffle) {
        const rest = list.filter((_, i) => i !== index).sort(() => Math.random() - 0.5);
        this.queue = [list[index], ...rest];
        this.queuePos = 0;
      } else {
        this.queue = list.slice();
        this.queuePos = index;
      }
      this.playTrackObj(this.queue[this.queuePos]);
    },

    playShuffled(list) {
      if (!list || !list.length) return;
      this.shuffle = true;
      this.playFromList(list, Math.floor(Math.random() * list.length));
    },

    playQueueIndex(i) {
      if (!this.queue[i]) return;
      this.queuePos = i;
      this.playTrackObj(this.queue[i]);
    },

    removeFromQueue(i) {
      if (i === this.queuePos) return;
      this.queue.splice(i, 1);
      if (i < this.queuePos) this.queuePos -= 1;
    },

    playNext(track) {
      if (!this.queue.length) {
        this.playFromList([track], 0);
        return;
      }
      this.queue.splice(this.queuePos + 1, 0, track);
      this.snackbar('Playing next');
    },

    addToQueue(track) {
      if (!this.queue.length) {
        this.playFromList([track], 0);
        return;
      }
      this.queue.push(track);
      this.snackbar('Added to queue');
    },

    toggleShuffle() {
      this.shuffle = !this.shuffle;
      if (!this.queue.length) return;
      const cur = this.queue[this.queuePos];
      if (this.shuffle) {
        this.queueOrig = this.queue.slice();
        const rest = this.queue.filter((_, i) => i !== this.queuePos).sort(() => Math.random() - 0.5);
        this.queue = [cur, ...rest];
        this.queuePos = 0;
      } else {
        this.queue = this.queueOrig.length ? this.queueOrig.slice() : this.queue;
        this.queuePos = Math.max(
          0,
          this.queue.findIndex((t) => t.id === (cur && cur.id))
        );
      }
    },

    cycleRepeat() {
      this.repeat = this.repeat === 'off' ? 'all' : this.repeat === 'all' ? 'one' : 'off';
    },

    async trackUrl(track) {
      if (track.url) return track.url;
      if (fileUrls.has(track.id)) return fileUrls.get(track.id);
      const row = await idbGet('files', track.id);
      if (!row) return null;
      const url = URL.createObjectURL(row.blob);
      fileUrls.set(track.id, url);
      return url;
    },

    async playTrackObj(track) {
      if (!track) return;
      this.currentTrack = track;
      this.currentTime = 0;
      this.duration = track.duration || 0;
      this.lyricsStatus = 'idle';
      this.addToHistory(track);
      if (track.source === 'youtube') {
        Object.assign(ytFallback, { tried: new Set([track.videoId]), alts: null, altsFor: null, notified: false });
        await this.startYouTube(track);
      } else {
        this.stopYouTube();
        const url = await this.trackUrl(track);
        if (this.currentTrack !== track) return;
        if (!url) {
          this.isPlaying = false;
          this.snackbar('This track’s audio is missing. Import it again.');
          return;
        }
        this.loadSource(url);
        this.audioEl.playbackRate = this.playbackSpeed;
        this.isPlaying = true;
        this.audioEl.play().catch((e) => {
          console.warn('Play interrupted:', e);
          this.isPlaying = false;
        });
      }
      this.fetchLyrics();
      if (this.settings.pickColorFromArtwork && track.artwork) this.extractArtworkColor(track.artwork);
      this.updateMediaSession();
    },

    // Discovery result -> library track when saved, otherwise a transient track.
    trackFromItem(item) {
      const id = (item.source === 'youtube' ? 'yt_' : 'rm_') + (item.videoId || item.id);
      const saved = this.tracks.find(
        (t) =>
          t.id === id ||
          (item.videoId && t.videoId === item.videoId) ||
          (t.stored === false && t.name === item.name && t.artist === item.artist)
      );
      if (saved) return saved;
      return {
        id,
        name: item.name,
        artist: item.artist,
        artists: [item.artist],
        album: item.album || 'Discovery',
        artwork: item.artwork || null,
        duration: item.duration || 0,
        source: item.source || 'remote',
        videoId: item.videoId || null,
        url: item.previewUrl || null,
        stored: false
      };
    },

    addToHistory(track) {
      this.history = [track, ...this.history.filter((t) => t.id !== track.id)].slice(0, 100);
      this.saveLists();
    },

    loadSource(url) {
      this.resumeAudio();
      if (/^https?:/i.test(url)) this.audioEl.crossOrigin = 'anonymous';
      else this.audioEl.removeAttribute('crossorigin');
      this.audioEl.src = url;
    },

    resumeAudio() {
      if (equalizer) equalizer.resume();
    },

    togglePlay() {
      if (!this.currentTrack) {
        if (this.tracks.length) this.playFromList(this.filteredTracks, 0);
        return;
      }
      if (this.ytMode) {
        if (this.isPlaying) {
          YTBridge.pause();
          this.isPlaying = false;
        } else {
          YTBridge.play();
          this.isPlaying = true;
        }
        return;
      }
      if (this.isPlaying) {
        this.audioEl.pause();
        this.isPlaying = false;
      } else {
        this.resumeAudio();
        this.audioEl
          .play()
          .then(() => {
            this.isPlaying = true;
          })
          .catch((e) => console.warn(e));
        this.isPlaying = true;
      }
    },

    nextTrack() {
      if (!this.queue.length) return;
      if (this.repeat === 'one') {
        this.seekTo(0);
        if (!this.isPlaying) this.togglePlay();
        return;
      }
      let pos = this.queuePos + 1;
      if (pos >= this.queue.length) {
        if (this.repeat === 'all') pos = 0;
        else {
          this.stopAtEnd();
          return;
        }
      }
      this.queuePos = pos;
      this.playTrackObj(this.queue[pos]);
    },

    prevTrack() {
      if (!this.queue.length) return;
      if (this.currentTime > 3) {
        this.seekTo(0);
        return;
      }
      let pos = this.queuePos - 1;
      if (pos < 0) pos = this.repeat === 'all' ? this.queue.length - 1 : 0;
      this.queuePos = pos;
      this.playTrackObj(this.queue[pos]);
    },

    stopAtEnd() {
      this.isPlaying = false;
      if (this.ytMode) YTBridge.pause();
      else this.audioEl && this.audioEl.pause();
      this.seekTo(0);
    },

    seek(e) {
      this.seekTo(Number(e.target.value));
    },
    seekToLine(line) {
      if (line && line.t !== null) this.seekTo(line.t);
    },
    seekTo(t) {
      if (this.ytMode) YTBridge.seek(t);
      else if (this.audioEl) this.audioEl.currentTime = t;
      this.currentTime = t;
      this.syncLyricHighlight();
      this.updatePositionState();
      this.syncPresence();
    },

    setVolume(e) {
      this.volume = Number(e.target.value);
      if (this.muted && this.volume > 0) this.muted = false;
      this.applyVolume();
    },

    applyVolume() {
      if (this.audioEl) {
        this.audioEl.volume = this.volume;
        this.audioEl.muted = this.muted;
      }
      YTBridge.setVolume(Math.round(this.volume * 100));
      YTBridge.setMuted(this.muted);
      this.settings.volume = this.volume;
    },

    toggleMute() {
      this.muted = !this.muted;
      if (this.audioEl) this.audioEl.muted = this.muted;
      YTBridge.setMuted(this.muted);
    },

    setSpeed(speed) {
      this.playbackSpeed = Math.round(Number(speed) * 100) / 100;
      if (this.audioEl) this.audioEl.playbackRate = this.playbackSpeed;
    },

    onTimeUpdate() {
      if (this.ytMode) return;
      this.currentTime = this.audioEl.currentTime;
      this.syncLyricHighlight();
    },
    onLoadedMetadata() {
      if (this.ytMode) return;
      const d = this.audioEl.duration;
      if (isFinite(d) && d > 0) {
        this.duration = d;
        if (this.currentTrack && !this.currentTrack.duration) this.currentTrack.duration = d;
      }
    },
    onEnded() {
      this.nextTrack();
    },
    onAudioError() {
      if (!this.currentTrack || this.ytMode) return;
      this.isPlaying = false;
      this.snackbar('Could not play “' + this.currentTrack.name + '”');
    },

    // ---- YouTube
    async startYouTube(track) {
      if (this.audioEl) this.audioEl.pause();
      this.ytMode = true;
      this.isPlaying = true;
      try {
        await YTBridge.load();
        if (!this.ytMode || this.currentTrack !== track) return;
        YTBridge.loadVideo(track.videoId);
        YTBridge.setVolume(Math.round(this.volume * 100));
        YTBridge.setMuted(this.muted);
      } catch (e) {
        console.warn('YouTube playback failed:', e);
        this.onYTError(e.message);
      }
    },
    stopYouTube() {
      if (!this.ytMode) return;
      YTBridge.stop();
      this.ytMode = false;
    },
    onYTState(state) {
      if (!this.ytMode) return;
      if (state === 1) this.isPlaying = true;
      else if (state === 2) this.isPlaying = false;
      else if (state === 0) {
        // Ignore the ENDED that follows a pre-roll ad; only a real end moves to the next track.
        const total = this.currentTrack ? this.currentTrack.duration : 0;
        if (YTBridge.nearEnd(total)) this.onEnded();
      }
    },
    onYTTick({ t, d }) {
      if (!this.ytMode) return;
      this.currentTime = t || 0;
      if (d) this.duration = d;
      this.syncLyricHighlight();
    },
    // 100 (gone), 101 and 150 (embedding blocked by the uploader or label) cannot be fixed by
    // retrying the same video. Try another upload of the song first; skip only if none plays.
    async onYTError(code) {
      const unplayable = ['100', '101', '150'].includes(String(code));
      const track = this.currentTrack;
      if (unplayable && track && track.source === 'youtube' && track.videoId) {
        if (String(code) !== '100') blockedVideos.add(track.videoId);
        if (await this.tryYouTubeAlternative(track)) return;
      }
      this.ytMode = false;
      this.isPlaying = false;
      if (unplayable && this.queue.length > 1 && this.repeat !== 'one') {
        this.snackbar('Skipped: no playable version of this song was found.');
        this.nextTrack();
        return;
      }
      this.snackbar(
        unplayable ? 'This song cannot be played from YouTube.' : 'This video cannot be played here (YouTube error ' + code + ')'
      );
    },

    /** Switches [track] to the next candidate upload. Returns false when there is none left. */
    async tryYouTubeAlternative(track) {
      ytFallback.tried.add(track.videoId);
      if (ytFallback.altsFor !== track.id) {
        ytFallback.altsFor = track.id;
        ytFallback.alts = await findYouTubeAlternatives(track, [...ytFallback.tried]);
        if (this.currentTrack !== track) return true; // the user moved on while searching
      }
      const next = (ytFallback.alts || []).find((a) => !ytFallback.tried.has(a.id) && !blockedVideos.has(a.id));
      if (!next) return false;
      ytFallback.tried.add(next.id);
      track.videoId = next.id;
      if (!track.duration && next.duration) track.duration = next.duration;
      const saved = this.tracks.find((t) => t.id === track.id);
      if (saved) {
        saved.videoId = next.id;
        this.persistTrack(saved);
      }
      if (!ytFallback.notified) {
        ytFallback.notified = true;
        this.snackbar('That upload cannot be embedded. Playing another version of the song.');
      }
      await this.startYouTube(track);
      return true;
    },

    // ---- Discord Rich Presence
    discordStatus: 'off',
    setupPresence() {
      presence.onStatus = (s) => {
        this.discordStatus = s;
      };
      for (const key of ['currentTrack', 'isPlaying', 'settings.discordRpc', 'settings.discordClientId']) {
        this.$watch(key, () => this.syncPresence());
      }
      // Leave nothing behind on Discord when the tab closes.
      window.addEventListener('pagehide', () => {
        if (this.settings.discordRpc)
          fetch('http://127.0.0.1:6480/clear', { method: 'POST', mode: 'no-cors', keepalive: true }).catch(() => {});
      });
    },
    // Debounced: Discord throttles activity updates, and play/track/seek events arrive in bursts.
    syncPresence() {
      clearTimeout(this._presenceTimer);
      this._presenceTimer = setTimeout(() => {
        const s = this.settings;
        if (!s.discordRpc || !/^\d{5,25}$/.test(String(s.discordClientId || '').trim())) {
          if (presence.status !== 'off') presence.clear();
          presence._set('off');
          return;
        }
        if (!this.currentTrack) return presence.clear();
        presence.update(
          buildPresence(s.discordClientId.trim(), this.currentTrack, {
            playing: this.isPlaying,
            position: this.currentTime,
            duration: this.duration || this.currentTrack.duration
          })
        );
      }, 1200);
    },
    async testDiscord() {
      const status = await presence.check();
      const messages = {
        connected: 'Discord is connected.',
        'no-bridge': 'The bridge is not running. Start tools/discord-rpc/adi-discord-rpc.py on this computer.',
        'no-discord': 'The bridge is running, but Discord is not. Open the Discord desktop app.',
        error: 'Discord refused the update. Check the application id.'
      };
      this.snackbar(messages[status] || 'Discord presence is off.');
      this.syncPresence();
    },

    // ---- install (PWA)
    installable: false,
    installed: false,
    installHint: '',
    setupInstall() {
      const sync = () => {
        this.installable = pwa.canPrompt;
        this.installed = pwa.standalone;
        this.installHint = pwa.hint;
      };
      sync();
      pwa.onChange(sync);
    },
    async installApp() {
      if ((await pwa.install()) === 'accepted') this.snackbar('Adi Music installed');
    },
    // Installed desktop app: "Open with" on audio files hands them to launchQueue.
    setupFileLaunch() {
      if (!('launchQueue' in window)) return;
      window.launchQueue.setConsumer(async (params) => {
        if (!params.files || !params.files.length) return;
        const files = await Promise.all(params.files.map((h) => h.getFile()));
        await this.importFiles(files);
        const keys = new Set(files.map((f) => f.name + ':' + f.size + ':' + f.lastModified));
        const first = this.tracks.find((t) => keys.has(t.fileKey));
        if (first) this.playFromList([first], 0);
      });
    },

    // ---- Media Session
    setupMediaSession() {
      if (!('mediaSession' in navigator)) return;
      const ms = navigator.mediaSession;
      ms.setActionHandler('play', () => this.togglePlay());
      ms.setActionHandler('pause', () => this.togglePlay());
      ms.setActionHandler('previoustrack', () => this.prevTrack());
      ms.setActionHandler('nexttrack', () => this.nextTrack());
      ms.setActionHandler('stop', () => this.isPlaying && this.togglePlay());
      ms.setActionHandler('seekbackward', (d) => this.seekTo(Math.max(0, this.currentTime - (d.seekOffset || 10))));
      ms.setActionHandler('seekforward', (d) => this.seekTo(Math.min(this.duration || 0, this.currentTime + (d.seekOffset || 10))));
      try {
        ms.setActionHandler('seekto', (d) => this.seekTo(d.seekTime));
      } catch {}
      this.$watch('isPlaying', (playing) => {
        ms.playbackState = playing ? 'playing' : 'paused';
        this.updatePositionState();
      });
    },
    updatePositionState() {
      if (!('mediaSession' in navigator) || !navigator.mediaSession.setPositionState || !(this.duration > 0)) return;
      try {
        navigator.mediaSession.setPositionState({
          duration: this.duration,
          playbackRate: this.audioEl && !this.ytMode ? this.audioEl.playbackRate || 1 : 1,
          position: Math.min(this.currentTime || 0, this.duration)
        });
      } catch {}
    },
    updateMediaSession() {
      if (!('mediaSession' in navigator) || !this.currentTrack) return;
      const t = this.currentTrack;
      navigator.mediaSession.metadata = new MediaMetadata({
        title: t.name,
        artist: t.artist,
        album: t.album || '',
        artwork: t.artwork ? [{ src: t.artwork }] : []
      });
    },

    // ---- equalizer
    setupEqualizer() {
      this.eq = normalizeEq(JSON.parse(JSON.stringify(this.eq)));
      if (eqIsActive(this.eq)) this.eqSync();
      // The spectrum only animates while the dialog is open and the user has not asked for less motion.
      this.$watch('dialog.type', (type) => (type === 'equalizer' ? this.$nextTick(() => this.startSpectrum()) : this.stopSpectrum()));
      this.$watch('isPlaying', () => this.dialog.type === 'equalizer' && this.startSpectrum());
    },

    // Applies this.eq to the audio. The graph is only built once the equalizer actually does something.
    eqSync() {
      if (!equalizer && eqIsActive(this.eq)) equalizer = new Equalizer(this.audioEl);
      if (equalizer && !equalizer.connected && !equalizer.connect()) return;
      if (equalizer) {
        equalizer.resume();
        equalizer.apply(this.eq);
        if (this.dialog.type === 'equalizer' && !spectrumFrame) this.startSpectrum();
      }
    },
    eqChanged() {
      this.eq.preset = matchPreset(this.eq.gains, this.eq.custom);
      this.eqSync();
    },
    get eqPreamp() {
      return effectivePreamp({ ...this.eq, enabled: true });
    },
    get eqPresetNames() {
      return [...Object.keys(EQ_PRESETS), ...Object.keys(this.eq.custom)];
    },
    get eqIsCustomPreset() {
      return this.eq.preset in this.eq.custom;
    },
    get eqCurve() {
      const dbs = responseDb(this.eq.enabled ? this.eq.gains : EQ_PRESETS.Flat, logFreqs(96), this.eq.enabled ? this.eqPreamp : 0);
      return curvePath(dbs, 300, 96);
    },
    get eqAffectsPlayback() {
      return !this.ytMode;
    },
    updateEqBand(idx, gainVal) {
      this.eq.gains[idx] = clampDb(gainVal);
      this.eqChanged();
    },
    applyEqPreset(name) {
      const gains = EQ_PRESETS[name] || this.eq.custom[name];
      if (!gains) return;
      this.eq.gains = gains.slice();
      this.eq.preset = name;
      this.eqSync();
    },
    setEqPreamp(db) {
      this.eq.preamp = clampDb(db);
      this.eq.auto = false;
      this.eqSync();
    },
    toggleEqAuto() {
      if (this.eq.auto) this.eq.preamp = Math.round(autoPreamp(this.eq.gains) * 2) / 2;
      this.eq.auto = !this.eq.auto;
      this.eqSync();
    },
    toggleEq() {
      this.eq.enabled = !this.eq.enabled;
      this.eqSync();
    },
    resetEq() {
      Object.assign(this.eq, { gains: EQ_PRESETS.Flat.slice(), preset: 'Flat', preamp: 0, auto: true });
      this.eqSync();
    },
    saveEqPreset() {
      const name = this.eqCustomName.trim().slice(0, 24);
      if (!name) return;
      if (name in EQ_PRESETS) return this.snackbar('“' + name + '” is a built-in preset. Pick another name.');
      if (!(name in this.eq.custom) && Object.keys(this.eq.custom).length >= EQ_MAX_CUSTOM)
        return this.snackbar('You can keep up to ' + EQ_MAX_CUSTOM + ' presets.');
      this.eq.custom = { ...this.eq.custom, [name]: this.eq.gains.slice() };
      this.eq.preset = name;
      this.eqCustomName = '';
      this.eqNaming = false;
      this.snackbar('Saved preset “' + name + '”');
    },
    deleteEqPreset() {
      const name = this.eq.preset;
      if (!(name in this.eq.custom)) return;
      const rest = { ...this.eq.custom };
      delete rest[name];
      this.eq.custom = rest;
      this.eq.preset = matchPreset(this.eq.gains, rest);
      this.snackbar('Deleted preset “' + name + '”');
    },

    // Live spectrum behind the response curve.
    startSpectrum() {
      this.stopSpectrum();
      const canvas = document.getElementById('eq-spectrum');
      const reduced = document.documentElement.classList.contains('reduce-motion');
      if (!canvas || reduced || !equalizer || !equalizer.connected || !this.isPlaying || this.ytMode) return;
      const g = canvas.getContext('2d');
      const bins = new Uint8Array(equalizer.binCount);
      const draw = () => {
        spectrumFrame = requestAnimationFrame(draw);
        if (!equalizer.spectrum(bins)) return;
        const { width: w, height: h } = canvas;
        g.clearRect(0, 0, w, h);
        g.fillStyle = getComputedStyle(canvas).color;
        g.globalAlpha = 0.3;
        const nyquist = equalizer.ctx.sampleRate / 2;
        const bars = 48;
        for (let i = 0; i < bars; i++) {
          // Log-spaced bars so the low end is not squeezed into the first few pixels.
          const lo = 20 * Math.pow(1000, i / bars),
            hi = 20 * Math.pow(1000, (i + 1) / bars);
          const a = Math.floor((lo / nyquist) * bins.length),
            b = Math.max(a + 1, Math.floor((hi / nyquist) * bins.length));
          let peak = 0;
          for (let k = a; k < b && k < bins.length; k++) peak = Math.max(peak, bins[k]);
          const bh = (peak / 255) * h;
          g.fillRect((i * w) / bars + 1, h - bh, w / bars - 2, bh);
        }
      };
      draw();
    },
    stopSpectrum() {
      if (spectrumFrame) cancelAnimationFrame(spectrumFrame);
      spectrumFrame = 0;
    },

    // ================================================================= lyrics
    syncLyricHighlight() {
      if (!this.lyricLines.length) {
        this.activeLyricIndex = -1;
        return;
      }
      const now = this.currentTime;
      let idx = -1;
      for (let i = 0; i < this.lyricLines.length; i++) {
        if (this.lyricLines[i].t <= now) idx = i;
        else break;
      }
      if (idx !== this.activeLyricIndex) {
        this.activeLyricIndex = idx;
        const el = document.querySelector('[data-lyric-active="true"]');
        if (el && typeof el.scrollIntoView === 'function') el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      }
    },

    applyLyrics(data) {
      const synced = data.syncedLyrics || '';
      const ttml = data.ttml || '';
      const plain = data.plainLyrics || '';
      this.lyricsProvider = data.provider || data.source || 'unknown';
      this.lyricsSyncLevel = data.syncLevel || (synced ? 'line' : 'plain');
      let parsed = parseLRC(synced);
      if (!parsed.length && ttml) parsed = parseTTML(ttml);
      if (parsed.length) {
        this.lyricLines = parsed;
        this.lyricsContent = parsed.map((l) => l.text).join('\n');
      } else {
        this.lyricLines = [];
        this.lyricsContent = plain || '';
      }
      this.lyricsStatus = this.lyricLines.length ? 'synced' : plain ? 'plain' : 'none';
      this.syncLyricHighlight();
    },

    async fetchLyrics() {
      const track = this.currentTrack;
      if (!track || !track.name) return;
      this.lyricsStatus = 'loading';
      this.lyricsContent = '';
      this.lyricLines = [];
      this.activeLyricIndex = -1;
      const dur = this.duration || track.duration;
      const record = await resolveLyrics({
        title: track.name,
        artist: track.artist || '',
        album: track.album || '',
        duration: dur,
        prefer: this.settings.lyricsPrefer || 'word',
        provider: this.settings.lyricsProvider || 'auto'
      });
      if (this.currentTrack !== track) return;
      if (record) this.applyLyrics(record);
      else {
        this.lyricsStatus = 'none';
        this.lyricsContent = '';
      }
    },

    // ================================================================== theme
    applyTheme() {
      const pref = this.settings.theme || 'auto';
      const systemDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      const dark = pref === 'dark' || (pref !== 'light' && systemDark);
      const root = document.documentElement;
      root.classList.toggle('dark', dark);
      const reduced =
        this.settings.motion === 'reduced' ||
        (this.settings.motion !== 'full' && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
      root.classList.toggle('reduce-motion', reduced);

      const accent = this.effectiveAccent();
      for (const [name, pair] of Object.entries(DEFAULT_TOKENS)) {
        const prop = '--color-' + name;
        if (!accent) {
          root.style.removeProperty(prop);
          continue;
        }
        const delta = hexToHsl(accent).h - DEFAULT_SEED_HUE;
        const light = rotateHex(pair[0], delta),
          darkValue = rotateHex(pair[1], delta);
        // Safari before 17.5 has no light-dark(): hand it the side that is active.
        root.style.setProperty(prop, LIGHT_DARK ? 'light-dark(' + light + ', ' + darkValue + ')' : dark ? darkValue : light);
      }
      const meta = document.querySelectorAll('meta[name="theme-color"]');
      meta.forEach((m) =>
        m.setAttribute('content', getComputedStyle(root).getPropertyValue('--color-surface').trim() || (dark ? '#271816' : '#fff8f7'))
      );
    },

    // Artwork colour (when enabled and available) wins over the manual accent.
    effectiveAccent() {
      if (this.settings.pickColorFromArtwork && this.artworkAccent) return this.artworkAccent;
      return this.settings.accent || '';
    },

    setAccent(hex) {
      this.settings.accent = hex;
      this.settings.pickColorFromArtwork = false;
      this.persistSettings();
    },

    persistSettings() {
      this.applyTheme();
      if (this.audioEl) this.audioEl.preservesPitch = this.settings.preservePitch !== false;
    },

    extractArtworkColor(imageUrl) {
      try {
        const img = new Image();
        img.crossOrigin = 'Anonymous';
        img.onload = () => {
          try {
            const canvas = document.createElement('canvas');
            canvas.width = canvas.height = 1;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0, 1, 1);
            const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
            const hex = '#' + [r, g, b].map((v) => v.toString(16).padStart(2, '0')).join('');
            this.artworkAccent = hexToHsl(hex).s >= 12 ? hex : '';
            this.applyTheme();
          } catch {
            /* cross-origin artwork: keep the current colours */
          }
        };
        img.src = imageUrl;
      } catch (e) {
        console.warn('Artwork colour extraction skipped:', e);
      }
    },

    // ================================================================= backup
    exportBackup() {
      const payload = {
        version: 2,
        exportedAt: new Date().toISOString(),
        settings: this.settings,
        favorites: this.favoriteIds,
        playlists: this.customPlaylists,
        remoteTracks: this.tracks
          .filter((t) => t.source !== 'local')
          .map((t) => ({
            id: t.id,
            name: t.name,
            artist: t.artist,
            album: t.album,
            artwork: t.artwork,
            duration: t.duration,
            source: t.source,
            videoId: t.videoId,
            url: t.url
          }))
      };
      const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'adimusic-backup-' + new Date().toISOString().slice(0, 10) + '.json';
      a.click();
      URL.revokeObjectURL(url);
    },

    importBackup(event) {
      const file = event.target.files && event.target.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = (e) => {
        try {
          const data = JSON.parse(e.target.result);
          if (data.settings) this.settings = { ...DEFAULT_SETTINGS, ...data.settings };
          if (Array.isArray(data.favorites)) this.favoriteIds = data.favorites;
          if (Array.isArray(data.playlists)) this.customPlaylists = data.playlists;
          (data.remoteTracks || []).forEach((t) => this.addRemoteTrack(t));
          this.persistSettings();
          this.saveLists();
          this.snackbar('Backup restored');
        } catch {
          this.snackbar('That file is not a valid backup');
        }
      };
      reader.readAsText(file);
      event.target.value = '';
    },

    // ================================================================== menus
    openMenu(e, items) {
      let anchor = e.currentTarget && e.currentTarget.nodeType === 1 ? e.currentTarget : null;
      if (e.type === 'contextmenu' || !anchor) {
        // Right-click: anchor the menu to a zero-size element parked at the cursor.
        anchor = this.$refs.menuGhost;
        anchor.style.left = e.clientX + 'px';
        anchor.style.top = e.clientY + 'px';
      }
      this.menu = { open: true, ready: false, anchor, items };
      // Arm the focus trap once the items have rendered.
      this.$nextTick(() => {
        if (this.menu.open) this.menu.ready = true;
      });
    },
    closeMenu() {
      this.menu = { ...this.menu, open: false, ready: false };
    },
    runMenuItem(item) {
      this.closeMenu();
      item.run();
    },

    openTrackMenu(e, track) {
      this.openMenu(e, [
        { icon: 'play', label: 'Play next', run: () => this.playNext(track) },
        { icon: 'playlist', label: 'Add to queue', run: () => this.addToQueue(track) },
        { icon: 'addPlaylist', label: 'Add to playlist', run: () => this.openDialog('addToPlaylist', { track }) },
        {
          icon: 'trashOutline',
          label: 'Remove from library',
          run: () =>
            this.openDialog('confirm', {
              title: 'Remove from library?',
              body: '“' + track.name + '” will be removed from this browser.',
              confirmLabel: 'Remove',
              onConfirm: () => this.removeTrack(track)
            })
        }
      ]);
    },

    openSortMenu(e) {
      const keys = [
        ['name', 'Name'],
        ['artist', 'Artist'],
        ['album', 'Album'],
        ['duration', 'Duration'],
        ['addedAt', 'Date added']
      ];
      this.openMenu(
        e,
        keys.map(([k, label]) => ({
          icon: this.sortKey === k ? 'check' : 'sort',
          label,
          run: () => {
            this.sortKey = k;
          }
        }))
      );
    },

    openLibraryMenu(e) {
      this.openMenu(e, [
        {
          icon: 'plus',
          label: 'Import tracks',
          run: () => {
            const i = document.createElement('input');
            i.type = 'file';
            i.multiple = true;
            i.accept = 'audio/*,.zip,application/zip';
            i.onchange = () => this.importFiles(i.files);
            i.click();
          }
        },
        { icon: 'compass', label: 'Discover music', run: () => this.go('/discovery') }
      ]);
    },

    openDetailMenu(e, d) {
      if (!d) return;
      const items = [
        {
          icon: 'play',
          label: 'Play next',
          run: () =>
            d.tracks
              .slice()
              .reverse()
              .forEach((t) => this.playNext(t))
        },
        { icon: 'playlist', label: 'Add to queue', run: () => d.tracks.forEach((t) => this.addToQueue(t)) }
      ];
      if (d.playlist && d.id !== 'favorites')
        items.push({
          icon: 'trashOutline',
          label: 'Delete playlist',
          run: () =>
            this.openDialog('confirm', {
              title: 'Delete playlist?',
              body: '“' + d.name + '” will be deleted. Your tracks stay in the library.',
              confirmLabel: 'Delete',
              onConfirm: () => this.deletePlaylist(d.id)
            })
        });
      this.openMenu(e, items);
    },

    openDiscoveryMenu(e) {
      this.openMenu(e, [
        {
          icon: 'cached',
          label: this.settings.discoverySource === 'youtube' ? 'Use Apple previews' : 'Use YouTube',
          run: () => {
            this.settings.discoverySource = this.settings.discoverySource === 'youtube' ? 'itunes' : 'youtube';
            this.persistSettings();
            this.snackbar('Discovery source changed. Search again.');
          }
        }
      ]);
    },

    // =============================================================== snackbars
    snackbar(message, opts = {}) {
      const id = opts.id || 's' + Date.now() + Math.random().toString(36).slice(2, 5);
      const entry = { id, message, action: opts.action || null };
      const i = this.snackbars.findIndex((s) => s.id === id);
      if (i >= 0) this.snackbars.splice(i, 1, entry);
      else this.snackbars.push(entry);
      if (opts.duration !== 0) setTimeout(() => this.dismissSnackbar(id), opts.duration || 4000);
    },
    dismissSnackbar(id) {
      this.snackbars = this.snackbars.filter((s) => s.id !== id);
    },

    // ================================================================ dialogs
    openDialog(type, extra = {}) {
      this.closeMenu();
      this.dialog = { type, name: '', ...extra };
    },
    closeDialog() {
      this.dialog = { type: null };
    },
    syncDialog(el, type) {
      const open = this.dialog.type === type;
      if (open && !el.open) {
        el.showModal();
        if (type === 'newPlaylist') this.$nextTick(() => this.$refs.newPlaylistName && this.$refs.newPlaylistName.focus());
      } else if (!open && el.open) el.close();
    },
    onDialogClose(type) {
      if (this.dialog.type === type) this.closeDialog();
    },
    confirmDialog() {
      const fn = this.dialog.onConfirm;
      this.closeDialog();
      if (fn) fn();
    },

    // =============================================================== keyboard
    onKey(e) {
      const tag = e.target && e.target.tagName ? e.target.tagName.toLowerCase() : '';
      if (tag === 'input' || tag === 'textarea' || tag === 'select' || this.dialog.type) return;
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      if (e.code === 'Space' && tag !== 'button') {
        e.preventDefault();
        this.togglePlay();
      } else if (e.code === 'ArrowRight') {
        e.preventDefault();
        this.seekTo(Math.min(this.duration || 0, this.currentTime + 5));
      } else if (e.code === 'ArrowLeft') {
        e.preventDefault();
        this.seekTo(Math.max(0, this.currentTime - 5));
      } else if (e.code === 'ArrowUp') {
        e.preventDefault();
        this.volume = Math.min(1, Math.round((this.volume + 0.05) * 100) / 100);
        this.applyVolume();
      } else if (e.code === 'ArrowDown') {
        e.preventDefault();
        this.volume = Math.max(0, Math.round((this.volume - 0.05) * 100) / 100);
        this.applyVolume();
      } else if (e.key === 'm' || e.key === 'M') {
        e.preventDefault();
        this.toggleMute();
      }
    },

    // ================================================================= format
    formatTime(sec) {
      if (!sec || !isFinite(sec) || sec < 0) return '00:00';
      const s = Math.floor(sec);
      const h = Math.floor(s / 3600),
        m = Math.floor((s % 3600) / 60),
        r = s % 60;
      const pad = (n) => String(n).padStart(2, '0');
      return h ? h + ':' + pad(m) + ':' + pad(r) : pad(m) + ':' + pad(r);
    }
  }));

  // ------------------------------------------------------------- discovery
  window.Alpine.data('discoveryView', () => ({
    query: '',
    loading: false,
    error: '',
    results: [],
    title: 'Top Hits',
    source: 'youtube',

    app() {
      return window.Alpine.$data(document.body);
    },

    init() {
      this.search('Top Hits', true);
    },

    async search(term, initial = false) {
      term = (term || '').trim();
      if (!term) return;
      this.loading = true;
      this.error = '';
      this.title = initial ? 'Top Hits' : 'Songs';
      const wantYouTube = this.app().settings.discoverySource !== 'itunes';
      try {
        let rows = null;
        if (wantYouTube) {
          try {
            rows = await youtubeSearch(term, 24);
          } catch (e) {
            if (!e.status) throw e; /* no key / quota spent: fall back to previews */
          }
        }
        if (rows) {
          this.source = 'youtube';
          this.results = rows.map((r) => {
            const m = cleanYouTubeMeta(r.title, r.channel);
            return {
              id: r.id,
              videoId: r.id,
              name: m.name,
              artist: m.artist,
              album: 'YouTube',
              artwork: r.artwork,
              duration: r.duration || 0,
              source: 'youtube',
              previewUrl: null
            };
          });
        } else {
          // Chosen in Settings, or YouTube unavailable: 30-second Apple previews.
          const data = await itunesSearch(term, 24);
          this.source = 'itunes';
          this.results = data
            .map((r) => ({
              id: r.trackId,
              name: r.trackName,
              artist: r.artistName,
              album: r.collectionName,
              artwork: (r.artworkUrl100 || '').replace('100x100', '600x600'),
              previewUrl: r.previewUrl,
              duration: Math.round((r.trackTimeMillis || 0) / 1000),
              source: 'remote'
            }))
            .filter((r) => r.previewUrl);
        }
      } catch (e) {
        console.error('Discovery search error:', e);
        this.results = [];
        this.error = 'Failed to fetch';
      } finally {
        this.loading = false;
      }
    },

    play(item) {
      const app = this.app();
      const list = this.results.map((r) => app.trackFromItem(r));
      app.playFromList(list, this.results.indexOf(item));
    },

    isItemPlaying(item) {
      const cur = this.app().currentTrack;
      if (!cur || !this.app().isPlaying) return false;
      return (item.videoId && cur.videoId === item.videoId) || (cur.name === item.name && cur.artist === item.artist);
    },

    isSaved(item) {
      return this.app().tracks.some(
        (t) => (item.videoId && t.videoId === item.videoId) || (t.stored === false && t.name === item.name && t.artist === item.artist)
      );
    },

    save(item) {
      const app = this.app();
      const t = app.trackFromItem(item);
      if (app.tracks.some((x) => x.id === t.id)) return;
      app.addRemoteTrack({
        id: t.id,
        name: t.name,
        artist: t.artist,
        album: t.album,
        artwork: t.artwork,
        duration: t.duration,
        source: t.source,
        videoId: t.videoId,
        url: t.url
      });
      app.snackbar('Added to your library');
    }
  }));
}

document.addEventListener('alpine:init', initAlpineApp);
if (window.Alpine) initAlpineApp();

window.parseLRC = parseLRC;
window.parseTTML = parseTTML;

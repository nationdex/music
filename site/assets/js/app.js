// Adi Music: Alpine.js app (library, router, player) and audio controller.
// Lyrics source: Adi Lyrics aggregator (https://lyrics.imreallyadi.space)

import { DEFAULT_SETTINGS, EQ_PRESETS } from './config.js';
import { idbAll, idbClear, idbDelete, idbGet, idbPut } from './db.js';
import { parseLRC, parseTTML, resolveLyrics } from './lyrics.js';
import { DEFAULT_SEED_HUE, DEFAULT_TOKENS, hexToHsl, rotateHex } from './palette.js';
import { resolveRoute } from './router.js';
import { YTBridge, cleanYouTubeMeta, itunesSearch, youtubeSearch } from './sources.js';
import { compressArtwork, probeDuration, readTags } from './tags.js';
import { slugId } from './util.js';

// Object URLs for stored audio blobs, created on first play.
const fileUrls = new Map();

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
    audioCtx: null,
    eqSource: null,
    eqFilters: [],
    selectedEqPreset: 'Flat',
    eqBands: [
      { freq: '32Hz', f: 32, gain: 0 },
      { freq: '64Hz', f: 64, gain: 0 },
      { freq: '125Hz', f: 125, gain: 0 },
      { freq: '250Hz', f: 250, gain: 0 },
      { freq: '500Hz', f: 500, gain: 0 },
      { freq: '1kHz', f: 1000, gain: 0 },
      { freq: '2kHz', f: 2000, gain: 0 },
      { freq: '4kHz', f: 4000, gain: 0 },
      { freq: '8kHz', f: 8000, gain: 0 },
      { freq: '16kHz', f: 16000, gain: 0 }
    ],

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

      this.initEqualizerAudioGraph();
      this.setupMediaSession();
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

    async importFiles(fileList) {
      const exts = /\.(mp3|m4a|m4b|aac|flac|ogg|oga|opus|wav|webm|mp4)$/i;
      const files = Array.from(fileList || []).filter((f) => (f.type || '').startsWith('audio/') || exts.test(f.name));
      if (!files.length) {
        this.snackbar('No audio files found');
        return;
      }
      const sid = 'import';
      let added = 0;
      for (let i = 0; i < files.length; i++) {
        const f = files[i];
        this.snackbar('Importing ' + (i + 1) + ' of ' + files.length + '…', { id: sid, duration: 0 });
        const fileKey = f.name + ':' + f.size + ':' + f.lastModified;
        if (this.tracks.some((t) => t.fileKey === fileKey)) continue;
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
      if (this.audioCtx && this.audioCtx.state === 'suspended') {
        this.audioCtx.resume().catch((e) => console.warn('AudioContext resume failed:', e));
      }
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
      else if (state === 0) this.onEnded();
    },
    onYTTick({ t, d }) {
      if (!this.ytMode) return;
      this.currentTime = t || 0;
      if (d) this.duration = d;
      this.syncLyricHighlight();
    },
    onYTError(code) {
      this.ytMode = false;
      this.isPlaying = false;
      this.snackbar('This video cannot be played here (YouTube error ' + code + ')');
    },

    // ---- Media Session
    setupMediaSession() {
      if (!('mediaSession' in navigator)) return;
      const ms = navigator.mediaSession;
      ms.setActionHandler('play', () => this.togglePlay());
      ms.setActionHandler('pause', () => this.togglePlay());
      ms.setActionHandler('previoustrack', () => this.prevTrack());
      ms.setActionHandler('nexttrack', () => this.nextTrack());
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
    initEqualizerAudioGraph() {
      if (!this.audioEl || this.audioCtx) return;
      try {
        const AudioContext = window.AudioContext || window.webkitAudioContext;
        if (!AudioContext) return;
        this.audioCtx = new AudioContext();
        this.eqSource = this.audioCtx.createMediaElementSource(this.audioEl);
        let last = this.eqSource;
        this.eqFilters = this.eqBands.map((band, idx) => {
          const filter = this.audioCtx.createBiquadFilter();
          if (idx === 0) filter.type = 'lowshelf';
          else if (idx === this.eqBands.length - 1) filter.type = 'highshelf';
          else {
            filter.type = 'peaking';
            filter.Q.value = 1.4;
          }
          filter.frequency.value = band.f;
          filter.gain.value = band.gain || 0;
          last.connect(filter);
          last = filter;
          return filter;
        });
        last.connect(this.audioCtx.destination);
      } catch (e) {
        console.warn('Web Audio equalizer unavailable:', e);
      }
    },
    updateEqBand(idx, gainVal) {
      const val = Number(gainVal);
      if (this.eqBands[idx]) this.eqBands[idx].gain = val;
      this.resumeAudio();
      if (this.eqFilters[idx]) this.eqFilters[idx].gain.value = val;
    },
    applyEqPreset(name) {
      this.selectedEqPreset = name;
      const gains = EQ_PRESETS[name] || EQ_PRESETS.Flat;
      this.eqBands.forEach((_, i) => this.updateEqBand(i, gains[i] || 0));
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
        root.style.setProperty(prop, 'light-dark(' + rotateHex(pair[0], delta) + ', ' + rotateHex(pair[1], delta) + ')');
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
            i.accept = 'audio/*';
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

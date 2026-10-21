/// The library: tracks, favourites, playlists and history, plus the derived
/// albums, artists and playlist views. Ported from the library sections of
/// site/assets/js/app.js.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../core/config.dart';
import '../core/format.dart';
import '../data/models.dart';
import '../data/settings.dart';
import '../data/storage.dart';
import '../services/tag_reader.dart';
import '../services/zip_reader.dart';

/// A file chosen by the user (file picker, share sheet, "Open with").
class ImportSource {
  const ImportSource({required this.path, required this.name});
  final String path;
  final String name;
}

typedef DurationProbe = Future<double?> Function(String path);

final _audioExt = RegExp(
  r'\.(mp3|m4a|m4b|aac|flac|ogg|oga|opus|wav|webm|mp4|aif|aiff|ape)$',
  caseSensitive: false,
);

Future<double?> _probeWithPlayer(String path) async {
  final player = AudioPlayer();
  try {
    final d = await player.setFilePath(path);
    return d == null ? null : d.inMilliseconds / 1000;
  } catch (_) {
    return null;
  } finally {
    await player.dispose();
  }
}

class _ImportJob {
  const _ImportJob({
    required this.name,
    required this.key,
    required this.write,
  });

  final String name;
  final String key;

  /// Puts the audio at [dest]: a copy for a plain file, an extraction for a ZIP member.
  final Future<void> Function(File dest) write;
}

class LibraryController extends ChangeNotifier {
  LibraryController(
    this._storage, {
    DurationProbe? probeDuration,
    Random? random,
  }) : _probe = probeDuration ?? _probeWithPlayer,
       _random = random ?? Random();

  final Storage _storage;
  final DurationProbe _probe;
  final Random _random;

  final List<Track> tracks = [];
  List<String> favoriteIds = [];
  final List<Playlist> customPlaylists = [];
  List<Track> history = [];

  String sortKey = 'name';
  bool sortAsc = true;

  /// Progress text while importing ("Importing 3 of 12…"), null when idle.
  String? importStatus;

  /// Called with the ids of tracks that were just removed so playback can stop.
  void Function(Set<String> ids)? onTracksRemoved;

  // Bumped on every mutation; derived views are cached per version.
  int _version = 0;
  int _cacheVersion = -1;
  List<Collection>? _albums, _artists;

  void _changed() {
    _version++;
    notifyListeners();
  }

  // -------------------------------------------------------------------- load

  Future<void> load() async {
    tracks
      ..clear()
      ..addAll(await _storage.readLibrary());
    final lists = _storage.readLists();
    favoriteIds = lists.favorites;
    customPlaylists
      ..clear()
      ..addAll(lists.playlists);
    history = [];
    for (final h in _storage.readHistory()) {
      final snapshot = h['snapshot'];
      final track =
          _byId(h['id'] as String?) ??
          (snapshot is Map<String, dynamic> ? Track.fromJson(snapshot) : null);
      if (track != null) history.add(track);
    }
    sortKey = _storage.getString('adimusic:sortKey') ?? 'name';
    sortAsc = _storage.getBool('adimusic:sortAsc') ?? true;
    _changed();
  }

  Track? _byId(String? id) {
    if (id == null) return null;
    for (final t in tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Track? trackById(String id) => _byId(id);

  File? audioFileFor(Track t) =>
      t.audioFile == null ? null : _storage.audioFile(t.audioFile!);
  File? artworkFileFor(Track t) =>
      t.artworkFile == null ? null : _storage.artworkFile(t.artworkFile!);

  Future<void> _saveTracks() => _storage.writeLibrary(tracks);

  /// Completes when all pending writes are on disk.
  Future<void> flush() => _storage.flush();
  Future<void> _saveLists() async {
    await _storage.writeLists(favoriteIds, customPlaylists);
    await _storage.writeHistory(history, limit: AppConfig.historyLimit);
  }

  // ----------------------------------------------------------------- import

  /// Things that went wrong in the last [importFiles] (damaged ZIP members, unreadable archives).
  List<String> importProblems = [];

  /// Turns what the user picked into import jobs. A `.zip` becomes one job per audio member; a
  /// member is only extracted when its turn comes (see zip_reader.dart).
  Future<List<_ImportJob>> _jobsFor(List<ImportSource> files) async {
    final jobs = <_ImportJob>[];
    for (final f in files) {
      if (isZipPath(f.name)) {
        try {
          final zip = await ZipArchive.open(File(f.path));
          final stat = await File(f.path).stat();
          for (final e in zip.audioEntries) {
            jobs.add(
              _ImportJob(
                name: e.baseName,
                key:
                    '${f.name}!${e.name}:${e.size}:${stat.modified.millisecondsSinceEpoch}',
                write: (dest) => zip.extractTo(e, dest),
              ),
            );
          }
        } on ZipException catch (e) {
          importProblems.add('Could not read “${f.name}”: ${e.message}');
        }
      } else if (_audioExt.hasMatch(f.name)) {
        final src = File(f.path);
        final stat = await src.stat();
        jobs.add(
          _ImportJob(
            name: f.name,
            key:
                '${f.name}:${stat.size}:${stat.modified.millisecondsSinceEpoch}',
            write: (dest) async {
              await src.copy(dest.path);
            },
          ),
        );
      }
    }
    return jobs;
  }

  /// Copies each audio file into app storage (extracting ZIP members as it goes), reads its tags
  /// and cover, and adds it. Returns the tracks that were added; already-imported files are skipped.
  Future<List<Track>> importFiles(List<ImportSource> files) async {
    importProblems = [];
    final added = <Track>[];
    final jobs = await _jobsFor(files);
    if (jobs.isEmpty) return added;

    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      importStatus = 'Importing ${i + 1} of ${jobs.length}…';
      notifyListeners();

      final fileKey = job.key;
      if (tracks.any((t) => t.fileKey == fileKey)) continue;

      final id =
          't_${_random.nextInt(1 << 32).toRadixString(36)}${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      final ext = p.extension(job.name).toLowerCase();
      final audioName = '$id$ext';
      final dest = _storage.audioFile(audioName);
      try {
        await job.write(dest);
      } on ZipException catch (e) {
        importProblems.add('Skipped “${job.name}”: ${e.message}');
        continue;
      } catch (e) {
        debugPrint('Could not copy ${job.name}: $e');
        importStatus = null;
        notifyListeners();
        throw const FileSystemException('Storage is full or unavailable');
      }

      final tags = await readTags(dest.path);
      final duration = tags.duration ?? await _probe(dest.path) ?? 0;

      String? artworkName;
      if (tags.picture != null) {
        artworkName = '$id.jpg';
        await _storage.artworkFile(artworkName).writeAsBytes(tags.picture!);
      }

      final artist = (tags.artist ?? '').trim();
      final track = Track(
        id: id,
        fileKey: fileKey,
        name: tags.title ?? p.basenameWithoutExtension(job.name),
        artist: artist.isEmpty ? 'Unknown artist' : artist,
        artists: artist.isEmpty
            ? ['Unknown artist']
            : artist
                  .split(RegExp(r'\s*[,&;]\s*'))
                  .where((s) => s.isNotEmpty)
                  .toList(),
        albumArtist: tags.albumArtist ?? '',
        album: tags.album ?? 'Unknown album',
        year: tags.year ?? '',
        trackNo: tags.trackNo ?? 0,
        duration: duration,
        source: TrackSource.local,
        stored: true,
        addedAt: DateTime.now().millisecondsSinceEpoch + i,
        audioFile: audioName,
        artworkFile: artworkName,
      );
      tracks.add(track);
      added.add(track);
      await _saveTracks();
      _changed();
    }
    importStatus = null;
    notifyListeners();
    return added;
  }

  Track? addRemoteTrack(Track item) {
    if (_byId(item.id) != null) return null;
    final track = Track(
      id: item.id,
      name: item.name,
      artist: item.artist,
      album: item.album.isEmpty ? 'Discovery' : item.album,
      duration: item.duration,
      source: item.source,
      stored: false,
      artworkUrl: item.artworkUrl,
      videoId: item.videoId,
      url: item.url,
    );
    tracks.add(track);
    _saveTracks();
    _changed();
    return track;
  }

  Future<void> removeTrack(Track track) => removeTracks({track.id});

  Future<void> removeTracks(Set<String> ids) async {
    final gone = tracks.where((t) => ids.contains(t.id)).toList();
    if (gone.isEmpty) return;
    onTracksRemoved?.call(ids);
    tracks.removeWhere((t) => ids.contains(t.id));
    history.removeWhere((t) => ids.contains(t.id));
    favoriteIds.removeWhere(ids.contains);
    for (final pl in customPlaylists) {
      pl.trackIds.removeWhere(ids.contains);
    }
    for (final t in gone) {
      await _storage.deleteTrackFiles(t);
    }
    await _saveTracks();
    await _saveLists();
    _changed();
  }

  Future<void> clearLibrary() => removeTracks({for (final t in tracks) t.id});

  // ------------------------------------------------------- history / favorites

  void addToHistory(Track track) {
    history = [
      track,
      ...history.where((t) => t.id != track.id),
    ].take(AppConfig.historyLimit).toList();
    _saveLists();
    _changed();
  }

  bool isFavorite(Track? t) => t != null && favoriteIds.contains(t.id);

  void toggleFavorite(Track track) {
    if (_byId(track.id) == null) addRemoteTrack(track);
    if (isFavorite(track)) {
      favoriteIds = favoriteIds.where((id) => id != track.id).toList();
    } else {
      favoriteIds = [track.id, ...favoriteIds];
    }
    _saveLists();
    _changed();
  }

  // --------------------------------------------------------------- playlists

  String createPlaylist(String name) {
    final id = 'pl_${_random.nextInt(1 << 32).toRadixString(36)}';
    customPlaylists.add(Playlist(id: id, name: name.trim()));
    _saveLists();
    _changed();
    return id;
  }

  /// Returns the playlist name, or null if it does not exist.
  String? addTrackToPlaylist(Track track, String playlistId) {
    final pl = customPlaylists.where((x) => x.id == playlistId).firstOrNull;
    if (pl == null) return null;
    if (_byId(track.id) == null) addRemoteTrack(track);
    if (!pl.trackIds.contains(track.id)) pl.trackIds.add(track.id);
    _saveLists();
    _changed();
    return pl.name;
  }

  void deletePlaylist(String id) {
    customPlaylists.removeWhere((x) => x.id == id);
    _saveLists();
    _changed();
  }

  // ------------------------------------------------------------------ search

  void setSortKey(String key) {
    sortKey = key;
    _storage.setString('adimusic:sortKey', key);
    notifyListeners();
  }

  void toggleSortDirection() {
    sortAsc = !sortAsc;
    _storage.setBool('adimusic:sortAsc', sortAsc);
    notifyListeners();
  }

  static bool _matches(String query, String text) {
    final q = query.toLowerCase().trim();
    return q.isEmpty || text.toLowerCase().contains(q);
  }

  // ----------------------------------------------------------- derived views

  Comparable<Object> _sortValue(Track t, String key) => switch (key) {
    'duration' => t.duration,
    'addedAt' => t.addedAt,
    'artist' => t.artist.toLowerCase(),
    'album' => t.album.toLowerCase(),
    _ => t.name.toLowerCase(),
  };

  /// Tracks matching [query] (name, artist or album), sorted by the current sort key.
  List<Track> tracksMatching(String query) {
    final list = tracks
        .where((t) => _matches(query, '${t.name} ${t.artist} ${t.album}'))
        .toList();
    final dir = sortAsc ? 1 : -1;
    list.sort(
      (a, b) =>
          Comparable.compare(_sortValue(a, sortKey), _sortValue(b, sortKey)) *
          dir,
    );
    return list;
  }

  void _rebuildCache() {
    if (_cacheVersion == _version) return;
    _cacheVersion = _version;

    final albumMap = <String, List<Track>>{};
    final albumInfo = <String, Track>{};
    final artistMap = <String, List<Track>>{};
    for (final t in tracks) {
      final key = albumKey(t);
      albumMap.putIfAbsent(key, () => []).add(t);
      albumInfo.putIfAbsent(key, () => t);
      for (final name in t.artists.isEmpty ? [t.artist] : t.artists) {
        artistMap.putIfAbsent(name, () => []).add(t);
      }
    }

    _albums = [
      for (final e in albumMap.entries)
        () {
          int order(Track t) => t.trackNo == 0 ? 999 : t.trackNo;
          final list = e.value
            ..sort(
              (x, y) => order(x) != order(y)
                  ? order(x) - order(y)
                  : x.name.compareTo(y.name),
            );
          final first = albumInfo[e.key]!;
          final year = list
              .map((t) => t.year)
              .firstWhere((y) => y.isNotEmpty, orElse: () => '');
          return Collection(
            id: albumId(first),
            name: first.album,
            artist: first.albumArtist.isNotEmpty
                ? first.albumArtist
                : first.artist,
            tracks: list,
            meta:
                '${year.isNotEmpty ? '$year • ' : ''}${plural(list.length, 'track')}',
          );
        }(),
    ];

    _artists = [
      for (final e in artistMap.entries)
        () {
          final albums = e.value.map((t) => t.album).toSet();
          return Collection(
            id: slugId(e.key),
            name: e.key,
            tracks: e.value,
            meta:
                '${plural(albums.length, 'album')} • ${plural(e.value.length, 'track')}',
          );
        }(),
    ];
  }

  List<Collection> get albums {
    _rebuildCache();
    final dir = sortAsc ? 1 : -1;
    return _albums!.toList()..sort((a, b) => a.name.compareTo(b.name) * dir);
  }

  List<Collection> get artists {
    _rebuildCache();
    final dir = sortAsc ? 1 : -1;
    return _artists!.toList()..sort((a, b) => a.name.compareTo(b.name) * dir);
  }

  List<Collection> get playlists {
    List<Track> resolve(List<String> ids) => ids.map(_byId).nonNulls.toList();
    Collection mk(
      String id,
      String name,
      List<String> ids, {
      bool favorites = false,
    }) {
      final list = resolve(ids);
      return Collection(
        id: id,
        name: name,
        tracks: list,
        meta: plural(list.length, 'track'),
        isFavorites: favorites,
      );
    }

    return [
      mk('favorites', 'Favorites', favoriteIds, favorites: true),
      for (final pl in customPlaylists) mk(pl.id, pl.name, pl.trackIds),
    ];
  }

  List<Collection> albumsMatching(String query) =>
      albums.where((a) => _matches(query, '${a.name} ${a.artist}')).toList();
  List<Collection> artistsMatching(String query) =>
      artists.where((a) => _matches(query, a.name)).toList();
  List<Collection> playlistsMatching(String query) =>
      playlists.where((pl) => _matches(query, pl.name)).toList();

  Collection? album(String id) => albums.where((a) => a.id == id).firstOrNull;
  Collection? artist(String id) => artists.where((a) => a.id == id).firstOrNull;
  Collection? playlist(String id) =>
      playlists.where((pl) => pl.id == id).firstOrNull;

  // ------------------------------------------------------------------ backup

  /// Settings, favourites, playlists and the saved Discovery tracks. Imported
  /// audio files are not included (the same as the web build).
  String exportBackup(AppSettings settings) =>
      const JsonEncoder.withIndent('  ').convert({
        'version': 2,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'settings': settings.toJson(),
        'favorites': favoriteIds,
        'playlists': [for (final pl in customPlaylists) pl.toJson()],
        'remoteTracks': [
          for (final t in tracks.where((t) => t.source != TrackSource.local))
            {
              'id': t.id,
              'name': t.name,
              'artist': t.artist,
              'album': t.album,
              'artwork': t.artworkUrl,
              'duration': t.duration,
              'source': t.source.name,
              'videoId': t.videoId,
              'url': t.url,
            },
        ],
      });

  /// Returns the restored settings, or null when [json] is not a valid backup.
  AppSettings? importBackup(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final settings = data['settings'] is Map<String, dynamic>
          ? AppSettings.fromJson(data['settings'] as Map<String, dynamic>)
          : null;
      if (data['favorites'] is List) {
        favoriteIds = (data['favorites'] as List).cast<String>();
      }
      if (data['playlists'] is List) {
        customPlaylists
          ..clear()
          ..addAll([
            for (final x in data['playlists'] as List)
              Playlist.fromJson(x as Map<String, dynamic>),
          ]);
      }
      for (final t
          in (data['remoteTracks'] as List? ?? const [])
              .cast<Map<String, dynamic>>()) {
        addRemoteTrack(Track.fromJson(t));
      }
      _saveLists();
      _changed();
      return settings ?? const AppSettings();
    } catch (_) {
      return null;
    }
  }
}

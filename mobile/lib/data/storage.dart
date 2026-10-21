/// On-disk storage. The web build keeps audio blobs and tags in IndexedDB and
/// the rest in localStorage; here audio and artwork are files in the app's
/// support directory, track metadata is one JSON file, and small state lives in
/// SharedPreferences.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'settings.dart';

class Storage {
  Storage({required this.root, required this.prefs}) {
    audioDir.createSync(recursive: true);
    artworkDir.createSync(recursive: true);
  }

  static Future<Storage> open() async {
    final root = await getApplicationSupportDirectory();
    final prefs = await SharedPreferences.getInstance();
    return Storage(root: root, prefs: prefs);
  }

  final Directory root;
  final SharedPreferences prefs;

  Directory get audioDir => Directory(p.join(root.path, 'audio'));
  Directory get artworkDir => Directory(p.join(root.path, 'artwork'));
  File get _libraryFile => File(p.join(root.path, 'library.json'));

  File audioFile(String name) => File(p.join(audioDir.path, name));
  File artworkFile(String name) => File(p.join(artworkDir.path, name));

  // ------------------------------------------------------------------ library

  Future<List<Track>> readLibrary() async {
    try {
      if (!await _libraryFile.exists()) return [];
      final raw = jsonDecode(await _libraryFile.readAsString());
      if (raw is! List) return [];
      return [
        for (final row in raw)
          if (row is Map<String, dynamic>) Track.fromJson(row),
      ];
    } catch (e) {
      debugPrint('Library unreadable: $e');
      return [];
    }
  }

  Future<void> _pendingLibraryWrite = Future.value();

  /// Writes through a temp file so a crash never leaves a half-written library.
  /// Writes are queued, so rapid changes never race on the temp file, and the
  /// JSON is captured now so later edits to [tracks] cannot leak into this write.
  Future<void> writeLibrary(List<Track> tracks) {
    final json = jsonEncode([for (final t in tracks) t.toJson()]);
    return _pendingLibraryWrite = _pendingLibraryWrite.then((_) async {
      try {
        final tmp = File('${_libraryFile.path}.tmp');
        await tmp.writeAsString(json, flush: true);
        await tmp.rename(_libraryFile.path);
      } catch (e) {
        debugPrint('Library not saved: $e');
      }
    });
  }

  /// Completes when every queued library write has finished.
  Future<void> flush() => _pendingLibraryWrite;

  Future<void> deleteTrackFiles(Track t) async {
    for (final f in [
      if (t.audioFile != null) audioFile(t.audioFile!),
      if (t.artworkFile != null) artworkFile(t.artworkFile!),
    ]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('Could not delete ${f.path}: $e');
      }
    }
  }

  // --------------------------------------------------------------- small state

  static const _settingsKey = 'adimusic:settings';
  static const _listsKey = 'adimusic:lists';
  static const _historyKey = 'adimusic:history';

  AppSettings readSettings() {
    try {
      final raw = prefs.getString(_settingsKey);
      if (raw != null) {
        return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Settings unreadable: $e');
    }
    return const AppSettings();
  }

  Future<void> writeSettings(AppSettings s) =>
      prefs.setString(_settingsKey, jsonEncode(s.toJson()));

  ({List<String> favorites, List<Playlist> playlists}) readLists() {
    try {
      final raw = prefs.getString(_listsKey);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        return (
          favorites: ((j['favorites'] as List?) ?? const []).cast<String>(),
          playlists: [
            for (final p in (j['custom'] as List?) ?? const [])
              Playlist.fromJson(p as Map<String, dynamic>),
          ],
        );
      }
    } catch (e) {
      debugPrint('Playlists unreadable: $e');
    }
    return (favorites: <String>[], playlists: <Playlist>[]);
  }

  Future<void> writeLists(List<String> favorites, List<Playlist> playlists) =>
      prefs.setString(
        _listsKey,
        jsonEncode({
          'favorites': favorites,
          'custom': [for (final p in playlists) p.toJson()],
        }),
      );

  /// History stores ids only; unsaved (Discovery) tracks keep a snapshot so they
  /// can still be replayed.
  List<Map<String, dynamic>> readHistory() {
    try {
      final raw = prefs.getString(_historyKey);
      if (raw != null) {
        return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('History unreadable: $e');
    }
    return [];
  }

  Future<void> writeHistory(List<Track> history, {required int limit}) =>
      prefs.setString(
        _historyKey,
        jsonEncode([
          for (final t in history.take(limit))
            {'id': t.id, if (!t.stored) 'snapshot': t.toJson()},
        ]),
      );

  String? getString(String key) => prefs.getString(key);
  bool? getBool(String key) => prefs.getBool(key);
  Future<void> setString(String key, String value) =>
      prefs.setString(key, value);
  Future<void> setBool(String key, bool value) => prefs.setBool(key, value);
}

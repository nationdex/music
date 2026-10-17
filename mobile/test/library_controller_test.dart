import 'dart:io';
import 'dart:math';

import 'package:adi_music/data/models.dart';
import 'package:adi_music/data/settings.dart';
import 'package:adi_music/data/storage.dart';
import 'package:adi_music/state/library_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Env {
  Env(this.dir, this.storage, this.lib);
  final Directory dir;
  final Storage storage;
  final LibraryController lib;

  static Future<Env> make({Directory? dir}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final d = dir ?? Directory.systemTemp.createTempSync('adi_test');
    final storage = Storage(root: d, prefs: prefs);
    return Env(d, storage, LibraryController(storage, probeDuration: (_) async => 1.0, random: Random(7)));
  }
}

const _fixtures = [
  ImportSource(path: 'test/fixtures/tagged.mp3', name: '01 - Midnight Drive.mp3'),
  ImportSource(path: 'test/fixtures/tagged.m4a', name: '09 - Window Seat.m4a'),
  ImportSource(path: 'test/fixtures/tagged.flac', name: '08 - Salt Air.flac'),
];

Track remote(String id, String name, {String artist = 'Someone', String album = 'YouTube'}) =>
    Track(id: id, name: name, artist: artist, album: album, source: TrackSource.youtube, stored: false, videoId: id, duration: 200);

void main() {
  test('imports files: copies audio, reads tags, writes artwork, skips duplicates', () async {
    final env = await Env.make();
    final added = await env.lib.importFiles(_fixtures);

    expect(added, hasLength(3));
    final mp3 = env.lib.tracks.firstWhere((t) => t.name == 'Midnight Drive');
    expect(mp3.artist, 'Neon Harbor');
    expect(mp3.album, 'Afterglow');
    expect(mp3.year, '2024');
    expect(mp3.trackNo, 3);
    expect(env.storage.audioFile(mp3.audioFile!).existsSync(), isTrue);
    expect(env.storage.artworkFile(mp3.artworkFile!).existsSync(), isTrue);
    expect(env.lib.tracks.firstWhere((t) => t.name == 'Salt Air').artworkFile, isNull);

    // Same files again: nothing new.
    expect(await env.lib.importFiles(_fixtures), isEmpty);
    expect(env.lib.tracks, hasLength(3));
    expect(env.lib.importStatus, isNull);
  });

  test('ignores files that are not audio', () async {
    final env = await Env.make();
    expect(await env.lib.importFiles(const [ImportSource(path: 'test/fixtures/cover.jpg', name: 'cover.jpg')]), isEmpty);
  });

  test('library, favourites, playlists and history survive a restart', () async {
    final env = await Env.make();
    await env.lib.importFiles(_fixtures);
    final first = env.lib.tracks.first;
    env.lib.toggleFavorite(first);
    final plId = env.lib.createPlaylist('Late night');
    env.lib.addTrackToPlaylist(env.lib.tracks.last, plId);
    env.lib.addToHistory(first);
    env.lib.setSortKey('artist');
    await env.lib.flush();

    final prefs = await SharedPreferences.getInstance();
    final reloaded = LibraryController(Storage(root: env.dir, prefs: prefs));
    await reloaded.load();
    expect(reloaded.tracks.map((t) => t.id), env.lib.tracks.map((t) => t.id));
    expect(reloaded.favoriteIds, [first.id]);
    expect(reloaded.customPlaylists.single.name, 'Late night');
    expect(reloaded.customPlaylists.single.trackIds, [env.lib.tracks.last.id]);
    expect(reloaded.history.map((t) => t.id), [first.id]);
    expect(reloaded.sortKey, 'artist');
  });

  test('derives albums and artists, ordered by track number', () async {
    final env = await Env.make();
    await env.lib.importFiles(_fixtures);
    env.lib.addRemoteTrack(Track(id: 'x1', name: 'Bonus', artist: 'Neon Harbor', album: 'Afterglow', source: TrackSource.remote, stored: false, url: 'https://x/y.m4a'));

    final albums = env.lib.albums;
    expect(albums.map((a) => a.name), ['Afterglow', 'Greenhouse', 'Quiet Rooms']);
    final afterglow = albums.first;
    expect(afterglow.artist, 'Neon Harbor');
    expect(afterglow.tracks.map((t) => t.name), ['Midnight Drive', 'Bonus'], reason: 'numbered tracks first, unnumbered last');
    expect(afterglow.meta, '2024 • 2 tracks');

    final artists = env.lib.artists;
    expect(artists.map((a) => a.name), ['Hollow Pines', 'Ivy and the Wire', 'Neon Harbor']);
    expect(artists.last.meta, '1 album • 2 tracks');

    env.lib.toggleSortDirection();
    expect(env.lib.albums.first.name, 'Quiet Rooms');
  });

  test('search and sort', () async {
    final env = await Env.make();
    await env.lib.importFiles(_fixtures);
    expect(env.lib.tracksMatching('').map((t) => t.name), ['Midnight Drive', 'Salt Air', 'Window Seat']);
    expect(env.lib.tracksMatching('hollow').map((t) => t.name), ['Window Seat'], reason: 'matches artist');
    expect(env.lib.tracksMatching('GREENHOUSE').map((t) => t.name), ['Salt Air'], reason: 'matches album, case-insensitive');
    expect(env.lib.tracksMatching('zzz'), isEmpty);

    env.lib.setSortKey('duration');
    env.lib.toggleSortDirection();
    expect(env.lib.tracksMatching('').length, 3);
    expect(env.lib.albumsMatching('quiet').single.name, 'Quiet Rooms');
    expect(env.lib.artistsMatching('ivy').single.name, 'Ivy and the Wire');
  });

  test('removing a track deletes its files and cleans every list', () async {
    final env = await Env.make();
    await env.lib.importFiles(_fixtures);
    final track = env.lib.tracks.firstWhere((t) => t.name == 'Midnight Drive');
    final audio = env.storage.audioFile(track.audioFile!);
    final art = env.storage.artworkFile(track.artworkFile!);
    env.lib.toggleFavorite(track);
    final pl = env.lib.createPlaylist('P');
    env.lib.addTrackToPlaylist(track, pl);
    env.lib.addToHistory(track);

    Set<String>? removed;
    env.lib.onTracksRemoved = (ids) => removed = ids;
    await env.lib.removeTrack(track);

    expect(removed, {track.id});
    expect(audio.existsSync(), isFalse);
    expect(art.existsSync(), isFalse);
    expect(env.lib.tracks.any((t) => t.id == track.id), isFalse);
    expect(env.lib.favoriteIds, isEmpty);
    expect(env.lib.customPlaylists.single.trackIds, isEmpty);
    expect(env.lib.history, isEmpty);

    await env.lib.clearLibrary();
    expect(env.lib.tracks, isEmpty);
    expect(env.dir.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('/audio/')), isEmpty);
  });

  test('favourites and playlists accept unsaved Discovery tracks by saving them first', () async {
    final env = await Env.make();
    final t = remote('yt_abc', 'Song');
    env.lib.toggleFavorite(t);
    expect(env.lib.tracks.single.id, 'yt_abc');
    expect(env.lib.playlists.first.tracks.single.name, 'Song');
    expect(env.lib.playlists.first.isFavorites, isTrue);

    final id = env.lib.createPlaylist('Mix');
    expect(env.lib.addTrackToPlaylist(remote('yt_def', 'Other'), id), 'Mix');
    expect(env.lib.addTrackToPlaylist(remote('yt_def', 'Other'), id), 'Mix');
    expect(env.lib.customPlaylists.single.trackIds, ['yt_def'], reason: 'no duplicates');
    expect(env.lib.addTrackToPlaylist(t, 'missing'), isNull);
  });

  test('history is capped and most recent first', () async {
    final env = await Env.make();
    for (var i = 0; i < 120; i++) {
      env.lib.addToHistory(remote('v$i', 'S$i'));
    }
    expect(env.lib.history.length, 100);
    expect(env.lib.history.first.id, 'v119');
    env.lib.addToHistory(remote('v50', 'S50'));
    expect(env.lib.history.first.id, 'v50');
    expect(env.lib.history.where((t) => t.id == 'v50'), hasLength(1));
  });

  test('backup round-trips and accepts a web-build backup', () async {
    final env = await Env.make();
    env.lib.addRemoteTrack(remote('yt_1', 'Saved'));
    env.lib.toggleFavorite(env.lib.tracks.single);
    env.lib.createPlaylist('Road trip');
    final json = env.lib.exportBackup(const AppSettings(theme: 'dark', accent: '#2e7d32'));

    final other = await Env.make();
    final restored = other.lib.importBackup(json)!;
    expect(restored.theme, 'dark');
    expect(restored.accent, '#2e7d32');
    expect(other.lib.favoriteIds, ['yt_1']);
    expect(other.lib.customPlaylists.single.name, 'Road trip');
    expect(other.lib.tracks.single.name, 'Saved');

    // Shape written by site/assets/js/app.js `exportBackup`.
    const web = '{"version":2,"settings":{"theme":"light","volume":0.5,"unknown":1},"favorites":["a"],"playlists":[{"id":"pl_1","name":"Web","trackIds":["a"]}],"remoteTracks":[{"id":"yt_w","name":"From web","artist":"A","album":"YouTube","artwork":"https://i/x.jpg","duration":100,"source":"youtube","videoId":"w","url":null}]}';
    final fromWeb = (await Env.make());
    final s = fromWeb.lib.importBackup(web)!;
    expect(s.theme, 'light');
    expect(s.volume, 0.5);
    expect(fromWeb.lib.tracks.single.artworkUrl, 'https://i/x.jpg');

    expect(other.lib.importBackup('not json'), isNull);
    expect(other.lib.importBackup('[]'), isNull);
  });
}

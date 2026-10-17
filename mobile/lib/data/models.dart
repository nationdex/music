/// Data models. Mirrors the objects in site/assets/js/app.js.
library;

import '../core/format.dart';

enum TrackSource {
  /// An audio file imported into the app's storage.
  local,

  /// A full-length YouTube video, played in YouTube's iframe.
  youtube,

  /// A remote audio URL (30-second Apple previews).
  remote;

  static TrackSource parse(String? s) => switch (s) {
    'youtube' => youtube,
    'remote' => remote,
    _ => local,
  };
}

class Track {
  Track({
    required this.id,
    required this.name,
    required this.artist,
    List<String>? artists,
    this.albumArtist = '',
    this.album = 'Unknown album',
    this.year = '',
    this.trackNo = 0,
    this.duration = 0,
    this.source = TrackSource.local,
    this.stored = true,
    int? addedAt,
    this.fileKey,
    this.audioFile,
    this.artworkFile,
    this.artworkUrl,
    this.videoId,
    this.url,
  }) : artists = artists ?? [artist],
       addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  String name;
  String artist;
  List<String> artists;
  String albumArtist;
  String album;
  String year;
  int trackNo;

  /// Seconds. 0 when unknown.
  double duration;
  TrackSource source;

  /// False for Discovery tracks that were saved without a local file.
  bool stored;
  int addedAt;

  /// `name:size:modified`, used to skip files that are already imported.
  String? fileKey;

  /// File names inside the app's audio and artwork directories. Never absolute
  /// paths: iOS changes the app container path between launches and updates.
  String? audioFile;
  String? artworkFile;

  /// Remote artwork (Discovery results).
  String? artworkUrl;
  String? videoId;

  /// Remote audio URL (Apple previews).
  String? url;

  bool get isLocal => source == TrackSource.local;
  bool get isYouTube => source == TrackSource.youtube;
  bool get hasArtwork => artworkFile != null || (artworkUrl != null && artworkUrl!.isNotEmpty);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'artist': artist,
    'artists': artists,
    'albumArtist': albumArtist,
    'album': album,
    'year': year,
    'trackNo': trackNo,
    'duration': duration,
    'source': source.name,
    'stored': stored,
    'addedAt': addedAt,
    'fileKey': fileKey,
    'audioFile': audioFile,
    'artworkFile': artworkFile,
    'artworkUrl': artworkUrl,
    'videoId': videoId,
    'url': url,
  };

  factory Track.fromJson(Map<String, dynamic> j) {
    final artist = (j['artist'] as String?) ?? 'Unknown artist';
    return Track(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Untitled',
      artist: artist,
      artists: (j['artists'] as List?)?.cast<String>(),
      albumArtist: (j['albumArtist'] as String?) ?? '',
      album: (j['album'] as String?) ?? 'Unknown album',
      year: (j['year'] ?? '').toString(),
      trackNo: (j['trackNo'] as num?)?.toInt() ?? 0,
      duration: (j['duration'] as num?)?.toDouble() ?? 0,
      source: TrackSource.parse(j['source'] as String?),
      stored: (j['stored'] as bool?) ?? true,
      addedAt: (j['addedAt'] as num?)?.toInt(),
      fileKey: j['fileKey'] as String?,
      audioFile: j['audioFile'] as String?,
      artworkFile: j['artworkFile'] as String?,
      artworkUrl: (j['artworkUrl'] ?? j['artwork']) as String?,
      videoId: j['videoId'] as String?,
      url: j['url'] as String?,
    );
  }
}

class Playlist {
  Playlist({required this.id, required this.name, List<String>? trackIds}) : trackIds = trackIds ?? [];

  final String id;
  String name;
  List<String> trackIds;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'trackIds': trackIds};

  factory Playlist.fromJson(Map<String, dynamic> j) =>
      Playlist(id: j['id'] as String, name: (j['name'] as String?) ?? 'Playlist', trackIds: (j['trackIds'] as List?)?.cast<String>());
}

/// A derived, read-only grouping of tracks (album, artist, or playlist).
class Collection {
  const Collection({required this.id, required this.name, required this.tracks, this.artist = '', this.meta = '', this.isFavorites = false});

  final String id;
  final String name;
  final String artist;
  final List<Track> tracks;
  final String meta;
  final bool isFavorites;

  Track? get artworkTrack {
    for (final t in tracks) {
      if (t.hasArtwork) return t;
    }
    return null;
  }
}

class LyricLine {
  const LyricLine(this.t, this.text, {this.tEnd});

  final double t;
  final double? tEnd;
  final String text;
}

enum LyricsStatus { idle, loading, synced, plain, none }

class LyricsRecord {
  const LyricsRecord({this.plain, this.synced, this.ttml, this.provider, this.syncLevel, required this.source});

  final String? plain;
  final String? synced;
  final String? ttml;
  final String? provider;
  final String? syncLevel;
  final String source;
}

/// One Discovery search result (YouTube video or Apple preview).
class DiscoveryItem {
  const DiscoveryItem({
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    required this.source,
    this.artwork,
    this.duration = 0,
    this.videoId,
    this.previewUrl,
  });

  final String id;
  final String name;
  final String artist;
  final String album;
  final String? artwork;
  final double duration;
  final TrackSource source;
  final String? videoId;
  final String? previewUrl;

  String get trackId => '${source == TrackSource.youtube ? 'yt_' : 'rm_'}${videoId ?? id}';

  /// Transient (unsaved) track for playback.
  Track toTrack() => Track(
    id: trackId,
    name: name,
    artist: artist,
    album: album.isEmpty ? 'Discovery' : album,
    duration: duration,
    source: source,
    stored: false,
    artworkUrl: artwork,
    videoId: videoId,
    url: previewUrl,
  );
}

String albumKey(Track t) => '${t.album}\u0000${t.albumArtist.isNotEmpty ? t.albumArtist : t.artist}';
String albumId(Track t) => slugId(albumKey(t));

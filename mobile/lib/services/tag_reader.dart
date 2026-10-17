/// Reads tags and cover art from audio files. The web build ships its own
/// ID3v2 / MP4 / FLAC parsers; here `audio_metadata_reader` does the same work
/// (and also Ogg, Opus, WAV, AIFF, APE).
library;

import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class Tags {
  const Tags({this.title, this.artist, this.albumArtist, this.album, this.year, this.trackNo, this.duration, this.picture});

  final String? title;
  final String? artist;
  final String? albumArtist;
  final String? album;
  final String? year;
  final int? trackNo;

  /// Seconds, when the container reports it.
  final double? duration;

  /// Cover art, already shrunk to a JPEG.
  final Uint8List? picture;

  static const empty = Tags();
}

/// Longest edge of stored cover art, in pixels (same as the web build).
const artworkMaxEdge = 512;

Future<Tags> readTags(String path) => compute(_readTagsSync, path);

Tags _readTagsSync(String path) {
  try {
    final meta = readMetadata(File(path), getImage: true);
    Uint8List? art;
    if (meta.pictures.isNotEmpty) {
      final front = meta.pictures.where((p) => p.pictureType == PictureType.coverFront);
      art = shrinkArtwork((front.isNotEmpty ? front.first : meta.pictures.first).bytes);
    }
    String? clean(String? s) {
      final t = s?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    return Tags(
      title: clean(meta.title),
      artist: clean(meta.artist),
      albumArtist: clean(meta.albumArtist),
      album: clean(meta.album),
      year: meta.year?.year.toString(),
      trackNo: meta.trackNumber,
      duration: meta.duration == null ? null : meta.duration!.inMilliseconds / 1000.0,
      picture: art,
    );
  } catch (e) {
    // Unsupported container or truncated tag: the file name is used instead.
    debugPrint('Tags unreadable for $path: $e');
    return Tags.empty;
  }
}

/// Decodes [bytes], scales the longest edge to [artworkMaxEdge], and re-encodes as JPEG (quality 86).
/// Returns null when the data is not a decodable image.
Uint8List? shrinkArtwork(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longest > artworkMaxEdge
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? artworkMaxEdge : null,
            height: decoded.height > decoded.width ? artworkMaxEdge : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 86));
  } catch (e) {
    debugPrint('Artwork not decodable: $e');
    return null;
  }
}

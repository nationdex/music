import 'dart:io';
import 'dart:typed_data';

import 'package:adi_music/services/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const dir = 'test/fixtures';

  test('reads ID3v2 tags and cover art from an MP3', () async {
    final t = await readTags('$dir/tagged.mp3');
    expect(t.title, 'Midnight Drive');
    expect(t.artist, 'Neon Harbor');
    expect(t.album, 'Afterglow');
    expect(t.year, '2024');
    expect(t.trackNo, 3);
    expect(t.duration, closeTo(1.0, 0.2));
    expect(t.picture, isNotNull);
    expect(t.picture!.take(2), [0xFF, 0xD8], reason: 'cover is re-encoded as JPEG');
  });

  test('reads MP4 atoms from an M4A', () async {
    final t = await readTags('$dir/tagged.m4a');
    expect(t.title, 'Window Seat');
    expect(t.artist, 'Hollow Pines');
    expect(t.album, 'Quiet Rooms');
    expect(t.trackNo, 2);
    expect(t.picture, isNotNull);
  });

  test('reads Vorbis comments from a FLAC', () async {
    final t = await readTags('$dir/tagged.flac');
    expect(t.title, 'Salt Air');
    expect(t.artist, 'Ivy and the Wire');
    expect(t.album, 'Greenhouse');
    expect(t.trackNo, 5);
  });

  test('a file without tags yields empty tags instead of throwing', () async {
    final tmp = File('${Directory.systemTemp.createTempSync().path}/junk.mp3')..writeAsBytesSync(List.filled(64, 0));
    final t = await readTags(tmp.path);
    expect(t.title, isNull);
  });

  test('shrinkArtwork caps the longest edge at 512 px', () {
    final big = Uint8List.fromList(img.encodePng(img.Image(width: 1200, height: 800)));
    final out = img.decodeJpg(shrinkArtwork(big)!)!;
    expect(out.width, 512);
    expect(out.height, closeTo(341, 1));

    final tall = Uint8List.fromList(img.encodePng(img.Image(width: 300, height: 900)));
    expect(img.decodeJpg(shrinkArtwork(tall)!)!.height, 512);

    final small = Uint8List.fromList(img.encodePng(img.Image(width: 200, height: 100)));
    expect(img.decodeJpg(shrinkArtwork(small)!)!.width, 200, reason: 'small covers are not upscaled');
    expect(shrinkArtwork(File('test/fixtures/tagged.mp3').readAsBytesSync()), isNull, reason: 'not an image');
  });
}

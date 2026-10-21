import 'dart:io';
import 'dart:math';

import 'package:adi_music/data/storage.dart';
import 'package:adi_music/services/zip_reader.dart';
import 'package:adi_music/state/library_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fixtures are shared with the web tests: python3 tests/js/make-zip-fixtures.py
File fixture(String name) => File('../tests/fixtures/zip/$name');
final mp3 = File('test/fixtures/tagged.mp3').readAsBytesSync();
final flac = File('test/fixtures/tagged.flac').readAsBytesSync();

Future<File> extract(ZipArchive z, ZipEntry e) async {
  final out = File(
    '${Directory.systemTemp.createTempSync('adi_zip').path}/out.bin',
  );
  await z.extractTo(e, out);
  return out;
}

void main() {
  for (final name in ['deflate.zip', 'stored.zip']) {
    test('$name: lists audio only and extracts byte-identical files', () async {
      final z = await ZipArchive.open(fixture(name));
      expect(z.entries, hasLength(7));
      expect(z.audioEntries.map((e) => e.name), [
        'Album/01 - Midnight Drive.mp3',
        'Album/02 - Salt Air.flac',
      ]);
      expect(await (await extract(z, z.audioEntries[0])).readAsBytes(), mp3);
      expect(await (await extract(z, z.audioEntries[1])).readAsBytes(), flac);
      expect(z.audioEntries[0].baseName, '01 - Midnight Drive.mp3');
    });
  }

  test('ZIP64, unicode names, long comment, data descriptors', () async {
    final z64 = await ZipArchive.open(fixture('zip64.zip'));
    expect(z64.entries.map((e) => e.name), ['a/one.mp3', 'a/two.flac']);
    expect(await (await extract(z64, z64.entries[0])).readAsBytes(), mp3);

    final uni = await ZipArchive.open(fixture('unicode.zip'));
    expect(uni.entries.single.name, 'Música/Canción ñandú ☃.mp3');
    expect(await (await extract(uni, uni.entries.single)).readAsBytes(), mp3);

    final com = await ZipArchive.open(fixture('comment.zip'));
    expect(await (await extract(com, com.entries.single)).readAsBytes(), mp3);

    final stream = await ZipArchive.open(fixture('streamed.zip'));
    expect(stream.entries.single.flags & 8, isNot(0));
    expect(
      await (await extract(stream, stream.entries.single)).readAsBytes(),
      mp3,
    );
  });

  test('a flipped byte is caught and leaves no partial file', () async {
    final z = await ZipArchive.open(fixture('corrupt.zip'));
    final out = File(
      '${Directory.systemTemp.createTempSync('adi_zip').path}/bad.bin',
    );
    await expectLater(
      z.extractTo(z.audioEntries[0], out),
      throwsA(
        isA<ZipException>().having(
          (e) => e.message,
          'message',
          contains('damaged'),
        ),
      ),
    );
    expect(out.existsSync(), isFalse);
    expect(await (await extract(z, z.audioEntries[1])).readAsBytes(), flac);
  });

  test('encrypted entries and non-ZIP files are refused clearly', () async {
    final enc = await ZipArchive.open(fixture('encrypted.zip'));
    await expectLater(
      extract(enc, enc.audioEntries[0]),
      throwsA(
        isA<ZipException>().having((e) => e.message, 'm', contains('password')),
      ),
    );
    await expectLater(
      ZipArchive.open(fixture('not-a-zip.zip')),
      throwsA(isA<ZipException>()),
    );
    final tiny = File('${Directory.systemTemp.createTempSync().path}/t.zip')
      ..writeAsBytesSync([1, 2, 3]);
    await expectLater(ZipArchive.open(tiny), throwsA(isA<ZipException>()));
  });

  group('import into the library', () {
    Future<LibraryController> make() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final storage = Storage(
        root: Directory.systemTemp.createTempSync('adi_zipimport'),
        prefs: await SharedPreferences.getInstance(),
      );
      return LibraryController(
        storage,
        probeDuration: (_) async => 1,
        random: Random(2),
      );
    }

    ImportSource src(String name) =>
        ImportSource(path: fixture(name).path, name: name);

    test('a ZIP imports its audio with tags and cover art', () async {
      final lib = await make();
      final added = await lib.importFiles([src('deflate.zip')]);
      expect(added.map((t) => t.name), ['Midnight Drive', 'Salt Air']);
      expect(added.first.artist, 'Neon Harbor');
      expect(added.first.artworkFile, isNotNull);
      expect(lib.importProblems, isEmpty);
      await lib.flush();
    });

    test('importing the same ZIP again adds nothing', () async {
      final lib = await make();
      await lib.importFiles([src('deflate.zip')]);
      expect(await lib.importFiles([src('deflate.zip')]), isEmpty);
      expect(lib.tracks, hasLength(2));
    });

    test(
      'a damaged member is skipped and reported, the rest still import',
      () async {
        final lib = await make();
        final added = await lib.importFiles([src('corrupt.zip')]);
        expect(added.map((t) => t.name), ['Salt Air']);
        expect(lib.importProblems.single, contains('damaged'));
      },
    );

    test(
      'an unreadable ZIP is reported, plain audio next to it still imports',
      () async {
        final lib = await make();
        final added = await lib.importFiles([
          src('not-a-zip.zip'),
          ImportSource(
            path: 'test/fixtures/tagged.m4a',
            name: 'Window Seat.m4a',
          ),
        ]);
        expect(added.map((t) => t.name), ['Window Seat']);
        expect(lib.importProblems.single, contains('not-a-zip.zip'));
      },
    );

    test('ZIP members land in app storage and play from there', () async {
      final lib = await make();
      final added = await lib.importFiles([src('zip64.zip')]);
      for (final t in added) {
        expect(lib.audioFileFor(t)!.existsSync(), isTrue);
      }
      expect(added, hasLength(2));
    });
  });
}

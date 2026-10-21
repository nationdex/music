/// A small ZIP reader for importing albums that come as .zip files. Same approach as the web build
/// (site/assets/js/zip.js) and nationdex/nzip: a ZIP keeps its index at the end of the file, so read
/// the tail, then the central directory, then only the bytes of the member you want. The archive is
/// never loaded into memory and members that are skipped are never decompressed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ZipException implements Exception {
  const ZipException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ZipEntry {
  ZipEntry({
    required this.name,
    required this.method,
    required this.flags,
    required this.crc,
    required this.compressedSize,
    required this.size,
    required this.offset,
    required this.modified,
  });

  final String name;
  final int method;
  final int flags;
  final int crc;
  final int compressedSize;
  final int size;
  final int offset;
  final DateTime modified;

  bool get isDirectory => name.endsWith('/');
  String get baseName => name.substring(name.lastIndexOf('/') + 1);
}

const _sigEocd = 0x06054b50;
const _sigEocd64 = 0x06064b50;
const _sigLocator64 = 0x07064b50;
const _sigCentral = 0x02014b50;
const _sigLocal = 0x04034b50;
const _maxEntries = 50000;
final _audio = RegExp(
  r'\.(mp3|m4a|m4b|aac|flac|ogg|oga|opus|wav|webm|mp4|aif|aiff|ape)$',
  caseSensitive: false,
);

bool isZipPath(String name) => name.toLowerCase().endsWith('.zip');

int _crcStep(int crc, List<int> data, Uint32List table) {
  for (final b in data) {
    crc = table[(crc ^ b) & 0xff] ^ (crc >> 8);
  }
  return crc;
}

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

class ZipArchive {
  ZipArchive._(this.file, this.entries);

  final File file;
  final List<ZipEntry> entries;

  /// Reads the index of [file]. Throws [ZipException] when it is not a readable ZIP.
  static Future<ZipArchive> open(File file) async {
    final raf = await file.open();
    try {
      final size = await raf.length();
      if (size < 22) throw const ZipException('not a ZIP file');
      final tailStart = size > 22 + 0xffff ? size - (22 + 0xffff) : 0;
      final tail = await _read(raf, tailStart, size - tailStart);
      final tv = ByteData.sublistView(tail);
      var eocd = -1;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (tv.getUint32(i, Endian.little) == _sigEocd) {
          eocd = i;
          break;
        }
      }
      if (eocd < 0) throw const ZipException('not a ZIP file');

      var total = tv.getUint16(eocd + 10, Endian.little);
      var cdSize = tv.getUint32(eocd + 12, Endian.little);
      var cdOffset = tv.getUint32(eocd + 16, Endian.little);
      if (total == 0xffff || cdSize == 0xffffffff || cdOffset == 0xffffffff) {
        final loc = tailStart + eocd - 20;
        if (loc < 0) throw const ZipException('corrupt ZIP64 archive');
        final locator = ByteData.sublistView(await _read(raf, loc, 20));
        if (locator.getUint32(0, Endian.little) != _sigLocator64) {
          throw const ZipException('corrupt ZIP64 archive');
        }
        final at = locator.getUint64(8, Endian.little);
        final rec = ByteData.sublistView(await _read(raf, at, 56));
        if (rec.getUint32(0, Endian.little) != _sigEocd64) {
          throw const ZipException('corrupt ZIP64 archive');
        }
        total = rec.getUint64(32, Endian.little);
        cdSize = rec.getUint64(40, Endian.little);
        cdOffset = rec.getUint64(48, Endian.little);
      }
      if (total > _maxEntries) {
        throw const ZipException('too many files in the archive');
      }
      if (cdOffset + cdSize > size) {
        throw const ZipException('corrupt ZIP index');
      }

      final cdBytes = await _read(raf, cdOffset, cdSize);
      final cd = ByteData.sublistView(cdBytes);
      final entries = <ZipEntry>[];
      var p = 0;
      for (var n = 0; n < total; n++) {
        if (p + 46 > cdBytes.length ||
            cd.getUint32(p, Endian.little) != _sigCentral) {
          throw const ZipException('corrupt ZIP index');
        }
        final flags = cd.getUint16(p + 8, Endian.little);
        final nameLen = cd.getUint16(p + 28, Endian.little);
        final extraLen = cd.getUint16(p + 30, Endian.little);
        final commentLen = cd.getUint16(p + 32, Endian.little);
        var csize = cd.getUint32(p + 20, Endian.little);
        var usize = cd.getUint32(p + 24, Endian.little);
        var offset = cd.getUint32(p + 42, Endian.little);
        // ZIP64 extra field: only values that overflowed 32 bits are present, in this order.
        for (var x = p + 46 + nameLen; x + 4 <= p + 46 + nameLen + extraLen;) {
          final id = cd.getUint16(x, Endian.little);
          final len = cd.getUint16(x + 2, Endian.little);
          if (id == 0x0001) {
            var o = x + 4;
            if (usize == 0xffffffff) {
              usize = cd.getUint64(o, Endian.little);
              o += 8;
            }
            if (csize == 0xffffffff) {
              csize = cd.getUint64(o, Endian.little);
              o += 8;
            }
            if (offset == 0xffffffff) offset = cd.getUint64(o, Endian.little);
          }
          x += 4 + len;
        }
        final rawName = cdBytes.sublist(p + 46, p + 46 + nameLen);
        final String name;
        try {
          name = utf8.decode(rawName);
        } on FormatException {
          if (flags & 0x800 != 0) throw const ZipException('invalid file name');
          // The usual encoding of old, non-UTF-8 archives.
          entries.add(
            _entry(latin1.decode(rawName), flags, cd, p, csize, usize, offset),
          );
          p += 46 + nameLen + extraLen + commentLen;
          continue;
        }
        entries.add(_entry(name, flags, cd, p, csize, usize, offset));
        p += 46 + nameLen + extraLen + commentLen;
      }
      return ZipArchive._(file, entries);
    } finally {
      await raf.close();
    }
  }

  static ZipEntry _entry(
    String name,
    int flags,
    ByteData cd,
    int p,
    int csize,
    int usize,
    int offset,
  ) {
    final time = cd.getUint16(p + 12, Endian.little);
    final date = cd.getUint16(p + 14, Endian.little);
    return ZipEntry(
      name: name,
      method: cd.getUint16(p + 10, Endian.little),
      flags: flags,
      crc: cd.getUint32(p + 16, Endian.little),
      compressedSize: csize,
      size: usize,
      offset: offset,
      modified: DateTime(
        ((date >> 9) & 0x7f) + 1980,
        ((date >> 5) & 0x0f).clamp(1, 12),
        (date & 0x1f).clamp(1, 31),
        (time >> 11) & 0x1f,
        (time >> 5) & 0x3f,
        (time & 0x1f) * 2,
      ),
    );
  }

  static Future<Uint8List> _read(
    RandomAccessFile raf,
    int at,
    int length,
  ) async {
    await raf.setPosition(at);
    final data = await raf.read(length);
    if (data.length != length) throw const ZipException('corrupt ZIP index');
    return data;
  }

  /// Audio members worth importing: no folders, no macOS metadata (`__MACOSX`, `._name`).
  List<ZipEntry> get audioEntries => [
    for (final e in entries)
      if (!e.isDirectory &&
          _audio.hasMatch(e.name) &&
          !RegExp(r'(^|/)(__MACOSX/|\._)').hasMatch(e.name))
        e,
  ];

  /// Writes [entry] to [dest], streaming: a 100 MB FLAC never sits in memory. Verifies the CRC and
  /// deletes the partial file when anything is wrong.
  Future<void> extractTo(ZipEntry entry, File dest) async {
    if (entry.flags & 1 != 0) {
      throw ZipException('“${entry.name}” is password protected');
    }
    final raf = await file.open();
    final out = dest.openWrite();
    try {
      final head = ByteData.sublistView(await _read(raf, entry.offset, 30));
      if (head.getUint32(0, Endian.little) != _sigLocal) {
        throw const ZipException('corrupt ZIP entry');
      }
      final start =
          entry.offset +
          30 +
          head.getUint16(26, Endian.little) +
          head.getUint16(28, Endian.little);

      Stream<List<int>> raw() async* {
        var left = entry.compressedSize;
        await raf.setPosition(start);
        while (left > 0) {
          final chunk = await raf.read(left < 65536 ? left : 65536);
          if (chunk.isEmpty) throw const ZipException('truncated ZIP entry');
          left -= chunk.length;
          yield chunk;
        }
      }

      final Stream<List<int>> data;
      if (entry.method == 0) {
        data = raw();
      } else if (entry.method == 8) {
        data = raw().transform(ZLibDecoder(raw: true));
      } else {
        throw ZipException(
          '“${entry.name}” uses an unsupported compression method',
        );
      }

      var crc = 0xffffffff, written = 0;
      await for (final chunk in data) {
        crc = _crcStep(crc, chunk, _crcTable);
        written += chunk.length;
        out.add(chunk);
      }
      await out.close();
      if (written != entry.size) {
        throw ZipException('“${entry.name}” is damaged (wrong size)');
      }
      if ((crc ^ 0xffffffff) & 0xffffffff != entry.crc) {
        throw ZipException('“${entry.name}” is damaged (checksum mismatch)');
      }
    } catch (_) {
      try {
        await out.close();
      } catch (_) {}
      if (await dest.exists()) await dest.delete();
      rethrow;
    } finally {
      await raf.close();
    }
  }
}

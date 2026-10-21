// Tests for site/assets/js/zip.js against real archives. Run: node --test tests/js/
// (fixtures: python3 tests/js/make-zip-fixtures.py)
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { ZipError, ZipReader, baseName, isZipFile, mimeFor } from '../../site/assets/js/zip.js';

const load = (name) => {
  const b = readFileSync(new URL('../fixtures/zip/' + name, import.meta.url));
  return new File([b], name, { type: 'application/zip' });
};
const MP3 = readFileSync(new URL('../../mobile/test/fixtures/tagged.mp3', import.meta.url));
const FLAC = readFileSync(new URL('../../mobile/test/fixtures/tagged.flac', import.meta.url));
const same = async (blob, buf) => Buffer.from(await blob.arrayBuffer()).equals(buf);

for (const name of ['deflate.zip', 'stored.zip']) {
  test(name + ': lists audio only, skips folders, covers, notes and macOS metadata', async () => {
    const z = await ZipReader.open(load(name));
    assert.equal(z.entries.length, 7);
    assert.deepEqual(z.audioEntries().map((e) => e.name), ['Album/01 - Midnight Drive.mp3', 'Album/02 - Salt Air.flac']);
  });

  test(name + ': extracts byte-identical files with matching CRC', async () => {
    const z = await ZipReader.open(load(name));
    const [mp3, flac] = z.audioEntries();
    assert.ok(await same(await z.read(mp3), MP3));
    assert.ok(await same(await z.read(flac), FLAC));
    assert.equal((await z.read(mp3)).type, 'audio/mpeg');
  });
}

test('deflate really compresses and stored really does not', async () => {
  const d = (await ZipReader.open(load('deflate.zip'))).audioEntries()[0];
  const s = (await ZipReader.open(load('stored.zip'))).audioEntries()[0];
  assert.equal(d.method, 8);
  assert.equal(s.method, 0);
  assert.equal(s.compressedSize, s.size);
});

test('ZIP64 archives (sizes and offsets in the extra field)', async () => {
  const z = await ZipReader.open(load('zip64.zip'));
  assert.deepEqual(z.entries.map((e) => e.name), ['a/one.mp3', 'a/two.flac']);
  assert.ok(await same(await z.read(z.entries[0]), MP3));
  assert.ok(await same(await z.read(z.entries[1]), FLAC));
});

test('UTF-8 names survive', async () => {
  const z = await ZipReader.open(load('unicode.zip'));
  assert.equal(z.entries[0].name, 'Música/Canción ñandú ☃.mp3');
  assert.equal(baseName(z.entries[0].name), 'Canción ñandú ☃.mp3');
  assert.ok(await same(await z.read(z.entries[0]), MP3));
});

test('a long archive comment does not hide the index', async () => {
  const z = await ZipReader.open(load('comment.zip'));
  assert.ok(await same(await z.read(z.entries[0]), MP3));
});

test('streamed archives (sizes after the data, bit 3) read through the central directory', async () => {
  const z = await ZipReader.open(load('streamed.zip'));
  assert.ok(z.entries[0].flags & 8, 'fixture really uses a data descriptor');
  assert.ok(await same(await z.read(z.entries[0]), MP3));
});

test('only the needed slices of the archive are read', async () => {
  const file = load('deflate.zip');
  const reads = [];
  const spy = new Proxy(file, {
    get(t, k) {
      if (k === 'slice') return (a, b, c) => (reads.push([a, b]), t.slice(a, b, c));
      const v = Reflect.get(t, k, t);
      return typeof v === 'function' ? v.bind(t) : v;
    }
  });
  const z = await ZipReader.open(spy);
  const afterIndex = reads.length;
  await z.read(z.audioEntries()[1]); // the FLAC, second member
  const payload = reads.slice(afterIndex).reduce((n, [a, b]) => n + (b - a), 0);
  const e = z.audioEntries()[1];
  assert.ok(payload <= e.compressedSize + 30 + 1024, 'header plus that member only: ' + payload);
  assert.ok(payload < file.size / 2, 'not the whole archive');
});

test('a flipped byte is caught by the checksum', async () => {
  const z = await ZipReader.open(load('corrupt.zip'));
  await assert.rejects(() => z.read(z.audioEntries()[0]), /damaged/);
  assert.ok(await same(await z.read(z.audioEntries()[1]), FLAC), 'other members still extract');
});

test('encrypted entries are refused with a clear message', async () => {
  const z = await ZipReader.open(load('encrypted.zip'));
  await assert.rejects(() => z.read(z.audioEntries()[0]), /password protected/);
});

test('things that are not ZIP files', async () => {
  await assert.rejects(() => ZipReader.open(load('not-a-zip.zip')), ZipError);
  await assert.rejects(() => ZipReader.open(new File([new Uint8Array(10)], 'tiny.zip')), /not a ZIP/);
  await assert.rejects(() => ZipReader.open(new File([], 'empty.zip')), ZipError);
});

test('helpers', () => {
  assert.ok(isZipFile({ name: 'Album.ZIP', type: '' }));
  assert.ok(isZipFile({ name: 'x', type: 'application/x-zip-compressed' }));
  assert.ok(!isZipFile({ name: 'song.mp3', type: 'audio/mpeg' }));
  assert.equal(mimeFor('a.FLAC'), 'audio/flac');
  assert.equal(mimeFor('a.xyz'), 'application/octet-stream');
});

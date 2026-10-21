// A small ZIP reader for importing albums that come as .zip files.
//
// Same idea as nationdex/nzip: a ZIP keeps its index at the *end* of the file, so we read the tail,
// then the central directory, then exactly the bytes of the one member we want. File.slice() reads
// lazily from disk, so a 2 GB archive is never loaded into memory, and members that are skipped
// are never decompressed. Inflating uses the browser's DecompressionStream; there is no dependency.

export class ZipError extends Error {}

const SIG_EOCD = 0x06054b50;
const SIG_EOCD64 = 0x06064b50;
const SIG_LOCATOR64 = 0x07064b50;
const SIG_CENTRAL = 0x02014b50;
const SIG_LOCAL = 0x04034b50;
const MAX_COMMENT = 0xffff;
const MAX_ENTRIES = 50000;

const AUDIO = /\.(mp3|m4a|m4b|aac|flac|ogg|oga|opus|wav|webm|mp4|aif|aiff|ape)$/i;
const MIME = {
  mp3: 'audio/mpeg',
  m4a: 'audio/mp4',
  m4b: 'audio/mp4',
  aac: 'audio/aac',
  flac: 'audio/flac',
  ogg: 'audio/ogg',
  oga: 'audio/ogg',
  opus: 'audio/ogg',
  wav: 'audio/wav',
  webm: 'audio/webm',
  mp4: 'audio/mp4',
  aif: 'audio/aiff',
  aiff: 'audio/aiff',
  ape: 'audio/x-ape'
};

export const isZipFile = (f) => /\.zip$/i.test(f.name) || f.type === 'application/zip' || f.type === 'application/x-zip-compressed';
export const baseName = (path) => path.slice(path.lastIndexOf('/') + 1);
export const mimeFor = (name) => MIME[name.split('.').pop().toLowerCase()] || 'application/octet-stream';

const bytes = async (blob) => new DataView(await blob.arrayBuffer());
const u64 = (v, o) => {
  const n = v.getUint32(o, true) + v.getUint32(o + 4, true) * 2 ** 32;
  if (!Number.isSafeInteger(n)) throw new ZipError('archive too large');
  return n;
};

function decodeName(raw, utf8Flag) {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(raw);
  } catch {
    if (utf8Flag) throw new ZipError('invalid file name');
    return new TextDecoder('windows-1252').decode(raw); // the usual encoding of old, non-UTF-8 archives
  }
}

function dosDate(date, time) {
  return new Date(
    ((date >> 9) & 0x7f) + 1980,
    ((date >> 5) & 0x0f) - 1,
    date & 0x1f,
    (time >> 11) & 0x1f,
    (time >> 5) & 0x3f,
    (time & 0x1f) * 2
  );
}

let crcTable = null;
async function crc32(blob) {
  if (!crcTable) {
    crcTable = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      crcTable[n] = c >>> 0;
    }
  }
  let crc = 0xffffffff;
  const reader = blob.stream().getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    for (let i = 0; i < value.length; i++) crc = crcTable[(crc ^ value[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

export class ZipReader {
  constructor(file, entries) {
    this.file = file;
    this.entries = entries;
  }

  /** Reads the index of [file] (a File or Blob). Throws ZipError when it is not a readable ZIP. */
  static async open(file) {
    const size = file.size;
    if (size < 22) throw new ZipError('not a ZIP file');
    const tailStart = Math.max(0, size - (22 + MAX_COMMENT));
    const tail = await bytes(file.slice(tailStart, size));
    let eocd = -1;
    for (let i = tail.byteLength - 22; i >= 0; i--) {
      if (tail.getUint32(i, true) === SIG_EOCD) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw new ZipError('not a ZIP file');

    let total = tail.getUint16(eocd + 10, true);
    let cdSize = tail.getUint32(eocd + 12, true);
    let cdOffset = tail.getUint32(eocd + 16, true);
    if (total === 0xffff || cdSize === 0xffffffff || cdOffset === 0xffffffff) {
      // ZIP64: the real numbers live in a second record, found through the locator just before the EOCD.
      const loc = tailStart + eocd - 20;
      if (loc < 0) throw new ZipError('corrupt ZIP64 archive');
      const locator = await bytes(file.slice(loc, loc + 20));
      if (locator.getUint32(0, true) !== SIG_LOCATOR64) throw new ZipError('corrupt ZIP64 archive');
      const at = u64(locator, 8);
      const rec = await bytes(file.slice(at, at + 56));
      if (rec.getUint32(0, true) !== SIG_EOCD64) throw new ZipError('corrupt ZIP64 archive');
      total = u64(rec, 32);
      cdSize = u64(rec, 40);
      cdOffset = u64(rec, 48);
    }
    if (total > MAX_ENTRIES) throw new ZipError('too many files in the archive');
    if (cdOffset + cdSize > size) throw new ZipError('corrupt ZIP index');

    const cd = await bytes(file.slice(cdOffset, cdOffset + cdSize));
    const raw = new Uint8Array(cd.buffer);
    const entries = [];
    let p = 0;
    for (let n = 0; n < total; n++) {
      if (p + 46 > cd.byteLength || cd.getUint32(p, true) !== SIG_CENTRAL) throw new ZipError('corrupt ZIP index');
      const flags = cd.getUint16(p + 8, true);
      const nameLen = cd.getUint16(p + 28, true),
        extraLen = cd.getUint16(p + 30, true),
        commentLen = cd.getUint16(p + 32, true);
      const e = {
        flags,
        method: cd.getUint16(p + 10, true),
        mtime: dosDate(cd.getUint16(p + 14, true), cd.getUint16(p + 12, true)),
        crc: cd.getUint32(p + 16, true),
        compressedSize: cd.getUint32(p + 20, true),
        size: cd.getUint32(p + 24, true),
        offset: cd.getUint32(p + 42, true),
        name: decodeName(raw.subarray(p + 46, p + 46 + nameLen), (flags & 0x800) !== 0)
      };
      // ZIP64 extra field: only the values that overflowed 32 bits are present, in this order.
      for (let x = p + 46 + nameLen, end = x + extraLen; x + 4 <= end; ) {
        const id = cd.getUint16(x, true),
          len = cd.getUint16(x + 2, true);
        if (id === 0x0001) {
          let o = x + 4;
          if (e.size === 0xffffffff) {
            e.size = u64(cd, o);
            o += 8;
          }
          if (e.compressedSize === 0xffffffff) {
            e.compressedSize = u64(cd, o);
            o += 8;
          }
          if (e.offset === 0xffffffff) e.offset = u64(cd, o);
        }
        x += 4 + len;
      }
      e.isDirectory = e.name.endsWith('/');
      entries.push(e);
      p += 46 + nameLen + extraLen + commentLen;
    }
    return new ZipReader(file, entries);
  }

  /** Audio members worth importing: no folders, no macOS metadata (__MACOSX, ._name). */
  audioEntries() {
    return this.entries.filter((e) => !e.isDirectory && AUDIO.test(e.name) && !/(^|\/)(__MACOSX\/|\._)/.test(e.name));
  }

  /** Extracts one member as a Blob. Exactly one slice is read from the archive. Verifies the CRC. */
  async read(entry, { verify = true } = {}) {
    if (entry.flags & 1) throw new ZipError('“' + entry.name + '” is password protected');
    const head = await bytes(this.file.slice(entry.offset, entry.offset + 30));
    if (head.getUint32(0, true) !== SIG_LOCAL) throw new ZipError('corrupt ZIP entry');
    const start = entry.offset + 30 + head.getUint16(26, true) + head.getUint16(28, true);
    const data = this.file.slice(start, start + entry.compressedSize);
    let blob;
    if (entry.method === 0) {
      blob = data.slice(0, entry.size, mimeFor(entry.name));
    } else if (entry.method === 8) {
      if (typeof DecompressionStream === 'undefined') throw new ZipError('this browser cannot unzip files');
      blob = await new Response(data.stream().pipeThrough(new DecompressionStream('deflate-raw'))).blob();
      blob = blob.slice(0, blob.size, mimeFor(entry.name));
    } else {
      throw new ZipError('“' + entry.name + '” uses an unsupported compression method');
    }
    if (blob.size !== entry.size) throw new ZipError('“' + entry.name + '” is damaged (wrong size)');
    if (verify && (await crc32(blob)) !== entry.crc) throw new ZipError('“' + entry.name + '” is damaged (checksum mismatch)');
    return blob;
  }
}

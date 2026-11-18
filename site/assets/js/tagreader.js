// -------------------------------------------------------------- tag reader
// Reads title / artist / album / year / track number / cover art from ID3v2
// (MP3), MP4 (M4A/AAC) and FLAC without any dependency.

const ascii = (b, o, n) => {
  let s = '';
  for (let i = 0; i < n; i++) s += String.fromCharCode(b[o + i]);
  return s;
};
const u32be = (b, o) => ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;
const u32le = (b, o) => ((b[o + 3] << 24) | (b[o + 2] << 16) | (b[o + 1] << 8) | b[o]) >>> 0;
const synchsafe = (b, o) => ((b[o] & 0x7f) << 21) | ((b[o + 1] & 0x7f) << 14) | ((b[o + 2] & 0x7f) << 7) | (b[o + 3] & 0x7f);

function decodeText(bytes, enc) {
  const label = ['iso-8859-1', 'utf-16', 'utf-16be', 'utf-8'][enc] || 'utf-8';
  try {
    return new TextDecoder(label).decode(bytes).replace(/\0+$/g, '').replace(/^﻿/, '');
  } catch {
    return '';
  }
}

function id3TextFrame(body) {
  return decodeText(body.subarray(1), body[0]).split('\0')[0].trim();
}

function id3Picture(body, v2) {
  const enc = body[0];
  let p = 1,
    mime;
  if (v2) {
    mime = 'image/' + ascii(body, 1, 3).toLowerCase().replace('jpg', 'jpeg');
    p = 4;
  } else {
    let e = p;
    while (e < body.length && body[e] !== 0) e++;
    mime = ascii(body, p, e - p) || 'image/jpeg';
    p = e + 1;
  }
  p += 1; // picture type
  if (enc === 1 || enc === 2) {
    while (p + 1 < body.length && !(body[p] === 0 && body[p + 1] === 0)) p += 2;
    p += 2;
  } else {
    while (p < body.length && body[p] !== 0) p++;
    p += 1;
  }
  if (p >= body.length) return null;
  if (!mime.startsWith('image/')) mime = 'image/jpeg';
  return new Blob([body.slice(p)], { type: mime });
}

function readID3(buf) {
  if (buf.length < 10 || ascii(buf, 0, 3) !== 'ID3') return null;
  const ver = buf[3];
  const end = Math.min(10 + synchsafe(buf, 6), buf.length);
  let pos = 10;
  if (buf[5] & 0x40 && ver >= 3) pos += ver === 4 ? synchsafe(buf, pos) : u32be(buf, pos) + 4;
  const tags = {};
  while (pos + 10 <= end) {
    const v2 = ver === 2;
    const id = ascii(buf, pos, v2 ? 3 : 4);
    const size = v2 ? (buf[pos + 3] << 16) | (buf[pos + 4] << 8) | buf[pos + 5] : ver === 4 ? synchsafe(buf, pos + 4) : u32be(buf, pos + 4);
    const hdr = v2 ? 6 : 10;
    if (!/^[A-Z0-9]{3,4}$/.test(id) || size <= 0 || pos + hdr + size > buf.length) break;
    const body = buf.subarray(pos + hdr, pos + hdr + size);
    pos += hdr + size;
    if (id === 'TIT2' || id === 'TT2') tags.title = id3TextFrame(body);
    else if (id === 'TPE1' || id === 'TP1') tags.artist = id3TextFrame(body);
    else if (id === 'TPE2' || id === 'TP2') tags.albumArtist = id3TextFrame(body);
    else if (id === 'TALB' || id === 'TAL') tags.album = id3TextFrame(body);
    else if (id === 'TRCK' || id === 'TRK') tags.trackNo = parseInt(id3TextFrame(body), 10) || 0;
    else if (id === 'TDRC' || id === 'TYER' || id === 'TYE') tags.year = (id3TextFrame(body).match(/\d{4}/) || [''])[0];
    else if ((id === 'APIC' || id === 'PIC') && !tags.picture) tags.picture = id3Picture(body, v2);
  }
  return tags;
}

function readMP4(buf) {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const atoms = (start, end, cb) => {
    let p = start;
    while (p + 8 <= end) {
      let size = dv.getUint32(p),
        hdr = 8;
      const type = ascii(buf, p + 4, 4);
      if (size === 1) {
        size = Number(dv.getBigUint64(p + 8));
        hdr = 16;
      } else if (size === 0) size = end - p;
      if (size < hdr || p + size > end) break;
      cb(type, p + hdr, p + size);
      p += size;
    }
  };
  const tags = {};
  const item = (type, s, e) =>
    atoms(s, e, (t, ds, de) => {
      if (t !== 'data') return;
      const kind = dv.getUint32(ds) & 0xffffff;
      const payload = buf.subarray(ds + 8, de);
      const text = () => new TextDecoder().decode(payload).trim();
      if (type === '©nam') tags.title = text();
      else if (type === '©ART') tags.artist = text();
      else if (type === 'aART') tags.albumArtist = text();
      else if (type === '©alb') tags.album = text();
      else if (type === '©day') tags.year = (text().match(/\d{4}/) || [''])[0];
      else if (type === 'trkn' && payload.length >= 4) tags.trackNo = (payload[2] << 8) | payload[3];
      else if (type === 'covr' && !tags.picture)
        tags.picture = new Blob([payload.slice()], { type: kind === 14 ? 'image/png' : 'image/jpeg' });
    });
  atoms(0, buf.length, (t, s, e) => {
    if (t !== 'moov') return;
    atoms(s, e, (t2, s2, e2) => {
      if (t2 === 'udta')
        atoms(s2, e2, (t3, s3, e3) => {
          if (t3 === 'meta')
            atoms(s3 + 4, e3, (t4, s4, e4) => {
              if (t4 === 'ilst') atoms(s4, e4, item);
            });
        });
    });
  });
  return Object.keys(tags).length ? tags : null;
}

function readFLAC(buf) {
  if (buf.length < 8 || ascii(buf, 0, 4) !== 'fLaC') return null;
  const tags = {};
  let pos = 4;
  while (pos + 4 <= buf.length) {
    const last = buf[pos] & 0x80,
      type = buf[pos] & 0x7f;
    const len = (buf[pos + 1] << 16) | (buf[pos + 2] << 8) | buf[pos + 3];
    const body = buf.subarray(pos + 4, pos + 4 + len);
    pos += 4 + len;
    if (type === 4 && body.length > 8) {
      let p = 4 + u32le(body, 0);
      const count = u32le(body, p);
      p += 4;
      for (let i = 0; i < count && p + 4 <= body.length; i++) {
        const n = u32le(body, p);
        p += 4;
        const kv = new TextDecoder().decode(body.subarray(p, p + n));
        p += n;
        const eq = kv.indexOf('=');
        if (eq < 0) continue;
        const k = kv.slice(0, eq).toUpperCase(),
          v = kv.slice(eq + 1).trim();
        if (k === 'TITLE') tags.title = v;
        else if (k === 'ARTIST') tags.artist = v;
        else if (k === 'ALBUMARTIST') tags.albumArtist = v;
        else if (k === 'ALBUM') tags.album = v;
        else if (k === 'TRACKNUMBER') tags.trackNo = parseInt(v, 10) || 0;
        else if (k === 'DATE') tags.year = (v.match(/\d{4}/) || [''])[0];
      }
    } else if (type === 6 && body.length > 32 && !tags.picture) {
      let p = 4;
      const mlen = u32be(body, p);
      p += 4;
      const mime = ascii(body, p, mlen);
      p += mlen;
      const dlen = u32be(body, p);
      p += 4 + dlen + 16;
      const n = u32be(body, p);
      p += 4;
      tags.picture = new Blob([body.slice(p, p + n)], { type: mime || 'image/jpeg' });
    }
    if (last) break;
  }
  return tags;
}

export async function readTags(file) {
  if (file.size > 120 * 1024 * 1024) return {};
  try {
    const buf = new Uint8Array(await file.arrayBuffer());
    return readID3(buf) || readFLAC(buf) || readMP4(buf) || {};
  } catch (e) {
    console.warn('Tag read failed for', file.name, e);
    return {};
  }
}

export function probeDuration(file) {
  return new Promise((resolve) => {
    const a = new Audio();
    const url = URL.createObjectURL(file);
    const done = (v) => {
      URL.revokeObjectURL(url);
      resolve(v);
    };
    a.preload = 'metadata';
    a.onloadedmetadata = () => done(isFinite(a.duration) ? a.duration : 0);
    a.onerror = () => done(0);
    setTimeout(() => done(0), 6000);
    a.src = url;
  });
}

export async function compressArtwork(blob) {
  try {
    const bmp = await createImageBitmap(blob);
    const scale = Math.min(1, 512 / Math.max(bmp.width, bmp.height));
    const c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(bmp.width * scale));
    c.height = Math.max(1, Math.round(bmp.height * scale));
    c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
    return await new Promise((res) => c.toBlob((b) => res(b || blob), 'image/jpeg', 0.86));
  } catch {
    return blob;
  }
}

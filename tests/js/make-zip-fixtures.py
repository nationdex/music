#!/usr/bin/env python3
"""Builds the ZIP fixtures used by tests/js/zip.test.mjs and mobile/test (run from the repo root).

    python3 tests/js/make-zip-fixtures.py
"""
import io
import os
import struct
import zipfile

OUT = "tests/fixtures/zip"
os.makedirs(OUT, exist_ok=True)
AUDIO = open("mobile/test/fixtures/tagged.mp3", "rb").read()
FLAC = open("mobile/test/fixtures/tagged.flac", "rb").read()
TEXT = b"cover art placeholder\n" * 50


def write(name, build):
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(build())


def plain(compression):
    def build():
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", compression) as z:
            z.writestr("Album/", b"")
            z.writestr("Album/01 - Midnight Drive.mp3", AUDIO)
            z.writestr("Album/02 - Salt Air.flac", FLAC)
            z.writestr("Album/cover.jpg", TEXT)
            z.writestr("Album/notes.txt", TEXT)
            z.writestr("__MACOSX/Album/._01 - Midnight Drive.mp3", b"\0" * 120)
            z.writestr("Album/._02 - Salt Air.flac", b"\0" * 120)
        return buf.getvalue()
    return build


def zip64():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as z:
        for name, data in (("a/one.mp3", AUDIO), ("a/two.flac", FLAC)):
            with z.open(zipfile.ZipInfo(name), "w", force_zip64=True) as f:
                f.write(data)
    return buf.getvalue()


def unicode_names():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("Música/Canción ñandú ☃.mp3", AUDIO)
    return buf.getvalue()


def with_comment():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("song.mp3", AUDIO)
        z.comment = b"x" * 4000
    return buf.getvalue()


def streamed():
    # Written to a non-seekable stream: sizes and CRC come after the data (general-purpose bit 3).
    class Unseekable(io.RawIOBase):
        def __init__(self):
            self.data = bytearray()
        def writable(self):
            return True
        def write(self, b):
            self.data += b
            return len(b)
    out = Unseekable()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("song.mp3", AUDIO)
    return bytes(out.data)


def corrupt():
    raw = bytearray(plain(zipfile.ZIP_STORED)())
    i = raw.index(AUDIO[:32]) + 100  # a byte inside the stored mp3
    raw[i] ^= 0xFF
    return bytes(raw)


def encrypted():
    raw = bytearray(plain(zipfile.ZIP_STORED)())
    # set the "encrypted" bit in every central directory header
    pos = 0
    while True:
        pos = raw.find(b"PK\x01\x02", pos)
        if pos < 0:
            break
        flags = struct.unpack_from("<H", raw, pos + 8)[0] | 1
        struct.pack_into("<H", raw, pos + 8, flags)
        pos += 4
    return bytes(raw)


write("deflate.zip", plain(zipfile.ZIP_DEFLATED))
write("stored.zip", plain(zipfile.ZIP_STORED))
write("zip64.zip", zip64)
write("unicode.zip", unicode_names)
write("comment.zip", with_comment)
write("streamed.zip", streamed)
write("corrupt.zip", corrupt)
write("encrypted.zip", encrypted)
write("not-a-zip.zip", lambda: b"this is not a zip file at all" * 10)
print("wrote", len(os.listdir(OUT)), "fixtures to", OUT)

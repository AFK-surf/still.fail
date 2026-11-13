#!/usr/bin/env python3
"""The marks' contract's picture (scripts/host_contract.sh HOST marks): made here, flat colours only, so that its
bytes are this script's alone. 480x320 RGB: a pale ground, a blue band, a dark tile, a green disc, a stripe of greys.

  python3 test/marks/base.py      test/marks/base.png
"""
import os
import struct
import zlib

W, H = 480, 320


def pixel(x, y):
    if 24 <= x < 456 and 24 <= y < 104:
        return (0x8E, 0xC5, 0xFC)  # the band
    if 300 <= x < 420 and 140 <= y < 260:
        return (0x2B, 0x2F, 0x3A)  # the tile
    if (x - 140) ** 2 + (y - 200) ** 2 < 60 ** 2:
        return (0x5B, 0xB9, 0x8B)  # the disc
    if 280 <= y < 296:
        g = 0x60 + (x // 60) * 0x14
        return (g, g, g)  # the stripe, eight greys
    return (0xF4, 0xF1, 0xEA)  # the ground


def chunk(kind, data):
    c = kind + data
    return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)


def png():
    raw = b"".join(b"\0" + bytes(v for x in range(W) for v in pixel(x, y)) for y in range(H))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "base.png"), "wb") as f:
        f.write(png())

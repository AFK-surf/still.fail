#!/usr/bin/env python3
# How much a row of a screenshot varies: pngrow.py SHOT.png Y X0 X1 (logical points of a 2x shot) prints the
# luminance's standard deviation over that row and its mean (0-255). A flat ground prints 0; glass over what scrolls
# under it does not. Reads 8-bit RGB/RGBA PNGs (what the hosts' snapshots write), no packages.
import struct, sys, zlib


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
    i, idat, w = 8, b'', 0
    while i < len(data):
        n, kind = struct.unpack('>I4s', data[i:i + 8])
        body = data[i + 8:i + 8 + n]
        if kind == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and ctype in (2, 6) and interlace == 0, 'an 8-bit RGB(A) PNG'
            bpp = 4 if ctype == 6 else 3
        elif kind == b'IDAT':
            idat += body
        i += 12 + n
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return w, h, bpp, rows


path, y, x0, x1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
w, h, bpp, rows = read_png(path)
k = w / 390.0
row = rows[min(h - 1, int(y * k))]
lum = []
for x in range(int(x0 * k), min(w, int(x1 * k))):
    r, g, b = row[x * bpp], row[x * bpp + 1], row[x * bpp + 2]
    lum.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
m = sum(lum) / len(lum)
sd = (sum((v - m) ** 2 for v in lum) / len(lum)) ** 0.5
print('%.2f %.1f' % (sd, m))

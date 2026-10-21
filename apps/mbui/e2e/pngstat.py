#!/usr/bin/env python3
# Whether a part of a screenshot shows something: pngstat.py FILE X0 Y0 X1 Y1 N passes (exit 0) when the rect (in
# shares of the picture's width and height) holds at least N different colours (a video's frame has many, a black
# box one). A PNG reader of its own (8-bit RGB or RGBA, any filter), so it needs nothing installed.
import struct, sys, zlib

def read(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
    i, idat, w = 8, b'', 0
    while i < len(data):
        n, kind = struct.unpack('>I4s', data[i:i + 8])
        body = data[i + 8:i + 8 + n]
        if kind == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
            assert depth == 8 and ctype in (2, 6), 'only 8-bit RGB(A)'
            bpp = 3 if ctype == 2 else 4
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
        rows.append(bytes(line))
        prev = line
    return w, h, bpp, rows

path, x0, y0, x1, y1, n = sys.argv[1], *map(float, sys.argv[2:6]), int(sys.argv[6])
w, h, bpp, rows = read(path)
seen = set()
for y in range(int(y0 * h), int(y1 * h), 2):
    r = rows[y]
    for x in range(int(x0 * w), int(x1 * w), 2):
        seen.add(r[x * bpp:x * bpp + 3])
print(f'{path}: {len(seen)} colours in the rect')
sys.exit(0 if len(seen) >= n else 1)

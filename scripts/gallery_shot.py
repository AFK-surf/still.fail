#!/usr/bin/env python3
# Whether a picture is of kitdemo's gallery (src/kitdemo/main.mbt: a page in both themes side by side), not of what
# lies before or over it (a system's splash, a blank window) or of a page it has not ("No page …"): its left half on
# the light theme's ground, its right half on the dark's, each with as much drawn on it as a page has. The picture's
# own rows only: a phone's status bar, its gesture bar, above and below the window are left out.
#
#   gallery_shot.py PNG           exit 0, saying what it found; else 1, saying why
#   gallery_shot.py PNG OTHER     both the gallery, and the same in the window's rows, to the byte (what the system
#                                 draws around it, its clock in the status bar, is not the app's)
import struct, sys, zlib

LIGHT = (0xFF, 0xFF, 0xFF)  # Theme::light().bg (src/ui/theme.mbt)
DARK = (0x1F, 0x20, 0x23)   # Theme::dark().bg
# (of a half's ground, at least this share its theme's ground, and at least this share other: drawn on)
GROUND_MOST, DRAWN_LEAST = 0.5, 0.03


def pixels(path):
    d = open(path, 'rb').read()
    i, idat = 8, b''
    while i < len(d):
        n = struct.unpack('>I', d[i:i + 4])[0]
        t, c = d[i + 4:i + 8], d[i + 8:i + 8 + n]
        if t == b'IHDR':
            w, h, depth, ct = struct.unpack('>IIBB', c[:10])
        elif t == b'IDAT':
            idat += c
        i += 12 + n
    if depth != 8 or ct not in (2, 6):
        sys.exit(f"gallery shot: {path}: not an 8-bit RGB(A) PNG")
    bpp = 4 if ct == 6 else 3
    raw, stride = zlib.decompress(idat), w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
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


def gallery(path):
    """The window's rows of the picture at `path` (its rows, from, to), or None, said why."""
    w, h, bpp, rows = pixels(path)
    px = lambda x, y: tuple(rows[y][x * bpp:x * bpp + 3])
    # the window's rows: those whose two halves' middles are the two grounds (a phone's bars are neither)
    mid_l, mid_r = w // 4, 3 * w // 4
    window = [y for y in range(h) if px(2, y) == LIGHT and px(w - 3, y) == DARK]
    if not window:
        print(f"gallery shot: {path}: no row with the light ground at its left and the dark at its right: not the gallery")
        return None
    ys = range(window[0], window[-1] + 1)
    for name, x0, x1, ground in (("left", 0, w // 2, LIGHT), ("right", w // 2, w, DARK)):
        n = on = 0
        for y in ys[::4]:
            for x in range(x0, x1, 4):
                n += 1
                on += px(x, y) == ground
        share = on / n
        if share < GROUND_MOST or 1 - share < DRAWN_LEAST:
            print(f"gallery shot: {path}: its {name} half {share:.0%} its ground: not a page of the gallery's")
            return None
    print(f"gallery shot: {path}: the gallery, rows {window[0]}..{window[-1]}")
    return rows, window[0], window[-1]


def main():
    found = [gallery(p) for p in sys.argv[1:3]]
    if None in found:
        return 1
    if len(found) == 2:
        (a, a0, a1), (b, b0, b1) = found
        if (a0, a1) != (b0, b1) or a[a0:a1 + 1] != b[b0:b1 + 1]:
            print(f"gallery shot: {sys.argv[1]} and {sys.argv[2]}: the window's rows differ")
            return 1
        print(f"gallery shot: {sys.argv[1]} and {sys.argv[2]}: the window's rows the same, to the byte")
    return 0


if __name__ == "__main__":
    sys.exit(main())

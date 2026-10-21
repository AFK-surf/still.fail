#!/usr/bin/env python3
"""The mbui app's pictures against Android's, pixel by pixel (scripts/android-ref.sh compare).

  android_ref.py REFS MBUI OUT ALLOWED NAME…

REFS/NAME.png (Android's), MBUI/NAME.png (the mbui app's, the same emulator's screen): every pixel whose colour
differs counts (a channel more than one step apart: Android's same picture on two runners has differed by that alone,
31 px at circles' edges, one channel a step; within a run it never has), but those under the system's bars (their
icons the system's: REFS/android.json `bars`, the rows at the top and the bottom) and those inside a region ALLOWED
lets differ. allowed.json: {"NAME": {"regions": [{"x", "y", "w", "h", "why"}], "left": N, "why": …}}: `left` the
pixels the mbui app is known to differ by still, outside its regions (what is not done yet, said in `why`): a screen
fails when it differs by more, and is told to lower it when by fewer (the number only falls).
  android_ref.py place PICTURE OUT WIDTH HEIGHT TOP

`place`: the mbui app's window drawn offscreen (PICTURE: mbui-render's of its draw list, the window between the
emulator's bars) put where the window is on the emulator's screen (WIDTH × HEIGHT, its top TOP rows down: the bars'
rows black, which the comparison leaves out), as Android's picture is of the whole screen.

Out: OUT/NAME.png (Android | mbui | Android greyed with the differing pixels red, the allowed regions outlined blue,
at half size), OUT/report.md (each screen's count and where its differences lie). Exit 1 when a screen differs
outside its regions by more than its `left`, or a picture is missing or of another size.
"""
import json
import os
import struct
import sys
import zlib

CELL = 16


def load(path):
    """A PNG (8 bits, RGB or RGBA) as (w, h, rows of RGB bytes)."""
    data = open(path, "rb").read()
    i, idat, w = 8, b"", 0
    while i < len(data):
        n, = struct.unpack(">I", data[i:i + 4])
        kind, chunk = data[i + 4:i + 8], data[i + 8:i + 8 + n]
        if kind == b"IHDR":
            w, h, depth, ct = struct.unpack(">IIBB", chunk[:10])
            if depth != 8 or ct not in (2, 6):
                raise ValueError(f"{path}: not an 8-bit RGB(A) PNG")
        elif kind == b"IDAT":
            idat += chunk
        i += 12 + n
    raw = zlib.decompress(idat)
    bpp = 4 if ct == 6 else 3
    stride = w * bpp
    prev = bytearray(stride)
    rows, o = [], 0
    for _ in range(h):
        f = raw[o]
        line = bytearray(raw[o + 1:o + 1 + stride])
        o += 1 + stride
        if f == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        rows.append(bytes(line) if bpp == 3 else bytes(b for k, b in enumerate(line) if k % 4 != 3))
    return w, h, rows


def save(path, w, h, rows):
    """RGB rows as a PNG."""
    raw = b"".join(b"\0" + r for r in rows)
    chunk = lambda k, d: struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def regions(cells):
    """The cells with differences, joined where they touch, as rectangles (x, y, w, h, pixels) in the screen's pixels."""
    seen, out = set(), []
    for start in sorted(cells):
        if start in seen:
            continue
        stack, group = [start], []
        seen.add(start)
        while stack:
            cx, cy = stack.pop()
            group.append((cx, cy))
            for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                if (nx, ny) in cells and (nx, ny) not in seen:
                    seen.add((nx, ny))
                    stack.append((nx, ny))
        xs, ys = [c[0] for c in group], [c[1] for c in group]
        out.append((min(xs) * CELL, min(ys) * CELL, (max(xs) - min(xs) + 1) * CELL, (max(ys) - min(ys) + 1) * CELL,
                    sum(cells[c] for c in group)))
    return sorted(out, key=lambda r: -r[4])


def main():
    refs, mbui, out, allowed_path, names = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
    allowed = json.load(open(allowed_path)) if os.path.exists(allowed_path) else {}
    bars = json.load(open(os.path.join(refs, "android.json"))).get("bars", {"top": 0, "bottom": 0})
    os.makedirs(out, exist_ok=True)
    report, failed, lower = ["| screen | pixels differing | outside its regions (left) | where (x, y, w, h: pixels) |",
                             "|---|---|---|---|"], [], []
    for name in names:
        a_path, m_path = os.path.join(refs, name + ".png"), os.path.join(mbui, name + ".png")
        if not os.path.exists(a_path) or not os.path.exists(m_path):
            report.append(f"| {name} | — | missing: {'Android' if not os.path.exists(a_path) else 'mbui'}'s picture | |")
            failed.append(name)
            continue
        aw, ah, arows = load(a_path)
        mw, mh, mrows = load(m_path)
        if (aw, ah) != (mw, mh):
            report.append(f"| {name} | — | another size: Android {aw}×{ah}, mbui {mw}×{mh} | |")
            failed.append(name)
            continue
        mine = allowed.get(name, {})
        rects = [(r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"]) for r in mine.get("regions", [])]
        left = mine.get("left", 0)
        inside = lambda x, y: any(x0 <= x < x1 and y0 <= y < y1 for x0, y0, x1, y1 in rects)
        total, outside, cells = 0, 0, {}
        diff_rows = []
        for y in range(ah):
            ar, mr = arows[y], mrows[y]
            row = bytearray(len(ar))
            if y < bars["top"] or y >= ah - bars["bottom"]:
                diff_rows.append(bytes(b"\xd0" * len(ar)))
                continue
            for x in range(aw):
                k = x * 3
                g = (ar[k] * 30 + ar[k + 1] * 59 + ar[k + 2] * 11) // 100
                g = 128 + g // 2
                if abs(ar[k] - mr[k]) > 1 or abs(ar[k + 1] - mr[k + 1]) > 1 or abs(ar[k + 2] - mr[k + 2]) > 1:
                    total += 1
                    if not inside(x, y):
                        outside += 1
                        c = (x // CELL, y // CELL)
                        cells[c] = cells.get(c, 0) + 1
                    row[k:k + 3] = b"\xe0\x20\x20"
                else:
                    row[k:k + 3] = bytes((g, g, g))
            for x0, y0, x1, y1 in rects:
                if y in (y0, y1 - 1):
                    for x in range(max(0, x0), min(aw, x1)):
                        row[x * 3:x * 3 + 3] = b"\x20\x60\xe0"
                elif y0 < y < y1 - 1:
                    for x in (x0, x1 - 1):
                        if 0 <= x < aw:
                            row[x * 3:x * 3 + 3] = b"\x20\x60\xe0"
            diff_rows.append(bytes(row))
        # Android | mbui | the differences, at half size
        half = []
        for y in range(0, ah, 2):
            line = bytearray()
            for src in (arows[y], mrows[y], diff_rows[y]):
                for x in range(0, aw, 2):
                    line += src[x * 3:x * 3 + 3]
                line += b"\xff\xff\xff" * 8
            half.append(bytes(line))
        save(os.path.join(out, name + ".png"), (aw // 2 + 8) * 3, len(half), half)
        where = "; ".join(f"{x}, {y}, {w}, {h}: {n}" for x, y, w, h, n in regions(cells)[:8])
        report.append(f"| {name} | {total} of {aw * ah} | {outside} ({left}) | {where} |")
        if outside > left:
            failed.append(name)
        elif outside < left:
            lower.append(f"{name} {outside} (was {left})")
    report.append("")
    report.append(f"Android | mbui | Android greyed, the pixels that differ red, the regions allowed.json lets differ "
                  f"outlined blue: {out}/NAME.png.")
    open(os.path.join(out, "report.md"), "w").write("\n".join(report) + "\n")
    print("\n".join(report))
    if lower:
        print(f"android-ref: closer to Android's than allowed.json's `left` says, lower it: {', '.join(lower)}")
    if failed:
        print(f"android-ref: {len(failed)} of {len(names)} screens differ from Android's by more than allowed.json "
              f"allows (its regions, its `left`): {', '.join(failed)}")
        sys.exit(1)


def place(picture, out, width, height, top):
    w, h, rows = load(picture)
    if w != width or top + h > height:
        sys.exit(f"android_ref: {picture} is {w}×{h}: not a window {width} wide that fits {height} from {top} down")
    blank = bytes(3 * width)
    save(out, width, height, [blank] * top + rows + [blank] * (height - top - h))


if __name__ == "__main__":
    if sys.argv[1:2] == ["place"]:
        place(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]))
    else:
        main()

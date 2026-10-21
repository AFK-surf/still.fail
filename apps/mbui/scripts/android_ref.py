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

Words are compared by where they stand, not by their pixels (a line set a fraction of a pixel apart differs in every
pixel along its edges, which hides what else differs): REFS/NAME.texts.json (Android's lines: ScreensRefTest, in the
screen's pixels) and MBUI/NAME.texts.json (the mbui app's: the Tester's text runs, in points, with the window's scale
and where it lies), each line {"t": words, "x0", "x1": its first letter's left, its last's right, "b": its baseline,
"top", "bot"}. Their boxes (both apps', a pixel around) are left out of the pixels compared; the lines are paired by
their words (in order where words repeat) and one counts as apart when its left, right or baseline is more than
TEXT_PX from Android's, or when either app has a line the other has not. allowed.json's `texts_left`: how many lines
are known apart still (the number only falls, as `left`).

Out: OUT/NAME.png (Android | mbui | Android greyed with the differing pixels red, the allowed regions outlined blue,
the words' boxes left out green, at half size), OUT/report.md (each screen's count and where its differences lie, its
lines apart). Exit 1 when a screen differs outside its regions by more than its `left`, its lines apart are more than
its `texts_left`, or a picture is missing or of another size.
"""
import json
import os
import struct
import sys
import zlib

CELL = 16
# how far a line may stand from Android's (its left, right or baseline, in the screen's pixels) and be where it is
TEXT_PX = 0.5
# how far around a line's box its pixels are left out (antialiasing reaches past the box by a pixel)
TEXT_PAD = 2


def texts(path, top=0):
    """A screen's lines (texts.json), in the screen's pixels: the mbui app's in points, with the window's scale, put
    `top` rows down (where its window lies on the screen: {"scale", "lines"}); Android's in the screen's pixels already
    (a list)."""
    if not os.path.exists(path):
        return None
    d = json.load(open(path))
    if not isinstance(d, dict):
        return d
    scale = d["scale"]
    return [{"t": l["t"], "x0": l["x0"] * scale, "x1": l["x1"] * scale, "b": l["b"] * scale + top,
             "top": l["top"] * scale + top, "bot": l["bot"] * scale + top} for l in d["lines"]]


def pair(android, mbui):
    """The lines paired by their words, in order where words repeat: (Android's, mbui's), and those of each alone."""
    left = list(mbui)
    pairs, alone_a = [], []
    for a in android:
        k = next((i for i, m in enumerate(left) if m["t"] == a["t"]), -1)
        if k < 0:
            alone_a.append(a)
        else:
            pairs.append((a, left.pop(k)))
    return pairs, alone_a, left


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
    text_report = ["| screen | Android's lines | lines apart (texts_left) | which (pixels: mbui's less Android's) |",
                   "|---|---|---|---|"]
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
        # the words: compared by where they stand; their boxes left out of the pixels
        a_texts = texts(os.path.join(refs, name + ".texts.json"))
        m_texts = texts(os.path.join(mbui, name + ".texts.json"), top=bars["top"])
        boxes = []
        apart = []
        if a_texts is not None and m_texts is not None:
            for l in a_texts + m_texts:
                boxes.append((int(l["x0"]) - TEXT_PAD, int(l["top"]) - TEXT_PAD, int(l["x1"]) + 1 + TEXT_PAD,
                              int(l["bot"]) + 1 + TEXT_PAD))
            pairs, alone_a, alone_m = pair(a_texts, m_texts)
            for a, m in pairs:
                d = (m["x0"] - a["x0"], m["x1"] - a["x1"], m["b"] - a["b"])
                if max(abs(v) for v in d) > TEXT_PX:
                    apart.append((max(abs(v) for v in d), f'"{a["t"][:24]}" left {d[0]:+.1f} right {d[1]:+.1f} '
                                  f'baseline {d[2]:+.1f}'))
            apart += [(1e9, f'"{a["t"][:24]}" Android\'s alone') for a in alone_a]
            apart += [(1e9, f'"{m["t"][:24]}" mbui\'s alone') for m in alone_m]
            apart.sort(key=lambda p: -p[0])
        # (a row's boxes, for the rows they cover)
        row_boxes = {}
        for b in boxes:
            for y in range(max(0, b[1]), min(ah, b[3])):
                row_boxes.setdefault(y, []).append((b[0], b[2]))
        texts_left = mine.get("texts_left", 0)
        inside = lambda x, y: any(x0 <= x < x1 and y0 <= y < y1 for x0, y0, x1, y1 in rects)
        total, outside, cells = 0, 0, {}
        diff_rows = []
        for y in range(ah):
            ar, mr = arows[y], mrows[y]
            row = bytearray(len(ar))
            if y < bars["top"] or y >= ah - bars["bottom"]:
                diff_rows.append(bytes(b"\xd0" * len(ar)))
                continue
            spans = row_boxes.get(y, [])
            for x in range(aw):
                k = x * 3
                g = (ar[k] * 30 + ar[k + 1] * 59 + ar[k + 2] * 11) // 100
                g = 128 + g // 2
                if spans and any(x0 <= x < x1 for x0, x1 in spans):
                    row[k:k + 3] = bytes((g // 2, g, g // 2))
                elif abs(ar[k] - mr[k]) > 1 or abs(ar[k + 1] - mr[k + 1]) > 1 or abs(ar[k + 2] - mr[k + 2]) > 1:
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
        if a_texts is not None and m_texts is not None:
            text_report.append(f"| {name} | {len(a_texts)} | {len(apart)} ({texts_left}) | "
                               + "; ".join(t for _, t in apart[:8]) + " |")
            if len(apart) > texts_left:
                failed.append(name)
            elif len(apart) < texts_left:
                lower.append(f"{name} texts_left {len(apart)} (was {texts_left})")
    if len(text_report) > 2:
        report += [""] + text_report
    report.append("")
    report.append(f"Android | mbui | Android greyed, the pixels that differ red, the regions allowed.json lets differ "
                  f"outlined blue, the words' boxes (compared by where they stand) green: {out}/NAME.png.")
    open(os.path.join(out, "report.md"), "w").write("\n".join(report) + "\n")
    print("\n".join(report))
    if lower:
        print(f"android-ref: closer to Android's than allowed.json's `left` says, lower it: {', '.join(lower)}")
    if failed:
        failed = sorted(set(failed))
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

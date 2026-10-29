#!/usr/bin/env python3
"""still.fail's brand art (README.md here says what it is), made from Inter Bold and written where each app takes it.

    python3 design/brand/make.py          the SVGs and the Android drawables (fontTools and uharfbuzz)
    python3 design/brand/make.py png      and the rasters, drawn by headless Chrome (CHROME, else the Mac's)

Inter is the web app's own (node_modules' @fontsource-variable/inter, after pnpm install), at weight 700. Paths are
written as cubics only (M L C Z): every reader of them takes those (mbui's drawables, VectorDrawables, mac-icon.swift).
"""
import glob, io, os, re, signal, subprocess, sys, tempfile, time
import xml.etree.ElementTree as ET

from fontTools.pens.basePen import BasePen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
import uharfbuzz as hb

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg2vd  # noqa: E402  (the SVG → VectorDrawable converter)
import illus  # noqa: E402

ORANGE = "#E5704A"
INK, INK_DARK = "#18181B", "#F4F4F5"
PAPER, NIGHT = "#FAFAF9", "#111114"
BLACK_FACE, WHITE_FACE, BLUSH = "#1C1D20", "#F4F4F5", "#F6BC9F"
# Each app's face: its tile, its eyes, its cheeks, and whether the beta's tape is across its corner. still.fail is the
# black face where things are light and the white face where they are dark (mbui's app is still.fail's now, its own
# violet gone: 2026-10-29); youdid.wtf the same under the tape; the debug build grey.
VARIANTS = {
    "stable": (BLACK_FACE, "#FFFFFF", BLUSH, False),
    "stable-dark": (WHITE_FACE, BLACK_FACE, BLUSH, False),
    "beta": (BLACK_FACE, "#FFFFFF", BLUSH, True),
    "beta-dark": (WHITE_FACE, BLACK_FACE, BLUSH, True),
    "debug": ("#5F646B", "#FFFFFF", "#9AA0A7", False),
}
WORD_TRACK = -0.02     # the wordmark's (em), as the site's headline
DOT_IN = 0.035         # the wordmark's dot drawn closer to the words it joins, each side (em)


# ---- Inter Bold ----

def inter():
    """Inter's variable font file: INTER, else the web app's (node_modules)."""
    found = [os.environ["INTER"]] if os.environ.get("INTER") else sorted(glob.glob(os.path.join(
        REPO, "node_modules/.pnpm/@fontsource-variable+inter@*/node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2")))
    if not found:
        sys.exit("make.py: no Inter (pnpm install first, or INTER=its woff2)")
    return found[-1]


def _font():
    font = TTFont(inter())
    font.flavor = None
    inst = instancer.instantiateVariableFont(font, {"wght": 700})
    buf = io.BytesIO()
    inst.save(buf)
    return inst, buf.getvalue()


FONT, BLOB = _font()
UPM = FONT["head"].unitsPerEm
GS = FONT.getGlyphSet()
CMAP = FONT.getBestCmap()


def f(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


class CubicPen(BasePen):
    """A path of M, L, C and Z only (the font's quadratics raised to cubics)."""

    def __init__(self, glyph_set=None):
        super().__init__(glyph_set)
        self.d, self.cur = [], None

    def _moveTo(self, p):
        self.d.append(f"M{f(p[0])} {f(p[1])}"); self.cur = p

    def _lineTo(self, p):
        self.d.append(f"L{f(p[0])} {f(p[1])}"); self.cur = p

    def _curveToOne(self, a, b, c):
        self.d.append(f"C{f(a[0])} {f(a[1])} {f(b[0])} {f(b[1])} {f(c[0])} {f(c[1])}"); self.cur = c

    def _qCurveToOne(self, q, p):
        p0 = self.cur
        self._curveToOne((p0[0] + 2 / 3 * (q[0] - p0[0]), p0[1] + 2 / 3 * (q[1] - p0[1])),
                         (p[0] + 2 / 3 * (q[0] - p[0]), p[1] + 2 / 3 * (q[1] - p[1])), p)

    def _closePath(self):
        self.d.append("Z")

    def _endPath(self):
        pass


def glyph(ch):
    return CMAP[ord(ch)]


def bounds(name):
    bp = BoundsPen(GS)
    GS[name].draw(bp)
    return bp.bounds  # x0 y0 x1 y1, y up


def outline(name, k, x, y):
    """The glyph's outline at scale k (per font unit), its origin at (x, y) on the page (y down)."""
    pen = CubicPen(GS)
    GS[name].draw(TransformPen(pen, (k, 0, 0, -k, x, y)))
    return "".join(pen.d)


def shape(text, tracking):
    """Glyph names and their pen x (font units) as harfbuzz sets `text` (its kerning), with tracking per glyph."""
    font = hb.Font(hb.Face(BLOB))
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {"kern": True, "liga": False, "calt": False})
    out, x, order = [], 0, FONT.getGlyphOrder()
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        out.append((order[info.codepoint], x + pos.x_offset))
        x += pos.x_advance + tracking * UPM
    return out


# ---- the face ----
# On a tile 100 square (the old app icon's, design/app-icon before 2026-10-26, its eyes a little larger to hold at
# 16 px): two round eyes, two cheeks; the beta's tape a band at 45° across the top right corner, between the lines
# x − y = 42 and 62, so it stays inside a launcher's round mask (the middle circle of 50) and clear of the eyes, BETA on
# it in Inter Bold.

EYES = ((32.4, 47.6), (67.6, 47.6))
EYE_R = 6.6
CHEEKS = ((14, 67.8), (71.6, 67.8))
CHEEK = (14.4, 7.8)
TAPE = (42, 62)
K = 0.5523  # a quarter circle's cubic handle


def circle_path(cx, cy, r):
    k = K * r
    return (f"M{f(cx + r)} {f(cy)}C{f(cx + r)} {f(cy + k)} {f(cx + k)} {f(cy + r)} {f(cx)} {f(cy + r)}"
            f"C{f(cx - k)} {f(cy + r)} {f(cx - r)} {f(cy + k)} {f(cx - r)} {f(cy)}"
            f"C{f(cx - r)} {f(cy - k)} {f(cx - k)} {f(cy - r)} {f(cx)} {f(cy - r)}"
            f"C{f(cx + k)} {f(cy - r)} {f(cx + r)} {f(cy - k)} {f(cx + r)} {f(cy)}Z")


def pill_path(x, y, w, h):
    r = h / 2
    k = K * r
    return (f"M{f(x + r)} {f(y)}L{f(x + w - r)} {f(y)}C{f(x + w - r + k)} {f(y)} {f(x + w)} {f(y + r - k)} {f(x + w)} {f(y + r)}"
            f"C{f(x + w)} {f(y + r + k)} {f(x + w - r + k)} {f(y + h)} {f(x + w - r)} {f(y + h)}L{f(x + r)} {f(y + h)}"
            f"C{f(x + r - k)} {f(y + h)} {f(x)} {f(y + r + k)} {f(x)} {f(y + r)}C{f(x)} {f(y + r - k)} {f(x + r - k)} {f(y)} {f(x + r)} {f(y)}Z")


def tape_text():
    """BETA's outline on the tile's 100, along the tape's middle, its letters 6.4 high."""
    glyphs = shape("BETA", 0.04)
    cap = bounds(glyph("B"))[3]
    k = 6.4 / cap
    width = (glyphs[-1][1] + GS[glyphs[-1][0]].width) * k
    mid = (TAPE[0] + TAPE[1]) / 2
    cx, cy = (mid + 100) / 2, (100 - mid) / 2      # the middle of the tape's line between the top and right edges
    c = s_ = 0.70710678
    pen = CubicPen(GS)
    for name, x in glyphs:
        # along the line, then turned 45° clockwise about the tape's middle (y down)
        lx, ly = x * k - width / 2, cap * k / 2
        m = (c * k, s_ * k, s_ * k, -c * k, cx + c * lx - s_ * ly, cy + s_ * lx + c * ly)
        GS[name].draw(TransformPen(pen, m))
    return "".join(pen.d)


TAPE_TEXT = tape_text()


def face_parts(variant):
    """The face's shapes on the tile's 100, each (path, what it is: eye, cheek, tape, words): no tile."""
    out = [(circle_path(x, y, EYE_R), "eye") for x, y in EYES] + [(pill_path(x, y, *CHEEK), "cheek") for x, y in CHEEKS]
    if VARIANTS[variant][3]:
        a, b = TAPE
        out += [(f"M{a} 0L{b} 0L100 {100 - b}L100 {100 - a}Z", "tape"), (TAPE_TEXT, "words")]
    return out


def face_shapes(variant):
    """The face's shapes on the tile's 100, each (path, colour)."""
    _, eye, cheek, _ = VARIANTS[variant]
    colour = {"eye": eye, "cheek": cheek, "tape": ORANGE, "words": "#FFFFFF"}
    return [(d, colour[part]) for d, part in face_parts(variant)]


def moved(d, k, x, y):
    """A path of M, L, C and Z, scaled by k and moved by (x, y)."""
    out, nums = [], re.findall(r"[MLCZ]|-?[\d.]+", d)
    i = 0
    while i < len(nums):
        t = nums[i]
        if t in "MLCZ":
            out.append(t); i += 1; pair = 0
            continue
        v = float(t) * k + (x if pair % 2 == 0 else y)
        out.append(("" if out[-1] in "MLCZ" else " ") + f(v))
        pair += 1; i += 1
    return "".join(out)


def face_svg(variant, x, y, side):
    return "".join(f'<path d="{moved(d, side / 100, x, y)}" fill="{c}"/>' for d, c in face_shapes(variant))


def svg_file(w, h, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{f(w)}" height="{f(h)}" viewBox="0 0 {f(w)} {f(h)}" role="img">'
            f"<title>{title}</title>{body}</svg>")


def mark_file(variant):
    """The face on its rounded tile, a square of 32 (the corner 22.5%, as an app icon's)."""
    return svg_file(32, 32, f'<rect width="32" height="32" rx="7.2" fill="{VARIANTS[variant][0]}"/>' + face_svg(variant, 0, 0, 32), "still.fail")


def tile(side, variant, corner=None):
    bg = VARIANTS[variant][0]
    r = f' rx="{f(corner)}"' if corner else ""
    return f'<rect width="{f(side)}" height="{f(side)}"{r} fill="{bg}"/>' + face_svg(variant, 0, 0, side)


def icon_square(variant):
    """The app's icon as a square the system rounds (iOS, a web app's icons)."""
    return svg_file(1024, 1024, tile(1024, variant), "still.fail")


def icon_mac(variant):
    """The app's icon on macOS's grid: its 824 tile at 100, its corner 185, its shadow (the white face edged faintly)."""
    bg = VARIANTS[variant][0]
    edge = '<rect x="100.5" y="100.5" width="823" height="823" rx="184.5" fill="none" stroke="#000" stroke-opacity=".06"/>' if bg == WHITE_FACE else ""
    return svg_file(1024, 1024,
                     '<defs><filter id="s" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity=".28"/></filter>'
                     '<clipPath id="t"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath></defs>'
                     f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{bg}" filter="url(#s)"/>{edge}'
                     f'<g clip-path="url(#t)">{face_svg(variant, 100, 100, 824)}</g>', "still.fail")


def favicon(variant):
    """The browser's tab: the black face, the white one where the browser is dark."""
    light, dark = variant, variant + "-dark"
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">'
            '<style>.d{display:none}@media (prefers-color-scheme: dark){.l{display:none}.d{display:inline}}</style>'
            f'<g class="l"><rect width="32" height="32" rx="7.2" fill="{VARIANTS[light][0]}"/>{face_svg(light, 0, 0, 32)}</g>'
            f'<g class="d"><rect width="32" height="32" rx="7.2" fill="{VARIANTS[dark][0]}"/>{face_svg(dark, 0, 0, 32)}</g></svg>')


# ---- the wordmarks ----

DOT = glyph(".")
DB = bounds(DOT)
DOT_R = max(DB[2] - DB[0], DB[3] - DB[1]) / 2                       # the period made a round dot of its size


def wordmark(text, ink):
    """`text` in Inter Bold, its period a round orange dot; still.fail's letters 60 high (the same scale for youdid.wtf,
    whose y goes below), from the tallest letter's top to the baseline or the descender's foot."""
    glyphs, shift, after = shape(text, WORD_TRACK), 0.0, False
    for i, (name, x) in enumerate(glyphs):
        if name == DOT:
            shift -= DOT_IN * UPM; after = True
        elif after:
            shift -= DOT_IN * UPM; after = False
        glyphs[i] = (name, x + shift)
    xs, ys = [], []
    for name, x in glyphs:
        b = bounds(name)
        if b:
            xs += [x + b[0], x + b[2]]; ys += [b[1], b[3]]
    pad = 0.02 * UPM
    top, bottom = max(ys), min(ys)
    bottom = bottom if bottom < -60 else 0          # an overshoot under the baseline is not a descender
    k = 60 / (bounds(glyph("l"))[3] + 2 * pad)
    parts = []
    for name, x in glyphs:
        ox, oy = (x - min(xs) + pad) * k, (top + pad) * k
        if name == DOT:
            parts.append(f'<circle cx="{f(ox + (DB[0] + DB[2]) / 2 * k)}" cy="{f(oy - (DB[1] + DB[3]) / 2 * k)}" r="{f(DOT_R * k)}" fill="{ORANGE}"/>')
        else:
            parts.append(f'<path d="{outline(name, k, ox, oy)}" fill="{ink}"/>')
    return svg_file((max(xs) - min(xs) + 2 * pad) * k, (top - bottom + 2 * pad) * k, "".join(parts), text)


# ---- Android (mbui's launcher and marks) and mac-icon.swift ----

def circle_d(cx, cy, r):
    return f"M{f(cx - r)} {f(cy)}A{f(r)} {f(r)} 0 1 0 {f(cx + r)} {f(cy)}A{f(r)} {f(r)} 0 1 0 {f(cx - r)} {f(cy)}Z"


def vector(size, paths, comment):
    body = "".join(f'    <path android:pathData="{d}" android:fillColor="{c}" />\n' for d, c in paths)
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            f"<!-- {comment} -->\n"
            f'<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="{size}dp" android:height="{size}dp" android:viewportWidth="{size}" android:viewportHeight="{size}">\n'
            f"{body}</vector>\n")


# the launcher's 108 viewport, of which a launcher shows the middle 72: the face on that 72 as on every tile
def launcher_shapes(variant, colour=None):
    """The face's shapes on the launcher's 108, in the launcher's named colours (or one `colour`)."""
    names = {"eye": "@color/launcher_ink", "cheek": "@color/launcher_cheek", "tape": "@color/launcher_tape", "words": "#FFFFFF"}
    return [(moved(d, 0.72, 18, 18), colour or names[part]) for d, part in face_parts(variant)]


def colors(comment, pairs):
    body = "".join(f'    <color name="{k}">{v}</color>\n' for k, v in pairs)
    return f'<?xml version="1.0" encoding="utf-8"?>\n<!-- {comment} -->\n<resources>\n{body}</resources>\n'


def put(path, text):
    out = os.path.join(REPO, path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as fh:
        fh.write(text)


def make():
    put("web/public/mark.svg", mark_file("stable"))
    put("web/public/mark-dark.svg", mark_file("stable-dark"))
    for name, text, ink in [("wordmark", "still.fail", INK), ("wordmark-dark", "still.fail", INK_DARK),
                            ("wordmark-beta", "youdid.wtf", INK), ("wordmark-beta-dark", "youdid.wtf", INK_DARK)]:
        put(f"web/public/{name}.svg", wordmark(text, ink))
    put("web/public/favicon.svg", favicon("stable"))
    put("web/public/favicon-beta.svg", favicon("beta"))
    for v in VARIANTS:
        put(f"design/brand/icon-{v}.svg", icon_square(v))
        put(f"design/brand/icon-mac-{v}.svg", icon_mac(v))
    # the illustrations, and mbui's VectorDrawables of them (illus.py)
    illus.write(REPO)
    R = "apps/mbui/android/app/src"
    M = f"{R}/main/res"
    # one face for every app, its colours each app's (values/launcher.xml); youdid.wtf's its own, with the tape
    put(f"{M}/drawable/launcher_face.xml", vector(108, launcher_shapes("stable"),
        "The launcher's face (design/brand/make.py): its eyes in launcher_ink, its cheeks in launcher_cheek, on launcher_bg, in the 66dp safe circle."))
    put(f"{R}/beta/res/drawable/launcher_face.xml", vector(108, launcher_shapes("beta"),
        "youdid.wtf's launcher face (design/brand/make.py): still.fail's, the orange tape (launcher_tape) across its top right corner, BETA on it."))
    put(f"{M}/drawable/launcher_face_mono.xml", vector(108, launcher_shapes("stable", "#FFFFFF"),
        "The launcher's face in one colour (themed icons)."))
    for name, v in [("stillfail_mark", "stable"), ("stillfail_mark_dark", "stable-dark")]:
        bg = VARIANTS[v][0]
        put(f"{M}/drawable/{name}.xml", vector(32, [(rounded_square(32, 7.2), bg)]
                                           + [(moved(d, 0.32, 0, 0), c) for d, c in face_shapes(v)],
            f"still.fail's mark (web/public/{name.replace('stillfail_', '').replace('_', '-')}.svg; design/brand/make.py)."))
    for v, where, night, comment in [
        ("stable", "main", "stable-dark", "Every app's but the debug build's: still.fail's black face (design/brand/icon-stable.svg); values-night's the white."),
        ("debug", "debug", "debug", "The debug build (dev.mbui.demo) apart from the others on a launcher: grey."),
        ("stable", "stable", "stable-dark", "The released app's (fail.still.android; design/brand/icon-stable.svg): the black face; values-night's the white."),
        ("beta", "beta", "beta-dark", "The beta app's (fail.still.android.beta; design/brand/icon-beta.svg): still.fail's face under the orange tape; values-night's the white."),
    ]:
        for v2, qual in [(v, "values")] + ([(night, "values-night")] if night else []):
            bg, eye, cheek, tape = VARIANTS[v2]
            pairs = [("launcher_bg", bg), ("launcher_ink", eye), ("launcher_cheek", cheek)] + ([("launcher_tape", ORANGE)] if tape else [])
            put(f"{R}/{where}/res/{qual}/launcher.xml", colors(comment, pairs))
    # mac-icon.swift draws the same face: its shapes on the tile's 100, between the markers
    swift = os.path.join(REPO, "apps/mbui/scripts/mac-icon.swift")
    text = open(swift).read()
    eyes = [d for d, _ in face_shapes("stable")[:2]]
    cheeks = [d for d, _ in face_shapes("stable")[2:4]]
    tape = [d for d, _ in face_shapes("beta")[4:]]
    q = lambda ds: "[" + ", ".join(f'"{d}"' for d in ds) + "]"
    block = f"let eyePaths = {q(eyes)}\nlet cheekPaths = {q(cheeks)}\nlet tapePath = \"{tape[0]}\"\nlet tapeWords = \"{tape[1]}\"\n"
    text = re.sub(r"(// brand: made by design/brand/make\.py\n).*?(// brand end\n)", lambda m: m.group(1) + block + m.group(2), text, flags=re.S)
    put(os.path.relpath(swift, REPO), text)


def rounded_square(side, r):
    """A square `side` with corners of `r`, as M L C Z."""
    k = K * r
    s = side
    return (f"M{f(r)} 0L{f(s - r)} 0C{f(s - r + k)} 0 {f(s)} {f(r - k)} {f(s)} {f(r)}L{f(s)} {f(s - r)}"
            f"C{f(s)} {f(s - r + k)} {f(s - r + k)} {f(s)} {f(s - r)} {f(s)}L{f(r)} {f(s)}C{f(r - k)} {f(s)} 0 {f(s - r + k)} 0 {f(s - r)}"
            f"L0 {f(r)}C0 {f(r - k)} {f(r - k)} 0 {f(r)} 0Z")


# ---- rasters ----

CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")


def shoot(path, w, h, body):
    """`body` drawn `w` × `h` into `path` by headless Chrome, transparent where nothing is drawn."""
    tmp = os.path.join(tempfile.gettempdir(), f"stillfail-brand-{os.getpid()}")
    os.makedirs(tmp, exist_ok=True)
    font = inter()
    html = os.path.join(tmp, "page.html")
    with open(html, "w") as fh:
        fh.write(f"<html><head><style>@font-face{{font-family:InterV;src:url(file://{font})}}html,body{{margin:0;background:transparent}}</style></head><body>{body}</body></html>")
    out = os.path.join(REPO, path)
    if os.path.exists(out):
        os.remove(out)
    p = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", "--allow-file-access-from-files", f"--user-data-dir={tmp}/chrome",
                          "--hide-scrollbars", "--default-background-color=00000000", f"--window-size={w},{h}", "--force-device-scale-factor=1",
                          f"--screenshot={out}", "file://" + html], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(200):
        time.sleep(0.1)
        if os.path.exists(out) and os.path.getsize(out) > 0:
            time.sleep(0.3)
            break
    p.send_signal(signal.SIGTERM)
    p.wait()
    if not os.path.exists(out):
        sys.exit(f"make.py: {path} was not drawn")


def svg(w, h, inner):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" style="display:block">{inner}</svg>'


def square(variant, side, corner=0):
    """The app's tile `side` square, rounded `corner` (none: the system rounds it); the paper's edged faintly."""
    k = 1024 / side
    edge = (f'<rect x=".5" y=".5" width="{side - 1}" height="{side - 1}" rx="{max(corner - .5, 0)}" fill="none" stroke="#000" stroke-opacity=".08"/>'
            if VARIANTS[variant][0] == WHITE_FACE and corner else "")
    return svg(side, side, f'<g transform="scale({1 / k})">' + tile(1024, variant, corner * k if corner else None) + "</g>" + edge)


def rasters():
    for v, suf in [("stable", ""), ("beta", "-beta")]:
        shoot(f"web/public/favicon{suf}-32.png", 32, 32, favicon(v).replace("<svg ", '<svg style="display:block" '))
        shoot(f"web/public/apple-touch-icon{suf}.png", 180, 180, square(v, 180))
        for s in (192, 512):
            shoot(f"web/public/icon{suf}-{s}.png" if suf else f"web/public/icon-{s}.png", s, s, square(v, s))
    # still.fail Helper's (the station's macOS app: scripts/native.ts makes its .icns of it), on macOS's grid
    shoot("station/native/helper/icon.png", 1024, 1024, icon_mac("stable").replace("<svg ", '<svg style="display:block" '))
    for s in (16, 32, 48, 128):
        shoot(f"apps/extension/icons/{s}.png", s, s, square("stable", s, corner=round(s * 0.22)))
    # the link previews' card: the name, the headline (its full stop the dot), its line
    k = 34 / 63.13
    name = wordmark("still.fail", INK)
    w, h = (float(v) for v in re.search(r'width="([\d.]+)" height="([\d.]+)"', name).groups())
    name = name.replace(f'width="{f(w)}" height="{f(h)}"', f'width="{f(w * k)}" height="{f(h * k)}" style="display:block"', 1)
    for lang, line in [("", "在任何一台上，用所有设备"), ("-en", "All in one, all is one.")]:
        shoot(f"web/public/og-image{lang}.png", 1200, 630,
              '<div style="width:1200px;height:630px;background:#FAFAF9;position:relative;font-family:InterV,-apple-system,\'PingFang SC\',sans-serif">'
              f'<div style="position:absolute;left:82px;top:82px">{name}</div>'
              f'<div style="position:absolute;left:78px;top:222px;font-size:92px;font-weight:700;letter-spacing:-.02em;color:#09090B;line-height:1.1">One devices<span style="color:{ORANGE}">.</span></div>'
              f'<div style="position:absolute;left:82px;top:476px;font-size:28px;color:#52525B">{line}</div></div>')


if __name__ == "__main__":
    make()
    if sys.argv[1:] == ["png"]:
        rasters()

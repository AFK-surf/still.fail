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
sys.path.insert(0, os.path.join(REPO, "apps/android/scripts"))
import svg2vd  # noqa: E402  (the SVG → VectorDrawable converter the Android drawables were made with)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import illus  # noqa: E402

ORANGE = "#E5704A"
INK, INK_DARK = "#18181B", "#F4F4F5"
PAPER, NIGHT = "#FAFAF9", "#111114"
# Each app's tile, its s and its dot: still.fail, youdid.wtf, still.fail mbui (its violet, the dot as yellow as the
# moon it had), the debug build.
VARIANTS = {
    "stable": (PAPER, INK, ORANGE),
    "beta": (NIGHT, "#FAFAFA", ORANGE),
    "mbui": ("#5B4FD6", "#FFFFFF", "#FFD66B"),
    "debug": ("#5F646B", "#FFFFFF", "#C9CDD2"),
}
ICON_H = 0.44          # the s's height, of the tile's side
NUDGE = 0.018          # the mark's ink box moved right by this much of its width: the dot is light, the s carries it
TRACK = -0.03          # the mark's tracking (em)
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


# ---- the mark: s. ----

S, DOT = glyph("s"), glyph(".")
SB, DB = bounds(S), bounds(DOT)
DOT_R = max(DB[2] - DB[0], DB[3] - DB[1]) / 2                       # the period made a round dot of its size
DOT_C = (GS[S].width + TRACK * UPM + (DB[0] + DB[2]) / 2, (DB[1] + DB[3]) / 2)
INK_BOX = (SB[0], min(SB[1], DOT_C[1] - DOT_R), DOT_C[0] + DOT_R, SB[3])
MARK_W_PER_H = (INK_BOX[2] - INK_BOX[0]) / (INK_BOX[3] - INK_BOX[1])


def mark_parts(cx, cy, h, nudge=0.0):
    """The mark's s (a path) and dot (cx, cy, r), its ink `h` tall, its ink box's middle at (cx, cy) (+ `nudge` of its
    width to the right)."""
    k = h / (INK_BOX[3] - INK_BOX[1])
    w = (INK_BOX[2] - INK_BOX[0]) * k
    x0 = cx - w / 2 + nudge * w - INK_BOX[0] * k
    y0 = cy + h / 2 + INK_BOX[1] * k
    return outline(S, k, x0, y0), (x0 + DOT_C[0] * k, y0 - DOT_C[1] * k, DOT_R * k)


def mark_svg(cx, cy, h, ink, dot=ORANGE, nudge=0.0):
    s, (dx, dy, r) = mark_parts(cx, cy, h, nudge)
    return f'<path d="{s}" fill="{ink}"/><circle cx="{f(dx)}" cy="{f(dy)}" r="{f(r)}" fill="{dot}"/>'


def svg_file(w, h, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{f(w)}" height="{f(h)}" viewBox="0 0 {f(w)} {f(h)}" role="img">'
            f"<title>{title}</title>{body}</svg>")


def mark_file(ink):
    """A square of 32, the mark nearly as wide (30)."""
    return svg_file(32, 32, mark_svg(16, 16, 30 / MARK_W_PER_H, ink), "still.fail")


def tile(side, variant, corner=None):
    bg, ink, dot = VARIANTS[variant]
    r = f' rx="{f(corner)}"' if corner else ""
    return f'<rect width="{f(side)}" height="{f(side)}"{r} fill="{bg}"/>' + mark_svg(side / 2, side / 2, ICON_H * side, ink, dot, NUDGE)


def icon_square(variant):
    """The app's icon as a square the system rounds (iOS, a web app's icons)."""
    return svg_file(1024, 1024, tile(1024, variant), "still.fail")


def icon_mac(variant):
    """The app's icon on macOS's grid: its 824 tile at 100, its corner 185, its shadow (the paper's edged faintly)."""
    bg, ink, dot = VARIANTS[variant]
    edge = '<rect x="100.5" y="100.5" width="823" height="823" rx="184.5" fill="none" stroke="#000" stroke-opacity=".06"/>' if variant == "stable" else ""
    return svg_file(1024, 1024,
                     '<defs><filter id="s" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity=".28"/></filter></defs>'
                     f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{bg}" filter="url(#s)"/>{edge}'
                     + mark_svg(512, 512, ICON_H * 824, ink, dot, NUDGE), "still.fail")


def favicon(variant):
    bg, ink, dot = VARIANTS[variant]
    edge = '<rect x=".25" y=".25" width="31.5" height="31.5" rx="7" fill="none" stroke="#000" stroke-opacity=".12" stroke-width=".5"/>' if variant == "stable" else ""
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">'
            f'<rect width="32" height="32" rx="7" fill="{bg}"/>{edge}' + mark_svg(16, 16, 16, ink, dot, NUDGE) + "</svg>")


# ---- the wordmarks ----

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


# the launcher's 108 viewport, of which a launcher shows the middle 72: the s 44% of that, as on every tile
LAUNCH_S, LAUNCH_DOT = mark_parts(54, 54, ICON_H * 72, NUDGE)


def colors(comment, pairs):
    body = "".join(f'    <color name="{k}">{v}</color>\n' for k, v in pairs)
    return f'<?xml version="1.0" encoding="utf-8"?>\n<!-- {comment} -->\n<resources>\n{body}</resources>\n'


def put(path, text):
    out = os.path.join(REPO, path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as fh:
        fh.write(text)


def make():
    put("web/public/mark.svg", mark_file(INK))
    put("web/public/mark-dark.svg", mark_file(INK_DARK))
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
    M = "apps/mbui/android/app/src/main/res"
    dot = circle_d(*LAUNCH_DOT)
    put(f"{M}/drawable/launcher_face.xml", vector(108, [(LAUNCH_S, "@color/launcher_ink"), (dot, "@color/launcher_dot")],
        "The launcher's mark (design/brand/make.py): s. on launcher_bg, in the 66dp safe circle; the s in launcher_ink, its dot in launcher_dot."))
    put(f"{M}/drawable/launcher_face_mono.xml", vector(108, [(LAUNCH_S, "#FFFFFF"), (dot, "#FFFFFF")],
        "The launcher's mark in one colour (themed icons)."))
    for name, ink in [("stillfail_mark", INK), ("stillfail_mark_dark", INK_DARK)]:
        s, (dx, dy, r) = mark_parts(16, 16, 30 / MARK_W_PER_H)
        put(f"{M}/drawable/{name}.xml", vector(32, [(s, ink), (circle_d(dx, dy, r), ORANGE)],
            f"still.fail's mark (web/public/{name.replace('stillfail_', '').replace('_', '-')}.svg; design/brand/make.py)."))
    for v, where, comment in [
        ("mbui", "main", "still.fail mbui's (release, fail.still.mbui; design/brand/icon-mbui.svg): violet, the s white, the dot yellow."),
        ("debug", "debug", "The debug build (dev.mbui.demo) apart from the others on a launcher: grey."),
        ("stable", "stable", "The released app's (fail.still.android; design/brand/icon-stable.svg): the paper, the s in ink, the dot orange."),
        ("beta", "beta", "The beta app's (fail.still.android.beta; design/brand/icon-beta.svg): night, the s white, the dot orange."),
    ]:
        bg, ink, d = VARIANTS[v]
        pairs = [("launcher_bg", bg), ("launcher_dot", d)] if v == "debug" else [("launcher_bg", bg), ("launcher_ink", ink), ("launcher_dot", d)]
        put(f"apps/mbui/android/app/src/{where}/res/values/launcher.xml", colors(comment, pairs))
    # mac-icon.swift draws the same launcher mark: its s and dot, between the markers
    swift = os.path.join(REPO, "apps/mbui/scripts/mac-icon.swift")
    text = open(swift).read()
    block = (f'let sPath = "{LAUNCH_S}"\n'
             f"let dot = (x: {f(LAUNCH_DOT[0])} as CGFloat, y: {f(LAUNCH_DOT[1])} as CGFloat, r: {f(LAUNCH_DOT[2])} as CGFloat)\n")
    text = re.sub(r"(// brand: made by design/brand/make\.py\n).*?(// brand end\n)", lambda m: m.group(1) + block + m.group(2), text, flags=re.S)
    put(os.path.relpath(swift, REPO), text)


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
            if variant == "stable" and corner else "")
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

"""still.fail's illustrations (web/public/illus-*.svg), drawn as the site draws its idea: devices, and the wires that
join them. One line weight for all of it; the devices outlined in ink, what is on them in the lighter line; orange
only for what is joined (a live wire, the dots running on it) and a station's light. What is not joined yet is a
dashed grey wire, what is not there yet a dashed outline. No ground, no backdrop; a station has still.fail's face (its
eyes and cheeks, the app icon's), its eyes shut when it is asleep.

make.py writes them and mbui's VectorDrawables of them, as `python3 design/brand/illus.py` alone does.
Dashes are drawn as their own strokes, not stroke-dasharray, which VectorDrawables do not have.
"""
import json
import math
import os
import sys
import xml.etree.ElementTree as ET

ORANGE = "#E5704A"
SW = 1.5  # every stroke's width
STYLE = ("<style>:root{--ink:#24272B;--line:#8A8C90;--panel:#FFFFFF;--sleep:#ACAAA4;}"
         "@media(prefers-color-scheme:dark){:root{--ink:#E4E4E7;--line:#8E9096;--panel:#26282C;--sleep:#6F7076;}}</style>")


def f(x):
    s = f"{x:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def stroke(d, colour="var(--ink)", fill="none"):
    return (f'<path d="{d}" fill="{fill}" stroke="{colour}" stroke-width="{SW}" '
            'stroke-linecap="round" stroke-linejoin="round"/>')


def box(x, y, w, h, r, colour="var(--ink)", fill="var(--panel)"):
    return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(r)}" fill="{fill}" stroke="{colour}" stroke-width="{SW}"/>'


def dot(x, y, r, colour):
    return f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="{colour}"/>'


# ---- dashes: a polyline cut into strokes 4 long, 4 apart ----

def dashed(points, on=4.0, off=4.0, colour="var(--line)"):
    out, run, left, drawing = [], [points[0]], on, True
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        at = 0.0
        while seg - at > left:
            at += left
            p = (x0 + (x1 - x0) * at / seg, y0 + (y1 - y0) * at / seg)
            if drawing:
                out.append(run + [p])
            run, drawing = [p], not drawing
            left = off if not drawing else on
        left -= seg - at
        run.append((x1, y1))
    if drawing and len(run) > 1:
        out.append(run)
    d = "".join("M" + "L".join(f"{f(x)} {f(y)}" for x, y in r) for r in out)
    return stroke(d, colour)


def cubic(p0, p1, p2, p3, n=48):
    def at(t):
        u = 1 - t
        return tuple(u**3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t**3 * e for a, b, c, e in zip(p0, p1, p2, p3))
    return [at(i / n) for i in range(n + 1)]


def rounded(x, y, w, h, r, n=8):
    """A rounded rectangle's outline as points, clockwise from its top left corner's end."""
    pts = []
    for cx, cy, a0 in [(x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)]:
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts + [pts[0]]


# ---- the devices ----

STATION = (60, 36)
LAPTOP = (84, 54)   # its screen; the base is wider and under it
PHONE = (32, 60)


BLUSH = "#F6BC9F"


def station(x, y, asleep=False):
    """A station: a machine, a rounded box with still.fail's face (its eyes shut asleep) and its light in the corner
    (orange; grey asleep)."""
    w, h = STATION
    light = "var(--sleep)" if asleep else ORANGE
    ex, ey = (x + w / 2 - 7, x + w / 2 + 7), y + h / 2 - 2
    if asleep:
        eyes = stroke("".join(f"M{f(e - 2.6)} {f(ey - .6)}Q{f(e)} {f(ey + 2.2)} {f(e + 2.6)} {f(ey - .6)}" for e in ex))
    else:
        eyes = "".join(dot(e, ey, 2.4, "var(--ink)") for e in ex)
    cheeks = "".join(f'<rect x="{f(e - 6.4 + (0 if e < x + w / 2 else 7.6))}" y="{f(ey + 5)}" width="5" height="2.6" rx="1.3" fill="{BLUSH}"/>' for e in ex)
    return (f'<g data-station="{"asleep" if asleep else "awake"}">' + box(x, y, w, h, 8)
            + eyes + cheeks + dot(x + w - 8, y + 8, 2.2, light) + "</g>")


def station_missing(x, y):
    """Where a station would be: its outline dashed, a plus in it."""
    w, h = STATION
    cx, cy = x + w / 2, y + h / 2
    return dashed(rounded(x, y, w, h, 8)) + stroke(f"M{f(cx - 6)} {f(cy)}H{f(cx + 6)}M{f(cx)} {f(cy - 6)}V{f(cy + 6)}", "var(--line)")


def laptop(x, y):
    """A laptop: its screen at x, y with a chat on it, and its base."""
    w, h = LAPTOP
    return (box(x, y, w, h, 6)
            + stroke(f"M{f(x + 12)} {f(y + 15)}H{f(x + 44)}M{f(x + 12)} {f(y + 26)}H{f(x + 62)}", "var(--line)")
            + stroke(f"M{f(x + 30)} {f(y + 39)}H{f(x + w - 12)}", "var(--ink)")
            + box(x - 9, y + h, w + 18, 6, 3))


def phone(x, y):
    """A phone: its glass, the island at its top, a chat on it."""
    w, h = PHONE
    return (box(x, y, w, h, 7)
            + stroke(f"M{f(x + 12)} {f(y + 7)}H{f(x + w - 12)}", "var(--ink)")
            + stroke(f"M{f(x + 7)} {f(y + 22)}H{f(x + 20)}M{f(x + 7)} {f(y + 31)}H{f(x + 24)}", "var(--line)")
            + stroke(f"M{f(x + 13)} {f(y + 42)}H{f(x + w - 7)}", "var(--ink)"))


def card(x, y):
    """An account: a card with its face and its name."""
    w, h = 72, 46
    return (box(x, y, w, h, 6)
            + f'<circle cx="{f(x + 18)}" cy="{f(y + 19)}" r="6" fill="none" stroke="var(--line)" stroke-width="{SW}"/>'
            + stroke(f"M{f(x + 10)} {f(y + 36)}a8 6 0 0 1 16 0", "var(--line)")
            + stroke(f"M{f(x + 34)} {f(y + 17)}H{f(x + 60)}", "var(--ink)")
            + stroke(f"M{f(x + 34)} {f(y + 28)}H{f(x + 52)}", "var(--line)"))


def bubble(x, y):
    """A team chat: a speech bubble, its lines."""
    w, h = 70, 44
    d = (f"M{f(x + 7)} {f(y)}H{f(x + w - 7)}a7 7 0 0 1 7 7V{f(y + h - 7)}a7 7 0 0 1-7 7H{f(x + 24)}l-10 9v-9H{f(x + 7)}"
         f"a7 7 0 0 1-7-7V{f(y + 7)}a7 7 0 0 1 7-7Z")
    return (stroke(d, "var(--ink)", "var(--panel)")
            + stroke(f"M{f(x + 12)} {f(y + 14)}H{f(x + 56)}M{f(x + 12)} {f(y + 24)}H{f(x + 44)}", "var(--line)")
            + stroke(f"M{f(x + 12)} {f(y + 34)}H{f(x + 30)}", "var(--ink)"))


# ---- the wires ----

def wire(p0, p1, p2, p3, live=True, dots=(0.5,)):
    """A wire from p0 to p3 (a cubic): orange with the dots running on it when live, dashed grey when not joined."""
    if not live:
        return dashed(cubic(p0, p1, p2, p3))
    pts = cubic(p0, p1, p2, p3, 200)
    d = f"M{f(p0[0])} {f(p0[1])}C{f(p1[0])} {f(p1[1])} {f(p2[0])} {f(p2[1])} {f(p3[0])} {f(p3[1])}"
    return (stroke(d, ORANGE) + "".join(dot(*pts[round(t * 200)], 3.5, ORANGE) for t in dots))


def unplugged(x0, y0, x1, y1):
    """A wire pulled apart (grey): from x0, y0 to its plug, a gap, the socket on the wire from x1, y1."""
    mid = (x0 + x1) / 2
    px = mid - 8   # the plug's prongs end here
    sx = mid + 8   # the socket's face
    end = px - 18
    return (stroke(f"M{f(x0)} {f(y0)}C{f((x0 + end) / 2)} {f(y0)} {f((x0 + end) / 2)} {f(y1)} {f(end)} {f(y1)}", "var(--line)")
            + box(px - 18, y1 - 6, 12, 12, 3, "var(--line)")
            + stroke(f"M{f(px - 6)} {f(y1 - 3)}H{f(px)}M{f(px - 6)} {f(y1 + 3)}H{f(px)}", "var(--line)")
            + box(sx, y1 - 7, 10, 14, 3, "var(--line)")
            + stroke(f"M{f(sx + 10)} {f(y1)}H{f(x1)}", "var(--line)"))


def svg(w, h, title, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img">'
            f"<title>{title}</title>{STYLE}{body}</svg>\n")


def scenes():
    lw, lh = LAPTOP
    sw, sh = STATION
    # a laptop and what it is joined to, each standing on the same line (the base's foot, the box's)
    lx, ly = 44, 50            # the laptop's screen; its base ends at ly + lh + 6 = 110
    sx, sy = 216, 110 - sh     # the station on the same line
    a, b = (lx + lw, ly + 28), (sx, sy + sh / 2)
    joined = wire(a, (a[0] + 40, a[1]), (b[0] - 40, b[1]), b)
    yield "new-chat", svg(320, 160, "A laptop joined to a station", laptop(lx, ly) + joined + station(sx, sy))
    yield "no-station", svg(320, 160, "A laptop with no station to join yet", laptop(lx, ly)
                            + wire(a, (a[0] + 40, a[1]), (b[0] - 40, b[1]), b, live=False) + station_missing(sx, sy))
    yield "station-offline", svg(320, 160, "A station asleep, its wire pulled out", laptop(lx, ly)
                                 + unplugged(a[0], a[1], b[0], b[1]) + station(sx, sy, asleep=True))
    # a station and what it waits for: an account, a team chat
    sx2, sy2 = 54, 62
    s = (sx2 + sw, sy2 + sh / 2)
    yield "no-profile", svg(320, 160, "A station waiting for an account", station(sx2, sy2)
                            + wire(s, (s[0] + 40, s[1]), (194 - 40, 80), (194, 80), live=False) + card(194, 57))
    yield "no-connect", svg(320, 160, "A station waiting for a team chat", station(sx2, sy2)
                            + wire(s, (s[0] + 40, s[1]), (194 - 40, 80), (194, 80), live=False) + bubble(194, 58))
    # signing in: a phone, a laptop and a station, all joined
    px, py = 46, 96
    lx, ly = 138, 34
    sx, sy = 254, 118
    p_top, p_low = (px + PHONE[0], py + 16), (px + PHONE[0], py + 46)
    l_left, l_right = (lx, ly + 27), (lx + lw, ly + 27)
    s_top, s_left = (sx + sw / 2, sy), (sx, sy + sh / 2)
    yield "sign-in", svg(360, 200, "A phone, a laptop and a station, joined",
                         wire(p_top, (p_top[0] + 30, p_top[1]), (l_left[0] - 30, l_left[1]), l_left)
                         + wire(l_right, (l_right[0] + 40, l_right[1]), (s_top[0], s_top[1] - 40), s_top)
                         + wire(p_low, (p_low[0] + 60, p_low[1]), (s_left[0] - 60, s_left[1]), s_left)
                         + phone(px, py) + laptop(lx, ly) + station(sx, sy))


# the ones mbui draws, as its VectorDrawables
VD = {"new-chat": "illus_new_chat", "no-station": "illus_no_station", "no-profile": "illus_no_profile",
      "sign-in": "illus_sign_in", "station-offline": "illus_station_offline"}


def write(repo):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import svg2vd
    for name, text in scenes():
        src = os.path.join(repo, "web/public", f"illus-{name}.svg")
        with open(src, "w") as fh:
            fh.write(text)
        if name == "sign-in":
            # (still.fail cloud's sign-in pages draw it in place: their pages fetch nothing, page.ts)
            with open(os.path.join(repo, "cloud/src/illus.ts"), "w") as fh:
                fh.write("// web/public/illus-sign-in.svg, for still.fail cloud's sign-in pages (page.ts) to draw in place: written by\n"
                         "// design/brand/illus.py, not by hand.\n"
                         f"export const SIGN_IN_ILLUSTRATION = {json.dumps(text)};\n")
        if name not in VD:
            continue
        light, dark = svg2vd.css_vars(ET.parse(src).getroot())
        for suffix, values in [("", light), ("_dark", {**light, **dark})]:
            xml = svg2vd.convert(src, values).replace(
                f"<!-- Generated by scripts/svg2vd.py from design/mobile/assets/illus-{name}.svg. -->",
                f"<!-- web/public/illus-{name}.svg as a VectorDrawable (design/brand/illus.py, svg2vd's convert{', its dark colours' if suffix else ''}). -->")
            with open(os.path.join(repo, "apps/mbui/android/app/src/main/res/drawable", f"{VD[name]}{suffix}.xml"), "w") as fh:
                fh.write(xml)


if __name__ == "__main__":
    write(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

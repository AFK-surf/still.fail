#!/usr/bin/env python3
"""still.fail's icons (ember design/icons, 24x24 strokes) flattened for mbui:
src/sf/icon_data.mbt holds, per icon, its strokes and fills as polylines in
the 24 grid, which src/sf/icons.mbt draws at any size.

  python3 scripts/icons.py <ember>/design/icons > src/sf/icon_data.mbt

Each icon is one Array[Double]: a run of parts, each
  kind (0 open stroke, 1 closed stroke, 2 fill), width, n, x0, y0, … x(n-1), y(n-1)
with a fill's subpaths as consecutive parts of kind 2 whose first carries
the count of subpaths in `width` (a fill has no stroke width)."""
import math, os, re, sys
import xml.etree.ElementTree as ET

def num_tokens(d):
    return re.findall(r'[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?', d)

def arc_points(x1, y1, rx, ry, phi, fa, fs, x2, y2):
    # SVG arc, endpoint to centre parametrisation
    if rx == 0 or ry == 0:
        return [(x2, y2)]
    cp, sp = math.cos(math.radians(phi)), math.sin(math.radians(phi))
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    rx, ry = abs(rx), abs(ry)
    lam = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if lam > 1:
        rx *= math.sqrt(lam); ry *= math.sqrt(lam)
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    co = math.sqrt(max(0, num / den)) if den else 0
    if fa == fs:
        co = -co
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2
    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a
    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not fs and dt > 0:
        dt -= 2 * math.pi
    elif fs and dt < 0:
        dt += 2 * math.pi
    n = max(2, int(abs(dt) / math.radians(8)) + 1)
    out = []
    for i in range(1, n + 1):
        t = t1 + dt * i / n
        x = rx * math.cos(t); y = ry * math.sin(t)
        out.append((cp * x - sp * y + cx, sp * x + cp * y + cy))
    return out

def path_subpaths(d):
    """[(points, closed)]"""
    toks = num_tokens(d)
    i = 0
    subs = []
    cur = None
    x = y = 0.0
    sx = sy = 0.0
    cmd = None
    lastc = None  # last control point for S/T
    def nxt():
        nonlocal i
        v = float(toks[i]); i += 1
        return v
    while i < len(toks):
        t = toks[i]
        if re.match(r'[A-Za-z]', t):
            cmd = t; i += 1
            if cmd in 'Zz':
                if cur:
                    subs.append((cur, True)); cur = None
                x, y = sx, sy
                continue
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = (x, y) if rel else (0.0, 0.0)
        if c == 'M':
            if cur:
                subs.append((cur, False))
            x, y = nxt() + ox, nxt() + oy
            sx, sy = x, y
            cur = [(x, y)]
            cmd = 'l' if rel else 'L'
        elif c == 'L':
            x, y = nxt() + ox, nxt() + oy
            cur.append((x, y))
        elif c == 'H':
            x = nxt() + (x if rel else 0.0)
            cur.append((x, y))
        elif c == 'V':
            y = nxt() + (y if rel else 0.0)
            cur.append((x, y))
        elif c == 'Q':
            qx, qy = nxt() + ox, nxt() + oy
            ex, ey = nxt() + ox, nxt() + oy
            for k in range(1, 9):
                tt = k / 8
                mt = 1 - tt
                cur.append((mt * mt * x + 2 * mt * tt * qx + tt * tt * ex, mt * mt * y + 2 * mt * tt * qy + tt * tt * ey))
            x, y = ex, ey
        elif c == 'C':
            c1x, c1y = nxt() + ox, nxt() + oy
            c2x, c2y = nxt() + ox, nxt() + oy
            ex, ey = nxt() + ox, nxt() + oy
            for k in range(1, 13):
                tt = k / 12
                mt = 1 - tt
                cur.append((mt ** 3 * x + 3 * mt * mt * tt * c1x + 3 * mt * tt * tt * c2x + tt ** 3 * ex,
                            mt ** 3 * y + 3 * mt * mt * tt * c1y + 3 * mt * tt * tt * c2y + tt ** 3 * ey))
            x, y = ex, ey
        elif c == 'A':
            rx, ry, phi = nxt(), nxt(), nxt()
            fa, fs = int(nxt()), int(nxt())
            ex, ey = nxt() + ox, nxt() + oy
            cur.extend(arc_points(x, y, rx, ry, phi, fa, fs, ex, ey))
            x, y = ex, ey
        else:
            raise SystemExit('path command %s not handled' % cmd)
    if cur:
        subs.append((cur, False))
    return subs

def circle(cx, cy, r):
    n = max(12, int(r * 10))
    return [(cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n)) for k in range(n)]

def rrect(x, y, w, h, rx):
    rx = min(rx, w / 2, h / 2)
    pts = []
    for (cx, cy, a0) in ((x + w - rx, y + rx, -90), (x + w - rx, y + h - rx, 0), (x + rx, y + h - rx, 90), (x + rx, y + rx, 180)):
        for k in range(7):
            a = math.radians(a0 + 15 * k)
            pts.append((cx + rx * math.cos(a), cy + rx * math.sin(a)))
    return pts

def icon_parts(path):
    root = ET.parse(path).getroot()
    ns = '{http://www.w3.org/2000/svg}'
    base_fill = root.get('fill', 'black')
    base_stroke = root.get('stroke', 'none')
    base_w = float(root.get('stroke-width', '1'))
    parts = []
    for el in root.iter():
        tag = el.tag.replace(ns, '')
        if tag == 'svg':
            continue
        fill = el.get('fill', base_fill)
        stroke = el.get('stroke', base_stroke)
        sw = float(el.get('stroke-width', base_w))
        if tag == 'path':
            subs = path_subpaths(el.get('d'))
        elif tag == 'circle':
            subs = [(circle(float(el.get('cx', 0)), float(el.get('cy', 0)), float(el.get('r'))), True)]
        elif tag == 'rect':
            rx = float(el.get('rx', el.get('ry', 0)))
            subs = [(rrect(float(el.get('x', 0)), float(el.get('y', 0)), float(el.get('width')), float(el.get('height')), rx), True)]
        else:
            continue
        if fill != 'none':
            for k, (pts, _) in enumerate(subs):
                parts.append((2, len(subs) if k == 0 else 0, pts))
        if stroke != 'none':
            for pts, closed in subs:
                parts.append((1 if closed else 0, sw, pts))
    return parts

def fmt(v):
    s = ('%.3f' % v).rstrip('0').rstrip('.')
    return s if s not in ('-0', '') else '0'

def main():
    d = sys.argv[1]
    names = sorted(f[:-4] for f in os.listdir(d) if f.endswith('.svg'))
    print('// Generated by scripts/icons.py from ember design/icons: do not edit.')
    print()
    print('///|')
    print('let icon_data : Map[String, Array[Double]] = {')
    for n in names:
        out = []
        for kind, w, pts in icon_parts(os.path.join(d, n + '.svg')):
            out += [kind, w, len(pts)]
            for (x, y) in pts:
                out += [x, y]
        print('  "%s": [%s],' % (n, ', '.join(fmt(float(v)) for v in out)))
    print('}')

main()

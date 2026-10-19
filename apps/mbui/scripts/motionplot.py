#!/usr/bin/env python3
"""How mbui's motion went, frame by frame, against how still.fail's Android app (Compose) moves the same thing.

  motionplot.py LOG [SVG]

LOG: a run with MBUI_MOTION_LOG=1 (scripts/record.sh writes out/rec/<name>/log.txt; on Android adb logcat -s mbui:I):
lines `MOTION <ms> <key> name=value …`. Each motion (a key's run of frames) is matched to the spec the Android app
gives that motion (docs/stillfail-motion.md; SPECS below, by its key), and its values compared with Compose's, worked
out here from Compose's formulas apart from the MoonBit (CubicBezierEasing, tween(), SpringSimulation with the
duration of SpringEstimation; src/motion/motion_test.mbt checks the MoonBit against Compose's own classes), from the frame
the motion was asked in, with Compose's frame from being asked to moving. Prints, per motion, its frames and the
largest difference as a share of its way; SVG draws them (no dependencies).
"""
import math
import re
import sys


def bezier(x1, y1, x2, y2):
    def f(t):
        if t <= 0:
            return 0.0
        if t >= 1:
            return 1.0
        lo, hi = 0.0, 1.0
        for _ in range(60):
            s = (lo + hi) / 2
            x = 3 * (1 - s) ** 2 * s * x1 + 3 * (1 - s) * s * s * x2 + s ** 3
            if x < t:
                lo = s
            else:
                hi = s
        s = (lo + hi) / 2
        return 3 * (1 - s) ** 2 * s * y1 + 3 * (1 - s) * s * s * y2 + s ** 3
    return f


CURVES = {
    "standard": bezier(0.4, 0, 0.2, 1),
    "arrive": bezier(0.2, 0.8, 0.2, 1),
    "out": bezier(0.2, 0.7, 0.2, 1),
    "css": bezier(0.25, 0.1, 0.25, 1),
    "cssout": bezier(0, 0, 0.58, 1),
    "flight": bezier(0.6, 0, 0.2, 1),
    "linear": lambda t: min(max(t, 0.0), 1.0),
    "soft": bezier(0.16, 1, 0.3, 1),
}


def tween(ms, curve, delay=0.0):
    """What is left of the way (1 → 0) `t` ms in."""
    c = CURVES[curve]
    return lambda t, d0: 1.0 - c(min(max(math.floor(t) - delay, 0.0) / ms, 1.0))


def spring(stiffness, ratio=1.0, threshold=1.0, delay=0.0):
    """What is left of the way from `d0` (Compose's spring, at rest within `threshold`)."""
    w = math.sqrt(stiffness)

    def x(d, t):
        if ratio == 1.0:
            return (d + w * d * t) * math.exp(-w * t)
        wd = w * math.sqrt(1 - ratio * ratio)
        r = -ratio * w
        return math.exp(r * t) * (d * math.cos(wd * t) + (-r * d) / wd * math.sin(wd * t))

    def duration(d):
        p0 = abs(d / threshold)
        last, t = -1.0, 0.0
        while t < 10:
            if abs(x(p0, t)) >= 1:
                last = t
            elif abs(x(p0, t)) < 0.01:
                break
            t += 0.0005
        return math.floor(last * 1000) if last >= 0 else 0.0

    def left(t, d0):
        tt = math.floor(t)
        if tt < delay:
            return 1.0
        if d0 == 0 or tt >= delay + duration(d0):
            return 0.0
        return x(1.0, (tt - delay) / 1000.0)
    return left


def rspring(tension, friction):
    """What is left of the way of the bar's own springs (Bar.kt BarSpring: react-spring's tension and friction, mass 1,
    from rest), stepped as the bar steps them: 4 ms at most a step, each frame's time."""
    def left(t, d0):
        x, v, done = 1.0, 0.0, 0.0
        while done < t:
            h = min(0.004 * 1000, t - done) / 1000.0
            v += (-tension * x - friction * v) * h
            x += v * h
            done += h * 1000
        return x
    return left


def flight(t, d0=0.0):
    """What is left of the words' way up (ChatHost.kt: Ease.Flight, 12% late, over 80% of 600 ms)."""
    p = min(math.floor(t) / 600.0, 1.0)
    fly = min(p / 0.8, 1.0)
    return 1.0 - CURVES["flight"](max((fly - 0.12) / 0.88, 0.0))


# key pattern, field, what it is, what is left of its way at t (ms from its start), its frame's lag (Compose's: a frame
# from being asked to moving; the bar's own loop (Bar.kt) none: told as it is composed, stepped the next frame), its rest
SPECS = [
    (r"^home/.*\x01r/", "fy", "a Home row to its new place (ListMotion.kt: spring(1, 350), 100 ms late closing over one gone)",
     [spring(350.0), spring(350.0, delay=100.0)], 1, 0.0),
    (r"^home/.*\x01h/", "fy", "a day's heading to its new place (ListMotion.kt)", [spring(350.0), spring(350.0, delay=100.0)], 1, 0.0),
    (r"^chat-jump", "alpha", "the way to the newest, its opacity (Chat.kt: in 180 ms, out 150, CSS's ease)",
     [tween(180, "css"), tween(150, "css")], 1, None),
    (r"^chat-jump", "scale", "the way to the newest, its growing (Chat.kt: in 220 ms, out 180, standard)",
     [tween(220, "standard"), tween(180, "standard")], 1, None),
    (r"^composer/part/", "fy", "the composer's parts (Composer.kt Morph: 260 ms, Ease.Out)", [tween(260, "out")], 1, 0.0),
    (r"^composer/morph", "value", "the composer's height (Composer.kt Morph: 260 ms, Ease.Out)", [tween(260, "out")], 1, "to"),
    (r"^attach/offset", "value", "＋'s sheet (Sheet.kt: SheetSpring)", [spring((2 * math.pi / (1.2 * 0.32)) ** 2, threshold=0.5)], 1, "to"),
    (r"^attach/scrim", "value", "＋'s scrim (Sheet.kt: 300 ms, CSS's ease)", [tween(300, "css")], 1, "to"),
    (r"^toast", "alpha", "a toast (Sheet.kt ToastHost: 200 ms, CSS's ease)", [tween(200, "css")], 1, None),
    (r"^fly$", "dy", "words sent, up (ChatHost.kt Flight: Ease.Flight, 12% late, over 80% of 600 ms)", [flight], 1, "fly"),
    (r"^bar/icon-swap", "value", "the notch's icon swapping (Bar.kt showIcon: 300 ms on the bar's clock, linear)",
     [tween(300, "linear")], 0, "to"),
    (r"^bar/vis", "value", "the bar going down and coming back (Bar.kt: out 300 ms, in 380, Ease.Arrive)",
     [tween(300, "arrive"), tween(380, "arrive")], 0, "to"),
    (r"^bar/swap", "value", "a bar chosen in the panel landing (Bar.kt pick: the panel closing on BarSpring 200/28)",
     [rspring(200.0, 28.0)], 0, "to"),
    (r"^settings-sheet/offset", "value", "a settings sheet (Sheet.kt: SheetSpring)", [spring((2 * math.pi / (1.2 * 0.32)) ** 2, threshold=0.5)], 1, "to"),
    (r"^settings-sheet/scrim", "value", "a settings sheet's scrim (Sheet.kt: 300 ms, CSS's ease)", [tween(300, "css")], 1, "to"),
    (r"^under/options/", "alpha", "a card's options going (Decisions.kt: fadeOut 200 ms, CSS's ease-out)", [tween(200, "cssout")], 1, None),
    (r"^under/options/", "open", "a card's options' room closing (ListMotion.kt closeGap: spring(1, 350), 100 ms late)",
     [spring(350.0, threshold=0.002, delay=100.0)], 1, 0.0),
    (r"^under/outcome/", "open", "how a card went, its room opening (closeGap)", [spring(350.0, threshold=0.002, delay=100.0)], 1, 1.0),
    (r"^under/(dismiss|archive)/", "open", "忽略, 保留 / 归档此对话 coming or going (Chat.kt: 280 ms, ArchiveEase)",
     [tween(280, "soft")], 1, None),
    (r"^under/(dismiss|archive)/", "alpha", "their opacity (Chat.kt: 280 ms, ArchiveEase)", [tween(280, "soft")], 1, None),
    (r"^bar-archive/", "alpha", "the bar's 归档 coming or going (Chat.kt ChatBar: 280 ms, ArchiveEase)", [tween(280, "soft")], 1, None),
]


def emit_poses(runs):
    """An agent's answer out of its avatar (ChatMotion.kt): each pose's frames against Android's formulas, from where
    the flying avatar set out and where it landed (its first and last frames): the hop's height, the spit's squash.
    Returns (what, frames, largest difference as a share of the way)."""
    out = []
    for key, series in runs.items():
        if key.startswith("emit/"):
            out.extend(by_pose(key, series))
    return out


def by_pose(key, lines):
    res = []
    floats = [(t, v) for t, v in lines if v.get("_pose") == "Float"]
    spits = [(t, v) for t, v in lines if v.get("_pose") == "Spit"]
    if len(floats) >= 3:
        t0, t1 = floats[0][0], floats[-1][0]
        ms = 440.0
        sy, ly = floats[0][1]["y"], floats[-1][1]["y"]
        top = min(sy, ly) - 34.0
        worst, way = 0.0, max(abs(ly - sy), 34.0)
        for t, v in floats:
            u = min((t - t0) / ms, 1.0)
            if u < 0.42:
                want = sy + (top - sy) * (1 - (1 - u / 0.42) ** 2.5)
            else:
                want = top + (ly - top) * ((u - 0.42) / 0.58) ** 2.5
            worst = max(worst, abs(v["y"] - want))
        res.append((f"the avatar's hop (ChatMotion.kt Float: 440 ms) — {key}, over {t1 - t0:.0f} ms", len(floats), worst / way))
    if len(spits) >= 3:
        t0 = spits[0][0]
        worst = 0.0
        for t, v in spits:
            u = min((t - t0) / 380.0, 1.0)
            w0 = math.sqrt(520.0)
            z = 14.0 / (2 * w0)
            wd = w0 * math.sqrt(1 - z * z)
            s = u * 0.38
            k = math.exp(-z * w0 * s) * (math.cos(wd * s) + z * w0 / wd * math.sin(wd * s))
            sm = lambda x: x * x * (3 - 2 * x)
            swell = 1 + 0.12 * (sm(u / 0.4) if u < 0.4 else (1 - sm((u - 0.4) / 0.35)) if u < 0.75 else 0.0)
            worst = max(worst, abs(v["sx"] - swell * (1 + 0.16 * k)) / 0.28)
        res.append((f"the answer let out, the avatar squashed (ChatMotion.kt Spit: 380 ms) — {key}", len(spits), worst))
    return res


def parse(path):
    runs = {}
    for line in open(path, errors="replace"):
        m = re.search(r"MOTION (\S+) (.*?) ((?:\w+=\S+ ?)+)$", line.strip())
        if not m:
            continue
        vals = {}
        for kv in m.group(3).split():
            k, v = kv.split("=")
            try:
                vals[k] = float(v)
            except ValueError:
                vals["_" + k] = v
        runs.setdefault(m.group(2), []).append((float(m.group(1)), vals))
    return runs


def segments(series):
    out, cur = [], []
    for t, v in series:
        if cur and t - cur[-1][0] > 40:
            out.append(cur)
            cur = []
        cur.append((t, v))
    if cur:
        out.append(cur)
    return out


def compare(seg, field, specs, lag_frames, rest):
    t0 = seg[0][0]
    if field not in seg[0][1]:
        return None
    if rest == "fly":
        # flown from where it took off to where it is laid out (read each frame): dy is what is left
        y0 = seg[0][1]["y"]
        got = [(t - t0, v["dy"]) for t, v in seg]
        laid = [v["y"] - v["dy"] for _, v in seg]
        way = [y0 - l for l in laid]
    else:
        if rest == "to":
            end = seg[0][1]["to"]
        elif rest is None:
            last = seg[-1][1][field]
            end = 0.0 if abs(last) < abs(1.0 - last) and field == "alpha" else 1.0
            if field == "alpha":
                end = 0.0 if seg[0][1][field] > 0.5 else 1.0
        else:
            end = rest
        d0 = seg[0][1][field] - end
        got = [(t - t0, v[field] - end) for t, v in seg]
        way = [d0] * len(seg)
    lag = (seg[1][0] - seg[0][0]) * lag_frames
    best = None
    for spec in specs:
        want = [(t, w * spec(max(t - lag, 0.0), w)) for (t, _), w in zip(got, way)]
        err = max(abs(a[1] - b[1]) for a, b in zip(got, want))
        if best is None or err < best[0]:
            best = (err, want)
    scale = max(abs(way[0]), 1e-9)
    return got, best[1], best[0], best[0] / scale, way[0]


def svg(plots, path):
    w, h, pad = 640, 200, 36
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h * len(plots)}" font-family="sans-serif" font-size="11">']
    for i, (title, got, want) in enumerate(plots):
        oy = i * h
        ts = [t for t, _ in got] + [t for t, _ in want]
        vs = [v for _, v in got] + [v for _, v in want]
        t1 = max(ts) or 1.0
        lo, hi = min(vs + [0.0]), max(vs + [0.0])
        if hi - lo < 1e-9:
            hi = lo + 1
        fx = lambda t: pad + (w - 2 * pad) * t / t1
        fy = lambda v: oy + h - pad + (pad * 2 - h) * (v - lo) / (hi - lo)
        out.append(f'<text x="{pad}" y="{oy + 16}">{title}</text>')
        out.append(f'<line x1="{pad}" y1="{fy(0)}" x2="{w - pad}" y2="{fy(0)}" stroke="#ddd"/>')
        out.append('<polyline fill="none" stroke="#adb5bd" stroke-width="4" points="' +
                   " ".join(f"{fx(t):.1f},{fy(v):.1f}" for t, v in want) + '"/>')
        out.append('<polyline fill="none" stroke="#d9480f" stroke-width="1.5" points="' +
                   " ".join(f"{fx(t):.1f},{fy(v):.1f}" for t, v in got) + '"/>')
        for t, v in got:
            out.append(f'<circle cx="{fx(t):.1f}" cy="{fy(v):.1f}" r="2" fill="#d9480f"/>')
        out.append(f'<text x="{w - pad}" y="{oy + h - 8}" text-anchor="end">{t1:.0f} ms · grey: Android (Compose) · orange: mbui</text>')
    out.append("</svg>")
    open(path, "w").write("\n".join(out))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    runs = parse(sys.argv[1])
    plots, worst = [], 0.0
    for key, series in sorted(runs.items()):
        for pattern, field, what, specs, lag, rest in SPECS:
            if not re.search(pattern, key):
                continue
            for seg in segments(series):
                if len(seg) < 3:
                    continue
                r = compare(seg, field, specs, lag, rest)
                if r is None:
                    continue
                got, want, err, share, d0 = r
                if abs(d0) < 1e-6:
                    continue
                worst = max(worst, share)
                name = key.replace("\x01", " · ")
                print(f"{what}\n  {name}: {len(seg)} frames over {seg[-1][0] - seg[0][0]:.0f} ms, from {d0:.2f}; "
                      f"largest difference {err:.3f} ({100 * share:.2f}% of the way)")
                plots.append((f"{what} — {name}", got, want))
    for what, n, share in emit_poses(runs):
        worst = max(worst, share)
        print(f"{what}\n  {n} frames; largest difference {100 * share:.2f}% of the way")
    print(f"WORST {100 * worst:.2f}% of the way")
    if len(sys.argv) > 2 and plots:
        svg(plots[:12], sys.argv[2])
        print("PLOT", sys.argv[2])


if __name__ == "__main__":
    main()

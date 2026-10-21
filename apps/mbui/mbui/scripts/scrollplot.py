#!/usr/bin/env python3
"""How a list flings in mbui against how Compose's would (src/ui/scroll.mbt).

A reference of Compose's own formulas, written apart from the MoonBit (androidx.compose.animation FlingCalculator and
AndroidFlingSpline, androidx.compose.ui VelocityTracker1D's Lsq2), used two ways:

  scrollplot.py table                  expected values for src/ui/scroll_wbtest.mbt
  scrollplot.py LOG [PNG]              a log of an app run with MBUI_SCROLL_LOG=1 (adb logcat -s mbui:I): each fling's
                                       velocity (mbui's, and this file's from the same touches), distance and duration,
                                       the positions frame by frame against Compose's spline from the same velocity, and
                                       against mbui before (velocity smoothed per move, decaying 0.997 per ms); PNG plots
                                       them (matplotlib).
"""
import math
import re
import sys

# --- Compose's fling (FlingCalculator, AndroidFlingSpline) ---

INFLECTION, START_T, END_T = 0.35, 0.5, 1.0
P1, P2 = START_T * INFLECTION, 1.0 - END_T * (1.0 - INFLECTION)
DECEL = math.log(0.78) / math.log(0.9)


def spline_positions(n=100):
    pos = [0.0] * (n + 1)
    x_min = 0.0
    for i in range(n):
        alpha = i / n
        x_max = 1.0
        while True:
            x = x_min + (x_max - x_min) / 2.0
            coef = 3.0 * x * (1.0 - x)
            tx = coef * ((1.0 - x) * P1 + x * P2) + x * x * x
            if abs(tx - alpha) < 1e-5:
                break
            if tx > alpha:
                x_max = x
            else:
                x_min = x
        pos[i] = coef * ((1.0 - x) * START_T + x) + x * x * x
    pos[n] = 1.0
    return pos


SPLINE = spline_positions()


def fling(v_px_s, density):
    """distance (px) and duration (whole ms) of a fling at v px/s on a screen of `density`"""
    if v_px_s == 0:
        return 0.0, 0
    friction = 0.015 * (9.80665 * 39.37 * 160.0 * density * 0.84)
    l = math.log(0.35 * abs(v_px_s) / friction)
    return friction * math.exp(DECEL / (DECEL - 1.0) * l), int(1000.0 * math.exp(l / (DECEL - 1.0)))


def fling_at(t_ms, dist, dur):
    s = min(max(t_ms / dur if dur > 0 else 1.0, 0.0), 1.0)
    i = int(100 * s)
    if i >= 100:
        return dist
    vc = (SPLINE[i + 1] - SPLINE[i]) / 0.01
    return dist * (SPLINE[i] + (s - i / 100) * vc)


# --- Compose's VelocityTracker1D, Lsq2 ---

def lsq2_velocity(samples):
    """samples: [(t_ms, pos)] oldest first; units per ms at the newest"""
    if not samples:
        return 0.0
    pts = []
    newest = samples[-1][0]
    prev = newest
    for t, v in reversed(samples[-20:]):
        age, gap = newest - t, abs(t - prev)
        prev = t
        if age > 100 or gap > 40:
            break
        pts.append((-age, v))
    if len(pts) < 2:
        return 0.0
    m, n = len(pts), min(3, len(pts))
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    a = [[xs[h] ** i for h in range(m)] for i in range(n)]
    q, r = [[0.0] * m for _ in range(n)], [[0.0] * n for _ in range(n)]
    dot = lambda u, w: sum(i * j for i, j in zip(u, w))
    for j in range(n):
        w = a[j][:]
        for i in range(j):
            d = dot(w, q[i])
            w = [w[h] - d * q[i][h] for h in range(m)]
        nrm = max(math.sqrt(dot(w, w)), 1e-6)
        q[j] = [x / nrm for x in w]
        for i in range(n):
            r[j][i] = 0.0 if i < j else dot(q[j], a[i])
    c = [0.0] * n
    for i in range(n - 1, -1, -1):
        s = dot(q[i], ys)
        for k in range(n - 1, i, -1):
            s -= r[i][k] * c[k]
        c[i] = s / r[i][i]
    return c[1]


def old_velocity(samples):
    """mbui before: per move v = vel*0.4 + dy/dt*0.6, kept only if the last move was under 80 ms before the up"""
    vel = 0.0
    for (t0, y0), (t1, y1) in zip(samples, samples[1:]):
        if t1 - t0 > 0:
            vel = vel * 0.4 + (y1 - y0) / (t1 - t0) * 0.6
    return max(-8.0, min(8.0, vel))


def old_fling_at(t_ms, v):
    """mbui before: decaying 0.997 per ms until under 0.02 px/ms"""
    if v == 0.0:
        return 0.0
    k = math.log(0.997)
    t_end = math.log(0.02 / abs(v)) / k if abs(v) > 0.02 else 0.0
    t = min(t_ms, t_end)
    return v * (0.997 ** t - 1.0) / k


def table():
    print("density 2.625 (420 dpi) and 3.0; v in dp/ms -> distance dp, duration ms")
    for density in (2.625, 3.0):
        for v in (0.5, 1.0, 2.0, 4.0, 8.0):
            d, dur = fling(v * 1000 * density, density)
            print(f"  density={density} v={v}: distance={d / density:.4f} dp duration={dur} ms "
                  f"at 100ms={fling_at(100, d, dur) / density:.4f} dp at 300ms={fling_at(300, d, dur) / density:.4f} dp")
    print("Lsq2: y = 0.002 t^2 + 1.5 t every 8 ms from 0 to 96 ->", lsq2_velocity([(t, 0.002 * t * t + 1.5 * t) for t in range(0, 97, 8)]))
    print("Lsq2: y = 3 t, samples at 0..64 then a 50 ms pause ->", lsq2_velocity([(t, 3.0 * t) for t in range(0, 65, 8)] + [(114, 192.0)]))
    print("Lsq2: uneven [(0,0),(3,5),(16,20),(21,31),(33,52)] ->", lsq2_velocity([(0, 0), (3, 5), (16, 20), (21, 31), (33, 52)]))
    print("spline positions [10],[35],[70]:", SPLINE[10], SPLINE[35], SPLINE[70])


def parse(path):
    """the log's runs: each down..up with its touches, its FLING line and the SCROLL frames until the next down"""
    runs, cur = [], None
    pat = re.compile(r"(TOUCH|FLING|SCROLL) (.*)$")
    for line in open(path, errors="replace"):
        m = pat.search(line.strip())
        if not m:
            continue
        kind, rest = m.group(1), m.group(2).split()
        if kind == "TOUCH":
            k, t, x, y = int(rest[0]), float(rest[1]), float(rest[2]), float(rest[3])
            handled = float(rest[4]) if len(rest) > 4 else t
            if k == 0:
                cur = {"touches": [], "handled": [], "fling": None, "frames": []}
                runs.append(cur)
            if cur is not None:
                cur["touches"].append((k, t, x, y))
                cur["handled"].append((k, handled, y))
        elif kind == "FLING" and cur is not None:
            cur["fling"] = (float(rest[0]), float(rest[1]), float(rest[2]), float(rest[3].split("=")[1]))
            cur["from"] = len(cur["frames"])
        elif kind == "SCROLL" and cur is not None:
            cur["frames"].append(tuple(float(v) for v in rest[:4]))
    return [r for r in runs if r["fling"] and r["frames"]]


def analyse(path, png=None):
    runs = parse(path)
    plots = []
    for n, r in enumerate(runs):
        v, dist_pred, dur_pred, scale = r["fling"]
        touches = [(t, y) for k, t, x, y in r["touches"]]
        # the fling's frames: those drawn after the finger left (logged after it); its start, the first of them
        # (playtime 0, as Compose's; its time is its vsync's, which may come before the up was handled)
        frames = r["frames"][r["from"]:]
        if not frames:
            continue
        t0, y0 = frames[0][0], frames[0][1]
        moving = [f for f in frames if f[3] != 0.0]
        end = moving[-1] if moving else frames[0]
        after = [f for f in frames if f[0] > end[0]]
        last = after[0] if after else end
        measured_dist, measured_dur = last[1] - y0, last[0] - t0
        ref_v = -lsq2_velocity(touches)
        ref_v = max(-8.0, min(8.0, ref_v))
        # mbui before saw each touch at the time the GL thread handled it, without the samples batched into a move
        # (here all are; the batched ones come handled at the same time, which gave the old code dt = 0)
        hs = [(t, y) for k, t, y in r["handled"] if k != 2]
        # one per MotionEvent: the last of the samples handled together
        last_of = [p for p, q in zip(hs, hs[1:] + [(1e18, 0)]) if q[0] - p[0] >= 0.5]
        old_v = -old_velocity(last_of)
        # ...and kept it only if the last move was handled less than 80 ms before the up
        ups = [t for k, t, y in r["handled"] if k == 2]
        if ups and last_of and ups[-1] - last_of[-1][0] >= 80:
            old_v = 0.0
        same = sum(1 for a, b in zip(hs, hs[1:]) if b[0] - a[0] < 0.5)
        gaps = [round(b[0] - a[0], 1) for a, b in zip(hs, hs[1:])]
        evgaps = [round(b - a, 1) for (a, _), (b, _) in zip(touches, touches[1:])]
        cd, cdur = fling(ref_v * 1000 * scale, scale)
        print(f"fling {n}: touches {len(touches)} over {touches[-1][0] - touches[0][0]:.0f} ms; velocity mbui {v:.4f} "
              f"reference Lsq2 {ref_v:.4f} (before: smoothed over handling times {old_v:.4f}) dp/ms")
        print(f"  touch times apart (ms): {evgaps}")
        print(f"  handled apart (ms):     {gaps} ({same} handled together)")
        print(f"  mbui: {measured_dist:.1f} dp in {measured_dur:.0f} ms (frames {len(frames)}); "
              f"Compose at the same velocity: {cd / scale:.1f} dp in {cdur} ms; mbui before: "
              f"{old_fling_at(1e9, old_v):.1f} dp in {math.log(0.02 / abs(old_v)) / math.log(0.997) if abs(old_v) > 0.02 else 0:.0f} ms")
        # up to an end of the list, where it stops (and stretches)
        free = [f for f in frames if f[2] == 0.0]
        edge = next((f for f in frames if f[2] != 0.0), None)
        if edge:
            print(f"  reached an end {edge[0] - t0:.0f} ms in, at {edge[1] - y0:.1f} dp: stretched there, at most "
                  f"{max(abs(f[2]) for f in frames):.3f} of the list's height, at rest again "
                  f"{frames[-1][0] - edge[0]:.0f} ms later")
        errs = [abs((f[1] - y0) - math.copysign(fling_at(f[0] - t0, cd, cdur) / scale, ref_v)) for f in free] or [0.0]
        print(f"  position against Compose's{' (before the end)' if edge else ''}: max error {max(errs):.2f} dp, "
              f"mean {sum(errs) / len(errs):.2f} dp")
        ivs = [b[0] - a[0] for a, b in zip(frames, frames[1:])]
        if ivs:
            print(f"  frames apart (ms): min {min(ivs):.1f} median {sorted(ivs)[len(ivs) // 2]:.1f} max {max(ivs):.1f}")
        if ref_v != 0.0:
            plots.append((n, frames, t0, y0, ref_v, old_v, cd / scale, cdur, scale))
    if png and plots:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        plt.rcParams.update({"axes.edgecolor": "#c3c2b7", "axes.labelcolor": "#52514e", "xtick.color": "#52514e",
                             "ytick.color": "#52514e", "text.color": "#0b0b0b", "axes.spines.top": False,
                             "axes.spines.right": False})
        cols = min(3, len(plots))
        rows = (len(plots) + cols - 1) // cols
        fig, axes = plt.subplots(rows, cols, figsize=(5.2 * cols, 4.0 * rows), squeeze=False, facecolor="#fcfcfb")
        for ax in axes.flat[len(plots):]:
            ax.set_visible(False)
        for ax, (n, frames, t0, y0, v, old_v, cd, cdur, scale) in zip(axes.flat, plots):
            ax.set_facecolor("#fcfcfb")
            ts = [f[0] - t0 for f in frames]
            horizon = max(max(ts), cdur) + 100
            grid = [i * 4.0 for i in range(int(horizon / 4) + 1)]
            ax.plot(grid, [math.copysign(fling_at(t, cd * scale, cdur) / scale, v) for t in grid], color="#2a6fdb",
                    lw=2, label=f"Compose spline ({cd:.0f} dp, {cdur} ms)")
            ax.plot(grid, [old_fling_at(t, old_v) for t in grid], color="#8f8e88", lw=2, ls="--",
                    label=f"mbui before ({old_fling_at(1e9, old_v):.0f} dp)")
            ax.plot(ts, [f[1] - y0 for f in frames], "o", ms=6, color="#eb6834", markeredgecolor="#fcfcfb",
                    markeredgewidth=1.5, label="mbui now, each frame drawn")
            ax.set_title(f"fling {n}: {v * 1000:.0f} dp/s", fontsize=11, loc="left")
            ax.set_xlabel("ms after the finger left")
            ax.set_ylabel("scrolled (dp)")
            ax.grid(color="#e4e3dd", lw=0.8)
            ax.legend(fontsize=8, frameon=False)
        fig.tight_layout()
        fig.suptitle("A list flung on Android: mbui against Compose's fling at the same velocity", x=0.01, ha="left",
                     fontsize=12)
        fig.tight_layout()
        fig.savefig(png, dpi=120, facecolor="#fcfcfb")
        print("plot:", png)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "table":
        table()
    elif len(sys.argv) > 1:
        analyse(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
    else:
        print(__doc__)

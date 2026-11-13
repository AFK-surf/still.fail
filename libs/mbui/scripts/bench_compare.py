#!/usr/bin/env python3
"""Compares the last bench run of each framework, scene by scene: mbui's
(bench/history.jsonl, src/bench) against its previous and best runs, and
beside it every other framework found in the files given: nanoui's and
mygo's (nanoui's hillclimb/history.jsonl), Flutter's (bench/flutter, also
appended to bench/history.jsonl with "fw": "flutter").

  scripts/bench_compare.py bench/history.jsonl [nanoui/hillclimb/history.jsonl] [--md]

For each framework the latest entry that has results for it is used.
Flutter's runs (scripts/bench_flutter.sh) show as up to three columns:
"flutter", frames at vsync with another core kept busy (HEAT=1), so the
CPU runs at the clock the other frameworks' back-to-back loops get;
"flutter-b2b", frames back to back (PACE=hot: no raster times, the engine
skips rasterizing most of them); "flutter-cold", frames at vsync on an
otherwise idle machine, where macOS clocks the cores down between frames.
"""
import json
import sys
import time

METRICS = [
    ("frame CPU (median)", "frame_ms", "ms"),
    ("frame CPU (p95)", "frame_p95", "ms"),
    ("  build", "build_ms", "ms"),
    ("  layout", "layout_ms", "ms"),
    ("  paint", "paint_ms", "ms"),
    ("encode CPU", "encode_ms", "ms"),
    ("GPU", "gpu_ms", "ms"),
    ("process CPU / frame", "cpu_ms", "ms"),
    ("draw items", "ops", ""),
    ("frames", "frames", ""),
    ("run (ms)", "run_ms", ""),
]
ORDER = ["mbui", "nanoui", "mygo", "flutter", "flutter-b2b", "flutter-cold"]


def load(path):
    out = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        e = json.loads(line)
                    except ValueError:
                        continue
                    for r in e.get("results", []):
                        if r.get("fw") == "flutter":
                            if r.get("pace") == "hot":
                                r["fw"] = "flutter-b2b"
                            elif not r.get("heat"):
                                r["fw"] = "flutter-cold"
                    out.append(e)
    except OSError:
        pass
    return out


def find(entry, fw, scene):
    if not entry:
        return None
    for r in entry["results"]:
        if r.get("fw") == fw and r.get("scene") == scene:
            return r
    return None


def has(entry, fw):
    return any(r.get("fw") == fw for r in entry.get("results", []))


def fmt(v, unit):
    if v is None:
        return "—"
    # times (kept in ms) as whole µs: 1 to 999 for most of them, easy to scan
    return f"{v * 1000:.0f}" if unit else f"{int(v)}"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    md = "--md" in sys.argv
    entries = [e for path in args for e in load(path)]
    mine = [e for e in entries if has(e, "mbui")]
    if not mine:
        print("no mbui runs in", args[0])
        return
    last = mine[-1]
    prev = mine[-2] if len(mine) > 1 else None
    fws = sorted({r.get("fw") for e in entries for r in e.get("results", [])} - {"mbui", None},
                 key=lambda f: (ORDER.index(f) if f in ORDER else len(ORDER), f))
    latest = {fw: [e for e in entries if has(e, fw)][-1] for fw in fws}
    scenes = [r["scene"] for r in last["results"]]
    ratios = [fw for fw in ("nanoui", "flutter") if fw in fws]
    # mbui against nanoui (how far behind it), Flutter against mbui (how far behind mbui)
    cols = ["mbui"] + fws + [("mbui/nanoui" if fw == "nanoui" else f"{fw}/mbui") for fw in ratios] + ["Δ last", "Δ best"]
    w = max(11, *(len(c) + 1 for c in cols))
    if md:
        print("| scene | metric | " + " | ".join(cols) + " |")
        print("|---|---|" + "---:|" * len(cols))
    else:
        print(f"{'scene':<10} {'metric':<20} " + " ".join(f"{c:>{w}}" for c in cols))
    for scene in scenes:
        m = find(last, "mbui", scene)
        others = {fw: find(latest[fw], fw, scene) for fw in fws}
        for i, (name, key, unit) in enumerate(METRICS):
            v = m.get(key) if m else None
            # nanoui records mygo's phases as 0: not measured
            vals = {fw: (o.get(key) if o and o.get(key) else None) for fw, o in others.items()}
            ratio = [(f"{v / vals[fw]:.2f}×" if fw == "nanoui" else f"{vals[fw] / v:.2f}×")
                     if v and vals[fw] and min(v, vals[fw]) >= 0.001 else "" for fw in ratios]
            dl = db = ""
            p = find(prev, "mbui", scene)
            if key in ("frames", "run_ms"):  # how long it ran, not how fast
                p = None
            if p and p.get(key) and v is not None:
                dl = f"{(v - p[key]) / p[key] * 100:+.1f}%"
            best = [find(e, "mbui", scene) for e in mine[:-1]]
            best = [b[key] for b in best if b and b.get(key)]
            if best and v is not None and p is not None:
                db = f"{(v - min(best)) / min(best) * 100:+.1f}%"
            cells = [fmt(v, unit)] + [fmt(vals[fw], unit) for fw in fws] + ratio + [dl, db]
            label = scene if i == 0 else ""
            if md:
                print(f"| {label} | {name.strip()} | " + " | ".join(cells) + " |")
            else:
                print(f"{label:<10} {name:<20} " + " ".join(f"{c:>{w}}" for c in cells))
        if not md:
            print()
    if not md:
        print("times in µs a frame; Δ against mbui's previous run" + (f" ({prev['label']})" if prev and prev.get("label") else "") +
              f" and its best of {len(mine) - 1}; changes within ±5% are noise")
        for fw in ["mbui"] + fws:
            e = last if fw == "mbui" else latest[fw]
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(e.get("time", 0)))
            print(f"  {fw}: run of {when}" + (f" ({e['label']})" if e.get("label") else ""))


main()

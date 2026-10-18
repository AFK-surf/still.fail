#!/usr/bin/env python3
"""Compares mbui's last bench run (bench/history.jsonl, src/bench) with its
previous and best runs, and with nanoui's and mygo's last run of nanoui's
hill-climb (its hillclimb/history.jsonl), scene by scene.

  scripts/bench_compare.py bench/history.jsonl [nanoui/hillclimb/history.jsonl] [--md]
"""
import json
import sys

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
]


def load(path):
    out = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        out.append(json.loads(line))
                    except ValueError:
                        pass
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


def fmt(v, unit):
    if v is None:
        return "—"
    return f"{v:.3f}" if unit else f"{int(v)}"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    md = "--md" in sys.argv
    mine = load(args[0])
    if not mine:
        print("no mbui runs in", args[0])
        return
    last = mine[-1]
    prev = mine[-2] if len(mine) > 1 else None
    other = load(args[1])[-1:] if len(args) > 1 else []
    other = other[0] if other else None
    scenes = [r["scene"] for r in last["results"]]
    cols = ["mbui", "nanoui", "mygo", "mbui/nanoui", "Δ last", "Δ best"]
    if md:
        print("| scene | metric | " + " | ".join(cols) + " |")
        print("|---|---|" + "---:|" * len(cols))
    else:
        print(f"{'scene':<10} {'metric':<20} " + " ".join(f"{c:>11}" for c in cols))
    for scene in scenes:
        m = find(last, "mbui", scene)
        n = find(other, "nanoui", scene)
        g = find(other, "mygo", scene)
        for i, (name, key, unit) in enumerate(METRICS):
            v = m.get(key) if m else None
            nv = n.get(key) if n else None
            gv = g.get(key) if g and g.get(key) else None
            ratio = f"{v / nv:.2f}×" if v is not None and nv else ""
            dl = ""
            p = find(prev, "mbui", scene)
            if p and p.get(key) and v is not None:
                dl = f"{(v - p[key]) / p[key] * 100:+.1f}%"
            best = [find(e, "mbui", scene) for e in mine[:-1]]
            best = [b[key] for b in best if b and b.get(key)]
            db = f"{(v - min(best)) / min(best) * 100:+.1f}%" if best and v is not None else ""
            cells = [fmt(v, unit), fmt(nv, unit), fmt(gv, unit), ratio, dl, db]
            label = scene if i == 0 else ""
            if md:
                print(f"| {label} | {name.strip()} | " + " | ".join(cells) + " |")
            else:
                print(f"{label:<10} {name:<20} " + " ".join(f"{c:>11}" for c in cells))
        if not md:
            print()
    if not md:
        print("times in ms; Δ against mbui's previous run" + (f" ({prev['label']})" if prev and prev.get("label") else "") +
              f" and its best of {len(mine) - 1}; changes within ±5% are noise")


main()

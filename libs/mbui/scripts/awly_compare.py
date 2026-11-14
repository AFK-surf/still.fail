#!/usr/bin/env python3
# Two or more runs of src/awly (its JSON lines, e.g. before.jsonl after.jsonl, each file one or more runs): each
# workload's fastest mean per file, the last against the first, and whether every file came to the same layout.
import json, sys

runs = []
for path in sys.argv[1:]:
    by = {}
    for line in open(path):
        if line.startswith("{"):
            d = json.loads(line)
            by.setdefault(d["scenario"], []).append(d)
    runs.append(by)
names = sys.argv[1:]
print(f"{'workload':36s}" + "".join(f"{n[-14:]:>15s}" for n in names) + f"{'last/first':>11s}  same layout")
for s in runs[0]:
    ms = [min(d["mean_ns"] for d in r[s]) / 1e6 for r in runs]
    first = runs[0][s][0]
    same = all(d["sum"] == first["sum"] and d["root"] == first["root"] for r in runs for d in r[s])
    print(f"{s:36s}" + "".join(f"{m:15.3f}" for m in ms) + f"{ms[-1] / ms[0]:11.2f}  {same}")

#!/usr/bin/env python3
"""Whether two outputs of the chat list are the same value (key order and 1 vs 1.0 aside); the first differences if
not. compare.py <a.json> <b.json>"""
import json, sys

a, b = (json.load(open(p)) for p in sys.argv[1:3])
found = []

def walk(x, y, path):
    if len(found) >= 10:
        return
    if isinstance(x, dict) and isinstance(y, dict):
        for k in sorted(set(x) | set(y)):
            if k not in x or k not in y:
                found.append(f"{path}.{k}: {'missing in a' if k not in x else 'missing in b'} ({json.dumps(x.get(k, y.get(k)), ensure_ascii=False)[:80]})")
            else:
                walk(x[k], y[k], f"{path}.{k}")
    elif isinstance(x, list) and isinstance(y, list):
        if len(x) != len(y):
            found.append(f"{path}: {len(x)} items vs {len(y)}")
        for i, (p, q) in enumerate(zip(x, y)):
            walk(p, q, f"{path}[{i}]")
    elif x != y or type(x) is bool != (type(y) is bool):
        found.append(f"{path}: {json.dumps(x, ensure_ascii=False)[:80]} vs {json.dumps(y, ensure_ascii=False)[:80]}")

walk(a, b, "")
rows = sum(len(d["items"]) for d in a.get("days", []))
if found:
    print(f"DIFFERENT ({rows} rows):")
    print("\n".join(found))
    sys.exit(1)
print(f"same: {rows} rows in {len(a.get('days', []))} days")

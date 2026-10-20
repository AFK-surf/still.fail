#!/usr/bin/env python3
"""What a re-recording changed in a flow's trace, at a glance: the app's asks (calls, subscriptions, their params
without ids and times) more or fewer than before, and how many messages each side had. Not the JSON's diff.

  scripts/tracediff.py OLD.trace NEW.trace
"""
import json, re, sys
from collections import Counter

VOLATILE = re.compile(r"^(id|ts|at|createdAt|updatedAt|startedAt|endedAt|w|time|now|nonce|clientKey|key|session|thread|station)$")


def calm(v):
    if isinstance(v, dict):
        return {k: ("…" if VOLATILE.match(k) else calm(x)) for k, x in sorted(v.items())}
    if isinstance(v, list):
        return [calm(x) for x in v]
    if isinstance(v, str):
        # a run's own: its mark, the workspace's and stations' ids (a fresh local still.fail makes new ones), ports
        v = re.sub(r"\b[0-9A-HJKMNP-TV-Z]{26}\b", "<ws>", v)
        v = re.sub(r"\b[0-9a-f]{64}\b", "<st>", v)
        v = re.sub(r"ember(%3A|:)c-[0-9a-f]{10}", "<session>", v)
        v = re.sub(r"127\.0\.0\.1:\d+", "127.0.0.1:<port>", v)
        v = re.sub(r"message=\d+", "message=<n>", v)
        if re.fullmatch(r"\d{6}", v):
            return "…"
    return v


def asks(path):
    out, n_in = Counter(), 0
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        ev = json.loads(line)
        if "in" in ev:
            n_in += 1
            continue
        m = ev.get("out", {})
        if "call" in m:
            name = "call " + m["call"]
            detail = calm(m.get("params"))
        elif "subscribe" in m:
            name = "subscribe " + m["subscribe"].get("topic", "?")
            detail = calm({k: v for k, v in m["subscribe"].items() if k != "topic"})
        elif m.get("unsubscribe"):
            name, detail = "unsubscribe", None
        elif m.get("cancel"):
            name, detail = "cancel", None
        else:
            name, detail = "other", calm(m)
        out[name + ("" if detail in (None, {}) else " " + json.dumps(detail, ensure_ascii=False, sort_keys=True))] += 1
    return out, n_in


old, old_in = asks(sys.argv[1])
new, new_in = asks(sys.argv[2])
more = new - old
fewer = old - new
print(f"asks {sum(old.values())} → {sum(new.values())}, messages in {old_in} → {new_in}")
for k, n in sorted(more.items()):
    print(f"  + {n}× {k[:200]}")
for k, n in sorted(fewer.items()):
    print(f"  - {n}× {k[:200]}")
if not more and not fewer:
    print("  the same asks")

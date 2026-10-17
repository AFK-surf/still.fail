#!/usr/bin/env python3
"""ui.py for the iOS simulator: finds things in AXe's `describe-ui` (its accessibility tree, JSON) by what they say
(ios-shots.sh), printing the centre (in points, what `axe tap -x -y` takes) of the first element whose label or value
matches one of the patterns, else exits 1. Patterns as ui.py's: matched whole, `~x` contains x, `@x` an element whose
type has x in it (`@TextField`, `@TextView`). `--list`: every element that says something, with its frame.
`--below Y` / `--above Y`: only elements whose centre is there.

  ios-ui.py <describe-ui.json> [--below Y] [--above Y] <pattern>...
  ios-ui.py <describe-ui.json> --list
"""
import json
import sys


def nodes(path):
    # AXe says other things around the JSON (on stderr, kept with it): read from where the JSON starts.
    try:
        with open(path) as f:
            text = f.read()
        starts = [i for i in (text.find("["), text.find("{")) if i >= 0]
        root = json.JSONDecoder().raw_decode(text[min(starts):])[0]
    except Exception:
        return
    todo = list(root) if isinstance(root, list) else [root]
    while todo:
        n = todo.pop(0)
        todo[0:0] = n.get("children") or []
        f = n.get("frame") or {}
        w, h = f.get("width", 0), f.get("height", 0)
        if w <= 0 or h <= 0:
            continue
        x0, y0 = f.get("x", 0), f.get("y", 0)
        said = [s for s in (n.get("AXLabel"), n.get("AXValue"), n.get("title")) if isinstance(s, str) and s]
        yield said, (round(x0 + w / 2), round(y0 + h / 2)), (round(x0), round(y0), round(x0 + w), round(y0 + h)), n


def main(argv):
    path, rest = argv[0], argv[1:]
    if rest[:1] == ["--list"]:
        seen = set()
        for said, c, b, n in nodes(path):
            line = f"{b} {' | '.join(dict.fromkeys(said))} [{n.get('type', '')}]"
            if said and line not in seen:
                seen.add(line)
                print(line)
        return 0
    below, above = -1, 10**9
    while rest and rest[0] in ("--below", "--above"):
        if rest[0] == "--below":
            below = int(rest[1])
        else:
            above = int(rest[1])
        rest = rest[2:]
    found = [(said, c, n) for said, c, _, n in nodes(path) if below < c[1] < above]
    for p in rest:
        loose = p.startswith("~")
        want = p[1:] if loose or p.startswith("@") else p
        for said, c, n in found:
            if p.startswith("@"):
                if want in (n.get("type") or ""):
                    print(c[0], c[1])
                    return 0
            elif any((want in s) if loose else (s == want) for s in said):
                print(c[0], c[1])
                return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

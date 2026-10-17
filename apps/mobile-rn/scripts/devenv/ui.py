#!/usr/bin/env python3
"""Finds things in a `uiautomator dump` by what they say (shots.sh): prints the centre of the first node whose text or
content-desc matches one of the patterns, else exits 1. A pattern is matched whole; `~x` is "contains x"; `@x` is a
node whose class has x in it (`@EditText`: a text field, whatever its hint says). Patterns are
tried in order, so the exact one can come before a looser one. `--list`: every node that says something, with its
bounds (what shots.sh keeps beside each screenshot). `--below Y` / `--above Y`: only nodes whose centre is there.

  ui.py <dump.xml> [--below Y] [--above Y] <pattern>...
  ui.py <dump.xml> --list
"""
import re
import sys
import xml.etree.ElementTree as ET


def nodes(path):
    try:
        root = ET.parse(path).getroot()
    except Exception:
        return
    for n in root.iter("node"):
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
        if not m:
            continue
        x0, y0, x1, y1 = map(int, m.groups())
        if x1 <= x0 or y1 <= y0:
            continue
        said = [s for s in (n.get("text", ""), n.get("content-desc", "")) if s]
        yield said, ((x0 + x1) // 2, (y0 + y1) // 2), (x0, y0, x1, y1), n


def main(argv):
    path, rest = argv[0], argv[1:]
    if rest[:1] == ["--list"]:
        for said, c, b, n in nodes(path):
            if said:
                print(f"{b} {' | '.join(said)}{' [click]' if n.get('clickable') == 'true' else ''}")
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
                if want in n.get("class", ""):
                    print(c[0], c[1])
                    return 0
            elif any((want in s) if loose else (s == want) for s in said):
                print(c[0], c[1])
                return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

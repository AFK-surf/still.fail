#!/usr/bin/env python3
"""The outsides' kinds as src/ui/hostcall.mbt numbers them (its outside_kinds) and as each host does.

  scripts/outside_kinds.py [HOST...]   (android, mac, ios, windows, web; none: every one)

hostcall.mbt: every `let outside_NAME = N` in outside_kinds as ("NAME", outside_NAME), no number twice. Each host:
every kind it names (Native.java's OUTSIDE_*, apple.h's / win.h's / android_host.c's MB_OUTSIDE_*, web/host.js's
OUTSIDE_*) one of those, by the same number; a kind told as a bare number (tell(9, …)) is not one. Exit 1 on any.
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
HOSTS = {
    "android": ["android/app/src/main/java/dev/mbui/*.java", "src/host/android_host.c", "src/host/android_*.h"],
    "mac": ["src/host/apple.h", "src/host/apple_*.h", "src/host/apple_*.m", "src/host/mac_app.m"],
    "ios": ["src/host/apple.h", "src/host/apple_*.h", "src/host/apple_*.m", "src/host/ios_app.m"],
    "windows": ["src/host/win.h", "src/host/win_*.h", "src/host/win_*.c", "src/host/win_*.cpp"],
    "web": ["web/host.js"],
}
# a kind named: OUTSIDE_X = N or MB_OUTSIDE_X = N (in a list, an enum, a const)
NAMED = re.compile(r"\b(?:MB_)?OUTSIDE_([A-Z]+)\s*=\s*(\d+)")
# a kind told as a number: the host's ways of telling one
BARE = re.compile(r"\b(?:mb_host_outside|Native\.tell|outside_cb|tell|f)\(\s*\d+\s*,")


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def files(globs):
    import glob
    out = []
    for g in globs:
        out += sorted(os.path.relpath(p, ROOT) for p in glob.glob(os.path.join(ROOT, g)))
    return sorted(set(out))


def table():
    src = read("src/ui/hostcall.mbt")
    lets = {m.group(1): int(m.group(2)) for m in re.finditer(r"^let outside_([a-z]+) = (\d+)$", src, re.M)}
    m = re.search(r"^fn outside_kinds\(\) -> Array\[\(String, Int\)\] \{\n  \[(.*?)^  \]", src, re.M | re.S)
    if not m:
        return lets, ["hostcall.mbt: no outside_kinds"]
    listed = re.findall(r'\("([a-z]+)", outside_([a-z]+)\)', m.group(1))
    bad = []
    for name, ref in listed:
        if name != ref:
            bad.append(f'hostcall.mbt: outside_kinds has ("{name}", outside_{ref})')
    names = [n for n, _ in listed]
    for n in lets:
        if n not in names:
            bad.append(f"hostcall.mbt: outside_{n} not in outside_kinds")
    seen = {}
    for n, v in lets.items():
        if v in seen:
            bad.append(f"hostcall.mbt: outside_{seen[v]} and outside_{n} both {v}")
        seen[v] = n
    return lets, bad


def host(h, kinds):
    bad = []
    for rel in files(HOSTS[h]):
        src = read(rel)
        for m in NAMED.finditer(src):
            name, n = m.group(1).lower(), int(m.group(2))
            line = src.count("\n", 0, m.start()) + 1
            if name not in kinds:
                bad.append(f"{h}: {rel}:{line}: OUTSIDE_{m.group(1)} is no kind of hostcall.mbt's")
            elif kinds[name] != n:
                bad.append(f"{h}: {rel}:{line}: OUTSIDE_{m.group(1)} = {n}, hostcall.mbt's outside_{name} is {kinds[name]}")
        for m in BARE.finditer(src):
            line = src.count("\n", 0, m.start()) + 1
            before = src[src.rfind("\n", 0, m.start()) + 1:m.start()]
            if "//" in before or before.lstrip().startswith("*"):
                continue  # (said in a comment)
            bad.append(f"{h}: {rel}:{line}: a kind told as a number ({m.group(0)}): name it")
    return bad


def main():
    hosts = sys.argv[1:] or list(HOSTS)
    for h in hosts:
        if h not in HOSTS:
            print(f"outside_kinds.py: no host {h} ({', '.join(HOSTS)})", file=sys.stderr)
            return 1
    kinds, bad = table()
    for h in hosts:
        bad += host(h, kinds)
    for b in bad:
        print(b)
    if bad:
        return 1
    print(f"outside kinds: {len(kinds)} in hostcall.mbt, each its own; {', '.join(hosts)} the same")
    return 0


if __name__ == "__main__":
    sys.exit(main())

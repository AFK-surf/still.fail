#!/usr/bin/env python3
"""The renderers' corners from one copy (src/host/corner.sl, src/ui/smooth.mbt's in the shaders' words).

  scripts/corner_sl.py           writes src/host/corner_sl.h (MB_CORNER_SL, a C string the Metal, Direct3D and Android
                                 GL shaders take in) and web/host.js's lines between its "corner.sl" marks
  scripts/corner_sl.py --check   says which of them is not what corner.sl makes, and fails (CI's test job)
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src/host/corner.sl"
HEADER = ROOT / "src/host/corner_sl.h"
WEB = ROOT / "web/host.js"
BEGIN = "// corner.sl begin (scripts/corner_sl.py: not edited here)"
END = "// corner.sl end"


def header(lines):
    out = [
        "// src/host/corner.sl as a C string (scripts/corner_sl.py makes it: edit corner.sl, then run it). The shaders",
        "// write float2; GLSL's take it with `#define float2 vec2` before it.",
        "#define MB_CORNER_SL \\",
    ]
    for l in lines:
        esc = l.replace("\\", "\\\\").replace('"', '\\"')
        out.append(f'  "{esc}\\n" \\')
    out.append('  ""')
    return "\n".join(out) + "\n"


def web(text, lines):
    a = text.index(BEGIN)
    b = text.index(END, a)
    start = text.rindex("\n", 0, a) + 1
    indent = text[start:a]
    body = "".join(indent + l + "\n" if l else "\n" for l in lines)
    return text[: a + len(BEGIN)] + "\n" + indent + "#define float2 vec2\n" + body + indent + text[b:]


def main():
    lines = SRC.read_text().rstrip("\n").split("\n")
    # (web/host.js holds it in a template literal: no backquote, no ${)
    bad = [i + 1 for i, l in enumerate(lines) if "`" in l or "${" in l]
    if bad:
        print(f"src/host/corner.sl: a backquote or ${{ on line {bad[0]}, which would end web/host.js's shader")
        sys.exit(1)
    want_h = header(lines)
    js = WEB.read_text()
    want_js = web(js, lines)
    if "--check" in sys.argv:
        bad = []
        if not HEADER.exists() or HEADER.read_text() != want_h:
            bad.append(str(HEADER.relative_to(ROOT)))
        if js != want_js:
            bad.append(str(WEB.relative_to(ROOT)))
        if bad:
            print("not what src/host/corner.sl makes (run scripts/corner_sl.py): " + ", ".join(bad))
            sys.exit(1)
        print("corner.sl: the renderers' copies are its")
        return
    HEADER.write_text(want_h)
    WEB.write_text(want_js)


main()

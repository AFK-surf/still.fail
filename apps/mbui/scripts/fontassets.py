#!/usr/bin/env python3
"""The fonts the app carries in itself, as the Android app packs them into its resources: src/sf/font_assets.mbt holds,
as its bytes (a Bytes literal: kept as they are, not in base64 nor UTF-16), apps/android/shared/src/main/res/font/
jetbrains_mono.ttf (JetBrains Mono, variable: the code face, as Android's Theme.kt JetBrainsMono; SIL Open Font
License), given to the hosts as the app starts (@sf.give_faces).

  python3 scripts/fontassets.py          the file written
  python3 scripts/fontassets.py --check  fails (saying so) when it is not what the font makes (scripts/check.sh)"""
import os, sys

A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(A))
FONTS = [("code_face_ttf", "apps/android/shared/src/main/res/font/jetbrains_mono.ttf")]
OUT = os.path.join(A, "src/sf/font_assets.mbt")


def literal(b):
    """A MoonBit Bytes literal's inside: printable ASCII as it is, the rest escaped."""
    return "".join(chr(c) if 0x20 <= c < 0x7F and c not in (0x22, 0x5C) else "\\x%02x" % c for c in b)


def made():
    out = ["// Made by scripts/fontassets.py from the Android app's own fonts (do not edit: run it again when they change).", ""]
    for name, rel in FONTS:
        with open(os.path.join(ROOT, rel), "rb") as f:
            data = f.read()
        out.append("///|")
        out.append(f"/// {rel}, its bytes.")
        out.append("// kept across runs: a file's bytes, never written")
        out.append(f'let {name} : Bytes = b"{literal(data)}"')
        out.append("")
    return "\n".join(out)


text = made()
if "--check" in sys.argv:
    with open(OUT, encoding="utf-8") as f:
        if f.read() != text:
            sys.exit("src/sf/font_assets.mbt is not what the fonts make: python3 scripts/fontassets.py")
else:
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)

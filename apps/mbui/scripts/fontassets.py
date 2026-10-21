#!/usr/bin/env python3
"""The fonts the app carries in itself, as the Android app packs them into its resources: src/sf/font_assets.mbt holds,
in base64, apps/android/shared/src/main/res/font/jetbrains_mono.ttf (JetBrains Mono, variable: the code face, as
Android's Theme.kt JetBrainsMono; SIL Open Font License), given to the hosts as the app starts (@sf.give_faces).

  python3 scripts/fontassets.py          the file written
  python3 scripts/fontassets.py --check  fails (saying so) when it is not what the font makes (scripts/check.sh)"""
import base64, os, sys

A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(A))
FONTS = [("code_face_b64", "apps/android/shared/src/main/res/font/jetbrains_mono.ttf")]
OUT = os.path.join(A, "src/sf/font_assets.mbt")


def made():
    out = ["// Made by scripts/fontassets.py from the Android app's own fonts (do not edit: run it again when they change).", ""]
    for name, rel in FONTS:
        with open(os.path.join(ROOT, rel), "rb") as f:
            b64 = base64.b64encode(f.read()).decode()
        out.append("///|")
        out.append(f"/// {rel}, in base64 (lines of 120).")
        out.append("// kept across runs: a file's bytes, never written")
        out.append(f"let {name} : String =")
        for i in range(0, len(b64), 120):
            out.append("  #|" + b64[i:i + 120])
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

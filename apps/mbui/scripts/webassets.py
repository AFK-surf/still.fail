#!/usr/bin/env python3
"""The web's own files a page of the app's carries, as the Android app packs them into its assets:
src/sfapp/web_assets.mbt holds, as strings,
  viz_css     web/src/viz/ember-viz.css   (a visualization's stylesheet: ui/Viz.kt documentOf)
  viz_bridge  web/src/viz/bridge.js       (its bridge: its height, what its widget keeps, words to send)
  page_js     apps/android/app/src/main/assets/preview/page.js (first in each page of a service's preview:
              its WebSockets, its requests' bodies and fetches, marking it; PreviewWeb.kt)

  python3 scripts/webassets.py          the file written
  python3 scripts/webassets.py --check  fails (saying so) when it is not what they make (scripts/check.sh)"""
import os, sys

A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(A))
FILES = [
    ("viz_css", "web/src/viz/ember-viz.css"),
    ("viz_bridge", "web/src/viz/bridge.js"),
    ("page_js", "apps/android/app/src/main/assets/preview/page.js"),
]
OUT = os.path.join(A, "src/sfapp/web_assets.mbt")


def made():
    out = ["// Made by scripts/webassets.py from the web's own files (do not edit: run it again when they change).", ""]
    for name, rel in FILES:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            text = f.read()
        if text.endswith("\n"):
            text = text[:-1]
        out.append("///|")
        out.append(f"/// {rel}, as it is.")
        out.append("// kept across runs: a file's words, never written")
        out.append(f"let {name} : String =")
        for line in text.split("\n"):
            out.append("  #|" + line)
        out.append("")
    return "\n".join(out)


text = made()
if "--check" in sys.argv:
    have = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
    if have != text:
        print("src/sfapp/web_assets.mbt is not what the web's files make: python3 apps/mbui/scripts/webassets.py")
        sys.exit(1)
else:
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)

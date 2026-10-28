#!/usr/bin/env python3
"""The web's own files a page of the app's carries (both frames'):
src/sfbase/web_assets.mbt holds, as strings,
  viz_css     web/src/viz/ember-viz.css   (a visualization's stylesheet: ui/Viz.kt documentOf)
  viz_bridge  web/src/viz/bridge.js       (its bridge: its height, what its widget keeps, words to send)
  viz_components web/src/viz/components.js (still.fail's <sf-…> elements a figure is written with)
  viz_icons   design/icons/*.svg          (still.fail's own icons for a visualization's data-icon marks: each SVG's
              inside, by name, as JSON, as Viz.tsx gives them)
  page_js     apps/mbui/assets/preview/page.js (first in each page of a service's preview: its WebSockets, its
              requests' bodies and fetches, marking it)

  python3 scripts/webassets.py          the file written
  python3 scripts/webassets.py --check  fails (saying so) when it is not what they make (scripts/check.sh)"""
import json, os, re, sys

A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(A))
FILES = [
    ("viz_css", "web/src/viz/ember-viz.css"),
    ("viz_bridge", "web/src/viz/bridge.js"),
    ("viz_components", "web/src/viz/components.js"),
    ("page_js", "apps/mbui/assets/preview/page.js"),
]
OUT = os.path.join(A, "src/sfbase/web_assets.mbt")


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
        out.append(f"pub let {name} : String =")
        for line in text.split("\n"):
            out.append("  #|" + line)
        out.append("")
    icons = {}
    folder = os.path.join(ROOT, "design/icons")
    for f in sorted(os.listdir(folder)):
        if f.endswith(".svg"):
            svg = open(os.path.join(folder, f), encoding="utf-8").read()
            inside = re.search(r"<svg[^>]*>([\s\S]*)</svg>", svg)
            icons[f[:-4]] = re.sub(r"\s+", " ", inside.group(1) if inside else "").strip()
    out.append("///|")
    out.append("/// design/icons/*.svg: each one's inside, by its name, as JSON (for a <script> element: no `<`).")
    out.append("// kept across runs: a file's words, never written")
    out.append("pub let viz_icons : String =")
    out.append("  #|" + json.dumps(icons, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c"))
    out.append("")
    return "\n".join(out)


text = made()
if "--check" in sys.argv:
    have = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
    if have != text:
        print("src/sfbase/web_assets.mbt is not what the web's files make: python3 apps/mbui/scripts/webassets.py")
        sys.exit(1)
else:
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)

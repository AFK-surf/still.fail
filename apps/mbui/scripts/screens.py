#!/usr/bin/env python3
"""The Mac host's text as sffix recorded it for each screen (MBUI_TEXT_RECORD=1: TEXTREC lines on its log) and the
frames it drew (MBUI_DRAW_LOG=1: their DRAWHASH lines), kept in screens/text-mac.textrec, a section a screen:

  # MODE FRAME TIME WIDTH HEIGHT SCALE HASH STABLE      (the DRAWHASH line of the frame its picture is of)
  {"m":…}                                              (its TEXTREC lines, as the run said them)
  DRAWHASH FRAME TIME …                                (each frame it drew, in its place among them: when it drew
                                                       them, what a screen's Tester draws its frames at)

src/sfscreens embeds it (moon.pkg's pre-build) and gives each screen's Tester its own section: a run's glyphs are
numbered in the order it met them (and placed in its atlas so), so each screen keeps its own run's.

  scripts/screens.py keep MODE LOG     LOG's lines kept as MODE's section (scripts/screens.sh rec)
"""
import os, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
kept = f"{root}/screens/text-mac.textrec"


def sections():
    out, mode = {}, None
    if os.path.exists(kept):
        for line in open(kept, encoding="utf-8").read().split("\n"):
            if line.startswith("# "):
                mode = line[2:].split(" ", 1)[0]
                out[mode] = [line]
            elif line and mode:
                out[mode].append(line)
    return out


def keep_log(mode, log):
    rec, last = [], None
    for line in open(log, encoding="utf-8", errors="replace"):
        i = line.find("TEXTREC ")
        if i >= 0:
            rec.append(line[i + 8:].rstrip("\n"))
            continue
        i = line.find("DRAWHASH ")
        if i >= 0:
            last = line[i + 9:].split()
            rec.append("DRAWHASH " + " ".join(last))
    if not rec:
        sys.exit(f"screens.py: no TEXTREC lines in {log} (MBUI_TEXT_RECORD=1?)")
    if not last:
        sys.exit(f"screens.py: no DRAWHASH lines in {log} (MBUI_DRAW_LOG=1?)")
    s = sections()
    s[mode] = [f"# {mode} " + " ".join(last)] + rec
    os.makedirs(os.path.dirname(kept), exist_ok=True)
    with open(kept, "w", encoding="utf-8") as f:
        for m in sorted(s):
            f.write("\n".join(s[m]) + "\n")
    print(f"{mode}: {len(rec)} lines of text, frame {last[0]} hash {last[5]}")


if sys.argv[1:2] == ["keep"] and len(sys.argv) == 4:
    keep_log(sys.argv[2], sys.argv[3])
else:
    sys.exit(__doc__)

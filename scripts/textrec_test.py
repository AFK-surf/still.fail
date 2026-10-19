#!/usr/bin/env python3
"""A real host's run (MBUI_TEXT_RECORD=1 MBUI_DRAW_LOG=1: TEXTREC and DRAWHASH lines on its log) made a test of
whether a Tester over the host's kept text draws, frame for frame, what the host drew: src/kitdemo/textrec_NAME_wbtest.mbt.

  scripts/textrec_test.py LOG NAME PAGE W H
"""
import sys
log, name, page, w, h = sys.argv[1:6]
lines = [l.rstrip("\n") for l in open(log, encoding="utf-8")]
first = next(l[l.index("DRAWHASH"):].split() for l in lines if "DRAWHASH " in l)
t0, scale, stable = first[2], first[5], "true" if len(first) > 7 and first[7] == "1" else "false"
if "." not in scale:
    scale += ".0"
if "." not in t0:
    t0 += ".0"
keep = [l[l.index("TEXTREC"):] for l in lines if "TEXTREC " in l] + [l[l.index("DRAWHASH"):] for l in lines if "DRAWHASH " in l]
out = [f"// Kept from a real host's run ({name}: MBUI_TEXT_RECORD=1 MBUI_DRAW_LOG=1 MBUI_SCREEN={page} MBUI_WIN={w}x{h}),",
       "// made by scripts/textrec_test.py: not edited by hand.", "", "///|", f"let run_{name} : String ="]
out += ["  #|" + l for l in keep]
out += ["", "///|",
        f'test "the {page} page under a Tester over {name}\'s kept text draws, frame for frame, what it drew" {{',
        f'  let t = @ui.Tester::new(fn(c) {{ gallery(c, "{page}") }}, w={w}.0, h={h}.0, text=run_{name}, scale={scale}, time={t0} - 16.0, stable={stable})',
        f"  let frames = t.replay_frames(run_{name})",
        "  let apart = frames.filter(fn(f) { f.1 != f.2 })",
        '  println("frames \\{frames.length()}, apart \\{apart.length()}, text missing \\{t.text_missing()}")',
        "  if apart.length() > 0 {",
        '    println("first apart: frame \\{apart[0].0}")',
        "    for line in t.drawn_text().split(\"\\n\") {",
        '      println("TDUMP " + line.to_owned())',
        "    }",
        "  }",
        "  assert_true(frames.length() > 0)",
        "  assert_eq(t.text_missing(), [])",
        "  assert_eq(apart.length(), 0)",
        "}"]
open(f"src/kitdemo/textrec_{name}_wbtest.mbt", "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"{len(keep)} lines")

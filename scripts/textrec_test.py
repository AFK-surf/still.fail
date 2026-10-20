#!/usr/bin/env python3
"""A real host's run (MBUI_TEXT_RECORD=1 MBUI_DRAW_LOG=1: TEXTREC, DRAWHASH, INPUT and ENV lines on its log) made a test of
whether a Tester over the host's kept text draws, frame for frame, what the host drew (the host's contract,
docs/determinism.md): the run kept as src/kitdemo/textrec_NAME.mbt, its test src/kitdemo/textrec_NAME_wbtest.mbt, and
src/kitdemo/textrec_runs.mbt naming every kept run (what MBUI_TEXTCHECK=NAME asks the host's text system again: the
text's contract, src/kitdemo/textcheck.mbt).

  scripts/textrec_test.py LOG NAME PAGE W H [PLATFORM]

W H "-": the window's size at the run's first frame (its DRAWHASH line).

PLATFORM is the host's as @host.platform has it (0 macOS, 1 iOS, 2 Android, 3 Windows, 4 the web; 0 by default).
"""
import glob
import re
import os
import sys

KIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "kitdemo")


def runs_file():
    """src/kitdemo/textrec_runs.mbt: every run kept in src/kitdemo (textrec_NAME.mbt), by its name."""
    names = sorted(
        os.path.basename(p)[len("textrec_"):-len(".mbt")]
        for p in glob.glob(os.path.join(KIT, "textrec_*.mbt"))
        if not p.endswith("_wbtest.mbt") and not p.endswith("textrec_runs.mbt"))
    out = ["// Every run kept in this package (textrec_NAME.mbt), by its name: what MBUI_TEXTCHECK=NAME asks the host's",
           "// text system again (textcheck.mbt). Made by scripts/textrec_test.py: not edited by hand.", "", "///|",
           "fn kept_run(name : String) -> String? {", "  match name {"]
    out += [f'    "{n}" => Some(run_{n})' for n in names]
    out += ["    _ => None", "  }", "}"]
    open(os.path.join(KIT, "textrec_runs.mbt"), "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")


def num(x):
    """A number of the log as a MoonBit Double literal."""
    return x if "." in x or "e" in x or "inf" in x else x + ".0"


def main():
    log, name, page, w, h = sys.argv[1:6]
    platform = sys.argv[6] if len(sys.argv) > 6 else "0"
    lines = [l.rstrip("\r\n") for l in open(log, encoding="utf-8", errors="replace")]
    first = next(l[l.index("DRAWHASH"):].split() for l in lines if "DRAWHASH " in l)
    t0, scale, stable = first[2], first[5], "true" if len(first) > 7 and first[7] == "1" else "false"
    if w == "-":
        w, h = first[3], first[4]
    size = f"{w}x{h}"
    w, h, scale, t0 = (num(x) for x in (w, h, scale, t0))

    def tail(l, w):
        return l[l.index(w):]

    # the host's text, then its frames, the inputs between them and the system's settings (ENV) in the order they came
    def frame_line(l):
        for w in ("DRAWHASH ", "INPUT "):
            if w in l and "TEXTREC " not in l:
                return tail(l, w)
        m = re.search(r"(^|[\s:])(ENV \{.*)", l)
        return m.group(2) if m and "TEXTREC " not in l else None

    keep = [tail(l, "TEXTREC") for l in lines if "TEXTREC " in l] + [
        k for k in (frame_line(l) for l in lines) if k is not None]
    how = f"{name}: MBUI_TEXT_RECORD=1 MBUI_DRAW_LOG=1 MBUI_SCREEN={page} MBUI_WIN={size}, platform {platform}"
    data = [f"// Kept from a real host's run ({how}),",
            "// made by scripts/textrec_test.py: not edited by hand.", "", "///|", f"let run_{name} : String ="]
    data += ["  #|" + l for l in keep]
    plat = f", platform={platform}" if platform != "0" else ""
    test = [f"// A Tester over {name}'s kept text and frames (textrec_{name}.mbt), made by scripts/textrec_test.py.", "",
            "///|",
            f'test "the {page} page under a Tester over {name}\'s kept text draws, frame for frame, what it drew" {{',
            "  reset()",
            f'  let t = @ui.Tester::new(fn(c) {{ gallery(c, "{page}") }}, w={w}, h={h}, text=run_{name}, run=run_{name}, scale={scale}, time={t0} - 16.0, stable={stable}{plat})',
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
    open(os.path.join(KIT, f"textrec_{name}.mbt"), "w", encoding="utf-8", newline="\n").write("\n".join(data) + "\n")
    open(os.path.join(KIT, f"textrec_{name}_wbtest.mbt"), "w", encoding="utf-8", newline="\n").write("\n".join(test) + "\n")
    runs_file()
    print(f"{len(keep)} lines")


if __name__ == "__main__":
    if sys.argv[1:] == ["--runs"]:
        runs_file()
    else:
        main()

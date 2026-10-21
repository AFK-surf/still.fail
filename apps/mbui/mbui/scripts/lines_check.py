#!/usr/bin/env python3
# Whether a renderer draws lines (scene.mbt's kind 10) as they are: the picture of src/kitdemo/dl_print_wbtest.mbt's
# lines_shown (160 by 160 at scale 2, on white) drawn by it. Its horizontal line is the same as the rounded rect of the
# same shape drawn 40 under it (each pixel's channels within TOL), its slanted line and its arc are inked along their
# middles and not off them, and its half drawn line ends halfway.
#
#   lines_check.py PNG      exit 0, saying what it found; else 1, saying what is wrong where
import math, os, sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gallery_shot import pixels  # noqa: E402

TOL = 3
S = 2  # the picture's scale


def main(path):
    w, h, bpp, rows = pixels(path)
    if (w, h) != (160 * S, 160 * S):
        return f"{path}: {w}x{h}, not {160 * S}x{160 * S}"
    pxl = lambda x, y: tuple(rows[y][x * bpp:x * bpp + 3])
    at = lambda x, y: pxl(int(x * S), int(y * S))
    bad = []
    # the line against the rounded rect 40 under it, row by row over the band they are in
    worst = 0
    for y in range(12 * S, 28 * S):
        for x in range(0, 160 * S):
            a, b = pxl(x, y), pxl(x, y + 40 * S)
            worst = max(worst, max(abs(a[i] - b[i]) for i in range(3)))
    if worst > TOL:
        bad.append(f"the line 8 wide is not the rounded rect of its shape: a channel {worst} apart (at most {TOL})")
    blue, white = (0x15, 0x59, 0xC4), (0xFF, 0xFF, 0xFF)
    near = lambda c, want: max(abs(c[i] - want[i]) for i in range(3)) <= TOL
    # the slanted line, (20, 90) to (60, 130), 6 wide: inked along its middle, white 5 off it on either side
    for k in range(1, 10):
        x, y = 20 + 4 * k, 90 + 4 * k
        if not near(at(x + 0.25, y + 0.25), blue):
            bad.append(f"the slanted line is not inked at ({x}, {y}): {at(x, y)}")
        for s in (1, -1):
            if not near(at(x + s * 5 * 0.7071 + 0.25, y - s * 5 * 0.7071 + 0.25), white):
                bad.append(f"the slanted line is inked 5 off its middle at ({x}, {y})")
    # the arc about (120, 120), radius 20, 3 wide, from 3 o'clock through 6, 9 to 12: inked on the circle there, not in
    # the quarter it leaves out, nor at its middle
    for deg in (20, 90, 160, 200, 250):
        a = math.radians(deg)
        x, y = 120 + 20 * math.cos(a), 120 + 20 * math.sin(a)
        if not near(at(x, y), blue):
            bad.append(f"the arc is not inked at {deg}°: {at(x, y)}")
    a = math.radians(315)
    if not near(at(120 + 20 * math.cos(a), 120 + 20 * math.sin(a)), white):
        bad.append("the arc is inked in the quarter it leaves out (315°)")
    if not near(at(120, 120), white):
        bad.append("the arc's middle is inked")
    # the half drawn line, (20, 150) to (80, 150) of (140, 150)
    if not near(at(50, 150), blue):
        bad.append("the half drawn line is not inked halfway along what is drawn of it")
    if not near(at(90, 150), white) or not near(at(130, 150), white):
        bad.append("the half drawn line is inked past its half")
    if bad:
        return f"{path}:\n  " + "\n  ".join(bad)
    print(f"lines check: {path}: the line is the rounded rect of its shape (a channel {worst} apart at most), the "
          "slanted line, the arc and the half line drawn where they are")
    return None


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("lines_check.py PNG")
    err = main(sys.argv[1])
    if err:
        print(f"lines check: {err}")
        sys.exit(1)

#!/usr/bin/env python3
"""The numbers in a decision's option circles (design/icons/option-1…6.svg): Inter SemiBold's digits, as the web draws
type, taken out of the font and centred on their ink. Text in a circle sits wherever its line box puts it, a little high
for Inter's figures, then snapped to the pixel; a path drawn in the circle's own box sits where it is put. The icon is
the circle's size (20 of 24 units around a 13.2-unit digit: 11px type in a 20px circle). Then scripts/icons.py.

Needs fontTools (pip install fonttools brotli) and the web's node_modules (@fontsource-variable/inter)."""
import glob
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parent.parent
FONT = "node_modules/.pnpm/@fontsource-variable+inter*/node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2"
SIZE = 11 * 24 / 20


def fmt(v: float) -> str:
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def main():
    font = instantiateVariableFont(TTFont(glob.glob(str(ROOT / FONT))[0]), {"wght": 600})
    glyphs, cmap, upm = font.getGlyphSet(), font.getBestCmap(), font["head"].unitsPerEm
    s = SIZE / upm
    for n in range(1, 7):
        glyph = glyphs[cmap[ord(str(n))]]
        bounds = BoundsPen(glyphs)
        glyph.draw(bounds)
        x0, y0, x1, y1 = bounds.bounds
        pen = SVGPathPen(glyphs, ntos=fmt)
        glyph.draw(TransformPen(pen, (s, 0, 0, -s, 12 - (x0 + x1) / 2 * s, 12 + (y0 + y1) / 2 * s)))
        (ROOT / f"design/icons/option-{n}.svg").write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">\n'
            f'  <!-- Inter SemiBold {n}, centred on its ink: scripts/option-digits.py -->\n'
            f'  <path fill="currentColor" stroke="none" d="{pen.getCommands()}"/>\n'
            "</svg>\n")


if __name__ == "__main__":
    main()

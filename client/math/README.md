# Local formula drawings

Each client's core reads TeX with MathJax and its TeX font. The network still carries Markdown source; the local
UI bridge carries `MathDrawing` (1000 units per em, top-left origin, y down): alphabet version, dimensions,
baseline, glyph IDs and placements, rectangles, and native text for characters outside the alphabet. UI code
never runs a TeX parser or a WebView. Invalid/unsupported formulas retain their source; selection and
accessibility use that same source.

The font is split by who uses which half. The core lays formulas out with the glyphs' sizes alone
(`client/core-ts/src/math-font.ts`: MathJax's TeX font tables, each outline replaced by its ID), so its bundle
carries no outline; MathJax's default font (New Computer Modern), which its SVG output imports regardless, is
replaced by nothing (`client/core-ts/pnpm-workspace.yaml` overrides, `no-default-font`). The UIs hold the outlines,
each once: `font.json` (IDs hash an outline; the generator rejects collisions) for the web, which loads it with its
drawing component, and the frozen Android app, which packages it as an asset; mbui embeds them packed
(`apps/mbui/src/sf/math_glyphs.mbt`: commands and delta-coded whole coordinates, gzipped), unpacked on its first
formula and read by ID. It is never repeated in a message. The core and UI caches account for the drawing/expanded
geometry as well as its shorter source.

Generate with `cd client/core-ts && node scripts/math-font.ts`; `--check` verifies all three.
The alphabet derives from `@mathjax/mathjax-tex-font` 4.1.3, part of MathJax, licensed under Apache 2.0 (LICENSE).

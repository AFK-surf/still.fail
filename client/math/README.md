# Local formula drawings

Each client's core reads TeX with MathJax and its TeX font. The network still carries Markdown source; the local
UI bridge carries `MathDrawing` (1000 units per em, top-left origin, y down): alphabet version, dimensions,
baseline, glyph IDs and placements, rectangles, and native text for characters outside the alphabet. UI code
never runs a TeX parser or a WebView. Invalid/unsupported formulas retain their source; selection and
accessibility use that same source.

`font.json` is the fixed alphabet included once in each client. IDs hash an outline; the generator rejects
collisions. Web loads it with its drawing component, Android packages it as an asset, and mbui embeds the same
bytes for Android/iOS/desktop GPU drawing. It is never repeated in a message. The core and UI caches account for
the drawing/expanded geometry as well as its shorter source.

Generate with `cd client/core-ts && node scripts/math-font.ts`; `--check` verifies both packaged copies.
The alphabet derives from `@mathjax/mathjax-tex-font` 4.1.3, part of MathJax, licensed under Apache 2.0 (LICENSE).

// The core's typeset formula, in 1000 units per em, from its top left (y down). Glyphs refer to client/math/font.json,
// bundled once with each UI. Neither outlines nor a font are repeated in messages or across the local UI bridge.
export interface MathDrawing {
  font: "tex-4.1.3";
  width: number;
  height: number;
  baseline: number;
  draw: [glyph: string, sx: number, sy: number, x: number, y: number][];
  rects: [x: number, y: number, width: number, height: number][];
  // Characters outside the bundled math alphabet use native text at the given baseline.
  text: [words: string, sx: number, sy: number, x: number, y: number][];
}

// Content-addressed outlines: IDs are independent of font traversal order. The generator rejects collisions.
export function mathGlyphId(path: string): string {
  let h = 2166136261;
  for (let i = 0; i < path.length; i++) h = Math.imul(h ^ path.charCodeAt(i), 16777619);
  return (h >>> 0).toString(16);
}

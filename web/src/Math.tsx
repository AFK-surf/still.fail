// A formula already parsed and laid out by the core. SVG is just this client's drawing surface, the same paths and
// positions that native clients paint on their canvases. The source remains text for copying and accessibility.
import { memo } from "react";
import type { MathDrawing } from "../../client/core-ts/src/mathDrawing.ts";
import font from "../../client/math/font.json";
import * as css from "./Prose.css.ts";

export const Formula = memo(function Formula({ text, drawing }: { text: string; drawing?: MathDrawing | null | undefined }) {
  const glyphs: Record<string, string> = font.glyphs;
  if (!drawing || drawing.font !== font.version || drawing.draw.some(([id]) => !glyphs[id])) return <code>{text}</code>;
  const { width, height, baseline, draw, rects, text: words } = drawing;
  return <span className={css.formula} role="math" aria-label={text} style={{ width: `${width / 1000}em`, height: `${height / 1000}em`, verticalAlign: `${(baseline - height) / 1000}em` }}>
    <span className={css.formulaSource} aria-hidden="true">{text}</span>
    <svg viewBox={`0 0 ${width} ${height}`} width="100%" height="100%" fill="currentColor" aria-hidden="true" focusable="false">
      {draw.map(([id, sx, sy, x, y], i) => <path key={i} d={glyphs[id]} transform={`translate(${x} ${y}) scale(${sx} ${sy})`} />)}
      {rects.map(([x, y, w, h], i) => <rect key={i} x={x} y={y} width={w} height={h} />)}
      {words.map(([word, sx, sy, x, y], i) => <text key={i} fontSize="1000" fontFamily="serif" transform={`translate(${x} ${y}) scale(${sx} ${sy})`}>{word}</text>)}
    </svg>
  </span>;
});

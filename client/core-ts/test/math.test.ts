import assert from "node:assert/strict";
import test from "node:test";
import { mathDrawing } from "../src/math.ts";
import { readFileSync } from "node:fs";
const font = JSON.parse(readFileSync(new URL("../../math/font.json", import.meta.url), "utf8")) as { glyphs: Record<string, string> };

test("formulas reference the packaged alphabet without carrying outlines or fetching fonts", () => {
  for (const tex of ["E=mc^2", String.raw`\frac{-b\pm\sqrt{b^2-4ac}}{2a}`, String.raw`\begin{pmatrix}a&b\\c&d\end{pmatrix}`, String.raw`\sum_{k=0}^n x_k`, String.raw`\left(\frac{1}{\sqrt{x}}\right)`, String.raw`\mathbb{R}\mathbf{A}\mathcal{L}\boldsymbol{\alpha}\hat{x}\vec{y}`, String.raw`\underbrace{\mathbb{E}[Y_7 \mid x]}_{\text{expected seven-day attributed revenue}}`]) {
    const drawing = mathDrawing(tex, false);
    assert(drawing, tex);
    assert(drawing.width > 0 && drawing.height > 0 && drawing.baseline > 0, tex);
    assert(drawing.draw.length > 0, tex);
    assert(!JSON.stringify(drawing).includes("<"));
    assert(drawing.draw.every(([p, ...move]) => font.glyphs[p] !== undefined && move.every(Number.isFinite)), tex);
    assert(!("paths" in drawing), "outlines are never sent with a formula");
  }
  const d = mathDrawing("xxx", false)!;
  assert.equal(new Set(d.draw.map(([id]) => id)).size, 1, "a repeated glyph uses the same packaged outline");
  assert.equal(d.draw.length, 3);
  assert.equal(mathDrawing("xxx", false), d);
});

test("inline formulas are one drawing, display fractions have their own layout", () => {
  const whole = mathDrawing("E=mc^2", false)!;
  assert(whole.draw.length >= 5, "all terms, including the terms after an equality, are carried");
  const a = mathDrawing(String.raw`\frac{1}{2}`, false)!;
  const b = mathDrawing(String.raw`\frac{1}{2}`, true)!;
  assert(b.height > a.height);
});

test("macros cannot leak between messages; invalid and recursive TeX stay source", () => {
  assert(mathDrawing(String.raw`\def\mine{x}\mine`, false));
  assert.equal(mathDrawing(String.raw`\mine`, false), null);
  assert.equal(mathDrawing(String.raw`\frac{`, false), null);
  assert.equal(mathDrawing(String.raw`\def\again{\again}\again`, false), null);
  assert.equal(mathDrawing(String.raw`\require{html}\href{https://example.test}{x}`, false), null);
});

test("non-math text has positioned native text, and TeX preserves its baseline", () => {
  const drawing = mathDrawing(String.raw`a+\text{你好}`, false)!;
  assert(drawing);
  assert.equal(drawing.text[0]?.[0], "你好");
  assert.equal(drawing.text[0]?.[4], drawing.baseline);
});

// A command's output in a terminal's colours (the core's `TermRun`s, client/core-ts/src/terminal.ts): the 16 colours
// from a palette for each theme (VS Code's terminal's, the darkest made readable on a dark page), the rest as said.
import type { CSSProperties, ReactNode } from "react";
import type { TermRun } from "./core/shapes.ts";

const PALETTE: [light: string, dark: string][] = [
  ["#000000", "#6e6e6e"], ["#cd3131", "#cd3131"], ["#00bc00", "#0dbc79"], ["#949800", "#e5e510"],
  ["#0451a5", "#2472c8"], ["#bc05bc", "#bc3fbc"], ["#0598bc", "#11a8cd"], ["#555555", "#e5e5e5"],
  ["#666666", "#8a8a8a"], ["#cd3131", "#f14c4c"], ["#14ce14", "#23d18b"], ["#b5ba00", "#f5f543"],
  ["#0451a5", "#3b8eea"], ["#bc05bc", "#d670d6"], ["#0598bc", "#29b8db"], ["#a5a5a5", "#e5e5e5"],
];

function color(c: string | undefined): string | undefined {
  if (c === undefined || c.startsWith("#")) return c;
  const pair = PALETTE[Number(c)];
  return pair && `light-dark(${pair[0]}, ${pair[1]})`;
}

/** `runs` as spans in their styles, or `text` alone when none is styled. */
export function TermText({ text, runs }: { text: string; runs?: TermRun[] | undefined }): ReactNode {
  if (!runs) return text;
  return runs.map((r, i) => {
    const style: CSSProperties = {
      color: color(r.fg), background: color(r.bg),
      fontWeight: r.bold ? 600 : undefined, opacity: r.dim ? 0.6 : undefined,
      fontStyle: r.italic ? "italic" : undefined, textDecoration: r.underline ? "underline" : undefined,
    };
    return Object.values(style).some((v) => v !== undefined) ? <span key={i} style={style}>{r.text}</span> : r.text;
  });
}

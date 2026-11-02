// A simulator's screen as Apple draws it: its device type's framebuffer masks (a PDF for each of its panels, an iPhone
// Duo's two), read for what the app's device body goes round. Each corner comes from its edge: the path's point on the
// top and bottom edges nearest the corner, as a share of the panel's width (a Duo's cover is nearly square on its hinge).
import { inflateSync } from "node:zlib";

export type Panel = { width: number; height: number; corners: [number, number, number, number] };

/// The panel a mask's PDF says, its corners top left and then round it; null when it is not such a mask.
export function panelOf(pdf: Buffer): Panel | null {
  const text = pdf.toString("latin1");
  const box = /\/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]/.exec(text);
  const start = /stream\r?\n/.exec(text);
  const end = text.indexOf("endstream");
  if (!box || !start || end < 0) return null;
  const [width, height] = [Number(box[1]), Number(box[2])];
  const body = pdf.subarray(start.index + start[0].length, end);
  let path: string;
  try {
    path = inflateSync(body).toString("latin1");
  } catch {
    path = body.toString("latin1");
  }
  // The shape is the first subpath with curves: a clip round the page before it has none, and it may be a clip itself.
  let points: [number, number][] = [];
  let curved = false;
  const said: number[] = [];
  for (const word of path.split(/\s+/)) {
    const n = Number(word);
    if (word !== "" && !Number.isNaN(n)) {
      said.push(n);
      continue;
    }
    if (word === "m") {
      if (curved) break;
      points = [];
    }
    if (word === "c") curved = true;
    if ((word === "m" || word === "l" || word === "c") && said.length >= 2) points.push([said.at(-2)!, said.at(-1)!]);
    said.length = 0;
  }
  if (!curved) return null;
  const along = (y: number) => points.filter(([px, py]) => Math.abs(py - y) < 0.01 && px >= 0 && px <= width).map(([px]) => px);
  const [top, bottom] = [along(height), along(0)];
  if (top.length === 0 || bottom.length === 0) return null;
  const share = (v: number) => Math.round((v / width) * 10_000) / 10_000;
  return {
    width,
    height,
    corners: [share(Math.min(...top)), share(width - Math.max(...top)), share(width - Math.max(...bottom)), share(Math.min(...bottom))],
  };
}

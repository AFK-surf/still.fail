// The hand-drawn strokes under words found in a message (`[data-search-marks]`, global.css.ts): under the words a
// search opened the message for (Chat.tsx markWords), and under what a chat's find found (ChatFind.tsx).

/** A layer for strokes over `root` (its box, so they move with it), appended to it. */
export function strokeLayer(root: HTMLElement): HTMLElement {
  const layer = document.createElement("span");
  layer.dataset.searchMarks = "";
  layer.setAttribute("aria-hidden", "true");
  if (getComputedStyle(root).position === "static") root.style.position = "relative";
  root.append(layer);
  return layer;
}

/** The strokes under `ranges`, where they are in `root` now, in its layer: one a line of each range. `each` is told a
 *  stroke and the range it is of. */
export function placeStrokes(layer: HTMLElement, root: HTMLElement, ranges: Range[], each?: (svg: SVGSVGElement, range: Range, n: number) => void): void {
  const svgNs = "http://www.w3.org/2000/svg";
  const box = root.getBoundingClientRect();
  const strokes: Element[] = [];
  for (const range of ranges) {
    for (const rect of range.getClientRects()) {
      if (rect.width < 1) continue;
      const svg = document.createElementNS(svgNs, "svg");
      svg.setAttribute("viewBox", "0 0 100 9");
      svg.setAttribute("preserveAspectRatio", "none");
      Object.assign(svg.style, { left: `${rect.left - box.left - 2}px`, top: `${rect.bottom - box.top - 4}px`, width: `${rect.width + 4}px`, height: "9px" });
      const path = document.createElementNS(svgNs, "path");
      path.setAttribute("d", "M1 6 C 25 3, 55 8, 99 4");
      path.setAttribute("pathLength", "1");
      path.style.animationDelay = `${strokes.length * 180}ms`;
      svg.append(path);
      each?.(svg, range, strokes.length);
      strokes.push(svg);
    }
  }
  layer.replaceChildren(...strokes);
}

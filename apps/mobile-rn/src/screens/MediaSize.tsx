// The box an image or video still takes in the chat (screens/MediaSize.kt), as web/src/imageBox.ts sizes it.

/**
 * The box an image or video still takes in the chat, as web/src/imageBox.ts sizes it: its own proportions within
 * 360×300, a tiny one drawn to 40 on its longer side. A strip thinner than `least` there gets a box that thick all the
 * same and is letterboxed in it: fitted whole inside rather than filling (and cropped to) it, `fit` the share of the
 * box (of its width, of its height) it takes.
 */
export interface MediaSize { width: number; height: number; fit?: [number, number] | null }

export function mediaSize(w: number, h: number, least = 16): MediaSize {
  const scale = Math.min(Math.max(1, 40 / Math.max(w, h)), 360 / w, 300 / h);
  const width = w * scale;
  const height = h * scale;
  if (width >= least && height >= least) return { width: Math.round(width), height: Math.round(height) };
  const boxW = Math.round(Math.max(least, width));
  const boxH = Math.round(Math.max(least, height));
  const k = Math.min(boxW / w, boxH / h);
  return { width: boxW, height: boxH, fit: [(w * k) / boxW, (h * k) / boxH] };
}

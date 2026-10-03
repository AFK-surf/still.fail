import type { Attachment } from "./core/shapes.ts";
import { thumbhashRatio } from "./thumbhash.ts";

/**
 * The box an image takes in the chat, known before it loads: its own
 * proportions (sent with it, or read from its ThumbHash) within 360×300, or a
 * fixed box for images sent before sizes were recorded. A narrower chat shrinks it (max-width), the
 * proportions kept. An image thinner than 40px there gets a 40px box all the same, and letterbox says
 * to fit it whole inside rather than fill (and crop) it.
 */
export function imageBox(file: Attachment): { width: number; aspectRatio: string; letterbox?: true } {
  // No size sent, but a ThumbHash: its proportions, at the fixed box's height.
  const ratio = thumbhashRatio(file.thumbhash);
  const [w, h] = file.width && file.height ? [file.width, file.height] : ratio ? [Math.round(160 * ratio), 160] : [0, 0];
  if (!w || !h) return { width: 240, aspectRatio: "240 / 160" };
  const scale = Math.min(1, 360 / w, 300 / h);
  const width = Math.round(w * scale), height = Math.round(h * scale);
  if (width >= 40 && height >= 40) return { width, aspectRatio: `${width} / ${height}` };
  const [boxW, boxH] = [Math.max(40, width), Math.max(40, height)];
  return { width: boxW, aspectRatio: `${boxW} / ${boxH}`, letterbox: true };
}

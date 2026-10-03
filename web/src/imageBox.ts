import type { Attachment } from "./core/shapes.ts";
import { thumbhashRatio } from "./thumbhash.ts";

/**
 * The box an image takes in the chat, known before it loads: its own
 * proportions (sent with it, or read from its ThumbHash) within 360×300, or a
 * fixed box for images sent before sizes were recorded. A narrower chat shrinks it (max-width), the
 * proportions kept. A tiny image is drawn larger, to 40px on its longer side. A strip thinner than 16px there
 * gets a 16px box all the same, and letterbox says to fit it whole inside rather than fill (and crop) it.
 */
export function imageBox(file: Attachment): { width: number; aspectRatio: string; letterbox?: true } {
  // No size sent, but a ThumbHash: its proportions, at the fixed box's height.
  const ratio = thumbhashRatio(file.thumbhash);
  const [w, h] = file.width && file.height ? [file.width, file.height] : ratio ? [Math.round(160 * ratio), 160] : [0, 0];
  if (!w || !h) return { width: 240, aspectRatio: "240 / 160" };
  const scale = Math.min(Math.max(1, 40 / Math.max(w, h)), 360 / w, 300 / h);
  const width = Math.round(w * scale), height = Math.round(h * scale);
  if (width >= 16 && height >= 16) return { width, aspectRatio: `${width} / ${height}` };
  const [boxW, boxH] = [Math.max(16, width), Math.max(16, height)];
  return { width: boxW, aspectRatio: `${boxW} / ${boxH}`, letterbox: true };
}

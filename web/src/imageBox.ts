import type { Attachment } from "./core/shapes.ts";
import { thumbhashRatio } from "./thumbhash.ts";

/**
 * The box an image takes in the chat, known before it loads: its own
 * proportions (sent with it, or read from its ThumbHash) within 360×300, or a
 * fixed box for images sent before sizes were recorded. A narrower chat shrinks it (max-width), the
 * proportions kept. A tiny image is drawn larger, to 40px on its longer side. A strip thinner than `least` there
 * (16px; a video's needs room for its play mark and name) gets a box that thick all the same, and is letterboxed in
 * it: fitted whole inside rather than filling (and cropped to) it, `letterbox` saying how much of the box it takes.
 */
export function imageBox(file: Attachment, least = 16): { width: number; aspectRatio: string; letterbox?: { width: string; height: string } } {
  // No size sent, but a ThumbHash: its proportions, at the fixed box's height.
  const ratio = thumbhashRatio(file.thumbhash);
  const [w, h] = file.width && file.height ? [file.width, file.height] : ratio ? [Math.round(160 * ratio), 160] : [0, 0];
  if (!w || !h) return { width: 240, aspectRatio: "240 / 160" };
  const scale = Math.min(Math.max(1, 40 / Math.max(w, h)), 360 / w, 300 / h);
  const width = w * scale, height = h * scale;
  if (width >= least && height >= least) return { width: Math.round(width), aspectRatio: `${Math.round(width)} / ${Math.round(height)}` };
  const [boxW, boxH] = [Math.round(Math.max(least, width)), Math.round(Math.max(least, height))];
  const k = Math.min(boxW / w, boxH / h);
  const share = (part: number, whole: number) => `${Math.round((part * k / whole) * 1000) / 10}%`;
  return { width: boxW, aspectRatio: `${boxW} / ${boxH}`, letterbox: { width: share(w, boxW), height: share(h, boxH) } };
}

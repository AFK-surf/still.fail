// The pictures the page shows in place of an image, by their URL, and how to get the image itself: a chat's images are
// thumbnails (at most 720×600: station/src/sessions/thumbs.ts), as is the preview's until the image comes
// (FilePreview.tsx, useFile). The desktop app's 「复制图片」 on one copies the image, not the thumbnail
// (apps/desktop/src/main.ts, wholeImage; main.tsx answers it with wholeImage below).
const standIns = new Map<string, () => Promise<Blob>>();

/** The picture at `url` (a blob: URL the page made) stands in for the image `whole` gets, until the returned function is called. */
export function standIn(url: string, whole: () => Promise<Blob>): () => void {
  standIns.set(url, whole);
  return () => {
    if (standIns.get(url) === whole) standIns.delete(url);
  };
}

/**
 * The image the picture at `src` stands in for, whole, as a PNG (the clipboard's kind of image: another kind is drawn
 * again as one). Null for a picture that stands in for nothing: it is the image itself.
 */
export async function wholeImage(src: string): Promise<Uint8Array | null> {
  const whole = standIns.get(src);
  if (!whole) return null;
  return new Uint8Array(await (await asPng(await whole())).arrayBuffer());
}

/** An image as a PNG, the clipboard's kind of image: another kind (a JPEG, a WebP, …) is drawn again as one. */
export async function asPng(image: Blob): Promise<Blob> {
  return isPng(new Uint8Array(await image.slice(0, 8).arrayBuffer())) ? new Blob([image], { type: "image/png" }) : redrawn(image);
}

/** Whether `bytes` are a PNG, by its signature (a file's name may say otherwise). */
const isPng = (bytes: Uint8Array) => [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((b, i) => bytes[i] === b);

/** An image (a JPEG, a WebP, …) drawn again as a PNG. */
async function redrawn(image: Blob): Promise<Blob> {
  const bitmap = await createImageBitmap(image);
  const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0);
  bitmap.close();
  return canvas.convertToBlob({ type: "image/png" });
}

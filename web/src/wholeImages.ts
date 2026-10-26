// Images for the clipboard, whose kind of image is a PNG (FilePreview.tsx copies one so).
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

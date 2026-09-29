import { thumbHashToApproximateAspectRatio, thumbHashToDataURL } from "thumbhash";

/**
 * An image's ThumbHash as the station keeps it with the message (base64, made as it keeps the image,
 * mesh/app/src/thumbs.rs): a blurred likeness of it, shown until the image itself loads.
 */
const drawn = new Map<string, { url: string; ratio: number } | null>();

function read(hash: string | undefined): { url: string; ratio: number } | null {
  if (!hash) return null;
  let got = drawn.get(hash);
  if (got !== undefined) return got;
  try {
    const bytes = Uint8Array.from(atob(hash), (c) => c.charCodeAt(0));
    got = { url: thumbHashToDataURL(bytes), ratio: thumbHashToApproximateAspectRatio(bytes) };
  } catch {
    got = null;
  }
  drawn.set(hash, got);
  return got;
}

/** The likeness as a small PNG data URL (about 32px across; the box it fills blurs it further), or null for none. */
export const thumbhashUrl = (hash: string | undefined) => read(hash)?.url ?? null;

/** The image's width over its height, near enough to size a box by (the likeness keeps it roughly). */
export const thumbhashRatio = (hash: string | undefined) => read(hash)?.ratio ?? null;

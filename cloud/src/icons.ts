// The pictures put up as stations' and workspaces' icons: a client sends one as a data URL (with the name and the emoji,
// as before); it is kept in the bucket under icons/<its hash>.<kind> and the workspace keeps its address, served from
// /v1/icons/, so a workspace's views stay small however large its pictures are. A GIF keeps moving.
import type { Env } from "./env";

/** The part of R2Bucket this needs. */
export interface IconBucket {
  put(key: string, value: Uint8Array, options: { httpMetadata: { contentType: string; cacheControl: string } }): Promise<unknown>;
  get(key: string): Promise<{ body: ReadableStream<Uint8Array>; httpEtag: string } | null>;
}

/** How large a picture put up may be. */
export const ICON_FILE_BYTES = 1024 * 1024;
/** A data URL of one that large, and a little more. */
export const ICON_URL_CHARS = Math.ceil(ICON_FILE_BYTES / 3) * 4 + 64;

const TYPES: Record<string, string> = { png: "image/png", webp: "image/webp", jpeg: "image/jpeg", gif: "image/gif" };
const CACHE = "public, max-age=31536000, immutable";

/** Where a picture kept here is served: PUBLIC_ORIGIN's /v1/icons/<hash>.<kind>. */
export const iconUrl = (origin: string, name: string) => `${origin}/v1/icons/${name}`;
/** Whether `value` is the address of a picture kept here (iconUrl). */
export const isIconUrl = (origin: string, value: string) => value.startsWith(`${origin}/v1/icons/`) && /^[0-9a-f]{32}\.(png|webp|jpeg|gif)$/.test(value.slice(origin.length + 10));

/**
 * A picture sent as a data URL, put in the bucket: its address. Fails (invalid_icon) for one that is not a PNG, WebP,
 * JPEG or GIF of up to ICON_FILE_BYTES. Without a bucket the data URL is given back (directory.ts cleanIcon takes a small one).
 */
export async function keptIcon(env: Env, icon: string): Promise<string> {
  const bucket = env.RELEASES as IconBucket | undefined;
  if (!bucket) return icon;
  const m = icon.length <= ICON_URL_CHARS ? /^data:image\/(png|webp|jpeg|gif);base64,([A-Za-z0-9+/]+={0,2})$/.exec(icon) : null;
  const kind = m?.[1] ?? "";
  const bytes = m ? Uint8Array.from(atob(m[2]!), (c) => c.charCodeAt(0)) : new Uint8Array();
  if (!m || bytes.length > ICON_FILE_BYTES || !looksLike(kind, bytes)) throw new Error("invalid_icon");
  const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].slice(0, 16).map((b) => b.toString(16).padStart(2, "0")).join("");
  const name = `${hash}.${kind}`;
  await bucket.put(`icons/${name}`, bytes, { httpMetadata: { contentType: TYPES[kind]!, cacheControl: CACHE } });
  return iconUrl(env.PUBLIC_ORIGIN, name);
}

/** GET /v1/icons/<hash>.<kind>: a picture kept here, to anyone with its address (it never changes). */
export async function serveIcon(env: Env, name: string): Promise<Response | null> {
  const m = /^[0-9a-f]{32}\.(png|webp|jpeg|gif)$/.exec(name);
  const bucket = env.RELEASES as IconBucket | undefined;
  if (!m || !bucket) return null;
  const file = await bucket.get(`icons/${name}`);
  if (!file) return null;
  return new Response(file.body, { headers: { "content-type": TYPES[m[1]!]!, "cache-control": CACHE, etag: file.httpEtag, "access-control-allow-origin": "*", "x-content-type-options": "nosniff" } });
}

/** Whether the bytes are what the data URL says they are (its first bytes), so nothing else is served as a picture. */
function looksLike(kind: string, b: Uint8Array): boolean {
  const at = (i: number, s: string) => [...s].every((ch, j) => b[i + j] === ch.charCodeAt(0));
  if (kind === "png") return at(0, "\x89PNG");
  if (kind === "jpeg") return b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
  if (kind === "webp") return at(0, "RIFF") && at(8, "WEBP");
  return at(0, "GIF8");
}

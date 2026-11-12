// The pictures of a link's card and of a file's peek go beside the JSON, not in it. A station answers GET /link-preview
// with a page's icon and picture and a pull request's author's face inline (data: URLs, station/src/links/preview.ts:
// an icon up to 48 KB, a picture up to 192 KB), and GET /sessions/:key/peek with a picture's bytes in base64 (up to
// 256 KB: sessions.ts PEEK_IMAGE). The link's memory keeps that as it came (link.ts `linkPreviewKey`, `filePeekKey`)
// and the core's own readers read it whole (`store.value`); what goes out to a UI (`linkPreview`, `filePeek`: present.ts)
// says only that there is one and which (`shown`: a token that changes when the picture does), and the UI asks its
// bytes of `link.preview.picture` / `file.peek.picture`, answered here out of what the topic's read brought (`bytes`):
// no request made. A `linkPreview page` went out at 222 KB and a `filePeek picture` at 342 KB, each parsed on the app's
// frame thread, its base64 decoded there too.
import { CoreError } from "./error.ts";
import { textHash } from "./digest.ts";
import { t } from "./i18n.ts";
import { fromBase64, isObject } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// Which of a link's card's pictures: the page's icon, its picture, a pull request's or issue's author's face.
export type LinkPicture = "icon" | "image" | "avatar";
export const LINK_PICTURES: readonly LinkPicture[] = ["icon", "image", "avatar"];

/// The tokens of the pictures last shown, by their text: a value goes out decorated from a copy (output.ts) each time
/// it is made again (a minute on, its time in words), and the same picture is not hashed again each time. As many as
/// the links' memory keeps of each (link.ts LINK_PREVIEWS_KEPT, FILE_PEEKS_KEPT), a few each, the least lately had
/// going first.
const tokens = new Map<string, string>();
const TOKENS_KEPT = 128;

/// The token of a picture's text (its data: URL, its base64): a hash of it.
function token(text: string): string {
  let made = tokens.get(text);
  if (made !== undefined) tokens.delete(text);
  else made = textHash(text);
  tokens.set(text, made);
  if (tokens.size > TOKENS_KEPT) tokens.delete(tokens.keys().next().value as string);
  return made;
}

/// A data: URL's base64 and type; null for anything else (an address, a token already: present.ts may shape a value
/// twice).
function dataUrl(v: unknown): { type: string; data: string } | null {
  if (typeof v !== "string" || !v.startsWith("data:")) return null;
  const comma = v.indexOf(",");
  const head = comma < 0 ? "" : v.slice(5, comma);
  if (!head.endsWith(";base64")) return null;
  return { type: head.slice(0, -";base64".length), data: v.slice(comma + 1) };
}

/// A `linkPreview` value as it goes out: each picture inline (`icon`, `image`, `author.avatar`) its token in its place.
export function linkShown(v: J): J {
  if (!isObject(v)) return v;
  let out: J = v;
  for (const field of ["icon", "image"] as const) {
    if (dataUrl(v[field]) !== null) out = { ...out, [field]: token(v[field] as string) };
  }
  const author = v.author;
  if (isObject(author) && dataUrl(author.avatar) !== null) out = { ...out, author: { ...author, avatar: token(author.avatar as string) } };
  return out;
}

/// A `filePeek` value as it goes out: its picture's bytes (`image.data`) its token (`image.picture`) in their place.
export function peekShown(v: J): J {
  if (!isObject(v) || !isObject(v.image) || typeof v.image.data !== "string") return v;
  const { data, ...image } = v.image;
  return { ...v, image: { ...image, picture: token(data) } };
}

/// No such picture in what was kept: the topic not read yet, read with none, or let go of.
function none(): CoreError {
  return new CoreError("no_picture", t("core-misc.call.no_picture"), 404);
}

/// Picture `which` of a link's card as the station said it last (`kept`, the link's memory's): its type and bytes.
export function linkPicture(kept: J, which: LinkPicture): { type: string; bytes: Uint8Array } {
  const url = which === "avatar" ? (isObject(kept?.author) ? kept.author.avatar : undefined) : kept?.[which];
  const d = dataUrl(url);
  const bytes = d === null ? null : fromBase64(d.data);
  if (d === null || bytes === null) throw none();
  return { type: d.type, bytes };
}

/// A file's peek's picture as the station said it last (`kept`): its type and bytes.
export function peekPicture(kept: J): { type: string; bytes: Uint8Array } {
  const image = kept?.image;
  const bytes = isObject(image) && typeof image.data === "string" ? fromBase64(image.data) : null;
  if (bytes === null) throw none();
  return { type: typeof image.type === "string" ? image.type : "", bytes };
}

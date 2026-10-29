// What was said in a chat besides words (the `chatThings` view): its pictures and videos, its other files, the web links
// in its messages and the pull requests among them, each found once however often it was said, the latest first, with
// the message it was last said in (where 在对话里看 goes). Read from its messages as its page draws them (views.ts
// drawn: a file's `owner`, an agent's words read as Markdown, `md`): an agent's links are those its Markdown links (code
// links nothing), a person's those written bare in their words (bareLinks.ts), as each is drawn. Self-contained: the
// web's demo makes its chats' with it, typechecked as the web is.
import { bareLinks } from "./bareLinks.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The kinds, in the order the page offers them.
export const KINDS = ["media", "files", "links", "pulls"] as const;
export type Kind = (typeof KINDS)[number];

/// A message's part in it: when it was said, by whom, the message (its seq).
type Said = { seq: number; createdAt: number | null; by: string };

export type Thing = Said & { key: string; file?: J; url?: string; title?: string; site?: string; count?: number; repository?: string; number?: number };

const MEDIA = /\.(png|jpe?g|gif|webp|svg|avif|bmp|ico|heic|mp4|m4v|webm|mov|ogv)$/i;
const VIDEO = /\.(mp4|m4v|webm|mov|ogv)$/i;

/// A file the page shows among the pictures and videos (as a message draws it: a picture, a video's still).
export const isMedia = (name: string): boolean => MEDIA.test(name);
export const isVideo = (name: string): boolean => VIDEO.test(name);

/// A pull request's link (`https://github.com/<owner>/<repo>/pull/<n>`, with anything after its number): its
/// repository and number, else null.
export function pullOf(url: string): { repository: string; number: number } | null {
  const m = /^https?:\/\/(?:www\.)?github\.com\/([^/\s?#]+)\/([^/\s?#]+)\/pull\/(\d+)(?:[/?#]|$)/i.exec(url);
  if (m === null) return null;
  return { repository: `${m[1]}/${m[2]}`, number: Number(m[3]) };
}

/// A link's host and path, as its card says where it goes (Peeks.tsx destination).
export function siteOf(url: string): string {
  const rest = url.replace(/^[a-z][\w+.-]*:\/\//i, "").replace(/[?#].*$/, "");
  return rest.endsWith("/") ? rest.slice(0, -1) : rest;
}

/// Which link a link is among the chat's: as written, without its fragment and a closing slash.
const linkKey = (url: string): string => url.replace(/#.*$/, "").replace(/\/$/, "");

/// The words of a node of an agent's tree (markdown.ts), as read from `source`.
function wordsIn(node: J, source: string): string {
  if (typeof node === "string") return node;
  if (!Array.isArray(node)) return "";
  if (typeof node[0] === "number") return source.slice(node[0], node[1]);
  const children = Array.isArray(node[1]) ? node[1] : [];
  return children.map((c: J) => wordsIn(c, source)).join("");
}

/// The web links of a message, in order: an agent's as its Markdown links them (with their words), a person's written bare.
export function linksOf(message: J): { url: string; words: string }[] {
  const text = typeof message?.text === "string" ? message.text : "";
  const out: { url: string; words: string }[] = [];
  const web = (url: unknown): url is string => typeof url === "string" && /^https?:\/\/[^\s]/i.test(url);
  if (Array.isArray(message?.md)) {
    const walk = (nodes: J[]) => {
      for (const n of nodes) {
        if (!Array.isArray(n) || typeof n[0] !== "string") continue;
        const attrs = n.find((x: J, i: number) => i > 0 && x !== null && typeof x === "object" && !Array.isArray(x));
        const children = Array.isArray(n[1]) ? n[1] : [];
        if (n[0] === "a" && web(attrs?.href)) out.push({ url: attrs.href, words: children.map((c: J) => wordsIn(c, text)).join("").trim() });
        else walk(children);
      }
    };
    walk(message.md);
    return out;
  }
  if (message?.authorKind !== "person") return out;
  for (const part of bareLinks(text)) if (typeof part !== "string") out.push({ url: part.url, words: "" });
  return out;
}

/// A chat's things from its messages (oldest first, as its page draws them): each kind the latest first. A file is one
/// per message it was sent with (the same name sent again is another picture); a link and a pull request one however
/// often said, at the latest time (`count`: how many times), with the words it was last linked by (`title`, none where
/// they are its address).
export function thingsOf(messages: readonly J[]): Record<Kind, Thing[]> {
  const media: Thing[] = [];
  const files: Thing[] = [];
  const links = new Map<string, Thing>();
  const pulls = new Map<string, Thing>();
  for (const m of messages) {
    const seq = typeof m?.seq === "number" ? m.seq : null;
    if (seq === null) continue;
    const said: Said = { seq, createdAt: typeof m.createdAt === "number" ? m.createdAt : null, by: typeof m.by?.name === "string" ? m.by.name : typeof m.authorName === "string" ? m.authorName : "" };
    for (const f of Array.isArray(m.attachments) ? m.attachments : []) {
      if (f === null || typeof f !== "object" || typeof f.name !== "string") continue;
      const thing = { ...said, key: `${seq}/${typeof f.path === "string" ? f.path : f.name}`, file: f };
      (isMedia(f.name) ? media : files).push(thing);
    }
    for (const { url, words } of linksOf(m)) {
      const pr = pullOf(url);
      if (pr !== null) {
        const key = `${pr.repository.toLowerCase()}#${pr.number}`;
        const was = pulls.get(key);
        pulls.delete(key);
        pulls.set(key, { ...said, key, url: `https://github.com/${pr.repository}/pull/${pr.number}`, ...pr, count: (was?.count ?? 0) + 1 });
        continue;
      }
      const key = linkKey(url);
      const was = links.get(key);
      const title = words !== "" && linkKey(words) !== key && words !== url ? words : (was?.title ?? "");
      links.delete(key);
      links.set(key, { ...said, key, url, site: siteOf(url), ...(title !== "" ? { title } : {}), count: (was?.count ?? 0) + 1 });
    }
  }
  return { media: media.reverse(), files: files.reverse(), links: [...links.values()].reverse(), pulls: [...pulls.values()].reverse() };
}

/// Those of `things` that have every one of `words` (lower case) in what the page says of them: a file's name, a link's
/// words and address, a pull request's title, repository and number.
export function thingsHaving(things: readonly Thing[], words: readonly string[]): Thing[] {
  if (words.length === 0) return [...things];
  return things.filter((t) => {
    const said = [t.file?.name, t.title, t.url, t.repository, t.number !== undefined ? `#${t.number}` : undefined].filter((s) => typeof s === "string").join(" ").toLowerCase();
    return words.every((w) => said.includes(w));
  });
}

// What X says and is told, in the station's terms (docs/x.md): a post that mentions the bot as a message of its
// conversation, and the agent's Markdown as X's plain posts (no formatting, at most 280 weighted characters each, links
// left unlinked unless the connect takes them: X bills a post with a link 20 times one without).
import type { InboundFile } from "../sessions/chat.ts";

type Json = any;

const text = (v: unknown): string => (typeof v === "string" ? v : "");

/// What a post's fields are asked for, and what is expanded with it: its author, the posts it replies to and quotes,
/// its pictures. X's API calls posts tweets in its older names; both are read.
export const POST_QUERY = {
  "post.fields": "author_id,conversation_id,created_at,entities,in_reply_to_user_id,note_post,referenced_posts,attachments",
  expansions: "author_id,referenced_posts.id,attachments.media_keys",
  "user.fields": "name,username,profile_image_url",
  "media.fields": "media_key,type,url,preview_image_url",
};
/// The same in the names X's API had before posts were called posts (an API that refuses the others).
export const LEGACY_QUERY = {
  "tweet.fields": "author_id,conversation_id,created_at,entities,in_reply_to_user_id,note_tweet,referenced_tweets,attachments",
  expansions: "author_id,referenced_tweets.id,attachments.media_keys",
  "user.fields": "name,username,profile_image_url",
  "media.fields": "media_key,type,url,preview_image_url",
};

/// A person on X as an answer's `includes.users` says.
export type XUser = { id: string; name: string; username: string; picture: string };

/// A post, as the station takes it.
export type XPost = {
  id: string;
  conversation: string;
  author: string;
  text: string;
  /// The post it replies to, and the one it quotes, if any.
  repliesTo: string | null;
  quotes: string | null;
  files: InboundFile[];
};

/// An answer's expansions, by id.
export type Includes = { users: Map<string, XUser>; posts: Map<string, Json>; media: Map<string, Json> };

export function includesOf(answer: Json): Includes {
  const inc = answer?.includes ?? {};
  const users = new Map<string, XUser>();
  for (const u of Array.isArray(inc.users) ? inc.users : []) {
    const id = text(u?.id);
    if (id !== "") users.set(id, { id, name: text(u?.name), username: text(u?.username), picture: text(u?.profile_image_url) });
  }
  const posts = new Map<string, Json>();
  for (const p of [...(Array.isArray(inc.posts) ? inc.posts : []), ...(Array.isArray(inc.tweets) ? inc.tweets : [])]) if (text(p?.id) !== "") posts.set(p.id, p);
  const media = new Map<string, Json>();
  for (const m of Array.isArray(inc.media) ? inc.media : []) if (text(m?.media_key) !== "") media.set(m.media_key, m);
  return { users, posts, media };
}

/// A post's whole words: a long post's note, else its text; X's HTML escapes undone.
export function wordsOf(post: Json): string {
  const note = text(post?.note_post?.text) || text(post?.note_tweet?.text);
  return (note || text(post?.text)).replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&amp;", "&");
}

const referenced = (post: Json, type: string): string | null => {
  const refs = [...(Array.isArray(post?.referenced_posts) ? post.referenced_posts : []), ...(Array.isArray(post?.referenced_tweets) ? post.referenced_tweets : [])];
  const id = text(refs.find((r: Json) => r?.type === type)?.id);
  return id === "" ? null : id;
};

/// A post as the station takes it, its pictures as files (fetched from where X shows them).
export function postOf(post: Json, inc: Includes): XPost | null {
  const id = text(post?.id);
  const author = text(post?.author_id);
  if (id === "" || author === "") return null;
  const files: InboundFile[] = [];
  for (const key of Array.isArray(post?.attachments?.media_keys) ? post.attachments.media_keys : []) {
    const m = inc.media.get(key);
    const url = text(m?.url) || text(m?.preview_image_url);
    if (url === "") continue;
    const ext = /\.(jpe?g|png|gif|webp)(\?|$)/i.exec(url)?.[1]?.toLowerCase() ?? "jpg";
    files.push({ id: key, name: `${key}.${ext}`, size: 0, url });
  }
  return { id, conversation: text(post?.conversation_id) || id, author, text: wordsOf(post), repliesTo: referenced(post, "replied_to"), quotes: referenced(post, "quoted"), files };
}

/// A post's words without the @handles it begins with (those X puts before a reply, and the bot's own): what it says.
/// One that is nothing but those keeps them.
export function said(text: string): string {
  const rest = text.replace(/^(?:\s*@[A-Za-z0-9_]{1,15}\b)+\s*/, "");
  return rest === "" ? text : rest;
}

/// A post's words as a message (said), the post it quotes after them, as a quote with whose it is.
export function messageText(p: XPost, inc: Includes): string {
  const quoted = p.quotes === null ? null : inc.posts.get(p.quotes);
  if (!quoted) return said(p.text);
  const who = inc.users.get(text(quoted.author_id));
  const by = who ? `@${who.username}` : "a post";
  const lines = wordsOf(quoted)
    .split("\n")
    .map((l) => `> ${l}`)
    .join("\n");
  return `${said(p.text)}\n\n[Quoting ${by}]\n${lines}`;
}

// ── what the agent writes, as posts ─────────────────────────────────────────────────────────────────────────────

const URL_RE = /\bhttps?:\/\/[^\s<>()]+[^\s<>().,;:!?'"]/g;
/// A bare domain X would link (still.fail, example.com/path).
const DOMAIN_RE = /\b(?:[a-z0-9-]+\.)+(?:com|net|org|io|ai|dev|app|fail|surf|co|me|so|sh|xyz|cn|jp|uk|de|fr|us|info|tech|site|link|gg|tv|ly)\b(?:\/[^\s<>()]*[^\s<>().,;:!?'"])?/gi;

/// A link made plain text X does not link: its dots bracketed.
const unlinked = (url: string) => url.replace(/^https?:\/\//, "").replaceAll(".", "[.]");

/// The agent's Markdown as plain text: no markers (bold, italic, code, headings, quotes stay as words), a link as its
/// label and address, lists as lines, a table's rows as lines. Links stay links only where `links` (each post with one
/// costs $0.20 on X's pay-per-use API, one without $0.01): elsewhere their dots are bracketed, so X does not link them.
export function plainOf(markdown: string, links: boolean): string {
  let out = markdown.replace(/\r\n/g, "\n");
  // Code blocks: their lines as they are.
  out = out.replace(/```[^\n]*\n([\s\S]*?)```/g, (_m, body: string) => body.replace(/\n$/, ""));
  out = out.replace(/!\[([^\]]*)\]\(([^)\s]+)\)/g, (_m, alt: string) => alt);
  out = out.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_m, label: string, url: string) => (label === url || label === url.replace(/^https?:\/\//, "") ? url : `${label} (${url})`));
  out = out.replace(/^#{1,6}\s+/gm, "");
  out = out.replace(/^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$/gm, "");
  out = out.replace(/^\|(.*)\|\s*$/gm, (_m, row: string) =>
    row
      .split("|")
      .map((c) => c.trim())
      .join(" · "),
  );
  out = out.replace(/(\*\*|__)(?=\S)([\s\S]*?\S)\1/g, "$2");
  out = out.replace(/(^|[^\w*])\*(?=\S)([^*\n]*?\S)\*(?!\w)/g, "$1$2");
  out = out.replace(/~~(?=\S)([\s\S]*?\S)~~/g, "$1");
  out = out.replace(/`([^`\n]+)`/g, "$1");
  out = out.replace(/^(\s*)[-*+]\s+/gm, "$1• ");
  out = out.replace(/\\([\\`*_{}[\]()#+\-.!|>~])/g, "$1");
  out = out.replace(/\n{3,}/g, "\n\n").trim();
  if (!links) {
    out = out.replace(URL_RE, unlinked);
    out = out.replace(DOMAIN_RE, (d) => (d.includes("[.]") ? d : unlinked(d)));
  }
  return out;
}

/// How much X counts a character (twitter-text's weights: most Latin, punctuation and spaces count one, the rest, CJK
/// among them, two), and a link as 23 whatever its length.
export function weightOf(s: string): number {
  let w = 0;
  let rest = s;
  for (const url of s.match(URL_RE) ?? []) {
    w += 23;
    rest = rest.replace(url, "");
  }
  for (const ch of rest) {
    const c = ch.codePointAt(0)!;
    w += c <= 4351 || (c >= 8192 && c <= 8205) || (c >= 8208 && c <= 8223) || (c >= 8242 && c <= 8247) ? 1 : 2;
  }
  return w;
}

/// Splits plain text into posts of at most `limit` weighted characters (X's 280), at paragraph, then line, then word
/// boundaries; a run with none is cut where it fills the post.
export function splitForX(plain: string, limit = 280): string[] {
  const posts: string[] = [];
  let rest = plain.trim();
  while (rest !== "" && weightOf(rest) > limit) {
    // The longest prefix that fits, in characters.
    const chars = Array.from(rest);
    let fit = 0;
    let w = 0;
    for (const ch of chars) {
      const cw = weightOf(ch);
      if (w + cw > limit) break;
      w += cw;
      fit++;
    }
    const head = chars.slice(0, fit).join("");
    const at = (needle: string) => {
      const i = head.lastIndexOf(needle);
      return i > head.length / 3 ? i : -1;
    };
    let cut = at("\n\n");
    if (cut < 0) cut = at("\n");
    if (cut < 0) cut = at(" ");
    if (cut < 0) cut = head.length;
    posts.push(head.slice(0, cut).trimEnd());
    rest = rest.slice(cut).trimStart();
  }
  if (rest !== "" || posts.length === 0) posts.push(rest);
  return posts;
}

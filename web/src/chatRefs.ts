// References to other chats in what is written (ChatRef.tsx): in the composer a short mark, `@[its title]`, drawn as a
// chip; sent, a link, `[its title](its page)`, which the agent reads the chat by and a message draws as the same chip.

/** A reference as the composer holds it. */
export const REF_MARK = /@\[([^\]\n]{1,120})\]/g;
/** A reference as sent: a link to a chat's page. */
export const REF_LINK = /\[([^\]\n]{1,120})\]\((\S*?\/chats\/[^\s)]+)\)/g;

const KEY = "ember.chatRefs";
const KEPT = 200;
/** Characters of a title a reference shows. */
const TITLE = 24;

function links(): Record<string, string> {
  try { return JSON.parse(localStorage.getItem(KEY) ?? "{}") as Record<string, string>; } catch { return {}; }
}

/** A chat's title, as a reference shows it: its start, on one line. */
export function refTitle(title: string): string {
  const words = [...title.replace(/[[\]\n]/g, " ").replace(/\s+/g, " ").trim()];
  return (words.length > TITLE ? `${words.slice(0, TITLE).join("").trimEnd()}…` : words.join("")) || "对话";
}

/** The mark for a chat, its link kept (across reloads: a draft outlives the page) until the mark is sent. */
export function refMark(title: string, link: string): string {
  const all = links();
  delete all[title];
  all[title] = link;
  const kept = Object.entries(all).slice(-KEPT);
  try { localStorage.setItem(KEY, JSON.stringify(Object.fromEntries(kept))); } catch { /* kept for this page only */ }
  return `@[${title}]`;
}

/** What is written, its marks made links (one whose link is gone stays as written). */
export function expandRefs(text: string): string {
  const all = links();
  return text.replace(REF_MARK, (mark, title: string) => (all[title] ? `[${title}](${all[title]})` : mark));
}

/** Text split into its plain runs and the parts `pattern` finds (with its groups). */
export function splitBy(text: string, pattern: RegExp): (string | RegExpExecArray)[] {
  const parts: (string | RegExpExecArray)[] = [];
  let at = 0;
  for (const m of text.matchAll(new RegExp(pattern.source, "g"))) {
    if (m.index > at) parts.push(text.slice(at, m.index));
    parts.push(m as RegExpExecArray);
    at = m.index + m[0].length;
  }
  if (at < text.length) parts.push(text.slice(at));
  return parts;
}

/** A link to a chat's page (…/chats/<key>, or ember cloud's /o/<workspace>/<station>/<key>). */
export function isChatLink(href: string | undefined): boolean {
  return !!href && (/\/chats\/[^/?#\s]+\/?(?:[?#]|$)/.test(href) || /^https?:\/\/[^/]+\/o\/[^/]+\/[^/]+\/[^/?#]+\/?(?:#|$)/.test(href));
}

// References to other chats in what is written (ChatRef.tsx): in the composer a short mark, `@[its title]`, drawn as a
// chip; sent, a link, `[its title](its page)`, which the agent reads the chat by and a message draws as the same chip.
// The core makes the mark of a chat picked and keeps its link until it is sent (`chat.ref`, client/core-ts/src/refs.ts).

/** A reference as the composer holds it. */
export const REF_MARK = /@\[([^\]\n]{1,120})\]/g;
/** A reference as sent: a link to a chat's page, or its still.fail link (…/o/<workspace>/<station>/<key>, as copied). */
export const REF_LINK = /\[([^\]\n]{1,120})\]\((\S*?(?:\/chats\/|\/o\/[^/\s)]+\/[^/\s)]+\/)[^\s)]+)\)/g;

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

/** A link to a chat's page (…/chats/<key>, or still.fail cloud's /o/<workspace>/<station>/<key>). */
export function isChatLink(href: string | undefined): boolean {
  return !!href && (/\/chats\/[^/?#\s]+\/?(?:[?#]|$)/.test(href) || /^https?:\/\/[^/]+\/o\/[^/]+\/[^/]+\/[^/?#]+\/?(?:[?#]|$)/.test(href));
}

/**
 * The link a chat is given away by (copied from its row's menu): still.fail's, `…/o/<workspace>/<station>/<session>`,
 * which opens it wherever it is pasted and which an agent on any station of the workspace reads it by (chat_read);
 * `history`: an agent's execution history there (session_history), opened at `entry` (copied from the history). A
 * station of no workspace has no such link: its page here (`root`, where this page's routes start).
 */
export function shareLink(item: { station: string; session: string; id: string }, root: string, history?: { key: string; entry?: number | undefined }): string {
  const at = item.station.indexOf("/");
  const here = /^https?:$/.test(location.protocol) ? location.origin : null;
  const cloud = window.stillfailDesktop?.cloudOrigin || here;
  const page = at >= 0 && cloud
    ? `${cloud.replace(/\/+$/, "")}/o/${item.station.slice(0, at)}/${item.station.slice(at + 1)}/${encodeURIComponent(item.session)}`
    : `${here ?? ""}${root.replace(/\/+$/, "")}/chats/${encodeURIComponent(item.id)}`;
  return history ? `${page}?history=${encodeURIComponent(history.key)}${history.entry === undefined ? "" : `&entry=${history.entry}`}` : page;
}

/**
 * Puts a link to a chat on the clipboard: as a reference is sent, `[its title](link)`, for plain text (a composer,
 * where it becomes a reference again, or a terminal), and as a link for what takes HTML (Slack, documents).
 */
export function copyChatLink(title: string, link: string): Promise<void> {
  const shown = Array.from(title.replace(/[[\]\n]/g, " ").trim() || link).slice(0, 120).join("");
  const plain = `[${shown}](${link})`;
  if (typeof ClipboardItem === "undefined" || !navigator.clipboard.write) return navigator.clipboard.writeText(plain);
  const escape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const html = `<a href="${escape(link)}">${escape(shown)}</a>`;
  return navigator.clipboard.write([new ClipboardItem({ "text/plain": new Blob([plain], { type: "text/plain" }), "text/html": new Blob([html], { type: "text/html" }) })]);
}

/**
 * The chat a link names, when it is one of a workspace's chats: a still.fail link (`…/o/<workspace>/<station>/<session>`)
 * or its page (`…/w/<workspace>/s/<station>/chats/<id>`), and what follows it when that is its agent's execution
 * history (`?history=<session>`, maybe `&entry=<n>`; else ""). Null otherwise.
 */
export function chatOfLink(href: string): { station: string; id: string; history: string } | null {
  const m = /\/o\/([^/?#\s]+)\/([^/?#\s]+)\/([^/?#\s]+)\/?(\?history=[^&#\s]+(?:&entry=\d+)?)?$/.exec(href)
    ?? /\/w\/([^/?#\s]+)\/s\/([^/?#\s]+)\/chats\/([^/?#\s]+)\/?(\?history=[^&#\s]+(?:&entry=\d+)?)?$/.exec(href);
  if (!m) return null;
  try {
    return { station: `${m[1]}/${m[2]}`, id: decodeURIComponent(m[3]!), history: m[4] ?? "" };
  } catch {
    return null;
  }
}

/** The station (`<workspace>/<station>`) a link to a chat is on, as chatOfLink reads it; null for a link that does not say. */
export function stationOfLink(href: string): string | null {
  const m = /\/o\/([^/?#\s]+)\/([^/?#\s]+)\/[^/?#\s]+/.exec(href) ?? /\/w\/([^/?#\s]+)\/s\/([^/?#\s]+)\/chats\//.exec(href);
  return m ? `${m[1]}/${m[2]}` : null;
}

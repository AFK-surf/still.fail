// still.fail's links as what is written names them, read alike by every client: a reference to another chat (in the
// composer a short mark, `@[its title]`; sent, a link, `[its title](its page)`), the link a chat is given away by, and
// the chat, screen or 共享调试 a link names. Read as a message or a draft is drawn, so the web takes them as they are
// (web/src/chatRefs.ts), as it takes markdown.ts's words; nothing here reads the device or the station. The core's own
// keeping of a mark's link until it is sent is refs.ts's.

import { bareLinks } from "./bareLinks.ts";

/// A reference as the composer holds it.
export const REF_MARK = /@\[([^\]\n]{1,120})\]/g;
/// A reference as sent: a link to a chat's page, or its still.fail link (…/o/<workspace>/<station>/<key>, as copied).
export const REF_LINK = /\[([^\]\n]{1,120})\]\((\S*?(?:\/chats\/|\/o\/[^/\s)]+\/[^/\s)]+\/)[^\s)]+)\)/g;

/// Text split into its plain runs and the parts `pattern` finds (with its groups).
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

/// A link to a chat's page (…/chats/<key>, or still.fail cloud's /o/<workspace>/<station>/<key>).
export function isChatLink(href: string | undefined): boolean {
  return !!href && (/\/chats\/[^/?#\s]+\/?(?:[?#]|$)/.test(href) || /^https?:\/\/[^/]+\/o\/[^/]+\/[^/]+\/[^/?#]+\/?(?:[?#]|$)/.test(href));
}

/// The link a chat is given away by: still.fail's, `…/o/<workspace>/<station>/<session>` under `at.cloud` (still.fail
/// cloud's origin; null: none known), which opens it wherever it is pasted and which an agent on any station of the
/// workspace reads it by (chat_read); `history`: an agent's execution history there (session_history), opened at
/// `entry`. A station of no workspace has no such link: its page, under `at.here` (the page's own origin; null: none)
/// and `at.root` (where the page's routes start).
export function shareLink(
  item: { station: string; session: string; id: string },
  at: { cloud: string | null; here: string | null; root: string },
  history?: { key: string; entry?: number | undefined },
): string {
  const slash = item.station.indexOf("/");
  const page = slash >= 0 && at.cloud
    ? `${at.cloud.replace(/\/+$/, "")}/o/${item.station.slice(0, slash)}/${item.station.slice(slash + 1)}/${encodeURIComponent(item.session)}`
    : `${at.here ?? ""}${at.root.replace(/\/+$/, "")}/chats/${encodeURIComponent(item.id)}`;
  return history ? `${page}?history=${encodeURIComponent(history.key)}${history.entry === undefined ? "" : `&entry=${history.entry}`}` : page;
}

/// A chat's link as a reference is sent, to be copied: its words (`shown`: the title on one line, at most 120
/// characters; the link itself for none) and `[shown](link)` (`plain`), which a composer makes a reference again.
export function copiedRef(title: string, link: string): { shown: string; plain: string } {
  const shown = Array.from(title.replace(/[[\]\n]/g, " ").trim() || link).slice(0, 120).join("");
  return { shown, plain: `[${shown}](${link})` };
}

/// The chat a link names, when it is one of a workspace's chats: a still.fail link (`…/o/<workspace>/<station>/<session>`)
/// or its page (`…/w/<workspace>/s/<station>/chats/<id>`), and what follows it when that is its agent's execution
/// history (`?history=<session>`, maybe `&entry=<n>`; else "") or one of its messages (`?message=<seq>`; else ""). Null
/// otherwise.
export function chatOfLink(href: string): { station: string; id: string; history: string; message: string } | null {
  const m = /\/o\/([^/?#\s]+)\/([^/?#\s]+)\/([^/?#\s]+)\/?(\?history=[^&#\s]+(?:&entry=\d+)?|\?message=[1-9]\d{0,14})?$/.exec(href)
    ?? /\/w\/([^/?#\s]+)\/s\/([^/?#\s]+)\/chats\/([^/?#\s]+)\/?(\?history=[^&#\s]+(?:&entry=\d+)?|\?message=[1-9]\d{0,14})?$/.exec(href);
  if (!m) return null;
  try {
    const after = m[4] ?? "";
    const message = after.startsWith("?message=");
    return { station: `${m[1]}/${m[2]}`, id: decodeURIComponent(m[3]!), history: message ? "" : after, message: message ? after : "" };
  } catch {
    return null;
  }
}

/// The chats what is written links to, each link once: in a reference (`[its title](link)`), then written bare
/// (bareLinks.ts); each its link, its station and its key as chatOfLink reads them, a link with no station of its own
/// (`…/chats/<id>`) one of `here`'s.
export function chatsLinked(text: string, here: string): { href: string; station: string; id: string }[] {
  const out: { href: string; station: string; id: string }[] = [];
  const add = (href: string) => {
    if (!isChatLink(href) || out.some((c) => c.href === href)) return;
    const of = chatOfLink(href) ?? ownChat(href, here);
    if (of !== null) out.push({ href, station: of.station, id: of.id });
  };
  for (const m of text.matchAll(/\]\((\S+?)\)/g)) add(m[1]!);
  for (const part of bareLinks(text)) if (typeof part !== "string") add(part.url);
  return out;
}

/// The chat a link with no station of its own names (`…/chats/<id>`): one of `here`'s.
function ownChat(href: string, here: string): { station: string; id: string } | null {
  const m = /\/chats\/([^/?#\s]+)\/?(?:[?#]|$)/.exec(href);
  if (!m) return null;
  try {
    return { station: here, id: decodeURIComponent(m[1]!) };
  } catch {
    return null;
  }
}

/// The station (`<workspace>/<station>`) a link to a chat is on, as chatOfLink reads it; null for a link that does not say.
export function stationOfLink(href: string): string | null {
  const m = /\/o\/([^/?#\s]+)\/([^/?#\s]+)\/[^/?#\s]+/.exec(href) ?? /\/w\/([^/?#\s]+)\/s\/([^/?#\s]+)\/chats\//.exec(href);
  return m ? `${m[1]}/${m[2]}` : null;
}

/// The screen a link names, when it is one of a station's screens (`…/w/<workspace>/s/<station>/screen/<id>`, as its
/// agents' `screen` tool links it): its station (`<workspace>/<station>`) and its id. Null otherwise.
export function screenOfLink(href: string): { station: string; screen: string } | null {
  const m = /^(?:https?:\/\/[^/]+)?\/w\/([^/?#\s]+)\/s\/([^/?#\s]+)\/screen\/([^/?#\s]+)\/?$/.exec(href);
  if (!m) return null;
  try {
    return { station: `${decodeURIComponent(m[1]!)}/${decodeURIComponent(m[2]!)}`, screen: decodeURIComponent(m[3]!) };
  } catch {
    return null;
  }
}

/// The station a link to its 共享调试 names (`…/w/<workspace>/s/<station>/adb`, as its agents' `adb_devices` tool links
/// it: docs/adb-share.md), as `<workspace>/<station>`. Null otherwise.
export function adbOfLink(href: string): string | null {
  const m = /^(?:https?:\/\/[^/]+)?\/w\/([^/?#\s]+)\/s\/([^/?#\s]+)\/adb\/?$/.exec(href);
  if (!m) return null;
  try {
    return `${decodeURIComponent(m[1]!)}/${decodeURIComponent(m[2]!)}`;
  } catch {
    return null;
  }
}

/// The web service a link names: a chat's item with its service, as its agent links to it
/// (`…/o/<workspace>/<station>/<chat>?service=<job>`, after a host or alone): its station and its job. Null otherwise.
export function serviceOfLink(href: string): { station: string; job: string } | null {
  const m = /^(?:https?:\/\/[^/]+)?\/o\/([^/?#\s]+)\/([^/?#\s]+)\/[^/?#\s]+\/?\?([^#]*)/.exec(href);
  if (!m) return null;
  const job = new URLSearchParams(m[3]!).get("service");
  if (!job) return null;
  try {
    return { station: `${decodeURIComponent(m[1]!)}/${decodeURIComponent(m[2]!)}`, job };
  } catch {
    return null;
  }
}

/// What a link is to, as every client draws it: a chat's (`chat`: a reference to it), a screen's, a station's 共享调试 or
/// a chat's web service's (`card`: a card alone in a paragraph, its title bare in a sentence), with what names it.
/// Null for any other link. The clients take it from the core with each link (markdown.ts, personWords), reading none
/// of it themselves.
export type LinkTo = { chat?: true; card?: "screen" | "adb" | "service"; station?: string; screen?: string; job?: string };
export function linkTo(href: string): LinkTo | null {
  const chat = isChatLink(href) ? { chat: true as const } : {};
  const screen = screenOfLink(href);
  if (screen) return { ...chat, card: "screen", station: screen.station, screen: screen.screen };
  const adb = adbOfLink(href);
  if (adb) return { ...chat, card: "adb", station: adb };
  const service = serviceOfLink(href);
  if (service) return { ...chat, card: "service", station: service.station, job: service.job };
  return chat.chat ? chat : null;
}

/// The `@words` the caret is at the end of (`@` and a few letters ask for a chat to refer to), and where its `@` is;
/// null when it is in none.
export function refAt(text: string, caret: number): { start: number; query: string } | null {
  const m = /(?:^|\s)@([^\s@[\]()]{0,40})$/.exec(text.slice(0, caret));
  return m ? { start: caret - m[1]!.length - 1, query: m[1]! } : null;
}

/// Where the mark just before `caret` starts (a backspace there takes it whole), or null.
export function markBefore(text: string, caret: number): number | null {
  const m = /@\[[^\]\n]{1,120}\]$/.exec(text.slice(0, caret));
  return m ? m.index : null;
}

/// The marks in what is written, each where it starts and ends and its title (drawn as a chip).
export function marksIn(text: string): { start: number; end: number; title: string }[] {
  return [...text.matchAll(new RegExp(REF_MARK.source, "g"))].map((m) => ({ start: m.index, end: m.index + m[0].length, title: m[1]! }));
}

/// The chats' links in what is pasted as a chat's link is copied (`[its title](its link)`) that name a chat of the
/// workspace of the station `here` is (a station of no workspace: none): where each is in `pasted`, its title, its
/// chat (its station, its key) and what follows its link when it is its agent's execution history or one of its
/// messages (`history`: the composer puts it back on the link it keeps).
export function pastedRefs(pasted: string, here: string): { start: number; end: number; title: string; station: string; id: string; history: string }[] {
  const scope = (station: string) => station.split("/")[0]!;
  if (!here.includes("/")) return [];
  return [...pasted.matchAll(/\[([^\]\n]{1,120})\]\((\S+?)\)/g)].flatMap((m) => {
    const chat = chatOfLink(m[2]!);
    return chat && scope(chat.station) === scope(here) ? [{ start: m.index, end: m.index + m[0].length, title: m[1]!, station: chat.station, id: chat.id, history: chat.history || chat.message }] : [];
  });
}

/// A run of a person's words as the clients draw it: as they wrote it, a web address written bare (`link`), or a
/// reference to a chat (`ref`: its title is `text` where they wrote one, `[title](its page)`; a chat's page written bare
/// is one too, `text` its address, the message's `chats` saying its title).
export type WordsRun = { text: string; link?: string; ref?: true; to?: LinkTo };

/// What a person wrote, in runs (WordsRun): references to chats, and web addresses written bare (bareLinks.ts). The one
/// reading the clients draw a person's words by (apps/mbui sfbase/message_words.mbt for words not the core's yet).
export function personWords(text: string): WordsRun[] {
  const out: WordsRun[] = [];
  for (const part of splitBy(text, REF_LINK)) {
    if (typeof part !== "string") {
      const to = linkTo(part[2]!);
      out.push({ text: part[1]!, link: part[2]!, ref: true, ...(to ? { to } : {}) });
      continue;
    }
    for (const bit of bareLinks(part)) {
      if (typeof bit === "string") {
        if (bit !== "") out.push({ text: bit });
      } else {
        const to = linkTo(bit.url);
        out.push({ text: bit.url, link: bit.url, ...(to?.chat ? { ref: true as const } : {}), ...(to ? { to } : {}) });
      }
    }
  }
  return out;
}

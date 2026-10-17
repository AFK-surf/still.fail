// Copying a chat's link, to paste into another chat for its agent to read (web chatRefs.ts shareLink, copyChatLink):
// from its row's menu (Home.tsx rowMenu) and from its own sheet (ChatInfo.tsx).
import * as Clipboard from "expo-clipboard";
import type { app as App } from "../AppState";
import { t } from "../i18n";

/**
 * A chat's still.fail link, `<cloud>/o/<workspace>/<station>/<session>`, as web's shareLink makes it. Null for a station
 * of no workspace (no `/` in its address) or a chat its station has not given a session yet: neither has one.
 */
export function chatLink(cloud: string, station: string, session: string): string | null {
  const at = station.indexOf("/");
  if (at <= 0 || at === station.length - 1 || session.length === 0) return null;
  return `${cloud.replace(/\/+$/, "")}/o/${station.substring(0, at)}/${station.substring(at + 1)}/${encodeComponent(session)}`;
}

/** As JavaScript's encodeURIComponent (what web's link has): here it is that. */
export function encodeComponent(s: string): string {
  return encodeURIComponent(s);
}

/** A chat a link names (web chatRefs.ts chatOfLink): its station (`<workspace>/<station>`), its key, and `?history=…` after it, or "". */
export interface LinkedChat { station: string; id: string; history: string }

const SHARED = /\/o\/([^/?#\s]+)\/([^/?#\s]+)\/([^/?#\s]+)\/?(\?history=[^&#\s]+(?:&entry=\d+)?)?$/;
const PAGE = /\/w\/([^/?#\s]+)\/s\/([^/?#\s]+)\/chats\/([^/?#\s]+)\/?(\?history=[^&#\s]+(?:&entry=\d+)?)?$/;

/** The chat a link names: a still.fail link (`…/o/<workspace>/<station>/<session>`) or its page (`…/w/<workspace>/s/<station>/chats/<id>`); null otherwise. */
export function chatOfLink(href: string): LinkedChat | null {
  const m = SHARED.exec(href) ?? PAGE.exec(href);
  if (!m) return null;
  let id: string;
  try {
    id = decodeURIComponent(m[3]!);
  } catch {
    return null;
  }
  return { station: `${m[1]}/${m[2]}`, id, history: m[4] ?? "" };
}

/** An IntRange: `first` to `last`, both in. */
export interface IntRange { first: number; last: number }
/** A match of a pasted reference: where it is in the text, all of it, and its groups (Kotlin's MatchResult). */
export interface RefMatch { range: IntRange; value: string; groupValues: string[] }

const PASTED_REF = /\[([^\]\n]{1,120})\]\((\S+?)\)/g;

/**
 * The chats' links in `text`, `[its title](its link)` as one is copied (copyChatLink), of the workspace of `here` (the
 * station written on; one of no workspace has none), as web's composer takes them when pasted (Chat.tsx pasteReferences).
 */
export function linkedRefs(text: string, here: string): [RefMatch, LinkedChat][] {
  if (!here.includes("/")) return [];
  const workspace = here.substring(0, here.indexOf("/"));
  const out: [RefMatch, LinkedChat][] = [];
  for (const m of text.matchAll(PASTED_REF)) {
    const chat = chatOfLink(m[2]!);
    if (!chat || chat.station.substring(0, chat.station.indexOf("/")) !== workspace) continue;
    const first = m.index;
    out.push([{ range: { first, last: first + m[0].length - 1 }, value: m[0], groupValues: [m[0], m[1]!, m[2]!] }, chat]);
  }
  return out;
}

/** Where one change put text in (a paste): the range in `now` that is not in `was`; null when nothing went in. */
export function insertedRange(was: string, now: string): IntRange | null {
  const most = Math.min(was.length, now.length);
  let start = 0;
  while (start < most && was[start] === now[start]) start++;
  let end = 0;
  while (end < most - start && was[was.length - 1 - end] === now[now.length - 1 - end]) end++;
  return now.length - end > start ? { first: start, last: now.length - end - 1 } : null;
}

/** What goes on the clipboard as text: `[title](link)`, as a reference is sent; the title kept to a line of 120 at most. */
export function chatLinkText(title: string, link: string): [shown: string, plain: string] {
  const trimmed = title.replace(/[[\]\n]/g, " ").trim();
  const whole = trimmed.length > 0 ? trimmed : link;
  const points = Array.from(whole);
  const shown = points.length > 120 ? points.slice(0, 120).join("") : whole;
  return [shown, `[${shown}](${link})`];
}

/**
 * Puts a chat's link on the clipboard: `[title](link)` for plain text (a composer, where it becomes a reference again,
 * or a terminal), and a link for what takes HTML (Slack, documents). A toast says it is copied, or why not. (The
 * Android app's `context` is not needed here: it may be given, as there, or left out.)
 */
export function copyChatLink(app: typeof App, ...rest: [context: unknown, title: string, link: string] | [title: string, link: string]): void {
  const [title, link] = (rest.length === 3 ? rest.slice(1) : rest) as [string, string];
  const [, plain] = chatLinkText(title, link);
  // NATIVE: expo-clipboard puts plain text or HTML (with its own plain text taken from the HTML), not both as
  // ClipData.newHtmlText does: the plain `[title](link)` is what goes, without the `<a href>` beside it for Slack.
  Clipboard.setStringAsync(plain).then(
    () => { app.toast = t("web-main.chat.linkCopied"); },
    (e: unknown) => { app.toast = t("web-main.chat.copyFailed", { error: e instanceof Error ? e.message : String(e) }); },
  );
}

// References to other chats in what is written, and finding chats by a few words (refs.rs): the `chatSearch` view
// (the composer's `@` menu and ⌘K's switcher). In the composer a reference is a short mark, `@[its title]`; sent, a
// link, `[its title](its page)`. The link of each title picked (`chat.ref`) is kept on the device, the latest 200 of
// each workspace, and a mark is made its link as it is sent in a chat of the same workspace.
import type { Data } from "./data.ts";
import { t } from "./i18n.ts";
import { encode } from "./ops.ts";
import { ofAddress } from "./workspace.ts";
import { arr as arrU, get as getU } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

const TABLE = "chat_ref";
const KEY = "links";
export const KEPT = 200;
const TITLE = 24;
const MARK_MAX = 120;

/// A chat's title, as a reference shows it: its start, on one line.
export function title(full: string): string {
  const plain = full.replace(/[[\]\n]/g, " ");
  const words = plain.split(/\s+/).filter((w) => w !== "").join(" ");
  const chars = Array.from(words);
  const shown = chars.length > TITLE ? `${chars.slice(0, TITLE).join("").trimEnd()}…` : words;
  return shown === "" ? t("core-logic.refs.untitled") : shown;
}

/// A chat's page: under `base` (still.fail cloud), its station's pages, then the chat.
export function link(base: string, station: string, id: string): string {
  const at = station.indexOf("/");
  const under = at >= 0 ? `/w/${station.slice(0, at)}/s/${station.slice(at + 1)}` : "";
  return `${base.replace(/\/+$/, "")}${under}/chats/${encode(id)}`;
}

function workspaceOf(l: string): string | null {
  const parts = l.split("/");
  for (let i = 0; i + 2 < parts.length; i++) if (parts[i] === "w" && parts[i + 2] === "s") return parts[i + 1];
  return null;
}

function record(data: Data, key: string): [string, string][] {
  return arr(data.record(TABLE, key)).flatMap((pair) => (Array.isArray(pair) && typeof pair[0] === "string" && typeof pair[1] === "string" ? [[pair[0], pair[1]] as [string, string]] : []));
}

function links(data: Data, workspace: string): [string, string][] {
  return [...record(data, KEY).filter(([, l]) => workspaceOf(l) === workspace), ...record(data, `${KEY}:${workspace}`)];
}

/// Keeps these links (title, link), each with its workspace's, the latest, the oldest going past 200.
export function keep(data: Data, added: Iterable<[string, string]>): void {
  const by = new Map<string, [string, string][]>();
  for (const [ti, l] of added) {
    const workspace = workspaceOf(l);
    if (workspace === null || ti === "") continue;
    let all = by.get(workspace);
    if (!all) {
      all = record(data, `${KEY}:${workspace}`);
      by.set(workspace, all);
    }
    const kept = all.filter(([x]) => x !== ti);
    kept.push([ti, l]);
    by.set(workspace, kept);
  }
  for (const [workspace, all] of [...by].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
    data.put(TABLE, `${KEY}:${workspace}`, all.slice(Math.max(all.length - KEPT, 0)));
  }
}

/// The mark for a chat picked, its link kept until the mark is sent.
export function mark(data: Data, base: string, station: string, id: string, fullTitle: string): string {
  const ti = title(fullTitle);
  keep(data, [[ti, link(base, station, id)]]);
  return `@[${ti}]`;
}

/// What is written in a chat on `station`, its marks made links to chats of its workspace.
export function expand(data: Data, station: string, text: string): string {
  if (!text.includes("@[")) return text;
  const all = links(data, ofAddress(station));
  let out = "";
  let rest = text;
  for (;;) {
    const at = rest.indexOf("@[");
    if (at < 0) break;
    out += rest.slice(0, at);
    const after = rest.slice(at + 2);
    const m = after.search(/[\]\n]/);
    const found = m >= 0 && after[m] === "]" ? after.slice(0, m) : null;
    if (found !== null && found !== "" && Array.from(found).length <= MARK_MAX) {
      const hit = [...all].reverse().find(([x]) => x === found);
      out += hit ? `[${found}](${hit[1]})` : `@[${found}]`;
      rest = after.slice(found.length + 1);
    } else {
      out += "@[";
      rest = after;
    }
  }
  return out + rest;
}

/// What `query` finds among a `chats` view's rows.
export function search(chats: J, query: string, station: string | null | undefined, exclude: string | null | undefined, limit: number | null | undefined): J {
  const q = query.trim().toLowerCase();
  const has = (v: J) => typeof v === "string" && v.toLowerCase().includes(q);
  const rows = arr(get(chats, "days")).flatMap((d) => arr(get(d, "items")));
  const candidates = rows
    .filter((i) => get(i, "pending") !== true)
    .filter((i) => station == null || get(i, "station") === station)
    .filter((i) => exclude == null || ["id", "session"].every((f) => get(i, f) !== exclude));
  const titled = candidates.filter((i) => q === "" || has(get(i, "title")));
  const rest = candidates.filter(
    (i) =>
      q !== "" &&
      !has(get(i, "title")) &&
      (arr(get(i, "agents")).some((a) => has(get(a, "agentText"))) || has(get(i, "stationName")) || has(get(i, "originText")) || has(get(get(i, "last"), "preview"))),
  );
  return { items: [...titled, ...rest].slice(0, limit ?? Infinity) };
}

/// The words a search looks for: what is typed, split at spaces, each to be found (case aside).
export function terms(query: string): string[] {
  return [...new Set(query.toLowerCase().split(/\s+/).filter((w) => w !== ""))];
}

/// How much of a line goes before the first word found, at most, when the line is cut to show it.
const LEAD = 24;
/// How much of a line a found message gives (the page fits it to its width).
const LINE_MAX = 240;

/// The line of a message's text that has what was looked for, as a found message shows it: Markdown's marks out, on one
/// line, its start cut (`…`) when the word found lies far into it; and where the words are in it, as UTF-16 ranges.
export function excerpt(text: string, words: string[]): { text: string; marks: { from: number; to: number }[] } {
  const plain = text
    .replace(/^ {0,3}(```|~~~).*$/gm, "")
    .replace(/!?\[([^\]\n]*)\]\([^)\s]*\)/g, "$1")
    .replace(/<((?:https?|mailto):[^>\s]+)>/g, "$1")
    .replace(/(\*\*|__|~~|`)/g, "")
    .replace(/^ {0,3}(#{1,6} |> ?|[-*+] |\d+[.)] )/gm, "");
  const lines = plain.split("\n").map((l) => l.replace(/\s+/g, " ").trim()).filter((l) => l !== "");
  const has = (line: string, w: string) => line.toLowerCase().includes(w);
  const line = lines.find((l) => words.every((w) => has(l, w))) ?? lines.find((l) => words.some((w) => has(l, w))) ?? lines[0] ?? "";
  const lower = line.toLowerCase();
  const first = Math.min(...words.map((w) => lower.indexOf(w)).filter((i) => i >= 0), Infinity);
  let start = 0;
  if (first !== Infinity && first > LEAD) {
    start = first - LEAD;
    // At a word's start where there is one near.
    const space = line.indexOf(" ", start);
    if (space >= 0 && space < first) start = space + 1;
  }
  const lead = start > 0 ? "…" : "";
  const body = line.slice(start, start + LINE_MAX);
  const shown = lead + body;
  const low = shown.toLowerCase();
  const found: [number, number][] = [];
  if (low.length === shown.length) {
    for (const w of words) {
      for (let at = low.indexOf(w); at >= 0; at = low.indexOf(w, at + w.length)) found.push([at, at + w.length]);
    }
  }
  found.sort((a, b) => a[0] - b[0]);
  const marks: { from: number; to: number }[] = [];
  for (const [from, to] of found) {
    const last = marks[marks.length - 1];
    if (last && from <= last.to) last.to = Math.max(last.to, to);
    else marks.push({ from, to });
  }
  return { text: shown, marks };
}

/// The chat a draft's key names, as the pages key them: `new:<station>` a new chat there, else `<station>:<chat>`.
export function draftAt(key: string): [string, string] | null {
  if (key.startsWith("new:")) {
    const station = key.slice(4);
    return station !== "" ? [station, "new"] : null;
  }
  const at = key.indexOf(":");
  if (at < 0) return null;
  const station = key.slice(0, at);
  const chat = key.slice(at + 1);
  return station !== "" && chat !== "" ? [station, chat] : null;
}

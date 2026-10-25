// What a search finds among what the station has (docs/search.md): nothing is indexed, everything is looked through as
// it is asked for (search/worker.ts reads it). Each thing found is a document: its kind, whom it is for (the workspace
// it is in, and a scope a viewer must have), what it is called, what it says, when, and what opens it.
import { opensTo } from "../store/rows.ts";

export type Doc = {
  /// Unique among all documents: its kind's and its own (`m:<thread>:<n>`, `h:<session>:<i>`…).
  key: string;
  kind: string;
  /// The workspace it is in: null the station's home one, `*` every workspace's members.
  ws: string | null;
  /// What else a viewer must have (`write`: a member who may write); null: none.
  scope?: string | null;
  /// The people it is private to (a direct message's chat, docs/private-chats.md); absent or null: none.
  to?: string[] | null;
  title: string;
  body: string;
  at: number | null;
  /// What opens it, as the clients and agents are told.
  ref: Record<string, unknown>;
};

/// Whom a search is for: their workspace, whether it is the station's home one, and the scopes they have; `reader`:
/// those who see what it finds (store/rows.ts `opensTo`; absent: anyone, so nothing private).
export type Asker = { workspace: string; home: boolean; scopes: string[]; reader?: string[] | null };

export type Hit = { kind: string; key: string; title: string; text: string; at: number | null } & Record<string, unknown>;
/// `left`: the sessions whose execution history was not looked through, the time being up.
export type Group = { kind: string; hits: Hit[]; more: boolean; left?: number };

/// How much of a body a hit says: around where the words are.
const BEFORE = 80;
const AFTER = 240;

/// The words of a query: split at white space, each once, case aside; at most eight.
export function terms(query: string): string[] {
  const out: string[] = [];
  for (const t of query.trim().split(/\s+/u)) {
    const w = t.toLowerCase();
    if (w !== "" && !out.includes(w)) out.push(w);
  }
  return out.slice(0, 8);
}

/// Where a body has the first of the words, and that part of it on one line: `…` where it is cut.
export function excerpt(body: string, words: string[]): string {
  const flat = body.replace(/\s+/gu, " ").trim();
  const lower = flat.toLowerCase();
  let at = -1;
  for (const w of words) {
    const i = lower.indexOf(w);
    if (i >= 0 && (at < 0 || i < at)) at = i;
  }
  if (at < 0) at = 0;
  const from = Math.max(0, at - BEFORE);
  const to = Math.min(flat.length, at + AFTER);
  return `${from > 0 ? "…" : ""}${flat.slice(from, to)}${to < flat.length ? "…" : ""}`;
}

/// Whether `asker` may see `doc`.
export const sees = (doc: Pick<Doc, "ws" | "scope" | "to">, asker: Asker): boolean =>
  (doc.ws === "*" || doc.ws === asker.workspace || (doc.ws === null && asker.home)) && (doc.scope == null || asker.scopes.includes(doc.scope)) &&
  opensTo(asker.reader, doc.to);

/// Whether a text has every word, case aside.
export const has = (text: string, words: string[]): boolean => {
  const lower = text.toLowerCase();
  return words.every((w) => lower.includes(w));
};

/// A document as a hit, said around the words (a chat's from its title when that has them: a long one is cut where it is
/// listed).
export const hitOf = (d: Doc, words: string[]): Hit => ({ ...d.ref, kind: d.kind, key: d.key, title: d.title, text: excerpt(d.kind === "chat" && has(d.title, words) ? d.title : d.body, words), at: d.at });

/**
 * What of `docs` the words find for `asker`, by kind, `limit` of each from `offset`: those whose title has the first word
 * first, then the newest. Every word must be in its title or body.
 */
export function pick(docs: Iterable<Doc>, words: string[], asker: Asker, options: { limit?: number; offset?: number } = {}): Group[] {
  if (words.length === 0) return [];
  const limit = Math.max(1, Math.min(options.limit ?? 8, 200));
  const offset = Math.max(0, options.offset ?? 0);
  const byKind = new Map<string, { d: Doc; titled: boolean }[]>();
  for (const d of docs) {
    if (!sees(d, asker) || !has(`${d.title}\n${d.body}`, words)) continue;
    const list = byKind.get(d.kind) ?? [];
    list.push({ d, titled: d.title.toLowerCase().includes(words[0]!) });
    byKind.set(d.kind, list);
  }
  const out: Group[] = [];
  for (const kind of [...byKind.keys()].sort()) {
    const list = byKind.get(kind)!;
    list.sort((a, b) => Number(b.titled) - Number(a.titled) || (a.d.at === null ? 1 : 0) - (b.d.at === null ? 1 : 0) || (b.d.at ?? 0) - (a.d.at ?? 0));
    const page = list.slice(offset, offset + limit);
    if (page.length === 0) continue;
    out.push({ kind, more: list.length > offset + limit, hits: page.map((x) => hitOf(x.d, words)) });
  }
  return out;
}

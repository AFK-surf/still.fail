// What a search finds among what the station has (docs/search.md): nothing is indexed, everything is looked through as
// it is asked for (search/worker.ts reads it). Each thing found is a document: its kind, whom it is for (the workspace
// it is in, and a scope a viewer must have), what it is called, what it says, when, and what opens it.

export type Doc = {
  /// Unique among all documents: its kind's and its own (`m:<thread>:<n>`, `h:<session>:<i>`…).
  key: string;
  kind: string;
  /// The workspace it is in: null the station's home one, `*` every workspace's members.
  ws: string | null;
  /// What else a viewer must have (`write`: a member who may write); null: none.
  scope?: string | null;
  title: string;
  body: string;
  at: number | null;
  /// What opens it, as the clients and agents are told.
  ref: Record<string, unknown>;
};

/// Whom a search is for: their workspace, whether it is the station's home one, and the scopes they have.
/// `typist`: the device of a person typing the search (a search of theirs typed on takes the place of the one before:
/// files.ts); none for an agent's or another station's.
/// `again`: a search a client shows asked again as the station's chats changed (`again=1`), not words typed.
export type Asker = { workspace: string; home: boolean; scopes: string[]; typist?: string; again?: boolean };

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
export const sees = (doc: Pick<Doc, "ws" | "scope">, asker: Asker): boolean =>
  (doc.ws === "*" || doc.ws === asker.workspace || (doc.ws === null && asker.home)) && (doc.scope == null || asker.scopes.includes(doc.scope));

/// Whether a text has every word, case aside.
export const has = (text: string, words: string[]): boolean => {
  const lower = text.toLowerCase();
  return words.every((w) => lower.includes(w));
};

/// A document as a hit, said around the words (a chat's from its title when that has them: a long one is cut where it is
/// listed).
export const hitOf = (d: Doc, words: string[]): Hit => ({ ...d.ref, kind: d.kind, key: d.key, title: d.title, text: excerpt(d.kind === "chat" && has(d.title, words) ? d.title : d.body, words), at: d.at });

type Ranked = { titled: boolean; at: number | null; order: number; hit: Hit };

// Negative when a belongs before b. The input order breaks ties, as a stable sort of the original documents did.
const compare = (a: Pick<Ranked, "titled" | "at" | "order">, b: Pick<Ranked, "titled" | "at" | "order">): number =>
  Number(b.titled) - Number(a.titled) || Number(a.at === null) - Number(b.at === null) || (b.at ?? 0) - (a.at ?? 0) || a.order - b.order;

/// Keep only enough matches for the requested page. Each kind has a heap with its worst retained result at the root.
class Pages {
  readonly #words: string[];
  readonly #asker: Asker;
  readonly #limit: number;
  readonly #offset: number;
  readonly #want: number;
  readonly #kinds = new Map<string, { heap: Ranked[]; count: number }>();
  #order = 0;

  constructor(words: string[], asker: Asker, options: { limit?: number; offset?: number }) {
    this.#words = words;
    this.#asker = asker;
    this.#limit = Math.max(1, Math.min(options.limit ?? 8, 200));
    this.#offset = Math.max(0, options.offset ?? 0);
    this.#want = this.#offset + this.#limit;
  }

  add(d: Doc): void {
    if (!sees(d, this.#asker)) return;
    const title = d.title, body = d.body;
    if (!has(`${title}\n${body}`, this.#words)) return;
    const list = this.#kinds.get(d.kind) ?? { heap: [], count: 0 };
    this.#kinds.set(d.kind, list);
    list.count++;
    const key = { titled: title.toLowerCase().includes(this.#words[0]!), at: d.at, order: this.#order++ };
    const heap = list.heap;
    if (heap.length >= this.#want && compare(key, heap[0]!) >= 0) return;
    const hit: Hit = { ...d.ref, kind: d.kind, key: d.key, title, text: excerpt(d.kind === "chat" && has(title, this.#words) ? title : body, this.#words), at: key.at };
    const ranked = { ...key, hit };
    if (heap.length < this.#want) {
      let i = heap.push(ranked) - 1;
      while (i > 0) {
        const parent = Math.floor((i - 1) / 2);
        if (compare(heap[i]!, heap[parent]!) <= 0) break;
        [heap[i], heap[parent]] = [heap[parent]!, heap[i]!];
        i = parent;
      }
    } else {
      heap[0] = ranked;
      let i = 0;
      for (;;) {
        const left = i * 2 + 1, right = left + 1;
        if (left >= heap.length) break;
        const worst = right < heap.length && compare(heap[right]!, heap[left]!) > 0 ? right : left;
        if (compare(heap[worst]!, heap[i]!) <= 0) break;
        [heap[i], heap[worst]] = [heap[worst]!, heap[i]!];
        i = worst;
      }
    }
  }

  result(): Group[] {
    const out: Group[] = [];
    for (const kind of [...this.#kinds.keys()].sort()) {
      const { heap, count } = this.#kinds.get(kind)!;
      heap.sort(compare);
      const hits = heap.slice(this.#offset, this.#offset + this.#limit).map((x) => x.hit);
      if (hits.length > 0) out.push({ kind, more: count > this.#want, hits });
    }
    return out;
  }
}

/**
 * What of `docs` the words find for `asker`, by kind, `limit` of each from `offset`: those whose title has the first word
 * first, then the newest. Every word must be in its title or body.
 */
export function pick(docs: Iterable<Doc>, words: string[], asker: Asker, options: { limit?: number; offset?: number } = {}): Group[] {
  if (words.length === 0) return [];
  const pages = new Pages(words, asker, options);
  for (const d of docs) pages.add(d);
  return pages.result();
}

/// The worker gives other searches a turn between bounded batches; undefined marks a source batch with no documents.
export async function pickAsync(docs: Iterable<Doc | undefined>, words: string[], asker: Asker, options: { limit?: number; offset?: number } = {}, cancelled: () => boolean = () => false): Promise<Group[]> {
  if (words.length === 0) return [];
  const pages = new Pages(words, asker, options);
  let processed = 0;
  for (const d of docs) {
    if (cancelled()) throw new Error("the search took too long");
    if (d !== undefined) pages.add(d);
    if (d === undefined || ++processed % 128 === 0) await new Promise<void>((resolve) => setImmediate(resolve));
  }
  if (cancelled()) throw new Error("the search took too long");
  return pages.result();
}

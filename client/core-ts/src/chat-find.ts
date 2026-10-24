// A chat's own find (⌘F: web/src/ChatFind.tsx, the mbui app's sfdesk/find.mbt): which of the times the words are in the
// chat the reader is at, as they go along them. What the core found (`chat.find`) is its `hits`, the messages that
// have the words (oldest first) with how many times each; the reader is at the `k`th time in message `seq`. What the
// view knows is given: the messages showing (where the reader starts) and how many times a message's row draws the
// words (its text's marks or a link's address are not words in it: fewer than the core counted). Asked of the core as
// `chat.find.go`; self-contained: the web imports it, typechecked as the web is.

/// A message that has the words, and how many times.
export type FindHit = { seq: number; count: number };
/// The time the reader is at: the `k`th in message `seq`.
export type FindAt = { seq: number; k: number };
/// Where the reader is, and which of how many times that is (1 the first; 0 none).
export type FindPlace = { at: FindAt | null; position: number; total: number };

/// Where the reader starts among `hits`: one in the messages showing (from `from` to `to`, their seqs; null none
/// showing), else the nearest before them, else the first.
export function findStart(hits: readonly FindHit[], from: number | null, to: number | null): FindAt | null {
  let hit: FindHit | undefined;
  if (from !== null && to !== null) hit = hits.find((h) => h.seq >= from && h.seq <= to);
  if (!hit && from !== null) for (const h of hits) if (h.seq < from) hit = h;
  hit ??= hits[0];
  return hit ? { seq: hit.seq, k: 0 } : null;
}

/// The next time the words are in the chat (`by` 1) or the one before (-1), round from an end to the other. How many
/// times a message is gone along is as many as its row draws (`drawn`, by seq: where it is drawn and draws some),
/// else as many as the core counted.
export function findStep(hits: readonly FindHit[], at: FindAt | null, by: 1 | -1, drawn: Readonly<Record<string, number>> = {}): FindAt | null {
  if (hits.length === 0) return null;
  const i = at ? hits.findIndex((h) => h.seq === at.seq) : -1;
  if (i < 0 || !at) {
    const end = hits[by > 0 ? 0 : hits.length - 1];
    return end ? { seq: end.seq, k: 0 } : null;
  }
  const times = (h: FindHit) => {
    const n = drawn[String(h.seq)] ?? 0;
    return n > 0 ? Math.min(n, h.count) : h.count;
  };
  const here = hits[i];
  const k = at.k + by;
  if (here && k >= 0 && k < times(here)) return { seq: at.seq, k };
  const next = hits[(i + by + hits.length) % hits.length];
  return next ? { seq: next.seq, k: by > 0 ? 0 : Math.max(0, times(next) - 1) } : null;
}

/// Which of how many times the words are in the chat the reader at `at` is at.
export function findPlace(hits: readonly FindHit[], at: FindAt | null): FindPlace {
  const total = hits.reduce((n, h) => n + h.count, 0);
  const i = at ? hits.findIndex((h) => h.seq === at.seq) : -1;
  const here = hits[i];
  if (!at || !here) return { at: null, position: 0, total };
  const before = hits.slice(0, i).reduce((n, h) => n + h.count, 0);
  return { at, position: before + Math.min(at.k, here.count - 1) + 1, total };
}

/// `chat.find.go`: with `by` 0 where the reader is (`at`, while what was found still has its message: more of the chat
/// read since), else where they start (from the messages showing); else the next or the one before from where they
/// are; and which of how many times that is.
export function findGo(hits: readonly FindHit[], at: FindAt | null, by: -1 | 0 | 1, from: number | null, to: number | null,
  drawn: Readonly<Record<string, number>> = {}): FindPlace {
  if (by !== 0) return findPlace(hits, findStep(hits, at, by, drawn));
  const kept = at && hits.some((h) => h.seq === at.seq) ? at : null;
  return findPlace(hits, kept ?? findStart(hits, from, to));
}

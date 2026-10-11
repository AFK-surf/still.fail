// Which of a chat's messages are yet to be brought onto the device, from two things only: the entry numbers held of
// its thread (in order), and how far the thread goes as far as is known (`last`: its summary's, raised by anything
// that says it goes further). Entries are numbered from 1 without gaps; the device holds some run ending at the latest
// it heard, with holes where something told went missing, and nothing before the page it opened at until that is
// scrolled back to or brought with the station's history.
//
// Nothing here asks anything: sync.ts reads what these say to read.

/// One read of a thread's entries: its latest page; what came after an entry; or a stretch of them (both included).
export type Fill = { latest: true } | { after: number } | { from: number; to: number };

/// The highest entry not held, up to how far the thread goes; null when every one is held.
export function missing(held: number[], last: number): number | null {
  let n = Math.max(last, held.length > 0 ? held[held.length - 1]! : 0);
  for (let i = held.length - 1; n >= 1; n--) {
    while (i >= 0 && held[i]! > n) i--;
    if (i < 0 || held[i] !== n) return n;
  }
  return null;
}

/// The read that brings the next of a thread's entries: its latest page when none is held; what came after what is
/// held; then the highest hole (from just past the held entry below it, `page` entries at most); null when it has them
/// all.
export function next(held: number[], last: number, page: number): Fill | null {
  if (held.length === 0) return { latest: true };
  const top = held[held.length - 1]!;
  if (last > top) return { after: top };
  const hole = missing(held, last);
  if (hole === null) return null;
  let below = 0;
  for (const n of held) if (n < hole && n > below) below = n;
  return { from: Math.max(below + 1, hole - page + 1), to: hole };
}

/// Whether entries are missing between the lowest held and the latest (a hole what was told left), as against history
/// older than what is held.
export function holeAbove(held: number[], last: number): boolean {
  if (held.length === 0) return false;
  const hole = missing(held, last);
  return hole !== null && hole > held[0]!;
}

/// Whether a thread's latest entries are not held: none is (`top`: the highest held, null), or it goes further.
export function latestMissing(top: number | null, last: number): boolean {
  return top === null || last > top;
}

/// A read as GET /threads/:id/entries takes it.
export function path(thread: number, fill: Fill, page: number): string {
  if ("latest" in fill) return `/threads/${thread}/entries?limit=${page}`;
  if ("after" in fill) return `/threads/${thread}/entries?after=${fill.after}`;
  return `/threads/${thread}/entries?from=${fill.from}&to=${fill.to}`;
}

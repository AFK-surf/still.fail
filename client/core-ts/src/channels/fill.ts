// Which of a channel's items are yet to be brought onto the device (channels.ts), from two things only: the numbers held
// of it (in order), and how far it goes as far as is known (`last`, raised by anything that says it goes further). A
// channel's items are numbered without gaps and only added to; the device holds some run of them ending at the latest
// it heard, with holes where something told went missing, and nothing before the page it began at until that is asked
// for or brought in the background.
//
// Nothing here asks anything, or knows what a channel is of: channels.ts reads what these say to read.

import { lowerBound } from "../ordered.ts";

/// One read of a channel: its latest page; what came after an item; a stretch of them (both included); or the page
/// before an item.
/// `whole` (a stretch): its items as they are, where a channel's are otherwise read in brief (a transcript's step opened).
export type Read = { latest: true } | { after: number } | { from: number; to: number; whole?: boolean } | { before: number };

/// The highest item not held, up to how far the channel goes; null when every one is held.
export function missing(held: readonly number[], last: number): number | null {
  if (held.length === 0) return last >= 1 ? last : null;
  const top = held[held.length - 1]!;
  if (last > top) return last;
  // In sorted unique numbers, held[i] - i never decreases. Its highest value names the contiguous suffix;
  // the hole immediately below that suffix is the highest missing number.
  const offset = top - held.length + 1;
  let lo = 0, hi = held.length - 1;
  while (lo < hi) {
    const mid = lo + Math.floor((hi - lo) / 2);
    if (held[mid]! - mid < offset) lo = mid + 1;
    else hi = mid;
  }
  return held[lo]! > 1 ? held[lo]! - 1 : null;
}

/// The read that brings the next of a channel's items: its latest page when none is held; what came after what is
/// held; then the highest hole (from just past the held item below it, `page` items at most); null when it has them
/// all.
export function next(held: readonly number[], last: number, page: number): Read | null {
  if (held.length === 0) return { latest: true };
  const top = held[held.length - 1]!;
  if (last > top) return { after: top };
  const hole = missing(held, last);
  if (hole === null) return null;
  const at = lowerBound(held, hole);
  const below = at > 0 ? held[at - 1]! : 0;
  return { from: Math.max(below + 1, hole - page + 1), to: hole };
}

/// Whether the device is behind on a channel it holds some of: it goes further than what is held, or items are missing
/// between the lowest held and the latest (a hole what was told left). What is before all that is held is not that.
export function behind(held: readonly number[], last: number): boolean {
  if (held.length === 0) return false;
  const hole = missing(held, last);
  return hole !== null && hole > held[0]!;
}

/// Whether a channel's latest items are not held: none is (`top`: the highest held, null), or it goes further.
export function latestMissing(top: number | null, last: number): boolean {
  return top === null || last > top;
}

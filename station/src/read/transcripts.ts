// The transcripts a reader keeps read, in brief (transcript.ts `brief`): what the pages of a history ask for (GET
// /sessions/:key/timeline with `brief=1`), so a page of a long one is a slice of what was read before, not the whole file
// read again for each page, and a read goes on from where the last left off as the transcript grows. One reader keeps
// each session's (read/pool.ts sends its reads there). At most KEPT_ENTRIES entries are kept, the least recently read
// transcripts let go first (a reader's heap is small); a stretch read whole (a step opened) is read from the file.
import type { RuntimeKind } from "../agents/runtime.ts";
import { ChainTail } from "./tail.ts";
import { type TimelineEntry, brief } from "./transcript.ts";

export const KEPT_ENTRIES = 40_000;

/// By runtime and paths (a chain read as one), the most recently read last.
const kept = new Map<string, { chain: ChainTail; entries: number }>();

/// A chain of transcripts in brief as it is now: what was kept of it, and what was written since.
export function inBrief(runtime: RuntimeKind, paths: string[]): TimelineEntry[] {
  const key = `${runtime}\u0000${paths.join("\u0000")}`;
  const had = kept.get(key);
  kept.delete(key);
  const chain = had?.chain ?? new ChainTail(runtime, paths, brief);
  chain.read();
  const entries = chain.entries;
  kept.set(key, { chain, entries: entries.length });
  let total = 0;
  for (const k of kept.values()) total += k.entries;
  for (const [k, v] of kept) {
    if (total <= KEPT_ENTRIES || k === key) break;
    kept.delete(k);
    total -= v.entries;
  }
  return entries;
}

/// How many entries are kept, and of how many chains (for tests).
export function keptNow(): { chains: number; entries: number } {
  let entries = 0;
  for (const k of kept.values()) entries += k.entries;
  return { chains: kept.size, entries };
}

/// Lets go of all of it (for tests).
export function forgetKept(): void {
  kept.clear();
}

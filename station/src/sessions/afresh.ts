// When a session goes on in a new runtime session instead of taking up its own: its next turn runs on another account
// than the one its conversation last ran on. A prompt cache is an account's own, so taking the conversation up there
// would have the whole of it read again at full price; instead the agent reads back what it needs (session_history,
// chat_history). The runtime sessions a session ran in are kept in order (store `runtime_sessions`), and its history
// reads them as one (read/tail.ts ChainTail).
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { coldAfresh, coldWorth } from "../../../client/core-ts/src/cache-policy.ts";
import { LONG_CHAT, afresh, cleared, longChat, resumeLost, threadAddress } from "../agents/instructions.ts";
import type { Profile } from "../agents/runtime.ts";
import { log } from "../ops/log.ts";
import { find as findMachineSession } from "../read/machine.ts";
import { usageNow } from "../read/usage.ts";
import { homesFirst, transcriptPaths } from "../read/transcript.ts";
import type { Hub } from "./hub.ts";

/// The addresses of a session's threads its agent is told to read back: the recent ones (store `recentSessionThreads`),
/// and where it takes part in more, where it finds those, so that a chat with thousands of threads is not told them all.
export function threadsToldOf(hub: Hub, key: string, recent = hub.store.recentSessionThreads(key)): string[] {
  const { threads, more } = recent;
  const told = threads.map((t) => threadAddress(t.thread.channel, t.thread.threadTs));
  return more ? [...told, OLDER_THREADS] : told;
}

/// What a session's older threads left out of a list are said as.
export const OLDER_THREADS = "and older ones (chat_list finds them)";

/// What a session going on on `to` is told when it starts afresh rather than take up runtime session `id`, last run on
/// `was` (when the store has no record of it); null when it takes it up: on the account it ran on, or one not known.
export function startsAfresh(hub: Hub, key: string, id: string, to: Profile, was: string | null): string | null {
  const row = hub.store.getSession(key);
  const source = hub.store.runtimeSessionSource(key, id);
  if (row && source && source.runtime !== row.runtime) return afresh(key, threadsToldOf(hub, key));
  const from = hub.store.ranOn(key, id) ?? was;
  if (from === null || from === to.id) return null;
  return afresh(key, threadsToldOf(hub, key));
}

/// What a session whose context was cleared by hand is told as its new runtime session starts: its chats to read back;
/// cleared to go on afresh (`readBack`), what it needs of its work too, as on another account.
export function toldCleared(hub: Hub, key: string, readBack = false): string {
  const threads = threadsToldOf(hub, key);
  return readBack ? afresh(key, threads) : cleared(key, threads);
}

/// Whether session `key` started at `now` (by a message, or a notice) is to start afresh: set to in its chat, or else its
/// station (`afreshWhenCold`), its runtime session's prompt cache over (read/usage.ts `usageNow`: as its runtime told
/// what it wrote), and its context worth it. The station's default takes the estimated reread cost into account.
export function goesAfresh(hub: Hub, key: string, now: number): boolean {
  const row = hub.store.getSession(key);
  if (row?.runtimeSessionId == null) return false;
  const u = usageNow(hub.store, key);
  if (u?.lastCallAt === undefined || u.cacheMs === undefined || u.lastCallAt + u.cacheMs > now) return false;
  const { afreshWhenCold, afreshAbove } = hub.config();
  const threshold = afreshWhenCold || row.afresh === true ? afreshAbove : undefined;
  return coldWorth(u.contextTokens ?? 0, u.rereadCost, threshold, row.afresh, afreshWhenCold) && coldAfresh(row.afresh, afreshWhenCold, afreshAbove, u.rereadCost);
}

/// What a session whose runtime session could not be resumed is told as its new one starts: where its earlier
/// conversation is, to read back.
/// One continued from a terminal is told where that conversation is on the machine: its own transcript there (not the
/// station's copy, which may be what failed).
export function toldResumeLost(hub: Hub, key: string): string {
  const threads = threadsToldOf(hub, key);
  const row = hub.store.getSession(key);
  const first = hub.store.runtimeSessions(key)[0];
  const runtime = row?.runtime === "claude" || row?.runtime === "codex" ? row.runtime : null;
  const terminal = row?.cwd && first !== undefined && runtime !== null ? (findMachineSession(hub.machineRoots(), runtime, first)?.path ?? null) : null;
  return resumeLost(key, threads, terminal);
}

/// What a session compacted or gone on in a new conversation is told when its chats are long (more than `LONG_CHAT`
/// messages): to read back what people said in them. Null when they are not.
/// Counted over the threads it is told of (`threadsToldOf`): those are what it reads back.
export function toldLongChat(hub: Hub, key: string): string | null {
  const recent = hub.store.recentSessionThreads(key);
  const count = recent.threads.reduce((sum, t) => sum + hub.store.messageCount(t.thread.id), 0);
  return count > LONG_CHAT ? longChat(count, threadsToldOf(hub, key, recent)) : null;
}

/// Claude's subagents `ids` of runtime session `from`, stopped with its process, copied to session `to` (just started on
/// `on`) so that SendMessage takes them up there where they stopped: a subagent's transcript is in its session's
/// (<project>/<session>/subagents/agent-<id>.jsonl, with its .meta.json). The ids copied.
export function carrySubagents(hub: Hub, from: string, to: string, on: Profile, ids: string[]): string[] {
  if (ids.length === 0 || on.runtime !== "claude") return [];
  const { dataDir, profiles } = hub.config();
  const main = transcriptPaths("claude", dataDir, homesFirst(profiles, on.id), [from]).paths[0];
  if (!main) return [];
  const source = join(dirname(main), from, "subagents");
  // The same project's in the home it starts in (the shared one, where homes share their transcripts).
  const target = join(on.home, "projects", basename(dirname(main)), to, "subagents");
  const carried: string[] = [];
  for (const id of ids) {
    try {
      if (!existsSync(join(source, `agent-${id}.jsonl`))) continue;
      mkdirSync(target, { recursive: true });
      for (const ext of ["jsonl", "meta.json"]) if (existsSync(join(source, `agent-${id}.${ext}`))) copyFileSync(join(source, `agent-${id}.${ext}`), join(target, `agent-${id}.${ext}`));
      carried.push(id);
    } catch (error) {
      log.warn("session", "could not carry a subagent to the new runtime session", { from, to, subagent: id, error: (error as Error).message });
    }
  }
  return carried;
}

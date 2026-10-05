// When a session goes on in a new runtime session instead of taking up its own: its next turn would run on another
// account than the one its conversation last ran on, and a prompt cache is an account's own, so the whole conversation
// would be read again at full price. Past AFRESH_TOKENS that costs more than the agent reading back what it needs
// (chat_history, session_history, its files); below, it is taken up as before. The runtime sessions a session ran in
// are kept in order (store `runtime_sessions`), and its history reads them as one (live.ts ChainTail).
import { afresh, threadAddress } from "../agents/instructions.ts";
import type { Profile } from "../agents/runtime.ts";
import { lastContext, transcriptPath } from "../read/transcript.ts";
import { parseDeclared } from "./actor.ts";
import type { Hub } from "./hub.ts";
import { runtimeNamed } from "./config.ts";

/// A conversation this long (tokens given to its last request) is not taken up on another account.
export const AFRESH_TOKENS = 150_000;

/// What a session going on on `to` is told when it starts afresh rather than take up runtime session `id`, last run on
/// `was` (when the store has no record of it); null when it takes it up.
export function startsAfresh(hub: Hub, key: string, id: string, to: Profile, was: string | null): string | null {
  const store = hub.store;
  const row = store.getSession(key);
  const runtime = row && runtimeNamed(row.runtime);
  if (!row || !runtime) return null;
  const from = store.ranOn(key, id) ?? was;
  if (from === null || from === to.id) return null;
  const path = transcriptPath(runtime, to.home, id);
  const tokens = path === null ? null : lastContext(runtime, path);
  if (tokens === null || tokens < AFRESH_TOKENS) return null;
  const threads = store.sessionThreads(key).map((t) => threadAddress(t.thread.channel, t.thread.threadTs));
  const last = store.lastTurn(key);
  const declared = last?.declared ? parseDeclared(last.declared, 0) : null;
  const ended =
    last === null || last.endedAt === null
      ? null
      : declared?.kind === "waiting"
        ? `waiting${last.waitFor ? ` for ${last.waitFor}` : ""}`
        : declared?.kind === "need_help"
          ? `need_human${last.need ? `: ${last.need}` : ""}`
          : declared?.kind === "all_done"
            ? "all_done"
            : last.outcome === "failed"
              ? "cut off"
              : null;
  const name = (profile: string) => hub.config().profiles.find((p) => p.id === profile)?.name ?? profile;
  return afresh(`your account changed (from ${name(from)} to ${name(to.id)}), and a prompt cache is an account's own`, tokens, key, threads, ended);
}

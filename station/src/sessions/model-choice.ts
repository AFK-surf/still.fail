// The model a chat an agent opens runs when its agent names none (chat_create): the one the person it goes to (its
// starter) has opened most chats with on the station it is opened on, of those a profile there has enabled for its
// workspace. Not its opener's: the opener runs on another station, or on a model the person does not use here (2026-10-19:
// chats opened on Studio took the opener's Opus, which no profile there runs, and failed on their first turn). When
// several are as used (or none was, and there is more than one), nobody guesses: the agent is told them, to ask.
import { type Runtime, type Profile, sameModel } from "./config.ts";

/// What is counted: the starter's chats over this long.
export const USED_WITHIN_MS = 30 * 86_400_000;

/// A model a profile runs; `model` null for a profile that names none (it runs its runtime's default).
export type Candidate = { runtime: Runtime; model: string | null };
/// How many chats the starter opened on (runtime, model).
export type Used = { runtime: string; model: string | null; n: number };

export type Choice = { pick: Candidate } | { ask: { candidate: Candidate; n: number }[] };

/// The models the profiles run, each once (in their order), of `runtime` when given.
export function candidates(profiles: Profile[], runtime: Runtime | null): Candidate[] {
  const out: Candidate[] = [];
  const has = (c: Candidate) => out.some((o) => o.runtime === c.runtime && (o.model === null || c.model === null ? o.model === c.model : sameModel(o.model, c.model)));
  for (const p of profiles) {
    for (const r of p.runtimes) {
      if (runtime !== null && r !== runtime) continue;
      for (const c of p.models.length > 0 ? p.models.map((m): Candidate => ({ runtime: r, model: m })) : [{ runtime: r, model: null }]) if (!has(c)) out.push(c);
    }
  }
  return out;
}

/// The candidate a chat that ran (runtime, model) counts for: the one with its model, else its runtime's default.
function counted(cands: Candidate[], u: Used): number {
  const named = u.model === null ? -1 : cands.findIndex((c) => c.runtime === u.runtime && c.model !== null && sameModel(c.model, u.model!));
  return named >= 0 ? named : cands.findIndex((c) => c.runtime === u.runtime && c.model === null);
}

/// The one to run, or those to ask about (the most used, as used as each other; all of them when none was).
export function choose(cands: Candidate[], used: Used[]): Choice {
  if (cands.length === 1) return { pick: cands[0]! };
  const n = cands.map(() => 0);
  for (const u of used) {
    const i = counted(cands, u);
    if (i >= 0) n[i]! += u.n;
  }
  const most = Math.max(0, ...n);
  const top = cands.map((candidate, i) => ({ candidate, n: n[i]! })).filter((c) => c.n === most);
  if (most > 0 && top.length === 1) return { pick: top[0]!.candidate };
  return { ask: top };
}

/// Why no chat was opened, for the agent: the models to ask the person about.
export function askWhich(ask: { candidate: Candidate; n: number }[], where: string): string {
  const named = ask.map(({ candidate: c, n }) => `${c.model ?? `${c.runtime}'s default`} (runtime ${c.runtime}, ${n === 0 ? "not used" : `${n} chat${n === 1 ? "" : "s"}`} in 30 days)`);
  return `no model given, and the person this chat goes to has no one most used model on ${where}: ${named.join("; ")}. Ask them which (in your chat, an options card fits), then call chat_create again with that model and its runtime, and the same key`;
}

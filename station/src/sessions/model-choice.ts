// The model a chat an agent opens runs when its agent names none (chat_create): the one the person it goes to (its
// starter) has opened most chats with on the station it is opened on, of those a profile there has enabled for its
// workspace. Not its opener's: the opener runs on another station, or on a model the person does not use here (2026-10-19:
// chats opened on Studio took the opener's Opus, which no profile there runs, and failed on their first turn). The most
// used one has to lead clearly, used at least twice as often as any other; when another is close to it (or none was
// used, and there is more than one), nobody guesses: the agent is told them, to ask (the user's rule: 差距不大就要问).
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

/// The one to run: used at least twice as often as any other. Else those to ask about: the most used and those close to
/// it (used more than half as often), most used first; all of them when none was used.
export function choose(cands: Candidate[], used: Used[]): Choice {
  if (cands.length === 1) return { pick: cands[0]! };
  const n = cands.map(() => 0);
  for (const u of used) {
    const i = counted(cands, u);
    if (i >= 0) n[i]! += u.n;
  }
  const most = Math.max(0, ...n);
  const close = cands.map((candidate, i) => ({ candidate, n: n[i]! })).filter((c) => (most === 0 ? true : c.n * 2 > most));
  if (most > 0 && close.length === 1) return { pick: close[0]!.candidate };
  return { ask: close.sort((a, b) => b.n - a.n) };
}

/// Why no chat was opened, for the agent: the models to ask the person about.
export function askWhich(ask: { candidate: Candidate; n: number }[], where: string): string {
  const named = ask.map(({ candidate: c, n }) => `${c.model ?? `${c.runtime}'s default`} (runtime ${c.runtime}, ${n === 0 ? "not used" : `${n} chat${n === 1 ? "" : "s"}`} in 30 days)`);
  return `no model given, and no one model is clearly the most used by the person this chat goes to on ${where} (the most used must be used at least twice as often as any other): ${named.join("; ")}. Ask them which (in your chat, an options card fits), then call chat_create again with that model and its runtime, and the same key`;
}

// The model a chat an agent opens runs when its agent names none (chat_create): the one the person it goes to (its
// starter) has opened most chats with on the station it is opened on, of those a profile there runs for its
// workspace. Not its opener's: the opener can run on another station or a model no profile runs here. The most
// used one has to lead clearly, used at least twice as often as any other; when another is close to it (or none was
// used, and the profiles lead with more than one), nobody guesses: the agent is told them, to ask (the user's rule: 差距不大就要问).
import { type Runtime, type Profile, sameModel } from "./config.ts";

/// What is counted: the starter's chats over this long.
export const USED_WITHIN_MS = 30 * 86_400_000;

/// A model a profile runs; `model` null for a profile that names none (it runs its runtime's default).
export type Candidate = { runtime: Runtime; model: string | null };
/// How many chats the starter opened on (runtime, model).
export type Used = { runtime: string; model: string | null; n: number };

export type Choice = { pick: Candidate } | { ask: { candidate: Candidate; n: number }[] };

/// The models the profiles run, each once (in their order), of `runtime` when given; with `leads`, only the one each
/// runs first (the model it names, else the first it runs: what a chat on it runs unless told otherwise).
export function candidates(profiles: Profile[], runtime: Runtime | null, leads = false): Candidate[] {
  const out: Candidate[] = [];
  const has = (c: Candidate) => out.some((o) => o.runtime === c.runtime && (o.model === null || c.model === null ? o.model === c.model : sameModel(o.model, c.model)));
  for (const p of profiles) {
    const runs = leads ? [p.model ?? p.models[0]].filter((m) => m !== undefined) : p.models;
    for (const r of p.runtimes) {
      if (runtime !== null && r !== runtime) continue;
      for (const c of runs.length > 0 ? runs.map((m): Candidate => ({ runtime: r, model: m })) : [{ runtime: r, model: null }]) if (!has(c)) out.push(c);
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
/// it (used more than half as often), most used first. When none was used, `leads` (those the profiles run first: a
/// profile runs many models): the one, else all of them asked about.
export function choose(cands: Candidate[], used: Used[], leads: Candidate[] = cands): Choice {
  if (cands.length === 1) return { pick: cands[0]! };
  const n = cands.map(() => 0);
  for (const u of used) {
    const i = counted(cands, u);
    if (i >= 0) n[i]! += u.n;
  }
  const most = Math.max(0, ...n);
  if (most === 0) return leads.length === 1 ? { pick: leads[0]! } : { ask: leads.map((candidate) => ({ candidate, n: 0 })) };
  const close = cands.map((candidate, i) => ({ candidate, n: n[i]! })).filter((c) => c.n * 2 > most);
  if (close.length === 1) return { pick: close[0]!.candidate };
  return { ask: close.sort((a, b) => b.n - a.n) };
}

/// The most models a person is offered before they type anything (as many as the app's model panel puts in one list).
export const FEW_MOST = 12;

/// Of `all` (the models a person may pick for a new chat, the one it runs unless told otherwise first), the few they
/// are offered before they type anything (Slack's `/sf`): all of them where they are FEW_MOST or fewer; else its
/// first, those the person started chats on lately (`used`, the most used first), then those config.json names
/// (`named`: what the app's panel stars before anyone starred one), each once, FEW_MOST at most. The rest are found
/// by typing. A station's profiles run every model their checks found, tens of them (the user, 2026-11-14:
/// 「能出来，但模型太多了」).
export function few<C extends { runtime: string; model: string | null }>(all: C[], used: Used[], named: { runtime: string; model: string | null }[]): C[] {
  if (all.length <= FEW_MOST) return all;
  const at = (c: { runtime: string; model: string | null }) => all.findIndex((o) => o.runtime === c.runtime && (o.model === null || c.model === null ? o.model === c.model : sameModel(o.model, c.model)));
  const n = all.map(() => 0);
  for (const u of used) {
    const i = at(u);
    if (i >= 0) n[i]! += u.n;
  }
  const most = all.map((_, i) => i).filter((i) => n[i]! > 0).sort((a, b) => n[b]! - n[a]! || a - b);
  const order = [0, ...most, ...named.map(at).filter((i) => i >= 0)];
  return [...new Set(order)].slice(0, FEW_MOST).map((i) => all[i]!);
}

/// Why no chat was opened, for the agent: the models to ask the person about.
export function askWhich(ask: { candidate: Candidate; n: number }[], where: string): string {
  const named = ask.map(({ candidate: c, n }) => `${c.model ?? `${c.runtime}'s default`} (runtime ${c.runtime}, ${n === 0 ? "not used" : `${n} chat${n === 1 ? "" : "s"}`} in 30 days)`);
  return `no model given, and no one model is clearly the most used by the person this chat goes to on ${where} (the most used must be used at least twice as often as any other): ${named.join("; ")}. Ask them which (in your chat, an options card fits), then call chat_create again with that model and its runtime, and the same key`;
}

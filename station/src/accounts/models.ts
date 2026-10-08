// Which models a profile has enabled without anyone choosing them (2026-10-09): a profile just signed in takes those the
// station's other profiles of its runtime have enabled, and models known to be outdated are unchecked, once each.
import { modelKey } from "../read/usage.ts";

type Json = any;

/// Models known to be outdated, by key (read/usage.ts modelKey: claude-opus-4-5-20251101 and anthropic/claude-opus-4-5
/// are claude-opus-4-5), each with the model that came after it in its series; null where no one model did. A model not
/// here is not known to be outdated and is left as it is. Add a line when a newer model comes out.
export const OUTDATED = new Map<string, string | null>([
  // Claude: Opus 5.5, Sonnet 5.5, Haiku 5.5, Fable 5.1 and Mythos 5.1 the newest (Anthropic's model list, 2026-10-09).
  ["claude-opus-5", "claude-opus-5-5"],
  ["claude-opus-4-8", "claude-opus-5"],
  ["claude-opus-4-7", "claude-opus-4-8"],
  ["claude-opus-4-6", "claude-opus-4-7"],
  ["claude-opus-4-5", "claude-opus-4-6"],
  ["claude-opus-4-1", "claude-opus-4-5"],
  ["claude-opus-4", "claude-opus-4-1"],
  ["claude-3-opus", "claude-opus-4"],
  ["claude-sonnet-5", "claude-sonnet-5-5"],
  ["claude-sonnet-4-6", "claude-sonnet-5"],
  ["claude-sonnet-4-5", "claude-sonnet-4-6"],
  ["claude-sonnet-4", "claude-sonnet-4-5"],
  ["claude-3-7-sonnet", "claude-sonnet-4"],
  ["claude-3-5-sonnet", "claude-3-7-sonnet"],
  ["claude-3-sonnet", "claude-3-5-sonnet"],
  ["claude-haiku-4-5", "claude-haiku-5-5"],
  ["claude-3-5-haiku", "claude-haiku-4-5"],
  ["claude-3-haiku", "claude-3-5-haiku"],
  ["claude-fable-5", "claude-fable-5-1"],
  ["claude-mythos-5", "claude-mythos-5-1"],
  // OpenAI: GPT-6 Astra (09-03), Sol and Luna (09-22), GPT-6.1 Sol (09-29). GPT-6 has no Terra.
  ["gpt-6-sol", "gpt-6.1-sol"],
  ["gpt-5.6-sol", "gpt-6-sol"],
  ["gpt-5.6-luna", "gpt-6-luna"],
  ["gpt-5.6-terra", null],
  ["gpt-5.2", null],
  ["gpt-5.2-codex", null],
  ["gpt-5.1", null],
  ["gpt-5.1-codex", null],
  ["gpt-5.1-codex-max", null],
  ["gpt-5.1-codex-mini", null],
  ["gpt-5", null],
  ["gpt-5-codex", null],
  ["gpt-5-mini", null],
  ["gpt-5-nano", null],
  ["gpt-4.1", null],
  ["gpt-4.1-mini", null],
  ["gpt-4.1-nano", null],
  ["gpt-4o", null],
  ["gpt-4o-mini", null],
  ["o4-mini", null],
  ["o3", null],
  ["o3-mini", null],
  ["o1", null],
]);

/// A model's key and its context ([1m]) apart.
function split(model: string): [string, string] {
  const k = modelKey(model);
  const at = k.indexOf("[");
  return at >= 0 ? [k.slice(0, at), k.slice(at)] : [k, ""];
}

/// Whether a model is known to be outdated, however it is spelled.
export const outdated = (model: string): boolean => OUTDATED.has(split(model)[0]);

/// The key of the model that replaced it and is not outdated itself (the end of its line in the table), in its context;
/// null when the table names none.
export function replacement(model: string): string | null {
  const [key, context] = split(model);
  const seen = new Set([key]);
  let next = OUTDATED.get(key);
  while (typeof next === "string" && OUTDATED.has(next) && !seen.has(next)) {
    seen.add(next);
    next = OUTDATED.get(next);
  }
  return typeof next === "string" && !OUTDATED.has(next) ? next + context : null;
}

/// The models a profile just signed in takes: those the station's other profiles of its runtime have enabled
/// (`others`), as the account spells them among those its check found (`offered`), and none known outdated.
export function adopted(offered: string[], others: string[]): string[] {
  const wanted = new Set(others.map(modelKey));
  return [...new Set(offered.filter((m) => wanted.has(modelKey(m)) && !outdated(m)))].sort();
}

/// What unchecking changed on a profile.
export type Unchecked = { profile: string; removed: string[]; added: string[] };

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);

/// Unchecks, in config.json as parsed (`raw`, changed in place), the known outdated models whose keys are not in `done`
/// (unchecked here before: one checked again by hand stays). What replaced one goes in its place; one whose replacement
/// the profile is not known to have (its check, `found`, did not list it: maybe not yet) is left for a later start, its
/// key `deferred`. One nothing replaced is unchecked unless the profile would be left with no model, serving no chat.
/// Copies of other stations' profiles are theirs to change.
export function uncheckOutdated(raw: Json, found: (id: string) => string[] | null, done: ReadonlySet<string>): { changes: Unchecked[]; deferred: Set<string> } {
  const changes: Unchecked[] = [];
  const deferred = new Set<string>();
  for (const p of Array.isArray(raw?.profiles) ? raw.profiles : []) {
    if (!isObject(p) || !Array.isArray(p.models) || (isObject(p.share) && p.share.borrowed === true)) continue;
    const models: string[] = p.models.filter((m: unknown): m is string => typeof m === "string");
    const offered = [...(found(p.id) ?? []), ...models];
    let next = [...models];
    const removed: string[] = [];
    const added: string[] = [];
    for (const m of models) {
      const key = split(m)[0];
      if (!OUTDATED.has(key) || done.has(key)) continue;
      const after = replacement(m);
      if (after !== null && !next.some((o) => modelKey(o) === after)) {
        const spelled = offered.find((o) => modelKey(o) === after);
        if (spelled === undefined) {
          deferred.add(key);
          continue;
        }
        next.push(spelled);
        added.push(spelled);
      }
      next = next.filter((o) => o !== m);
      removed.push(m);
    }
    if (removed.length === 0 || next.length === 0) continue;
    p.models = next;
    changes.push({ profile: String(p.id), removed, added });
  }
  return { changes, deferred };
}

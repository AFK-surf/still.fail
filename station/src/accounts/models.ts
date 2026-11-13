// What the station knows of models: which read images, and which are outdated: those a profile names in config.json
// (by hand, or ticked on before every model a profile's check found ran) that a newer model of their line, offered on
// the same profile, replaces once each.
import { agyBaseModel } from "../agents/agy.ts";
import { modelKey } from "../read/usage.ts";
import { facts } from "./catalog.ts";

type Json = any;

/// A model's key and its context ([1m]) apart.
function split(model: string): [string, string] {
  const k = modelKey(model);
  const at = k.indexOf("[");
  return at >= 0 ? [k.slice(0, at), k.slice(at)] : [k, ""];
}

/// A model's line and its version in it, from its key: the words of its name without their numbers, and those numbers
/// (claude-fable-5-1 is claude-fable 5.1, claude-3-5-sonnet claude-sonnet 3.5, gpt-6.1-sol gpt-sol 6.1, kimi-k3 kimi-k
/// 3). A snapshot's stamp at its end (deepseek-v4-flash-0731; read/usage.ts modelKey takes off a full date) is neither,
/// so a snapshot is not newer than the model it pins. Read from the name rather than kept in a table: a table went
/// stale as each model came out (Fable 5.2 had no line in it, 2026-11-09).
export function lineOf(model: string): { line: string; version: number[] } {
  const words = split(model)[0].split("-");
  while (words.length > 1 && /^[0-9]{4,}$/.test(words[words.length - 1]!)) words.pop();
  const version: number[] = [];
  const named = words
    .map((w) => w.replace(/[0-9]+(\.[0-9]+)*/g, (d) => {
      for (const n of d.split(".")) version.push(Number(n));
      return "";
    }))
    .filter((w) => w !== "");
  return { line: named.join("-"), version };
}

/// Whether version `a` comes after `b` (5.1 after 5, 5.2 after 5.1).
function after(a: number[], b: number[]): boolean {
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const [x, y] = [a[i], b[i]];
    if (x === undefined) return false;
    if (y === undefined) return true;
    if (x !== y) return x > y;
  }
  return false;
}

/// The newest model of `model`'s line among `offered`, if one is newer than it, in `model`'s context; null when none is.
export function newerOf(model: string, offered: readonly string[]): string | null {
  const [, context] = split(model);
  const { line, version } = lineOf(model);
  let best: { spelled: string; version: number[] } | null = null;
  for (const o of offered) {
    const of = lineOf(o);
    if (of.line !== line || !after(of.version, version) || (best !== null && !after(of.version, best.version))) continue;
    best = { spelled: o, version: of.version };
  }
  if (best === null) return null;
  return split(best.spelled)[1] === "" ? best.spelled + context : best.spelled;
}

/// Models that read images, by key: sent an image through the provider they were checked on, they answer what is in
/// it. Each was checked with a drawn digit, and its opposite, on OpenCode Go (2026-10-27); it is a fact about the model
/// there, not a promise for every endpoint serving that name: another may refuse the part, and its own error says so.
/// A model neither here nor said by its maker to read images (the model catalog) is taken as text only, which is what a
/// runtime's read tool acts on: it refuses an image and says to switch models, better than handing a model pixels it
/// would answer around. Add a line for a model checked this way that the catalog does not say reads them.
export const VISION = new Set<string>(["deepseek-v4.1-flash", "glm-5.3-flash", "kimi-k3", "omen-alpha", "qwen3.8-flash"]);
/// Families whose every model reads images (Anthropic's API takes them throughout).
const VISION_FAMILIES = ["claude-"];

/// Whether a model takes image input, however a profile spells it: checked here, or its maker says so (the model
/// catalog, accounts/catalog.ts).
export const seesImages = (model: string): boolean => {
  const key = split(model)[0]!;
  return VISION.has(key) || VISION_FAMILIES.some((family) => key.startsWith(family)) || (facts(model)?.input?.includes("image") ?? false);
};

/// What unchecking changed on a profile.
export type Unchecked = { profile: string; removed: string[]; added: string[] };

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);

/// Unchecks, in config.json as parsed (`raw`, changed in place), the models a profile names that are outdated there, each
/// once: those its keys are not in `done` (unchecked here before: one checked again by hand stays). One a newer model of
/// its line replaces (newerOf), among those the profile's check found (`found`) and those it names, gives its place to
/// it; one a subscription's check found the account no longer runs is unchecked, unless the profile would be left with
/// no model, serving no chat. A key's list (an API key's provider, capped by some) does not say that of what it leaves
/// out. The profile's own default (`model`) and a connect's (`bind.model`) naming one unchecked follow it to what
/// replaced it. Gives what changed and the keys unchecked. Copies of other stations' profiles are theirs to change.
export function uncheckOutdated(raw: Json, found: (id: string) => readonly string[] | null, done: ReadonlySet<string>): { changes: Unchecked[]; unchecked: Set<string> } {
  const changes: Unchecked[] = [];
  const unchecked = new Set<string>();
  /// What replaced each model unchecked, by its spelling: null where nothing did.
  const replaced = new Map<string, string | null>();
  for (const p of Array.isArray(raw?.profiles) ? raw.profiles : []) {
    if (!isObject(p) || !Array.isArray(p.models) || (isObject(p.share) && p.share.borrowed === true)) continue;
    const models: string[] = p.models.filter((m: unknown): m is string => typeof m === "string");
    const listed = found(String(p.id));
    const offered = [...(listed ?? []), ...models];
    const listedKeys = new Set((listed ?? []).map((m) => split(m)[0]));
    const subscription = isObject(p.access) && p.access.kind === "subscription";
    let next = [...models];
    const removed: string[] = [];
    const added: string[] = [];
    const keys: string[] = [];
    const swaps = new Map<string, string | null>();
    for (const m of models) {
      const key = split(m)[0];
      if (done.has(key)) continue;
      const agyBase = p.runtime === "agy" ? agyBaseModel(m).model : null;
      const newer = agyBase !== null && agyBase !== m && offered.includes(agyBase) ? agyBase : newerOf(m, offered);
      if (newer !== null) {
        if (!next.some((o) => modelKey(o) === modelKey(newer))) {
          next.push(newer);
          added.push(newer);
        }
      } else if (!(subscription && listed !== null && listed.length > 0 && !listedKeys.has(key))) continue;
      next = next.filter((o) => o !== m);
      removed.push(m);
      keys.push(key);
      swaps.set(m, newer);
    }
    if (removed.length === 0 || next.length === 0) continue;
    p.models = next;
    for (const k of keys) unchecked.add(k);
    for (const [m, newer] of swaps) replaced.set(m, newer);
    if (typeof p.model === "string" && swaps.has(p.model)) {
      const newer = swaps.get(p.model);
      if (newer) p.model = newer;
      else delete p.model;
    }
    changes.push({ profile: String(p.id), removed, added });
  }
  for (const c of Array.isArray(raw?.connects) ? raw.connects : []) {
    const newer = isObject(c?.bind) && typeof c.bind.model === "string" ? replaced.get(c.bind.model) : undefined;
    if (newer) c.bind.model = newer;
  }
  return { changes, unchecked };
}

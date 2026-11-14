// What models can do and cost, as still.fail cloud last said (GET /v1/models, cloud/src/models.ts: models.dev's catalog
// with still.fail's corrections), by key (read/usage.ts modelKey). The models part (models/module.ts) asks for it and
// tells it here; until it has, or for a model it does not name, the station's own tables (read/usage.ts PRICES,
// accounts/models.ts VISION) answer alone.
import { modelKey, splitAgyTier } from "../read/usage.ts";

/// A model's API prices, in dollars per million tokens.
export type Cost = { input: number; output: number; cacheRead?: number; cacheWrite?: number };

/// What the catalog says of a model; a field it does not know is left out.
export type Facts = {
  name?: string;
  /// Who made it (the lab models.dev names: meta, tencent…), its name where the cloud has one, and its series as its
  /// name spells it (Muse, MiMo).
  maker?: string;
  makerName?: string;
  family?: string;
  /// What it reads: text, image, pdf, audio, video.
  input?: string[];
  reasoning?: boolean;
  /// The effort levels its maker takes (low, medium, high, xhigh, max…).
  efforts?: string[];
  /// Its context window and most output, in tokens.
  context?: number;
  output?: number;
  cost?: Cost;
};

let told = new Map<string, Facts>();
let catalogSnapshot: Record<string, Facts> = {};
let catalogVersion = 0;

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);
const number = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : undefined);
const strings = (v: unknown) => (Array.isArray(v) ? v.filter((s): s is string => typeof s === "string") : undefined);

/// One model's facts as the cloud wrote them, those of a shape not known dropped.
function factsOf(raw: unknown): Facts | null {
  if (!isObject(raw)) return null;
  const f: Facts = {};
  if (typeof raw.name === "string") f.name = raw.name;
  for (const k of ["maker", "makerName", "family"] as const) if (typeof raw[k] === "string" && raw[k] !== "") f[k] = raw[k];
  const input = strings(raw.input);
  if (input) f.input = input;
  if (typeof raw.reasoning === "boolean") f.reasoning = raw.reasoning;
  const efforts = strings(raw.efforts);
  if (efforts) f.efforts = efforts;
  const context = number(raw.context);
  if (context !== undefined) f.context = context;
  const output = number(raw.output);
  if (output !== undefined) f.output = output;
  if (isObject(raw.cost)) {
    const [input, output] = [number(raw.cost.input), number(raw.cost.output)];
    if (input !== undefined && output !== undefined) {
      f.cost = { input, output };
      const [cacheRead, cacheWrite] = [number(raw.cost.cacheRead), number(raw.cost.cacheWrite)];
      if (cacheRead !== undefined) f.cost.cacheRead = cacheRead;
      if (cacheWrite !== undefined) f.cost.cacheWrite = cacheWrite;
    }
  }
  return f;
}

/// Takes the catalog's `models` (as GET /v1/models answers them) in place of what it said before; gives how many it named.
export function learn(models: unknown): number {
  const next = new Map<string, Facts>();
  if (isObject(models)) {
    for (const [id, raw] of Object.entries(models)) {
      const f = factsOf(raw);
      if (f !== null) next.set(modelKey(id), f);
    }
  }
  told = next;
  catalogSnapshot = Object.fromEntries(next);
  catalogVersion += 1;
  return next.size;
}

/// The current catalog and its change counter, for worker threads that answer reads off the main thread.
export const catalog = (): { version: number; models: Record<string, Facts> } => ({ version: catalogVersion, models: catalogSnapshot });

/// The keys of the models the catalog names.
export const named = (): string[] => [...told.keys()];

/// What the catalog says of a model, however a profile spells it (anthropic/claude-opus-5-5[1m] is claude-opus-5-5,
/// gemini-4-hydrogen-high falls back to gemini-4-hydrogen); null for one it does not name.
export function facts(model: string): Facts | null {
  const key = modelKey(model);
  const at = key.indexOf("[");
  const bare = at >= 0 ? key.slice(0, at) : key;
  const direct = told.get(bare);
  if (direct !== undefined) return direct;
  const split = splitAgyTier(bare);
  return split === null ? null : (told.get(split.model) ?? null);
}

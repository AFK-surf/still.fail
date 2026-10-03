// Runtime-reported model capabilities (as the station reads them). Missing metadata keeps old stations usable;
// an explicitly empty list means the model has no adjustable reasoning.
import { same } from "./model.ts";

export type Catalog = Record<string, Record<string, string[]>>;

export function fallback(runtime: string): string[] {
  return runtime === "codex" ? ["minimal", "low", "medium", "high", "xhigh"] : ["low", "medium", "high", "xhigh", "max"];
}

export function available(runtime: string, model: string | null | undefined, catalog: Catalog | null | undefined): string[] {
  const models = catalog?.[runtime];
  if (model !== null && model !== undefined && models) {
    const levels = models[model] ?? Object.entries(models).find(([id]) => same(id, model))?.[1];
    if (levels) return [...levels];
  }
  return fallback(runtime);
}

export function common(profiles: string[][], runtime: string): string[] {
  if (profiles.length === 0) return available(runtime, null, null);
  let levels = [...profiles[0]];
  for (const other of profiles.slice(1)) levels = levels.filter((l) => other.includes(l));
  return levels;
}

// The most context a session runs with (sessions.context), chosen where its model is: its runtime compacts on its own
// once its context holds that much, so a model with a long window (Opus 5.5's 1M) is kept to less of it. Claude Code
// takes it as its autoCompactWindow setting, Codex as model_auto_compact_token_limit; the other runtimes have no such
// setting and are not offered it.
import { tr, type Lang } from "../ops/i18n.ts";

/// The runtimes that take a cap.
export const CONTEXT_RUNTIMES: readonly string[] = ["claude", "codex"];
/// The least a cap can be: Claude Code's autoCompactWindow takes 100,000 tokens and up.
export const CONTEXT_LEAST = 100_000;
/// The most: past any model's window (one past its own is its whole window anyway).
const CONTEXT_MOST = 10_000_000;

/// A cap as asked (`v`): undefined when not asked, null for the model's whole window. Throws, in `lang`, for one that
/// is not whole tokens from CONTEXT_LEAST up.
export function contextAsked(v: unknown, lang: Lang): number | null | undefined {
  if (v === undefined) return undefined;
  if (v === null) return null;
  if (typeof v !== "number" || !Number.isInteger(v) || v < CONTEXT_LEAST || v > CONTEXT_MOST) throw new Error(tr(lang, "station.session.badContext", { least: CONTEXT_LEAST }));
  return v;
}

/// Whether `runtime` takes a cap; throws, in `lang`, when one is asked of a runtime that does not.
export function checkContext(runtime: string, context: number | null | undefined, lang: Lang): void {
  if (context !== undefined && context !== null && !CONTEXT_RUNTIMES.includes(runtime)) throw new Error(tr(lang, "station.session.contextRuntimes"));
}

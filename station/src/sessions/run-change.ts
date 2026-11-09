// A session's run changed (lifecycle.ts `configure`): how it ran and how it runs now, as its chat's notice keeps them
// (rows.ts RunChange), and the notice's words where a chat shows no more than them (Slack, Feishu, an app from before).
import { runtimeKind, runtimeLabel } from "../agents/runtime.ts";
import { tr, type Lang } from "../ops/i18n.ts";
import { modelName } from "../ops/model-name.ts";
import type { RunChange, RunShown, SessionRow } from "../store/rows.ts";

/// How session `row` runs, its account named by `named` (null: a profile the station no longer has).
export function runShown(row: SessionRow, named: (profile: string) => string | null): RunShown {
  const account = named(row.profile);
  return {
    runtime: row.runtime, model: row.model, effort: row.effort, fast: row.fast, profile: row.profile, account,
    pinned: row.profilePinned, context: row.context,
  };
}

/// What a notice is posted for: another runtime, model, effort or speed. Another account (the station's pick moving it
/// as an allowance runs out, say) or most context alone says nothing in the chat.
export const RUN_PARTS = ["runtime", "model", "effort", "fast"] as const;

export function runChanged(change: RunChange): boolean {
  return RUN_PARTS.some((k) => change.was[k] !== change.now[k]);
}

/// The notice's words: what changed, before and after (Opus 5.5 · high → Sonnet 5.5 · medium).
export function runChangeWords(change: RunChange, lang: Lang): string {
  const part = (r: RunShown, k: (typeof RUN_PARTS)[number]): string => {
    switch (k) {
      case "runtime":
        return runtimeLabel(runtimeKind(r.runtime) ?? "claude");
      case "model":
        return r.model === null ? tr(lang, "station.notice.runDefaultModel") : modelName(r.model);
      case "effort":
        return r.effort ?? tr(lang, "station.notice.runDefaultEffort");
      case "fast":
        return r.fast === true ? "Fast" : tr(lang, "station.notice.runStandard");
    }
  };
  const changed = RUN_PARTS.filter((k) => change.was[k] !== change.now[k]);
  const side = (r: RunShown) => changed.map((k) => part(r, k)).join(" · ");
  return tr(lang, "station.notice.runChanged", { was: side(change.was), now: side(change.now) });
}

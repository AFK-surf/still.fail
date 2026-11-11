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

/// What a change by hand posts a notice for: another runtime, model, effort or speed. Another account kept to by hand,
/// or most context, alone says nothing in the chat; the station moving it to another account on its own (an allowance
/// run out, a login over: accounts.ts `moved`) is said, as another account (the user, 2026-11-10).
export const RUN_PARTS = ["runtime", "model", "effort", "fast"] as const;
const WORD_PARTS = [...RUN_PARTS, "profile"] as const;

export function runChanged(change: RunChange): boolean {
  return RUN_PARTS.some((k) => change.was[k] !== change.now[k]);
}

/// The notice's words: what changed, before and after (Opus 5.5 · high → Sonnet 5.5 · medium), or another account
/// alone (已切换账号：a → b).
export function runChangeWords(change: RunChange, lang: Lang): string {
  const part = (r: RunShown, k: (typeof WORD_PARTS)[number]): string => {
    switch (k) {
      case "runtime":
        return runtimeLabel(runtimeKind(r.runtime) ?? "claude");
      case "model":
        return r.model === null ? tr(lang, "station.notice.runDefaultModel") : modelName(r.model);
      case "effort":
        return r.effort ?? tr(lang, "station.notice.runDefaultEffort");
      case "fast":
        return r.fast === true ? "Fast" : tr(lang, "station.notice.runStandard");
      case "profile":
        return r.account ?? r.profile ?? "";
    }
  };
  const differs = WORD_PARTS.filter((k) => change.was[k] !== change.now[k]);
  // The account named only where it alone changed: with another runtime or model it is the rest's.
  const changed = differs.length > 1 ? differs.filter((k) => k !== "profile") : differs;
  const side = (r: RunShown) => changed.map((k) => part(r, k)).join(" · ");
  const words = changed.length === 1 && changed[0] === "profile" ? "station.notice.runAccountChanged" : "station.notice.runChanged";
  return tr(lang, words, { was: side(change.was), now: side(change.now) });
}

// The station's notice that a chat's run changed (station sessions/run-change.ts): what changed as a line of the chat,
// what it runs on now where that line has not the room, and how it ran and runs, whole, once the notice is opened.
import * as format from "./format.ts";
import { t } from "./i18n.ts";
import * as model from "./shapes/model.ts";
import { get, isObject } from "./util.ts";

type J = any;

/// What a notice is posted for, in the order a line says them; the account only where it alone changed (the station
/// moved it to another on its own, an allowance run out): with another runtime or model it is the rest's.
const PARTS = ["runtime", "model", "effort", "fast", "account"] as const;
type Part = (typeof PARTS)[number];

const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

/// One part of a run in words; null where it has none to say (no speed for a runtime without one).
function partText(run: J, part: Part): string | null {
  switch (part) {
    case "runtime":
      return format.runtimeLabel(str(get(run, "runtime")) ?? "claude");
    case "model": {
      const id = str(get(run, "model"));
      return id === null ? t("core-logic.format.default_model") : model.name(id);
    }
    case "effort": {
      const effort = str(get(run, "effort"));
      return effort === null ? t("core-logic.choose.default_effort") : format.effortLabel(effort);
    }
    case "fast": {
      const fast = get(run, "fast");
      return fast === true ? "Fast" : fast === false ? t("core-logic.choose.speed.standard") : null;
    }
    case "account":
      return str(get(run, "account")) ?? str(get(run, "profile"));
  }
}

/// A run whole: its runtime, model, effort, speed, account (kept to it, or the station's pick) and most context.
function runText(run: J): string {
  const parts = PARTS.filter((p) => p !== "account").map((p) => partText(run, p)).filter((p): p is string => p !== null);
  const account = str(get(run, "account"));
  if (get(run, "pinned") === true && account !== null) parts.push(account);
  else parts.push(account === null ? t("core-logic.choose.account.auto") : t("core-logic.choose.account.auto_on", { name: account }));
  const context = get(run, "context");
  if (typeof context === "number" && context > 0) parts.push(t("core-logic.notice.run.context", { n: format.compactNumber(context) }));
  return parts.join(" · ");
}

/// The mark a side of a change is drawn with (RunSides): who made its model, else its runtime's maker (the app's
/// maker_mark, as a chat's agent is drawn).
function markOf(run: J): { maker: string; runtime: string } {
  const id = str(get(run, "model"));
  return { maker: (id !== null ? format.makerOf(id)?.[0] : null) ?? "", runtime: str(get(run, "runtime")) ?? "claude" };
}

type Sides = { was: string; now: string; to: string; wasMaker: string; wasRuntime: string; nowMaker: string; nowRuntime: string };

/// A run's change as its notice says it (NoticeShown `words`, `short`, `lines`, `sides`); null for a message that is
/// none. `words`: the parts that changed, before and after (Opus 5.5 · 高 → Sonnet 5.5 · 中), an effort or a speed alone
/// named (思考深度：高 → 中, 账号：a → b). `short`: those parts as they are now alone. `lines`: the run before and after,
/// whole. `sides`: with another runtime or model, the two sides of `words` apart, each with the mark it is drawn with,
/// and what leads what it runs on now where it is said alone (换成, as `short`).
export function runChangeOf(change: unknown): { words: string; short: string; lines: string[]; sides?: Sides } | null {
  if (!isObject(change) || !isObject(change.was) || !isObject(change.now)) return null;
  const { was, now } = change;
  const differs = PARTS.filter((p) => {
    const [a, b] = [partText(was, p), partText(now, p)];
    // (a speed only where both runtimes have one: another runtime says the rest)
    return a !== null && b !== null && a !== b;
  });
  const changed = differs.length > 1 ? differs.filter((p) => p !== "account") : differs;
  const lines = [t("core-logic.notice.run.was", { run: runText(was) }), t("core-logic.notice.run.now", { run: runText(now) })];
  if (changed.length === 0) return { words: lines[1]!, short: lines[1]!, lines };
  const side = (run: J) => changed.map((p) => partText(run, p)).join(" · ");
  const arrow = `${side(was)} → ${side(now)}`;
  const NAMED: Partial<Record<Part, string>> = { effort: "core-logic.notice.run.effort", fast: "core-logic.notice.run.speed", account: "core-logic.notice.run.account" };
  const named = changed.length === 1 ? (NAMED[changed[0]!] ?? null) : null;
  if (named !== null) return { words: t(named, { change: arrow }), short: t(named, { change: side(now) }), lines };
  const short = t("core-logic.notice.run.to", { now: side(now) });
  if (!changed.includes("runtime") && !changed.includes("model")) return { words: arrow, short, lines };
  const [a, b] = [markOf(was), markOf(now)];
  const sides = { was: side(was), now: side(now), to: t("core-logic.notice.run.toLead"), wasMaker: a.maker, wasRuntime: a.runtime, nowMaker: b.maker, nowRuntime: b.runtime };
  return { words: arrow, short, lines, sides };
}

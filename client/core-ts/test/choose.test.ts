// The Rust core's choose.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { frequentCombos, recordCombo, resolve } from "../src/choose.ts";
import { holdLanguage } from "../src/i18n.ts";
import { machineMeta, models, quotaLine } from "../src/views/models.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

test("frequent_combos_rank_usage_break_ties_by_recency_and_never_substitute_unavailable_choices", () => {
  const options = [{ model: "astra", name: "Astra", ids: ["openai/astra"], runtimes: ["codex"], efforts: { codex: ["low", "medium", "high"] }, accounts: { codex: [] } }];
  const choice = (model: string, runtime: string, effort: string | null) => ({ model, runtime, effort });
  const medium = choice("astra", "codex", "medium");
  const current = resolve(options, medium);
  let history: J[] = [];
  [medium, medium, choice("astra", "codex", null), choice("astra", "codex", "high"), choice("astra", "codex", "ultra"), choice("astra", "claude", "medium"), choice("gone", "codex", null)].forEach((c, at) => {
    history = recordCombo(history, c, at);
  });
  const combos = frequentCombos(history, options, current);
  assert.equal(combos.length, 3);
  assert.equal(combos[0].label, "Astra · medium");
  assert.equal(combos[0].selected, true);
  assert.equal(combos[1].effort, "high");
  assert.equal(combos[2].label, "Astra · 默认深度");
  assert.equal(combos[2].selected, false);
});

test("frequent_combos_deduplicate_aliases_and_limit_visible_and_stored_history", () => {
  let history: J[] = [];
  let options: J[] = [];
  for (let i = 0; i < 70; i++) {
    history = recordCombo(history, { model: `m${i}`, runtime: "codex" }, i);
    options.push({ model: `m${i}`, name: `m${i}`, runtimes: ["codex"] });
  }
  assert.equal(history.length, 64);
  assert.equal(frequentCombos(history, options, resolve(options, {})).length, 4);
  options = [{ model: "astra", name: "Astra", ids: ["openai/astra"], runtimes: ["codex"] }];
  history = [];
  for (const m of ["astra", "openai/astra"]) history = recordCombo(history, { model: m, runtime: "codex" }, 1);
  assert.equal(frequentCombos(history, options, resolve(options, {})).length, 1);
});

test("speed_choices_preserve_false_and_follow_the_runtime", () => {
  const options = [{ model: "gpt-6-astra", runtimes: ["codex", "claude", "dsh"], efforts: {}, accounts: {} }];
  for (const fast of [true, false, null]) {
    const r = resolve(options, { runtime: "codex", model: "gpt-6-astra", fast });
    assert.equal(r.fast, fast);
  }
  assert.equal(resolve(options, { runtime: "claude", fast: true }).fast, null);
  assert.deepEqual([resolve(options, { runtime: "dsh", fast: true }).runtime, resolve(options, { runtime: "dsh", fast: true }).fast], ["dsh", null]);
});

test("the_runtimes_a_chat_starts_on_are_offered_claude_codex_then_deepseek_harness", () => {
  const overview = {
    profiles: [
      { id: "ds", runtimes: ["dsh"], models: ["deepseek-v4"] },
      { id: "oc", runtimes: ["dsh", "codex", "claude"], models: ["glm-5"] },
    ],
  };
  const list = models(overview, 0);
  assert.deepEqual(list.find((m: J) => m.model === "glm-5").runtimes, ["claude", "codex", "dsh"]);
  const ds = list.find((m: J) => m.model === "deepseek-v4");
  assert.deepEqual([ds.runtimes, ds.efforts.dsh], [["dsh"], ["low", "medium", "high", "max"]]);
  assert.equal(machineMeta({ runtime: "dsh", cwd: "/tmp/x" }, 0).meta, "DeepSeek Harness · /tmp/x");
});

test("grok_build_is_offered_after_deepseek_harness_with_its_own_efforts_and_no_fast_mode", () => {
  const overview = {
    profiles: [
      { id: "super", runtimes: ["grok"], models: ["grok-5"], access: { kind: "subscription" } },
      { id: "xai", runtimes: ["grok", "dsh", "codex"], models: ["grok-5-fast"], access: { kind: "api-provider", provider: "xai" } },
    ],
  };
  const list = models(overview, 0);
  assert.deepEqual(list.find((m: J) => m.model === "grok-5-fast").runtimes, ["codex", "dsh", "grok"]);
  const grok = list.find((m: J) => m.model === "grok-5");
  assert.deepEqual([grok.runtimes, grok.efforts.grok], [["grok"], ["low", "medium", "high", "xhigh", "max"]]);
  assert.equal(grok.maker?.id, "xai");
  const options = [{ model: "grok-5", runtimes: ["grok"], efforts: { grok: ["low", "high"] }, accounts: {} }];
  const r = resolve(options, { runtime: "grok", model: "grok-5", fast: true, effort: "high" });
  assert.deepEqual([r.runtime, r.fast, r.effort], ["grok", null, "high"]);
  assert.equal(machineMeta({ runtime: "grok", cwd: "/tmp/x" }, 0).meta, "Grok Build · /tmp/x");
});

test("cursor_is_offered_last_and_sets_no_effort", () => {
  const overview = {
    profiles: [
      { id: "cur", runtimes: ["cursor"], models: ["composer-2", "gpt-5.5"], access: { kind: "subscription" }, check: { modelEfforts: { cursor: { "composer-2": [], "gpt-5.5": [] } } } },
      { id: "gpt", runtimes: ["codex"], models: ["gpt-5.5"], access: { kind: "subscription" } },
      { id: "old", runtimes: ["cursor"], models: ["auto"], access: { kind: "subscription" } },
    ],
  };
  const list = models(overview, 0);
  const gpt = list.find((m: J) => m.model === "gpt-5.5");
  assert.deepEqual([gpt.runtimes, gpt.efforts.cursor], [["codex", "cursor"], []]);
  const composer = list.find((m: J) => m.model === "composer-2");
  assert.deepEqual([composer.runtimes, composer.efforts.cursor, composer.maker], [["cursor"], [], { id: "cursor", name: "Cursor" }]);
  // None either where the station says nothing of its efforts.
  assert.deepEqual(list.find((m: J) => m.model === "auto").efforts.cursor, []);
  const options = [{ model: "composer-2", runtimes: ["cursor"], efforts: { cursor: [] }, accounts: {} }];
  const r = resolve(options, { runtime: "cursor", model: "composer-2", fast: true, effort: "high" });
  assert.deepEqual([r.runtime, r.fast, r.effort], ["cursor", null, null]);
  assert.equal(machineMeta({ runtime: "cursor", cwd: "/tmp/x" }, 0).meta, "Cursor · /tmp/x");
});

test("model_efforts_follow_the_account_and_survive_resolving_saved_choices", () => {
  const overview = {
    profiles: [
      { id: "full", runtimes: ["codex"], models: ["gpt-6-astra"], check: { modelEfforts: { codex: { "gpt-6-astra": ["low", "medium", "high", "xhigh", "max", "ultra"] } } } },
      { id: "limited", runtimes: ["codex"], models: ["openai/gpt-6-astra"], check: { modelEfforts: { codex: { "openai/gpt-6-astra": ["low", "medium", "high", "xhigh", "max"] } } } },
    ],
  };
  const options = models(overview, 0);
  const choice = (profile: J, effort: string) => ({ runtime: "codex", model: "gpt-6-astra", profile, effort });
  assert.equal(resolve(options, choice(null, "max")).effort, "max");
  assert.equal(resolve(options, choice(null, "ultra")).effort, null);
  const pinned = resolve(options, choice("full", "ultra"));
  assert.equal(pinned.effort, "ultra");
  assert.ok(!pinned.efforts.includes("minimal"));
  assert.equal(resolve(options, choice("limited", "ultra")).effort, null);
  assert.equal(resolve(options, choice("full", "")).effort, null);
});

test("a_machines_session_is_a_line_its_home_as_tilde", () => {
  const meta = (cwd: string, ago: number) => {
    let s: J = { runtime: "claude", cwd, updatedAt: 1_000_000_000 };
    s = machineMeta(s, 1_000_000_000 + ago);
    return s.meta;
  };
  assert.equal(meta("/Users/bob/src/x", 3_000), "Claude Code · ~/src/x · 刚刚");
  assert.equal(meta("/home/bob", 12_000), "Claude Code · ~ · 12 秒前");
  assert.equal(meta("/srv/x", 4 * 60_000), "Claude Code · /srv/x · 4 分钟前");
  assert.equal(meta("/Users/bob/x", 30 * 3_600_000), "Claude Code · ~/x · 昨天");
  assert.equal(meta("/Users/bob/x", 3 * 86_400_000), "Claude Code · ~/x · 3 天前");
});

test("a_quota_in_a_line_names_only_the_window_running_low", () => {
  const q = (windows: J) => quotaLine({ state: "ok", windows });
  assert.deepEqual(q([{ label: "每周", usedPercent: 10 }, { label: "5 小时", usedPercent: 40 }]), { text: "5 小时 60% · 每周 90%" });
  assert.deepEqual(q([{ label: "每周", usedPercent: 95 }, { label: "5 小时", usedPercent: 75 }]), { text: "每周剩余 5%", level: "red" });
  assert.deepEqual(quotaLine({ state: "unavailable", windows: [], detail: "读不到" }), { text: "读不到" });
  assert.equal(quotaLine(null), null);
});

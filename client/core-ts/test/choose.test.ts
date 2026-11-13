// The Rust core's choose.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { frequentCombos, recordCombo, resolve } from "../src/choose.ts";
import { holdLanguage } from "../src/i18n.ts";
import { choices, machineMeta, models, quotaLine } from "../src/views/models.ts";

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
  // (the effort as the model's picker says it)
  assert.equal(combos[0].label, "Astra · 中");
  assert.equal(combos[0].name, "Astra");
  assert.equal(combos[0].effortText, "中");
  assert.equal(combos[0].runtimeText, undefined);
  assert.equal(combos[0].selected, true);
  assert.equal(combos[1].effort, "high");
  assert.equal(combos[2].label, "Astra · 默认深度");
  assert.equal(combos[2].effortText, "默认深度");
  assert.equal(combos[2].selected, false);
});

test("frequent_combos_name_the_runtime_only_where_the_model_runs_on_more_than_one", () => {
  const options = [{ model: "deepseek-v4-1-flash", name: "DeepSeek V4.1 Flash", ids: ["deepseek-v4-1-flash"], runtimes: ["claude", "dsh"], efforts: { claude: ["low", "high"], dsh: ["low", "high"] }, accounts: { claude: [], dsh: [] } }];
  const history = recordCombo([], { model: "deepseek-v4-1-flash", runtime: "dsh", effort: "high" }, 1);
  const [combo] = frequentCombos(history, options, resolve(options, {}));
  assert.equal(combo.label, "DeepSeek V4.1 Flash · DeepSeek Harness · 高");
  assert.equal(combo.name, "DeepSeek V4.1 Flash");
  assert.equal(combo.runtimeText, "DeepSeek Harness");
  assert.equal(combo.effortText, "高");
  // after its name in the panel the runtime's short name; its own control says the full one (the user, 2026-11-10:
  // 「agent runtime 可以用缩写，比如 CC，DSH」)
  assert.equal(combo.text, "DSH · 高");
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

test("frequent_combos_keep_speed_separate_and_restore_it_including_defaults", () => {
  const options = [{ model: "astra", name: "Astra", ids: ["openai/astra"], runtimes: ["codex"], efforts: { codex: ["high"] } }];
  const base = { model: "astra", runtime: "codex", effort: "high" };
  let history: J[] = [ { ...base, count: 2, last: 0 } ]; // history written before speed was kept
  for (const [at, fast] of [true, false, null, true].entries()) {
    history = recordCombo(history, { ...base, fast }, at + 1);
  }
  assert.equal(history.length, 3);
  assert.deepEqual(history.map((v) => [v.fast, v.count]), [[true, 2], [null, 3], [false, 1]]);
  for (const fast of [true, false, null]) {
    const combos = frequentCombos(history, options, resolve(options, { ...base, fast }));
    assert.deepEqual(combos.filter((c) => c.selected).map((c) => c.fast), [fast]);
    assert.equal(new Set(combos.map((c) => c.label)).size, 3);
    for (const combo of combos) assert.equal(resolve(options, { ...base, fast: !fast, ...combo }).fast, combo.fast);
    assert.equal(combos.find((c) => c.fast === true).speedText, "Fast");
    assert.equal(combos.find((c) => c.fast === null).speedText, undefined);
  }
  // Claude Code's speed is kept apart as Codex's is (an Anthropic key's Fast); one without Fast has none to keep.
  const claude = { ...base, runtime: "claude" };
  assert.equal(recordCombo(recordCombo([], { ...claude, fast: true }, 1), { ...claude, fast: false }, 2).length, 2);
  const other = { ...base, runtime: "dsh" };
  assert.equal(recordCombo(recordCombo([], { ...other, fast: true }, 1), { ...other, fast: false }, 2).length, 1);
});

// A combination used most is a configuration (the user, 2026-11-10: 「常用包括了思考深度和速度还有上下文长度」「是一种
// 配置」): its context is part of it, each counted on its own.
test("frequent_combos_are_configurations_each_context_and_effort_counted_on_its_own", () => {
  const options = [
    { model: "opus", name: "Opus", ids: ["opus"], runtimes: ["claude", "dsh"], efforts: { claude: ["low", "high"], dsh: ["high"] }, contexts: { claude: [500_000, 200_000], dsh: [] }, accounts: { claude: [], dsh: [] } },
    { model: "far", name: "Far", ids: ["far"], runtimes: ["claude"], efforts: { claude: ["high"] }, availability: "borrowable" },
  ];
  const opus = { model: "opus", runtime: "claude", effort: "high" };
  // (kept before context was: none, read as the whole window, counted with those of the whole window)
  let history: J[] = [{ ...opus, fast: null, count: 2, last: 0 }];
  const chats = [{ ...opus, context: null }, { ...opus, context: 200_000 }, { ...opus, context: 200_000 }, { ...opus, context: 200_000 }, { ...opus, effort: "low" }, { ...opus, context: 300_000 }, { model: "far", runtime: "claude", effort: "high" }, { ...opus, runtime: "dsh", context: null }];
  chats.forEach((c, at) => {
    history = recordCombo(history, c, at + 1);
  });
  assert.deepEqual(
    history.filter((v) => v.model === "opus" && v.runtime === "claude" && v.effort === "high").map((v) => [v.context, v.count]).sort((a, b) => b[1] - a[1]),
    [[200_000, 3], [null, 3], [300_000, 1]],
  );
  const current = resolve(options, { ...opus, context: 200_000 });
  const combos = frequentCombos(history, options, current);
  // (a context no longer offered, 300K, drops its entry; a model only another station has is left out)
  assert.deepEqual(combos.map((c) => [c.effort, c.runtime, c.context]), [["high", "claude", 200_000], ["high", "claude", null], ["high", "dsh", null], ["low", "claude", null]]);
  assert.deepEqual(combos.map((c) => c.text), ["CC · 高 · 200K", "CC · 高", "DSH · 高", "CC · 低"]);
  assert.deepEqual(combos.map((c) => c.selected), [true, false, false, false]);
  // fixed to one runtime: its own alone, the runtime not said
  const fixed = frequentCombos(history, options, current, "claude");
  assert.deepEqual(fixed.map((c) => c.runtime), ["claude", "claude", "claude"]);
  assert.deepEqual(fixed.map((c) => c.text), ["高 · 200K", "高", "低"]);
});

test("speed_choices_preserve_false_and_follow_the_runtime", () => {
  const options = [{ model: "gpt-6-astra", runtimes: ["codex", "claude", "dsh"], efforts: {}, accounts: {} }];
  for (const fast of [true, false, null]) {
    const r = resolve(options, { runtime: "codex", model: "gpt-6-astra", fast });
    assert.equal(r.fast, fast);
  }
  assert.equal(resolve(options, { runtime: "claude", fast: true }).fast, true);
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
  // its parts apart: today's how long ago, an earlier day's its clock under that day's heading; still.fail's own
  const day = 86_400_000;
  const kept = machineMeta({ runtime: "codex", cwd: "/Users/me/Documents/GitHub/still.fail", updatedAt: 10 * day + 3_600_000 }, 10 * day + 4 * 3_600_000);
  assert.deepEqual([kept.where, kept.folder, kept.day, kept.when, kept.own], ["~/Documents/GitHub/still.fail", "still.fail", "今天", "3 小时前", false]);
  const old = machineMeta({ runtime: "codex", cwd: "/Users/me/.stillfail/sessions/ember/c-1/workspace", updatedAt: 9 * day + 13 * 3_600_000 + 5 * 60_000 }, 10 * day + 3_600_000);
  assert.deepEqual([old.folder, old.day, old.when, old.own], ["workspace", "昨天", "13:05", true]);
});

test("a models maker and series are the catalogs the station says, else known by its name", () => {
  const overview = {
    profiles: [{ id: "p", runtimes: ["claude"], models: ["muse-spark-1.3", "step-5-preview", "anthropic/claude-opus-5-5", "kimi-k3", "gemini-4-pro", "my-model"] }],
    modelMakers: {
      "muse-spark-1.3": { maker: "meta", makerName: "Meta", family: "Muse" },
      "step-5-preview": { maker: "stepfun", makerName: "StepFun" },
      "anthropic/claude-opus-5-5": { maker: "anthropic", makerName: "Anthropic", family: "Claude Opus" },
      // A lab models.dev names otherwise than the marks do: the marks'.
      "kimi-k3": { maker: "moonshotai", makerName: "Moonshot AI", family: "Kimi K3" },
      "gemini-4-pro": { maker: "google", makerName: "Google" },
    },
  };
  const said = Object.fromEntries(models(overview, 0).map((m: J) => [m.model, [m.maker?.id ?? null, m.maker?.name ?? null, m.family]]));
  assert.deepEqual(said, {
    "muse-spark-1.3": ["meta", "Meta", "Muse"],
    "step-5-preview": ["stepfun", "阶跃星辰", null],
    // Its series as still.fail names it.
    "anthropic/claude-opus-5-5": ["anthropic", "Anthropic", "Opus"],
    "kimi-k3": ["kimi", "Kimi", "Kimi"],
    "gemini-4-pro": ["gemini", "Google", "Gemini"],
    // None in the catalog: by its name, none known.
    "my-model": [null, null, null],
  });
  // A station older than the catalog's word: by the names alone.
  const old = models({ profiles: overview.profiles }, 0);
  assert.equal(old.find((m: J) => m.model === "muse-spark-1.3").maker, null);
  assert.equal(old.find((m: J) => m.model === "kimi-k3").maker.id, "kimi");
});

test("model_options_read_each_accounts_model_list_once_even_when_it_offers_many_models", () => {
  let reads = 0;
  const names = Array.from({ length: 48 }, (_, i) => `gpt-6-sol-${i}`);
  const first = { id: "one", runtimes: ["codex", "codex"], get models() { reads++; return [...names, `openai/${names[0]}`, names[0]]; } };
  const second = { id: "two", runtimes: ["codex", "claude"], get models() { reads++; return [`openai/${names[0]}`, names[1]]; } };
  const overview = { profiles: [first, second] };
  const all = models(overview, 1_000);
  assert.equal(reads, 2, "a station's model lists are not rescanned for each model and runtime");
  assert.equal(all.length, names.length);
  const one = all.find((m: J) => m.model === names[0]);
  assert.deepEqual(one.ids, [names[0], `openai/${names[0]}`]);
  assert.deepEqual(one.accounts.codex.map((p: J) => p.id), ["one", "two"]);
  assert.deepEqual(one.accounts.claude.map((p: J) => p.id), ["two"]);
  reads = 0;
  const own = choices(overview, { runtime: "codex", profile: "one" }, 1_000);
  assert.equal(reads, 2, "an agent's choices do not rescan every account's model list for each option");
  assert.deepEqual(own.find((m: J) => m.model === names[0]).accounts.codex.map((p: J) => [p.id, p.current]), [["one", true], ["two", false]]);
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

test("devin_is_offered_after_cursor_each_model_at_its_own_thinking_levels", () => {
  const overview = {
    profiles: [
      { id: "dev", runtimes: ["devin"], models: ["swe-2", "kimi-k2-6"], access: { kind: "subscription" }, check: { modelEfforts: { devin: { "swe-2": ["medium", "high", "max"], "kimi-k2-6": [] } } } },
      { id: "old", runtimes: ["devin"], models: ["claude-opus-5-5"], access: { kind: "subscription" } },
    ],
  };
  const list = models(overview, 0);
  const swe = list.find((m: J) => m.model === "swe-2");
  assert.deepEqual([swe.runtimes, swe.efforts.devin, swe.maker], [["devin"], ["medium", "high", "max"], { id: "devin", name: "Cognition" }]);
  assert.deepEqual(list.find((m: J) => m.model === "kimi-k2-6").efforts.devin, []);
  // Where the station says nothing of a model's levels, the runtime's.
  assert.deepEqual(list.find((m: J) => m.model === "claude-opus-5-5").efforts.devin, ["low", "medium", "high", "xhigh", "max"]);
  const options = [{ model: "swe-2", runtimes: ["devin"], efforts: { devin: ["medium", "high", "max"] }, accounts: {} }];
  const r = resolve(options, { runtime: "devin", model: "swe-2", fast: true, effort: "high" });
  assert.deepEqual([r.runtime, r.fast, r.effort], ["devin", null, "high"]);
  // A Devin Fusion sidekick combination resolves on the fly from its lead model's Devin option, keeping the lead's thinking levels.
  const fusionResolved = resolve(list, { runtime: "devin", model: "fusion-claude-opus-5-5-sidekick-swe-2-medium", effort: "high" });
  assert.deepEqual([fusionResolved.entry?.model, fusionResolved.entry?.name, fusionResolved.runtime, fusionResolved.effort], [
    "fusion-claude-opus-5-5-sidekick-swe-2-medium",
    "Opus 5.5 + SWE-2 (中)",
    "devin",
    "high",
  ]);
  const legacyFusion = resolve(list, { runtime: "devin", model: "fusion-claude-opus-5-5-max-sidekick-swe-2-medium" });
  assert.deepEqual([legacyFusion.entry?.model, legacyFusion.effort], [
    "fusion-claude-opus-5-5-sidekick-swe-2-medium",
    "max",
  ]);
  assert.equal(machineMeta({ runtime: "devin", cwd: "/tmp/x" }, 0).meta, "Devin · /tmp/x");
});

test("an_account_that_has_reported_no_levels_does_not_hold_back_those_that_have", () => {
  const levels = ["low", "medium", "high", "xhigh", "max", "ultra"];
  const said = { id: "said", runtimes: ["codex"], models: ["gpt-6.1-terra"], check: { modelEfforts: { codex: { "gpt-6.1-terra": levels } } } };
  const unknown = { id: "unknown", runtimes: ["codex"], models: ["gpt-6.1-terra"], check: {} };
  assert.deepEqual(models({ profiles: [said, unknown] }, 0)[0].efforts.codex, levels);
  assert.deepEqual(models({ profiles: [unknown] }, 0)[0].efforts.codex, ["minimal", "low", "medium", "high", "xhigh"], "none has said: the runtime's usual ones");
  const pinned = resolve(models({ profiles: [said, unknown] }, 0), { runtime: "codex", model: "gpt-6.1-terra", profile: "unknown", effort: "ultra" });
  assert.equal(pinned.effort, null, "kept to one account, its own levels");
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
  assert.equal(meta("/Users/bob/x", 30 * 3_600_000), "Claude Code · ~/x · 1 天前");
  assert.equal(meta("/Users/bob/x", 3 * 86_400_000), "Claude Code · ~/x · 3 天前");
});

test("a_quota_in_a_line_names_only_the_window_running_low", () => {
  const q = (windows: J) => quotaLine({ state: "ok", windows });
  assert.deepEqual(q([{ label: "每周", usedPercent: 10 }, { label: "5 小时", usedPercent: 40 }]), { text: "5 小时 60% · 每周 90%" });
  assert.deepEqual(q([{ label: "每周", usedPercent: 95 }, { label: "5 小时", usedPercent: 75 }]), { text: "每周剩余 5%", level: "red" });
  assert.deepEqual(quotaLine({ state: "unavailable", windows: [], detail: "读不到" }), { text: "读不到" });
  assert.equal(quotaLine(null), null);
});

test("a_model_can_be_kept_to_the_steps_under_its_window_on_a_runtime_that_takes_one", () => {
  const overview = {
    profiles: [
      { id: "cc", runtimes: ["claude"], models: ["claude-opus-5-5", "claude-haiku-4-5"] },
      { id: "ds", runtimes: ["dsh"], models: ["deepseek-v4"] },
    ],
    contextCaps: { runtimes: ["claude", "codex"], least: 100_000, windows: { "claude-opus-5-5": 1_000_000, "claude-haiku-4-5": 200_000, "deepseek-v4": 1_000_000 } },
  };
  const list = models(overview, 0);
  const opus = list.find((m: J) => m.model === "claude-opus-5-5");
  assert.deepEqual([opus.contexts.claude, opus.contextWindow], [[500_000, 300_000, 200_000], 1_000_000]);
  // (a window no step is under; a runtime that cannot)
  assert.deepEqual(list.find((m: J) => m.model === "claude-haiku-4-5").contexts.claude, []);
  assert.deepEqual(list.find((m: J) => m.model === "deepseek-v4").contexts.dsh, []);
  // a step kept, another not offered given way to its whole window; as a client says it, in digits too
  assert.equal(resolve(list, { model: "claude-opus-5-5", runtime: "claude", context: 300_000 }).context, 300_000);
  assert.equal(resolve(list, { model: "claude-opus-5-5", runtime: "claude", context: "500000" }).context, 500_000);
  assert.equal(resolve(list, { model: "claude-opus-5-5", runtime: "claude", context: 400_000 }).context, null);
  assert.equal(resolve(list, { model: "claude-haiku-4-5", runtime: "claude", context: 300_000 }).context, null);
  // a station from before them offers none
  const before = models({ profiles: overview.profiles }, 0).find((m: J) => m.model === "claude-opus-5-5");
  assert.deepEqual([before.contexts.claude, before.contextWindow], [[], undefined]);
});

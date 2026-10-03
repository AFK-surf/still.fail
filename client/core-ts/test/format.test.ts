// The Rust core's format.rs, client/core-ts/src/shapes/model.ts, reasoning.rs and client/i18n tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import * as f from "../src/format.ts";
import { fromLocale, holdLanguage, tr } from "../src/i18n.ts";
import { compareOrder, family, key, name, same } from "../src/shapes/model.ts";
import { available, common, fallback } from "../src/shapes/reasoning.ts";

holdLanguage();
const MINUTE = 60_000;
const DAY = 86_400_000;

test("words_as_the_clients_had_them", () => {
  assert.deepEqual([f.bytes(0), f.bytes(812), f.bytes(83_968), f.bytes(1_468_006), f.bytes(3.2 * 1024 ** 3)], ["0 B", "812 B", "82 KB", "1.4 MB", "3.2 GB"]);
  assert.equal(f.compactNumber(950), "950");
  assert.equal(f.compactNumber(1200), "1.2K");
  assert.equal(f.compactNumber(70_600), "70.6K");
  assert.equal(f.compactNumber(3_000_000), "3M");
  assert.equal(f.duration(850), "850ms");
  assert.equal(f.duration(185_000), "3 分 5 秒");
  const now = 1_790_467_200_000;
  assert.equal(f.relativeTime(now - 10_000, now, 480), "刚刚");
  assert.equal(f.relativeTime(now - 3 * MINUTE, now, 480), "3 分钟前");
  assert.equal(f.relativeTime(now - 30 * 60 * MINUTE, now, 480), "昨天 02:00");
  assert.equal(f.dayLabel(now, now, 480), "今天");
  assert.equal(f.dayLabel(now - DAY, now, 480), "昨天");
  assert.equal(f.dayLabel(now - 20 * DAY, now, 480), "9月7日");
  assert.equal(f.timeUntil(now + 3 * 60 * MINUTE, now), "3 小时后");
  assert.equal(f.clock(now, 480), "08:00");
  assert.deepEqual(f.makerOf("gpt-6-astra"), ["openai", "OpenAI"]);
  assert.deepEqual(f.makerOf("deepseek-flash"), ["deepseek", "DeepSeek"]);
  assert.deepEqual(f.makerOf("o3"), ["openai", "OpenAI"]);
  assert.equal(f.makerOf("something"), null);
  assert.equal(f.agentLabel("gpt-6-astra", "medium"), "GPT-6 Astra · medium");
  assert.equal(f.agentLabel("my-model", null), "my-model");
  assert.equal(f.cleanText("<@U1> hi   there"), "hi there");
  assert.deepEqual(f.splitThread("C0OPS/1727.0001"), ["C0OPS", "1727.0001"]);
  assert.equal(f.splitThread("nope"), null);
  assert.equal(f.refillsIn(now + 185 * MINUTE, now), "3 小时 5 分钟后刷新");
  assert.equal(f.refillsIn(now + 48 * 60 * MINUTE, now), "2 天后刷新");
  assert.deepEqual(f.windowMark("5 hours"), ["5H", 0]);
  assert.deepEqual(f.windowMark("Weekly · Opus"), ["W", 2]);
});

test("words_in_english", () => {
  const now = 1_790_467_200_000;
  assert.equal(f.durationIn("en", 185_000), "3m 5s");
  assert.equal(f.relativeTimeIn("en", now - 10_000, now, 480), "just now");
  assert.equal(f.relativeTimeIn("en", now - MINUTE, now, 480), "1 min ago");
  assert.equal(f.relativeTimeIn("en", now - 3 * 60 * MINUTE, now, 480), "3 hr ago");
  assert.equal(f.relativeTimeIn("en", now - 30 * 60 * MINUTE, now, 480), "yesterday 02:00");
  assert.equal(f.relativeTimeIn("en", now - 20 * DAY, now, 480), "Sep 7, 08:00");
  assert.equal(f.dayLabelIn("en", now - 3 * DAY, now, 480), "Thursday");
  assert.equal(f.dayLabelIn("en", now - 20 * DAY, now, 480), "Sep 7");
  assert.equal(f.timeUntilIn("en", now + 3 * 60 * MINUTE, now), "in 3 hr");
  assert.equal(f.refillsInLang("en", now + 185 * MINUTE, now), "Refills in 3 hr 5 min");
  assert.equal(f.refillsInLang("en", now + 25 * 60 * MINUTE, now), "Refills in 1 day 1 hr");
});

test("spellings_of_one_model_share_a_key", () => {
  for (const [id, want] of [
    ["gpt-6-astra", "gpt-6-astra"], ["openai/gpt-6-astra", "gpt-6-astra"], ["OpenAI/GPT-6-Astra", "gpt-6-astra"], ["anthropic/claude-opus-5-5", "claude-opus-5-5"],
    ["us.anthropic.claude-opus-5-5-v1:0", "claude-opus-5-5"], ["anthropic.claude-opus-5-5-v1:0", "claude-opus-5-5"], ["claude-opus-5-5@20260101", "claude-opus-5-5"],
    ["claude-haiku-4-5-20251001", "claude-haiku-4-5"], ["gpt-4o-2024-08-06", "gpt-4o"], ["gpt-5.1", "gpt-5.1"], ["gpt-5.1-codex", "gpt-5.1-codex"],
    ["claude-sonnet-5[1m]", "claude-sonnet-5[1m]"], ["openai/gpt-oss-20b:free", "gpt-oss-20b:free"], ["qwen3:32b", "qwen3:32b"], ["deepseek-v4-pro", "deepseek-v4-pro"],
    ["deepseek-v4", "deepseek-v4"], ["o3", "o3"],
  ]) assert.equal(key(id), want, id);
  assert.ok(same("openai/gpt-6-astra", "gpt-6-astra"));
  assert.ok(!same("claude-sonnet-5[1m]", "claude-sonnet-5"));
  assert.ok(!same("gpt-5", "gpt-5.1"));
});

test("models_read_as_people_call_them", () => {
  for (const [id, want] of [
    ["claude-opus-5-5", "Opus 5.5"], ["claude-sonnet-5", "Sonnet 5"], ["claude-fable-5-1", "Fable 5.1"], ["claude-haiku-4-5-20251001", "Haiku 4.5"],
    ["us.anthropic.claude-opus-5-5-v1:0", "Opus 5.5"], ["claude-3-5-sonnet-latest", "Sonnet 3.5 Latest"], ["claude-sonnet-5[1m]", "Sonnet 5 1M"], ["opus", "Opus"],
    ["sonnet[1m]", "Sonnet 1M"], ["gpt-5", "GPT-5"], ["gpt-6-astra", "GPT-6 Astra"], ["openai/gpt-6-astra", "GPT-6 Astra"], ["gpt-5.1-codex-max", "GPT-5.1 Codex Max"],
    ["gpt-4o-mini", "GPT-4o Mini"], ["o3", "o3"], ["o4-mini", "o4 Mini"], ["deepseek-v4-pro", "DeepSeek V4 Pro"], ["deepseek-flash", "DeepSeek Flash"],
    ["qwen3-coder-plus", "Qwen3 Coder Plus"], ["glm-4.6", "GLM-4.6"], ["kimi-k2", "Kimi K2"], ["gemini-2.5-pro", "Gemini 2.5 Pro"], ["grok-4", "Grok 4"],
    ["minimax-m2", "MiniMax M2"], ["something-else", "something-else"], ["my-proxy/Custom-Model", "my-proxy/Custom-Model"],
  ]) assert.equal(name(id), want, id);
});

test("models_list_by_series_newest_first", () => {
  for (const [id, want] of [["claude-opus-5-5", "Opus"], ["sonnet[1m]", "Sonnet"], ["gpt-5.1-codex", "GPT"], ["o4-mini", "o 系列"], ["qwen3-coder", "Qwen"], ["deepseek-v4-pro", "DeepSeek"], ["something", null]] as const) {
    assert.equal(family(id), want, id);
  }
  const ids = ["claude-sonnet-5", "claude-opus-4-8", "claude-haiku-4-5-20251001", "claude-opus-5-5", "claude-fable-5-1", "claude-opus-5", "claude-sonnet-4-6"];
  ids.sort(compareOrder);
  assert.deepEqual(ids, ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]);
});

test("gpt_families_span_versions_and_provider_spellings", () => {
  for (const [id, want] of [["gpt-6.1-sol", "Sol"], ["gpt-5.6-sol", "Sol"], ["OpenAI/GPT-6-Astra", "Astra"], ["gpt-6-luna[1m]", "Luna"], ["gpt-6-sol-20261001", "Sol"], ["openai/gpt-6-astra:free", "Astra"], ["gpt-5.1-codex", "GPT"], ["gpt-4o-mini", "GPT"], ["gpt-6-solar", "GPT"]]) {
    assert.equal(family(id), want, id);
  }
  const ids = ["gpt-6-sol", "gpt-5.6-sol", "gpt-6-luna", "gpt-6.1-sol", "gpt-6-astra"];
  ids.sort(compareOrder);
  assert.deepEqual(ids, ["gpt-6-astra", "gpt-6-luna", "gpt-6.1-sol", "gpt-6-sol", "gpt-5.6-sol"]);
});

test("reported_levels_aliases_empty_and_legacy", () => {
  const catalog = { codex: { "gpt-6-astra": ["low", "medium", "high", "xhigh", "max", "ultra"], "gpt-6-luna": ["low", "medium", "high", "xhigh", "max"], "no-reasoning": [] } };
  const astra = available("codex", "openai/gpt-6-astra", catalog);
  assert.ok(astra.includes("max") && astra.includes("ultra"));
  assert.ok(!astra.includes("minimal"));
  assert.deepEqual(available("codex", "no-reasoning", catalog), []);
  assert.deepEqual(available("codex", "unknown", catalog), fallback("codex"));
  assert.deepEqual(available("claude", "gpt-6-astra", catalog), fallback("claude"));
  const limited = available("codex", "gpt-6-luna", catalog);
  assert.ok(!common([astra, limited], "codex").includes("ultra"));
});

test("fills_and_counts", () => {
  assert.equal(tr("zh", "no.such.key", { a: 1 }), "no.such.key");
  assert.equal(fromLocale("zh-Hant-TW"), "zh");
  assert.equal(fromLocale("en-GB"), "en");
  assert.equal(fromLocale(""), "zh");
  assert.equal(tr("en", "no.such.key"), "no.such.key");
});

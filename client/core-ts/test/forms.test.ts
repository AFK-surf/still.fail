// The Rust core's decision_form.rs, slack_tokens.rs and profile_flow.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conform } from "../src/conform.ts";
import { CoreError } from "../src/error.ts";
import { DecisionForms, PolicyForms, ProfileFlows, Tokens } from "../src/forms.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const store = () => {
  const host = new FakeHost();
  const s = new Store(host, new Runner(host.time.clock));
  s.setSource({ start: () => {}, stop: () => {} });
  return s;
};
const overview: Topic = { topic: "overview", station: "ws/st" };

test("model_control_uses_only_decision_candidates_and_confirms_in_core", () => {
  const s = store();
  const forms = new DecisionForms(s);
  const form: Topic = { topic: "decisionForm", station: "ws/st", form: "model" };
  forms.change(form, 1, "open", {});
  s.set(overview, { ok: { automaticDecisions: { settings: { completion: { enabled: true, model: "gpt-6-luna" } }, models: [{ id: "gpt-6-luna", name: "GPT-6 Luna" }, { id: "jev", name: "Jev" }] }, profiles: [{ models: ["unverified-chat-model"] }] } });
  const view = forms.value(form);
  assert.ok("ok" in conform("AutomaticDecisionDraft", view), JSON.stringify(conform("AutomaticDecisionDraft", view)));
  assert.equal(view.pick.options.length, 2);
  assert.deepEqual(view.pick.runtimes, []);
  forms.change(form, 1, "edit", { pickOpen: true });
  forms.change(form, 1, "edit", { pickModel: "jev" });
  assert.equal(forms.value(form).model, "gpt-6-luna");
  assert.equal(forms.value(form).dirty, false);
  assert.equal(forms.value(form).pick.changed, true);
  forms.change(form, 1, "edit", { pickOpen: true });
  assert.equal(forms.value(form).pick.draft.model, "gpt-6-luna");
  assert.throws(() => forms.change(form, 1, "edit", { pickModel: "unverified-chat-model" }));
  forms.change(form, 1, "edit", { pickModel: "jev", pickConfirm: true });
  assert.equal(forms.value(form).model, "jev");
  assert.equal(forms.value(form).dirty, true);
});

test("late_settings_update_clean_drafts_but_do_not_overwrite_edits", () => {
  const s = store();
  const forms = new DecisionForms(s);
  const form: Topic = { topic: "decisionForm", station: "ws/st", form: "late" };
  forms.change(form, 1, "open", {});
  s.set(overview, { ok: { automaticDecisions: { settings: { completion: { enabled: true, model: "gpt-6-luna" } } } } });
  const current = forms.value(form);
  assert.equal(current.enabled, true);
  assert.equal(current.model, "gpt-6-luna");
  forms.change(form, 1, "edit", { model: "gpt-6-luna" });
  assert.equal(forms.value(form).dirty, false);
  forms.change(form, 1, "edit", { enabled: false });
  assert.equal(forms.value(form).dirty, true);
  forms.change(form, 1, "edit", { enabled: true });
  assert.equal(forms.value(form).dirty, false);
  forms.change(form, 1, "edit", { model: "another" });
  s.set(overview, { ok: { automaticDecisions: { settings: { completion: { enabled: false, model: null } } } } });
  assert.equal(forms.value(form).model, "another");
  forms.change(form, 1, "drop", {});
});

test("the archive policy draft follows the station until edited, moves an option to the other group's end, and saves whole", () => {
  const s = store();
  const forms = new PolicyForms(s);
  const form: Topic = { topic: "policyForm", station: "ws/st", form: "p" };
  const policy = (text: string) => ({ ok: { automaticDecisions: { policy: { text, options: [
    { id: "answered", name: "已回答", rubric: "给了答案", archive: true, count: 0, chats: [] },
    { id: "awaiting_review", name: "等人看结果", rubric: "等人看", archive: false, count: 0, chats: [] },
    { id: "uncertain", name: "看不出来", rubric: "不够判断", archive: false, count: 0, chats: [] },
  ], days: 7, checked: 0, failed: 0, edited: false } } } });
  forms.change(form, 1, "open", {});
  s.set(overview, policy("看用户要的"));
  let v = forms.value(form);
  assert.ok("ok" in conform("ArchivePolicyDraft", v), JSON.stringify(conform("ArchivePolicyDraft", v)));
  assert.equal(v.policy, "看用户要的");
  assert.equal(v.dirty, false);
  // Changed elsewhere while not edited here: shown so.
  s.set(overview, policy("只看最初要的"));
  assert.equal(forms.value(form).policy, "只看最初要的");
  const review = forms.value(form).options[1].key;
  forms.change(form, 1, "edit", { option: review, archive: true });
  v = forms.value(form);
  assert.deepEqual(v.options.map((o: J) => [o.id, o.archive]), [["answered", true], ["uncertain", false], ["awaiting_review", true]]);
  assert.equal(v.dirty, true);
  forms.change(form, 1, "edit", { add: false });
  const added = forms.value(form).options.at(-1);
  forms.change(form, 1, "edit", { option: added.key, name: "等部署", rubric: "等人部署" });
  // An edited draft is not overwritten by the station's.
  s.set(overview, policy("又改了"));
  assert.equal(forms.value(form).policy, "只看最初要的");
  assert.throws(() => forms.change(form, 2, "edit", { policy: "x" }), CoreError);
  const input = forms.begin(form, 1);
  assert.deepEqual(input.options.at(-1), { name: "等部署", rubric: "等人部署", archive: false });
  assert.equal(input.options[0].id, "answered");
  assert.equal(forms.value(form).pending, true);
  forms.finish(form, 1, true);
  assert.equal(forms.value(form).dirty, false);
  forms.change(form, 1, "drop", {});
  assert.equal(forms.value(form), null);
});

const tokensTopic = (station: string): Topic => ({ topic: "slackTokens", station, form: "form" });

test("edits_and_install_changes_invalidate_verification_and_late_answers", () => {
  const forms = new Tokens();
  const t = tokensTopic("w/s");
  forms.edit(t, 1, { appToken: "old" });
  let [revision] = forms.begin(t, 1);
  forms.edit(t, 1, { appToken: "new" });
  const ok = { ok: { identity: { team: "team" }, errors: [] } };
  assert.ok(!forms.finish(t, revision, ok));
  assert.equal(forms.value(t).verified, null);
  [revision] = forms.begin(t, 1);
  assert.ok(forms.finish(t, revision, ok));
  forms.edit(t, 1, { install: "another-app" });
  assert.equal(forms.value(t).verified, null);
});

test("saved_tokens_and_installs_have_the_same_rules_in_every_view", () => {
  const forms = new Tokens();
  const t = tokensTopic("w/s");
  assert.equal(forms.edit(t, 1, { connect: "c" }).ready, true);
  assert.equal(forms.edit(t, 1, { connect: null, botToken: "bot" }).ready, true);
  assert.equal(forms.edit(t, 1, { install: "oauth" }).ready, false);
  assert.equal(forms.edit(t, 1, { appToken: "app" }).ready, true);
  assert.throws(() => forms.begin(t, 2));
  forms.edit(tokensTopic("other/s"), 2, { appToken: "other" });
  forms.disconnect(1);
  assert.throws(() => forms.begin(t, 1));
  forms.begin(tokensTopic("other/s"), 2);
});

test("a_closed_and_reopened_form_does_not_take_the_old_result", () => {
  const forms = new Tokens();
  const t = tokensTopic("w/s");
  forms.edit(t, 1, { appToken: "old" });
  const [revision] = forms.begin(t, 1);
  assert.throws(() => forms.begin(t, 1));
  forms.drop(t, 1);
  forms.edit(t, 1, { appToken: "new" });
  assert.ok(!forms.finish(t, revision, { ok: { identity: { team: "old" }, errors: [] } }));
  assert.equal(forms.value(t).verified, null);
});

const flow = () => {
  const s = store();
  return { s, flows: new ProfileFlows(s), topic: { topic: "profileFlow", station: "ws/st", form: "t" } as Topic };
};

test("the_picker_has_cues_groups_in_its_order_and_only_what_the_station_takes", () => {
  const { s, flows, topic } = flow();
  flows.change(topic, 1, "open", {});
  s.set(overview, { ok: { apiProviders: [{ id: "deepseek" }, { id: "groq" }, { id: "custom" }, { id: "openai" }] } });
  const view = flows.value(topic);
  assert.ok("ok" in conform("ProfileFlowView", view), JSON.stringify(conform("ProfileFlowView", view)));
  const ids = view.groups.map((g: J) => [g.id, g.providers.map((p: J) => p.id)]);
  assert.deepEqual(ids[0], ["labs", ["openai", "anthropic", "deepseek"]]);
  assert.deepEqual(ids[1], ["gateways", ["opencode-go"]]);
  assert.deepEqual(ids[2], ["hosted", ["groq"]]);
  assert.deepEqual(ids[3], ["local", ["custom", "env-claude", "env-codex"]]);
  assert.equal(view.step, "pick");
  s.set(overview, { ok: {} });
  const old = flows.value(topic);
  assert.deepEqual(old.groups.flatMap((g: J) => g.providers.map((p: J) => p.id)), ["openai", "anthropic", "opencode-go", "env-claude", "env-codex"]);
  const openai = old.groups[0].providers[0];
  assert.deepEqual([openai.hasKey, openai.hasPlan], [false, true]);
});

test("a_vendor_with_a_plan_and_a_key_asks_which_and_one_with_a_key_goes_straight_to_the_form", () => {
  const { s, flows, topic } = flow();
  flows.change(topic, 1, "open", {});
  s.set(overview, { ok: { apiProviders: [{ id: "openai" }, { id: "deepseek" }, { id: "azure-openai" }, { id: "custom" }] } });
  flows.change(topic, 1, "edit", { provider: "anthropic" });
  let view = flows.value(topic);
  assert.deepEqual([view.step, view.title], ["method", "连接 Anthropic"]);
  assert.equal(view.choices[0].title, "订阅 · Claude");
  flows.change(topic, 1, "edit", { method: "key" });
  view = flows.value(topic);
  assert.deepEqual([view.step, view.usesLine], ["connect", "添加后可用于：Claude Code"]);
  flows.change(topic, 1, "edit", { back: true });
  assert.equal(flows.value(topic).step, "method");
  flows.change(topic, 1, "edit", { back: true });
  assert.equal(flows.value(topic).step, "pick");
  flows.change(topic, 1, "edit", { provider: "deepseek" });
  view = flows.value(topic);
  assert.deepEqual([view.step, view.usesLine, view.canSubmit], ["connect", "添加后可用于：自动决策", false]);
  flows.change(topic, 1, "edit", { key: " sk-1 " });
  assert.equal(flows.value(topic).canSubmit, true);
  assert.deepEqual(flows.begin(topic, 1), { access: { kind: "api-provider", key: "sk-1", provider: "deepseek" } });
  assert.throws(() => flows.begin(topic, 1));
  flows.finish(topic, 1, CoreError.invalid("DeepSeek 拒绝了这个 key（401）"));
  assert.equal(flows.value(topic).error, "DeepSeek 拒绝了这个 key（401）");
  flows.change(topic, 1, "edit", { key: "sk-2" });
  assert.equal(flows.value(topic).error, null);
});

test("opencode_go_is_signed_in_to_with_an_opencode_account_where_the_station_can_and_given_a_key_elsewhere", () => {
  const { s, flows, topic } = flow();
  flows.change(topic, 1, "open", {});
  s.set(overview, { ok: { apiProviders: [{ id: "deepseek" }], consoleSignIn: true } });
  flows.change(topic, 1, "edit", { provider: "opencode-go" });
  let view = flows.value(topic);
  assert.ok("ok" in conform("ProfileFlowView", view), JSON.stringify(conform("ProfileFlowView", view)));
  assert.deepEqual([view.step, view.choices.map((c: J) => c.id), view.choices[0].title], ["method", ["plan", "key"], "订阅 · OpenCode Go"]);
  flows.change(topic, 1, "edit", { method: "plan" });
  view = flows.value(topic);
  assert.deepEqual([view.step, view.signIn, view.usesLine], ["connect", { runtime: "claude", access: "opencode-go", provider: "OpenCode" }, "添加后可用于：Claude Code · Codex"]);
  // A vendor's plan says whose sign-in it is too.
  flows.change(topic, 1, "edit", { provider: "openai" });
  flows.change(topic, 1, "edit", { method: "plan" });
  assert.deepEqual(flows.value(topic).signIn, { runtime: "codex", provider: "ChatGPT" });
  // A station from before it: a key, straight to the form.
  s.set(overview, { ok: { apiProviders: [{ id: "deepseek" }] } });
  flows.change(topic, 1, "edit", { provider: "opencode-go" });
  view = flows.value(topic);
  assert.deepEqual([view.step, view.showKey, view.signIn], ["connect", true, null]);
});

test("deepseek_harness_is_offered_where_the_station_runs_it_on_any_endpoint", () => {
  const { s, flows, topic } = flow();
  flows.change(topic, 1, "open", {});
  s.set(overview, { ok: { apiProviders: [{ id: "deepseek" }], updates: [{ id: "station" }, { id: "dsh" }] } });
  let view = flows.value(topic);
  assert.ok("ok" in conform("ProfileFlowView", view), JSON.stringify(conform("ProfileFlowView", view)));
  const tiles = view.groups.flatMap((g: J) => g.providers);
  assert.deepEqual(view.groups.find((g: J) => g.id === "local").providers.map((p: J) => p.id), ["env-claude", "env-codex", "env-dsh"]);
  assert.equal(tiles.find((p: J) => p.id === "anthropic").usesText, "Claude Code · DeepSeek Harness");
  assert.equal(tiles.find((p: J) => p.id === "opencode-go").usesText, "Claude Code · Codex · DeepSeek Harness · 自动决策");
  flows.change(topic, 1, "edit", { provider: "deepseek", key: "k" });
  assert.equal(flows.value(topic).usesLine, "添加后可用于：DeepSeek Harness · 自动决策");
  flows.change(topic, 1, "edit", { provider: "env-dsh" });
  view = flows.value(topic);
  assert.deepEqual([view.title, view.usesLine], ["连接 环境变量（DeepSeek Harness）", "添加后可用于：DeepSeek Harness"]);
  assert.deepEqual(flows.begin(topic, 1), { runtime: "dsh", access: { kind: "env" } });
  flows.finish(topic, 1, null);
  // A station from before it: not offered, and a key is said to be for what that station runs.
  s.set(overview, { ok: { apiProviders: [{ id: "deepseek" }], updates: [{ id: "station" }] } });
  assert.throws(() => flows.change(topic, 1, "edit", { provider: "env-dsh" }));
  flows.change(topic, 1, "edit", { provider: "deepseek", key: "k" });
  assert.equal(flows.value(topic).usesLine, "添加后可用于：自动决策");
});

test("supergrok_is_xais_plan_and_an_xai_key_runs_grok_build_where_the_station_runs_it", () => {
  const { s, flows, topic } = flow();
  flows.change(topic, 1, "open", {});
  s.set(overview, { ok: { apiProviders: [{ id: "xai" }], updates: [{ id: "station" }, { id: "grok" }] } });
  let view = flows.value(topic);
  assert.ok("ok" in conform("ProfileFlowView", view), JSON.stringify(conform("ProfileFlowView", view)));
  const tiles = view.groups.flatMap((g: J) => g.providers);
  const xai = tiles.find((p: J) => p.id === "xai");
  assert.deepEqual([xai.hasKey, xai.hasPlan, xai.runtime, xai.usesText], [true, true, "grok", "Codex · Grok Build"]);
  assert.equal(tiles.find((p: J) => p.id === "openai").usesText, "Codex");
  assert.deepEqual(view.groups.find((g: J) => g.id === "local").providers.map((p: J) => p.id), ["env-claude", "env-codex", "env-grok"]);
  // The plan or the key.
  flows.change(topic, 1, "edit", { provider: "xai" });
  view = flows.value(topic);
  assert.deepEqual([view.step, view.choices.map((c: J) => [c.id, c.title])], ["method", [["plan", "订阅 · SuperGrok"], ["key", "API key"]]]);
  assert.equal(view.choices[0].hint, "SuperGrok / X Premium+，用于运行 Grok Build。用设备码登录一次。");
  flows.change(topic, 1, "edit", { method: "plan" });
  view = flows.value(topic);
  assert.ok("ok" in conform("ProfileFlowView", view), JSON.stringify(conform("ProfileFlowView", view)));
  // Signed in with Grok Build's own command: a station without it installs it first (a manager can, here), then signs in.
  assert.deepEqual([view.step, view.signIn, view.install, view.usesLine], ["connect", null, { runtime: "grok", state: "missing", title: "此 station 尚未安装 Grok Build", note: "需由 workspace 的 owner 或管理员安装" }, "添加后可用于：Grok Build"]);
  s.set({ topic: "workspace", workspace: "ws" }, { ok: { role: "owner" } });
  const updates = (grok: J) => s.set(overview, { ok: { apiProviders: [{ id: "xai" }], updates: [{ id: "station" }, { id: "grok", name: "Grok Build", updatable: true, ...grok }] } });
  updates({});
  assert.deepEqual(flows.value(topic).install, { runtime: "grok", state: "missing", title: "此 station 尚未安装 Grok Build", action: "安装" });
  updates({ state: "updating", percent: 40 });
  assert.deepEqual(flows.value(topic).install, { runtime: "grok", state: "installing", title: "正在安装 Grok Build", percent: 40 });
  updates({ installed: true });
  view = flows.value(topic);
  assert.ok("ok" in conform("ProfileFlowView", view), JSON.stringify(conform("ProfileFlowView", view)));
  assert.deepEqual([view.step, view.signIn, view.install, view.usesLine], ["connect", { runtime: "grok", provider: "Grok" }, undefined, "添加后可用于：Grok Build"]);
  flows.change(topic, 1, "edit", { method: "key" });
  flows.change(topic, 1, "edit", { key: "xai-1" });
  view = flows.value(topic);
  assert.deepEqual([view.showKey, view.usesLine], [true, "添加后可用于：Codex · Grok Build"]);
  assert.deepEqual(flows.begin(topic, 1), { access: { kind: "api-provider", key: "xai-1", provider: "xai" } });
  flows.finish(topic, 1, null);
  flows.change(topic, 1, "edit", { provider: "env-grok" });
  assert.deepEqual(flows.value(topic).usesLine, "添加后可用于：Grok Build");
  assert.deepEqual(flows.begin(topic, 1), { runtime: "grok", access: { kind: "env" } });
  flows.finish(topic, 1, null);
  // A station from before it: no plan, the key straight to its form, for what that station runs.
  s.set(overview, { ok: { apiProviders: [{ id: "xai" }], updates: [{ id: "station" }] } });
  assert.throws(() => flows.change(topic, 1, "edit", { provider: "env-grok" }));
  flows.change(topic, 1, "edit", { provider: "xai" });
  view = flows.value(topic);
  assert.deepEqual([view.step, view.tile.hasPlan, view.tile.runtime, view.showKey, view.usesLine], ["connect", false, null, true, "添加后可用于：Codex"]);
});

test("cursor_is_a_plan_alone_last_of_the_makers_and_runs_on_variables_by_hand_where_the_station_runs_it", () => {
  const { s, flows, topic } = flow();
  flows.change(topic, 1, "open", {});
  s.set(overview, { ok: { apiProviders: [{ id: "openai" }], updates: [{ id: "station" }, { id: "cursor", name: "Cursor", installed: true }] } });
  let view = flows.value(topic);
  assert.ok("ok" in conform("ProfileFlowView", view), JSON.stringify(conform("ProfileFlowView", view)));
  const labs = view.groups.find((g: J) => g.id === "labs").providers;
  assert.deepEqual(labs.map((p: J) => p.id), ["openai", "anthropic", "cursor"]);
  const cursor = labs.at(-1);
  // Its account is its plan: no key to add (Cursor takes no provider's).
  assert.deepEqual([cursor.name, cursor.mark, cursor.hasKey, cursor.hasPlan, cursor.runtime, cursor.usesText], ["Cursor", "cursor", false, true, "cursor", "Cursor"]);
  assert.deepEqual(view.groups.find((g: J) => g.id === "local").providers.map((p: J) => p.id), ["env-claude", "env-codex", "env-cursor"]);
  // Straight to signing in, with no choice of plan or key.
  flows.change(topic, 1, "edit", { provider: "cursor" });
  view = flows.value(topic);
  assert.ok("ok" in conform("ProfileFlowView", view), JSON.stringify(conform("ProfileFlowView", view)));
  assert.deepEqual([view.step, view.method, view.choices, view.showKey, view.signIn, view.install, view.usesLine], ["connect", "plan", [], false, { runtime: "cursor", provider: "Cursor" }, undefined, "添加后可用于：Cursor"]);
  assert.throws(() => flows.begin(topic, 1));
  // Back from it is back to the picker.
  flows.change(topic, 1, "edit", { back: true });
  assert.equal(flows.value(topic).step, "pick");
  // A station without it installs it first.
  s.set(overview, { ok: { apiProviders: [], updates: [{ id: "station" }, { id: "cursor", name: "Cursor" }] } });
  flows.change(topic, 1, "edit", { provider: "cursor" });
  view = flows.value(topic);
  assert.deepEqual([view.signIn, view.install?.state, view.install?.title], [null, "missing", "此 station 尚未安装 Cursor"]);
  flows.change(topic, 1, "edit", { provider: "env-cursor" });
  assert.equal(flows.value(topic).usesLine, "添加后可用于：Cursor");
  assert.deepEqual(flows.begin(topic, 1), { runtime: "cursor", access: { kind: "env" } });
  flows.finish(topic, 1, null);
  // A station from before it: neither.
  s.set(overview, { ok: { apiProviders: [], updates: [{ id: "station" }] } });
  assert.throws(() => flows.change(topic, 1, "edit", { provider: "cursor" }));
  assert.throws(() => flows.change(topic, 1, "edit", { provider: "env-cursor" }));
  assert.ok(!flows.value(topic).groups.flatMap((g: J) => g.providers).some((p: J) => p.runtime === "cursor"));
});

test("jev_is_added_for_the_decisions_alone_and_its_key_is_not_tried_on_adding", () => {
  const { s, flows, topic } = flow();
  flows.change(topic, 1, "open", {});
  s.set(overview, { ok: { apiProviders: [{ id: "jev" }, { id: "deepseek" }] } });
  flows.change(topic, 1, "edit", { provider: "jev", key: "k" });
  const view = flows.value(topic);
  assert.deepEqual([view.usesLine, view.submitLabel, view.canSubmit], ["添加后可用于：自动决策", "添加", true]);
  flows.change(topic, 1, "edit", { provider: "deepseek", key: "k" });
  assert.equal(flows.value(topic).submitLabel, "验证并添加");
});

test("a_provider_in_two_regions_is_one_tile_and_the_region_is_asked_on_its_page", () => {
  const { s, flows, topic } = flow();
  flows.change(topic, 1, "open", {});
  s.set(overview, { ok: { apiProviders: [{ id: "qwen" }, { id: "qwen-cn" }, { id: "moonshotai" }, { id: "moonshotai-cn" }, { id: "deepseek" }] } });
  let view = flows.value(topic);
  assert.deepEqual(view.groups.find((g: J) => g.id === "labs").providers.map((p: J) => p.id), ["openai", "anthropic", "deepseek", "qwen", "moonshotai"]);
  flows.change(topic, 1, "edit", { provider: "qwen" });
  view = flows.value(topic);
  assert.ok("ok" in conform("ProfileFlowView", view));
  assert.deepEqual([view.regions[0].id, view.regions[1].id, view.region], ["qwen", "qwen-cn", "qwen"]);
  flows.change(topic, 1, "edit", { region: "qwen-cn", key: "k" });
  assert.equal(flows.value(topic).region, "qwen-cn");
  assert.equal(flows.begin(topic, 1).access.provider, "qwen-cn");
  flows.finish(topic, 1, null);
  flows.change(topic, 1, "edit", { provider: "deepseek" });
  assert.deepEqual(flows.value(topic).regions, []);
});

test("an_address_of_the_readers_own_and_its_protocol_are_asked_and_decide_what_it_can_do", () => {
  const { s, flows, topic } = flow();
  flows.change(topic, 1, "open", {});
  s.set(overview, { ok: { apiProviders: [{ id: "azure-openai" }, { id: "custom" }, { id: "ollama" }] } });
  flows.change(topic, 1, "edit", { provider: "azure-openai", key: "k" });
  let view = flows.value(topic);
  assert.deepEqual([view.showEndpoint, view.protocols.length, view.canSubmit], [true, 0, false]);
  flows.change(topic, 1, "edit", { endpoint: "https://r.openai.azure.com/openai/v1" });
  assert.equal(flows.value(topic).usesLine, "添加后可用于：Codex");
  flows.change(topic, 1, "edit", { provider: "custom", endpoint: "http://127.0.0.1:4000/v1" });
  view = flows.value(topic);
  assert.deepEqual([view.protocols.length, view.protocol, view.canSubmit, view.keyLabel], [3, "chat_completions", true, "API key（可选）"]);
  flows.change(topic, 1, "edit", { protocol: "anthropic" });
  assert.equal(flows.value(topic).usesLine, "添加后可用于：Claude Code");
  assert.deepEqual(flows.begin(topic, 1), { access: { kind: "api-provider", provider: "custom", endpoint: "http://127.0.0.1:4000/v1", protocol: "anthropic" } });
  flows.finish(topic, 1, null);
  flows.change(topic, 1, "edit", { provider: "ollama" });
  assert.equal(flows.value(topic).protocols.length, 0);
  flows.change(topic, 1, "edit", { provider: "env-codex" });
  view = flows.value(topic);
  assert.deepEqual([view.step, view.canSubmit, view.showKey], ["connect", true, false]);
  assert.deepEqual(flows.begin(topic, 1), { runtime: "codex", access: { kind: "env" } });
  assert.throws(() => flows.change(topic, 2, "edit", {}));
  assert.throws(() => flows.change(topic, 1, "edit", { provider: "nope" }));
});

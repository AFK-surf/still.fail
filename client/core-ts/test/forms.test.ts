// client/core/src/decision_form.rs, slack_tokens.rs and profile_flow.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conform } from "../src/conform.ts";
import { CoreError } from "../src/error.ts";
import { DecisionForms, ProfileFlows, Tokens } from "../src/forms.ts";
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

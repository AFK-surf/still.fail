// A station's variables for its agents as one page edits them (src/agent-env.ts, docs/agent-env.md): each line read
// into parts that together are the line as written (the pages colour them; Android's field maps offsets one to one),
// what keeps a line from being saved and what is only said; the draft follows the station's until edited, is not saved
// with a line wrong, and does not show the old text back between a save and the station telling what it has now.
import assert from "node:assert/strict";
import { test } from "node:test";
import { AgentEnvForms, readEnv } from "../src/agent-env.ts";
import { conform } from "../src/conform.ts";
import { CoreError } from "../src/error.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";

holdLanguage();
const store = () => {
  const host = new FakeHost();
  const s = new Store(host, new Runner(host.time.clock));
  s.setSource({ start: () => {}, stop: () => {} });
  return s;
};
const overview: Topic = { topic: "overview", station: "ws/st" };
const form: Topic = { topic: "agentEnvForm", station: "ws/st", form: "f" };

test("each line is read into parts that are the line as written, its problem said, only a wrong line keeping it from being saved", () => {
  const text = [
    "# proxy",
    "  export HTTPS_PROXY = \"http://127.0.0.1:7890\"",
    "",
    "http_proxy http://127.0.0.1:7890",
    "1BAD=x",
    "HTTPS_PROXY=http://127.0.0.1:7891",
    "EMPTY=",
    `LONG=${"x".repeat(4097)}`,
  ].join("\n");
  const read = readEnv(text);
  assert.equal(read.lines.map((l) => l.parts.map((p) => p.text).join("")).join("\n"), text);
  assert.deepEqual(read.lines.map((l) => [l.error, l.problem]), [
    [false, null],
    [false, "重复，以后面的为准"],
    [false, null],
    [true, "不是「变量名=值」的格式"],
    [true, "变量名 1BAD 无效"],
    [false, null],
    [false, null],
    [true, "值过长，上限 4096 个字符"],
  ]);
  assert.equal(read.errors, 3);
  assert.deepEqual(read.lines[1]!.parts.map((p) => p.kind), ["other", "name", "other", "value"]);
  assert.deepEqual(read.lines[0]!.parts.map((p) => p.kind), ["comment"]);
  assert.deepEqual(readEnv("").lines, [{ parts: [], problem: null, error: false }]);
});

test("the draft follows the station's until edited, is not saved with a line wrong, and keeps what was saved till the station tells", () => {
  holdLanguage();
  const s = store();
  const forms = new AgentEnvForms(s);
  const station = (env: [string, string][]) => s.set(overview, { ok: { agentEnv: env.map(([key, value]) => ({ key, value, secret: false })) } });
  station([["HTTP_PROXY", "http://p:1"]]);
  forms.change(form, 1, "open", {});
  let v = forms.value(form);
  assert.ok("ok" in conform("AgentEnvDraft", v), JSON.stringify(conform("AgentEnvDraft", v)));
  assert.equal(v.text, "HTTP_PROXY=http://p:1");
  station([["HTTP_PROXY", "http://p:2"]]);
  assert.equal(forms.value(form).text, "HTTP_PROXY=http://p:2");
  forms.change(form, 1, "edit", { text: "HTTP_PROXY http://p:3" });
  v = forms.value(form);
  assert.equal(v.dirty, true);
  assert.equal(v.errors, 1);
  assert.throws(() => forms.begin(form, 1), CoreError);
  assert.throws(() => forms.change(form, 2, "edit", { text: "x" }), CoreError);
  forms.change(form, 1, "edit", { text: "HTTP_PROXY=http://p:3\nNO_PROXY=corp" });
  // Edited: the station's change elsewhere does not overwrite it.
  station([["HTTP_PROXY", "http://p:4"]]);
  assert.equal(forms.value(form).text, "HTTP_PROXY=http://p:3\nNO_PROXY=corp");
  assert.deepEqual(forms.begin(form, 1), { text: "HTTP_PROXY=http://p:3\nNO_PROXY=corp" });
  assert.equal(forms.value(form).pending, true);
  forms.finish(form, 1, true);
  // Saved, the station not having told yet: what was typed stays, not the old text.
  assert.equal(forms.value(form).text, "HTTP_PROXY=http://p:3\nNO_PROXY=corp");
  station([["HTTP_PROXY", "http://p:3"], ["NO_PROXY", "corp"]]);
  v = forms.value(form);
  assert.equal(v.text, "HTTP_PROXY=http://p:3\nNO_PROXY=corp");
  assert.equal(v.dirty, false);
  forms.change(form, 1, "edit", { text: "A=1" });
  forms.change(form, 1, "edit", { reset: true });
  assert.equal(forms.value(form).text, "HTTP_PROXY=http://p:3\nNO_PROXY=corp");
  forms.change(form, 1, "drop", {});
  assert.equal(forms.value(form), null);
});

// Which chat page this device makes (the prefs' `chatPage`: 外观 → 试用新对话页): kept on the device as every pref is.
import assert from "node:assert/strict";
import { test } from "node:test";
import type { Core } from "../src/core.ts";
import type { FakeHost } from "../src/testing.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { started } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// A call answered: its `ok`, or its error (what else came stays to be read).
async function ask(host: FakeHost, core: Core, ui: number, id: number, name: string, params: unknown): Promise<J> {
  call(core, ui, id, name, params);
  await host.settle();
  const i = host.emitted.findIndex(([, m]) => (m as J).id === id && ("ok" in (m as J) || "error" in (m as J)));
  if (i < 0) throw new Error(`${name} not answered`);
  const [[, m]] = host.emitted.splice(i, 1);
  return m as J;
}

test("the_chat_page_tried_is_kept_on_the_device_and_nothing_else_is_taken", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.equal(v(values, 1).chatPage, undefined);
  await ask(host, core, ui, 2, "prefs.set", { chatPage: "nodes" });
  apply(host, values);
  assert.equal(v(values, 1).chatPage, "nodes");
  assert.equal((await ask(host, core, ui, 3, "prefs.set", { chatPage: "old" })).error.code, "invalid_params");
  assert.equal((await ask(host, core, ui, 4, "prefs.set", { chatPage: true })).error.code, "invalid_params");
  apply(host, values);
  assert.equal(v(values, 1).chatPage, "nodes");
  await ask(host, core, ui, 5, "prefs.set", { chatPage: null });
  apply(host, values);
  assert.equal(v(values, 1).chatPage, undefined);
  core.close();
});

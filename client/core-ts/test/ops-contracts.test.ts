// The operations' contracts (src/ops.ts `PARAMS`) say exactly what each reads of its params: the UIs' bindings are
// made from them (scripts/operations.ts), so a field the core reads that a binding cannot send, or one it sends that
// the core ignores, would be a bug either way. (scripts/operations.py checked this against ops.rs's source.)
import assert from "node:assert/strict";
import { test } from "node:test";
import { PARAMS, request } from "../src/ops.ts";

const CLOUD = ["workspace", "invitation", "loginSession", "admin"];
const SAMPLE: Record<string, unknown> = { string: "x", number: 1, boolean: true, strings: ["x"], json: {} };

/// The params' fields `request` reads, the params as given.
function read(name: string, params: Record<string, unknown>): Set<string> {
  const seen = new Set<string>();
  const watched = new Proxy(params, {
    get: (t, k) => (typeof k === "string" && seen.add(k), Reflect.get(t, k)),
    has: (t, k) => (typeof k === "string" && seen.add(k), Reflect.has(t, k)),
  });
  try {
    request(name, watched);
  } catch {
    // A field left out that it needs: what it read up to there still counts.
  }
  // Where it goes: a station's address, or the account still.fail cloud is asked as.
  seen.delete(CLOUD.includes(name.slice(0, name.indexOf("."))) ? "account" : "station");
  return seen;
}

test("every_operation_reads_what_its_contract_names_and_nothing_else", () => {
  for (const [name, contract] of Object.entries(PARAMS)) {
    const fields = contract.split(/\s+/).filter(Boolean).map((w) => w.split(":") as [string, string]);
    const declared = new Set(fields.map(([f]) => f.replace(/\?$/, "")));
    // All given, and only those it needs: between them every branch it takes.
    const where = CLOUD.includes(name.slice(0, name.indexOf("."))) ? { account: "a" } : { station: "w/s" };
    const all: Record<string, unknown> = { ...where };
    const needed: Record<string, unknown> = { ...where };
    for (const [f, type] of fields) {
      all[f.replace(/\?$/, "")] = SAMPLE[type];
      if (!f.endsWith("?")) needed[f] = SAMPLE[type];
    }
    const seen = new Set([...read(name, all), ...read(name, needed)]);
    assert.ok(request(name, all) !== null, `${name}: no such operation`);
    assert.deepEqual([...seen].filter((f) => !declared.has(f)).sort(), [], `${name} reads what its contract does not name`);
    assert.deepEqual([...declared].filter((f) => !seen.has(f)).sort(), [], `${name}'s contract names what it does not read`);
  }
});

test("a_chat_is_kept_by_put_and_let_go_by_delete", () => {
  const keep = (params: Record<string, unknown>) => request("chat.keep", { station: "w/s", thread: 3, ...params });
  assert.deepEqual([keep({})?.method, keep({})?.path], ["PUT", "/threads/3/keep"]);
  assert.equal(keep({ kept: true })?.method, "PUT");
  assert.deepEqual([keep({ kept: false })?.method, keep({ kept: false })?.path], ["DELETE", "/threads/3/keep"]);
});

test("a_slack_apps_form_writes_only_what_differs_from_what_it_started_from", () => {
  const from = { name: "still.fail", description: "Coding agent", groups: { base: true, dm: true } };
  const put = (params: Record<string, unknown>) => request("connect.putSlackApp", { station: "w/s", connect: "c1", ...params });
  // the whole draft given with what it started from: its changed fields and a new icon, nothing else
  const draft = { ...from, description: "Helper", groups: { base: true, dm: false }, icon: "data:image/jpeg;base64,AA" };
  assert.deepEqual(put({ input: draft, from })?.body, { description: "Helper", groups: { base: true, dm: false }, icon: "data:image/jpeg;base64,AA" });
  // nothing changed: nothing written; without `from`, the input as it is
  assert.deepEqual(put({ input: from, from })?.body, {});
  assert.deepEqual(put({ input: { name: "x" } })?.body, { name: "x" });
});

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

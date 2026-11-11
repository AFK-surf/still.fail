// What the app's sweep of its screens at a workspace's real size is given (apps/mbui/src/sfrealsize,
// apps/mbui/src/sfapp/real_size_wbtest.mbt): each way the app asks a topic (`ASKED`), and the value the core sends it
// whole as it subscribes, on the rig topic-bytes.test.ts weighs (real-size.ts), so the app's screens and the byte bar
// hold to one real size. A value a file (`v_<name>.mbt`), so two changes to different topics touch different files;
// not the chat's six pages (the app opens a chat on its last). REAL_SIZE_WRITE=1 writes them; otherwise this fails
// naming each file that differs, is missing or is left over: a change to real-size.ts or to what a topic sends writes
// them again in the same change.
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { ASKED, LONG, firstOfAll } from "./real-size-asked.ts";

holdLanguage();

const DIR = join(import.meta.dirname, "../../../apps/mbui/src/sfrealsize");
const write = process.env.REAL_SIZE_WRITE === "1";

/// The file a name of `ASKED` is written to: its words joined by `_`, lowercased.
const fileOf = (name: string) => `v_${name.replace(/[^A-Za-z0-9]+/g, "_").toLowerCase()}.mbt`;

/// `value` with each name the core made here (src/ids.ts `localId`, random by design: a new chat's `next`) written as
/// the n-th of its kind made, so the same rig writes the same files each run.
function steady(value: unknown): unknown {
  const made = new Map<string, string>();
  const named = (s: string) =>
    s.replace(/\b([a-z]+)-[0-9a-f]{18}\b/g, (id, kind: string) => {
      let n = made.get(id);
      if (n === undefined) made.set(id, (n = `${kind}-made-${made.size + 1}`));
      return n;
    });
  const walk = (v: unknown): unknown =>
    typeof v === "string"
      ? named(v)
      : Array.isArray(v)
        ? v.map(walk)
        : v !== null && typeof v === "object"
          ? Object.fromEntries(Object.entries(v).map(([k, x]) => [named(k), walk(x)]))
          : v;
  return walk(value);
}

/// A MoonBit file putting `asked` with `value` as the program starts (sfrealsize's `put`).
function source(name: string, asked: unknown, value: unknown): string {
  return [
    `// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends \`${name}\` whole on a`,
    "// workspace of real size.",
    "///|",
    "fn init {",
    "  let asked =",
    `    #|${JSON.stringify(asked)}`,
    "  let value =",
    `    #|${JSON.stringify(value)}`,
    "  put(asked, value)",
    "}",
    "",
  ].join("\n");
}

test("the app's real-size values are what the core sends each way it asks a topic", async () => {
  const first = await firstOfAll();
  const want = new Map<string, string>();
  for (const name of Object.keys(ASKED)) {
    if (LONG.has(name)) continue;
    const m = first.get(name);
    assert.ok(m !== undefined && "value" in m, `${name}: no value came`);
    want.set(fileOf(name), source(name, ASKED[name], steady(m.value)));
  }
  const have = readdirSync(DIR).filter((f) => /^v_.*\.mbt$/.test(f));
  const faults: string[] = [];
  for (const [file, text] of want) {
    const path = join(DIR, file);
    if (existsSync(path) && readFileSync(path, "utf8") === text) continue;
    if (write) writeFileSync(path, text);
    else faults.push(`${file}: ${existsSync(path) ? "differs from" : "missing:"} what the core sends now`);
  }
  for (const file of have) {
    if (want.has(file)) continue;
    if (write) unlinkSync(join(DIR, file));
    else faults.push(`${file}: no way the app asks a topic is written there now`);
  }
  assert.deepEqual(faults, [], "write them again: REAL_SIZE_WRITE=1 node --test test/real-size-app.test.ts");
});

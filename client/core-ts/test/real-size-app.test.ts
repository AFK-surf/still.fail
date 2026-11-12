// What the app's sweep of its screens at a workspace's real size is given (apps/mbui/src/sfrealsize,
// apps/mbui/src/sfapp/real_size_wbtest.mbt): each way the app asks a topic (`ASKED`), and the value the core sends it
// whole as it subscribes, on the rig topic-bytes.test.ts weighs (real-size.ts), so the app's screens and the byte bar
// hold to one real size. A value a file (`v_<name>.mbt`), so two changes to different topics touch different files;
// not the chat's six pages (the app opens a chat on its last). REAL_SIZE_WRITE=1 writes them; otherwise this fails
// naming each file that differs, is missing or is left over: a change to real-size.ts or to what a topic sends writes
// them again in the same change. With them, what each cause of real-size-asked.ts `CAUSES` sends each name it reaches,
// in order, as the keyed ops a device applies to the value (a value sent whole as itself): a file a name and cause
// (`c_<name>__<cause>.mbt`), for the app's sweep of what changes frames as it comes; each cause on a rig of its own, its
// value before it that of `v_<name>.mbt`; its first `FIRST_MESSAGES` messages. A name and cause one of whose messages
// weighs more than `LEFT_OUT_KB` is left out, listed in `LEFT_OUT` (all of them would be 654 KB, 105 files, the largest
// 126 KB: the coordinator, 2026-11-11), which only falls: one brought under it is written then.
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { ASKED, LONG, causesOfAll, firstOfAll } from "./real-size-asked.ts";

holdLanguage();

const DIR = join(import.meta.dirname, "../../../apps/mbui/src/sfrealsize");
const write = process.env.REAL_SIZE_WRITE === "1";

/// The messages of a cause written for a name, the first of them.
const FIRST_MESSAGES = 3;
/// What a message (as sent) may weigh for its name and cause to be written, in KB.
const LEFT_OUT_KB = 16;
/// The names and causes left out, by `<name>/<cause>`: their heaviest message, KB rounded up to the next 8 (as
/// topic-bytes.test.ts's tables, where each is in `OVER_DELTA`). It only falls.
const LEFT_OUT: Record<string, number> = {
  "vaultUses/used": 128,
  "usage/down": 88,
  "drive/file": 72,
  "chatLetters/letter": 40,
  "usage/usage": 40,
  "devices/device": 24,
  "connects/down": 24,
  "connect/session": 24,
  "connectCandidates/session": 24,
  "longJobs/down": 24,
  "chats mine/grown": 24,
  "chats/grown": 24,
};
/// KB rounded up to the next multiple of 8.
const tableKb = (n: number) => Math.max(8, Math.ceil(n / 1024 / 8) * 8);

/// A name of `ASKED` as a file's: its words joined by `_`, lowercased.
const slug = (name: string) => name.replace(/[^A-Za-z0-9]+/g, "_").toLowerCase();
/// The file a name of `ASKED` is written to.
const fileOf = (name: string) => `v_${slug(name)}.mbt`;
/// The file what `cause` sends a name of `ASKED` is written to.
const changesFile = (name: string, cause: string) => `c_${slug(name)}__${cause}.mbt`;

/// `value` with each name the core made here (src/ids.ts `localId`, random by design: a new chat's `next`) written as
/// the n-th of its kind made, so the same rig writes the same files each run.
function steady(value: unknown, made = new Map<string, string>()): unknown {
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

/// A MoonBit file putting what `cause` sends `asked`, each message the ops a device applies or `{value}` (sfrealsize's
/// `put_changes`).
function changesSource(name: string, cause: string, asked: unknown, messages: unknown[]): string {
  return [
    `// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends \`${name}\` as \`${cause}\``,
    "// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.",
    "///|",
    "fn init {",
    "  let asked =",
    `    #|${JSON.stringify(asked)}`,
    "  let messages =",
    `    #|${JSON.stringify(messages)}`,
    `  put_changes(asked, ${JSON.stringify(cause)}, messages)`,
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
  const faults: string[] = [];
  // What each cause sends, written as it applies to the value before it: the value of its own rig the same as `v_`'s,
  // the ids the core made at random named as there (`steady` of both together).
  const sizes: [string, number][] = [];
  const left = new Set<string>();
  const seen = new Set<string>();
  for (const { cause, sent, first: before } of await causesOfAll()) {
    for (const [name, sentTo] of sent) {
      if (LONG.has(name)) continue;
      const at = `${name}/${cause}`;
      seen.add(at);
      const heaviest = Math.max(...sentTo.map((x) => Buffer.byteLength(JSON.stringify(x))));
      if (heaviest > LEFT_OUT_KB * 1024) {
        left.add(at);
        if (LEFT_OUT[at] === undefined) faults.push(`${at}: a message of ${heaviest} B, over ${LEFT_OUT_KB} KB: list it in LEFT_OUT at ${tableKb(heaviest)}`);
        else if (heaviest > LEFT_OUT[at] * 1024) faults.push(`${at}: a message of ${heaviest} B, grew past the ${LEFT_OUT[at]} KB LEFT_OUT says`);
        continue;
      }
      if (LEFT_OUT[at] !== undefined) faults.push(`${at}: its messages ${LEFT_OUT_KB} KB or under now: write it, take it out of LEFT_OUT`);
      const m = before.get(name);
      const messages = sentTo.slice(0, FIRST_MESSAGES).map((x) => ("value" in x ? { value: x.value } : x.delta));
      if (messages.some((x) => x === undefined)) faults.push(`${name}/${cause}: a message neither a value nor ops`);
      const made = new Map<string, string>();
      const was = steady(m?.value, made);
      if (JSON.stringify(was) !== JSON.stringify(steady(first.get(name)?.value))) faults.push(`${name}/${cause}: its value before the cause is not v_'s`);
      const text = changesSource(name, cause, ASKED[name], steady(messages, made) as unknown[]);
      want.set(changesFile(name, cause), text);
      sizes.push([changesFile(name, cause), Buffer.byteLength(text)]);
    }
  }
  // (what they add, the largest, what is left out)
  const largest = [...sizes].sort((a, b) => b[1] - a[1]).slice(0, 10).map(([f, n]) => `${f} ${n}`);
  console.log(`c_ files: ${sizes.length}, ${sizes.reduce((a, [, n]) => a + n, 0)} B in all; the largest: ${largest.join(", ")}; left out: ${[...left].join(", ")}`);
  for (const at of Object.keys(LEFT_OUT)) if (!seen.has(at)) faults.push(`${at}: in LEFT_OUT, and no cause sends that name anything`);
  const have = readdirSync(DIR).filter((f) => /^[vc]_.*\.mbt$/.test(f));
  for (const [file, text] of want) {
    const path = join(DIR, file);
    if (existsSync(path) && readFileSync(path, "utf8") === text) continue;
    if (write) writeFileSync(path, text);
    else faults.push(`${file}: ${existsSync(path) ? "differs from" : "missing:"} what the core sends now`);
  }
  for (const file of have) {
    if (want.has(file)) continue;
    if (write) unlinkSync(join(DIR, file));
    else faults.push(`${file}: nothing the core sends is written there now`);
  }
  assert.deepEqual(faults, [], "write them again: REAL_SIZE_WRITE=1 node --test test/real-size-app.test.ts");
});

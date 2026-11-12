// What answering each way the app asks reads of the account's database follows what it sends, not how much the device
// holds (the owner, 2026-11-12: 「不应该这么无休止地扣细节」「这应该从架构设计和测试层面解决」, after two days of slow topics
// found one at a time by hand). topic-bytes.test.ts holds what a topic sends; this holds what answering it reads.
//
// Measured as the app asks (`ASKED`, real-size-asked.ts), each way on a core started anew over the real-size workspace
// already on the device (cold: from the subscribe to its first answer), and the same asked again once it was let go
// without `keep` (warm, `again`); and the interactions as the app sends them (topic-work-measure.ts `INTERACTIONS`: the
// first screen after a start, a switch of workspace on 小屏 and on 大屏, a chat opened from the list, each place of the
// bar), from a core at rest to the last answer the first screen waits for (`/waited`) and on to the core at rest again
// (`/idle`). Counted at the bottom, in the database's own calls: the bytes of text the rows it returns hold (`read`),
// against the bytes sent (topic-bytes' weight). Each at the workspace's size (`k = 1`) and with each of five things it
// holds three times (real-size.ts `Size`: its chats a station, the chat's messages, the profiles a station, its people,
// its stations), each size in a worker thread of its own (the fixture's exports are made of its size as it loads).
//
// Two bars:
// - READ: what answering reads is at most twice what it sends, or 8 KB (`READ_FREE_KB`). Those over now are in
//   `OVER_READ` (cold, `/waited`, `/idle`) and `OVER_READ_AGAIN` (warm), each with what it reads in KB rounded up to the
//   next 8: one there must still be over the bar (else it comes out of the table) and read no more than said.
// - GROWS: with each thing held three times, what it reads grows at most 1.2 times what it sends grows (read(3) ÷
//   read(1), where read(1) is taken as 8 KB at least, ≤ 1.2 × max(1, sent(3) ÷ sent(1))), or reads 8 KB at most. Those
//   over now are in `GROWS` by name and knob, each with what it reads at that knob in KB rounded up to the next 8: one
//   there must still be over the ratio (else it comes out of the table) and read no more than said there; a failure
//   says its ratio. (Its reading at the knob, not the ratio: a fixed part of what it reads taken away raises the ratio
//   of what is left, and the table only falls.)
// The tables only fall. A way of asking the rig cannot answer as a device does is in `NOT_HELD` with why; every name of
// `ASKED` is measured or there. On failure, and with TOPIC_WORK_PRINT=1, each name's numbers at each size and the five
// statements that read most at k = 1 and at the knob it fails at; with TOPIC_WORK_PRINT=1, the tables as they would be.
// The core's `work` counters (work.ts) are printed beside, under no bar.
//
// What a change the sync writes makes the core read follows what it writes and sends, the same way (the second test):
// each cause of real-size-asked.ts `CAUSES` (`<cause> six pages` again where it says `long`), from its run to the core
// at rest, `alone` (a core started anew on the device, nothing of the app's asked: the write's own cost) and `held`
// (every way the app asks held, at rest: the write and every reader's reaction), what it reads held to the same two bars
// against the bytes of text bound to the statements that write and the bytes sent. Those over now are in `OVER_WRITE`
// (by `<cause> alone` and `<cause> held`) and `GROWS_WRITE`, as `OVER_READ` and `GROWS` are kept. The causes run one
// after another in `CAUSES`' order, on one rig of each setting at each size (in the worker that measures answering
// there): a cause is measured on the rig as the causes before it left it (its core warmed by them, what they changed
// changed), so a cause inserted in the middle can move the numbers of those after it.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import type { Found, Measured } from "./topic-work-measure.ts";
import { ASKED, CAUSES, UNTOLD } from "./real-size-asked.ts";
import type { Size } from "./real-size.ts";

const print = process.env.TOPIC_WORK_PRINT === "1";
/// The clock's step, in ms, as answers are waited for (TOPIC_WORK_STEP): what is counted is taken as each answer goes
/// out (topic-work-measure.ts `answered`), so it is the same at any step.
const step = Number(process.env.TOPIC_WORK_STEP ?? "10");

/// What answering may read without counting against it, in KB.
const READ_FREE_KB = 8;
/// What answering may read for each byte it sends.
const READ_PER_SENT = 2;
/// How much faster than what it sends what answering reads may grow.
const GROWS_SLACK = 1.2;

/// The sizes measured: the workspace, and each thing it holds three times.
const KNOBS = { chats: { chats: 3 }, messages: { messages: 3 }, profiles: { profiles: 3 }, people: { people: 3 }, stations: { stations: 3 } } as const satisfies Record<string, Partial<Size>>;
type Knob = keyof typeof KNOBS;

/// The ways of asking the rig cannot answer as a device does, and why.
const NOT_HELD: Record<string, string> = {
  notices: "what the device heard of its stations' notices (notices.ts) is kept in memory, not on the device: a core started anew has none till its stations tell them again",
};
/// The topics an interaction asks that the rig serves no owner of (core.ts plugs them in: the device's own, the account's),
/// and why: an interaction's first screen does not wait for them here.
const NOT_HELD_ASKS: Record<string, string> = {
  prefs: "the device's own (core.ts)", accounts: "the device's own (core.ts)", workspaces: "the device's own (core.ts)", downloads: "the device's own (downloads.ts)",
  doing: "the device's own (core.ts)", lockPrompts: "the device's own (personal-lock.ts)", notify: "the device's own (core.ts)", driveTransfers: "the device's own (drive-transfers.ts)",
  status: "the device's own (core.ts)", composer: "the device's own (composer.ts)", chatFeedback: "the device's own (feedback.ts)",
};

/// Those reading more than `READ_PER_SENT` × what they send and `READ_FREE_KB` now, cold and of the interactions: what each
/// reads, KB rounded up to a multiple of 8.
const OVER_READ: Record<string, number> = {
  "stationPart archiving": 32,
  "stationPart automaticDecisions": 32,
  "stationPart machineLogins": 32,
  "stationPart logins": 32,
  "stationPart updates": 32,
  chats: 80,
  "chats mine": 80,
  profile: 72,
  "profile key": 72,
  connects: 144,
  "connects mine": 144,
  connect: 240,
  connectCandidates: 136,
  newChat: 40,
  pick: 144,
  settings: 144,
  "chatJobs compact": 48,
  "chatJobs summary": 48,
  agentCard: 48,
  usage: 304,
  fleet: 320,
  railCard: 344,
  "railCard usage": 232,
  workspaceMarks: 344,
  search: 176,
  chatSearch: 128,
  chatOutline: 672,
  "driveBrowse phone": 40,
  "driveBrowse columns": 40,
  vaults: 192,
  vaultItems: 184,
  chatThings: 48,
  "chatThings q": 48,
  "start 小屏/waited": 472,
  "start 小屏/idle": 472,
  "start 大屏/waited": 472,
  "start 大屏/idle": 472,
  "switch 大屏 to 新对话/waited": 128,
  "place connects/waited": 144,
  "place connects/idle": 144,
  "place vault/waited": 192,
  "place vault/idle": 192,
  "place usage/waited": 304,
  "place usage/idle": 304,
};
/// The same, asked again.
const OVER_READ_AGAIN: Record<string, number> = {};
/// Those whose reading grows faster than what they send with a knob, by name (`<name> again` warm) and knob: what each
/// reads with that thing held three times, KB rounded up to a multiple of 8.
const GROWS: Record<string, Partial<Record<Knob, number>>> = {
  connect: { chats: 648 },
  railCard: { chats: 1016, stations: 1024 },
  "start 小屏/waited": { chats: 1136, stations: 1248 },
  "start 小屏/idle": { chats: 1136, stations: 1248 },
  "start 大屏/waited": { chats: 1136, stations: 1192 },
  "start 大屏/idle": { chats: 1136, stations: 1192 },
  "stationPart archiving": { profiles: 56 },
  "stationPart automaticDecisions": { profiles: 56 },
  "stationPart machineLogins": { profiles: 56 },
  "stationPart logins": { profiles: 56 },
  "stationPart updates": { profiles: 56 },
  profiles: { profiles: 80, stations: 96 },
  profile: { profiles: 200, stations: 216 },
  "profile key": { profiles: 200, stations: 216 },
  connects: { profiles: 264 },
  "connects mine": { profiles: 264 },
  newChat: { profiles: 64 },
  pick: { profiles: 264, stations: 416 },
  settings: { profiles: 264, stations: 416 },
  history: { profiles: 72 },
  agentCard: { profiles: 72 },
  usage: { profiles: 432 },
  fleet: { profiles: 448, stations: 952 },
  "switch 大屏 to 新对话/waited": { profiles: 152 },
  "switch 大屏 to 新对话/idle": { profiles: 160 },
  "place profiles/waited": { profiles: 80, stations: 96 },
  "place profiles/idle": { profiles: 80, stations: 96 },
  "place connects/waited": { profiles: 272 },
  "place connects/idle": { profiles: 272 },
  "place usage/waited": { profiles: 424 },
  "place usage/idle": { profiles: 424 },
  chatRow: { people: 16 },
  archive: { people: 24 },
  "railCard usage": { stations: 696 },
  vaults: { stations: 384 },
  vaultItems: { stations: 376 },
  "place vault/waited": { stations: 384 },
  "place vault/idle": { stations: 384 },
};

/// The changes reading more than `READ_PER_SENT` × what they write and send and `READ_FREE_KB` now, by `<cause> alone`
/// and `<cause> held`: what each reads, KB rounded up to a multiple of 8.
const OVER_WRITE: Record<string, number> = {
  "message held": 48,
  "edit held": 16,
  "said held": 16,
  "archived held": 120,
  "screen held": 16,
  "member held": 24,
  "message six pages held": 32,
};
/// The changes whose reading grows faster than what they write and send with a knob, by the same names and knob: what
/// each reads with that thing held three times, KB rounded up to a multiple of 8. Those of a knob that came in as the
/// causes were told by key (real-size-asked.ts `listTold`) read less than they did at every size, past the ratio only as
/// the lists read whole went (KB read at k = 1 and with the knob, before and after): `message alone` with the people
/// 286.5, 292.5 → 10.4, 13.5; `message held` with the stations 321.3, 334.2 → 45.3, 58.2; `card held` with the stations
/// 203.7, 216.6 → 15.9, 28.8; `session alone` with the profiles 117.6, 143.4 → 14.6, 40.4; `session held` with the
/// profiles 144.1, 169.8 → 30.6, 56.3; `login held` with the profiles 25.1, 50.9 → 14.6, 40.4.
const GROWS_WRITE: Record<string, Partial<Record<Knob, number>>> = {
  "message alone": { chats: 16, people: 16 },
  "archived held": { chats: 296 },
  "quota alone": { profiles: 48 },
  "session alone": { profiles: 48 },
  "session held": { profiles: 64 },
  "machine alone": { profiles: 48 },
  "login alone": { profiles: 48 },
  "login held": { profiles: 48 },
  "message held": { stations: 64 },
  "card held": { stations: 32 },
  "screen held": { stations: 16 },
  "member held": { stations: 48 },
};

// ── measuring ──

/// One size measured, in a worker thread of its own.
function measure(realSize: Partial<Size>): Promise<Found> {
  return new Promise((resolve, reject) => {
    const w = new Worker(new URL("./topic-work-measure.ts", import.meta.url), { workerData: { topicWork: true, realSize, skip: Object.keys(NOT_HELD), step } });
    w.once("message", (m) => {
      void w.terminate();
      const e = (m as { error?: string }).error;
      if (e !== undefined) reject(new Error(e));
      else resolve(m as Found);
    });
    w.once("error", reject);
  });
}

/// Every size measured (k = 1, then each knob's), once for both tests.
let found: Promise<Found[]> | undefined;
const everySize = () => (found ??= Promise.all([measure({}), ...Object.values(KNOBS).map((size) => measure(size))]));
/// Each size's measures by name, `k = 1` first.
const bySize = (found: Found[], names: (f: Found) => Map<string, Measured>) =>
  new Map<string, Map<string, Measured>>([["k = 1", names(found[0]!)], ...Object.keys(KNOBS).map((k, i): [string, Map<string, Measured>] => [k, names(found[i + 1]!)])]);

/// Every measure of a size by its name: `<name>` cold, `<name> again` warm, `<interaction>/waited` and `/idle`.
function byName(f: Found): Map<string, Measured> {
  const out = new Map<string, Measured>();
  for (const a of f.asked) {
    out.set(a.name, a.cold);
    out.set(`${a.name} again`, a.warm);
  }
  for (const i of f.interactions) {
    out.set(`${i.name}/waited`, i.waited);
    out.set(`${i.name}/idle`, i.idle);
  }
  return out;
}

/// Every measure of a size of the changes by its name: `<cause> alone`, `<cause> held`.
function changesByName(f: Found): Map<string, Measured> {
  const out = new Map<string, Measured>();
  for (const c of f.changes) {
    out.set(`${c.name} alone`, c.alone);
    out.set(`${c.name} held`, c.held);
  }
  return out;
}

// ── the bars ──

const KB = 1024;
const kb = (n: number) => n / KB;
const up8 = (n: number) => Math.max(8, Math.ceil(kb(n) / 8) * 8);
/// What a measure gives out, that what it reads is held to: what answering sends; what a change writes and sends.
type Out = { of: (m: Measured) => number; what: string };
const SENDS: Out = { of: (m) => m.sent, what: "it sends" };
const WRITES: Out = { of: (m) => m.written + m.sent, what: "it writes and sends" };
const overRead = (m: Measured, out: Out) => m.read > Math.max(READ_PER_SENT * out.of(m), READ_FREE_KB * KB);
const growth = (one: Measured, three: Measured) => three.read / Math.max(one.read, READ_FREE_KB * KB);
const outGrowth = (one: Measured, three: Measured, out: Out) => (out.of(one) > 0 ? out.of(three) / out.of(one) : 1);
const growsBar = (one: Measured, three: Measured, out: Out) => GROWS_SLACK * Math.max(1, outGrowth(one, three, out));
const growsOver = (one: Measured, three: Measured, out: Out) => three.read > READ_FREE_KB * KB && growth(one, three) > growsBar(one, three, out);

type Fail = (name: string, why: string, knob?: string) => void;
/// `name`'s measure `m` held to READ, `said` what `table` says of it; whether it is over.
function readHeld(name: string, m: Measured, said: number | undefined, table: string, out: Out, fail: Fail): boolean {
  const over = overRead(m, out);
  if (said === undefined) {
    if (over) fail(name, `reads ${kb(m.read).toFixed(1)} KB, over ${READ_PER_SENT} × the ${kb(out.of(m)).toFixed(1)} KB ${out.what} (and ${READ_FREE_KB} KB)`);
  } else if (!over) fail(name, `under the read bar now: take it out of ${table}`);
  else if (kb(m.read) > said) fail(name, `reads ${kb(m.read).toFixed(1)} KB, more than the ${said} said`);
  return over;
}
/// `name` held to GROWS with `knob` three times (`m1` at k = 1, `m3` there), `said` what `table` says of it; whether it is
/// over.
function growsHeld(name: string, knob: Knob, m1: Measured, m3: Measured, said: number | undefined, table: string, out: Out, fail: Fail): boolean {
  const over = growsOver(m1, m3, out);
  const grew = `× ${growth(m1, m3).toFixed(2)} (${kb(m1.read).toFixed(1)} → ${kb(m3.read).toFixed(1)} KB) while what ${out.what} grows × ${outGrowth(m1, m3, out).toFixed(2)}`;
  if (said === undefined) {
    if (over) fail(name, `with ${knob} × 3 reads ${grew}`, knob);
  } else if (!over) fail(name, `no longer grows past what ${out.what} with ${knob}: take it out of ${table}`, knob);
  else if (kb(m3.read) > said) fail(name, `with ${knob} × 3 reads ${kb(m3.read).toFixed(1)} KB, more than the ${said} said (${grew})`, knob);
  return over;
}
/// The faults found, and the names failing with the knobs they fail at.
function faulted() {
  const faults: string[] = [];
  const failing = new Map<string, Set<string>>();
  const fail: Fail = (name, why, knob) => {
    faults.push(`${name}: ${why}`);
    if (!failing.has(name)) failing.set(name, new Set());
    if (knob !== undefined) failing.get(name)!.add(knob);
  };
  return { faults, failing, fail };
}

/// One measure as the print says it.
const line = (m: Measured) =>
  `read ${kb(m.read).toFixed(1)} KB, ${m.rows} rows, ${m.statements} statements; ${m.written > 0 ? `written ${kb(m.written).toFixed(1)} KB; ` : ""}sent ${kb(m.sent).toFixed(1)} KB${m.error ? `; ${m.error}` : ""}${Object.keys(m.work).length ? `; work ${JSON.stringify(m.work)}` : ""}`;
const tops = (m: Measured) =>
  m.top.map((s) => `      ${(kb(s.bytes).toFixed(1) + " KB").padStart(10)} ${String(s.rows).padStart(5)} rows ${String(s.runs).padStart(4)}×${s.written > 0 ? ` written ${kb(s.written).toFixed(1)} KB` : ""} ${s.sql}`).join("\n");

/// A name's numbers at each size, and its statements that read most at k = 1 and at `knobs`.
function said(name: string, sizes: Map<string, Map<string, Measured>>, knobs: string[]): string {
  const out = [`  ${name}`];
  for (const [size, all] of sizes) {
    const m = all.get(name);
    if (m !== undefined) out.push(`    ${size.padEnd(9)} ${line(m)}`);
  }
  for (const size of ["k = 1", ...knobs]) {
    const m = sizes.get(size)?.get(name);
    if (m !== undefined && m.top.length > 0) out.push(`    read most at ${size}:\n${tops(m)}`);
  }
  return out.join("\n");
}
/// A table as it would be written, of `wouldRead` and `wouldGrow`.
const keyed = (name: string) => (/^[A-Za-z_]\w*$/.test(name) ? name : JSON.stringify(name));
const flat = (o: Record<string, number>) => Object.entries(o).map(([n, v]) => `  ${keyed(n)}: ${v},`).join("\n");
const nested = (o: Record<string, Partial<Record<Knob, number>>>) =>
  Object.entries(o).map(([n, v]) => `  ${keyed(n)}: { ${Object.entries(v).map(([kn, r]) => `${kn}: ${r}`).join(", ")} },`).join("\n");

test("what answering each way the app asks reads follows what it sends, not how much the device holds", async () => {
  const skip = Object.keys(NOT_HELD);
  // (every name of ASKED measured, or said why not)
  assert.deepEqual(skip.filter((n) => !(n in ASKED)), [], "NOT_HELD names a way the app asks");
  const found = await everySize();
  const sizes = bySize(found, byName);
  const one = sizes.get("k = 1")!;
  const { faults, failing, fail } = faulted();
  // Every name measured: each way of asking but those not held, each interaction's two.
  for (const name of Object.keys(ASKED)) if (!skip.includes(name) && !one.has(name)) fail(name, "not measured");
  for (const f of found) {
    for (const i of f.interactions) {
      for (const t of i.unanswered) if (NOT_HELD_ASKS[t] === undefined) fail(`${i.name}`, `${t} not answered and not in NOT_HELD_ASKS`);
    }
    for (const a of f.asked) for (const m of [a.cold, a.warm]) if (m.error !== undefined) fail(a.name, `answered ${m.error}`);
  }
  // READ.
  const wouldRead: Record<string, number> = {};
  const wouldReadAgain: Record<string, number> = {};
  for (const [name, m] of one) {
    const table = name.endsWith(" again") ? OVER_READ_AGAIN : OVER_READ;
    const key = name.endsWith(" again") ? name.slice(0, -" again".length) : name;
    if (readHeld(name, m, table[key], table === OVER_READ ? "OVER_READ" : "OVER_READ_AGAIN", SENDS, fail)) (name.endsWith(" again") ? wouldReadAgain : wouldRead)[key] = up8(m.read);
  }
  for (const [table, named] of [[OVER_READ, ""], [OVER_READ_AGAIN, " again"]] as const) {
    for (const key of Object.keys(table)) if (!one.has(key + named)) fail(key + named, "in a table, measured nowhere");
  }
  // GROWS.
  const wouldGrow: Record<string, Partial<Record<Knob, number>>> = {};
  for (const knob of Object.keys(KNOBS) as Knob[]) {
    const three = sizes.get(knob)!;
    for (const [name, m1] of one) {
      const m3 = three.get(name);
      if (m3 === undefined) continue;
      if (growsHeld(name, knob, m1, m3, GROWS[name]?.[knob], "GROWS", SENDS, fail)) (wouldGrow[name] ??= {})[knob] = up8(m3.read);
    }
  }
  for (const [name, knobs] of Object.entries(GROWS)) if (!one.has(name)) fail(name, `in GROWS (${Object.keys(knobs).join(", ")}), measured nowhere`);
  if (print || faults.length > 0) {
    const names = print ? [...one.keys()] : [...failing.keys()];
    console.log(`What answering reads, by name, at each size (and the statements that read most):\n${names.map((n) => said(n, sizes, [...(failing.get(n) ?? [])])).join("\n")}`);
  }
  if (print) {
    console.log(`The tables as they would be:\nconst OVER_READ: Record<string, number> = {\n${flat(wouldRead)}\n};\nconst OVER_READ_AGAIN: Record<string, number> = {\n${flat(wouldReadAgain)}\n};\nconst GROWS: Record<string, Partial<Record<Knob, number>>> = {\n${nested(wouldGrow)}\n};\nEND TABLES`);
  }
  assert.deepEqual(faults, []);
});

test("what each change the sync writes makes the core read follows what it writes and sends, not how much the device holds", async () => {
  const sizes = bySize(await everySize(), changesByName);
  const one = sizes.get("k = 1")!;
  const { faults, failing, fail } = faulted();
  // Every cause measured, both ways, and none failed as it ran.
  for (const [cause, c] of Object.entries(CAUSES)) {
    for (const name of c.long ? [cause, `${cause} six pages`] : [cause]) {
      for (const setting of ["alone", "held"]) if (!one.has(`${name} ${setting}`)) fail(`${name} ${setting}`, "not measured");
    }
  }
  for (const all of sizes.values()) for (const [name, m] of all) if (m.error !== undefined) fail(name, `failed: ${m.error}`);
  // (a cause told otherwise than the sync would is one: real-size-asked.ts UNTOLD)
  for (const name of Object.keys(UNTOLD)) if (CAUSES[name] === undefined) fail(name, "in UNTOLD, not a cause");
  // READ.
  const wouldRead: Record<string, number> = {};
  for (const [name, m] of one) if (readHeld(name, m, OVER_WRITE[name], "OVER_WRITE", WRITES, fail)) wouldRead[name] = up8(m.read);
  for (const name of Object.keys(OVER_WRITE)) if (!one.has(name)) fail(name, "in OVER_WRITE, measured nowhere");
  // GROWS.
  const wouldGrow: Record<string, Partial<Record<Knob, number>>> = {};
  for (const knob of Object.keys(KNOBS) as Knob[]) {
    const three = sizes.get(knob)!;
    for (const [name, m1] of one) {
      const m3 = three.get(name);
      if (m3 !== undefined && growsHeld(name, knob, m1, m3, GROWS_WRITE[name]?.[knob], "GROWS_WRITE", WRITES, fail)) (wouldGrow[name] ??= {})[knob] = up8(m3.read);
    }
  }
  for (const [name, knobs] of Object.entries(GROWS_WRITE)) if (!one.has(name)) fail(name, `in GROWS_WRITE (${Object.keys(knobs).join(", ")}), measured nowhere`);
  if (print) {
    const rows = [...one].sort(([a, x], [b, y]) => y.read - x.read || (a < b ? -1 : 1));
    const cell = (n: number) => kb(n).toFixed(1).padStart(8);
    console.log(`What each change makes the core read, at k = 1, by what it reads (KB):\n${"".padEnd(28)}${"statements".padStart(11)}${"read".padStart(8)}${"written".padStart(8)}${"sent".padStart(8)}\n${rows.map(([n, m]) => `${n.padEnd(28)}${String(m.statements).padStart(11)}${cell(m.read)}${cell(m.written)}${cell(m.sent)}`).join("\n")}`);
  }
  if (print || faults.length > 0) {
    const names = print ? [...one.keys()] : [...failing.keys()];
    console.log(`What each change reads, by name, at each size (and the statements that read most):\n${names.map((n) => said(n, sizes, [...(failing.get(n) ?? [])])).join("\n")}`);
  }
  if (print) console.log(`The tables as they would be:\nconst OVER_WRITE: Record<string, number> = {\n${flat(wouldRead)}\n};\nconst GROWS_WRITE: Record<string, Partial<Record<Knob, number>>> = {\n${nested(wouldGrow)}\n};\nEND TABLES`);
  assert.deepEqual(faults, []);
});

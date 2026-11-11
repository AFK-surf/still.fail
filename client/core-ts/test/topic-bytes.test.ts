// What each topic the app asks is sent, in bytes, on a workspace of real size (real-size.ts), held to a bar. The app
// (apps/mbui) parses every message of the core on its frame thread: on the owner's phone (120 Hz, 8.3 ms a frame,
// 2026-11-10) a `stations` of 463,533 bytes took 25-86 ms each time it came, `connects` once 1,061,394, `chat` 134 KB
// on average, `chats` 105,704 for 50 rows, `profiles` 92,486, `newChat` 50-95 ms a value, `pick` ~110 KB, `usage`
// ~82 KB. Nothing saw it: the app's replays (apps/mbui/src/sfreplay/topic_bytes.mbt) run on a workspace of one
// station and a few chats. The owner's rule (2026-11-10): 「ui 应该只订阅目前 ui 需要或者可能需要的东西，严格控制通讯和
// 序列化的量」.
//
// Measured as the app asks (`keyed`, every way it asks each, `ASKED`): the value a subscription is sent whole as it
// subscribes to a topic the workspace has come in for, as the JSON text the host hands over (its UTF-8 bytes), is at
// most `BAR_KB`; then, the subscriptions held, what goes out as the workspace changes (a minute passes, a station's
// host reading, an allowance read again, a message in the chat), each message at most `DELTA_BAR_KB`. Those over a bar now are in `OVER` (by topic) and `OVER_DELTA` (by topic/cause),
// each with what it weighs now in KB, rounded up to the next 8 so the fixture's drift does not flap it: one there must
// still be over the bar (else it comes out of the table) and no heavier than said (else it grew). The tables only fall.
// Every topic of `TOPICS` is either asked here or in `NOT_MEASURED` with why: a new topic is placed in one of them.
// On failure, and with TOPIC_BYTES_PRINT=1, the table is printed: each topic's bytes, and of one over its bar its
// heaviest fields (a list's items as `[]`), as the app's `@core.weights` says them, and the fixture's `stations` field
// by field beside what the owner's phone was sent (`PHONE_STATIONS`).
import assert from "node:assert/strict";
import { Effect } from "effect";
import { test } from "node:test";
import { Changelog } from "../src/changelog.ts";
import { Choose } from "../src/choose.ts";
import { Devices } from "../src/devices.ts";
import type { PersonalLock } from "../src/personal-lock.ts";
import type { Rigs } from "../src/rigs.ts";
import { holdLanguage } from "../src/i18n.ts";
import { parseTopic, TOPICS, type Topic } from "../src/protocol.ts";
import { OUTLINE_FOUND, OUTLINE_ROWS } from "../src/things.ts";
import { CHAT, OUTLINED, OUTLINED_ENTRIES, UP, devicesSaid, fixture, hostReading, messageAdded, outlinedEdit, outlinedLog, outlinedSaid, outlinedWorking, quotaChanged } from "./real-size.ts";
import { applyKeyed } from "../src/collections.ts";
import { hostOf, overview, setup } from "./views-rig.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

/// What a value sent whole may weigh, in KB.
const BAR_KB = 32;
/// What one message may weigh as something changes, in KB.
const DELTA_BAR_KB = 4;

/// Each way the app asks a topic (apps/mbui/src: `.topic("name"`, sfbase/bars.mbt `place_reads`; a chat's and its
/// jobs' `compact`, sfbase/source.mbt `core_topic_params`), by a name of its own.
const station = CHAT.station;
const key = CHAT.keys[0];
const ASKED: Record<string, Record<string, unknown> & { topic: string }> = {
  "stations": { topic: "stations", scope: "ws" },
  "station": { topic: "station", scope: "ws", station },
  "stationPart archiving": { topic: "stationPart", scope: "ws", station, part: "archiving" },
  "stationPart automaticDecisions": { topic: "stationPart", scope: "ws", station, part: "automaticDecisions" },
  "stationPart profiles": { topic: "stationPart", scope: "ws", station, part: "profiles" },
  "stationPart machineLogins": { topic: "stationPart", scope: "ws", station, part: "machineLogins" },
  "stationPart logins": { topic: "stationPart", scope: "ws", station, part: "logins" },
  "stationPart updates": { topic: "stationPart", scope: "ws", station, part: "updates" },
  "chats": { topic: "chats", scope: "ws", mine: false, limit: 50 },
  "chats mine": { topic: "chats", scope: "ws", mine: true, limit: 50 },
  "profiles": { topic: "profiles", scope: "ws" },
  "connects": { topic: "connects", scope: "ws", mine: false },
  "connects mine": { topic: "connects", scope: "ws", mine: true },
  // (a connect of the chat's station with sessions, of its runtime many: its page, and its choice of a session's list)
  "connect": { topic: "connect", scope: "ws", station, id: "c-slack-1" },
  "connectCandidates": { topic: "connectCandidates", scope: "ws", station, id: "c-slack-1" },
  "newChat": { topic: "newChat", scope: "ws" },
  "pick": { topic: "pick", station, of: "new" },
  "settings": { topic: "settings", scope: "ws" },
  "chat": { topic: "chat", station, session: key },
  "chat compact": { topic: "chat", station, session: key, compact: true },
  "chatJobs compact": { topic: "chatJobs", station, session: key, compact: true },
  "chatJobs summary": { topic: "chatJobs", station, session: key, compact: true, summary: true },
  "history": { topic: "history", station, key },
  "agentCard": { topic: "agentCard", station, key },
  "usage": { topic: "usage", scope: "ws", days: 7 },
  "fleet": { topic: "fleet", scope: "ws" },
  "railCard": { topic: "railCard", scope: "ws", place: "chats" },
  "resources": { topic: "resources", scope: "ws", station },
  "workspace": { topic: "workspace", workspace: "ws" },
  "workspaceMarks": { topic: "workspaceMarks", workspace: "ws" },
  "longJobs": { topic: "longJobs", scope: "ws" },
  "archive": { topic: "archive", scope: "ws", limit: 60 },
  "search": { topic: "search", scope: "ws", query: "迁移" },
  "chatSearch": { topic: "chatSearch", scope: "ws", query: "迁移", station, limit: 8, elsewhere: true, exclude: key },
  "changelog": { topic: "changelog" },
  "changelog news": { topic: "changelog", news: true },
  "devices": { topic: "devices", workspace: "ws" },
  // (of the chat of four weeks held whole: what it is made of is all of a chat held)
  "chatOutline": { topic: "chatOutline", station: OUTLINED.station, thread: OUTLINED.thread },
};

/// Those over `BAR_KB` now, by the name `ASKED` gives them: what each weighs, KB rounded up to a multiple of 8.
const OVER: Record<string, number> = {
  "chat": 344,
  "chat compact": 328,
  "profiles": 160,
  "usage": 144,
  "chats": 88,
  "chats mine": 88,
  "newChat": 80,
  "pick": 64,
  "station": 56,
  "history": 56,
};

/// Those over `DELTA_BAR_KB` as something changes, by `<name>/<cause>`: the heaviest message, KB as in `OVER`.
const OVER_DELTA: Record<string, number> = {
  "newChat/quota": 8,
  "chat/quota": 8,
  "chat compact/quota": 8,
  "pick/quota": 8,
};

/// The topics measured nowhere here, and why. (Not `stationsWhole`, the stations each with its page and its models:
/// the core's own, which no UI can ask, so it is no topic of `TOPICS`; views/views.ts.)
const RAW = "a station's raw record, no UI asks it";
const FORM = "a form's";
const OWN = "the device's own, does not grow with the workspace";
const PAGE = "a page's of one thing, does not grow with the workspace";
const LATER = "not yet in the fixture";
const NOT_MEASURED: Record<string, string> = {
  link: RAW, overview: RAW, sessions: RAW, session: RAW, host: RAW, memory: RAW, net: RAW, way: RAW, threads: RAW, thread: RAW, letters: RAW, chatRows: RAW,
  slackApp: RAW, jobs: RAW, machineLogins: RAW, machineLogin: RAW, machineLoginScreen: RAW, archivedRows: RAW, stationUsage: RAW, stationResources: RAW,
  stationSearch: RAW,
  slackTokens: FORM, connectFlow: FORM, decisionForm: FORM, policyForm: FORM, agentEnvForm: FORM, profileFlow: FORM, lockDraft: FORM,
  accounts: OWN, workspaces: OWN, loginSessions: OWN, status: OWN, connection: OWN, draft: OWN, composer: OWN, notify: OWN, prefs: OWN, doing: OWN,
  adbShare: OWN, adbCard: OWN, rigs: OWN, previewLoad: OWN, releases: OWN, fonts: OWN, downloads: OWN, drivePlace: OWN, filesTabs: OWN,
  driveTransfers: OWN, lockPrompts: OWN,
  admin: "still.fail's operators' console, not the app's", adminList: "still.fail's operators' console, not the app's", adminItem: "still.fail's operators' console, not the app's",
  adminOverview: "still.fail's operators' console, not the app's", adminRelays: "still.fail's operators' console, not the app's",
  presets: PAGE, linkPreview: PAGE, filePeek: PAGE, messagePeek: PAGE, screenCard: PAGE, job: PAGE, shareIn: PAGE, chatFeedback: PAGE, imageNear: PAGE,
  live: LATER, jobLog: LATER, drive: LATER, driveBrowse: LATER, notices: LATER, lock: LATER, vaults: LATER, vaultItems: LATER, vaultUses: LATER,
  joinable: LATER, memberships: LATER, screens: LATER, workspaceWays: LATER, stationNet: LATER, chatLetters: LATER, chatThings: LATER,
};

// ── weighing ──

const enc = new TextEncoder();
const bytes = (m: unknown) => enc.encode(JSON.stringify(m)).length;
const kb = (n: number) => n / 1024;
/// KB, rounded up to the next multiple of 8: what a table says.
const tableKb = (n: number) => Math.max(8, Math.ceil(kb(n) / 8) * 8);

/// The bytes of `s` in UTF-8.
const utf8 = (s: string) => enc.encode(s).length;
/// Whether a key reads as a field's name (letters alone, 24 at most): another is one of a map's.
const fieldName = (k: string) => /^[A-Za-z]{1,24}$/.test(k);
/// How far a path goes, in fields (a list's items of their list's depth).
const DEEP = 4;

/// What `j` weighs as JSON (its strings unescaped), each path under `path` at most `DEEP` fields deep added to `by` with
/// what is under it (apps/mbui/src/core/weights.mbt `weigh`).
function weigh(j: unknown, path: string, deep: number, by: Map<string, number>, own = true): number {
  let n: number;
  if (j === null) n = 4;
  else if (typeof j === "boolean") n = j ? 4 : 5;
  else if (typeof j === "number") n = JSON.stringify(j).length;
  else if (typeof j === "string") n = utf8(j) + 2;
  else if (Array.isArray(j)) {
    n = 2;
    j.forEach((x, i) => (n += weigh(x, `${path}[]`, deep, by, false) + (i > 0 ? 1 : 0)));
  } else {
    n = 2;
    const entries = Object.entries(j as Record<string, unknown>).filter(([, x]) => x !== undefined);
    const fields = entries.length <= 48 && entries.every(([k]) => fieldName(k));
    entries.forEach(([k, x], i) => {
      const under = !fields ? `${path}{}` : path === "" ? k : `${path}.${k}`;
      n += utf8(k) + 3 + weigh(x, under, deep + 1, by) + (i > 0 ? 1 : 0);
    });
  }
  if (own && path !== "" && deep <= DEEP) by.set(path, (by.get(path) ?? 0) + n);
  return n;
}

/// The `most` heaviest paths of `j`, the heaviest first.
function heaviest(j: unknown, most = 8): [string, number][] {
  const by = new Map<string, number>();
  weigh(j, "", 0, by);
  return [...by].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).slice(0, most);
}

const print = process.env.TOPIC_BYTES_PRINT === "1";

/// What the owner's phone was sent of `stations` by field (2026-11-10, his workspace of five stations, which
/// real-size.ts is made the size of): printed with the fixture's beside it, so a fixture drifting from it is seen.
const PHONE_STATIONS: [string, number][] = [
  ["", 463_533], ["[].models", 295_504], ["[].models[].accounts", 252_287], ["[].models[].accounts.codex", 104_352], ["[].models[].accounts.claude", 93_932],
  ["[].models[].accounts.devin", 25_872], ["[].models[].accounts.dsh", 24_060], ["[].models[].accounts.codex[].quota", 64_204], ["[].models[].accounts.claude[].quota", 59_149],
  ["[].overview", 153_336], ["[].overview.profiles", 97_199], ["[].overview.profiles[].check", 23_601], ["[].overview.automaticDecisions", 28_262],
];

/// The fixture's `stations` beside the phone's, by field.
function beside(value: unknown): string {
  const by = new Map<string, number>();
  const all = weigh(value, "", 0, by);
  const lines = ["The fixture's `stations` beside the phone's (bytes):"];
  for (const [path, phone] of PHONE_STATIONS) {
    const here = path === "" ? all : (by.get(path) ?? 0);
    lines.push(`    ${(path || "(whole)").padEnd(40)} ${String(here).padStart(9)} ${String(phone).padStart(9)}  ${(here / phone).toFixed(2)}×`);
  }
  return lines.join("\n");
}

/// The table of what was measured: name, bytes, KB; of one over its bar, its heaviest paths.
function table(title: string, rows: { name: string; bytes: number; bar: number; value?: unknown }[]): string {
  const lines = [title];
  for (const r of [...rows].sort((a, b) => b.bytes - a.bytes)) {
    const over = r.bytes > r.bar * 1024;
    lines.push(`  ${over ? "!" : " "} ${r.name.padEnd(40)} ${String(r.bytes).padStart(9)} B ${kb(r.bytes).toFixed(1).padStart(8)} KB`);
    if (over && r.value !== undefined) for (const [p, n] of heaviest(r.value)) lines.push(`        ${p.padEnd(48)} ${String(n).padStart(9)}`);
  }
  return lines.join("\n");
}

/// What a table's entries say against what was measured: those to bring out, those grown, those over and not listed.
function judge(measured: Map<string, number>, bar: number, over: Record<string, number>, named: string): string[] {
  const faults: string[] = [];
  for (const [name, n] of measured) {
    const listed = over[name];
    if (listed === undefined) {
      if (n > bar * 1024) faults.push(`${name}: ${kb(n).toFixed(1)} KB, over the bar of ${bar} KB (bring it down, or list it in ${named} at ${tableKb(n)})`);
    } else if (n <= bar * 1024) faults.push(`${name}: ${kb(n).toFixed(1)} KB, under the bar now: bring it out of ${named}`);
    else if (n > listed * 1024) faults.push(`${name}: ${kb(n).toFixed(1)} KB, grew past the ${listed} KB ${named} allows it by ${kb(n - listed * 1024).toFixed(1)} KB`);
  }
  for (const name of Object.keys(over)) if (!measured.has(name)) faults.push(`${name}: in ${named} but not measured`);
  return faults;
}

// ── the workspace, held as a UI holds it ──

/// Where the second subscription of each topic's ids begin.
const AGAIN = 1000;

const topicOf = (name: string): Topic => {
  const t = parseTopic(ASKED[name]);
  if (t === null) throw new Error(`${name}: not a topic the core knows: ${JSON.stringify(ASKED[name])}`);
  return t;
};

/// A rig with every view, a new chat's and a model's pickers, the changelog; the real-size workspace set in it, and
/// every topic of `ASKED` subscribed as the app subscribes (keyed), its messages to each by id.
async function held() {
  // (the workspace's devices as core.ts makes them: what each up station says, the rigs' none here)
  let devices: Devices | null = null;
  const t = setup({
    all: true,
    owners: ({ host, store, data, views }) => {
      devices = new Devices({
        host, store, rigs: () => ({ devices: () => [] }) as unknown as Rigs, personal: () => null as unknown as PersonalLock,
        subOf: (ws) => (ws === "ws" ? "s1" : null), emailOf: (ws) => (ws === "ws" ? "me@x.com" : null),
        view: (workspace) => data.shared({ topic: "workspace", workspace }), call: () => Effect.succeed(null),
      });
      const d = devices;
      return [
        new Choose({ store, data, now: () => host.nowMs(), agent: (s, k) => views.agent(s, k) }),
        new Changelog(host, store, data),
        { owns: (topic: Topic) => topic.topic === "devices", compute: (topic: Topic) => ({ ok: d.value(String(topic.workspace)) }) },
      ];
    },
  });
  const base = t.host.nowMs();
  const names = Object.keys(ASKED);
  names.forEach((name, i) => t.store.subscribe(1, i + 1, topicOf(name), true));
  // Set as the topics are watched, and again once the views watch what they found they are made of (a value set of a
  // topic nothing watches is not kept: the core's station topics read what is watched).
  for (let round = 0; round < 2; round++) {
    for (const [topic, value] of fixture(base)) t.set(topic, value);
    t.data.putItems("entry", OUTLINED.station, String(OUTLINED.thread), outlinedLog(base));
    for (const [i, station] of UP.entries()) devices!.heard(station, "devices", devicesSaid(base, i));
    await t.host.time.pass(100);
  }
  // (what is made after the rest: Markdown read, a page's words)
  for (let i = 0; i < 5; i++) await t.host.settle();
  t.host.takeEmitted();
  // What a UI is sent as it subscribes to a topic held already: its value whole, as it stands (the first a topic
  // sends a first subscriber may be what it has so far, the rest coming as it is read).
  names.forEach((name, i) => t.store.subscribe(1, AGAIN + i + 1, topicOf(name), true));
  await t.host.time.pass(100);
  const first = new Map<string, J>();
  for (const [, m] of t.host.takeEmitted()) {
    const name = names[(m as J).id - AGAIN - 1];
    if (name !== undefined && !first.has(name) && ("value" in m || "error" in m)) first.set(name, m);
  }
  /// The messages that go out while `f` and `ms` of the clock pass, by name.
  const during = async (f: () => void, ms: number): Promise<Map<string, J[]>> => {
    t.host.takeEmitted();
    f();
    await t.host.time.pass(ms, 100);
    const out = new Map<string, J[]>();
    for (const [, m] of t.host.takeEmitted()) {
      // (the second subscription of each is the same topic: one is counted)
      const name = names[(m as J).id - 1];
      if (name === undefined) continue;
      out.set(name, [...(out.get(name) ?? []), m]);
    }
    return out;
  };
  return { t, base, first, during };
}

test("what each topic the app asks is sent whole holds to its bar on a workspace of real size", async () => {
  const { t, first } = await held();
  try {
    const failed = Object.keys(ASKED).flatMap((name) => {
      const m = first.get(name);
      return m === undefined ? [`${name}: no value came`] : "error" in m ? [`${name}: ${JSON.stringify(m.error)}`] : [];
    });
    const measured = new Map([...first].filter(([, m]) => "value" in m).map(([name, m]) => [name, bytes(m)]));
    const faults = [...failed, ...judge(measured, BAR_KB, OVER, "OVER")];
    if (print || faults.length > 0) {
      console.log(table(`What each topic is sent whole (bar ${BAR_KB} KB):`, [...first].map(([name, m]) => ({ name, bytes: bytes(m), bar: OVER[name] !== undefined ? 0 : BAR_KB, value: m.value }))));
      if (first.get("stations")?.value !== undefined) console.log(beside(first.get("stations").value));
    }
    assert.deepEqual(faults, []);
  } finally {
    t.store.runner.shutdown();
  }
});

test("what each topic the app asks is sent as the workspace changes holds to its bar", async () => {
  const { t, base, during } = await held();
  try {
    const st = 0;
    const causes: [string, Map<string, J[]>][] = [];
    causes.push(["host", await during(() => t.set(hostOf(station), hostReading(t.host.nowMs(), st, 0.83)), 1000)]);
    causes.push(["quota", await during(() => t.set(overview(station), quotaChanged(base, t.host.nowMs(), st)), 1000)]);
    causes.push(["message", await during(() => {
      for (const [topic, value] of messageAdded(base, t.host.nowMs())) t.set(topic, value);
    }, 1000)]);
    // The chat of four weeks: its agent writing on (twice), a person's words edited, a person saying something.
    const log = (item: [number, unknown]) => t.data.putItems("entry", OUTLINED.station, String(OUTLINED.thread), [item]);
    causes.push(["agent", await during(() => {
      log(outlinedWorking(base, 1));
      log(outlinedWorking(base, 2));
    }, 1000)]);
    causes.push(["edit", await during(() => log(outlinedEdit(base, t.host.nowMs())), 1000)]);
    causes.push(["said", await during(() => log(outlinedSaid(base, t.host.nowMs())), 1000)]);
    causes.push(["minute", await during(() => {}, 60_000)]);
    const heaviestOf = new Map<string, number>();
    const rows: { name: string; bytes: number; bar: number; value?: unknown }[] = [];
    for (const [cause, sent] of causes) {
      for (const [name, messages] of sent) {
        const sizes = messages.map(bytes);
        const top = Math.max(...sizes);
        const at = `${name}/${cause}`;
        heaviestOf.set(at, top);
        const m = messages[sizes.indexOf(top)];
        rows.push({ name: `${at} (${messages.length}, ${sizes.reduce((a, b) => a + b, 0)} B in all)`, bytes: top, bar: OVER_DELTA[at] !== undefined ? 0 : DELTA_BAR_KB, value: m.value ?? m.delta });
      }
    }
    const faults = judge(heaviestOf, DELTA_BAR_KB, OVER_DELTA, "OVER_DELTA");
    if (print || faults.length > 0) console.log(table(`What goes out as the workspace changes, its heaviest message (bar ${DELTA_BAR_KB} KB):`, rows));
    assert.deepEqual(faults, []);
  } finally {
    t.store.runner.shutdown();
  }
});

// ── what a chat's outline answers ──

/// What looking in a chat's outline finds of the words of `queries` (as station/topics.ts `found` gives the messages that
/// have them, all held), each answer.
function outlineFinds(t: ReturnType<typeof setup>, queries: string[]): [string, J][] {
  return queries.map((q) => {
    const found = t.data.findInThread(OUTLINED.station, OUTLINED.thread, [q]).map((f) => ({ ...f, count: 1 }));
    const span = t.data.logSpan("entry", OUTLINED.station, String(OUTLINED.thread))!;
    return [q, t.views.outlineFound(OUTLINED.station, OUTLINED.thread, { words: [q], found, held: span.count, of: span.max, whole: true })];
  });
}
/// The words that are in most of the long chat's messages, its people's and its agent's.
const COMMON = ["的", "，", "。", "e", "a", "i", "1"];

test("the rows a chat's outline gives at once hold to the bar on a chat of real size", async () => {
  const { t, first } = await held();
  try {
    const seqs: number[] = first.get("chatOutline").value.days.flatMap((d: J) => d.seqs);
    const newest = t.views.outlineRows(OUTLINED.station, OUTLINED.thread, seqs.slice(-OUTLINE_ROWS));
    // (the hundred heaviest of all its people's messages, as one answer)
    const all = t.views.outlineRows(OUTLINED.station, OUTLINED.thread, seqs).rows as J[];
    const heaviest = { rows: [...all].sort((a, b) => bytes(b) - bytes(a)).slice(0, OUTLINE_ROWS) };
    if (print) {
      console.log(`The chat of four weeks: ${seqs.length} messages of people of ${OUTLINED_ENTRIES} entries, over ${first.get("chatOutline").value.days.length} days; its outline ${bytes(first.get("chatOutline"))} B whole`);
      console.log(`chat.outline.rows: the newest ${newest.rows.length} ${bytes(newest)} B, the heaviest ${heaviest.rows.length} ${bytes(heaviest)} B`);
    }
    assert.equal(newest.rows.length, OUTLINE_ROWS);
    assert.ok(bytes(newest) <= BAR_KB * 1024, `${bytes(newest)} B`);
    assert.ok(bytes(heaviest) <= BAR_KB * 1024, `${bytes(heaviest)} B`);
  } finally {
    t.store.runner.shutdown();
  }
});

test("what looking in a chat's outline finds lists fifty at most, and says how many more", async () => {
  const { t } = await held();
  try {
    for (const [q, a] of outlineFinds(t, COMMON)) {
      assert.ok(a.total > OUTLINE_FOUND, q);
      assert.equal(a.days.flatMap((d: J) => d.items).length, OUTLINE_FOUND, q);
      assert.equal(a.more, a.total - OUTLINE_FOUND, q);
    }
  } finally {
    t.store.runner.shutdown();
  }
});

/// The heaviest a found row's `by` is: an agent's, its label, session, maker and runtime (views.ts shownMessage), its
/// session's key at its longest kind (`chat:c-` and 32 hex digits).
const LONG_KEY = "chat:c-c9091c93d6d6685b7330e4bd2d7eabbe";

test("what looking in a chat's outline finds holds to the bar on a chat of real size, and at its heaviest", async () => {
  const { t } = await held();
  try {
    const finds = outlineFinds(t, COMMON);
    // The heaviest that can be: fifty found of an agent's, each a line of Chinese with the words far into it.
    const heavy = 5000;
    const agent = (t.data.thread(OUTLINED.station, OUTLINED.thread) as J).sessions.map((s: J) => s.session)[0];
    t.data.putItems("entry", OUTLINED.station, String(OUTLINED.thread), Array.from({ length: OUTLINE_FOUND + 10 }, (_, i): [number, J] => [heavy + i, {
      thread: OUTLINED.thread, n: heavy + i, kind: "message", ts: `${OUTLINED.thread}.${heavy + i}`, authorKind: "agent", author: agent, authorName: null,
      text: `${"迁移演练的完整记录导出新实例".repeat(2)}逻辑复制${"追平增量延迟稳定切换停写校验".repeat(10)}`, at: t.host.nowMs() + i,
    }]));
    const [[, worst]] = outlineFinds(t, ["逻辑复制"]);
    const rows = worst.days.flatMap((d: J) => d.items);
    // (its agent's session's key the longest a key is)
    const longest = { ...worst, days: worst.days.map((d: J) => ({ ...d, items: d.items.map((r: J) => ({ ...r, author: LONG_KEY, by: { ...r.by, agent: LONG_KEY } })) })) };
    if (print) {
      for (const [q, a] of finds) console.log(`chat.outline.find "${q}": ${a.total} found, ${a.total - a.more} listed, ${bytes(a)} B`);
      console.log(`chat.outline.find at its heaviest: ${rows.length} of an agent's, ${bytes(longest)} B (its by ${bytes(rows[0].by)} B, a snippet ${bytes(rows[0].snippet)} B: ${rows[0].snippet})`);
    }
    assert.equal(rows.length, OUTLINE_FOUND);
    assert.ok(rows.every((r: J) => r.agent && r.by.maker !== undefined && r.snippet.endsWith("…")));
    for (const [q, a] of finds) assert.ok(bytes(a) <= BAR_KB * 1024, `"${q}": ${bytes(a)} B`);
    assert.ok(bytes(longest) <= BAR_KB * 1024, `${bytes(longest)} B`);
  } finally {
    t.store.runner.shutdown();
  }
});

// ── asked again ──
//
// A topic the app keeps as it lets go of it (`keep`), asked again with the version it kept (`have`), is sent `same`
// where it has not changed, else what changed from what it kept (store.ts `#first`), else its value whole. Measured
// for every way the app asks such a topic: let go of, each cause above happening while it is, asked again; its first
// message at most `DELTA_BAR_KB`, those over in `OVER_AGAIN` (by `<name>/<cause>`, as `OVER_DELTA`), which only falls.

/// The topics the app keeps as it lets go of them (apps/mbui/src/sfbase/source.mbt `topic_kept`: the lists the places
/// open on, `lasting`, and `chat`).
const KEPT = new Set(["workspace", "stations", "stationNet", "profiles", "connects", "vaults", "usage", "archive", "chat"]);

/// Those whose first message asked again after a cause is over `DELTA_BAR_KB`, by `<name>/<cause>`: KB as in `OVER`.
const OVER_AGAIN: Record<string, number> = {
  "chat/quota": 8,
  "chat compact/quota": 8,
};

/// What `m`, a first message, is: `same`, `kept` (what changed from what was kept), `value` (whole), else `?`.
const said = (m: J): string => ("same" in m ? "same" : "kept" in m ? "kept" : "value" in m ? "value" : "?");

test("what a topic the app keeps is sent as it is asked again after something changed holds to its bar", async () => {
  const { t, base } = await held();
  try {
    const names = Object.keys(ASKED).filter((name) => KEPT.has(ASKED[name]!.topic));
    const st = 0;
    const causes: [string, () => void, number][] = [
      ["host", () => t.set(hostOf(station), hostReading(t.host.nowMs(), st, 0.83)), 1000],
      ["quota", () => t.set(overview(station), quotaChanged(base, t.host.nowMs(), st)), 1000],
      ["message", () => {
        for (const [topic, value] of messageAdded(base, t.host.nowMs())) t.set(topic, value);
      }, 1000],
      ["minute", () => {}, 60_000],
    ];
    /// The first message to `id` once `f` was done.
    const firstTo = async (id: number, f: () => void): Promise<J> => {
      t.host.takeEmitted();
      f();
      await t.host.time.pass(100);
      return t.host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === id && !("waiting" in m));
    };
    let id = 10_000;
    const measured = new Map<string, number>();
    const rows: { name: string; whole: number; now: number; how: string }[] = [];
    const faults: string[] = [];
    for (const [cause, f, ms] of causes) {
      // Each subscribed as the app asks it, and let go of keeping what it was sent.
      const kept = new Map<string, { value: unknown; v: string }>();
      for (const name of names) {
        const at = ++id;
        const m = await firstTo(at, () => t.store.subscribe(1, at, topicOf(name), true));
        const v = await firstTo(at, () => t.store.unsubscribe(1, at, true));
        if (m === undefined || !("value" in m) || typeof v?.v !== "string") faults.push(`${name}/${cause}: nothing kept (${JSON.stringify(m)?.slice(0, 80)}, ${JSON.stringify(v)})`);
        else kept.set(name, { value: m.value, v: v.v });
      }
      t.host.takeEmitted();
      f();
      await t.host.time.pass(ms, 100);
      // Asked again with it; and as one that kept nothing, whole, to weigh it against.
      for (const [name, { value, v }] of kept) {
        const again = ++id;
        const fresh = ++id;
        const m = await firstTo(again, () => t.store.subscribe(1, again, topicOf(name), true, undefined, v));
        const w = await firstTo(fresh, () => t.store.subscribe(1, fresh, topicOf(name), true));
        t.store.unsubscribe(1, again);
        t.store.unsubscribe(1, fresh);
        const at = `${name}/${cause}`;
        if (m === undefined || w === undefined || !("value" in w)) {
          faults.push(`${at}: ${JSON.stringify(m)?.slice(0, 80)}, ${JSON.stringify(w)?.slice(0, 80)}`);
          continue;
        }
        // (what it holds then is what it would be sent whole)
        const holds = "same" in m ? value : "kept" in m ? applyKeyed(value, m.delta) : m.value;
        if (JSON.stringify(canonical(holds)) !== JSON.stringify(canonical(w.value))) faults.push(`${at}: asked again (${said(m)}), it holds another value than the one whole`);
        measured.set(at, bytes(m));
        rows.push({ name: at, whole: bytes(w), now: bytes(m), how: said(m) });
      }
    }
    faults.push(...judge(measured, DELTA_BAR_KB, OVER_AGAIN, "OVER_AGAIN"));
    if (print || faults.length > 0) {
      const lines = [`What a topic kept is sent asked again, its first message (bar ${DELTA_BAR_KB} KB), beside its value whole:`];
      for (const r of rows) {
        const over = r.now > DELTA_BAR_KB * 1024;
        lines.push(`  ${over ? "!" : " "} ${r.name.padEnd(28)} ${r.how.padEnd(6)} ${String(r.now).padStart(9)} B ${kb(r.now).toFixed(1).padStart(7)} KB   whole ${String(r.whole).padStart(9)} B ${kb(r.whole).toFixed(1).padStart(7)} KB`);
      }
      console.log(lines.join("\n"));
    }
    assert.deepEqual(faults, []);
  } finally {
    t.store.runner.shutdown();
  }
});

/// `v` with every object's keys in order: two values alike whatever order their keys were made in.
function canonical(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(canonical);
  if (v === null || typeof v !== "object") return v;
  const o = v as Record<string, unknown>;
  return Object.fromEntries(Object.keys(o).sort().filter((k) => o[k] !== undefined).map((k) => [k, canonical(o[k])]));
}

test("every topic of the core is measured or says why not", () => {
  const asked = new Set(Object.values(ASKED).map((a) => a.topic));
  const faults: string[] = [];
  for (const name of Object.keys(TOPICS)) {
    const here = asked.has(name);
    const why = NOT_MEASURED[name];
    if (here && why !== undefined) faults.push(`${name}: asked, and NOT_MEASURED says ${why}`);
    if (!here && why === undefined) faults.push(`${name}: neither asked nor in NOT_MEASURED: place it`);
  }
  for (const name of [...asked, ...Object.keys(NOT_MEASURED)]) if (!(name in TOPICS)) faults.push(`${name}: no topic of the core`);
  assert.deepEqual(faults, []);
});

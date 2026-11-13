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
// most `BAR_KB`; then, the subscriptions held, what goes out as the workspace changes (each cause of real-size-asked.ts
// `CAUSES`: a station's host reading, a message in the chat, a minute passing, …), each message at most `DELTA_BAR_KB`. Those over a bar now are in `OVER` (by topic) and `OVER_DELTA` (by topic/cause),
// each with what it weighs now in KB, rounded up to the next 8 so the fixture's drift does not flap it: one there must
// still be over the bar (else it comes out of the table) and no heavier than said (else it grew). The tables only fall.
// Every topic of `TOPICS` is either asked here or in `NOT_MEASURED` with why: a new topic is placed in one of them.
// What is weighed is weighed full: every list and map a value's shape declares holds something in the fixture, or is
// in `EMPTY` with why (a topic weighed empty passed at tens of bytes: `changelog`, 2026-11-11, ~190 KB on a phone).
// On failure, and with TOPIC_BYTES_PRINT=1, the table is printed: each topic's bytes, and of one over its bar its
// heaviest fields (a list's items as `[]`), as the app's `@core.weights` says them, and the fixture's `stations` field
// by field beside what the owner's phone was sent (`PHONE_STATIONS`).
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import type { Ty } from "../src/conform.ts";
import { shapeOf } from "../src/present.ts";
import { parseTopic, TOPICS, type Topic } from "../src/protocol.ts";
import { SHAPES } from "../src/shapes/schema.ts";
import { equal, isObject } from "../src/util.ts";
import { OUTLINE_FOUND, OUTLINE_ROWS } from "../src/things.ts";
import { OUTLINED, OUTLINED_ENTRIES, liveOf } from "./real-size.ts";
import { base, started } from "./station-fixture.ts";
import { applyKeyed } from "../src/collections.ts";
import { setup } from "./views-rig.ts";
import { ASKED, CAUSES, CHANGELOG_PAGE, LONG, causesOfAll, topicOf, held, firstOfAll } from "./real-size-asked.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

/// What one message may weigh as something changes, in KB.
const DELTA_BAR_KB = 4;
/// What a value sent whole may weigh, in KB.
const BAR_KB = 32;

/// Those over `BAR_KB` now, by the name `ASKED` gives them: what each weighs, KB rounded up to a multiple of 8.
const OVER: Record<string, number> = {
  "chat six pages": 264,
  "chat compact six pages": 264,
  "vaultUses": 128,
  "usage": 112,
  "jobLog 400": 96,
  "jobLog 300": 72,
  "drive": 72,
  // (its first window, 30 rows as the app asks them: real-size-asked.ts WINDOWS; the list of all of them, under the bar)
  "chats mine": 40,
  "history": 56,
  "chat": 56,
  "chat compact": 56,
  "chatLetters": 40,
};

/// Those over `DELTA_BAR_KB` as something changes, by `<name>/<cause>`: the heaviest message, KB as in `OVER`.
const OVER_DELTA: Record<string, number> = {
  // (a list scrolled near its foot told a window a step more: the step's 20 rows, ~1 KB each, put in its days, never
  // the list whole again; a step of rows a screen holds is what the app needs the moment it comes)
  "chats mine/grown": 24,
  "chats/grown": 24,
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
  "profiles/down": 16,
  "chatThings/thing": 16,
  "chatThings q/thing": 16,
  "driveBrowse phone/file": 16,
  "driveBrowse columns/file": 16,
  "archive/down": 16,
  "notices/card": 16,
  "workspaceMarks/card": 8,
  "longJobs/job": 16,
  "resources/sample": 8,
  "connects mine/down": 8,
  "stationPart automaticDecisions/decided": 8,
};

/// The topics measured nowhere here, and why. (Not `stationsWhole`, the stations each with its page and its models:
/// the core's own, which no UI can ask, so it is no topic of `TOPICS`; views/views.ts.)
const RAW = "a station's raw record, no UI asks it";
const FORM = "a form's";
/// What the device keeps of its own, and what a page of one thing holds, unweighed only where the core bounds it (the
/// bound named); the rest of them (`UNBOUNDED`) grow with nothing the core holds back, not weighed yet: what the report
/// of 2026-11-11 found of each.
const UNBOUNDED = "nothing in the core bounds it (to weigh)";
const NOT_MEASURED: Record<string, string> = {
  link: RAW, overview: RAW, sessions: RAW, session: RAW, host: RAW, memory: RAW, net: RAW, way: RAW, threads: RAW, thread: RAW, letters: RAW, chatRows: RAW,
  slackApp: RAW, jobs: RAW, machineLogins: RAW, machineLogin: RAW, machineLoginScreen: RAW, archivedRows: RAW, stationUsage: RAW, stationResources: RAW,
  stationSearch: RAW,
  slackTokens: FORM, connectFlow: FORM, decisionForm: FORM, policyForm: FORM, agentEnvForm: FORM, profileFlow: FORM, lockDraft: FORM,
  adbCard: "four fields, its line a word of the core's or the phone's message (adb.ts card)", releases: "one number (core.ts `told`)",
  fonts: "the fonts of a fixed catalogue, by id (font-files.ts, fonts.ids, SHARE_LOOKS_FILES)", drivePlace: "three fields (DrivePlace)",
  filesTabs: "twelve tabs at most, each of one or two panes (drive-browse.ts MOST_TABS)",
  previewLoad: "200 rows at most, past it only while those that load have not finished (preview-load.ts)",
  accounts: UNBOUNDED, workspaces: UNBOUNDED, loginSessions: UNBOUNDED, status: UNBOUNDED, connection: UNBOUNDED, draft: UNBOUNDED, composer: UNBOUNDED,
  notify: UNBOUNDED, prefs: UNBOUNDED, doing: UNBOUNDED, adbShare: UNBOUNDED, rigs: UNBOUNDED, downloads: UNBOUNDED, driveTransfers: UNBOUNDED, lockPrompts: UNBOUNDED,
  admin: "still.fail's operators' console, not the app's", adminList: "still.fail's operators' console, not the app's", adminItem: "still.fail's operators' console, not the app's",
  adminOverview: "still.fail's operators' console, not the app's", adminRelays: "still.fail's operators' console, not the app's",
  screenCard: "eight fields of one screen (screens.ts screenCard)", imageNear: "the two pictures beside one, at most (placed.ts near)",
  shareIn: "30 chats (share-in.ts LISTED) and the workspace's stations, 64 at most (client/limits.ts STATIONS_PER_WORKSPACE)",
  chatFeedback: UNBOUNDED,
};

/// What a topic's value as the fixture makes it holds nothing of, though its shape declares it (a list, a map), by the
/// name `ASKED` gives it and the path (as the table prints them; `(whole)` the value itself, a variant of a union in
/// parentheses), and why the fixture has none of it: a path under one listed is listed with it. A value weighed with
/// a list empty weighs nothing of what a workspace of real size has in it, so what is listed here must be what such a
/// workspace has none of, or a state it is not in. It only falls: one that now holds something comes out.
const ERROR = "an error, which the fixture's workspace is not in";
const WELL = "what is wrong, and all is well there";
const SAVING = "a change being saved or sent, none in the fixture";
const NONE = "a thing the workspace of real size has none of";
const STATE = "a state the fixture is not in";
const OLDER = "on the chat's earlier pages, not its last (its six pages' hold it)";
const LETTER = "what a letter, an agent's words to another chat, does not have";
const ASKED_SO = "not made for the way the app asks it here";
const NEVER = "the core never makes it, whatever the workspace";
const KIND = "another kind's: of a pull request (labels, its time), a text file (lines), a folder (entries)";
/// A chat's paths EMPTY lists, as each way of asking it has them: the chat at its last page (`older`), compact.
const chatEmpty = (older: boolean, compact: boolean): Record<string, string> => ({
  // (QuotaWindow's `time`: present.ts `times` makes a quota's windows anew, never into each; `refills` says `resetsAt`)
  "agents[].profile.quota.windows[].time": NEVER, "agents[].account.quota.windows[].time": NEVER,
  // (kept to a multi-account subset: the chat weighed runs unrestricted)
  "agents[].session.profiles": STATE,
  // (a Slack message given to the agent with files)
  "messages[].elsewhere[].attachments": STATE,
  // (what its agents said in Slack before its first message read: one read from its first message has said nothing before it)
  elsewhere: older ? OLDER : STATE,
  outbox: SAVING,
  ...(older ? { "messages[].notice.lines": OLDER } : {}),
  // (compact sends a chat's jobs as `chatJobs` does: output.ts compactChat)
  ...(compact ? { "agents[].jobs": ASKED_SO } : {}),
});
const EMPTY: Record<string, Record<string, string>> = {
  "station": {
    problems: WELL, profileStates: WELL, "overview.profiles[].modelsSaving": SAVING,
    // (a decision-only provider's, Jev's; the workspaces the station joined, it joined none)
    "overview.profiles[].decisionModels": NONE, "overview.profiles[].workspaces": NONE,
    // (offers: a station with no chats of its own; formerly: the stations it took the place of, none lost; taking: a
    // retired station's chats being taken here, none retired; retire.steps: the station being retired, it is not)
    "overview.copies.offers": STATE, "overview.copies.formerly": NONE, "overview.copies.taking": STATE,
    "overview.copies.retire.steps": STATE,
  },
  "stationPart profiles": { "[].modelsSaving": SAVING, "[].quota.windows[].time": NEVER, "[].decisionModels": NONE, "[].workspaces": NONE },
  // (a sign-in under way: Willow's)
  "stationPart logins": { "(whole)": STATE },
  "chats": { "note.failing": ERROR },
  "chats mine": { "note.failing": ERROR },
  // (foundMarks: a search's alone, views/search.ts foundChat; the chat weighed is shared with no other workspace)
  "chatRow": { foundMarks: NEVER, "xshare.to": STATE },
  // (profiles.ts gives its note no failing)
  "profiles": { "wait.failing": NEVER },
  // (a ChatGPT account's allowance: a count of resets and when each ends, no kinds, as a station tells Codex's,
  // accounts/quota.ts withCodexCredits; the Claude one asked by its station holds them)
  // (the Claude one used by no chat; the ChatGPT one by three)
  "profile": { "profile.usedBy": NONE },
  "profile key": { "profile.quota.resets": NONE },
  "connects": { "wait.failing": ERROR, "items[].connect.bind.profiles": STATE },
  "connects mine": { "wait.failing": ERROR, "items[].connect.bind.profiles": STATE },
  // (asked for its last line alone, a job's row: no lines, jobs.ts log)
  "jobLog line": { lines: ASKED_SO },
  // (a single-session connect's session, and the one weighed is many sessions')
  "connect": { "connect.bind.profiles": STATE, "sessions[].profiles": STATE, "bound.profiles": STATE, "bound.efforts": STATE, "bound.time": STATE, "bound.watch.names": STATE },
  "newChat": { "pick.value.profiles": STATE },
  // (a new chat's pick names no account's allowance, choose.ts `#now` quiet; the model it takes with nothing chosen,
  // Fable, runs on one runtime and takes no Devin sidekick; borrow: a model only another station has, picked)
  "pick": { "value.profiles": STATE, "draft.profiles": STATE, "account.profile.quota.windows": ASKED_SO, runtimes: STATE, sidekicks: STATE, "borrow.lines": STATE },
  "chat": chatEmpty(true, false),
  "chat compact": chatEmpty(true, true),
  "chat six pages": chatEmpty(false, false),
  "chat compact six pages": chatEmpty(false, true),
  // (a summary says whether there are jobs, jobs.ts)
  "chatJobs summary": { jobs: ASKED_SO },
  // (its account unable to run, the disk filling, its context cut mid-turn)
  "agentCard": { attention: STATE },
  "usage": { "wait.failing": ERROR },
  // (the chats' card has no rows, rail-cards.ts chatsCard: the usage card's are weighed)
  "railCard": { rows: ASKED_SO, days: ASKED_SO },
  // (notes: a station down, unread or not counting; the one asked is up and counted)
  "resources": { "wait.failing": ERROR, notes: WELL },
  "archive": { errors: ERROR, "wait.failing": ERROR },
  // (none of the chats found is one shared, or one waiting on a card)
  "search": {
    "items[].xshare.to": STATE, "messages[].chat.decision.options": STATE, "messages[].chat.decision.card.options": STATE, "messages[].chat.decision.card.vaultAsk.hosts": STATE,
    "messages[].chat.foundMarks": NEVER, "wait.failing": ERROR,
  },
  // (words, messages: asked with `messages`, which the app does not pass)
  "chatSearch": { "items[].xshare.to": STATE, "items[].foundMarks": NEVER, words: ASKED_SO, messages: ASKED_SO },
  // (asked for its news alone: no tab is made, changelog.ts)
  "changelog news": { tabs: ASKED_SO },
  // (a rig's devices', a station that only runs tasks: the workspace has none)
  "devices": { "devices[].requests": NONE },
  // (names chosen, a tree's folders open, columns widened by hand)
  "driveBrowse phone": { "chosen.names": STATE, open: STATE, widths: STATE },
  "driveBrowse columns": { "chosen.names": STATE, open: STATE, widths: STATE },
  // (this device being approved face to face)
  // (`upgrade`: a handover of safe mode under way on the owner's device, which none is while it is not done by itself)
  "lock": { "me.pair.approvers": STATE, "upgrade.lines": STATE },
  "vaults": { refused: ERROR },
  // (a simulator's panels and case: none is up)
  "screens": { "screens[].panels": STATE, "screens[].chrome": STATE },
  "chatLetters": {
    "chats[].letters[].quotes": LETTER, "chats[].letters[].notice.lines": LETTER, "chats[].letters[].options": LETTER, "chats[].letters[].card.options": LETTER,
    "chats[].letters[].card.vaultAsk.hosts": LETTER, "chats[].letters[].elsewhere": LETTER, "chats[].letters[].chats": LETTER,
  },
  // (what is looked for, `png`, only pictures' names have)
  "chatThings q": { files: ASKED_SO, links: ASKED_SO, pulls: ASKED_SO },
  "linkPreview page": { labels: KIND, time: KIND },
  "filePeek picture": { "lines.text": KIND, entries: KIND },
  "filePeek text": { entries: KIND },
};
/// Those that may say `loading: true` as they are weighed, by topic, and why.
const LOADING: Record<string, string> = {};

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


test("what each topic the app asks is sent whole holds to its bar on a workspace of real size", async () => {
  const first = await firstOfAll();
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
});

// ── what the fixture leaves empty ──

/// `path` and a field of it, as the table says paths (`(whole)` the value itself).
const pathAt = (path: string, k: string) => (path === "" ? k : `${path}.${k}`);
const shown = (path: string) => (path === "" ? "(whole)" : path);

/// Every list and map `ty` declares under `path`, at every depth (a shape met again inside itself not gone into).
function declared(ty: Ty, path: string, out: Set<string>, within: string[] = []): void {
  if (typeof ty === "object") {
    if ("opt" in ty) return declared(ty.opt, path, out, within);
    if ("vec" in ty) {
      out.add(path);
      return declared(ty.vec, `${path}[]`, out, within);
    }
    if ("map" in ty) {
      out.add(path);
      return declared(ty.map, `${path}{}`, out, within);
    }
    return ty.tuple.forEach((t, i) => declared(t, `${path}[${i}]`, out, within));
  }
  const shape = SHAPES[ty];
  if (shape === undefined || shape.kind === "enum" || within.includes(ty)) return;
  const inner = [...within, ty];
  if (shape.kind === "tagged") for (const [w, t] of Object.entries(shape.variants)) declared(t, `${pathAt(path, shape.content)}(${w})`, out, inner);
  else for (const f of shape.fields) declared(f.ty, pathAt(path, f.name), out, inner);
}

/// The lists and maps of `v` (as `ty`) that hold something, by path, added to `out`.
function holding(v: unknown, ty: Ty, path: string, out: Set<string>): void {
  if (v === null || v === undefined) return;
  if (typeof ty === "object") {
    if ("opt" in ty) return holding(v, ty.opt, path, out);
    if ("vec" in ty) {
      if (!Array.isArray(v)) return;
      if (v.length > 0) out.add(path);
      return v.forEach((x) => holding(x, ty.vec, `${path}[]`, out));
    }
    if ("map" in ty) {
      if (typeof v !== "object") return;
      const xs = Object.values(v as object);
      if (xs.length > 0) out.add(path);
      return xs.forEach((x) => holding(x, ty.map, `${path}{}`, out));
    }
    if (Array.isArray(v)) ty.tuple.forEach((t, i) => holding(v[i], t, `${path}[${i}]`, out));
    return;
  }
  const shape = SHAPES[ty];
  if (shape === undefined || shape.kind === "enum" || typeof v !== "object") return;
  const o = v as Record<string, unknown>;
  if (shape.kind === "tagged") {
    const t = shape.variants[String(o[shape.tag])];
    if (t !== undefined) holding(o[shape.content], t, `${pathAt(path, shape.content)}(${String(o[shape.tag])})`, out);
  } else for (const f of shape.fields) holding(o[f.name], f.ty, pathAt(path, f.name), out);
}

/// Of a value no shape declares: its lists and objects, and those of them that hold something.
function found(v: unknown, path: string, all: Set<string>, held: Set<string>): void {
  if (v === null || typeof v !== "object") return;
  all.add(path);
  const xs = Array.isArray(v) ? v : Object.values(v);
  if (xs.length > 0) held.add(path);
  if (Array.isArray(v)) v.forEach((x) => found(x, `${path}[]`, all, held));
  else for (const [k, x] of Object.entries(v)) found(x, fieldName(k) ? pathAt(path, k) : `${path}{}`, all, held);
}

/// Whether `outer` is a path `path` is under.
const under = (path: string, outer: string) => path !== outer && (outer === "" || (path.startsWith(outer) && "[{.(".includes(path[outer.length]!)));

/// What `EMPTY` says against what the values sent whole hold: each list or map no value fills that is not listed,
/// each listed that holds something now or is no path of its shape, a value that is still loading or none.
function emptyFaults(first: Map<string, J>): string[] {
  const faults: string[] = [];
  for (const name of Object.keys(ASKED)) {
    const m = first.get(name);
    const listed = EMPTY[name] ?? {};
    if (m === undefined || !("value" in m) || m.value === null || m.value === undefined) {
      faults.push(`${name}: answered with no value (${m === undefined ? "nothing came" : JSON.stringify(m.error ?? m.value)})`);
      continue;
    }
    if (isObject(m.value) && m.value.loading === true && LOADING[ASKED[name]!.topic] === undefined) faults.push(`${name}: still loading as it is weighed: the fixture gives it nothing to read`);
    const ty = shapeOf(topicOf(name));
    const all = new Set<string>();
    const held = new Set<string>();
    if (ty === undefined) found(m.value, "", all, held);
    else {
      declared(ty, "", all);
      holding(m.value, ty, "", held);
    }
    const empty = [...all].filter((p) => !held.has(p));
    const outermost = empty.filter((p) => !empty.some((o) => under(p, o)));
    for (const p of outermost) if (listed[shown(p)] === undefined) faults.push(`${name}: ${shown(p)} is empty in the fixture: fill it in real-size.ts, or list it in EMPTY with why`);
    for (const p of Object.keys(listed)) {
      const at = p === "(whole)" ? "" : p;
      if (!all.has(at)) faults.push(`${name}: EMPTY lists ${p}, no list or map of its shape`);
      else if (held.has(at)) faults.push(`${name}: ${p} holds something now: bring it out of EMPTY`);
      else if (!outermost.includes(at)) faults.push(`${name}: EMPTY lists ${p}, under ${shown(outermost.find((o) => under(at, o))!)} listed already`);
    }
  }
  for (const name of Object.keys(EMPTY)) if (!(name in ASKED)) faults.push(`${name}: in EMPTY but not asked`);
  return faults;
}

test("what each topic the app asks is sent whole fills what its shape declares", async () => {
  const faults = emptyFaults(await firstOfAll());
  if (print || faults.length > 0) console.log(["What the fixture leaves empty, not in EMPTY or wrongly there:", ...faults.map((f) => `    ${f}`)].join("\n"));
  assert.deepEqual(faults, []);
});

/// What goes out to each of `ASKED` as each cause of `CAUSES` happens (real-size-asked.ts), made once for the tests here.
let causesMade: ReturnType<typeof causesOfAll> | undefined;
const causesSent = () => (causesMade ??= causesOfAll());

/// What op `op` (a keyed message's) does, where, and what it weighs: as a line of the table.
const opLine = (op: J) => `        ${(["put", "patch", "drop", "move", "set", "append", "remove"].find((k) => k in op) ?? "?").padEnd(6)} ${JSON.stringify(op.path).padEnd(42)} ${JSON.stringify(op.key ?? "").slice(0, 40).padEnd(40)} ${String(bytes(op)).padStart(9)} B`;

test("what each topic the app asks is sent as the workspace changes holds to its bar", async () => {
  const heaviestOf = new Map<string, number>();
  const rows: { name: string; bytes: number; bar: number; value?: unknown }[] = [];
  /// Of each message over the bar, its ops (or that it is a value whole), the heaviest first.
  const ops: string[] = [];
  for (const { cause, sent } of await causesSent()) {
    for (const [name, messages] of sent) {
      const sizes = messages.map(bytes);
      const top = Math.max(...sizes);
      const at = `${name}/${cause}`;
      heaviestOf.set(at, top);
      const m = messages[sizes.indexOf(top)];
      rows.push({ name: `${at} (${messages.length}, ${sizes.reduce((a, b) => a + b, 0)} B in all)`, bytes: top, bar: OVER_DELTA[at] !== undefined ? 0 : DELTA_BAR_KB, value: m.value ?? m.delta });
      if (top > DELTA_BAR_KB * 1024) {
        ops.push(`  ${at}: ${top} B, ${"value" in m ? "its value whole" : `${(m.delta as J[]).length} ops`}`);
        if (Array.isArray(m.delta)) ops.push(...[...(m.delta as J[])].sort((a, b) => bytes(b) - bytes(a)).slice(0, 12).map(opLine));
      }
    }
  }
  const faults = judge(heaviestOf, DELTA_BAR_KB, OVER_DELTA, "OVER_DELTA");
  if (print || faults.length > 0) {
    console.log(table(`What goes out as the workspace changes, its heaviest message (bar ${DELTA_BAR_KB} KB):`, rows));
    if (ops.length > 0) console.log(["Of each over the bar, its heaviest ops (what, path, key, bytes):", ...ops].join("\n"));
  }
  assert.deepEqual(faults, []);
});

// ── what changes while shown ──
//
// What a topic sends as the workspace changes is weighed only where some cause above sends it something: a name no
// cause reached was weighed whole and never as it changes (a job's log re-sent whole, 128 KB, for every line it printed,
// for months: no cause printed a line). So every way the app asks a topic (`ASKED`) has a cause that changes what it
// shows (`CAUSES`, real-size-asked.ts), or is in `STILL` with why its value does not change while a page shows it. It
// only falls: one listed that a cause now reaches comes out.

/// Why a value does not change while shown: read as it opens and not again; changed only by what the same page does
/// (the call named); a device's or the cloud's that nothing tells it of.
const READ_ONCE = (how: string) => `read once as its page opens, not again while it shows (${how})`;
const BY_PAGE = (call: string) => `changed only by what this same page does (${call})`;
const UNTOLD = (what: string) => `nothing tells the core it changed (${what})`;
const CARD = READ_ONCE("station/sync.ts #cardShown: a card's read each time it shows, kept meanwhile");
/// Those of `ASKED` no cause sends a message, by the name `ASKED` gives them, and why.
const STILL: Record<string, string> = {
  // (a model control's: what the station's accounts read, their allowances, a station down move none of it, choose.ts)
  "pick": BY_PAGE("pick.set, pick.save, pick.like, pick.forget"),
  "joinable": BY_PAGE("station.join: the stations of the account's workspaces, one joining another"),
  "memberships": READ_ONCE("views/memberships.ts readSoon, and again by station.join"),
  "workspaceWays": BY_PAGE("workspace.setWay: the rest is still.fail's relays, as /v1/me lists them"),
  "changelog news": UNTOLD("what this build got since the changelog was last shown: the device's build, said as a run starts (client.device), and the changelog shown (changelog.seen), on its own page"),
  "linkPreview page": CARD, "linkPreview pull": CARD, "filePeek picture": CARD, "filePeek text": CARD, "messagePeek": CARD,
};
/// Those reached by a cause of a test of their own, not of `CAUSES`: by name, the test.
const REACHED_ELSEWHERE: Record<string, string> = { live: "a working agent's stream" };

test("every way the app asks a topic has a change weighed, or says why it has none", async () => {
  const reached = new Map<string, string[]>();
  for (const { cause, sent } of await causesSent()) for (const name of sent.keys()) reached.set(name, [...(reached.get(name) ?? []), cause]);
  for (const [name, test] of Object.entries(REACHED_ELSEWHERE)) reached.set(name, [...(reached.get(name) ?? []), test]);
  const faults: string[] = [];
  for (const name of Object.keys(ASKED)) {
    const by = reached.get(name);
    if (by !== undefined && STILL[name] !== undefined) faults.push(`${name}: reached by ${by.join(", ")}, and STILL says ${STILL[name]}: bring it out of STILL`);
    if (by === undefined && STILL[name] === undefined) faults.push(`${name}: no cause sends it a message: make one that changes what it shows (CAUSES, real-size-asked.ts), or list it in STILL with why its value does not change while a page shows it`);
  }
  for (const name of [...Object.keys(STILL), ...Object.keys(REACHED_ELSEWHERE)]) if (!(name in ASKED)) faults.push(`${name}: in STILL or REACHED_ELSEWHERE but not asked`);
  if (print || faults.length > 0) {
    const lines = ["Each way the app asks a topic, the causes that reach it, or why none does:"];
    for (const name of Object.keys(ASKED)) lines.push(`    ${name.padEnd(32)} ${reached.get(name)?.join(", ") ?? `STILL: ${STILL[name] ?? "(none)"}`}`);
    console.log(lines.join("\n"));
  }
  assert.deepEqual(faults, []);
});

// ── a working agent's stream ──
//
// While an agent works in an open chat, the chat's activity line (apps/mbui src/sfpages/chat_rows.mbt `activity_row`)
// holds its agent's `live` and reads `activity.now` of it, nothing else. What the agent's stream brings is told here
// as its station tells it (station/src/sessions/live.ts `LiveMessage`) and taken as the core takes it (station/sync.ts
// `#onLive`, station/topics.ts `#live`, the store, output.ts): on the real-size agent's state (real-size.ts `liveOf`),
// a turn of twenty events: a step's words growing (a call's input, its `start` told again), steps ended and their
// transcript entries come (`timeline` one entry longer), the rate changing, its work told whole. Each message at most
// `DELTA_BAR_KB`, and an event that leaves the line as it was sends nothing.

/// A turn of a working agent's stream after `live` (as `liveOf` makes it, its transcript `live.timeline`), each event
/// named by what it is.
function turnOf(live: J, at: (n: number) => string): [string, J][] {
  const from = live.timeline.length;
  const used = (k: number) => ({ ...live.usage, modelCalls: live.usage.modelCalls + k, outputTokens: live.usage.outputTokens + 280 * k, contextTokens: live.usage.contextTokens + 900 * k });
  const entry = (k: number, e: J): J => ({ type: "timeline", start: from + k, entries: [{ at: at(k), ...e }], usage: used(k + 1) });
  const step = (event: J): J => ({ type: "step", event });
  const rate = (n: number): J => ({ type: "rate", tokensPerSecond: n });
  const command = "pnpm exec tsgo --noEmit && TOPIC_BYTES_PRINT=1 node --test test/topic-bytes.test.ts";
  const call = (n: number) => JSON.stringify({ command: command.slice(0, n), description: "Type-check, then weigh what each topic sends" });
  return [
    ["step start (text)", step({ kind: "start", id: "s-2", step: "text", input: "" })],
    ["rate", rate(41)],
    ["rate", rate(44)],
    ["step end", step({ kind: "end", id: "s-2" })],
    ["rate", rate(0)],
    ["timeline +1", entry(0, { kind: "assistant", text: "先跑类型检查，再看 live 在一轮里发了多少。" })],
    ["step start (call)", step({ kind: "start", id: "s-3", step: "tool", tool: "Bash", input: "" })],
    ["step words", step({ kind: "start", id: "s-3", step: "tool", tool: "Bash", input: call(20) })],
    ["step words", step({ kind: "start", id: "s-3", step: "tool", tool: "Bash", input: call(50) })],
    ["step words", step({ kind: "start", id: "s-3", step: "tool", tool: "Bash", input: call(command.length) })],
    ["step end", step({ kind: "end", id: "s-3" })],
    ["timeline +1", entry(1, { kind: "tool_call", tool: "Bash", callId: "call-turn-1", text: call(command.length) })],
    ["work", { type: "work", tasks: live.tasks.map((t: J) => ({ ...t, elapsedMs: t.elapsedMs + 9_000 })), plan: live.plan }],
    ["timeline +1", entry(2, { kind: "tool_result", tool: "Bash", callId: "call-turn-1", ok: true, text: "✔ 9 tests passed (41.2s)" })],
    ["step start (thinking)", step({ kind: "start", id: "s-4", step: "thinking", input: "" })],
    ["rate", rate(52)],
    ["rate", rate(55)],
    ["step end", step({ kind: "end", id: "s-4" })],
    ["rate", rate(0)],
    ["timeline +1", entry(3, { kind: "thinking", text: "live 只剩下一行要发：这一行没变的事件什么也不发。" })],
  ];
}

test("what a working agent's stream sends its chat's activity line holds to the change's bar, and nothing where the line stays", async () => {
  const answers = base();
  answers["GET /chats"] = [{ id: "7", thread: 7, session: "k1", title: "部署", agents: [{ key: "k1", process: "running" }], lastActiveAt: 1 }];
  const { host, core, push } = await started(answers);
  try {
    const topic = { topic: "live", station: "ws/st", key: "k1" };
    const ui = core.connect();
    // (as the app holds it: keyed, sfbase's source.mbt)
    core.receive(ui, { kind: "subscribe", id: 1, subscribe: topic, keyed: true });
    await host.settle();
    // The agent as the real-size rig has it at work, told as its stream opens.
    const now = host.nowMs();
    const live = liveOf(now);
    push("live", { key: "k1", type: "timeline", start: 0, entries: live.timeline, usage: live.usage });
    push("live", { key: "k1", type: "steps", steps: [], phase: { phase: "working", elapsedMs: 40_000 } });
    push("live", { key: "k1", type: "work", tasks: live.tasks, plan: live.plan });
    await host.time.pass(100);
    host.takeEmitted();
    // What a chat opened now is sent whole.
    core.receive(ui, { kind: "subscribe", id: 2, subscribe: topic, keyed: true });
    await host.time.pass(100);
    const whole = host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === 2 && "value" in m);
    core.receive(ui, { kind: "unsubscribe", id: 2, unsubscribe: true });
    await host.time.pass(100);
    host.takeEmitted();
    const activity = () => (core.inner.store.value(topic as Topic) as J)?.ok?.activity;
    const rows: { name: string; bytes: number; bar: number; value?: unknown }[] = [];
    const faults: string[] = [];
    let all = 0;
    let changed = 0;
    const turn = turnOf(live, (k) => new Date(now + (k + 1) * 3000).toISOString());
    for (const [i, [name, message]] of turn.entries()) {
      const was = activity();
      push("live", { key: "k1", ...message });
      await host.time.pass(100);
      const sent = host.takeEmitted().map(([, m]) => m as J).filter((m) => m.id === 1);
      const n = sent.reduce((a, m) => a + bytes(m), 0);
      all += n;
      const same = equal(was, activity());
      if (!same) changed++;
      rows.push({ name: `${String(i + 1).padStart(2)} ${name}${same ? "" : " (the line changes)"}`, bytes: n, bar: DELTA_BAR_KB, value: sent[0]?.value ?? sent[0]?.delta });
      if (same && sent.length > 0) faults.push(`${i + 1} ${name}: the line stays, and ${n} B are sent: ${JSON.stringify(sent).slice(0, 160)}`);
      if (!same && sent.length !== 1) faults.push(`${i + 1} ${name}: the line changes, and ${sent.length} messages are sent`);
      for (const m of sent) if (bytes(m) > DELTA_BAR_KB * 1024) faults.push(`${i + 1} ${name}: ${kb(bytes(m)).toFixed(1)} KB, over the bar of ${DELTA_BAR_KB} KB`);
    }
    if (whole === undefined || bytes(whole) > BAR_KB * 1024) faults.push(`live whole: ${whole === undefined ? "none came" : `${kb(bytes(whole)).toFixed(1)} KB`}`);
    // (the turn moves the line: what it changes to comes)
    if (changed < 8) faults.push(`the line changed ${changed} times in the turn`);
    if (print || faults.length > 0) {
      console.log(`A working agent's stream to its chat's activity line (\`live\`): sent whole ${whole === undefined ? "-" : bytes(whole)} B; a turn of ${turn.length} events, ${all} B in all, the line changing ${changed} times`);
      for (const r of rows) console.log(`  ${r.bytes > r.bar * 1024 ? "!" : " "} ${r.name.padEnd(48)} ${String(r.bytes).padStart(9)} B${r.bytes > 0 && print ? `  ${JSON.stringify(r.value).slice(0, 140)}` : ""}`);
    }
    assert.deepEqual(faults, []);
  } finally {
    core.close();
  }
});

// ── a page more ──

test("a page more of the changelog comes as what changed from the page held, within the bar", async () => {
  const { t, first } = await held();
  try {
    // (the id `held` subscribed it by, among those held with the chat's last page)
    const at = Object.keys(ASKED).filter((name) => !LONG.has(name)).indexOf("changelog") + 1;
    const more = { ...ASKED.changelog!, limit: 2 * CHANGELOG_PAGE };
    t.host.takeEmitted();
    t.store.subscribe(1, 9_000, parseTopic(more)!, true, at);
    await t.host.time.pass(100);
    const m = t.host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === 9_000 && !("waiting" in m));
    const whole = first.get("changelog")!;
    const rows = [{ name: "changelog, a page more", bytes: m === undefined ? 0 : bytes(m), bar: BAR_KB }];
    const faults: string[] = [];
    if (m === undefined || !("delta" in m) || m.from !== at) faults.push(`a page more: ${JSON.stringify(m)?.slice(0, 120)}`);
    else {
      // (what it holds then: the tab's first two pages)
      const holds = applyKeyed(whole.value, m.delta) as J;
      const tab = holds.tabs.find((x: J) => x.days.length > 0);
      const shown = tab.days.flatMap((d: J) => d.entries).length;
      if (shown !== 2 * CHANGELOG_PAGE) faults.push(`a page more holds ${shown} changes`);
      // (the new changes alone, put by their days' and their own keys: not the tab's days set whole)
      if ((m.delta as J[]).some((op) => "set" in op && op.path[0] === "tabs")) faults.push("a page more sets the tabs whole");
      if (bytes(m) > BAR_KB * 1024) faults.push(`a page more: ${kb(bytes(m)).toFixed(1)} KB, over the bar of ${BAR_KB} KB`);
    }
    if (print || faults.length > 0) console.log(table(`What a page more of the changelog is sent, from the page held (bar ${BAR_KB} KB; the page whole ${bytes(whole)} B):`, rows));
    // (each of its ops: what it does, where, what it weighs)
    if (print && m !== undefined && Array.isArray(m.delta)) for (const op of m.delta as J[]) console.log(`        ${["put", "patch", "drop", "move", "set", "append", "remove"].find((k) => k in op)} ${JSON.stringify(op.path)} ${JSON.stringify(op.patch ?? op.put?.day ?? op.put?.version ?? "")} ${bytes(op)} B`);
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
const OVER_AGAIN: Record<string, number> = {};

/// What `m`, a first message, is: `same`, `kept` (what changed from what was kept), `value` (whole), else `?`.
const said = (m: J): string => ("same" in m ? "same" : "kept" in m ? "kept" : "value" in m ? "value" : "?");

test("what a topic the app keeps is sent as it is asked again after something changed holds to its bar", async () => {
  // (each measured where `held` holds it: the chat at its last page, and with its six pages loaded)
  let id = 10_000;
  const measured = new Map<string, number>();
  const rows: { name: string; whole: number; now: number; how: string }[] = [];
  const faults: string[] = [];
  for (const long of [false, true]) {
    const h = await held(long);
    const { t } = h;
    try {
      const names = Object.keys(ASKED).filter((name) => KEPT.has(ASKED[name]!.topic) && LONG.has(name) === long);
      const causes: [string, () => void, number][] = ["host", "quota", "message", "minute"].map((n) => [n, () => CAUSES[n]!.run(h), CAUSES[n]!.ms ?? 1000]);
      /// The first message to `id` once `f` was done.
      const firstTo = async (id: number, f: () => void): Promise<J> => {
        t.host.takeEmitted();
        f();
        await t.host.time.pass(100);
        return t.host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === id && !("waiting" in m));
      };
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
    } finally {
      t.store.runner.shutdown();
    }
  }
  faults.push(...judge(measured, DELTA_BAR_KB, OVER_AGAIN, "OVER_AGAIN"));
  if (print || faults.length > 0) {
    const lines = [`What a topic kept is sent asked again, its first message (bar ${DELTA_BAR_KB} KB), beside its value whole:`];
    for (const r of rows) {
      const over = r.now > DELTA_BAR_KB * 1024;
      lines.push(`  ${over ? "!" : " "} ${r.name.padEnd(36)} ${r.how.padEnd(6)} ${String(r.now).padStart(9)} B ${kb(r.now).toFixed(1).padStart(7)} KB   whole ${String(r.whole).padStart(9)} B ${kb(r.whole).toFixed(1).padStart(7)} KB`);
    }
    console.log(lines.join("\n"));
  }
  assert.deepEqual(faults, []);
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

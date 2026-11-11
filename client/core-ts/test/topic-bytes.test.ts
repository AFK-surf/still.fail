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
// What is weighed is weighed full: every list and map a value's shape declares holds something in the fixture, or is
// in `EMPTY` with why (a topic weighed empty passed at tens of bytes: `changelog`, 2026-11-11, ~190 KB on a phone).
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
import type { Ty } from "../src/conform.ts";
import { shapeOf } from "../src/present.ts";
import { parseTopic, TOPICS, type Topic } from "../src/protocol.ts";
import { SHAPES } from "../src/shapes/schema.ts";
import { isObject } from "../src/util.ts";
import { OUTLINE_FOUND, OUTLINE_ROWS } from "../src/things.ts";
import { CHAT, CHAT_MESSAGES, DRIVE, JOB, JOB_LOG_LINES, OPENS, OTHER_WORKSPACE, OUTLINED, OUTLINED_ENTRIES, PEEKS, SEARCH, UP, VAULT_ITEM, devicesSaid, fixture, hostReading, messageAdded, more, outlinedEdit, outlinedLog, outlinedSaid, outlinedWorking, quotaChanged, records, screensOf, transcriptOf } from "./real-size.ts";
import { applyKeyed } from "../src/collections.ts";
import type { Inner } from "../src/core.ts";
import type { Owner } from "../src/core/routing.ts";
import type { Data } from "../src/data.ts";
import { Browsing } from "../src/drive-browse.ts";
import { driveCount, kindOf } from "../src/drive.ts";
import { Notices } from "../src/notices.ts";
import { screensView } from "../src/screens.ts";
import type { Store } from "../src/store.ts";
import type { FakeHost } from "../src/testing.ts";
import { lockView } from "../src/views/lock.ts";
import { joinable, memberships } from "../src/views/memberships.ts";
import { itemsView, usesView, vaultsView } from "../src/views/vault.ts";
import type { Views } from "../src/views/views.ts";
import { waysView } from "../src/views/ways.ts";
import * as xshare from "../src/views/xshare.ts";
import { Workspaces } from "../src/workspace.ts";
import { hostOf, overview, setup } from "./views-rig.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

/// What a value sent whole may weigh, in KB.
const BAR_KB = 32;
/// What one message may weigh as something changes, in KB.
const DELTA_BAR_KB = 4;

/// Each way the app asks a topic (apps/mbui/src: `.topic("name"`, sfbase/bars.mbt `place_reads`; a chat's and its
/// jobs' `compact`, sfbase/source.mbt `core_topic_params`), by a name of its own. The chat is held as it opens, its last
/// page read (`OPENS`), and again as `… six pages`, its six pages loaded (`LONG`).
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
  "chat six pages": { topic: "chat", station, session: key },
  "chat compact six pages": { topic: "chat", station, session: key, compact: true },
  "chatJobs compact": { topic: "chatJobs", station, session: key, compact: true },
  "chatJobs summary": { topic: "chatJobs", station, session: key, compact: true, summary: true },
  "history": { topic: "history", station, key },
  "agentCard": { topic: "agentCard", station, key },
  "usage": { topic: "usage", scope: "ws", days: 7 },
  "fleet": { topic: "fleet", scope: "ws" },
  "railCard": { topic: "railCard", scope: "ws", place: "chats" },
  "railCard usage": { topic: "railCard", scope: "ws", place: "usage" },
  "resources": { topic: "resources", scope: "ws", station },
  "workspace": { topic: "workspace", workspace: "ws" },
  "workspaceMarks": { topic: "workspaceMarks", workspace: "ws" },
  "longJobs": { topic: "longJobs", scope: "ws" },
  "archive": { topic: "archive", scope: "ws", limit: 60 },
  "search": { topic: "search", scope: "ws", query: SEARCH },
  "chatSearch": { topic: "chatSearch", scope: "ws", query: SEARCH, station, limit: 8, elsewhere: true, exclude: key },
  "changelog": { topic: "changelog" },
  "changelog news": { topic: "changelog", news: true },
  "devices": { topic: "devices", workspace: "ws" },
  // (of the chat of four weeks held whole: what it is made of is all of a chat held)
  "chatOutline": { topic: "chatOutline", station: OUTLINED.station, thread: OUTLINED.thread },
  // (the chat's agent's activity row, sfpages/chat_rows.mbt; its live state as it runs, 160 entries of its timeline)
  "live": { topic: "live", station, key },
  // (the chat's dev server's log: its last line, a job's row; the sheet's 300 lines, sfapp/sheets.mbt job_output_most;
  // the desktop's 400, sfdesk/jobs.mbt job_output_lines: each as long as the station reads, 64 KB at most)
  "jobLog line": { topic: "jobLog", station, job: JOB, lines: JOB_LOG_LINES[0] },
  "jobLog 300": { topic: "jobLog", station, job: JOB, lines: JOB_LOG_LINES[1] },
  "jobLog 400": { topic: "jobLog", station, job: JOB, lines: JOB_LOG_LINES[2] },
  // (a folder of 420, sfbase/drive_viewer.mbt drive_params; and as a place shows it: the phone's list, sfbase/browse.mbt,
  // and a desktop page's columns, sfdesk/drive.mbt, where names may be changed)
  "drive": { topic: "drive", ...DRIVE },
  "driveBrowse phone": { topic: "driveBrowse", owner: "page", place: "phone", view: "list", ...DRIVE },
  "driveBrowse columns": { topic: "driveBrowse", owner: "page", place: "p1", view: "columns", ...DRIVE, write: true },
  // (the notices page, sfpages/notifications.mbt: as many as are kept, notices.ts KEEP)
  "notices": { topic: "notices", workspace: "ws" },
  // (安全模式, sfpages/security.mbt: the twelve members' devices, the five stations)
  "lock": { topic: "lock", workspace: "ws" },
  // (the vault, sfpages/vault.mbt and vault_item.mbt: 36 secrets, the uses of the most used one)
  "vaults": { topic: "vaults", workspace: "ws" },
  "vaultItems": { topic: "vaultItems", workspace: "ws", vault: "plain" },
  "vaultUses": { topic: "vaultUses", workspace: "ws", vault: "plain", item: VAULT_ITEM },
  // (adding a station, sfapp/settings/station_add.mbt; a station's workspaces, sfpages/station_page.mbt)
  "joinable": { topic: "joinable", workspace: "ws" },
  "memberships": { topic: "memberships", station },
  // (a station's screens, sfpages/station_page.mbt; its network, sfpages/station_facts.mbt; the workspace's ways,
  // sfpages/workspace_page.mbt)
  "screens": { topic: "screens", station },
  "stationNet": { topic: "stationNet", station },
  "workspaceWays": { topic: "workspaceWays", workspace: "ws" },
  // (what the chat and others wrote each other, sfdesk/letters.mbt; its things, sfpages/things.mbt, and looked in)
  "chatLetters": { topic: "chatLetters", station, thread: CHAT.thread },
  "chatThings": { topic: "chatThings", station, thread: CHAT.thread },
  "chatThings q": { topic: "chatThings", station, thread: CHAT.thread, q: "png" },
  // Those of one thing whose size nothing in the core bounds, at the most their station sends: a station's presets
  // (sfpages/presets.mbt); a link's card (sfpages/peeks.mbt), a page's with its icon and picture inline, a pull
  // request's; a file a message names, a picture's peek and a text's; a message of another chat a link names; a job
  // (sfdesk/service_tab.mbt), the soak with all the notices its station shows.
  "presets": { topic: "presets", station },
  "linkPreview page": { topic: "linkPreview", station, url: PEEKS.page },
  "linkPreview pull": { topic: "linkPreview", station, url: PEEKS.pull },
  "filePeek picture": { topic: "filePeek", station, key, path: PEEKS.picture },
  "filePeek text": { topic: "filePeek", station, key, path: PEEKS.text },
  "messagePeek": { topic: "messagePeek", station, thread: PEEKS.message.thread, seq: PEEKS.message.seq },
  "job": { topic: "job", station, id: "job-maple-3" },
};

/// Those measured with the chat's six pages loaded (`CHAT_MESSAGES`), the rest with its last alone.
const LONG = new Set(["chat six pages", "chat compact six pages"]);

/// Those over `BAR_KB` now, by the name `ASKED` gives them: what each weighs, KB rounded up to a multiple of 8.
const OVER: Record<string, number> = {
  "filePeek picture": 344,
  "chat six pages": 264,
  "chat compact six pages": 264,
  "linkPreview page": 224,
  "jobLog 400": 176,
  "jobLog 300": 128,
  "vaultUses": 128,
  "usage": 112,
  "chats mine": 80,
  "chats": 72,
  "drive": 72,
  "profiles": 64,
  "history": 56,
  "chat": 56,
  "chat compact": 56,
  "live": 40,
  "chatLetters": 40,
};

/// Those over `DELTA_BAR_KB` as something changes, by `<name>/<cause>`: the heaviest message, KB as in `OVER`.
const OVER_DELTA: Record<string, number> = {};

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
const CHANGELOG = "its feed is another change's (changelog-pages)";
/// A chat's paths EMPTY lists, as each way of asking it has them: the chat at its last page (`older`), compact.
const chatEmpty = (older: boolean, compact: boolean): Record<string, string> => ({
  // (QuotaWindow's `time`: present.ts `times` makes a quota's windows anew, never into each; `refills` says `resetsAt`)
  "agents[].profile.quota.windows[].time": NEVER, "agents[].account.quota.windows[].time": NEVER,
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
    // (offers: a station with no chats of its own; formerly: the stations it took the place of, none lost)
    "overview.copies.offers": STATE, "overview.copies.formerly": NONE,
  },
  "stationPart profiles": { "[].modelsSaving": SAVING, "[].quota.windows[].time": NEVER, "[].decisionModels": NONE, "[].workspaces": NONE },
  // (a sign-in under way: Willow's)
  "stationPart logins": { "(whole)": STATE },
  // (foundMarks: a search's alone, views/search.ts foundChat)
  "chats": { "days[].items[].foundMarks": NEVER, "note.failing": ERROR },
  "chats mine": { "days[].items[].foundMarks": NEVER, "note.failing": ERROR },
  // (profiles.ts gives its note no failing)
  "profiles": { "wait.failing": NEVER },
  "connects": { "wait.failing": ERROR },
  "connects mine": { "wait.failing": ERROR },
  // (a single-session connect's session, and the one weighed is many sessions')
  "connect": { "bound.efforts": STATE, "bound.time": STATE, "bound.watch.names": STATE },
  // (a new chat's pick names no account's allowance, choose.ts `#now` quiet; the model it takes with nothing chosen,
  // Fable, runs on one runtime; borrow: a model only another station has, picked)
  "newChat": { "pick.account.profile.quota.windows": ASKED_SO, "pick.runtimes": STATE, "pick.borrow.lines": STATE },
  "pick": { "account.profile.quota.windows": ASKED_SO, runtimes: STATE, "borrow.lines": STATE },
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
  "changelog": { tabs: CHANGELOG, "news.entries": CHANGELOG },
  "changelog news": { tabs: CHANGELOG, "news.entries": CHANGELOG },
  // (a rig's devices', a station that only runs tasks: the workspace has none)
  "devices": { "devices[].requests": NONE },
  // (names chosen, a tree's folders open, columns widened by hand)
  "driveBrowse phone": { "chosen.names": STATE, open: STATE, widths: STATE },
  "driveBrowse columns": { "chosen.names": STATE, open: STATE, widths: STATE },
  // (this device being approved face to face)
  "lock": { "me.pair.approvers": STATE },
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
const LOADING: Record<string, string> = { changelog: CHANGELOG };

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

/// The core's parts the pages' own topics are made of (core.ts `Inner`), as far as those read them here: the account
/// and its workspaces, what the device holds, its links to the stations all up.
function innerOf(parts: { host: FakeHost; store: Store; data: Data; views?: Views }): Inner {
  const workspaces = new Workspaces(parts.host, parts.store.runner);
  workspaces.setOwners(new Map([["ws", "s1"], [OTHER_WORKSPACE.id, "s1"], ["ws-friends", "s1"]]));
  return {
    host: parts.host, store: parts.store, runner: parts.store.runner, data: parts.data, views: parts.views, workspaces,
    accounts: { list: () => [{ sub: "s1", email: "me@x.com", name: "左子健" }] },
    stations: { seen: { read: () => {} }, link: () => ({ state: { state: "online" } }) },
    provider: { kind: "stillfail" }, adb: { personal: () => ({ standing: () => "member" }) }, meshNow: () => null,
  } as unknown as Inner;
}

/// Owners of the topics no view makes, as core.ts plugs them in: a drive's places (views/browse.ts), the notices
/// (attention.ts), the lock (views/lock.ts), the vault (views/vault.ts), stations to join and what a station is in
/// (views/memberships.ts), a station's screens (station/topics.ts, its `GET /screens` as `screens` gives it).
function pageOwners(inner: Inner, notices: Notices, screens: () => J): Owner[] {
  const browsing = new Browsing({
    prefs: () => inner.data.shared({ topic: "prefs" }),
    setPrefs: () => {},
    entries: (station, root, path) => {
      const folder = inner.data.shared({ topic: "drive", station, root, path }) as J;
      return isObject(folder) ? (folder.entries as J[]).map((e) => ({ name: e.name, dir: e.dir === true, size: e.size ?? 0, mtime: e.mtime ?? 0, kind: e.dir ? "folder" : kindOf(e.name) })) : null;
    },
    stations: (ws) => ((inner.data.shared({ topic: "workspace", workspace: ws }) as J)?.stations ?? []).flatMap((s: J) => {
      const station = `${ws}/${s.id}`;
      const drive = (inner.data.shared({ topic: "overview", station }) as J)?.drive;
      return isObject(drive) ? [{ station, name: s.name ?? s.id, home: typeof drive.home === "string" ? drive.home : null }] : [];
    }),
    now: () => inner.host.nowMs(), newId: () => "b0", invalid: (what) => new Error(what), countText: driveCount,
    changed: (pick) => inner.store.invalidateAll((topic) => topic.topic === "driveBrowse" && pick(topic)),
  });
  const of = (names: string[], compute: (topic: Topic) => unknown, start?: (topic: Topic) => void): Owner => ({ owns: (topic: Topic) => names.includes(topic.topic), start, compute: (topic: Topic) => ({ ok: compute(topic) }) });
  return [
    of(["driveBrowse"], (topic) => browsing.view(topic), (topic) => browsing.started(String(topic.place))),
    of(["notices"], (topic) => notices.value(typeof topic.workspace === "string" ? topic.workspace : null)),
    of(["lock"], (topic) => lockView(inner, String(topic.workspace))),
    of(["vaults"], (topic) => vaultsView(inner, String(topic.workspace))),
    of(["vaultItems"], (topic) => itemsView(inner, String(topic.workspace), String(topic.vault))),
    of(["vaultUses"], (topic) => usesView(inner, String(topic.workspace), String(topic.vault), String(topic.item))),
    of(["joinable"], (topic) => joinable(inner, String(topic.workspace))),
    of(["memberships"], (topic) => memberships(inner, String(topic.station))),
    of(["screens"], (topic) => screensView(inner, String(topic.station), topic.station === CHAT.station ? screens() : { screens: [], outdated: false }, true)),
  ];
}

/// The notices the workspace's chats' rows bring as each up station tells them one message on from where they were
/// (a card come where it waits on one): what a device has heard of them by then, the latest `KEEP`.
function noticesHeard(notices: Notices, rows: [string, J[]][]): void {
  for (const [station, list] of rows) {
    notices.changed(station, list.map((r) => ({ id: r.id, before: { ...r, last: { ...r.last, seq: r.last.seq - 1 }, card: undefined, decision: undefined }, after: r })), false);
  }
}

/// A rig with every view, a new chat's and a model's pickers, the changelog, the pages' own topics (`pageOwners`); the
/// real-size workspace set in it, the chat with its six pages loaded (`long`) or its last alone, the chat of four weeks
/// held whole, and every topic of `ASKED` measured so subscribed as the app subscribes (keyed), its messages to each by id.
async function held(long = false) {
  const chat = long ? CHAT_MESSAGES : OPENS;
  // (the workspace's devices as core.ts makes them: what each up station says, the rigs' none here)
  let devices: Devices | null = null;
  let notices: Notices | null = null;
  let screens: J = undefined;
  const inners = new WeakMap<Data, Inner>();
  const innerFor = (parts: { host: FakeHost; store: Store; data: Data }) => {
    if (!inners.has(parts.data)) inners.set(parts.data, innerOf(parts));
    return inners.get(parts.data)!;
  };
  const t = setup({
    all: true,
    // (the account's workspaces and how their stations are reached, as core.ts gives the views them of its `/v1/me`)
    env: (parts) => ({
      places: () => xshare.places(innerFor(parts)),
      ways: (ws) => {
        const me = parts.data.record("me", "s1") as J;
        const w = (me?.workspaces ?? []).find((x: J) => x.id === ws);
        return me === undefined ? undefined : waysView(me.relay_urls, me.relay_names, w?.relays ?? [], w?.ways_off ?? []);
      },
    }),
    owners: ({ host, store, data, views }) => {
      const inner = innerFor({ host, store, data });
      (inner as J).views = views;
      notices = new Notices({
        workspaces: inner.workspaces, now: () => host.nowMs(), emailOf: (ws) => (ws === "ws" ? "me@x.com" : null),
        members: (ws) => ((data.shared({ topic: "workspace", workspace: ws }) as J)?.members ?? []),
        slackUsers: (station) => ((data.shared({ topic: "overview", station }) as J)?.slackUsers ?? []),
      });
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
        ...pageOwners(inner, notices, () => screens),
      ];
    },
  });
  const base = t.host.nowMs();
  screens = screensOf(base);
  for (const [table, k, value] of records(base)) t.data.put(table, k, value);
  const names = Object.keys(ASKED).filter((name) => LONG.has(name) === long);
  names.forEach((name, i) => t.store.subscribe(1, i + 1, topicOf(name), true));
  // Set as the topics are watched, and again once the views watch what they found they are made of (a value set of a
  // topic nothing watches is not kept: the core's station topics read what is watched).
  for (let round = 0; round < 2; round++) {
    for (const [topic, value] of [...fixture(base, chat), ...more(base)]) t.set(topic, value);
    t.data.putItems("entry", OUTLINED.station, String(OUTLINED.thread), outlinedLog(base));
    for (const key of CHAT.keys) t.data.putItems("transcript", CHAT.station, key, key === CHAT.keys[0] ? transcriptOf(base) : []);
    for (const [i, station] of UP.entries()) devices!.heard(station, "devices", devicesSaid(base, i));
    await t.host.time.pass(100);
  }
  noticesHeard(notices!, UP.map((station) => [station, (t.data.shared({ topic: "chatRows", station }) as J[]) ?? []]));
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
  return { t, base, chat, first, during };
}

/// What each of `ASKED` is sent whole as it subscribes: the chat's six pages' with the rest.
async function firstOfAll(): Promise<Map<string, J>> {
  const all = new Map<string, J>();
  for (const long of [false, true]) {
    const { t, first } = await held(long);
    try {
      for (const [name, m] of first) all.set(name, m);
    } finally {
      t.store.runner.shutdown();
    }
  }
  return all;
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

/// What goes out to each of `ASKED` as the workspace changes, by cause: the chat's six pages' with the rest.
async function causesOfAll(): Promise<[string, Map<string, J[]>][]> {
  const causes: [string, Map<string, J[]>][] = [];
  for (const long of [false, true]) {
    const { t, base, chat, during } = await held(long);
    try {
      const st = 0;
      causes.push(["host", await during(() => t.set(hostOf(station), hostReading(t.host.nowMs(), st, 0.83)), 1000)]);
      causes.push(["quota", await during(() => t.set(overview(station), quotaChanged(base, t.host.nowMs(), st)), 1000)]);
      causes.push(["message", await during(() => {
        for (const [topic, value] of messageAdded(base, t.host.nowMs(), chat)) t.set(topic, value);
      }, 1000)]);
      if (!long) {
        // The chat of four weeks: its agent writing on (twice), a person's words edited, a person saying something.
        const log = (item: [number, unknown]) => t.data.putItems("entry", OUTLINED.station, String(OUTLINED.thread), [item]);
        causes.push(["agent", await during(() => {
          log(outlinedWorking(base, 1));
          log(outlinedWorking(base, 2));
        }, 1000)]);
        causes.push(["edit", await during(() => log(outlinedEdit(base, t.host.nowMs())), 1000)]);
        causes.push(["said", await during(() => log(outlinedSaid(base, t.host.nowMs())), 1000)]);
      }
      causes.push(["minute", await during(() => {}, 60_000)]);
    } finally {
      t.store.runner.shutdown();
    }
  }
  return causes;
}

test("what each topic the app asks is sent as the workspace changes holds to its bar", async () => {
  const causes = await causesOfAll();
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
    const { t, base, chat } = await held(long);
    try {
      const names = Object.keys(ASKED).filter((name) => KEPT.has(ASKED[name]!.topic) && LONG.has(name) === long);
      const st = 0;
      const causes: [string, () => void, number][] = [
        ["host", () => t.set(hostOf(station), hostReading(t.host.nowMs(), st, 0.83)), 1000],
        ["quota", () => t.set(overview(station), quotaChanged(base, t.host.nowMs(), st)), 1000],
        ["message", () => {
          for (const [topic, value] of messageAdded(base, t.host.nowMs(), chat)) t.set(topic, value);
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

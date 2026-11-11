// Every way the app asks each topic, and a rig holding the workspace of real size (real-size.ts) as the app holds it:
// what topic-bytes.test.ts weighs, and what real-size-app.test.ts writes for the app's sweep of its screens at that
// size (apps/mbui/src/sfrealsize).
import { Effect } from "effect";
import { Changelog } from "../src/changelog.ts";
import { Choose } from "../src/choose.ts";
import { Devices } from "../src/devices.ts";
import type { PersonalLock } from "../src/personal-lock.ts";
import type { Rigs } from "../src/rigs.ts";
import { parseTopic, type Topic } from "../src/protocol.ts";
import { isObject } from "../src/util.ts";
import { CHANGELOG_DEVICE, CHANGELOG_SEEN, CHAT, CHAT_MESSAGES, DRIVE, JOB, JOB_LOG_LINES, OPENS, OTHER_WORKSPACE, OUTLINED, PEEKS, SEARCH, UP, VAULT_ITEM, changelogFeed, devicesSaid, fixture, more, outlinedLog, records, screensOf, transcriptOf } from "./real-size.ts";
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
import { overview, setup } from "./views-rig.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// Each way the app asks a topic (apps/mbui/src: `.topic("name"`, sfbase/bars.mbt `place_reads`; a chat's and its
/// jobs' `compact`, sfbase/source.mbt `core_topic_params`), by a name of its own. The chat is held as it opens, its last
/// page read (`OPENS`), and again as `… six pages`, its six pages loaded (`LONG`).
const station = CHAT.station;
const key = CHAT.keys[0];
/// The changes of a tab the changelog's page asks first (apps/mbui/src/sfpages/changelog_node.mbt `changelog_page`).
export const CHANGELOG_PAGE = 30;
export const ASKED: Record<string, Record<string, unknown> & { topic: string }> = {
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
  // (the page's first page of the tab in view, none chosen; of another tab; and Home's card)
  "changelog": { topic: "changelog", limit: CHANGELOG_PAGE },
  "changelog station": { topic: "changelog", part: "station", limit: CHANGELOG_PAGE },
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
export const LONG = new Set(["chat six pages", "chat compact six pages"]);

// ── the workspace, held as a UI holds it ──

/// Where the second subscription of each topic's ids begin.
export const AGAIN = 1000;

export const topicOf = (name: string): Topic => {
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
export async function held(long = false) {
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
  let changelog: Changelog | null = null;
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
      changelog = new Changelog(host, store, data);
      return [
        new Choose({ store, data, now: () => host.nowMs(), agent: (s, k) => views.agent(s, k) }),
        changelog,
        { owns: (topic: Topic) => topic.topic === "devices", compute: (topic: Topic) => ({ ok: d.value(String(topic.workspace)) }) },
        ...pageOwners(inner, notices, () => screens),
      ];
    },
  });
  const base = t.host.nowMs();
  screens = screensOf(base);
  for (const [table, k, value] of records(base)) t.data.put(table, k, value);
  // (the changelog as read from the cloud, on a device of Android that saw a build before its own)
  t.data.put("changelog", "feed", changelogFeed(base));
  t.data.put("changelog", "seen", CHANGELOG_SEEN, false);
  changelog!.device(CHANGELOG_DEVICE);
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
export async function firstOfAll(): Promise<Map<string, J>> {
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

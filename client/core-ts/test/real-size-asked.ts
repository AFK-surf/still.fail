// Every way the app asks each topic, and a rig holding the workspace of real size (real-size.ts) as the app holds it:
// what topic-bytes.test.ts weighs, and what real-size-app.test.ts writes for the app's sweep of its screens at that
// size (apps/mbui/src/sfrealsize).
import { Effect } from "effect";
import { Changelog } from "../src/changelog.ts";
import { Choose } from "../src/choose.ts";
import { Devices } from "../src/devices.ts";
import type { PersonalLock } from "../src/personal-lock.ts";
import { pendingRow } from "../src/lock-pending.ts";
import type { Rigs } from "../src/rigs.ts";
import { parseTopic, type Topic } from "../src/protocol.ts";
import { isObject } from "../src/util.ts";
import {
  CHANGELOG_DEVICE, CHANGELOG_SEEN, CHAT, PEOPLE, CHAT_MESSAGES, DRIVE, LETTERS_COUNT, JOB, JOB_LOG_LINES, OPENS, OTHER_WORKSPACE, OUTLINED, PEEKS, SEARCH, UP, VAULT_ITEM, cardCame, changelogFeed, changelogReleased,
  chatArchived, chatRenamed, devicesAdded, devicesSaid, driveAdded, fixture, hostReading, jobLogOf, jobsMoved, lettersHeld, liveStepped, lockApproved, memberJoined, messageAdded, more,
  netOf, outlinedEdit, outlinedLog, outlinedSaid, outlinedWorking, overviewMoved, presetsChanged, quotaChanged, records, resourcesOf, screensMoved, screensOf, sessionMade, thingSaid, transcriptOf,
  usageRead, vaultAdded, vaultUsed, ownPendingOf, STATIONS,
} from "./real-size.ts";
import { logged } from "../src/log-lines.ts";
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
  // (its window told first, `WINDOWS`)
  "chats": { topic: "chats", scope: "ws", mine: false },
  "chats mine": { topic: "chats", scope: "ws", mine: true },
  // (a row pressed, held, swiped or pointed at: its chat's whole row, sfbase/rows.mbt whole_row; the chat's, its page's menu)
  "chatRow": { topic: "chatRow", station, session: key },
  "profiles": { topic: "profiles", scope: "ws" },
  // (an account's page on a station, sfpages/accounts.mbt: a Claude subscription of the chat's station lent to two more,
  // its allowance's resets of each kind; an account's page of all its stations by its key, settings/profile_new.mbt: the
  // ChatGPT one of the chat's station lent to three, its allowance the one read again, `quota`)
  "profile": { topic: "profile", scope: "ws", station, id: "claude-maple-0" },
  "profile key": { topic: "profile", scope: "ws", key: `sub:codex:${PEOPLE[0]!.email}` },
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
  "workspaceMarks": { topic: "workspaceMarks" },
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

/// The chats' lists' windows as the app first tells them (`chats.window`; apps/mbui sfbase/rows.mbt `first_window`): the
/// rows its room shows and a screen more, rounded up to ten, the same 30 on 小屏 (390×844, rows of 66) and on a wide
/// screen (1280×800, rows of 54); `WINDOW_STEP` more as one is scrolled near its foot (`window_step`: a screen of rows,
/// 20 at least).
export const WINDOWS: Record<string, number> = { "chats": 30, "chats mine": 30 };
export const WINDOW_STEP = 20;

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
  // (the person's own lock as the lock's page reads it: what is pending of it, as many as are kept)
  const personal = {
    standing: () => "member",
    chain: () => null,
    pendingShown: () => ownPendingOf(parts.host.nowMs()).map((item) => ({ item, row: pendingRow(item, STATIONS.map((s) => s.name)) })),
  };
  return {
    host: parts.host, store: parts.store, runner: parts.store.runner, data: parts.data, views: parts.views, workspaces,
    accounts: { list: () => [{ sub: "s1", email: "me@x.com", name: "左子健" }] },
    stations: { seen: { read: () => {} }, link: () => ({ state: { state: "online" } }) },
    provider: { kind: "stillfail" }, adb: { personal: () => personal }, meshNow: () => null,
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
// zz scratch: `cold`, a rig started anew on `host`, whose database holds the workspace already (a rig `held` made on it):
// what the device holds is not put again, nothing subscribed; `setLive` (on the returned value) puts what comes from
// the network as the sync would (the topics no table holds), for what a subscription made then watches.
export async function held(long = false, zz: { host?: FakeHost; cold?: boolean } = {}) {
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
    host: zz.host,
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
  const base = zz.cold ? zzBase : t.host.nowMs();
  zzBase = base;
  screens = screensOf(base);
  if (!zz.cold) {
    for (const [table, k, value] of records(base)) t.data.put(table, k, value);
    // (the changelog as read from the cloud, on a device of Android that saw a build before its own)
    t.data.put("changelog", "feed", changelogFeed(base));
    t.data.put("changelog", "seen", CHANGELOG_SEEN, false);
  }
  changelog!.device(CHANGELOG_DEVICE);
  const names = Object.keys(ASKED).filter((name) => LONG.has(name) === long);
  for (const name of names) if (WINDOWS[name] !== undefined) t.window(topicOf(name), WINDOWS[name]);
  if (zz.cold) {
    // (what comes of the network as the sync reads it: the topics no table holds, and each up station's devices)
    const setLive = () => {
      for (const [topic, value] of [...fixture(base, chat), ...more(base)]) if (!zzHolds(topic)) t.set(topic, value);
      for (const [i, station] of UP.entries()) devices!.heard(station, "devices", devicesSaid(base, i));
    };
    return { t, base, chat, first: new Map<string, J>(), during: async (_f: () => void, _ms: number) => new Map<string, J[]>(), notices: notices!, devices: devices!, screensAre: (_v: J) => {}, setLive, names };
  }
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
  /// The chat's station's screens as it tells them now (its `screens` event: sync.ts `#heldScreens`, what shows them
  /// made again).
  const screensAre = (value: J) => {
    screens = value;
    t.store.invalidate({ topic: "screens", station: CHAT.station });
  };
  return { t, base, chat, first, during, notices: notices!, devices: devices!, screensAre, setLive: () => {}, names };
}

export type Held = Awaited<ReturnType<typeof held>>;
// zz scratch
let zzBase = 0;
import { holds as zzHolds } from "../src/data.ts";

// ── what changes ──

/// A way the workspace changes while the app shows it, told the core as a core is told it: `run` does it on a rig `held`
/// made, as the sync would on what its station or the cloud said (what it sets, what the sync sets; where a change goes
/// through the core's own code, that code: log-lines.ts `logged`, notices.ts `changed`, devices.ts `heard`); then `ms`
/// of the clock pass (1 s). `long`: done again with the chat's six pages loaded. Each on a rig of its own, so what it
/// sends is what changed from the values sent whole (real-size-app.test.ts writes it for the app as that).
export type Cause = { run: (h: Held) => void; ms?: number; long?: true };
const job = (h: Held, j: J) => {
  // (as station/sync.ts `onJob` takes a station's `job` event)
  h.t.data.patchDetail(station, j.session, (detail) => {
    const i = detail.jobs.findIndex((x: J) => x.id === j.id);
    if (i >= 0) detail.jobs[i] = j;
  });
  h.t.data.putJob(station, j, j.state === "running" || (j.state === "exited" && j.port !== null));
};
export const CAUSES: Record<string, Cause> = {
  // A station's host reading (its load up), an allowance read again, a message in the chat, a minute passing.
  host: { run: ({ t }) => t.set(hostOf(station), hostReading(t.host.nowMs(), 0, 0.83)), long: true },
  quota: { run: ({ t, base }) => t.set(overview(station), quotaChanged(base, t.host.nowMs(), 0)), long: true },
  message: {
    run: ({ t, base, chat }) => {
      for (const [topic, value] of messageAdded(base, t.host.nowMs(), chat)) t.set(topic, value);
    },
    long: true,
  },
  minute: { run: () => {}, ms: 60_000, long: true },
  // The chat of four weeks: its agent writing on (twice), a person's words edited, a person saying something.
  agent: {
    run: ({ t, base }) => {
      t.data.putItems("entry", OUTLINED.station, String(OUTLINED.thread), [outlinedWorking(base, 1)]);
      t.data.putItems("entry", OUTLINED.station, String(OUTLINED.thread), [outlinedWorking(base, 2)]);
    },
  },
  edit: { run: ({ t, base }) => t.data.putItems("entry", OUTLINED.station, String(OUTLINED.thread), [outlinedEdit(base, t.host.nowMs())]) },
  said: { run: ({ t, base }) => t.data.putItems("entry", OUTLINED.station, String(OUTLINED.thread), [outlinedSaid(base, t.host.nowMs())]) },
  // The chat's dev server printing a line more: its log as the station's `job-log` event says it for each way the app
  // asks it, one line longer, its first gone where it was at its most, kept as station/sync.ts keeps it (its lines
  // numbered on from what was kept before: log-lines.ts `logged`).
  line: {
    run: ({ t, base }) => {
      for (const lines of JOB_LOG_LINES) {
        const now = jobLogOf(base, lines, 1);
        t.set({ topic: "jobLog", station, job: JOB, lines }, logged(jobLogOf(base, lines), now.text, now.outputAt));
      }
    },
  },
  // The chat's agent working on: a call more in its transcript (`live`), what the history page shows of it.
  step: { run: ({ t, base }) => t.set({ topic: "live", station, key }, liveStepped(base, t.host.nowMs())) },
  // The chat's agent's next message with a picture and a link (its things).
  thing: {
    run: ({ t, base, chat }) => {
      const told = messageAdded(base, t.host.nowMs(), chat, thingSaid(t.host.nowMs()));
      for (const [topic, value] of told) t.set(topic, value);
      // (and the chat's whole log, where its things are found: views.ts `#thingsMade`)
      t.set({ topic: "letters", station, thread: CHAT.thread }, lettersHeld(base, undefined, [(told[0]![1] as J).entries.at(-1)]));
    },
  },
  // A letter more from another chat.
  letter: { run: ({ t, base }) => t.set({ topic: "letters", station, thread: CHAT.thread }, lettersHeld(base, LETTERS_COUNT + 1)) },
  // A chat of the viewer's coming to wait on a card: its row, and the notice it makes (attention.ts `look`).
  card: {
    run: ({ t, base, notices }) => {
      const { rows, before, after } = cardCame(base, t.host.nowMs());
      t.set({ topic: "chatRows", station }, rows);
      notices.changed(station, [{ id: after.id, before, after }], false);
    },
  },
  // A chat archived by its station's archiving; one named by its agent with the words searched for.
  archived: {
    run: ({ t, base }) => {
      const { rows, archived } = chatArchived(base, t.host.nowMs());
      t.set({ topic: "chatRows", station }, rows);
      t.set({ topic: "archivedRows", station }, archived);
    },
  },
  renamed: { run: ({ t, base }) => t.set({ topic: "chatRows", station }, chatRenamed(base)) },
  // The chats' lists scrolled near their foot: each told a window a step more (the rows added go out, not the list).
  grown: {
    run: ({ t }) => {
      for (const [name, rows] of Object.entries(WINDOWS)) t.window(topicOf(name), rows + WINDOW_STEP);
    },
  },
  // Another station gone down.
  down: { run: ({ t }) => t.set({ topic: "link", station: "ws/willow" }, { state: "offline", message: "连不上这台 station：它可能关机了", last: "offline" }) },
  // Three of Maple's jobs told again (its `job` event): the chat's dev server crashed, its watch of CI ended red, the
  // soak a round more.
  job: { run: (h) => jobsMoved(h.base, h.t.host.nowMs()).forEach((j) => job(h, j)) },
  // Maple's usage read again (its `usage` event).
  usage: { run: ({ t, base }) => t.set({ topic: "stationUsage", station }, usageRead(base)) },
  // A sample more of what still.fail uses of Maple's machine, and of the device's connection to it.
  sample: {
    run: ({ t, base }) => {
      t.set({ topic: "stationResources", station }, resourcesOf(base, 0, 1));
      t.set({ topic: "net", station }, netOf(base, 1));
    },
  },
  // A file saved into the drive's folder shown (kept as it is while shown: sync.ts `driveWatch`).
  file: { run: ({ t, base }) => t.set({ topic: "drive", ...DRIVE }, driveAdded(base, t.host.nowMs())) },
  // Maple's screens told again: the agent's tab moved on, a person off it.
  screen: { run: ({ t, base, screensAre }) => screensAre(screensMoved(base, t.host.nowMs())) },
  // A member's phone attached to Maple (its `devices` event).
  device: { run: ({ t, base, devices }) => devices.heard(station, "devices", devicesAdded(base, t.host.nowMs())) },
  // A member's new device approved in the workspace's lock, as its stations keep it.
  approved: { run: ({ t, base }) => t.data.put("lock", "ws", lockApproved(base, t.host.nowMs())) },
  // The vault's plain library: an item used once more (its uses as Maple told them again), an item added.
  used: { run: ({ t, base }) => t.data.put("vault", "ws", vaultUsed(base, t.host.nowMs())) },
  item: { run: ({ t, base }) => t.data.put("vault", "ws", vaultAdded(base, t.host.nowMs())) },
  // A member more in the workspace, as the cloud lists it.
  member: { run: ({ t, base }) => t.set({ topic: "workspace", workspace: "ws" }, memberJoined(base)) },
  // A session more on Maple, a Slack thread's.
  session: {
    run: ({ t, base }) => {
      for (const [topic, value] of sessionMade(base, t.host.nowMs())) t.set(topic, value);
    },
  },
  // Maple's overview told again: an automatic decision made, Claude Code updating, the machine's login's allowance, a
  // sign-in begun, its archiving changed, its automatic decisions turned off.
  decided: { run: ({ t, base }) => t.set(overview(station), overviewMoved(base, t.host.nowMs(), "decided")) },
  updating: { run: ({ t, base }) => t.set(overview(station), overviewMoved(base, t.host.nowMs(), "updating")) },
  machine: { run: ({ t, base }) => t.set(overview(station), overviewMoved(base, t.host.nowMs(), "machine")) },
  login: { run: ({ t, base }) => t.set(overview(station), overviewMoved(base, t.host.nowMs(), "login")) },
  archiving: { run: ({ t, base }) => t.set(overview(station), overviewMoved(base, t.host.nowMs(), "archiving")) },
  off: { run: ({ t, base }) => t.set(overview(station), overviewMoved(base, t.host.nowMs(), "off")) },
  // A preset of Maple's changed on another device (its `presets` event, read again).
  preset: { run: ({ t, base }) => t.set({ topic: "presets", station }, presetsChanged(base, t.host.nowMs())) },
  // A build more out: the changelog read again (changelog.ts `read`: kept, and both of its ways told).
  release: {
    run: ({ t, base }) => {
      t.data.put("changelog", "feed", changelogReleased(base, t.host.nowMs()));
      t.store.invalidateAll((topic) => topic.topic === "changelog");
    },
  },
};

/// What goes out to each of `ASKED` as each cause happens, on a rig of its own (the chat's six pages' too where it is
/// done with them): the cause, the messages by name, and what each was sent whole before it.
export async function causesOfAll(): Promise<{ cause: string; sent: Map<string, J[]>; first: Map<string, J> }[]> {
  const out: { cause: string; sent: Map<string, J[]>; first: Map<string, J> }[] = [];
  for (const [cause, c] of Object.entries(CAUSES)) {
    for (const long of c.long ? [false, true] : [false]) {
      const h = await held(long);
      try {
        out.push({ cause, sent: await h.during(() => c.run(h), c.ms ?? 1000), first: h.first });
      } finally {
        h.t.store.runner.shutdown();
      }
    }
  }
  return out;
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

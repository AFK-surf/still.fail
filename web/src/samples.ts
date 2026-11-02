// Made-up data for what a page shows while it is read the first time, drawn in its bones by the parts that draw the
// real one (@stillfail/ui waiting.tsx Bones; docs/ui-panels.md 等待): only how long its words are is seen, as a bar.
import { sampleWords } from "@stillfail/ui/waiting.tsx";
import type { ArchiveItem, ArchivePolicyView, ArchivingView, ChangelogDay, ChatItem, ChatMessage, Connect, ConnectItem, DriveEntry, DriveRoot, HistoryItem, Host, LockDraftView, LockView, PickView, Profile, ProviderGroup, Quota, ResourcesView, ResourceUse, RowAgent, SkillFile, Stamp, StationMemory, StationView, UsageView, VaultItemRow, VaultsView, VaultUse, WorkspaceProfile } from "./core/shapes.ts";

export { sampleWords };

/** A time said in `n` letters. */
export const sampleStamp = (n = 3): Stamp => ({ at: 0, ago: sampleWords(n), full: sampleWords(n), until: sampleWords(n), past: true });

/** An agent of a made-up chat: its maker's mark at its row's end. */
const AGENT: RowAgent = { key: "sample", runtime: "claude", process: "", pending: 0, agentText: "", statusText: "" };

/** The chats' titles and last lines, letters long. */
const CHATS: readonly [number, number][] = [[6, 12], [9, 10], [5, 13], [8, 9], [7, 12], [10, 11], [6, 8], [9, 12]];

/** A chat of a list made up: its title, its last line, its agent, when. */
export function sampleChat(i: number): ChatItem {
  const [title, line] = CHATS[i % CHATS.length]!;
  return {
    id: `sample-${i}`, session: `sample-${i}`, title: sampleWords(title), agents: [AGENT], unread: false, mine: true,
    lastActiveAt: 0, station: "sample", stationName: "",
    last: { seq: 0, authorKind: "agent", author: "", text: "", createdAt: 0, preview: sampleWords(line), time: { createdAt: sampleStamp() } },
    time: { lastActiveAt: sampleStamp(2) },
  };
}

/** `n` chats made up. */
export const sampleChats = (n: number): ChatItem[] => Array.from({ length: n }, (_, i) => sampleChat(i));

/** A chat's messages: the viewer's (letters long), an agent's (its paragraphs, letters long), in turn. */
const MESSAGES: readonly (number | readonly number[])[] = [16, [48, 22], 12, [60, 34, 18], 9, [28]];

/** A chat's messages made up, as its list draws them: the viewer's in their bubble, an agent's under its name. */
export function sampleMessages(): ChatMessage[] {
  return MESSAGES.map((m, i) => {
    const mine = typeof m === "number";
    return {
      seq: i, thread: 0, ts: String(i), authorKind: mine ? "person" : "agent", author: "", attachments: [], quotes: [], createdAt: 0,
      text: typeof m === "number" ? sampleWords(m) : m.map(sampleWords).join("\n\n"), mine, system: false, waiting: false,
      by: mine ? { name: sampleWords(1) } : { name: sampleWords(5), runtime: "claude" }, time: { createdAt: sampleStamp(2) },
    };
  });
}

/** The stations' names, letters long. */
const STATIONS: readonly number[] = [5, 3, 7, 4];

/** A machine made up: what it is in a line, what is left of its CPU, memory and disk, a few facts of it. */
const sampleHost = (): Host => ({
  hostname: "", os: "", arch: "", cpus: 0, cpuModel: "", load: 0, uptimeSec: 0, memory: { totalBytes: 0, usedBytes: 0 },
  disk: { path: "", totalBytes: 0, freeBytes: 0 }, emberRssBytes: 0, checkedAt: 0, summary: "", line: "", facts: [], usage: "", emberText: "",
  identity: sampleWords(20),
  meters: [3, 2, 2].map((n) => ({
    label: sampleWords(n), short: sampleWords(n), percent: 50, left: 50, level: "ok", value: sampleWords(3), remaining: sampleWords(5),
    big: sampleWords(2), unit: sampleWords(1), title: sampleWords(4), total: sampleWords(5),
  })),
  details: [4, 3, 5].map((n) => ({ label: sampleWords(n), value: sampleWords(n + 6) })),
});

/** A station made up: online, its name, what it says of itself, how it is, its machine. */
export function sampleStation(i: number): StationView {
  return {
    station: `sample/${i}`, id: `sample-${i}`, name: sampleWords(STATIONS[i % STATIONS.length]!), summary: sampleWords(16), online: true,
    stateText: sampleWords(4), problems: [], link: { state: "online" }, runtimes: [], models: [], host: sampleHost(),
  };
}

/** `n` stations made up. */
export const sampleStations = (n: number): StationView[] => Array.from({ length: n }, (_, i) => sampleStation(i));

/** A page of words made up: its paragraphs, letters long. */
const samplePage = (): string => [40, 26, 52, 18].map(sampleWords).join("\n\n");

/** A skill made up, of `group`: its name `n` letters long, a line about it, one page. */
function sampleSkill(n: number, group: "project" | "skill"): SkillFile {
  return {
    name: sampleWords(n), description: "", project: group === "project", builtin: false, text: "", group, line: sampleWords(n + 14),
    size: sampleWords(3), kindText: sampleWords(4), whenText: sampleWords(30), pages: [{ key: "", label: sampleWords(4), size: sampleWords(3), text: samplePage() }],
  };
}

/** A station's memory made up: the global memory's parts, two projects' skills and two others. */
export const sampleMemory = (): StationMemory => ({
  global: { path: "", text: "", size: sampleWords(3), sections: [6, 9, 5, 8].map((n) => ({ title: sampleWords(n), text: samplePage(), note: sampleWords(3) })) },
  skills: [sampleSkill(5, "project"), sampleSkill(8, "project"), sampleSkill(6, "skill"), sampleSkill(4, "skill")],
});

/** What the agents spent made up: three totals, a week's bars, the core's four lists (people, chats, profiles, models) of three rows, two stations' prices. */
export function sampleUsage(): UsageView {
  const costs = [0.4, 0.7, 0.3, 0.9, 0.6, 0.5, 0.8];
  return {
    days: 7, wait: { reading: false, failing: [], empty: false }, empty: false, many: false, max: 1, top: 1, notes: [], basis: "",
    tiles: [4, 5, 3].map((n) => ({ label: sampleWords(n), value: sampleWords(3), sub: sampleWords(n + 4) })),
    series: [{ key: "", name: sampleWords(2) }],
    daily: costs.map((cost, i) => ({ day: String(i), label: sampleWords(2), today: i === costs.length - 1, cost, costText: sampleWords(3), calls: 0, callsText: sampleWords(3), parts: [cost], partsText: [sampleWords(3)], name: sampleWords(3), tick: sampleWords(1) })),
    ticks: [{ value: 0.5, label: sampleWords(2) }, { value: 1, label: sampleWords(2) }],
    lists: [2, 3, 5, 3].map((t, l) => ({ key: String(l), title: sampleWords(t), items: [8, 6, 9].map((n, i) => ({ key: String(i), title: sampleWords(n), sub: sampleWords(5), cost: 0, costText: sampleWords(3), share: 0.6 - i * 0.2, shareText: sampleWords(2), calls: 0, callsText: "", tokensText: "", detail: "" })) })),
    prices: [5, 4].map((n) => ({ station: sampleWords(n), note: sampleWords(20), rows: [9, 7, 8].map((m) => ({ model: sampleWords(m), rates: [3, 3, 4].map((r) => ({ label: sampleWords(r), value: sampleWords(3) })) })) })),
  };
}

/** An allowance made up: two windows, most of each left. */
const sampleQuota = (): Quota => ({ state: "ok", checkedAt: 0, windows: [70, 45].map((left) => ({ label: sampleWords(2), usedPercent: 100 - left, mark: sampleWords(1), left, level: "ok", refills: sampleWords(6) })) });

/** A profile's models made up, by series: each its id and its name, letters long. */
const MODELS: readonly (readonly number[])[] = [[9, 11, 8], [10, 7, 12, 9]];

/** A profile made up: its name `n` letters long, a subscription, its models (two series of them) and allowance, fine. */
export function sampleProfile(n: number, i = 0): Profile {
  const series = MODELS.map((names, s) => ({ name: sampleWords(5 + s), models: names.map((_, m) => `sample-${s}-${m}`) }));
  const models = series.flatMap((x) => x.models);
  const names = Object.fromEntries(MODELS.flatMap((ns, s) => ns.map((m, j) => [`sample-${s}-${j}`, sampleWords(m)])));
  return {
    id: `sample-${i}`, name: sampleWords(n), email: sampleWords(n + 10), runtime: "claude", runtimes: ["claude"], access: { kind: "subscription", key: "" },
    home: "", homeExists: true, models, available: models, env: [], usedBy: [], loginCommand: "", quota: sampleQuota(), checkText: sampleWords(2), checkTone: "green",
    makers: {}, names, series, modelsText: sampleWords(9), group: "claude", groupTitle: sampleWords(4),
  };
}

/** The workspace's profiles made up, a kind of account's run of them, each on two stations. */
export function sampleWorkspaceProfiles(): WorkspaceProfile[] {
  return [6, 8, 5].map((n, i) => ({
    key: `sample-${i}`, group: "", groupTitle: sampleWords(4), station: "sample/0", stationId: "sample-0", stationName: sampleWords(5), profile: sampleProfile(n, i), title: sampleWords(n),
    shared: false, host: "", hostName: "", hostOnline: true, usable: true, look: false, where: sampleWords(5), stations: [], editable: false, canShare: false,
    members: [5, 3].map((m, j) => ({ station: `sample/${j}`, stationId: `sample-${j}`, stationName: sampleWords(m), title: sampleWords(m), online: true, profileId: `sample-${i}`, profileName: sampleWords(m), role: "host", about: sampleWords(m + 6), usable: true, checkText: "", checkTone: "green", usedBy: 0 })),
  }));
}

/** The workspace's vault made up: the person's own, locked, set up here. */
export const sampleVaults = (): VaultsView => ({
  available: true, locked: true, canSign: true, setUp: true, requests: [], refused: [],
  vaults: [{ id: "sample", name: sampleWords(4), owner: "", ownerName: "", mine: true, members: [], station: "", stationName: "", items: 3, devices: 2, open: false, keyed: true, missing: 0, recoverable: false }],
});

/** A vault's secrets made up: each its name, its kind, how an agent gets it, its content shut. */
export const sampleVaultItems = (): VaultItemRow[] => [8, 6, 10].map((n, i) => ({
  id: `sample-${i}`, version: 0, at: 0, name: sampleWords(n), kind: "token", listed: true, modes: [], hosts: [], kindText: sampleWords(2), agentText: sampleWords(n + 6), lineText: sampleWords(n + 6),
  howText: sampleWords(n + 2), lastsText: sampleWords(4), shut: [{ key: "value", label: sampleWords(2), value: sampleWords(16), secret: true, mono: true }],
}));

/** A secret's uses made up: each its chat, how, when. */
export const sampleVaultUses = (): VaultUse[] => [9, 6, 11].map((n) => ({ at: sampleStamp(4), session: "", chatTitle: sampleWords(n), mode: "", hosts: [], howText: sampleWords(n + 4) }));

/** The workspace's security mode made up: off, its owner here, able to turn it on. */
export const sampleLock = (): LockView => ({
  available: true, locked: false, notice: false, role: "owner", manages: true, owner: true, canSign: true, signs: false, signers: 0, members: [], stations: [],
  protected: 0, renew: [], attention: 0,
});

/** Turning security mode on made up: three people, three devices, two stations. */
export const sampleLockDraft = (): LockDraftView => ({
  available: true, loading: false, canSign: true, owner: true, ready: true,
  members: [5, 7, 6].map((n, i) => ({ sub: `sample-${i}`, email: sampleWords(n + 8), name: "", role: "", nameText: sampleWords(n), roleText: sampleWords(2) })),
  devices: [8, 6, 9].map((n, i) => ({ id: `sample-${i}`, person: "", kind: "", label: "", older: false, current: false, last_seen: 0, on: true, fixed: false, nameText: sampleWords(n), howText: sampleWords(n + 4), time: { last_seen: sampleStamp(3) } })),
  stations: [5, 3].map((n, i) => ({ id: `sample-${i}`, name: sampleWords(n), state: "", on: true, fixed: false, stateText: sampleWords(n + 3), version: sampleWords(4) })),
});

/** What a machine's still.fail uses made up: three totals with their lines, four chats' and agents' rows. */
export function sampleResources(): ResourcesView {
  const use = (): ResourceUse => ({ cpu: 0, memory: 0, netIn: 0, netOut: 0, net: 0, diskRead: 0, diskWrite: 0, disk: 0, cpuText: sampleWords(3), memoryText: sampleWords(4), netText: sampleWords(3), diskText: sampleWords(3) });
  return {
    wait: { reading: false, failing: [], empty: false }, empty: false, net: true, disk: false, everyMs: 0, notes: [], basis: sampleWords(24), stations: [],
    tiles: (["cpu", "memory", "net"] as const).map((key, i) => ({ key, label: sampleWords(2 + (i % 2)), value: sampleWords(4), sub: sampleWords(6), points: [0.3, 0.5, 0.4, 0.6, 0.5, 0.7, 0.4, 0.5] })),
    kinds: [2, 3].map((n, i) => ({ key: String(i), label: sampleWords(n) })),
    groups: [10, 7, 12, 6].map((n, i) => ({ key: String(i), kind: "chat", title: sampleWords(n), kindText: sampleWords(2), station: "", use: use(), processes: [] })),
  };
}

/** A connect made up: its name `n` letters long, Slack's, how it runs, online. */
export function sampleConnect(n: number, i = 0): Connect {
  const word = { label: sampleWords(3), description: sampleWords(12) };
  return {
    id: `sample-${i}`, name: sampleWords(n), team: sampleWords(4), enabled: true, kind: "slack", mode: "multi-session", requireMention: true, bind: { runtime: "claude" },
    slack: { appToken: "", botToken: "" }, connection: { state: "connected" }, sessions: 0, statusText: sampleWords(2), presence: "online", modeText: sampleWords(4),
    modeShort: sampleWords(2), runtimeText: sampleWords(5), runText: sampleWords(5), modeWords: { multi: word, single: word, mentionOn: sampleWords(4), mentionOff: sampleWords(4) },
    modeLabel: sampleWords(3), modeSentence: sampleWords(14), placeText: sampleWords(4),
  };
}

/** The workspace's connects made up, each on a station. */
export const sampleConnects = (): ConnectItem[] => [7, 5, 9].map((n, i) => ({
  station: `sample/${i}`, stationName: sampleWords(4), connect: sampleConnect(n, i), sessions: [], candidates: [], running: 0, changes: [],
}));

/** A station's archive policy made up: its words, two options to archive by and two to keep by. */
export const sampleArchivePolicy = (): ArchivePolicyView => ({
  text: [40, 28].map(sampleWords).join(""), days: 7, checked: 0, failed: 0, edited: false,
  options: [[6, true], [8, true], [5, false], [7, false]].map(([n, archive], i) => ({ id: `sample-${i}`, name: sampleWords(n as number), rubric: sampleWords((n as number) + 14), archive: archive as boolean, count: 0, chats: [] })),
});

/** Words made up as the core reads them (Markdown): their paragraphs. */
const sampleMd = (text: string): unknown => text.split("\n\n").map((p) => ["p", [p]]);

/** An agent's history made up: a turn's message, its steps, its own words, more steps, its post. */
export function sampleHistory(): HistoryItem[] {
  const group = (n: number) => ({ kind: "group" as const, content: { summary: sampleWords(n), title: "", failures: 0, pending: 0, rows: [] } });
  const words = sampleWords(26);
  const post = [44, 30].map(sampleWords).join("\n\n");
  return [
    { key: "sample-0", entries: [0], turn: { time: sampleWords(3), text: sampleWords(8) }, body: { kind: "received", content: { tasks: [], messages: [{ key: "m", from: { name: sampleWords(4), bound: false }, text: sampleWords(34) }] } } },
    { key: "sample-1", entries: [1], body: group(18) },
    { key: "sample-2", entries: [2], body: { kind: "text", content: { text: words, md: sampleMd(words), line: words, subagent: false } } },
    { key: "sample-3", entries: [3], body: group(14) },
    { key: "sample-4", entries: [4], body: { kind: "post", content: { text: post, md: sampleMd(post), place: { name: sampleWords(6), surface: "stillfail" }, block: false, failed: false } } },
  ];
}

/** How an agent runs made up: its model, how hard it thinks, its account, nothing changed. */
export function samplePick(): PickView {
  const was = [6, 2, 7].map(sampleWords);
  return {
    options: [], runtimeFixed: false, value: { runtime: "claude" }, draft: { runtime: "claude" }, runtimes: ["claude"], efforts: [2, 2, 1].map(sampleWords), accounts: [],
    who: sampleWords(4), autoNote: sampleWords(12), changed: false, was, becomes: was, modelText: sampleWords(9), accountText: sampleWords(6), accountNote: sampleWords(14),
    accountWarn: false, saveText: sampleWords(2),
  };
}

/** Archived chats made up: each its title, its last line, when. */
export const sampleArchive = (): ArchiveItem[] => sampleChats(6).map((c) => ({
  station: c.station, id: c.id, session: c.session, title: c.title, last: c.last?.preview ?? "", at: 0, clock: sampleWords(2), how: "", deletable: true,
}));

/** How a station archives on its own made up: once idle a week, its three ways, five spans each to choose from. */
export function sampleArchiving(): ArchivingView {
  const days = [1, 3, 7, 14, 0];
  return {
    days: 7, slackDays: 7, reviewed: false, canEdit: true, mode: "idle", reviewText: sampleWords(16), lineText: sampleWords(14), modeNote: sampleWords(30),
    modes: [["off", 2], ["idle", 4], ["reviewed", 5]].map(([mode, n]) => ({ mode: mode as string, label: sampleWords(n as number), days: 7, reviewed: false, allowed: true })),
    daysOffered: days, daysOfferedText: days.map(() => sampleWords(2)), slackDaysOffered: days, slackDaysOfferedText: days.map(() => sampleWords(2)),
  };
}

/** What changed made up: two days, each a few changes of a line or two, their kind before each line. */
export const sampleChangelog = (): ChangelogDay[] => [[[22], [30, 16], [18]], [[26, 20], [14]]].map((day, d) => ({
  label: sampleWords(4),
  entries: day.map((lines, i) => ({
    version: d * 10 + i, versionName: sampleWords(3), text: [], has: true, note: "", mine: true,
    lines: lines.map((n, j) => ({ kind: j === 0 && i === 0 ? "new" : "fix", label: sampleWords(2), text: sampleWords(n) })),
  })),
}));

/** A folder's entries made up: three folders, then five files of as many kinds, each its name letters long. */
export const sampleDriveEntries = (): DriveEntry[] => [
  ...[7, 5, 9].map((n) => ({ n, kind: "folder" as const })),
  ...([[11, "markdown"], [8, "image"], [13, "code"], [6, "pdf"], [10, "text"]] as const).map(([n, kind]) => ({ n, kind })),
].map(({ n, kind }) => ({
  name: sampleWords(n), dir: kind === "folder", size: 0, mtime: 0, type: "", kind, opens: kind === "folder" ? "folder" : "read", sizeText: kind === "folder" ? "" : sampleWords(3), timeText: sampleWords(5),
}));

/** The folders pinned on a station made up, each its name letters long. */
export const sampleDriveRoots = (): DriveRoot[] => [6, 9, 4, 7].map((n, i) => ({ path: `/sample/${i}`, name: sampleWords(n), state: "ok" }));

/** The providers to add an account of made up: two kinds, a few each. */
export const sampleProviders = (): ProviderGroup[] => [[4, 6, 5], [7, 5, 6, 4, 8, 5]].map((names, i) => ({
  id: String(i), title: sampleWords(4), providers: names.map((n, j) => ({ id: `${i}-${j}`, name: sampleWords(n), group: String(i) })),
}));

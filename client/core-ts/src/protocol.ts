// Messages between a UI and the core (protocol.rs, Protocol). The JSON is the Rust core's.
import type { CoreError } from "./error.ts";
import type { AnyOp } from "./collections.ts";
import type { ClientId } from "./host-of.ts";
import { isObject, toJson } from "./util.ts";

/// One connected UI (a tab, a window).
export type { ClientId };
/// Chosen by the UI; answers and subscription values carry it back.
export type RequestId = number;

/// UI → core. `bytes`: a call may carry bytes beside its JSON (a file's part going up): the web and the desktop post
/// them in the message, the native hosts hand them over as they are (never as base64 in the JSON).
export type ClientMessage =
  | { kind: "call"; id: RequestId; call: string; params: unknown; bytes?: Uint8Array }
  /// `from`: another of its subscriptions to the same topic with other params (a list's first rows, more of them asked
  /// now), still held: this one's first value goes as a keyed delta to what that one has (store.ts `#firstFrom`).
  /// `have`: the token (digest.ts `token`) of the value it holds of this topic, kept from an unsubscribe's `v`:
  /// where the topic's value is that one still, its first message is `{id, same: true}`, not the value again; else,
  /// where the core remembers that value for this client, `{id, delta, kept: true}`, what changed from it (store.ts
  /// `#first`); else the value whole.
  | { kind: "subscribe"; id: RequestId; subscribe: Topic; keyed?: boolean; from?: RequestId; have?: string }
  /// `keep`: the client keeps what it holds of the topic, to ask with it again (`have`): answered `{id, v}`, the last
  /// message for this id, what it holds by then being the value `v` is the token of (opaque: a client only says it
  /// back). The core remembers that value for the client a while (store.ts `#kept`).
  | { kind: "unsubscribe"; id: RequestId; unsubscribe: boolean; keep?: boolean }
  | { kind: "cancel"; id: RequestId; cancel: boolean };

/// core → UI, as it goes on the wire. An answer's `bytes` go as a value's do (a file read: its JSON says what it is).
export type CoreMessage =
  | { id: RequestId; ok: unknown; bytes?: Uint8Array }
  | { id: RequestId; error: CoreError }
  /// `bytes`: a call's value may carry bytes beside its JSON (a screen view's frames): the web transfers them, the
  /// native hosts hand them over as they are (never as base64 in the JSON).
  | { id: RequestId; value: unknown; bytes?: Uint8Array }
  | { id: RequestId; delta: AnyOp[] }
  /// A subscription's first value as what changed from what its `from` has now (a subscribe's `from`).
  | { id: RequestId; delta: AnyOp[]; from: RequestId }
  /// A topic with no value yet whose value waits on a station (or the cloud), not on the core reading what the device
  /// holds (store.ts `waits`): what shows it can show what is to come now, not what it holds a moment later.
  | { id: RequestId; waiting: true }
  /// A subscription asked with `have`: the topic's value is the one it holds; nothing of it is sent.
  | { id: RequestId; same: true }
  /// A subscription asked with `have`, its first message: what changed from the value of that token, which the client
  /// kept as it let go of the topic, to the topic's value now (keyed ops to a keyed subscriber, as `delta`).
  | { id: RequestId; delta: AnyOp[]; kept: true }
  /// An unsubscribe with `keep` answered, its id's last message: the token of the value the client holds of it now
  /// (null: it had none).
  | { id: RequestId; v: string | null };

/// A call's answer with bytes beside its JSON (a file read), as a handler gives it: `{id, ok: value, bytes}`.
export class Beside {
  readonly value: unknown;
  readonly bytes: Uint8Array;
  constructor(value: unknown, bytes: Uint8Array) {
    this.value = value;
    this.bytes = bytes;
  }
}

/// What a UI can subscribe to: `{ topic, …params }`, its params as protocol.rs declares them (defaults filled, absent
/// options left out). `station` is `"<workspace>/<station>"`.
export type Topic = { topic: string; [param: string]: unknown };

type Param = "string" | "u64" | "u32" | "u16" | "bool" | "object";
/// How each param is kept: `req` must be given; `def` is filled in when absent (and always sent); `opt` is null when
/// absent and sent so; `skip` is left out when absent (`skip_serializing_if`); `skipFalse`, a bool left out when false.
type Spec = Record<string, [Param, "req" | "def" | "opt" | "skip" | "skipFalse"]>;

const S: [Param, "req"] = ["string", "req"];

/// protocol.rs `Topic`, by its wire name.
export const TOPICS: Record<string, Spec> = {
  accounts: {},
  workspaces: {},
  workspace: { workspace: S },
  link: { station: S },
  overview: { station: S },
  sessions: { station: S },
  session: { station: S, key: S },
  live: { station: S, key: S },
  host: { station: S },
  memory: { station: S },
  presets: { station: S },
  net: { station: S },
  way: { station: S },
  threads: { station: S },
  thread: { station: S, thread: ["u64", "req"] },
  letters: { station: S, thread: ["u64", "req"] },
  chatRows: { station: S },
  slackApp: { station: S, connect: S },
  jobs: { station: S },
  jobLog: { station: S, job: S, lines: ["u64", "req"] },
  machineLogins: { station: S },
  machineLogin: { station: S, id: S },
  machineLoginScreen: { station: S, id: S },
  loginSessions: { account: S },
  admin: { account: S, list: S },
  adminList: { account: S, list: S, query: ["string", "def"], filter: ["string", "skip"], sort: ["string", "skip"], limit: ["u32", "skip"] },
  adminItem: { account: S, list: S, id: S },
  adminOverview: { account: S },
  adminRelays: { account: S, range: ["string", "skip"] },
  // (how many of its rows go out is no part of it: its window, `chats.window`, views.ts Views `chatsWindow`)
  chats: { scope: S, mine: ["bool", "def"], watching: ["bool", "skipFalse"], hidden: ["bool", "skipFalse"] },
  // One chat's row whole (ChatItem), as the list made it before its rows were what they draw (ListedChat): what a row
  // offers only as it is pressed, held, swiped or pointed at (its menu, its swipe's question, its time), asked as that
  // begins and held while it is open (apps/mbui sfbase rows.mbt `whole_row`). Null where the station lists no such chat.
  chatRow: { station: S, session: S },
  // A list's stations, each its row (StationRow); one station's page asks that station (StationView), one part of its
  // overview `stationPart` (`part`: one of STATION_PARTS). (`stationsWhole`, the rows with the pages and the models
  // each can run, is the core's own: views/views.ts; no UI asks it.)
  stations: { scope: S },
  station: { scope: S, station: S },
  stationPart: { scope: S, station: S, part: S },
  // A list's accounts, each its row (ProfileRow); one account's pages ask that account (WorkspaceProfile): by its key,
  // or by a profile of it on a station (`station`, `id`), as a profile's page is opened.
  profiles: { scope: S },
  profile: { scope: S, key: ["string", "skip"], station: ["string", "skip"], id: ["string", "skip"] },
  // A list's connects, each its row (ConnectRow); one connect's page asks that connect (ConnectView), and a
  // single-session one's page what its choice of a session lists, `connectCandidates`, while it can open that choice.
  connects: { scope: S, mine: ["bool", "def"] },
  connect: { scope: S, station: S, id: S },
  connectCandidates: { scope: S, station: S, id: S },
  chat: { station: S, thread: ["u64", "opt"], session: ["string", "opt"], compact: ["bool", "skipFalse"] },
  history: { station: S, key: S },
  agentCard: { station: S, key: S },
  stationNet: { station: S },
  status: { workspace: ["string", "skip"] },
  notices: { workspace: ["string", "skip"] },
  connection: { station: S },
  draft: { station: S, chat: S },
  composer: { key: S },
  notify: { workspace: ["string", "skip"] },
  chatSearch: { scope: S, query: ["string", "def"], station: ["string", "skip"], exclude: ["string", "skip"], limit: ["u32", "skip"], messages: ["u32", "skip"], elsewhere: ["bool", "skipFalse"] },
  archivedRows: { station: S },
  archive: { scope: S, q: ["string", "skip"], limit: ["u32", "skip"] },
  search: { scope: S, query: ["string", "def"], kind: ["string", "skip"], limit: ["u32", "skip"] },
  stationSearch: { station: S, q: S, kind: ["string", "skip"], limit: ["u32", "skip"], archived: ["bool", "skipFalse"] },
  linkPreview: { station: S, url: S },
  filePeek: { station: S, key: S, path: S, line: ["u32", "skip"] },
  messagePeek: { station: S, thread: ["u64", "req"], seq: ["u64", "req"] },
  newChat: { scope: S },
  /// A preset whole, the person's own or someone else's (views/presets.ts), as its page shows and edits it.
  preset: { scope: S, id: S },
  /// Others' presets of a workspace, read as it is shown (a press: views/presets.ts).
  otherPresets: { scope: S },
  shareIn: { scope: S, source: S, query: ["string", "def"] },
  pick: { station: S, of: S },
  chatJobs: { station: S, thread: ["u64", "opt"], session: ["string", "opt"], compact: ["bool", "skipFalse"], summary: ["bool", "skipFalse"] },
  chatLetters: { station: S, thread: ["u64", "req"] },
  chatFeedback: { station: S, session: S },
  chatThings: { station: S, thread: ["u64", "req"], q: ["string", "skip"] },
  chatOutline: { station: S, thread: ["u64", "req"] },
  imageNear: { station: S, thread: ["u64", "opt"], session: ["string", "opt"], path: S, at: ["string", "skip"] },
  longJobs: { scope: S },
  stationUsage: { station: S },
  usage: { scope: S, days: ["u32", "skip"], split: ["string", "skip"], only: ["object", "skip"], day: ["string", "skip"] },
  fleet: { scope: S },
  railCard: { scope: S, place: S },
  // The workspace's stations whose newer release waits for this person (views/station-updates.ts).
  stationUpdates: { scope: S },
  settings: { scope: S },
  stationResources: { station: S },
  resources: { scope: S, station: ["string", "skip"] },
  job: { station: S, id: S },
  drive: { station: S, root: S, path: ["string", "def"] },
  drivePlace: { station: S, root: S, path: S },
  prefs: {},
  doing: {},
  adbShare: {},
  adbCard: { station: S },
  rigs: { workspace: S },
  devices: { workspace: S },
  previewLoad: { station: S, port: ["u16", "req"] },
  slackTokens: { station: S, form: S },
  connectFlow: { station: S, form: S },
  decisionForm: { station: S, form: S },
  policyForm: { station: S, form: S },
  agentEnvForm: { station: S, form: S },
  profileFlow: { station: S, form: S },
  changelog: { news: ["bool", "skipFalse"], part: ["string", "skip"], limit: ["u32", "skip"] },
  releases: {},
  fonts: {},
  workspaceMarks: {},
  workspaceWays: { workspace: S },
  lock: { workspace: S },
  joinable: { workspace: S },
  memberships: { station: S },
  screens: { station: S },
  terminals: { station: S },
  screenCard: { station: S, screen: S },
  lockDraft: { workspace: S },
  lockPrompts: {},
  vaults: { workspace: S },
  vaultItems: { workspace: S, vault: S },
  driveTransfers: { workspace: S },
  driveBrowse: { owner: S, place: S, view: S, station: S, root: S, path: ["string", "def"], write: ["bool", "skipFalse"] },
  filesTabs: { workspace: S },
  downloads: {},
  vaultUses: { workspace: S, vault: S, item: S },
};

const LIMITS: Record<string, number> = { u64: 2 ** 64, u32: 2 ** 32 - 1, u16: 65535 };

function fits(value: unknown, kind: Param): boolean {
  switch (kind) {
    case "string":
      return typeof value === "string";
    case "bool":
      return typeof value === "boolean";
    case "object":
      return isObject(value);
    default:
      return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= LIMITS[kind]!;
  }
}

/// The parts of a station's overview `stationPart` gives, each as the `station` topic's `overview` has it: what a page
/// showing a line of every station reads (权限's archiving, 自动决策's policy of each, the profiles' page), or a page
/// showing one part of a station that is not its own (关于's 本机 Station: its software, `updates`), not each
/// station's whole page.
export const STATION_PARTS: readonly string[] = ["archiving", "automaticDecisions", "profiles", "machineLogins", "logins", "updates"];

/// A topic as the UI said it, or null when it is none (the subscribe is then no message the core knows).
export function parseTopic(raw: unknown): Topic | null {
  if (!isObject(raw) || typeof raw.topic !== "string") return null;
  const spec = TOPICS[raw.topic];
  if (!spec) return null;
  const out: Topic = { topic: raw.topic };
  for (const [name, [kind, how]] of Object.entries(spec)) {
    const value = raw[name];
    const absent = value === undefined || (value === null && how !== "req");
    if (absent) {
      if (how === "req") return null;
      if (how === "def") out[name] = kind === "bool" ? false : "";
      else if (how === "opt") out[name] = null;
      else if (how === "skipFalse") continue;
      continue;
    }
    if (!fits(value, kind)) return null;
    if (how === "skipFalse" && value === false) continue;
    out[name] = value;
  }
  if (out.topic === "stationPart" && !STATION_PARTS.includes(out.part as string)) return null;
  return out;
}

/// A topic by its params: one key per topic, whatever order its params came in.
export function topicKey(topic: Topic): string {
  return toJson(topic);
}

export function sameTopic(a: Topic, b: Topic): boolean {
  return topicKey(a) === topicKey(b);
}

const STATION_TOPICS = new Set(["link", "overview", "sessions", "host", "net", "way", "threads", "chatRows", "jobs", "archivedRows", "stationUsage", "stationResources", "session", "live", "thread", "letters", "slackApp", "jobLog", "drive", "screens", "terminals", "screenCard", "machineLogins", "machineLogin", "machineLoginScreen", "stationSearch", "memory", "presets", "linkPreview", "filePeek", "messagePeek"]);
const VIEWS = new Set(["chats", "chatRow", "stations", "station", "stationPart", "profiles", "profile", "connects", "connect", "connectCandidates", "chat", "history", "agentCard", "stationNet", "chatSearch", "search", "archive", "chatJobs", "chatLetters", "chatThings", "chatOutline", "imageNear", "longJobs", "workspaceMarks", "decisions", "usage", "fleet", "railCard", "stationUpdates", "settings", "resources", "adminList", "adminItem", "adminOverview", "adminRelays", "workspaceWays"]);

/// The station a station topic belongs to; null for the account topics, the core's own and the views.
export function topicStation(topic: Topic): string | null {
  return STATION_TOPICS.has(topic.topic) ? (topic.station as string) : null;
}

export function isView(topic: Topic): boolean {
  return VIEWS.has(topic.topic);
}

/// A message from a UI, or why it is none (serde's words, as the native host answers them: `bad_message`). `bytes`:
/// those a native host handed over beside it; a page's come in it.
export function parseClientMessage(raw: unknown, bytes?: Uint8Array): ClientMessage | { invalid: string } {
  const bad = { invalid: "data did not match any variant of untagged enum ClientMessage" };
  if (!isObject(raw)) return bad;
  const id = raw.id;
  if (typeof id !== "number" || !Number.isInteger(id) || id < 0) return bad;
  if (typeof raw.call === "string") {
    const beside = bytes ?? (raw.bytes instanceof Uint8Array ? raw.bytes : undefined);
    const params = raw.params === undefined ? null : raw.params;
    return beside === undefined ? { kind: "call", id, call: raw.call, params } : { kind: "call", id, call: raw.call, params, bytes: beside };
  }
  if ("subscribe" in raw) {
    const topic = parseTopic(raw.subscribe);
    // `keyed`: the UI applies keyed ops (collections.ts); the Rust core ignores it.
    if (topic) {
      const have = typeof raw.have === "string" ? { have: raw.have } : {};
      if (raw.keyed !== true) return { kind: "subscribe", id, subscribe: topic, ...have };
      const from = raw.from;
      return typeof from === "number" && Number.isInteger(from) && from >= 0 && from !== id
        ? { kind: "subscribe", id, subscribe: topic, keyed: true, from, ...have }
        : { kind: "subscribe", id, subscribe: topic, keyed: true, ...have };
    }
  }
  if (typeof raw.unsubscribe === "boolean")
    return raw.keep === true ? { kind: "unsubscribe", id, unsubscribe: raw.unsubscribe, keep: true } : { kind: "unsubscribe", id, unsubscribe: raw.unsubscribe };
  if (typeof raw.cancel === "boolean") return { kind: "cancel", id, cancel: raw.cancel };
  return bad;
}

/// The Rust core's `{topic:?}` (for the words of a shape's error).
export function topicDebug(topic: Topic): string {
  const name = topic.topic[0]!.toUpperCase() + topic.topic.slice(1);
  const params = Object.entries(topic).filter(([k]) => k !== "topic");
  if (params.length === 0) return name;
  const shown = (v: unknown) => (v === null ? "None" : typeof v === "string" ? JSON.stringify(v) : String(v));
  return `${name} { ${params.map(([k, v]) => `${k}: ${shown(v)}`).join(", ")} }`;
}

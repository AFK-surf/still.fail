// Messages between a UI and the core (protocol.rs; docs/client-core.md, Protocol). The JSON is the Rust core's.
import type { CoreError } from "./error.ts";
import type { AnyOp } from "./collections.ts";
import { isObject, toJson } from "./util.ts";

/// One connected UI (a tab, a window).
export type ClientId = number;
/// Chosen by the UI; answers and subscription values carry it back.
export type RequestId = number;

/// UI → core.
export type ClientMessage =
  | { kind: "call"; id: RequestId; call: string; params: unknown }
  | { kind: "subscribe"; id: RequestId; subscribe: Topic; keyed?: boolean }
  | { kind: "unsubscribe"; id: RequestId; unsubscribe: boolean }
  | { kind: "cancel"; id: RequestId; cancel: boolean };

/// core → UI, as it goes on the wire.
export type CoreMessage =
  | { id: RequestId; ok: unknown }
  | { id: RequestId; error: CoreError }
  | { id: RequestId; value: unknown }
  | { id: RequestId; delta: AnyOp[] };

/// What a UI can subscribe to: `{ topic, …params }`, its params as protocol.rs declares them (defaults filled, absent
/// options left out). `station` is `"<workspace>/<station>"`.
export type Topic = { topic: string; [param: string]: unknown };

type Param = "string" | "u64" | "u32" | "u16" | "bool";
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
  footprint: { station: S },
  net: { station: S },
  threads: { station: S },
  thread: { station: S, thread: ["u64", "req"] },
  chatRows: { station: S },
  slackApp: { station: S, connect: S },
  jobs: { station: S },
  jobLog: { station: S, job: S, lines: ["u64", "req"] },
  loginSessions: { account: S },
  admin: { account: S, list: S },
  adminList: { account: S, list: S, query: ["string", "def"], filter: ["string", "skip"], sort: ["string", "skip"], limit: ["u32", "skip"] },
  adminItem: { account: S, list: S, id: S },
  adminOverview: { account: S },
  chats: { scope: S, mine: ["bool", "def"], watching: ["bool", "skipFalse"] },
  stations: { scope: S },
  profiles: { scope: S },
  connects: { scope: S, mine: ["bool", "def"] },
  chat: { station: S, thread: ["u64", "opt"], session: ["string", "opt"] },
  history: { station: S, key: S },
  status: { workspace: ["string", "skip"] },
  notices: { workspace: ["string", "skip"] },
  connection: { station: S },
  draft: { station: S, chat: S },
  notify: { workspace: ["string", "skip"] },
  chatSearch: { scope: S, query: ["string", "def"], station: ["string", "skip"], exclude: ["string", "skip"], limit: ["u32", "skip"] },
  archivedRows: { station: S },
  archive: { scope: S },
  newChat: { scope: S },
  pick: { station: S, of: S },
  chatJobs: { station: S, thread: ["u64", "opt"], session: ["string", "opt"] },
  longJobs: { scope: S },
  stationUsage: { station: S },
  usage: { scope: S, days: ["u32", "skip"] },
  job: { station: S, id: S },
  prefs: {},
  doing: {},
  adbShare: {},
  previewLoad: { station: S, port: ["u16", "req"] },
  slackTokens: { station: S, form: S },
  connectFlow: { station: S, form: S },
  decisionForm: { station: S, form: S },
  profileFlow: { station: S, form: S },
  changelog: {},
  workspaceMarks: { workspace: ["string", "skip"] },
  decisions: { workspace: S },
};

const LIMITS: Record<string, number> = { u64: 2 ** 64, u32: 2 ** 32 - 1, u16: 65535 };

function fits(value: unknown, kind: Param): boolean {
  switch (kind) {
    case "string":
      return typeof value === "string";
    case "bool":
      return typeof value === "boolean";
    default:
      return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= LIMITS[kind];
  }
}

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
  return out;
}

/// A topic by its params: one key per topic, whatever order its params came in.
export function topicKey(topic: Topic): string {
  return toJson(topic);
}

export function sameTopic(a: Topic, b: Topic): boolean {
  return topicKey(a) === topicKey(b);
}

const STATION_TOPICS = new Set(["link", "overview", "sessions", "host", "footprint", "net", "threads", "chatRows", "jobs", "archivedRows", "stationUsage", "session", "live", "thread", "slackApp", "jobLog"]);
const VIEWS = new Set(["chats", "stations", "profiles", "connects", "chat", "history", "chatSearch", "archive", "chatJobs", "longJobs", "workspaceMarks", "decisions", "usage", "adminList", "adminItem", "adminOverview"]);

/// The station a station topic belongs to; null for the account topics, the core's own and the views.
export function topicStation(topic: Topic): string | null {
  return STATION_TOPICS.has(topic.topic) ? (topic.station as string) : null;
}

export function isView(topic: Topic): boolean {
  return VIEWS.has(topic.topic);
}

/// A message from a UI, or why it is none (serde's words, as the native host answers them: `bad_message`).
export function parseClientMessage(raw: unknown): ClientMessage | { invalid: string } {
  const bad = { invalid: "data did not match any variant of untagged enum ClientMessage" };
  if (!isObject(raw)) return bad;
  const id = raw.id;
  if (typeof id !== "number" || !Number.isInteger(id) || id < 0) return bad;
  if (typeof raw.call === "string") return { kind: "call", id, call: raw.call, params: raw.params === undefined ? null : raw.params };
  if ("subscribe" in raw) {
    const topic = parseTopic(raw.subscribe);
    // `keyed`: the UI applies keyed ops (collections.ts); the Rust core ignores it.
    if (topic) return raw.keyed === true ? { kind: "subscribe", id, subscribe: topic, keyed: true } : { kind: "subscribe", id, subscribe: topic };
  }
  if (typeof raw.unsubscribe === "boolean") return { kind: "unsubscribe", id, unsubscribe: raw.unsubscribe };
  if (typeof raw.cancel === "boolean") return { kind: "cancel", id, cancel: raw.cancel };
  return bad;
}

/// The Rust core's `{topic:?}` (for the words of a shape's error).
export function topicDebug(topic: Topic): string {
  const name = topic.topic[0].toUpperCase() + topic.topic.slice(1);
  const params = Object.entries(topic).filter(([k]) => k !== "topic");
  if (params.length === 0) return name;
  const shown = (v: unknown) => (v === null ? "None" : typeof v === "string" ? JSON.stringify(v) : String(v));
  return `${name} { ${params.map(([k, v]) => `${k}: ${shown(v)}`).join(", ")} }`;
}

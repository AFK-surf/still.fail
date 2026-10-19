// Named calls and their input validation (core/calls.rs); execution stays in the core (execute.ts).
import { parseAdb, type AdbCall } from "../adb-parse.ts";
import { parseAsk, type Ask } from "../asks-parse.ts";
import { parseAttend, type AttendCall } from "../attend-parse.ts";
import { parseScreen, type ScreenCall } from "../screens.ts";
import { parseComposer, type ComposerAct } from "../composer.ts";
import { conform } from "../conform.ts";
import { type HeldCall, type ModuleCall, parseModuleCall } from "../module.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import * as ops from "../ops.ts";
import type { Topic } from "../protocol.ts";
import { draftAt } from "../refs.ts";
import { StationAddr } from "../station/addr.ts";
import { fromBase64, get, isObject } from "../util.ts";
import { orEmpty, read } from "./params.ts";

/// A message of a preview socket (station/wire.rs `SocketFrame`).
export type SocketFrame = { text: string } | { binary: Uint8Array } | { close: [number, string] };

export type Call =
  | { kind: "connectFlow"; topic: Topic; action: string; patch: unknown }
  | { kind: "decisionForm"; topic: Topic; action: string; patch: unknown }
  | { kind: "policyForm"; topic: Topic; action: string; patch: unknown }
  | { kind: "agentEnvForm"; topic: Topic; action: string; patch: unknown }
  | { kind: "profileFlow"; topic: Topic; action: string; patch: unknown }
  | { kind: "slackTokens"; topic: Topic; action: string; patch: unknown }
  | { kind: "clientError"; source: string; message: string }
  | { kind: "wake"; away: number; network: boolean; retry: boolean }
  | { kind: "authBegin"; redirectUri: string; returnTo: string; deviceName: string | null }
  | { kind: "authComplete"; query: string }
  | { kind: "authPassword"; email: string; password: string; deviceName: string | null }
  | { kind: "signOut"; account: string }
  | { kind: "deleteAccount"; account: string }
  | { kind: "op"; op: ops.Request }
  | { kind: "profileModels"; op: ops.Request; id: string; models: unknown }
  | { kind: "chatArchive"; op: ops.Request; thread: number | null; session: string; archived: boolean }
  | { kind: "chatChange"; op: ops.Request; thread: number | null; session: string; title: string | null; pinned: boolean | null; keep: boolean | null }
  | { kind: "chatXshare"; station: string; workspace: string | null; session: string; thread: number | null; to: string[]; write: boolean }
  | { kind: "stationJoin"; workspace: string; station: string; name: string | null }
  | { kind: "chatSend"; station: string; thread: number; text: string; attachments: unknown; uploads?: { id: string; name: string; size: number; width?: number; height?: number }[]; quotes: unknown; client: string | null }
  | { kind: "chatCreate"; station: string; ask: Record<string, unknown> }
  | { kind: "shareIn"; scope: string; source: string; title: string | null; target: { station: string; id?: string }; key: string | null }
  | { kind: "chatSendTo"; station: string; session: string; text: string; attachments: unknown; uploads?: { id: string; name: string; size: number; width?: number; height?: number }[]; quotes: unknown; client: string | null }
  | { kind: "decisionAnswer"; station: string; thread: number; seq: number; option: string }
  | { kind: "decisionReply"; station: string; thread: number; seq: number; text: string; attachments: unknown; uploads?: { id: string; name: string; size: number; width?: number; height?: number }[]; quotes: unknown }
  | { kind: "decisionDefer"; station: string; thread: number; seq: number }
  | { kind: "chatRetryIn"; station: string; session: string; id: string }
  | { kind: "chatDiscardIn"; station: string; session: string; id: string }
  | { kind: "chatRetry"; station: string; thread: number; id: string }
  | { kind: "chatDiscard"; station: string; thread: number; id: string }
  | { kind: "chatOlder"; station: string; thread: number }
  | { kind: "chatNewer"; station: string; thread: number }
  | { kind: "chatLatest"; station: string; thread: number }
  | { kind: "chatPlace"; station: string; thread: number; seq: number | null; offset: number | null }
  | { kind: "chatAround"; station: string; thread: number; seq: number }
  | { kind: "chatFind"; station: string; thread: number; query: string; bring: boolean }
  | { kind: "historyOlder"; station: string; key: string }
  | { kind: "historyDetail"; station: string; key: string; from: number; to: number }
  | { kind: "stationMeasure"; station: string }
  | { kind: "stationUpdateNotice"; station: string; action: string; version: string | null }
  | { kind: "chatRead"; station: string; thread: number; seq: number }
  | { kind: "stationUpload"; station: string; name: string; bytes: Uint8Array }
  | { kind: "stationUploadPart"; station: string; id: string; name: string; size: number; offset: number; bytes: Uint8Array; progress: boolean }
  | { kind: "stationFile"; station: string; key: string; name: string; thumb: boolean; progress: boolean }
  | { kind: "stationFilePart"; station: string; key: string; name: string; offset: number; length: number; progress: boolean; stream: boolean }
  | { kind: "stationPoster"; station: string; key: string; name: string }
  | { kind: "fileOpen"; station: string; key: string; path: string }
  | { kind: "driveRead"; station: string; root: string; path: string; offset: number; length: number; progress: boolean; stream: boolean }
  | { kind: "driveUploadPart"; station: string; root: string; path: string; id: string; offset: number; total: number; replace: boolean; bytes: Uint8Array }
  | { kind: "driveRefresh"; station: string; root: string; path: string }
  /// A login's page to open (docs/remote-login.md): a loopback login's callback listened for here first, unless the
  /// station is this machine (`here`).
  | { kind: "machineLoginOpen"; station: string; id: string; here: boolean }
  | { kind: "drivePlace"; station: string; root: string; path: string; at: number; of: number | null }
  | { kind: "cacheUsage" }
  | { kind: "cacheClear"; station: string; thread: number }
  | { kind: "stationPreview"; station: string; port: number; method: string; path: string; headers: [string, string][]; body: Uint8Array; stream: boolean }
  | { kind: "previewSocket"; station: string; port: number; path: string; headers: [string, string][]; socket: string }
  | { kind: "previewSocketSend"; socket: string; frame: SocketFrame }
  | { kind: "migrate"; accounts: unknown | null; device: Uint8Array | null }
  | { kind: "pushKey" }
  | { kind: "pushRegister"; registration: unknown }
  | { kind: "pushUnregister" }
  | { kind: "draftPut"; station: string; chat: string; draft: unknown }
  | { kind: "attend"; call: AttendCall }
  | { kind: "draftGet"; station: string; chat: string }
  | { kind: "composer"; key: string; act: ComposerAct }
  | { kind: "chatRef"; station: string; id: string; title: string; base: string | null; into: string | null }
  | { kind: "chatOutsideRefs"; station: string; text: string }
  | { kind: "chatXshareAdd"; station: string; id: string; workspace: string; prefer: string | null }
  /// A chat made public (views/publish.ts): what a snapshot would hold, one kept, one revoked.
  | { kind: "chatPublishPreview"; station: string; thread: number }
  | { kind: "chatPublish"; station: string; thread: number; upto: number; files: string[] }
  | { kind: "chatUnpublish"; station: string; thread: number | null; id: string }
  | { kind: "chatRefsKeep"; links: [string, string][] }
  | { kind: "choose"; name: string; params: Record<string, unknown> }
  | { kind: "prefsSet"; patch: unknown; fill: boolean }
  | { kind: "clientDevice"; facts: unknown }
  | { kind: "changelogSeen" }
  | { kind: "ask"; ask: Ask }
  | { kind: "adb"; call: AdbCall }
  /// A station's screen seen and driven (screens.ts): `screen.view` and what goes on it.
  | { kind: "screen"; call: ScreenCall }
  /// The workspace lock (views/lock.ts): `lock.<name>` on a workspace, with what it takes.
  | { kind: "lock"; name: string; workspace: string; params: Record<string, unknown> }
  | { kind: "lockPrompt"; name: string; params: Record<string, unknown> }
  /// The vault (views/vault.ts): `vault.<name>` on a workspace, with what it takes.
  | { kind: "vault"; name: string; workspace: string; params: Record<string, unknown> }
  | { kind: "plugins"; name: "run" | "delete"; scope: string; station: string; id: string; source: string }
  /// An app's module's call (module.ts): `<module>.<name>`, its params as the module checked them.
  | { kind: "module"; name: string; call: HeldCall };

/// Whether a UI can cancel it (`{id, cancel}`), and one gone does: the calls that hold something open for a page.
export function cancellable(call: Call): boolean {
  if (call.kind === "module") return call.call.def.cancellable === true;
  return (call.kind === "stationPreview" && call.stream) || call.kind === "previewSocket" || (call.kind === "screen" && call.call.kind === "view");
}

function opStation(op: ops.Request): string | null {
  return "station" in op.target ? op.target.station : null;
}

/// The station a call is about, if any.
export function callStation(call: Call): string | null {
  switch (call.kind) {
    case "op":
    case "profileModels":
    case "chatArchive":
    case "chatChange":
      return opStation(call.op);
    case "choose": {
      const s = call.params.station;
      return typeof s === "string" ? s : null;
    }
    case "adb":
      return call.call.kind === "share" ? call.call.offer.station : null;
    case "screen":
      return call.call.kind === "view" ? call.call.station : null;
    case "decisionForm":
    case "policyForm":
    case "agentEnvForm":
    case "profileFlow":
    case "connectFlow":
    case "slackTokens":
      return call.topic.station as string;
    case "module":
      return call.call.def.station?.(call.call.params) ?? null;
    default:
      return "station" in call && typeof call.station === "string" ? call.station : null;
  }
}

/// Whether a call is one a person does and waits on (doing.rs `counts`).
export function counts(call: Call, name: string): boolean {
  switch (call.kind) {
    case "module":
      return call.call.def.counts === true;
    case "decisionForm":
    case "policyForm":
    case "agentEnvForm":
      return call.action === "save";
    case "profileFlow":
      return call.action === "submit";
    case "connectFlow":
      return ["config", "make", "verify", "create"].includes(call.action);
    case "slackTokens":
      return call.action === "verify";
    case "profileModels":
      return true;
    case "op":
      return call.op.method !== "GET" && !ops.QUIET_WRITES.includes(name);
    case "chatArchive":
    case "chatChange":
    case "chatXshare":
    case "chatXshareAdd":
    case "stationJoin":
    case "chatPublish":
    case "chatUnpublish":
    case "chatRetry":
    case "chatRetryIn":
    case "chatDiscard":
    case "chatDiscardIn":
      return true;
    case "machineLoginOpen":
    case "chatLatest":
    case "signOut":
    case "deleteAccount":
    case "authBegin":
    case "authPassword":
    case "stationMeasure":
      return true;
    case "decisionAnswer":
    case "decisionReply":
      return true;
    case "wake":
      return call.retry;
    case "choose":
      return call.name === "pick.save" || call.name === "pick.borrow";
    case "attend":
      return name === "notify.set";
    case "ask":
      return name === "dev.signIn";
    case "adb":
      return call.call.kind === "pair" || call.call.kind === "grant";
    case "lock":
      return call.name !== "state" && call.name !== "toggle" && call.name !== "dismiss" && call.name !== "pair" && call.name !== "pairCode" && call.name !== "pairCancel";
    case "lockPrompt":
      return false;
    case "vault":
      return call.name !== "state" && call.name !== "lock" && call.name !== "open";
    default:
      return false;
  }
}

const S = "string" as const;

/// The vault's calls (views/vault.ts).
export const VAULT_CALLS = ["state", "lock", "setup", "create", "addDevice", "putItem", "deleteItem", "open", "recover", "approve", "deny", "migrate"];

/// The workspace lock's calls (views/lock.ts).
export const LOCK_CALLS = ["state", "open", "toggle", "dismiss", "request", "confirm", "deny", "addStation", "joinStation", "renew", "removeDevice", "disable", "pair", "pairCode", "pairCancel"];

/// The calls on a new device showing this one's code (views/pair.ts, `lockPrompts`).
export const LOCK_PROMPT_CALLS = ["deny", "state"];

function form(name: string, params: unknown, prefix: string, actions: string[]): { topic: Topic; action: string; patch: unknown } | null {
  if (!name.startsWith(prefix)) return null;
  const action = name.slice(prefix.length);
  if (!actions.includes(action)) return null;
  const f = read(params, [
    ["station", S, "req"],
    ["form", S, "req"],
  ]);
  StationAddr.parse(f.station as string);
  if (f.form === "") throw CoreError.invalid(t("core-misc.params.missing_form"));
  const patch = get(params, "input");
  return { topic: { topic: "", station: f.station, form: f.form }, action, patch: patch === undefined ? {} : patch };
}

function b64(text: string, what: string): Uint8Array {
  const bytes = fromBase64(text);
  if (!bytes) throw CoreError.invalid(t(what));
  return bytes;
}

/// The bytes a call carries beside its JSON (a file's part going up), which it must.
function beside(bytes: Uint8Array | undefined): Uint8Array {
  if (bytes === undefined) throw CoreError.invalid(t("core-misc.params.missing", { field: "bytes" }));
  return bytes;
}

/// `bytes`: what the call carries beside its JSON, if anything; `modules`: the calls of the app's modules (module.ts),
/// asked after the core's own.
export function parseCall(name: string, params: unknown, bytes?: Uint8Array, modules?: Map<string, ModuleCall<any>>): Call {
  const flows: [string, string[], "decisionForm" | "policyForm" | "agentEnvForm" | "profileFlow" | "connectFlow" | "slackTokens", string][] = [
    ["automaticDecisions.form.", ["open", "edit", "save", "drop"], "decisionForm", "decisionForm"],
    ["automaticDecisions.policy.", ["open", "edit", "save", "drop"], "policyForm", "policyForm"],
    ["agentEnv.form.", ["open", "edit", "save", "drop"], "agentEnvForm", "agentEnvForm"],
    ["profile.flow.", ["open", "edit", "submit", "drop"], "profileFlow", "profileFlow"],
    ["connect.flow.", ["open", "edit", "go", "config", "make", "verify", "create", "drop"], "connectFlow", "connectFlow"],
    ["slack.tokens.", ["edit", "verify", "drop"], "slackTokens", "slackTokens"],
  ];
  for (const [prefix, actions, kind, topicName] of flows) {
    const f = form(name, params, prefix, actions);
    if (f) {
      f.topic.topic = topicName;
      return { kind, ...f };
    }
  }
  const attend = parseAttend(name, params);
  if (attend) return { kind: "attend", call: attend };
  const composer = parseComposer(name, params);
  if (composer) return composer;
  const send = (p: unknown) =>
    read(p, [
      ["station", S, "req"],
      ["thread", "u64", "req"],
      ["text", S, "default"],
      ["attachments", "value", "opt"],
      ["quotes", "value", "opt"],
      ["client", S, "opt"],
    ]);
  // `#[serde(default = "empty_list")]`: [] when absent; given (null too), as given.
  const listOf = (field: string) => (isObject(params) && field in params ? (params as Record<string, unknown>)[field] : []);
  const uploads = () => {
    const files = listOf("uploads");
    if (!Array.isArray(files) || files.some((f) => !isObject(f) || typeof f.id !== "string" || !f.id || typeof f.name !== "string" || typeof f.size !== "number" || !Number.isFinite(f.size) || f.size < 0
      || [f.width, f.height].some((n) => n !== undefined && (!Number.isSafeInteger(n) || (n as number) <= 0)))) throw CoreError.invalid("invalid uploads");
    return files as { id: string; name: string; size: number; width?: number; height?: number }[];
  };
  const uploadFields = () => { const files = uploads(); return files.length ? { uploads: files } : {}; };
  if (name === "plugins.run" || name === "plugins.delete") {
    const p = read(params, [
      ["scope", S, "req"],
      ["station", S, "req"],
      ["id", S, "req"],
      ["source", S, "default"],
    ]);
    return { kind: "plugins", name: name === "plugins.run" ? "run" : "delete", scope: p.scope as string, station: p.station as string, id: p.id as string, source: p.source as string };
  }
  if (name.startsWith("vault.") && VAULT_CALLS.includes(name.slice(6))) {
    const p = read(params, [["workspace", S, "req"]]);
    return { kind: "vault", name: name.slice(6), workspace: p.workspace as string, params: isObject(params) ? (params as Record<string, unknown>) : {} };
  }
  if (name.startsWith("lockPrompt.") && LOCK_PROMPT_CALLS.includes(name.slice(11))) {
    read(params, [["device", S, name === "lockPrompt.state" ? "opt" : "req"]]);
    return { kind: "lockPrompt", name: name.slice(11), params: isObject(params) ? (params as Record<string, unknown>) : {} };
  }
  if (name.startsWith("lock.") && LOCK_CALLS.includes(name.slice(5))) {
    const p = read(params, [["workspace", S, "req"]]);
    return { kind: "lock", name: name.slice(5), workspace: p.workspace as string, params: isObject(params) ? (params as Record<string, unknown>) : {} };
  }
  switch (name) {
    case "auth.begin": {
      const p = read(params, [
        ["redirect_uri", S, "req"],
        ["return_to", S, "req"],
        ["device_name", S, "opt"],
      ]);
      return { kind: "authBegin", redirectUri: p.redirect_uri as string, returnTo: p.return_to as string, deviceName: p.device_name as string | null };
    }
    case "auth.complete":
      return { kind: "authComplete", query: read(params, [["query", S, "req"]]).query as string };
    case "auth.password": {
      const p = read(params, [
        ["email", S, "req"],
        ["password", S, "req"],
        ["device_name", S, "opt"],
      ]);
      return { kind: "authPassword", email: p.email as string, password: p.password as string, deviceName: p.device_name as string | null };
    }
    case "auth.signOut":
      return { kind: "signOut", account: read(params, [["account", S, "req"]]).account as string };
    case "auth.deleteAccount":
      return { kind: "deleteAccount", account: read(params, [["account", S, "req"]]).account as string };
    case "client.error": {
      const p = read(params, [
        ["source", S, "req"],
        ["message", S, "req"],
      ]);
      return { kind: "clientError", source: p.source as string, message: p.message as string };
    }
    case "client.wake": {
      const p = read(params, [
        ["away", "f64", "default"],
        ["network", "bool", "default"],
        ["retry", "bool", "default"],
      ]);
      return { kind: "wake", away: p.away as number, network: p.network as boolean, retry: p.retry as boolean };
    }
    case "push.key":
      return { kind: "pushKey" };
    case "push.register": {
      const registration = orEmpty(params);
      const kind = get(registration, "kind");
      const text = (k: string) => {
        const v = get(registration, k);
        return typeof v === "string" && v !== "";
      };
      const keys = (k: string) => {
        const v = get(get(registration, "keys"), k);
        return typeof v === "string" && v !== "";
      };
      const ok = kind === "web" ? text("endpoint") && keys("p256dh") && keys("auth") : kind === "fcm" ? text("token") : false;
      if (!ok) throw CoreError.invalid(t("core-misc.params.push_registration"));
      return { kind: "pushRegister", registration };
    }
    case "push.unregister":
      return { kind: "pushUnregister" };
    case "chat.create": {
      const p = read(params, [
        ["station", S, "req"],
        ["runtime", S, "req"],
        ["model", S, "opt"],
        ["effort", S, "opt"],
        ["profile", S, "opt"],
      ]);
      const ask: Record<string, unknown> = { runtime: p.runtime };
      for (const k of ["model", "effort", "profile"]) if (typeof p[k] === "string" && p[k] !== "") ask[k] = p[k];
      return { kind: "chatCreate", station: p.station as string, ask };
    }
  }
  const bySession = get(params, "session") !== undefined && get(params, "thread") === undefined;
  if (bySession && name === "chat.send") {
    const p = read(params, [
      ["station", S, "req"],
      ["session", S, "req"],
      ["text", S, "default"],
      ["attachments", "value", "opt"],
      ["quotes", "value", "opt"],
      ["client", S, "opt"],
    ]);
    return { kind: "chatSendTo", station: p.station as string, session: p.session as string, text: p.text as string, attachments: listOf("attachments"), ...uploadFields(), quotes: listOf("quotes"), client: p.client as string | null };
  }
  if (bySession && (name === "chat.retry" || name === "chat.discard")) {
    const p = read(params, [
      ["station", S, "req"],
      ["session", S, "req"],
      ["id", S, "req"],
    ]);
    return { kind: name === "chat.retry" ? "chatRetryIn" : "chatDiscardIn", station: p.station as string, session: p.session as string, id: p.id as string };
  }
  switch (name) {
    case "chat.send": {
      const p = send(params);
      return { kind: "chatSend", station: p.station as string, thread: p.thread as number, text: p.text as string, attachments: listOf("attachments"), ...uploadFields(), quotes: listOf("quotes"), client: p.client as string | null };
    }
    case "decision.answer": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
        ["seq", "u64", "req"],
        ["option", S, "req"],
      ]);
      const option = (p.option as string).trim();
      if (option === "") throw CoreError.invalid(t("core-misc.params.empty_option"));
      return { kind: "decisionAnswer", station: p.station as string, thread: p.thread as number, seq: p.seq as number, option };
    }
    case "decision.reply": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
        ["seq", "u64", "req"],
        ["text", S, "req"],
        ["attachments", "values", "default"],
        ["quotes", "values", "default"],
      ]);
      const text = (p.text as string).trim();
      const attachments = p.attachments as unknown[];
      const quotes = p.quotes as unknown[];
      const files = uploads();
      if (text === "" && attachments.length === 0 && files.length === 0 && quotes.length === 0) throw CoreError.invalid(t("core-misc.params.empty_reply"));
      return { kind: "decisionReply", station: p.station as string, thread: p.thread as number, seq: p.seq as number, text, attachments, ...(files.length ? { uploads: files } : {}), quotes };
    }
    case "station.updateNotice": {
      const p = read(params, [
        ["station", S, "req"],
        ["action", S, "req"],
        ["version", S, "opt"],
      ]);
      StationAddr.parse(p.station as string);
      const version = p.version as string | null;
      const action = p.action as string;
      if (!["open", "close", "dismiss"].includes(action) || (action === "dismiss" && (version === null || version === "" || new TextEncoder().encode(version).length > 200))) {
        throw CoreError.invalid(t("core-misc.call.bad_update_notice"));
      }
      return { kind: "stationUpdateNotice", station: p.station as string, action, version };
    }
    case "decision.defer": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
        ["seq", "u64", "req"],
      ]);
      return { kind: "decisionDefer", station: p.station as string, thread: p.thread as number, seq: p.seq as number };
    }
    case "chat.retry":
    case "chat.discard": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
        ["id", S, "req"],
      ]);
      return { kind: name === "chat.retry" ? "chatRetry" : "chatDiscard", station: p.station as string, thread: p.thread as number, id: p.id as string };
    }
    case "chat.older":
    case "chat.newer":
    case "chat.latest": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
      ]);
      const kind = name === "chat.older" ? "chatOlder" : name === "chat.newer" ? "chatNewer" : "chatLatest";
      return { kind, station: p.station as string, thread: p.thread as number };
    }
    case "chat.place": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
        ["seq", "u64", "opt"],
        ["offset", "f64", "opt"],
      ]);
      return { kind: "chatPlace", station: p.station as string, thread: p.thread as number, seq: p.seq as number | null, offset: p.offset as number | null };
    }
    case "chat.around": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
        ["seq", "u64", "req"],
      ]);
      return { kind: "chatAround", station: p.station as string, thread: p.thread as number, seq: p.seq as number };
    }
    case "chat.find": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
        ["query", S, "req"],
        ["bring", "bool", "opt"],
      ]);
      return { kind: "chatFind", station: p.station as string, thread: p.thread as number, query: p.query as string, bring: p.bring === true };
    }
    case "history.older": {
      const p = read(params, [
        ["station", S, "req"],
        ["key", S, "req"],
      ]);
      return { kind: "historyOlder", station: p.station as string, key: p.key as string };
    }
    case "history.detail": {
      const p = read(params, [
        ["station", S, "req"],
        ["key", S, "req"],
        ["from", "u64", "req"],
        ["to", "u64", "req"],
      ]);
      return { kind: "historyDetail", station: p.station as string, key: p.key as string, from: p.from as number, to: p.to as number };
    }
    case "station.measure":
      return { kind: "stationMeasure", station: read(params, [["station", S, "req"]]).station as string };
    case "chat.read": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
        ["seq", "u64", "req"],
      ]);
      return { kind: "chatRead", station: p.station as string, thread: p.thread as number, seq: p.seq as number };
    }
    case "shareIn.open": {
      const p = read(params, [
        ["scope", S, "req"],
        ["source", S, "req"],
        ["station", S, "req"],
        ["id", S, "opt"],
        ["title", S, "opt"],
        ["key", S, "opt"],
      ]);
      const id = typeof p.id === "string" && p.id !== "" ? p.id : null;
      return { kind: "shareIn", scope: p.scope as string, source: p.source as string, title: p.title as string | null, target: { station: p.station as string, ...(id !== null ? { id } : {}) }, key: typeof p.key === "string" && p.key.startsWith("new:") ? p.key : null };
    }
    case "newChat.pick":
    case "newChat.create":
    case "newChat.migrate":
    case "pick.set":
    case "pick.save":
    case "pick.borrow": {
      const p = orEmpty(params);
      const needs = name === "newChat.pick" ? ["scope"] : name === "newChat.create" ? ["station"] : name === "pick.set" || name === "pick.save" || name === "pick.borrow" ? ["station", "of"] : [];
      const missing = needs.find((f) => {
        const v = get(p, f);
        return typeof v !== "string" || v === "";
      });
      if (missing !== undefined) throw CoreError.invalid(t("core-misc.params.missing", { field: missing }));
      return { kind: "choose", name, params: (isObject(p) ? p : {}) as Record<string, unknown> };
    }
    case "draft.put":
    case "draft.get": {
      const p = orEmpty(params);
      const at = (field: string) => {
        const v = get(p, field);
        return typeof v === "string" && v !== "" ? v : null;
      };
      const key = at("key");
      const byKey = key !== null ? draftAt(key) : null;
      const station = byKey ? byKey[0] : at("station");
      const chat = byKey ? byKey[1] : at("chat");
      if (station === null || chat === null) throw CoreError.invalid(t("core-misc.params.key_or_chat"));
      if (name === "draft.get") return { kind: "draftGet", station, chat };
      const rest: Record<string, unknown> = isObject(p) ? { ...p } : {};
      delete rest.station;
      delete rest.chat;
      delete rest.key;
      const shaped = conform("DraftView", rest);
      if ("error" in shaped) throw CoreError.invalid(t("core-misc.params.invalid", { error: shaped.error }));
      return { kind: "draftPut", station, chat, draft: shaped.ok };
    }
    case "chat.xshare": {
      const p = read(params, [
        ["station", S, "req"],
        ["workspace", S, "opt"],
        ["session", S, "req"],
        ["thread", "u64", "opt"],
        ["to", "strings", "req"],
        ["write", "bool", "default"],
      ]);
      return { kind: "chatXshare", station: p.station as string, workspace: p.workspace as string | null, session: p.session as string, thread: p.thread as number | null, to: [...new Set(p.to as string[])], write: p.write as boolean };
    }
    case "station.join": {
      const p = read(params, [
        ["workspace", S, "req"],
        ["station", S, "req"],
        ["name", S, "opt"],
      ]);
      return { kind: "stationJoin", workspace: p.workspace as string, station: p.station as string, name: p.name as string | null };
    }
    case "chat.ref": {
      const p = read(params, [
        ["station", S, "req"],
        ["id", S, "req"],
        ["title", S, "req"],
        ["base", S, "opt"],
        ["into", S, "opt"],
      ]);
      return { kind: "chatRef", station: p.station as string, id: p.id as string, title: p.title as string, base: p.base as string | null, into: p.into as string | null };
    }
    case "chat.outsideRefs": {
      const p = read(params, [
        ["station", S, "req"],
        ["text", S, "req"],
      ]);
      return { kind: "chatOutsideRefs", station: p.station as string, text: p.text as string };
    }
    case "chat.xshareAdd": {
      const p = read(params, [
        ["station", S, "req"],
        ["id", S, "req"],
        ["workspace", S, "req"],
        ["prefer", S, "opt"],
      ]);
      return { kind: "chatXshareAdd", station: p.station as string, id: p.id as string, workspace: p.workspace as string, prefer: p.prefer as string | null };
    }
    case "chat.publishPreview": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
      ]);
      return { kind: "chatPublishPreview", station: p.station as string, thread: p.thread as number };
    }
    case "chat.publish": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
        ["upto", "u64", "req"],
        ["files", "strings", "default"],
      ]);
      return { kind: "chatPublish", station: p.station as string, thread: p.thread as number, upto: p.upto as number, files: [...new Set(p.files as string[])] };
    }
    case "chat.unpublish": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "opt"],
        ["id", S, "req"],
      ]);
      return { kind: "chatUnpublish", station: p.station as string, thread: p.thread as number | null, id: p.id as string };
    }
    case "chat.refs":
      return { kind: "chatRefsKeep", links: read(params, [["links", "pairs", "req"]]).links as [string, string][] };
    case "prefs.set": {
      const p = orEmpty(params);
      let fill = false;
      let patch = p;
      if (isObject(p)) {
        const rest = { ...p };
        fill = rest.fill === true;
        delete rest.fill;
        patch = rest;
      }
      return { kind: "prefsSet", patch, fill };
    }
    case "client.device":
      return { kind: "clientDevice", facts: orEmpty(params) };
    case "changelog.seen":
      return { kind: "changelogSeen" };
    // A file going up comes beside the call, not in it.
    case "station.upload": {
      const p = read(params, [
        ["station", S, "req"],
        ["name", S, "req"],
      ]);
      return { kind: "stationUpload", bytes: beside(bytes), station: p.station as string, name: p.name as string };
    }
    case "station.upload.part": {
      const p = read(params, [
        ["station", S, "req"],
        ["id", S, "req"],
        ["name", S, "req"],
        ["size", "u64", "req"],
        ["offset", "u64", "req"],
        ["progress", "bool", "default"],
      ]);
      return { kind: "stationUploadPart", station: p.station as string, id: p.id as string, name: p.name as string, size: p.size as number, offset: p.offset as number, bytes: beside(bytes), progress: p.progress as boolean };
    }
    case "station.file": {
      const p = read(params, [
        ["station", S, "req"],
        ["key", S, "req"],
        ["name", S, "req"],
        ["thumb", "bool", "default"],
        ["progress", "bool", "default"],
      ]);
      return { kind: "stationFile", station: p.station as string, key: p.key as string, name: p.name as string, thumb: p.thumb as boolean, progress: p.progress as boolean };
    }
    case "station.file.part": {
      const p = read(params, [
        ["station", S, "req"],
        ["key", S, "req"],
        ["name", S, "req"],
        ["offset", "u64", "req"],
        ["length", "u64", "req"],
        ["progress", "bool", "default"],
        ["stream", "bool", "default"],
      ]);
      return { kind: "stationFilePart", station: p.station as string, key: p.key as string, name: p.name as string, offset: p.offset as number, length: p.length as number, progress: p.progress as boolean, stream: p.stream as boolean };
    }
    // The station's drive (docs/drive.md): a part of a file read, a part of one written, a folder read again.
    case "drive.read": {
      const p = read(params, [
        ["station", S, "req"],
        ["root", S, "req"],
        ["path", S, "req"],
        ["offset", "u64", "req"],
        ["length", "u64", "req"],
        ["progress", "bool", "default"],
        ["stream", "bool", "default"],
      ]);
      return { kind: "driveRead", station: p.station as string, root: p.root as string, path: p.path as string, offset: p.offset as number, length: p.length as number, progress: p.progress as boolean, stream: p.stream as boolean };
    }
    case "drive.upload.part": {
      const p = read(params, [
        ["station", S, "req"],
        ["root", S, "req"],
        ["path", S, "req"],
        ["id", S, "req"],
        ["offset", "u64", "req"],
        ["total", "u64", "req"],
        ["replace", "bool", "default"],
      ]);
      return {
        kind: "driveUploadPart", station: p.station as string, root: p.root as string, path: p.path as string, id: p.id as string, offset: p.offset as number, total: p.total as number,
        replace: p.replace as boolean, bytes: beside(bytes),
      };
    }
    // Where a file of a drive was left (a book's place, a video's time): kept on this device, its `drivePlace`.
    case "drive.place": {
      const p = read(params, [
        ["station", S, "req"],
        ["root", S, "req"],
        ["path", S, "req"],
        ["at", "f64", "req"],
        ["of", "f64", "opt"],
      ]);
      return { kind: "drivePlace", station: p.station as string, root: p.root as string, path: p.path as string, at: p.at as number, of: (p.of as number | null) ?? null };
    }
    case "machineLogin.open": {
      const p = read(params, [
        ["station", S, "req"],
        ["id", S, "req"],
        ["here", "bool", "default"],
      ]);
      return { kind: "machineLoginOpen", station: p.station as string, id: p.id as string, here: p.here === true };
    }
    case "drive.refresh": {
      const p = read(params, [
        ["station", S, "req"],
        ["root", S, "req"],
        ["path", S, "default"],
      ]);
      return { kind: "driveRefresh", station: p.station as string, root: p.root as string, path: p.path as string };
    }
    // A file a message names, whole, its bytes beside the answer (as the station's op, from before, put them in it).
    case "file.open": {
      const p = read(params, [
        ["station", S, "req"],
        ["key", S, "req"],
        ["path", S, "req"],
      ]);
      return { kind: "fileOpen", station: p.station as string, key: p.key as string, path: p.path as string };
    }
    case "station.poster": {
      const p = read(params, [
        ["station", S, "req"],
        ["key", S, "req"],
        ["name", S, "req"],
      ]);
      return { kind: "stationPoster", station: p.station as string, key: p.key as string, name: p.name as string };
    }
    case "cache.usage":
      return { kind: "cacheUsage" };
    case "cache.clear": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
      ]);
      return { kind: "cacheClear", station: p.station as string, thread: p.thread as number };
    }
    case "station.preview": {
      const p = read(params, [
        ["station", S, "req"],
        ["port", "u16", "req"],
        ["method", S, "req"],
        ["path", S, "req"],
        ["headers", "pairs", "default"],
        ["stream", "bool", "default"],
      ]);
      // Its body, if it has one, beside the call.
      return {
        kind: "stationPreview",
        body: bytes ?? new Uint8Array(),
        station: p.station as string,
        port: p.port as number,
        method: p.method as string,
        path: p.path as string,
        headers: p.headers as [string, string][],
        stream: p.stream as boolean,
      };
    }
    case "preview.socket": {
      const p = read(params, [
        ["station", S, "req"],
        ["port", "u16", "req"],
        ["path", S, "req"],
        ["headers", "pairs", "default"],
        ["socket", S, "req"],
      ]);
      return { kind: "previewSocket", station: p.station as string, port: p.port as number, path: p.path as string, headers: p.headers as [string, string][], socket: p.socket as string };
    }
    case "preview.socket.send": {
      const p = read(params, [
        ["socket", S, "req"],
        ["text", S, "opt"],
        ["binary", "bool", "default"],
        ["close", "close", "opt"],
      ]);
      // A binary frame's bytes beside the call (`binary: true`).
      const given = [p.text !== null, p.binary === true, p.close !== null].filter(Boolean).length;
      if (given !== 1) throw CoreError.invalid(t("core-misc.params.one_frame"));
      const frame: SocketFrame = p.text !== null ? { text: p.text as string } : p.binary === true ? { binary: beside(bytes) } : { close: p.close as [number, string] };
      return { kind: "previewSocketSend", socket: p.socket as string, frame };
    }
    case "migrate": {
      const p = read(params, [
        ["accounts", "value", "opt"],
        ["device", S, "opt"],
      ]);
      let device: Uint8Array | null = null;
      if (p.device !== null) {
        device = b64(p.device as string, "core-misc.call.base64.device_key");
        if (device.length !== 32) throw CoreError.invalid(t("core-misc.params.device_key_size"));
      }
      return { kind: "migrate", accounts: p.accounts === null ? null : p.accounts, device };
    }
  }
  if (name === "profile.put" && get(get(params, "input"), "models") !== undefined) {
    const op = ops.request(name, params)!;
    const models = get(get(params, "input"), "models");
    if (!Array.isArray(models) || !models.every((m) => typeof m === "string")) throw CoreError.invalid(t("core-misc.params.bad_models"));
    const id = get(params, "id");
    return { kind: "profileModels", op, id: typeof id === "string" ? id : "", models };
  }
  if (name === "chat.archive") {
    const p = orEmpty(params);
    const op = ops.request(name, p)!;
    const session = get(p, "session");
    const thread = get(p, "thread");
    return { kind: "chatArchive", op, thread: typeof thread === "number" && Number.isInteger(thread) && thread >= 0 ? thread : null, session: typeof session === "string" ? session : "", archived: get(p, "archived") === true };
  }
  if (name === "chat.rename" || name === "chat.pin" || name === "chat.keep") {
    const p = orEmpty(params);
    const op = ops.request(name, p)!;
    const session = get(p, "session");
    const thread = get(p, "thread");
    const rawTitle = get(p, "title");
    const title = name === "chat.rename" ? (typeof rawTitle === "string" ? rawTitle : "").trim() : "";
    return {
      kind: "chatChange",
      op,
      thread: typeof thread === "number" && Number.isInteger(thread) && thread >= 0 ? thread : null,
      session: typeof session === "string" ? session : "",
      title: name === "chat.rename" && title !== "" ? title : null,
      pinned: name === "chat.pin" ? get(p, "pinned") === true : null,
      keep: name === "chat.keep" ? get(p, "kept") !== false : null,
    };
  }
  const p = orEmpty(params);
  const adb = parseAdb(name, p);
  if (adb) return { kind: "adb", call: adb };
  const screen = parseScreen(name, p, bytes);
  if (screen) return { kind: "screen", call: screen };
  const ask = parseAsk(name, p);
  if (ask) return { kind: "ask", ask };
  const op = ops.request(name, p);
  if (op) return { kind: "op", op };
  const held = modules ? parseModuleCall(modules, name, params, bytes) : null;
  if (held) return { kind: "module", name, call: held };
  throw new CoreError("unknown_call", t("core-misc.call.unknown", { name }));
}

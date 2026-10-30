// Named calls and their input validation (core/calls.rs); execution stays in the core (execute.ts).
import { parseAdb, type AdbCall } from "../adb-parse.ts";
import { parseAsk, type Ask } from "../asks-parse.ts";
import { parseAttend, type AttendCall } from "../attend-parse.ts";
import { parseScreen, type ScreenCall } from "../screens.ts";
import type { FontsCall } from "../font-files.ts";
import { parseComposer, type ComposerAct } from "../composer.ts";
import { conform } from "../conform.ts";
import { type HeldCall, type ModuleCall, parseModuleCall } from "../module.ts";
import type { KeepKind } from "../drive-kept.ts";
import { CALLS as BROWSE_CALLS } from "../drive-browse.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import * as keymap from "../keymap.ts";
import * as ops from "../ops.ts";
import type { Topic } from "../protocol.ts";
import { draftAt } from "../refs.ts";
import { StationAddr } from "../station/addr.ts";
import type { FindAt, FindHit } from "../chat-find.ts";
import { readConnects, readPeople, type RelayConnect, type RelayPerson } from "../relay-pick.ts";
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
  | { kind: "widgetState"; op: ops.Request; key: string; path: string; state: unknown | undefined }
  | { kind: "chatXshare"; station: string; workspace: string | null; session: string; thread: number | null; to: string[]; write: boolean }
  | { kind: "stationJoin"; workspace: string; station: string; name: string | null }
  | { kind: "chatSend"; station: string; thread: number; text: string; attachments: unknown; uploads?: { id: string; name: string; size: number; width?: number; height?: number }[]; quotes: unknown; client: string | null }
  | { kind: "chatCreate"; station: string; ask: Record<string, unknown> }
  | { kind: "shareIn"; scope: string; source: string; title: string | null; target: { station: string; id?: string }; key: string | null }
  | { kind: "chatSendTo"; station: string; session: string; text: string; attachments: unknown; uploads?: { id: string; name: string; size: number; width?: number; height?: number }[]; quotes: unknown; client: string | null }
  | { kind: "decisionAnswer"; station: string; thread: number; seq: number; option: string }
  | { kind: "decisionReply"; station: string; thread: number; seq: number; text: string; attachments: unknown; uploads?: { id: string; name: string; size: number; width?: number; height?: number }[]; quotes: unknown }
  | { kind: "decisionDismiss"; op: ops.Request; station: string; thread: number; seq: number }
  /// A chat's side-panel tabs changed (chat-tabs.ts): by the key they are kept under, the tab.
  | { kind: "chatTabs"; chat: string; action: "open" | "close" | "front" | "clear"; tab: string | null; auto: boolean }
  | { kind: "chatRetryIn"; station: string; session: string; id: string }
  | { kind: "chatDiscardIn"; station: string; session: string; id: string }
  | { kind: "chatRetry"; station: string; thread: number; id: string }
  | { kind: "chatDiscard"; station: string; thread: number; id: string }
  | { kind: "chatOlder"; station: string; thread: number }
  | { kind: "chatNewer"; station: string; thread: number }
  | { kind: "chatLatest"; station: string; thread: number }
  | { kind: "chatPlace"; station: string; thread: number; seq: number | null; offset: number | null }
  | { kind: "chatCc"; station: string; thread: number; to: number; on: boolean }
  | { kind: "chatAround"; station: string; thread: number; seq: number }
  | { kind: "chatFind"; station: string; thread: number; query: string; bring: boolean }
  | { kind: "historyOlder"; station: string; key: string }
  | { kind: "historyDetail"; station: string; key: string; from: number; to: number }
  | { kind: "stationMeasure"; station: string }
  | { kind: "stationUpdateNotice"; station: string; action: string; version: string | null }
  | { kind: "chatRead"; station: string; thread: number; seq: number }
  | { kind: "stationUpload"; station: string; name: string; bytes: Uint8Array }
  | { kind: "stationUploadPart"; station: string; id: string; name: string; size: number; offset: number; bytes: Uint8Array; progress: boolean }
  /// `keep` with the file's `size` as its message says: what is read kept on the device, with its chat, and what is
  /// kept answered (drive-kept.ts `chat`); without a size, nothing kept.
  /// `from`: where it was opened (KeptFrom: its chat, the file as its message has it), kept with it while it is kept, so
  /// what lists it (`downloads`' `keeping`, a download) leads back there.
  | { kind: "stationFile"; station: string; key: string; name: string; thumb: boolean; progress: boolean; keep: number | null; from?: unknown }
  /// `quiet`: the core's own (fill.ts), in the background: not waited on, and nothing a viewer let go.
  | { kind: "stationFilePart"; station: string; key: string; name: string; offset: number; length: number; progress: boolean; stream: boolean; keep: number | null; quiet?: boolean; from?: unknown }
  | { kind: "stationPoster"; station: string; key: string; name: string }
  | { kind: "fileOpen"; station: string; key: string; path: string; range: { offset: number; length: number } | null }
  /// `keep`: what is read kept on the device and what is kept answered (drive-kept.ts), the file as its folder said it
  /// is (`mtime`, `size`; neither said, nothing kept).
  /// `quiet`: as a chat's file's part's.
  | { kind: "driveRead"; station: string; root: string; path: string; offset: number; length: number; progress: boolean; stream: boolean; keep: KeepKind | null; mtime: number | null; size: number | null; quiet?: boolean; from?: unknown }
  | { kind: "driveUploadPart"; station: string; root: string; path: string; id: string; offset: number; total: number; replace: boolean; bytes: Uint8Array }
  | { kind: "driveRefresh"; station: string; root: string; path: string }
  /// A login's page to open (docs/remote-login.md): a loopback login's callback listened for here first, unless the
  /// station is this machine (`here`).
  | { kind: "machineLoginOpen"; station: string; id: string; here: boolean }
  | { kind: "drivePlace"; station: string; root: string; path: string; at: number; of: number | null }
  | { kind: "cacheUsage" }
  /// The colours of code a client holds itself (highlight.ts): code in Markdown it read, a tool's, a file's.
  | { kind: "codeInk"; code: string; lang: string }
  /// Markdown a client holds itself read by the core (markdown.ts): a file's, a memory's.
  | { kind: "markdown"; text: string }
  /// A text file as a reader shows it (reader.ts): the text, decoded by the client (in `text`, or its UTF-8 beside the
  /// call); `withText`: the text as joined in the answer too (else `reader.text` gives it).
  | { kind: "readerBook"; text: string; markdown: boolean; withText: boolean; tree: boolean }
  /// A kept book's text as joined, its UTF-8 beside the answer.
  | { kind: "readerText"; id: number }
  /// Where words are in a kept book.
  | { kind: "readerSearch"; id: number; query: string; limit: number }
  | { kind: "cacheClear"; station: string; thread: number }
  /// What the device keeps of the drives' files let go (drive-kept.ts).
  | { kind: "driveKeptClear" }
  /// A chat's file kept on the device let go (drive-kept.ts `chat`).
  | { kind: "cacheFileClear"; station: string; key: string; name: string }
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
  | { kind: "chatOutsideShare"; station: string; text: string }
  | { kind: "chatXshareAdd"; station: string; id: string; workspace: string; prefer: string | null }
  /// A chat made public (views/publish.ts): what a snapshot would hold, one kept, one revoked.
  | { kind: "chatPublishPreview"; station: string; thread: number; turn: number | null }
  | { kind: "chatPublish"; station: string; thread: number; upto: number; files: string[] }
  | { kind: "chatUnpublish"; station: string; thread: number | null; id: string }
  | { kind: "chatRefsKeep"; links: [string, string][] }
  | { kind: "choose"; name: string; params: Record<string, unknown> }
  | { kind: "prefsSet"; patch: unknown; fill: boolean }
  /// An action's keys changed on this device (keymap.ts): bindings as the keymap has them; null its own again; no
  /// action, every one's.
  | { kind: "keysSet"; action: string | null; keys: string[] | null }
  | { kind: "clientDevice"; facts: unknown }
  | { kind: "changelogSeen" }
  | { kind: "commandsFind"; query: string; offered: unknown[] }
  /// What a chat's relay picker shows (relay-pick.ts): the connects read, what was typed, all asked for, the bot picked.
  | { kind: "relayView"; connects: RelayConnect[]; query: string; all: boolean; bot: string | null }
  /// Who its note can mention now (relay-pick.ts): the people of the place picked, the note as written.
  | { kind: "relayMentions"; people: RelayPerson[]; note: string }
  /// A history step's call and what came back, read by what they are (tool-step.ts).
  | { kind: "historyTool"; name: string; call: string; result: string | null; failed: boolean; said: boolean }
  /// Where a chat's find goes (chat-find.ts): what was found, where the reader is, which way, what the view shows.
  | { kind: "chatFindGo"; hits: FindHit[]; at: FindAt | null; by: -1 | 0 | 1; from: number | null; to: number | null; drawn: Record<string, number> }
  | { kind: "words"; what: "ref.at" | "ref.before" | "ref.marks" | "ref.pasted" | "paste.info" | "drive.check"; text: string; caret: number; here: string }
  /// A face's files on a device that keeps none of its own (font-files.ts): fetched, kept, given back.
  | { kind: "fonts"; call: FontsCall }
  | { kind: "ask"; ask: Ask }
  | { kind: "adb"; call: AdbCall }
  /// A station's screen seen and driven (screens.ts): `screen.view` and what goes on it.
  | { kind: "screen"; call: ScreenCall }
  /// The workspace lock (views/lock.ts): `lock.<name>` on a workspace, with what it takes.
  | { kind: "lock"; name: string; workspace: string; params: Record<string, unknown> }
  | { kind: "lockPrompt"; name: string; params: Record<string, unknown> }
  /// The vault (views/vault.ts): `vault.<name>` on a workspace, with what it takes.
  | { kind: "vault"; name: string; workspace: string; params: Record<string, unknown> }
  | { kind: "driveTransfer"; action: "start" | "cancel" | "retry"; params: Record<string, unknown> }
  /// A station's files as they are browsed (views/browse.ts): `drive.browse` and the rest of drive-browse.ts's CALLS,
  /// with what each takes.
  | { kind: "browse"; name: string; params: Record<string, unknown> }
  /// A chat's file downloaded to this device (views/downloads.ts): its params read there.
  | { kind: "download"; action: "start" | "retry" | "take" | "read" | "done" | "cancel"; params: Record<string, unknown> }
  /// What was opened and let go, brought after everything else (fill.ts): one no longer brought (`fill.stop {id}`), or
  /// all (`fill.stopAll`), what was kept of each let go.
  | { kind: "fill"; action: "stop" | "stopAll"; params: Record<string, unknown> }
  /// An app's module's call (module.ts): `<module>.<name>`, its params as the module checked them.
  | { kind: "module"; name: string; call: HeldCall };

/// Where a file read was opened (`from`, as KeptFrom has it), as a call has it; none where it says none, or one that
/// is not that.
function fromOf(params: unknown): { from?: unknown } {
  const from = isObject(params) ? (params as Record<string, unknown>).from : undefined;
  if (from === undefined || from === null) return {};
  const shaped = conform("KeptFrom", from);
  return "ok" in shaped ? { from: shaped.ok } : {};
}

/// Whether a UI can cancel it (`{id, cancel}`), and one gone does: the calls that hold something open for a page, and
/// those that hand it what they read as it comes (`stream`: a player's part of a file, let go of as it seeks elsewhere
/// or closes), so that nothing no page waits for any more goes on coming over the network.
export function cancellable(call: Call): boolean {
  if (call.kind === "module") return call.call.def.cancellable === true;
  return ((call.kind === "stationPreview" || call.kind === "stationFilePart" || call.kind === "driveRead") && call.stream) || call.kind === "previewSocket" || (call.kind === "screen" && call.call.kind === "view");
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
    case "widgetState":
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
      return ["config", "make", "verify", "register", "create"].includes(call.action);
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
    case "decisionDismiss":
      return true;
    case "wake":
      return call.retry;
    case "choose":
      return call.name === "pick.save" || call.name === "pick.borrow" || call.name === "pick.repick";
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
/// What a part of a file a message names (`file.open` with `offset`) is when no `length` is asked.
const FILE_OPEN_PART = 4 * 1024 * 1024;

/// The vault's calls (views/vault.ts).
export const VAULT_CALLS = ["state", "lock", "setup", "create", "delete", "addDevice", "putItem", "deleteItem", "open", "recover", "approve", "deny", "setLasts", "migrate"];

/// The workspace lock's calls (views/lock.ts).
export const LOCK_CALLS = ["state", "open", "toggle", "dismiss", "request", "confirm", "deny", "addStation", "joinStation", "renew", "removeDevice", "disable", "pair", "pairCode", "pairCancel"];

/// The calls on a new device showing this one's code (views/pair.ts, `lockPrompts`).
export const LOCK_PROMPT_CALLS = ["deny", "hide", "state"];

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
    ["connect.flow.", ["open", "edit", "go", "config", "make", "verify", "register", "create", "drop"], "connectFlow", "connectFlow"],
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
  // Copies into a station's drive (views/transfers.ts): its params read there.
  if (name === "drive.transfer" || name === "drive.transfer.cancel" || name === "drive.transfer.retry") {
    return { kind: "driveTransfer", action: name === "drive.transfer" ? "start" : name === "drive.transfer.cancel" ? "cancel" : "retry", params: isObject(params) ? (params as Record<string, unknown>) : {} };
  }
  // A station's files as they are browsed (views/browse.ts): their params read there.
  if (BROWSE_CALLS.includes(name)) return { kind: "browse", name, params: isObject(params) ? (params as Record<string, unknown>) : {} };
  // A chat's file downloaded to this device (views/downloads.ts): its params read there.
  if (name === "download.start" || name === "download.retry" || name === "download.take" || name === "download.read" || name === "download.done" || name === "download.cancel") {
    return { kind: "download", action: name.slice(9) as "start" | "retry" | "take" | "read" | "done" | "cancel", params: isObject(params) ? (params as Record<string, unknown>) : {} };
  }
  if (name === "fill.stop" || name === "fill.stopAll") return { kind: "fill", action: name === "fill.stop" ? "stop" : "stopAll", params: isObject(params) ? (params as Record<string, unknown>) : {} };
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
      const ok = kind === "web" ? text("endpoint") && keys("p256dh") && keys("auth") : kind === "fcm" || kind === "apns" ? text("token") : false;
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
    case "chat.tabs.open":
    case "chat.tabs.close":
    case "chat.tabs.front":
    case "chat.tabs.clear": {
      const action = name.slice("chat.tabs.".length) as "open" | "close" | "front" | "clear";
      const p = read(params, [
        ["chat", S, "req"],
        ["tab", S, action === "clear" ? "opt" : "req"],
        ["auto", "bool", "opt"],
      ]);
      if (p.chat === "") throw CoreError.invalid(t("core-misc.params.missing", { field: "chat" }));
      if (action !== "clear" && p.tab === "") throw CoreError.invalid(t("core-misc.params.missing", { field: "tab" }));
      return { kind: "chatTabs", chat: p.chat as string, action, tab: action === "clear" ? null : (p.tab as string), auto: p.auto !== false };
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
    case "chat.cc": {
      const p = read(params, [
        ["station", S, "req"],
        ["thread", "u64", "req"],
        ["to", "u64", "req"],
        ["on", "bool", "req"],
      ]);
      return { kind: "chatCc", station: p.station as string, thread: p.thread as number, to: p.to as number, on: p.on as boolean };
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
    case "pick.repick":
    case "pick.borrow": {
      const p = orEmpty(params);
      const needs = name === "newChat.pick" ? ["scope"] : name === "newChat.create" ? ["station"] : name.startsWith("pick.") ? ["station", "of"] : [];
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
    case "chat.outsideShare": {
      const p = read(params, [
        ["station", S, "req"],
        ["text", S, "req"],
      ]);
      return { kind: "chatOutsideShare", station: p.station as string, text: p.text as string };
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
        ["turn", "u64", "opt"],
      ]);
      return { kind: "chatPublishPreview", station: p.station as string, thread: p.thread as number, turn: p.turn as number | null };
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
    case "keys.set": {
      const p = read(params, [
        ["action", S, "opt"],
        ["keys", "strings", "opt"],
      ]);
      const action = p.action as string | null;
      if (action !== null && !(action in keymap.ACTIONS)) throw CoreError.invalid(t("core-misc.params.invalid", { error: `action: ${action}` }));
      if (action === null && p.keys !== null) throw CoreError.invalid(t("core-misc.params.invalid", { error: "action" }));
      const keys = p.keys === null ? null : (p.keys as string[]).map((said) => {
        const b = keymap.binding(said);
        if (b === null) throw CoreError.invalid(t("core-misc.params.invalid", { error: `keys: ${said}` }));
        return b;
      });
      return { kind: "keysSet", action, keys: keys && [...new Set(keys)] };
    }
    case "client.device":
      return { kind: "clientDevice", facts: orEmpty(params) };
    case "changelog.seen":
      return { kind: "changelogSeen" };
    case "history.tool": {
      const p = read(params, [
        ["name", S, "req"],
        ["call", S, "req"],
        ["result", S, "opt"],
        ["failed", "bool", "default"],
        ["said", "bool", "default"],
      ]);
      return { kind: "historyTool", name: p.name as string, call: p.call as string, result: p.result as string | null, failed: p.failed as boolean, said: p.said as boolean };
    }
    // What is written, read as every client reads it (refLinks.ts refAt, markBefore, marksIn, pastedRefs; pasted.ts;
    // drive.ts nameProblem: a name typed for a file or folder, `text`).
    case "ref.at":
    case "ref.before":
    case "ref.marks":
    case "ref.pasted":
    case "paste.info":
    case "drive.check": {
      const p = read(params, [
        ["text", S, "default"],
        ["caret", "f64", "opt"],
        ["here", S, "default"],
      ]);
      const text = p.text as string;
      const caret = p.caret === null ? text.length : Math.max(0, Math.min(text.length, Math.floor(p.caret as number)));
      return { kind: "words", what: name as Extract<Call, { kind: "words" }>["what"], text, caret, here: p.here as string };
    }
    case "chat.find.go": {
      const p = read(params, [
        ["hits", "values", "default"],
        ["at", "value", "opt"],
        ["by", "value", "req"],
        ["from", "f64", "opt"],
        ["to", "f64", "opt"],
        ["drawn", "value", "opt"],
      ]);
      const bad = (what: string) => CoreError.invalid(t("core-misc.params.invalid", { error: what }));
      const num = (v: unknown, what: string) => {
        if (typeof v !== "number" || !Number.isFinite(v)) throw bad(what);
        return v;
      };
      const by = p.by;
      if (by !== -1 && by !== 0 && by !== 1) throw bad("by");
      const hits = (p.hits as unknown[]).map((h) => (isObject(h) ? { seq: num(h.seq, "hits"), count: num(h.count, "hits") } : (() => { throw bad("hits"); })()));
      const at = p.at === null ? null : isObject(p.at) ? { seq: num(p.at.seq, "at"), k: num(p.at.k, "at") } : (() => { throw bad("at"); })();
      const drawn: Record<string, number> = {};
      if (p.drawn !== null) {
        if (!isObject(p.drawn)) throw bad("drawn");
        for (const [seq, n] of Object.entries(p.drawn)) drawn[seq] = num(n, "drawn");
      }
      return { kind: "chatFindGo", hits, at, by, from: p.from as number | null, to: p.to as number | null, drawn };
    }
    case "chat.relayView": {
      const p = read(params, [
        ["connects", "values", "default"],
        ["query", S, "default"],
        ["all", "bool", "opt"],
        ["bot", S, "opt"],
      ]);
      return { kind: "relayView", connects: readConnects(p.connects), query: p.query as string, all: p.all === true, bot: p.bot as string | null };
    }
    case "chat.relayMentions": {
      const p = read(params, [
        ["people", "values", "default"],
        ["note", S, "default"],
      ]);
      return { kind: "relayMentions", people: readPeople(p.people), note: p.note as string };
    }
    case "commands.find": {
      const p = read(params, [
        ["query", S, "default"],
        ["offered", "values", "default"],
      ]);
      return { kind: "commandsFind", query: p.query as string, offered: p.offered as unknown[] };
    }
    case "fonts.fetch":
    case "fonts.preview": {
      const id = read(params, [["id", S, "req"]]).id as string;
      return { kind: "fonts", call: name === "fonts.fetch" ? { kind: "fetch", id } : { kind: "preview", id } };
    }
    // The file the app unzipped comes beside the call.
    case "fonts.file":
    case "fonts.keep": {
      const sha256 = read(params, [["sha256", S, "req"]]).sha256 as string;
      return { kind: "fonts", call: name === "fonts.file" ? { kind: "file", sha256 } : { kind: "keep", sha256, bytes: beside(bytes) } };
    }
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
        ["keep", "bool", "default"],
        ["size", "f64", "opt"],
      ]);
      return {
        kind: "stationFile", station: p.station as string, key: p.key as string, name: p.name as string, thumb: p.thumb as boolean, progress: p.progress as boolean,
        keep: p.keep && !p.thumb && p.size !== null ? (p.size as number) : null, ...fromOf(params),
      };
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
        ["keep", "bool", "default"],
        ["size", "f64", "opt"],
      ]);
      return {
        kind: "stationFilePart", station: p.station as string, key: p.key as string, name: p.name as string, offset: p.offset as number, length: p.length as number, progress: p.progress as boolean, stream: p.stream as boolean,
        keep: p.keep && p.size !== null ? (p.size as number) : null, ...fromOf(params),
      };
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
        ["keep", S, "opt"],
        ["mtime", "f64", "opt"],
        ["size", "f64", "opt"],
      ]);
      if (p.keep !== null && p.keep !== "file" && p.keep !== "played") throw CoreError.invalid(`keep: ${String(p.keep)}`);
      const said = p.keep !== null && p.mtime !== null && p.size !== null;
      return {
        kind: "driveRead", station: p.station as string, root: p.root as string, path: p.path as string, offset: p.offset as number, length: p.length as number, progress: p.progress as boolean, stream: p.stream as boolean,
        keep: said ? (p.keep as KeepKind) : null, mtime: said ? (p.mtime as number) : null, size: said ? (p.size as number) : null, ...fromOf(params),
      };
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
    // A file a message names, whole, its bytes beside the answer (as the station's op, from before, put them in it);
    // with `offset` and `length`, a part of it.
    case "file.open": {
      const p = read(params, [
        ["station", S, "req"],
        ["key", S, "req"],
        ["path", S, "req"],
        ["offset", "u64", "opt"],
        ["length", "u64", "opt"],
      ]);
      const range = p.offset === null && p.length === null ? null : { offset: (p.offset as number | null) ?? 0, length: (p.length as number | null) ?? FILE_OPEN_PART };
      return { kind: "fileOpen", station: p.station as string, key: p.key as string, path: p.path as string, range };
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
    case "code.ink": {
      const p = read(params, [
        ["code", S, "req"],
        ["lang", S, "req"],
      ]);
      return { kind: "codeInk", code: p.code as string, lang: p.lang as string };
    }
    case "markdown":
      return { kind: "markdown", text: read(params, [["text", S, "req"]]).text as string };
    case "reader.book": {
      const p = read(params, [
        ["markdown", "bool", "default"],
        ["text", S, "opt"],
        ["withText", "bool", "default"],
        ["tree", "bool", "default"],
      ]);
      const text = (p.text as string | undefined) ?? new TextDecoder().decode(beside(bytes));
      return { kind: "readerBook", text, markdown: p.markdown as boolean, withText: p.withText as boolean, tree: p.tree as boolean };
    }
    case "reader.text":
      return { kind: "readerText", id: read(params, [["id", "u64", "req"]]).id as number };
    case "reader.search": {
      const p = read(params, [
        ["id", "u64", "req"],
        ["query", S, "req"],
        ["limit", "u64", "opt"],
      ]);
      return { kind: "readerSearch", id: p.id as number, query: p.query as string, limit: (p.limit as number | undefined) ?? 500 };
    }
    case "drive.kept.clear":
      return { kind: "driveKeptClear" };
    case "cache.file.clear": {
      const p = read(params, [
        ["station", S, "req"],
        ["key", S, "req"],
        ["name", S, "req"],
      ]);
      return { kind: "cacheFileClear", station: p.station as string, key: p.key as string, name: p.name as string };
    }
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
  // What a visualization's widget kept, read (`state` undefined) or kept: kept on the device as well (station/calls.ts
  // widgetState).
  if (name === "widget.state" || name === "widget.setState") {
    const p = orEmpty(params);
    const op = ops.request(name, p)!;
    const [key, path] = [get(p, "key"), get(p, "path")];
    return { kind: "widgetState", op, key: typeof key === "string" ? key : "", path: typeof path === "string" ? path : "", state: name === "widget.state" ? undefined : (get(p, "state") ?? null) };
  }
  if (name === "chat.archive") {
    const p = orEmpty(params);
    const op = ops.request(name, p)!;
    const session = get(p, "session");
    const thread = get(p, "thread");
    return { kind: "chatArchive", op, thread: typeof thread === "number" && Number.isInteger(thread) && thread >= 0 ? thread : null, session: typeof session === "string" ? session : "", archived: get(p, "archived") === true };
  }
  if (name === "decision.dismiss") {
    const p = orEmpty(params);
    const op = ops.request(name, p)!;
    return { kind: "decisionDismiss", op, station: "station" in op.target ? op.target.station : "", thread: get(p, "thread") as number, seq: get(p, "seq") as number };
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

// What the UIs can have done on a station or on still.fail cloud, each by its name (ops.rs). A UI never makes a request
// itself: it names what it wants done and with what, and the core knows the request that does it and what it changes
// (the effects declared beside each operation).
import { CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { utf8 } from "./util.ts";

/// Where an operation goes: a station (its address), or still.fail cloud as a signed-in account.
export type Target = { station: string } | { cloud: string };

/// How a successful station operation updates its live topics.
export type Effect =
  | { kind: "none" }
  | { kind: "session"; key: string | null }
  /// What its process does (warm, stopped, let go): its station tells the lists that show it as they change.
  | { kind: "process"; key: string }
  | { kind: "thread"; archived: boolean }
  | { kind: "connect"; id: string | null }
  | { kind: "overview" }
  | { kind: "footprint" }
  | { kind: "slack" }
  | { kind: "job" }
  /// The agents' memory (the `memory` topic): read again.
  | { kind: "memory" }
  /// The programs granted the station's data (the `outflowGrants` topic, docs/data-outflow.md): read again.
  | { kind: "outflowGrants" }
  | { kind: "identity" }
  /// Folders of the station's drive under `root` (paths relative to it): read again where held or shown.
  | { kind: "drive"; root: string; paths: string[] }
  /// A station's logins (docs/remote-login.md): the login answered with is put in place at once.
  | { kind: "machineLogins" }
  /// A sign-in for a new profile (the overview's `logins`) started, given its code or dropped: as the station answered,
  /// in place at once until the overview says as much. `id`: the login's (null: the answer names it, as it starts);
  /// `from`: the state the step moves it on from (null: not listed yet).
  | { kind: "login"; id: string | null; from: string | null };

/// The request an operation makes.
export type Request = {
  target: Target;
  method: string;
  path: string;
  body: unknown | null;
  /// Made instead when the first one is a 404: what a station from before the first one knew.
  fallback: Request | null;
  effect: Effect;
};

/// Percent-encodes a path segment like encodeURIComponent (station.rs `encode`).
export function encode(text: string): string {
  let out = "";
  for (const b of utf8(text)) {
    const c = String.fromCharCode(b);
    if (/[A-Za-z0-9\-_.!~*'()]/.test(c)) out += c;
    else out += `%${b.toString(16).toUpperCase().padStart(2, "0")}`;
  }
  return out;
}

const CLOUD_SERVICES = ["workspace", "invitation", "loginSession", "admin"];

/// What each operation takes (`field:type`, `field?:type` when it may be left out; types: string, number, boolean,
/// strings, json), station operations first: the contract the UIs' bindings are made from (scripts/operations.ts:
/// web/src/core/operations.ts, the Android app's data/Operations.kt). It names exactly what `request` reads of the
/// params (test/ops.test.ts checks it), besides `station` and `account`.
export const PARAMS: Record<string, string> = {
  "session.stop": "key:string",
  "tools.access": "",
  "tools.setAccess": "access:string",
  "station.modules": "",
  "station.module.set": "id:string enabled:boolean",
  "agentEnv.set": "env?:json text?:string",
  "search.setPersonal": "personal:boolean",
  "network.setCongestion": "congestion:string",
  "station.restart": "",
  "context.setAfresh": "afreshWhenCold:boolean",
  "diagnostics.setLogs": "logs:boolean",
  "elevation.set": "on:boolean",
  "session.warm": "key:string",
  "session.evict": "key:string",
  "session.compact": "key:string",
  "session.clear": "key:string readBack?:boolean",
  "session.delete": "key:string",
  "session.settings": "key:string profile?:string model?:string effort?:string fast?:boolean repick?:boolean afresh?:boolean",
  "chat.archive": "archived?:boolean session:string thread?:number",
  "chat.keep": "kept?:boolean thread:number",
  "chat.rename": "session?:string title?:string thread?:number",
  "chat.pin": "pinned?:boolean session:string",
  "chat.relayPlaces": "thread:number",
  "chat.relay": "thread:number connect?:string channel?:string link?:string note?:string",
  "chat.relayPeople": "thread:number connect?:string channel?:string link?:string",
  "decision.dismiss": "thread:number seq:number",
  "decision.close": "thread:number seq:number option:string",
  "chat.report": "thread:number seq:number",
  "session.new": "runtime?:string profile?:string model?:string effort?:string fast?:boolean",
  "chats.archived": "",
  "chat.forSession": "session?:string",
  "widget.state": "key:string path:string",
  "session.transcript": "key:string",
  "file.peek": "key:string path:string line?:number",
  "link.preview": "url:string",
  "widget.setState": "key:string path?:string state?:json",
  "machineSessions.list": "",
  "machineSessions.read": "runtime:string id:string limit?:number",
  "machineSessions.continue": "runtime?:string id?:string",
  "automaticDecisions.save": "input:json",
  "automaticDecisions.refresh": "",
  "automaticDecisions.review": "",
  "automaticDecisions.policy": "input:json",
  "archiving.save": "days:number reviewed:boolean slackDays:number",
  "connect.create": "input?:json id?:string",
  "connect.put": "id:string input?:json",
  "connect.delete": "id:string",
  "connect.reconnect": "id:string",
  "connect.bindSession": "connect:string session?:string title?:string",
  "connect.putSlackApp": "connect:string input?:json from?:json",
  "feishu.register": "domain?:string name?:string",
  "feishu.cancelRegistration": "id:string",
  "feishu.verify": "appId:string appSecret:string domain?:string",
  "feishu.createConnect": "feishu:json bind?:json mode?:string requireMention?:boolean owner?:json",
  "feishu.putSecret": "id:string appSecret:string",
  "slack.verify": "connect?:string install?:string appToken?:string botToken?:string",
  "slack.makeApp": "team?:string settings?:json icon?:string",
  "slack.dropApp": "appId:string",
  "slack.installed": "code?:string state?:string",
  "slack.addConfigToken": "refreshToken?:string",
  "slack.removeConfigToken": "team:string",
  "slack.people": "",
  "slack.createAppUrl": "name:string",
  "slack.identity": "bound?:boolean user:string",
  "profile.add": "runtime?:string access?:json",
  "profile.useMachineLogin": "runtime?:string",
  "profile.put": "id:string input?:json",
  "profile.addModel": "id:string model:string",
  "profile.delete": "id:string",
  "profile.share": "id:string on?:boolean allow?:strings",
  "profile.move": "id:string to:string",
  "skill.share": "name:string on?:boolean allow?:strings",
  "profile.resetQuota": "id:string",
  "profile.quota": "id:string",
  "profile.check": "id:string",
  "profile.login": "id:string",
  "profile.cancelLogin": "id:string",
  "profile.loginCode": "id:string code?:string",
  "login.new": "runtime?:string access?:string",
  "login.code": "id:string code?:string",
  "login.drop": "id:string",
  "profile.loginBrowser": "id:string",
  "login.browser": "id:string",
  "job.get": "id:string",
  "job.log": "id:string lines:number",
  "job.stop": "id:string",
  "screen.close": "screen:string",
  "job.clearEnded": "session:string",
  "memory.get": "",
  "outflow.revoke": "id:string",
  "outflow.answer": "id:string allow:boolean scopes?:strings workspace?:boolean",
  "process.end": "pid:number session:string",
  "footprint.scan": "",
  "footprint.rebuild": "keys?:strings",
  "footprint.delete": "keys?:strings",
  "footprint.evict": "keys?:strings",
  "software.update": "id?:string",
  "software.updateAll": "",
  "software.check": "",
  "software.channel": "channel?:string",
  "drive.setRoots": "roots:strings",
  "permissions.request": "grant:string",
  "drive.folders": "path?:string",
  "drive.mkdir": "root:string path:string",
  "drive.rename": "root:string from:string to:string",
  "drive.remove": "root:string path:string permanent?:boolean",
  "drive.zip": "root:string path:string",
  "drive.stage": "root:string path:string zip?:boolean",
  "software.auto": "on?:boolean",
  "machineLogin.cancel": "id:string",
  "machineLogin.answer": "id:string text:string",
  "machineLogin.browser": "id:string",
  "workspace.create": "name?:string invite_code?:string",
  "workspace.rename": "workspace:string name?:string emoji?:string icon?:string",
  "workspace.setRelays": "workspace:string relays?:strings",
  "workspace.setWay": "workspace:string way:string on:boolean",
  "workspace.delete": "workspace:string",
  "workspace.invite": "workspace:string role?:string email?:string",
  "workspace.addMembers": "workspace:string role?:string emails?:strings",
  "workspace.removeAdded": "workspace:string email:string",
  "workspace.revokeInvitation": "workspace:string invitation:string",
  "workspace.setRole": "workspace:string member:string role?:string",
  "workspace.removeMember": "workspace:string member:string",
  "workspace.enroll": "workspace:string name?:string",
  "workspace.renameStation": "workspace:string station:string name?:string emoji?:string icon?:string",
  "workspace.removeStation": "workspace:string station:string",
  "invitation.preview": "token?:string",
  "invitation.accept": "id?:string token?:string",
  "invitation.decline": "id:string",
  "loginSession.revoke": "id:string",
  "admin.me": "",
  "admin.createCode": "note?:string days?:number beta?:boolean",
  "admin.revokeCode": "code:string",
  "admin.setBeta": "user:string on?:boolean",
  "admin.setMayCreate": "user:string on?:boolean",
  "admin.block": "user:string on?:boolean",
  "admin.setPending": "email:string beta?:boolean may_create?:boolean",
  "admin.removePending": "email:string",
  "admin.deleteWorkspace": "workspace:string",
  "admin.createWorkspace": "name:string owners:strings members:number stations:number",
  "admin.setLimits": "workspace:string members:number stations:number",
  "admin.enroll": "workspace:string name:string",
  "admin.feedbackStatus": "id:string status?:string",
};

/// Writes that are not shown as under way (`doing`): quick and quiet.
export const QUIET_WRITES = ["session.warm", "widget.setState", "login.drop"];


/// The request of the operation `name`, with its params; null when there is no such operation. It throws (a
/// CoreError) when the params are not what it needs.
export function request(name: string, params: unknown): Request | null {
  const dot = name.indexOf(".");
  if (dot < 0) return null;
  const service = name.slice(0, dot);
  return CLOUD_SERVICES.includes(service) ? cloudOp(name, params) : stationOp(name, params);
}

/// The params of one call, read as it goes.
class P {
  readonly v: Record<string, unknown>;
  constructor(v: unknown) {
    this.v = v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
  }
  missing(field: string): CoreError {
    return CoreError.invalid(t("core-misc.params.missing", { field }));
  }
  str(name: string): string {
    const v = this.v[name];
    if (typeof v !== "string") throw this.missing(name);
    return v;
  }
  word(name: string): string | null {
    const v = this.v[name];
    return typeof v === "string" ? v : null;
  }
  at(name: string): string {
    return encode(this.str(name));
  }
  u64(name: string): number {
    const v = this.v[name];
    if (typeof v !== "number" || !Number.isInteger(v) || v < 0) throw this.missing(name);
    return v;
  }
  bool(name: string): boolean {
    return this.v[name] === true;
  }
  value(name: string): unknown {
    if (!(name in this.v)) throw this.missing(name);
    return this.v[name];
  }
  has(name: string): boolean {
    return name in this.v;
  }
  /// Those of `names` that are given (null included), as a body.
  pick(names: string[]): Record<string, unknown> {
    const body: Record<string, unknown> = {};
    for (const n of names) if (n in this.v) body[n] = this.v[n];
    return body;
  }
}

const NONE: Effect = { kind: "none" };
const OVERVIEW: Effect = { kind: "overview" };
const SLACK: Effect = { kind: "slack" };
const FOOTPRINT: Effect = { kind: "footprint" };
/// The folders `paths` (under `root`) are in.
const drive = (root: string, paths: string[]): Effect => ({ kind: "drive", root, paths: paths.map(folderOf) });

/// The folder a path of the drive is in (`a/b/c` → `a/b`; the root's own entries → ``).
export const folderOf = (path: string) => path.split("/").filter((p) => p !== "" && p !== ".").slice(0, -1).join("/");

function stationOp(name: string, params: unknown): Request | null {
  const p = new P(params);
  // The station first, then the path (as the Rust core checks them).
  const op = (method: string, path: () => string, body: unknown | null, effect: Effect): Request => {
    const station = p.str("station");
    return { target: { station }, method, path: path(), body, fallback: null, effect };
  };
  const session = (k: string): Effect => ({ kind: "session", key: p.word(k) });
  const process = (k: string): Effect => ({ kind: "process", key: p.word(k) ?? "" });
  const connect = (k: string): Effect => ({ kind: "connect", id: p.word(k) });
  const optU64 = (k: string) => {
    const v = p.v[k];
    return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null;
  };
  switch (name) {
    // How far the control plane's gateway may go on the station (its device tools: off | read | full); set by the
    // workspace's owners and admins.
    case "tools.access":
      return op("GET", () => "/tools/access", null, NONE);
    case "tools.setAccess":
      return op("PUT", () => "/tools/access", p.pick(["access"]), OVERVIEW);
    // The modules beside the station (docs/station-modules.md): each still.fail makes and each it runs, how it is now;
    // one turned on (installed as a package and run) or off by the workspace's owners and admins.
    case "station.modules":
      return op("GET", () => "/modules", null, NONE);
    case "station.module.set":
      return op("PUT", () => `/modules/${encode(p.str("id"))}`, { enabled: p.bool("enabled") }, OVERVIEW);
    // The variables everything the station starts for its agents runs with (docs/agent-env.md), set by the workspace's
    // owners and admins: `text`, all of them as `NAME=value` lines; or `env`, a patch (a string sets one, null removes it).
    case "agentEnv.set":
      return op("PUT", () => "/agent-env", p.pick(["env", "text"]), OVERVIEW);
    // Whether the station's search finds its machine's person's own mail, messages and the like too (docs/search.md);
    // set by the workspace's owners and admins.
    case "search.setPersonal":
      return op("PUT", () => "/search/settings", p.pick(["personal"]), OVERVIEW);
    case "network.setCongestion":
      return op("PUT", () => "/network/settings", p.pick(["congestion"]), OVERVIEW);
    // The station started again by its launcher (its routes/network.ts), managers only.
    case "station.restart":
      return op("POST", () => "/station/restart", null, OVERVIEW);
    // Whether a message or notice to an agent whose large context's cache is over starts it afresh by itself, unless its
    // chat chose (`session.settings` `afresh`); its station's routes/context.ts, set by the workspace's owners and admins.
    case "context.setAfresh":
      return op("PUT", () => "/context/settings", p.pick(["afreshWhenCold"]), OVERVIEW);
    // Whether it sends its log to still.fail, scrubbed (its station's routes/diagnostics.ts); set by the workspace's
    // owners and admins.
    case "diagnostics.setLogs":
      return op("PUT", () => "/diagnostics/settings", p.pick(["logs"]), OVERVIEW);
    // Whether a Windows station runs as the machine's administrator (its station's elevation/elevation.ts): asked of
    // Windows there, then the station restarted; set by the workspace's owners and admins.
    case "elevation.set":
      return op("PUT", () => "/elevation", p.pick(["on"]), OVERVIEW);
    case "session.stop":
      return op("POST", () => `/sessions/${p.at("key")}/stop`, null, process("key"));
    case "session.warm":
      // As a person types in its chat (once a minute), nobody waiting on it: its station tells its session's new state.
      // It read the detail each time, a third of a phone's reads of details.
      return op("POST", () => `/sessions/${p.at("key")}/warm`, null, NONE);
    case "session.evict":
      return op("POST", () => `/sessions/${p.at("key")}/evict`, null, process("key"));
    // Its context compacted by hand (the station says in its chat when it is done), or cleared: its next turn starts a
    // new conversation. Refused (409, said why) while a turn runs.
    case "session.compact":
      return op("POST", () => `/sessions/${p.at("key")}/compact`, null, session("key"));
    case "session.clear":
      return op("POST", () => `/sessions/${p.at("key")}/clear`, p.has("readBack") ? p.pick(["readBack"]) : null, session("key"));
    case "session.delete":
      return op("DELETE", () => `/sessions/${p.at("key")}`, null, session("key"));
    case "session.settings":
      return op("POST", () => `/sessions/${p.at("key")}/settings`, p.pick(["profile", "model", "effort", "fast", "repick", "afresh"]), session("key"));
    case "chat.archive": {
      const method = p.bool("archived") ? "POST" : "DELETE";
      const fallback = op(method, () => `/sessions/${p.at("session")}/archive`, null, session("session"));
      const thread = optU64("thread");
      if (thread === null) return fallback;
      const r = op(method, () => `/threads/${thread}/archive`, null, { kind: "thread", archived: true });
      r.fallback = fallback;
      return r;
    }
    case "chat.keep": {
      // The thread is read before the station here (its `?` is in the closure's arguments).
      const thread = p.u64("thread");
      // Kept (the default), or let go (`kept: false`): offered for archiving again.
      return op(p.has("kept") && p.value("kept") === false ? "DELETE" : "PUT", () => `/threads/${thread}/keep`, null, { kind: "thread", archived: false });
    }
    case "chat.rename": {
      const thread = optU64("thread");
      if (thread !== null) return op("PUT", () => `/threads/${thread}/title`, p.pick(["title"]), { kind: "thread", archived: false });
      return op("POST", () => `/sessions/${p.at("session")}/title`, p.pick(["title"]), session("session"));
    }
    case "chat.pin":
      return op(p.bool("pinned") ? "PUT" : "DELETE", () => `/sessions/${p.at("session")}/pin`, null, session("session"));
    // Where a chat can be relayed (docs/relay.md): each connect's channels and groups its bot is in, read as asked.
    case "chat.relayPlaces": {
      const thread = p.u64("thread");
      return op("GET", () => `/threads/${thread}/relay`, null, NONE);
    }
    // The chat relayed to one of them (`connect`, `channel`) or to the Slack thread of a message's `link`, the person's
    // note said with it: where it went on.
    case "chat.relay": {
      const thread = p.u64("thread");
      return op("POST", () => `/threads/${thread}/relay`, p.pick(["connect", "channel", "link", "note"]), { kind: "thread", archived: false });
    }
    // The people of where it would be relayed (a connect's channel or group, or the thread of a message's `link`), for
    // the note to mention, read as asked.
    case "chat.relayPeople": {
      const thread = p.u64("thread");
      const query = ["connect", "channel", "link"].flatMap((k) => (p.word(k) !== null ? [`${k}=${encode(p.word(k)!)}`] : [])).join("&");
      return op("GET", () => `/threads/${thread}/relay/people?${query}`, null, NONE);
    }
    case "decision.dismiss": {
      const thread = p.u64("thread");
      const body = { n: p.u64("seq") };
      return op("PUT", () => `/threads/${thread}/dismissed`, body, { kind: "thread", archived: false });
    }
    case "decision.close": {
      const thread = p.u64("thread");
      const body = { n: p.u64("seq"), option: p.str("option") };
      return op("PUT", () => `/threads/${thread}/closed-card`, body, { kind: "session", key: null });
    }
    // A failure notice (its entry `seq`) sent to the still.fail team as a bug report: answered `{number, duplicate?}`.
    case "chat.report": {
      const thread = p.u64("thread");
      return op("POST", () => `/threads/${thread}/report`, { n: p.u64("seq") }, NONE);
    }
    case "session.new":
      return op("POST", () => "/sessions", p.pick(["runtime", "profile", "model", "effort", "fast"]), { kind: "session", key: null });
    case "chats.archived":
      return op("GET", () => "/chats?archived=1", null, NONE);
    case "chat.forSession":
      return op("POST", () => "/threads", p.pick(["session"]), { kind: "thread", archived: false });
    // A file a message names by its path: what it is (a few lines, a thumbnail); all of it is `file.open` (core/calls.ts).
    case "file.peek":
      return op("GET", () => `/sessions/${p.at("key")}/peek?path=${p.at("path")}${optU64("line") !== null ? `&line=${optU64("line")}` : ""}`, null, NONE);
    // A web link in a message: what the station finds it is (its title, a pull request's state).
    case "link.preview":
      return op("GET", () => `/link-preview?url=${p.at("url")}`, null, NONE);
    // Where its runtime keeps the session's transcript on the station's machine (null before it is written).
    case "session.transcript":
      return op("GET", () => `/sessions/${p.at("key")}/transcript`, null, NONE);
    case "widget.state":
      return op("GET", () => `/sessions/${p.at("key")}/widget-state?path=${p.at("path")}`, null, NONE);
    case "widget.setState":
      // A widget's own state: nothing a list shows (its page reads it, `widget.state`).
      return op("PUT", () => `/sessions/${p.at("key")}/widget-state`, p.pick(["path", "state"]), NONE);
    case "machineSessions.list":
      return op("GET", () => "/machine-sessions", null, NONE);
    case "machineSessions.read":
      return op("GET", () => `/machine-sessions/${p.at("runtime")}/${p.at("id")}?limit=${optU64("limit") ?? 200}`, null, NONE);
    case "machineSessions.continue":
      return op("POST", () => "/machine-sessions", p.pick(["runtime", "id"]), NONE);
    case "automaticDecisions.save":
      return op("PUT", () => "/automatic-decisions", p.has("input") ? p.v.input : {}, OVERVIEW);
    case "automaticDecisions.review":
      return op("POST", () => "/automatic-decisions/review", {}, OVERVIEW);
    case "automaticDecisions.policy":
      return op("PUT", () => "/automatic-decisions/policy", p.has("input") ? p.v.input : {}, OVERVIEW);
    case "archiving.save":
      return op("PUT", () => "/archiving", p.pick(["days", "slackDays", "reviewed"]), OVERVIEW);
    case "automaticDecisions.refresh":
      return op("POST", () => "/automatic-decisions/refresh", {}, OVERVIEW);
    case "connect.create":
      return op("POST", () => "/connects", p.has("input") ? p.v.input : null, connect("id"));
    case "connect.put":
      return op("PUT", () => `/connects/${p.at("id")}`, p.has("input") ? p.v.input : {}, connect("id"));
    case "connect.delete":
      return op("DELETE", () => `/connects/${p.at("id")}`, null, connect("id"));
    case "connect.reconnect":
      return op("POST", () => `/connects/${p.at("id")}/reconnect`, null, connect("id"));
    case "connect.bindSession":
      return op("POST", () => `/connects/${p.at("connect")}/session`, p.pick(["session", "title"]), connect("connect"));
    // `from`: the app's settings the form started from; only what differs from them is written (and a new icon).
    case "connect.putSlackApp": {
      const input = p.has("input") ? p.v.input : {};
      const from = p.has("from") ? p.v.from : null;
      const changed =
        from !== null && typeof from === "object" && input !== null && typeof input === "object"
          ? Object.fromEntries(Object.entries(input as Record<string, unknown>).filter(([k, v]) => k === "icon" || JSON.stringify(v) !== JSON.stringify((from as Record<string, unknown>)[k])))
          : input;
      return op("PUT", () => `/connects/${p.at("connect")}/slack-app`, changed, connect("connect"));
    }
    // Feishu (and Lark) bots (docs/feishu.md): made by scanning (the station follows it, the overview's
    // `feishuRegistrations` says how it goes), an app of one's own checked, a connect added with either.
    case "feishu.register":
      return op("POST", () => "/feishu/registrations", p.pick(["domain", "name"]), OVERVIEW);
    case "feishu.cancelRegistration":
      return op("DELETE", () => `/feishu/registrations/${p.at("id")}`, null, OVERVIEW);
    case "feishu.verify":
      return op("POST", () => "/feishu/verify", p.pick(["appId", "appSecret", "domain"]), NONE);
    case "feishu.createConnect":
      return op("POST", () => "/feishu/connects", p.pick(["feishu", "bind", "mode", "requireMention", "owner"]), { kind: "connect", id: null });
    // A Feishu connect's App Secret replaced (verified there first).
    case "feishu.putSecret":
      return op("PUT", () => `/feishu/connects/${p.at("id")}/secret`, p.pick(["appSecret"]), connect("id"));
    case "slack.verify":
      return op("POST", () => "/slack/verify", p.pick(["connect", "install", "appToken", "botToken"]), NONE);
    case "slack.makeApp":
      return op("POST", () => "/slack/apps", p.pick(["team", "settings", "icon"]), SLACK);
    case "slack.dropApp":
      return op("DELETE", () => `/slack/apps/${p.at("appId")}`, null, SLACK);
    case "slack.installed":
      return op("POST", () => "/slack/installs", p.pick(["code", "state"]), SLACK);
    case "slack.addConfigToken":
      return op("POST", () => "/slack/config-tokens", p.pick(["refreshToken"]), SLACK);
    case "slack.removeConfigToken":
      return op("DELETE", () => `/slack/config-tokens/${p.at("team")}`, null, SLACK);
    case "slack.people":
      return op("GET", () => "/slack/people", null, NONE);
    case "slack.createAppUrl":
      return op("GET", () => `/slack/create-app-url?name=${p.at("name")}`, null, NONE);
    case "slack.identity":
      return op(p.bool("bound") ? "PUT" : "DELETE", () => `/me/slack/${p.at("user")}`, null, { kind: "identity" });
    case "profile.add":
      return op("POST", () => "/profiles", p.pick(["runtime", "access"]), OVERVIEW);
    case "profile.useMachineLogin":
      return op("POST", () => "/profiles/machine", p.pick(["runtime"]), OVERVIEW);
    case "profile.put":
      return op("PUT", () => `/profiles/${p.at("id")}`, profileInput(p.has("input") ? p.v.input : {}), OVERVIEW);
    case "profile.addModel":
      return op("PUT", () => `/profiles/${p.at("id")}`, { addModel: p.word("model") ?? "" }, OVERVIEW);
    case "profile.delete":
      return op("DELETE", () => `/profiles/${p.at("id")}`, null, OVERVIEW);
    // Shared with the workspace's other stations (absent `allow`: every one), or not; moved to another station.
    case "profile.share":
      return op("POST", () => `/profiles/${p.at("id")}/share`, { on: p.bool("on"), allow: p.has("allow") ? p.v.allow : null }, OVERVIEW);
    case "profile.move":
      return op("POST", () => `/profiles/${p.at("id")}/move`, { station: p.word("to") ?? "" }, OVERVIEW);
    case "skill.share":
      return op("POST", () => `/skills/${p.at("name")}/share`, { on: p.bool("on"), allow: p.has("allow") ? p.v.allow : null }, { kind: "memory" });
    case "profile.resetQuota":
      return op("POST", () => `/profiles/${p.at("id")}/reset-quota`, null, OVERVIEW);
    case "profile.quota":
      return op("POST", () => `/profiles/${p.at("id")}/quota`, null, OVERVIEW);
    case "profile.check":
      return op("POST", () => `/profiles/${p.at("id")}/check`, null, OVERVIEW);
    case "profile.login":
      return op("POST", () => `/profiles/${p.at("id")}/login`, null, OVERVIEW);
    case "profile.cancelLogin":
      return op("DELETE", () => `/profiles/${p.at("id")}/login`, null, OVERVIEW);
    case "profile.loginCode":
      return op("POST", () => `/profiles/${p.at("id")}/login-code`, p.pick(["code"]), OVERVIEW);
    case "login.new":
      return op("POST", () => "/logins", p.pick(["runtime", "access"]), { kind: "login", id: null, from: null });
    // A code is taken only while its sign-in waits for one.
    case "login.code":
      return op("POST", () => `/logins/${p.at("id")}/code`, p.pick(["code"]), { kind: "login", id: p.str("id"), from: "needs_code" });
    case "login.drop":
      return op("DELETE", () => `/logins/${p.at("id")}`, null, { kind: "login", id: p.str("id"), from: null });
    // A sign-in's page opened in the station's own browser (docs/remote-login.md, 在 station 的浏览器中登录), for the
    // person to finish there: `{screen}`, the screen of its tab, to open. Its job says the tab from then on (`screen`).
    case "profile.loginBrowser":
      return op("POST", () => `/profiles/${p.at("id")}/login-browser`, null, NONE);
    case "login.browser":
      return op("POST", () => `/logins/${p.at("id")}/browser`, null, NONE);
    case "job.get":
      return op("GET", () => `/jobs/${p.at("id")}`, null, NONE);
    case "job.log":
      return op("GET", () => `/jobs/${p.at("id")}/log?lines=${p.u64("lines")}`, null, NONE);
    case "job.stop":
      return op("POST", () => `/jobs/${p.at("id")}/stop`, null, { kind: "job" });
    // A screen closed for good (a tab of the station's browser, docs/remote-screens.md): it leaves the station's list as
    // the station tells it (`screens` on its stream).
    case "screen.close":
      return op("POST", () => `/screens/${p.at("screen")}/close`, null, NONE);
    case "job.clearEnded":
      return op("DELETE", () => `/sessions/${p.at("session")}/jobs`, null, session("session"));
    case "memory.get":
      return op("GET", () => "/memory", null, NONE);
    // A program's grant of the station's data revoked (docs/data-outflow.md): its next read is refused.
    case "outflow.revoke":
      return op("DELETE", () => `/outflow/grants/${p.at("id")}`, null, { kind: "outflowGrants" });
    // An admin's answer to a program's request for the station's data: allowed with the kinds and reach they left, or
    // refused (docs/data-outflow.md). Its program takes the token the next time it asks.
    case "outflow.answer":
      return op("POST", () => `/outflow/requests/${p.at("id")}`, p.pick(["allow", "scopes", "workspace"]), { kind: "outflowGrants" });
    // A chat's process ended from its station's 进程 (resources/watch.ts `end`): the page reads it again in a moment.
    case "process.end":
      return op("POST", () => `/resources/processes/${p.u64("pid")}/end`, p.pick(["session"]), NONE);
    case "footprint.scan":
      return op("POST", () => "/footprint/scan", null, FOOTPRINT);
    case "footprint.rebuild":
      return op("POST", () => "/footprint/rebuild", p.pick(["keys"]), FOOTPRINT);
    case "footprint.delete":
      return op("POST", () => "/footprint/delete", p.pick(["keys"]), FOOTPRINT);
    case "footprint.evict":
      return op("POST", () => "/footprint/evict", p.pick(["keys"]), FOOTPRINT);
    case "software.update":
      return op("POST", () => "/updates", p.pick(["id"]), OVERVIEW);
    case "software.updateAll":
      return op("POST", () => "/updates/all", null, OVERVIEW);
    case "software.check":
      return op("POST", () => "/updates/check", null, OVERVIEW);
    case "software.channel":
      return op("POST", () => "/updates/channel", p.pick(["channel"]), OVERVIEW);
    case "software.auto":
      return op("POST", () => "/updates/auto", { on: p.bool("on") }, OVERVIEW);
    // The station's drive (docs/drive.md): the folders it lends its members, named by the workspace's owners and admins
    // (their folders to pick from: `drive.folders`), and changes of what is in them. A station in several workspaces keeps a
    // list for each: the asker's (docs/multi-workspace.md).
    case "drive.setRoots":
      return op("PUT", () => "/drive/roots", p.pick(["roots"]), OVERVIEW);
    // still.fail Helper's window for a grant up on a Mac station (docs/remote-screens.md "Grants"): `{window, screen}`.
    case "permissions.request":
      return op("POST", () => "/permissions/request", { grant: p.str("grant") }, OVERVIEW);
    case "drive.folders":
      return op("GET", () => `/drive/folders?path=${encode(p.word("path") ?? "")}`, null, NONE);
    case "drive.mkdir":
      return op("POST", () => "/drive/mkdir", p.pick(["root", "path"]), drive(p.str("root"), [p.str("path")]));
    case "drive.rename":
      return op("POST", () => "/drive/rename", p.pick(["root", "from", "to"]), drive(p.str("root"), [p.str("from"), p.str("to")]));
    case "drive.remove":
      return op("POST", () => "/drive/remove", p.pick(["root", "path", "permanent"]), drive(p.str("root"), [p.str("path")]));
    // A folder zipped on the station to download: where the zip is, read as a file of the drive (`drive.read`).
    case "drive.zip":
      return op("POST", () => "/drive/zip", p.pick(["root", "path"]), NONE);
    // A file of the drive (a folder: zipped there) put among the uploads, as one sent up would be, for a message to send
    // (the phone's Station 文件 switched to a file; the web's composer stages its own: composer.ts).
    case "drive.stage":
      return op("POST", () => "/drive/stage", p.pick(["root", "path", "zip"]), NONE);
    // A login to one of the station's command-line tools cancelled (docs/remote-login.md): agents start them and drive
    // their commands; how each stands comes on the station's stream (`machineLogins`).
    case "machineLogin.cancel":
      return op("DELETE", () => `/machine-logins/${p.at("id")}`, null, { kind: "machineLogins" });
    // What a login's page gave (a code), entered by the person from its card: the station types it into the command.
    case "machineLogin.answer":
      return op("POST", () => `/machine-logins/${p.at("id")}/answer`, p.pick(["text"]), { kind: "machineLogins" });
    // Its page opened in the station's own browser, for the person to finish it there: `{screen}`, to open.
    case "machineLogin.browser":
      return op("POST", () => `/machine-logins/${p.at("id")}/browser`, null, NONE);
    default:
      return null;
  }
}

function cloudOp(name: string, params: unknown): Request | null {
  const p = new P(params);
  const ws = () => `/v1/workspaces/${p.at("workspace")}`;
  const op = (method: string, path: () => string, body: unknown | null): Request => {
    const account = p.str("account");
    return { target: { cloud: account }, method, path: path(), body, fallback: null, effect: NONE };
  };
  switch (name) {
    case "workspace.create":
      return op("POST", () => "/v1/workspaces", p.pick(["name", "invite_code"]));
    case "workspace.rename":
      return op("PATCH", ws, p.pick(["name", "emoji", "icon"]));
    case "workspace.setRelays":
      return op("PUT", () => `${ws()}/relays`, p.pick(["relays"]));
    // One way its devices reach its stations (a relay, `lan`, `tailnet`, `direct`) turned on or off (cloud setWay).
    case "workspace.setWay":
      return op("PUT", () => `${ws()}/ways`, p.pick(["way", "on"]));
    case "workspace.delete":
      return op("DELETE", ws, null);
    case "workspace.invite":
      return op("POST", () => `${ws()}/invitations`, p.pick(["role", "email"]));
    case "workspace.addMembers":
      return op("POST", () => `${ws()}/members`, p.pick(["role", "emails"]));
    case "workspace.removeAdded":
      return op("DELETE", () => `${ws()}/added/${p.at("email")}`, null);
    case "workspace.revokeInvitation":
      return op("DELETE", () => `${ws()}/invitations/${p.at("invitation")}`, null);
    case "workspace.setRole":
      return op("PATCH", () => `${ws()}/members/${p.at("member")}`, p.pick(["role"]));
    case "workspace.removeMember":
      return op("DELETE", () => `${ws()}/members/${p.at("member")}`, null);
    case "workspace.enroll":
      return op("POST", () => `${ws()}/enrollments`, p.pick(["name"]));
    case "workspace.renameStation":
      return op("PATCH", () => `${ws()}/stations/${p.at("station")}`, p.pick(["name", "emoji", "icon"]));
    case "workspace.removeStation":
      return op("DELETE", () => `${ws()}/stations/${p.at("station")}`, null);
    case "invitation.preview":
      return op("POST", () => "/v1/invitations/preview", p.pick(["token"]));
    case "invitation.accept":
      return p.has("id") ? op("POST", () => `/v1/invitations/${p.at("id")}/accept`, null) : op("POST", () => "/v1/invitations/accept", p.pick(["token"]));
    case "invitation.decline":
      return op("POST", () => `/v1/invitations/${p.at("id")}/decline`, null);
    case "loginSession.revoke":
      return op("DELETE", () => `/v1/auth/sessions/${p.at("id")}`, null);
    case "admin.me":
      return op("GET", () => "/v1/admin/me", null);
    case "admin.createCode":
      return op("POST", () => "/v1/admin/invite-codes", p.pick(["note", "days", "beta"]));
    case "admin.revokeCode":
      return op("POST", () => `/v1/admin/invite-codes/${p.at("code")}/revoke`, null);
    case "admin.setBeta":
      return op("POST", () => `/v1/admin/users/${p.at("user")}/beta`, { on: p.bool("on") });
    case "admin.setMayCreate":
      return op("POST", () => `/v1/admin/users/${p.at("user")}/may-create`, { on: p.bool("on") });
    case "admin.block":
      return op("POST", () => `/v1/admin/users/${p.at("user")}/block`, { on: p.bool("on") });
    case "admin.setPending":
      return op("POST", () => "/v1/admin/pending", p.pick(["email", "beta", "may_create"]));
    case "admin.removePending":
      return op("POST", () => "/v1/admin/pending/remove", p.pick(["email"]));
    case "admin.deleteWorkspace":
      return op("POST", () => `/v1/admin/workspaces/${p.at("workspace")}/delete`, null);
    case "admin.createWorkspace":
      return op("POST", () => "/v1/admin/workspaces", p.pick(["name", "owners", "members", "stations"]));
    case "admin.setLimits":
      return op("POST", () => `/v1/admin/workspaces/${p.at("workspace")}/limits`, p.pick(["members", "stations"]));
    case "admin.enroll":
      return op("POST", () => `/v1/admin/workspaces/${p.at("workspace")}/enrollments`, p.pick(["name"]));
    case "admin.feedbackStatus":
      return op("POST", () => `/v1/admin/feedback/${p.at("id")}/status`, p.pick(["status"]));
    default:
      return null;
  }
}

/// A profile's change as the station takes it: the models it may use (`models`) each once, in order, however they were
/// ticked.
export function profileInput(input: unknown): unknown {
  if (input === null || typeof input !== "object" || !Array.isArray((input as { models?: unknown }).models)) return input;
  const given = (input as { models: unknown[] }).models;
  const models = [...new Set(given.filter((m): m is string => typeof m === "string"))].sort();
  return { ...(input as object), models };
}

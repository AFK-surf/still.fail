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
  | { kind: "thread"; archived: boolean }
  | { kind: "connect"; id: string | null }
  | { kind: "overview" }
  | { kind: "footprint" }
  | { kind: "slack" }
  | { kind: "job" }
  | { kind: "identity" };

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
  "session.warm": "key:string",
  "session.evict": "key:string",
  "session.delete": "key:string",
  "session.settings": "key:string profile?:string model?:string effort?:string fast?:boolean",
  "chat.archive": "archived?:boolean session:string thread?:number",
  "chat.keep": "thread:number",
  "chat.rename": "session?:string title?:string thread?:number",
  "chat.pin": "pinned?:boolean session:string",
  "decision.dismiss": "thread:number seq:number",
  "decision.close": "thread:number seq:number option:string",
  "session.new": "runtime?:string profile?:string model?:string effort?:string fast?:boolean",
  "chats.archived": "",
  "chat.forSession": "session?:string",
  "widget.state": "key:string path:string",
  "file.peek": "key:string path:string line?:number",
  "file.open": "key:string path:string",
  "link.preview": "url:string",
  "widget.setState": "key:string path?:string state?:json",
  "machineSessions.list": "",
  "machineSessions.read": "runtime:string id:string limit?:number",
  "machineSessions.continue": "runtime?:string id?:string",
  "automaticDecisions.save": "input:json",
  "automaticDecisions.refresh": "",
  "automaticDecisions.review": "",
  "automaticDecisions.policy": "input:json",
  "connect.create": "input?:json id?:string",
  "connect.put": "id:string input?:json",
  "connect.delete": "id:string",
  "connect.reconnect": "id:string",
  "connect.bindSession": "connect:string session?:string title?:string",
  "connect.putSlackApp": "connect:string input?:json",
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
  "login.new": "runtime?:string",
  "login.code": "id:string code?:string",
  "login.drop": "id:string",
  "job.get": "id:string",
  "job.log": "id:string lines:number",
  "job.stop": "id:string",
  "job.clearEnded": "session:string",
  "memory.get": "",
  "footprint.scan": "",
  "footprint.rebuild": "keys?:strings",
  "footprint.delete": "keys?:strings",
  "footprint.evict": "keys?:strings",
  "software.update": "id?:string",
  "software.updateAll": "",
  "software.check": "",
  "software.channel": "channel?:string",
  "software.auto": "on?:boolean",
  "workspace.create": "name?:string invite_code?:string",
  "workspace.rename": "workspace:string name?:string",
  "workspace.setRelays": "workspace:string relays?:strings",
  "workspace.delete": "workspace:string",
  "workspace.invite": "workspace:string role?:string email?:string",
  "workspace.addMembers": "workspace:string role?:string emails?:strings",
  "workspace.removeAdded": "workspace:string email:string",
  "workspace.revokeInvitation": "workspace:string invitation:string",
  "workspace.setRole": "workspace:string member:string role?:string",
  "workspace.removeMember": "workspace:string member:string",
  "workspace.enroll": "workspace:string name?:string",
  "workspace.renameStation": "workspace:string station:string name?:string",
  "workspace.removeStation": "workspace:string station:string",
  "invitation.preview": "token?:string",
  "invitation.accept": "id?:string token?:string",
  "invitation.decline": "id:string",
  "loginSession.revoke": "id:string",
  "admin.me": "",
  "admin.createCode": "note?:string days?:number",
  "admin.revokeCode": "code:string",
  "admin.setBeta": "user:string on?:boolean",
  "admin.setMayCreate": "user:string on?:boolean",
  "admin.block": "user:string on?:boolean",
  "admin.deleteWorkspace": "workspace:string",
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

function stationOp(name: string, params: unknown): Request | null {
  const p = new P(params);
  // The station first, then the path (as the Rust core checks them).
  const op = (method: string, path: () => string, body: unknown | null, effect: Effect): Request => {
    const station = p.str("station");
    return { target: { station }, method, path: path(), body, fallback: null, effect };
  };
  const session = (k: string): Effect => ({ kind: "session", key: p.word(k) });
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
    case "session.stop":
      return op("POST", () => `/sessions/${p.at("key")}/stop`, null, session("key"));
    case "session.warm":
      return op("POST", () => `/sessions/${p.at("key")}/warm`, null, session("key"));
    case "session.evict":
      return op("POST", () => `/sessions/${p.at("key")}/evict`, null, session("key"));
    case "session.delete":
      return op("DELETE", () => `/sessions/${p.at("key")}`, null, session("key"));
    case "session.settings":
      return op("POST", () => `/sessions/${p.at("key")}/settings`, p.pick(["profile", "model", "effort", "fast"]), session("key"));
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
      return op("PUT", () => `/threads/${thread}/keep`, null, { kind: "thread", archived: false });
    }
    case "chat.rename": {
      const thread = optU64("thread");
      if (thread !== null) return op("PUT", () => `/threads/${thread}/title`, p.pick(["title"]), { kind: "thread", archived: false });
      return op("POST", () => `/sessions/${p.at("session")}/title`, p.pick(["title"]), session("session"));
    }
    case "chat.pin":
      return op(p.bool("pinned") ? "PUT" : "DELETE", () => `/sessions/${p.at("session")}/pin`, null, session("session"));
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
    case "session.new":
      return op("POST", () => "/sessions", p.pick(["runtime", "profile", "model", "effort", "fast"]), { kind: "session", key: null });
    case "chats.archived":
      return op("GET", () => "/chats?archived=1", null, NONE);
    case "chat.forSession":
      return op("POST", () => "/threads", p.pick(["session"]), { kind: "thread", archived: false });
    // A file a message names by its path: what it is (a few lines, a thumbnail), or all of it for the preview.
    case "file.peek":
      return op("GET", () => `/sessions/${p.at("key")}/peek?path=${p.at("path")}${optU64("line") !== null ? `&line=${optU64("line")}` : ""}`, null, NONE);
    case "file.open":
      return op("GET", () => `/sessions/${p.at("key")}/open?path=${p.at("path")}`, null, NONE);
    // A web link in a message: what the station finds it is (its title, a pull request's state).
    case "link.preview":
      return op("GET", () => `/link-preview?url=${p.at("url")}`, null, NONE);
    case "widget.state":
      return op("GET", () => `/sessions/${p.at("key")}/widget-state?path=${p.at("path")}`, null, NONE);
    case "widget.setState":
      return op("PUT", () => `/sessions/${p.at("key")}/widget-state`, p.pick(["path", "state"]), session("key"));
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
    case "connect.putSlackApp":
      return op("PUT", () => `/connects/${p.at("connect")}/slack-app`, p.has("input") ? p.v.input : {}, connect("connect"));
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
      return op("PUT", () => `/profiles/${p.at("id")}`, p.has("input") ? p.v.input : {}, OVERVIEW);
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
      return op("POST", () => `/skills/${p.at("name")}/share`, { on: p.bool("on"), allow: p.has("allow") ? p.v.allow : null }, NONE);
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
      return op("POST", () => "/logins", p.pick(["runtime"]), NONE);
    case "login.code":
      return op("POST", () => `/logins/${p.at("id")}/code`, p.pick(["code"]), NONE);
    case "login.drop":
      return op("DELETE", () => `/logins/${p.at("id")}`, null, NONE);
    case "job.get":
      return op("GET", () => `/jobs/${p.at("id")}`, null, NONE);
    case "job.log":
      return op("GET", () => `/jobs/${p.at("id")}/log?lines=${p.u64("lines")}`, null, NONE);
    case "job.stop":
      return op("POST", () => `/jobs/${p.at("id")}/stop`, null, { kind: "job" });
    case "job.clearEnded":
      return op("DELETE", () => `/sessions/${p.at("session")}/jobs`, null, session("session"));
    case "memory.get":
      return op("GET", () => "/memory", null, NONE);
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
      return op("PATCH", ws, p.pick(["name"]));
    case "workspace.setRelays":
      return op("PUT", () => `${ws()}/relays`, p.pick(["relays"]));
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
      return op("PATCH", () => `${ws()}/stations/${p.at("station")}`, p.pick(["name"]));
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
      return op("POST", () => "/v1/admin/invite-codes", p.pick(["note", "days"]));
    case "admin.revokeCode":
      return op("POST", () => `/v1/admin/invite-codes/${p.at("code")}/revoke`, null);
    case "admin.setBeta":
      return op("POST", () => `/v1/admin/users/${p.at("user")}/beta`, { on: p.bool("on") });
    case "admin.setMayCreate":
      return op("POST", () => `/v1/admin/users/${p.at("user")}/may-create`, { on: p.bool("on") });
    case "admin.block":
      return op("POST", () => `/v1/admin/users/${p.at("user")}/block`, { on: p.bool("on") });
    case "admin.deleteWorkspace":
      return op("POST", () => `/v1/admin/workspaces/${p.at("workspace")}/delete`, null);
    case "admin.feedbackStatus":
      return op("POST", () => `/v1/admin/feedback/${p.at("id")}/status`, p.pick(["status"]));
    default:
      return null;
  }
}

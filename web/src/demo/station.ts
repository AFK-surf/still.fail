// The made-up station behind the demo's chats, and its workspace in ember cloud: what the settings, the station's
// page, the accounts and the phone's workspace pages read, so that every page the visitor can open shows something.
// station.json holds the station's views, shaped as a real station's (every value made up), its times counted from
// 0: they are moved to now here.
import data from "./station.json";
import { CHEN, LIN, stamp, STATION, ZHOU, type Runs } from "./fixtures.ts";
import type { ArchiveDay, ArchiveView, Connect, ConnectsView, Person } from "../core/shapes.ts";

const TIME = /^(at|checkedAt|resetsAt|startedAt|createdAt|endedAt|lastActiveAt|updatedAt)$/;

/** A copy with every time moved from 0 to now. */
function now<T>(value: T): T {
  const at = Date.now();
  const move = (v: unknown, key = ""): unknown => {
    if (Array.isArray(v)) return v.map((x) => move(x));
    if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, move(x, k)]));
    return typeof v === "number" && TIME.test(key) ? at + v : v;
  };
  return move(value) as T;
}

export const BAN_DETAIL = "Anthropic 拒绝了这个账号（403）This organization has been disabled.";

/** The team's Claude subscription (Max, signed in on the station): refused by Anthropic, as the visitor finds it. */
function subscription(base: Record<string, unknown>) {
  return {
    ...base, machine: false, name: "lin@acme.dev", loginCommand: "",
    quota: { state: "blocked", windows: [], detail: BAN_DETAIL, checkedAt: Date.now() }, checkText: "被停用", checkTone: "red",
  };
}

export const overview = () => {
  const base = now(data.overview);
  return {
    ...base, connects: [slack()],
    // The station's own Claude Code login is the subscription's profile, not offered again.
    machineLogins: base.machineLogins.filter((l) => l.runtime !== "claude"),
    profiles: [subscription(base.profiles[0]!)],
  };
};
export const host = () => now(data.host);
export const stationView = () => {
  const base = now(data.station);
  return { ...base, station: STATION, overview: overview() };
};
/** What a Claude agent's model control offers and the account it runs on. */
export const runs = (): Runs => ({ choices: stationView().models as Runs["choices"], profile: overview().profiles[0] as unknown as Runs["profile"] });
/** A connect's Slack app, as the station reads it from Slack: here, with no configuration token to read it with. */
export const slackApp = () => ({ state: "no_config_token" });

/** The Slack app the team talks to its agents through, shaped as the core presents a connect. */
function slack(): Connect {
  return {
    id: "acme-slack", name: "still.fail", team: "Acme", enabled: true, kind: "slack", mode: "multi-session", requireMention: true,
    bind: { runtime: "claude", model: "claude-opus-5-5", effort: "medium", profile: "machine-claude" },
    slack: { appToken: "", botToken: "" },
    connection: { state: "connected", botUserId: "U07EMBER", workspace: { team: "Acme", teamId: "T0ACME", url: "https://acme.slack.com/", botUserId: "U07EMBER", botName: "still.fail" } },
    createdBy: { id: LIN.id, name: LIN.name, shown: LIN.shown }, sessions: 14,
    statusText: "在线", presence: "online", modeText: "多会话", modeShort: "多会话", runtimeText: "Claude Code", runText: "Claude Code · Opus 5.5 · medium", modelName: "Opus 5.5",
  };
}

export const connects = (): ConnectsView => ({
  me: { id: "local" }, loading: false,
  items: [{ station: STATION, stationName: "Studio", connect: slack(), sessions: [], candidates: [], running: 0 }],
});

/**
 * What only a real ember can do: anything that reaches past the demo (Slack, a model's account, signing in, another
 * machine, ember cloud's members). The page offers the real one instead (mount.tsx).
 */
export class NeedsReal extends Error {
  constructor() {
    super("这是演示：这一步要连到真实的服务，请在真实的 still.fail 里做。");
  }
}

/** What the demo's station does itself, changing nothing: a chat's agent woken, stopped or moved to another model. */
const OWN = new Set(["session.warm", "session.stop", "session.evict", "session.settings"]);

/** The station's operations (client/core/src/ops.rs), by name: what is read answers; what would reach out needs a real
 *  ember; what stays in the station answers the overview (what most writes answer with) and changes nothing. */
export function op(name: string): unknown {
  if (name === "memory.get") return data.memory;
  if (name === "machineSessions.list") return now(data.machineSessions);
  // An inline visualization keeps nothing here.
  if (name === "widget.state") return { state: null };
  if (name === "widget.setState") return { ok: true };
  if (OWN.has(name)) return overview();
  throw new NeedsReal();
}

/** The archive, as the core puts it together (client/core/src/views/archive.rs): the station's archived chats by day. */
export function archive(): ArchiveView {
  const days: ArchiveDay[] = [];
  const today = new Date().setHours(0, 0, 0, 0);
  for (const chat of now(data.archived).sort((a, b) => b.archived.at - a.archived.at)) {
    const at = new Date(chat.archived.at);
    const ago = Math.round((today - new Date(at).setHours(0, 0, 0, 0)) / 86_400_000);
    const label = ago <= 0 ? "今天" : ago === 1 ? "昨天" : ago < 7 ? `星期${"日一二三四五六"[at.getDay()]}` : `${at.getMonth() + 1}月${at.getDate()}日`;
    const item = {
      station: STATION, session: chat.session, thread: chat.thread, title: chat.title, last: chat.last?.text ?? "", at: chat.archived.at,
      clock: at.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" }), how: "手动归档", deletable: !chat.archived.alone,
    };
    const last = days.at(-1);
    if (last?.label === label) last.items.push(item); else days.push({ label, items: [item] });
  }
  return { days, errors: [], loading: false };
}

// ---- ember cloud ----

const user = (p: Person) => ({ sub: p.id, email: p.email ?? p.id, name: p.name, picture: p.shown.picture ?? "" });

/** The visitor, signed in as a member of Acme. */
export const ACCOUNT = { sub: "demo-you", email: "you@acme.dev", name: "你", picture: "" };
/** Its workspace: the first part of STATION (fixtures.ts). */
export const WORKSPACE = "demo";

export function workspaces() {
  const at = Date.now();
  return [{
    account: ACCOUNT, invitations: [], relay_url: null, loaded: true,
    workspaces: [{ id: WORKSPACE, name: "Acme", role: "admin", created_at: at - 90 * 86_400_000, stations: 1, members: 4 }],
  }];
}

export function workspace() {
  const at = Date.now();
  const member = (p: ReturnType<typeof user>, role: string, days: number) => ({ ...p, role, added_at: at - days * 86_400_000 });
  return {
    id: WORKSPACE, name: "Acme", role: "admin", created_at: at - 90 * 86_400_000,
    members: [member(user(LIN), "owner", 90), member(ACCOUNT, "admin", 60), member(user(CHEN), "member", 45), member(user(ZHOU), "member", 30)],
    stations: [{ id: "local", name: "Studio", enrolled_at: at - 88 * 86_400_000, enrolled_by: LIN.email, last_seen: null, version: "0.1.1024" }],
    invitations: [], added: [],
  };
}

export function loginSessions() {
  const at = Date.now();
  const session = (id: string, name: string, days: number, current: boolean) => {
    const created = at - days * 86_400_000;
    const expires = created + 30 * 86_400_000;
    return { id, name, created_at: created, expires_at: expires, current, time: { created_at: stamp(created), expires_at: stamp(expires) } };
  };
  return [session("s1", "这台浏览器", 3, true), session("s2", "still.fail（Android）", 12, false)];
}

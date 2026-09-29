// The made-up station behind the demo's chats, and its workspace in ember cloud: what the settings, the station's
// page, the accounts and the phone's workspace pages read, so that every page the visitor can open shows something.
// station.json holds the station's views, shaped as a real station's (every value made up), its times counted from
// 0: they are moved to now here.
import data from "./station.json";
import { CHEN, LIN, stamp, ZHOU, type Runs } from "./fixtures.ts";
import type { Connect, ConnectsView, Person } from "../core/shapes.ts";
import { addUserProfile, presentProfile, removeUserProfile, updateUserProfile, userModels, userProfiles } from "./keys.ts";
import { check } from "./llm.ts";

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
    profiles: [subscription(base.profiles[0]!), ...userProfiles().map(presentProfile)],
  };
};
export const host = () => now(data.host);
export const stationView = () => {
  const base = now(data.station);
  return { ...base, overview: overview(), models: [...base.models, ...userModels()] };
};
/** What a Claude agent's model control offers and the account it runs on. */
export const runs = (): Runs => ({ choices: stationView().models as Runs["choices"], profile: overview().profiles[0] as Runs["profile"] });
/** The visitor's own account the demo's agent runs on, when they have added one. */
export const visitorProfile = () => userProfiles()[0];
/** A connect's Slack app, as the station reads it from Slack: here, with no configuration token to read it with. */
export const slackApp = () => ({ state: "no_config_token" });

/** The Slack app the team talks to its agents through, shaped as the core presents a connect. */
function slack(): Connect {
  return {
    id: "acme-slack", name: "ember", team: "Acme", enabled: true, kind: "slack", mode: "multi-session", requireMention: true,
    bind: { runtime: "claude", model: "claude-opus-5-5", effort: "medium", profile: "machine-claude" },
    slack: { appToken: "", botToken: "" },
    connection: { state: "connected", botUserId: "U07EMBER", workspace: { team: "Acme", teamId: "T0ACME", url: "https://acme.slack.com/", botUserId: "U07EMBER", botName: "ember" } },
    createdBy: { id: LIN.id, name: LIN.name, shown: LIN.shown }, sessions: 14,
    statusText: "在线", presence: "online", modeText: "多会话", modeShort: "多会话", runtimeText: "Claude Code", runText: "Claude Code · Opus 5.5 · medium", modelName: "Opus 5.5",
  };
}

export const connects = (): ConnectsView => ({
  me: { id: "local" }, loading: false,
  items: [{ station: "local", stationName: "Studio", connect: slack(), sessions: [], candidates: [], running: 0 }],
});

/** Something the station refuses, with its words (the core hands them to the page as the call's error). */
export class Refused extends Error {}

/** The station's admin API, as `station.request` reaches it. What is read answers; the visitor's own profiles (keys.ts)
 *  are added, changed and removed for real, in this browser; any other write answers the overview (what most writes
 *  answer with) and changes nothing. */
export async function request(method: string, path: string, body?: unknown): Promise<unknown> {
  const input = (body ?? {}) as { access?: { kind?: string; key?: string }; models?: string[] };
  const profile = /^\/profiles\/([^/]+)(\/.*)?$/.exec(path);
  if (method === "GET") {
    if (path === "/memory") return data.memory;
    if (path.startsWith("/chats?archived")) return now(data.archived);
    if (path === "/machine-sessions") return now(data.machineSessions);
    return overview();
  }
  if (method === "POST" && path === "/profiles") {
    if (input.access?.kind !== "opencode-go") throw new Refused("演示里只能添加 OpenCode Go 的 key：它存在你的浏览器里，由浏览器直接用它请求模型。");
    const key = input.access.key?.trim() ?? "";
    if (!key) throw new Refused("要填 key");
    const trial = { id: "trial", kind: "opencode-go" as const, key, models: ["kimi-k3"], addedAt: Date.now() };
    try {
      await check(trial);
    } catch (e) {
      throw new Refused(`这个 key 用不了：${(e as Error).message}`);
    }
    const made = addUserProfile("opencode-go", key);
    return { id: made.id, overview: overview() };
  }
  if (profile && userProfiles().some((p) => p.id === decodeURIComponent(profile[1]!))) {
    const id = decodeURIComponent(profile[1]!);
    if (method === "DELETE" && !profile[2]) removeUserProfile(id);
    if (method === "PUT" && !profile[2]) updateUserProfile(id, { ...(input.access?.key !== undefined ? { key: input.access.key } : {}), ...(input.models ? { models: input.models } : {}) });
    if (profile[2] === "/check") return presentProfile(userProfiles().find((p) => p.id === id)!).check;
    if (profile[2] === "/quota") return null;
  }
  return overview();
}

// ---- ember cloud ----

const user = (p: Person) => ({ sub: p.id, email: p.email ?? p.id, name: p.name, picture: p.shown.picture ?? "" });

/** The visitor, signed in as a member of Acme. */
export const ACCOUNT = { sub: "demo-you", email: "you@acme.dev", name: "你", picture: "" };
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
  return [session("s1", "这台浏览器", 3, true), session("s2", "ember（Android）", 12, false)];
}

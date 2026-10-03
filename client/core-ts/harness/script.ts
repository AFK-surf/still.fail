// What the side-by-side run does, step by step, as a UI and as still.fail cloud would: signing in and out, the
// accounts, workspaces and workspace topics, still.fail cloud's writes and events, prefs, the device, errors.
import type { FakeCloud } from "./cloud.ts";

export type Ctx = {
  cloud: FakeCloud;
  /// What call `id` answered (its `ok`, or its `error`).
  answer(id: number): unknown;
  send(message: unknown): void;
  disconnect(): void;
};

/// `deliberate`: the TS core is meant to show something else at this step (docs/core-ts.md, 刻意不同), and why; the end
/// state is still compared.
export type Step = { name: string; run(ctx: Ctx): void | Promise<void>; wait?: number; deliberate?: string };

const call = (id: number, name: string, params?: unknown) => (ctx: Ctx) => ctx.send(params === undefined ? { id, call: name } : { id, call: name, params });
const sub = (id: number, topic: unknown) => (ctx: Ctx) => ctx.send({ id, subscribe: topic });
const stateOf = (ctx: Ctx, id: number) => new URL(String((ctx.answer(id) as { url: string }).url)).searchParams.get("state");

export const SCRIPT: Step[] = [
  { name: "accounts, none signed in", run: sub(1, { topic: "accounts" }) },
  { name: "workspaces, none signed in", run: sub(2, { topic: "workspaces" }) },
  { name: "prefs as they start", run: sub(3, { topic: "prefs" }) },
  { name: "doing as it starts", run: sub(9, { topic: "doing" }) },
  { name: "the device says what it is", run: call(100, "client.device", { app: "desktop", build: "0.1.1200", locale: "zh-CN" }) },
  { name: "sign-in begins", run: call(101, "auth.begin", { redirect_uri: "stillfail://auth/callback", return_to: "/w/ws1" }) },
  { name: "sign-in with a wrong state", run: call(102, "auth.complete", { query: "?code=code-alice&state=wrong" }) },
  { name: "sign-in begins again", run: call(103, "auth.begin", { redirect_uri: "stillfail://auth/callback", return_to: "/w/ws1", device_name: "测试机" }) },
  { name: "sign-in completes as alice", run: (ctx) => call(104, "auth.complete", { query: `?code=code-alice&state=${stateOf(ctx, 103)}` })(ctx), wait: 500 },
  { name: "her workspace", run: sub(4, { topic: "workspace", workspace: "ws1" }) },
  { name: "a workspace she is not in", run: sub(5, { topic: "workspace", workspace: "ws2" }) },
  { name: "her signed-in devices", run: sub(6, { topic: "loginSessions", account: "u-alice" }) },
  { name: "status of her workspace", run: sub(7, { topic: "status", workspace: "ws1" }) },
  { name: "renames her workspace", run: call(105, "workspace.rename", { account: "u-alice", workspace: "ws1", name: "研发部" }) },
  { name: "an empty name is refused", run: call(106, "workspace.rename", { account: "u-alice", workspace: "ws1", name: " " }) },
  { name: "invites with a bad email", run: call(107, "workspace.invite", { account: "u-alice", workspace: "ws1", email: "nobody", role: "member" }) },
  { name: "invites carol", run: call(108, "workspace.invite", { account: "u-alice", workspace: "ws1", email: "carol@x.test", role: "member" }) },
  {
    name: "a station comes online (the cloud says so)",
    run: (ctx) => {
      ctx.cloud.workspaces.get("ws1")!.stations[1].online = true;
      ctx.cloud.push({ type: "workspace", id: "ws1" });
    },
  },
  { name: "renames a station", run: call(109, "workspace.renameStation", { account: "u-alice", workspace: "ws1", station: "st2", name: "mini 2" }) },
  { name: "signs a device out", run: call(110, "loginSession.revoke", { account: "u-alice", id: "d1" }) },
  { name: "makes a workspace", run: call(111, "workspace.create", { account: "u-alice", name: "新空间" }) },
  { name: "is no admin", run: call(112, "admin.me", { account: "u-alice" }) },
  { name: "an account she has not", run: call(113, "workspace.rename", { account: "u-nobody", workspace: "ws1", name: "x" }) },
  { name: "params missing", run: call(114, "workspace.rename", { account: "u-alice", name: "x" }) },
  { name: "no such call", run: call(115, "workspace.explode", { account: "u-alice" }) },
  { name: "not a message", run: (ctx) => ctx.send({ id: 116, what: true }) },
  { name: "prefs set", run: call(117, "prefs.set", { appearance: "dark", onlyMine: true, lastChat: { ws1: "/w/ws1/new" } }) },
  { name: "prefs refused", run: call(118, "prefs.set", { appearance: "blue" }) },
  { name: "a draft", run: call(119, "draft.put", { station: "ws1/st1", chat: "new", text: "你好" }) },
  { name: "the draft read back", run: call(120, "draft.get", { station: "ws1/st1", chat: "new" }) },
  { name: "bob signs in beside her", run: call(121, "auth.begin", { redirect_uri: "stillfail://auth/callback", return_to: "/" }) },
  { name: "bob's sign-in completes", run: (ctx) => call(122, "auth.complete", { query: `?code=code-bob&state=${stateOf(ctx, 121)}` })(ctx), wait: 500 },
  { name: "bob's own workspace now reached", run: sub(8, { topic: "workspace", workspace: "ws2" }) },
  { name: "alice invites bob to her new workspace", run: (ctx) => call(123, "workspace.invite", { account: "u-alice", workspace: [...ctx.cloud.workspaces.keys()].find((k) => k.startsWith("ws-new"))!, email: "bob@x.test", role: "member" })(ctx) },
  {
    name: "bob accepts",
    run: (ctx) => call(124, "invitation.accept", { account: "u-bob", id: ctx.cloud.invitations.find((i) => i.email === "bob@x.test")!.id })(ctx),
  },
  {
    name: "the cloud says bob's workspaces changed",
    deliberate: "rule 6: an account's workspaces changing reads each of them again (the Rust core only the list, until its socket reopens)",
    run: (ctx) => {
      ctx.cloud.workspaces.get("ws2")!.name = "个人空间";
      ctx.cloud.push({ type: "workspaces" }, "u-bob");
    },
  },
  {
    name: "the events sockets drop and come back",
    deliberate: "the step before: what the Rust core catches up on here the TS core had already",
    run: (ctx) => {
      for (const s of ctx.cloud.sockets) s.ws.terminate();
    },
    wait: 2500,
  },
  { name: "bob signs out", run: call(125, "auth.signOut", { account: "u-bob" }) },
  { name: "ws2 is no one's now", run: sub(10, { topic: "workspace", workspace: "ws2" }) },
  { name: "the wake answers", run: call(126, "client.wake", { away: 0 }) },
  { name: "push key", run: call(127, "push.key") },
  { name: "deletes her new workspace", run: (ctx) => call(128, "workspace.delete", { account: "u-alice", workspace: [...ctx.cloud.workspaces.keys()].find((k) => k.startsWith("ws-new")) ?? "x" })(ctx) },
  { name: "unsubscribes her workspace", run: (ctx) => ctx.send({ id: 4, unsubscribe: true }) },
  { name: "alice signs out", run: call(129, "auth.signOut", { account: "u-alice" }) },
];

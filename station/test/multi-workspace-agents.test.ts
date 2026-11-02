// One station in two workspaces, as its agents see it (docs/multi-workspace.md): a session of workspace W reaches W's
// chats and stations only (chat_list, chat_read, session_send, station_list, station_task), what other stations ask
// reaches that workspace's chats only, sessions run on the profiles allowed there, and each workspace has its own
// memory and skills. The transport is a direct call that checks what mesh/peer.ts checks (`member`).
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Cloud } from "../src/cloud/state.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import { type PeerCall, Remote } from "../src/jobs/remote.ts";
import { member } from "../src/mesh/peer.ts";
import { memory } from "../src/read/memory.ts";
import { workspaceAgentHome } from "../src/sessions/agent-home.ts";
import { profilesFor } from "../src/sessions/config.ts";
import { sessionKey } from "../src/sessions/hub.ts";
import { newSession } from "../src/sessions/lifecycle.ts";
import { openOptions } from "../src/sessions/actor.ts";
import { fromPeer } from "../src/sessions/messages.ts";
import { createForPeer } from "../src/sessions/opened.ts";
import { stationLang, tr } from "../src/ops/i18n.ts";
import { remoteTools } from "../src/tools/remote.ts";
import { ChatShares } from "../src/xshare/index.ts";
import { Rig, say, settle } from "./hub-fakes.ts";

const W1 = "W1";
const W2 = "W2";

/// The station "st" in W1 (its home, with station A) and W2 (with station B), as cloud.json says.
function cloudOf(dir: string): Cloud {
  const state = {
    station: "st", workspace: W1, workspace_name: "One", name: "st", relay_urls: [], revocations: [],
    peers: [{ id: "st", name: "st" }, { id: "A", name: "alpha" }],
    joined: [{ workspace: W2, workspace_name: "Two", name: "st", peers: [{ id: "st", name: "st" }, { id: "B", name: "beta" }], revocations: [] }],
  };
  mkdirSync(join(dir, "mesh"), { recursive: true });
  writeFileSync(join(dir, "mesh", "cloud.json"), JSON.stringify(state));
  return Object.assign(Object.create(Cloud.prototype), { peersCurrent: true, lock: null, state, listen: () => () => {} });
}

/// A rig of the station in both workspaces: its tools, its transport (what it asked of whom, in which workspace), a
/// session of each workspace.
async function twoWorkspaces() {
  const rig = new Rig({ link: true, place: { workspace: W1, station: "st" }, workspaces: [W1, W2] });
  const cloud = cloudOf(rig.dir);
  const asked: [string, string, any][] = [];
  const transport: PeerCall = async (target, workspace, request) => {
    if (target === "" && request?.method === "peers") {
      const of = workspace === null ? cloud.memberships()[0]! : cloud.membership(workspace)!;
      return { workspace: of.workspace, stations: of.peers, current: true };
    }
    const ws = member(cloud, target, workspace);
    asked.push([target, ws, request]);
    if (request?.method === "describe") return { protocol: 1, tasks: true };
    if (request?.method === "session.message") return { thread: "EMBER/1.1" };
    if (request?.method === "task.list") return { tasks: [] };
    throw new Error(`unexpected ${request?.method}`);
  };
  const jobs = new Jobs({ store: rig.store, data: rig.dir, notify: () => {}, link: () => null });
  const remote = new Remote({ data: rig.dir, store: rig.store, jobs, notify: () => {} });
  remote.attach(transport);
  const xshare = new ChatShares({
    data: rig.dir, store: rig.store, cloud,
    ask: (station, request) => remote.ask(station, request),
    link: (chat) => rig.hub.link(chat) ?? null,
    title: (chat) => rig.store.getSession(chat)?.title ?? chat,
    touches: () => [],
    inbox: async () => ({}),
    chatWs: (chat) => rig.hub.wsOf(chat),
  });
  rig.hub.onPeer((station, request) => xshare.send(station, request, (r) => remote.ask(station, r)));
  rig.hub.onOutsideChats((ws) => xshare.borrowed(ws));
  const stationTool = remoteTools(remote);
  const station = async (key: string, name: string, args: any) => JSON.parse(await stationTool.find((t) => t.name === name)!.run(key, args));
  // A Slack thread of W1 (its connect's: the home workspace), and a still.fail chat of W2.
  const m = say("<@UBOT> release plan of one");
  await rig.accept(m);
  await settle();
  const one = sessionKey("cl", "C1", m.threadTs);
  const [two] = newSession(rig.hub, { runtime: "claude", createdBy: "b@x", ws: W2, title: "plan of two" });
  const close = async () => {
    await remote.close();
    await jobs.shutdown();
    await xshare.close();
    await rig.close();
  };
  return { rig, cloud, asked, remote, xshare, station, one, two, close };
}

/// Runs `body` on the two workspaces' rig, closed after whatever happened.
async function withTwo(body: (t: Awaited<ReturnType<typeof twoWorkspaces>>) => Promise<void>) {
  const t = await twoWorkspaces();
  try {
    await body(t);
  } finally {
    await t.close();
  }
}

test("chat_list and chat_read show a session its own workspace's chats; another's only when shared with it", () => withTwo(async (t) => {
  const { rig, one, two } = t;
  const listOne = await rig.call(one, "chat_list", {});
  const listTwo = await rig.call(two, "chat_list", {});
  assert.ok(listOne.includes(one) && !listOne.includes(two) && !listOne.includes("plan of two"), listOne);
  assert.ok(listTwo.includes(two) && !listTwo.includes(one) && !listTwo.includes("release plan"), listTwo);
  // Its link names its own workspace.
  const linkTwo = rig.hub.link(two)!;
  assert.ok(linkTwo.includes(`/o/${W2}/st/`), linkTwo);
  assert.ok(rig.hub.link(one)!.includes(`/o/${W1}/st/`));
  // Not by its key, its link nor its address, though it is this very station.
  assert.match(await rig.refused(one, "chat_read", { chat: linkTwo }), /not shared with your workspace/);
  assert.match(await rig.refused(one, "chat_read", { chat: two }), /not a chat of this station/);
  assert.match(await rig.refused(one, "session_history", { chat: linkTwo }), /not shared with your workspace/);
  assert.match(await rig.refused(one, "session_send", { to: linkTwo, text: "hi" }), /not shared with your workspace/);
  assert.match(await rig.refused(two, "chat_read", { chat: "C1/" + one.split(":")[2] }), /no conversation/);
  // Shared with W1 to read: listed there as shared, read by its link, not written to.
  rig.store.setChatShare(two, [{ workspace: W1, name: "One" }], false, "b@x");
  const shared = await rig.call(one, "chat_list", {});
  assert.ok(shared.includes(`${linkTwo} (shared from workspace "Two", read only)`), shared);
  assert.ok(!(await rig.call(two, "chat_list", {})).includes("Shared with this workspace"));
  assert.ok((await rig.call(one, "chat_read", { chat: linkTwo })).startsWith("Conversation"));
  assert.match(await rig.refused(one, "session_send", { to: linkTwo, text: "hi" }), /read only/);
  // To write: sent.
  rig.store.setChatShare(two, [{ workspace: W1, name: "One" }], true, "b@x");
  assert.match(await rig.call(one, "session_send", { to: linkTwo, text: "hi from one" }), /^Sent to/);
  // (a letter: in that chat's own log of them, store/schema.ts LETTERS)
  assert.ok(rig.letters(rig.store.homeChat(two)!.id).at(-1)!.text.endsWith("hi from one"));
  // A station of another workspace W2's members said to take chats from: asked for W2's sessions only, saying so.
  await t.xshare.trust("W9", "Nine", "H", "host", W2);
  assert.deepEqual(t.xshare.address("H", { method: "session.read", workspace: W2 }), { method: "session.read", workspace: "W9", as: W2 });
  assert.deepEqual(t.xshare.address("H", { method: "session.read", workspace: W1 }), { method: "session.read", workspace: W1 });
  assert.deepEqual(t.xshare.address("A", { method: "session.read", workspace: W1 }), { method: "session.read", workspace: W1 });
}));

test("station_list, station_task and session_send reach the stations of the session's workspace only", () => withTwo(async (t) => {
  const { one, two, station, asked, rig } = t;
  assert.deepEqual((await station(one, "station_list", {})).stations.map((s: any) => s.id), ["st", "A"]);
  assert.deepEqual((await station(two, "station_list", {})).stations.map((s: any) => s.id), ["st", "B"]);
  assert.equal((await station(two, "station_list", { station: "B" })).tasks, true);
  await assert.rejects(station(one, "station_list", { station: "B" }), /not another station in this workspace/);
  await assert.rejects(station(one, "station_task", { station: "B", action: "list" }), /not another station in this workspace/);
  assert.deepEqual(await station(two, "station_task", { station: "B", action: "list" }), { tasks: [] });
  // A chat on B, a station of W2 only: W1's session is refused, W2's sends.
  const onB = `https://ember.test/o/${W2}/B/ember%3Ac-0123456789`;
  assert.match(await rig.refused(one, "session_send", { to: onB, text: "hi" }), /not another station in this workspace/);
  assert.match(await rig.call(two, "session_send", { to: onB, text: "hi" }), /^Sent to ember:c-0123456789 on station B/);
  // Each asked in its session's workspace (station_list asks each listed station how busy it is).
  assert.deepEqual(asked.map(([to, ws, r]) => [to, ws, r.method]), [["A", W1, "describe"], ["B", W2, "describe"], ["B", W2, "describe"], ["B", W2, "task.list"], ["B", W2, "session.message"]]);
}));

test("what another station asks reaches the chats of the workspace it asked in; a chat it opens is of that workspace", () => withTwo(async (t) => {
  const { rig, one, two } = t;
  const message = { method: "session.message", session: "s9", to: two, text: "hello" };
  await assert.rejects(fromPeer(rig.hub, "A", message, W1), /no session/);
  await assert.rejects(fromPeer(rig.hub, "A", { ...message, to: one }, W2), /no session/);
  assert.equal((await fromPeer(rig.hub, "B", message, W2)).thread.startsWith("EMBER/"), true);
  const made = createForPeer(rig.hub, "B", { session: "s9", key: "k", runtime: "claude", title: "from B" }, W2);
  assert.equal(rig.store.getSession(made.session)?.ws, W2);
  assert.ok(made.link.includes(`/o/${W2}/st/`), made.link);
  // The same key asked in the other workspace is not that chat.
  assert.throws(() => createForPeer(rig.hub, "B", { session: "s9", key: "k", runtime: "claude" }, W1), /gone|another workspace/);
}));

test("a session runs on the profiles allowed in its workspace (all but those withheld from it); picking, pinning and changing respect it", () => withTwo(async (t) => {
  const { rig, one, two } = t;
  rig.edit((raw) => raw.profiles.push({ id: "cc2", runtime: "claude", home: "homes/cc2", withheld: [W2] }));
  assert.equal(rig.session(two).profile, "cc");
  assert.equal(rig.hub.accounts.runOn(two).id, "cc");
  // Pinned or changed to one not for W2: refused.
  assert.throws(() => newSession(rig.hub, { runtime: "claude", createdBy: "b@x", ws: W2, profile: "cc2" }, "en"), /isn't available to this workspace/);
  assert.throws(() => rig.hub.accounts.change(two, { profile: "cc2" }, "en"), /isn't available to this workspace/);
  // The home workspace's sessions run on any.
  const [ofOne] = newSession(rig.hub, { runtime: "claude", createdBy: "a@x", ws: W1, profile: "cc2" }, "en");
  assert.equal(rig.session(ofOne).profile, "cc2");
  assert.equal(rig.hub.accounts.change(ofOne, { profile: "cc" }, "en").profile, "cc");
  // None left for W2: said so, for new chats and for its sessions.
  rig.edit((raw) => (raw.profiles[0].withheld = [W2]));
  assert.throws(() => newSession(rig.hub, { runtime: "claude", createdBy: "b@x", ws: W2 }, "en"), /No Profile can run Claude Code for this workspace's chats/);
  assert.throws(() => rig.hub.accounts.runOn(two), (e: Error) => e.message === tr(stationLang(), "station.session.noProfileHere", { runtime: "Claude Code" }));
  assert.notEqual(rig.hub.accounts.runOn(one).id, undefined);
  // A connect of W2 runs on those allowed there.
  rig.edit((raw) => delete raw.profiles[1 + 1].withheld);
  const connect = { ...rig.config.connects[0]!, workspace: W2 };
  assert.deepEqual(profilesFor(rig.config, connect, W1).map((p) => p.id), ["cc2"]);
  assert.deepEqual(profilesFor(rig.config, rig.config.connects[0]!, W1).map((p) => p.id), ["cc", "cc2"]);
}));

test("each workspace has its own memory and skills: a session gets its workspace's, the pages the viewer's", () => withTwo(async (t) => {
  const { rig, one, two } = t;
  const home = rig.config.agentHome;
  assert.equal(rig.hub.deps.memoryPath(one), join(home, "MEMORY.md"));
  const memoryTwo = rig.hub.deps.memoryPath(two);
  assert.equal(memoryTwo, join(home, "workspaces", W2, "MEMORY.md"));
  assert.ok(existsSync(memoryTwo) && existsSync(join(home, "workspaces", W2, "skills")));
  assert.equal(workspaceAgentHome(home, W1, W1), home);
  assert.equal(workspaceAgentHome(home, null, W1), home);
  assert.throws(() => workspaceAgentHome(home, "../x", W1), /not a workspace id/);
  // The pages: the home workspace's, or the joined one's, each with its own skills.
  mkdirSync(join(home, "skills", "one-project"), { recursive: true });
  writeFileSync(join(home, "skills", "one-project", "SKILL.md"), "---\ndescription: 项目记忆：one\n---\n");
  mkdirSync(join(home, "workspaces", W2, "skills", "two-project"), { recursive: true });
  writeFileSync(join(home, "workspaces", W2, "skills", "two-project", "SKILL.md"), "---\ndescription: 项目记忆：two\n---\n");
  writeFileSync(memoryTwo, "# two's lessons\n");
  const ofTwo = memory(rig.dir, W2);
  assert.deepEqual([ofTwo.global.path, ofTwo.global.text, ofTwo.skills.filter((s: any) => !s.builtin).map((s: any) => [s.name, s.share])], [memoryTwo, "# two's lessons\n", [["two-project", null]]]);
  assert.deepEqual(memory(rig.dir).skills.map((s: any) => s.name), ["one-project"]);
  // A workspace with none yet: empty.
  assert.deepEqual(memory(mkdtempSync(join(tmpdir(), "mws-memory-")), "W3").skills, []);
}));

test("a session's runtime is given its workspace's memory and skills, never another workspace's", () => withTwo(async (t) => {
  const { rig, one, two } = t;
  const home = rig.config.agentHome;
  mkdirSync(join(home, "skills", "one-project"), { recursive: true });
  writeFileSync(join(home, "MEMORY.md"), "# one's lessons\n");
  writeFileSync(join(home, "skills", "one-project", "SKILL.md"), "---\ndescription: 项目记忆：one\n---\n");
  writeFileSync(rig.hub.deps.memoryPath(two), "# two's lessons\n");
  mkdirSync(join(home, "workspaces", W2, "skills", "two-project"), { recursive: true });
  writeFileSync(join(home, "workspaces", W2, "skills", "two-project", "SKILL.md"), "---\ndescription: 项目记忆：two\n---\n");
  // The same profile runs both: what its home holds reaches both, so a workspace's are given with the session.
  const opened = (key: string) => {
    const row = rig.store.getSession(key)!;
    return { row, options: openOptions(row, rig.hub.accounts.runOn(key), rig.hub.deps) };
  };
  const ofTwo = opened(two);
  assert.ok(ofTwo.options.instructions.includes("# two's lessons") && !ofTwo.options.instructions.includes("# one's lessons"));
  assert.equal(ofTwo.options.skills, join(home, "workspaces", W2, "skills"));
  for (const at of [join(".claude", "skills"), join(".agents", "skills")]) {
    // (with the station's own, written into a joined workspace's as it is made)
    assert.deepEqual(readdirSync(join(ofTwo.row.workspace, at)).filter((n) => !n.startsWith("stillfail-")), ["two-project"], at);
    assert.ok(existsSync(join(ofTwo.row.workspace, at, "stillfail-jobs", "SKILL.md")), at);
  }
  const ofOne = opened(one);
  assert.ok(ofOne.options.instructions.includes("# one's lessons") && !ofOne.options.instructions.includes("# two's lessons"));
  assert.deepEqual(readdirSync(join(ofOne.row.workspace, ".claude", "skills")), ["one-project"]);
}));

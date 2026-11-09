// A connect is its workspace's (connects/remote.ts, connects/workspace.ts): it runs on one station, and its chats on any
// station of the workspace. Two stations here, H (the connect's) and S, over a transport of the test's that carries
// what the mesh does (a JSON head, bytes after it).
import assert from "node:assert/strict";
import { readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { PeerBus, bytesOf, withBytes } from "../src/mesh/bus.ts";
import { WorkspaceConnects, fingerprint } from "../src/connects/workspace.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { sessionKey } from "../src/sessions/hub.ts";
import { Rig, message, reply, settle } from "./hub-fakes.ts";

type Json = any;

const H = "aaaa1111";
const S = "bbbb2222";
const roster = [
  { id: H, name: "laptop" },
  { id: S, name: "desktop" },
];

/// What crosses the mesh: its JSON (a copy, as a stream's head is), and the bytes after it as they are.
function across(v: Json): Json {
  const bytes = bytesOf(v);
  const copy = JSON.parse(JSON.stringify(v));
  return bytes === null ? copy : withBytes(copy, bytes);
}

type Station = { rig: Rig; bus: PeerBus; connects: WorkspaceConnects; up: boolean };

/// Two stations of workspace "ws", each a hub of its own whose connects are config.json's and the other's it was told
/// of; H has the Slack connect `cl`.
function workspace(): { h: Station; s: Station; close(): Promise<void> } {
  const stations = new Map<string, Station>();
  const make = (id: string): Station => {
    const rig = new Rig({ place: { workspace: "ws", station: id } });
    const bus = new PeerBus({ sleep: async () => {} });
    const station = { rig, bus, up: true } as Station;
    bus.attach(async (to, ws, request) => {
      const there = stations.get(to);
      if (there === undefined || !there.up) throw new Error("station unreachable");
      return across(await there.bus.handle(ws ?? "ws", id, across(request)));
    });
    const config = () => {
      const read = hubConfig(rig.raw, rig.dir);
      read.connects.push(...station.connects.remote.connects());
      return read;
    };
    Object.defineProperty(rig, "config", { get: config, configurable: true });
    const local = new Map([["cl", rig.chat], ["gpt", rig.gptChat], ["team", rig.teamChat]]);
    rig.hub = rig.newHub({ chats: (c) => (rig.raw.connects.some((e: Json) => e.id === c) ? local.get(c) : undefined) ?? station.connects.remote.surface(c) });
    station.connects = new WorkspaceConnects({
      data: rig.dir,
      hub: () => rig.hub,
      store: rig.store,
      config: { raw: () => rig.raw, update: (f) => f(rig.raw) },
      bus,
      here: () => id,
      home: () => "ws",
      stations: (ws) => (ws === "ws" ? roster : []),
      names: () => null,
    });
    stations.set(id, station);
    return station;
  };
  const h = make(H);
  const s = make(S);
  // S runs no connect of its own: `cl` is H's.
  s.rig.raw.connects = [];
  return { h, s, close: async () => (await h.rig.close(), await s.rig.close()) };
}

test("a new conversation of a connect that names another station runs there; what follows in its thread goes there too, and what its agent says goes out through the connect", async () => {
  const { h, s, close } = workspace();
  h.rig.raw.connects.find((c: Json) => c.id === "cl").station = S;
  const first = message({ text: "<@UBOT> look at the build" });
  await h.connects.receive("cl", { type: "message", message: first });
  await settle();
  const id = `cl@${H}`;
  const key = sessionKey(id, first.channel, first.threadTs);
  assert.ok(s.rig.store.getSession(key), "the session is S's");
  assert.equal(h.rig.store.threadAt("slack:T1", first.channel, first.threadTs), null, "H keeps no thread of it");
  assert.equal(h.rig.store.connectThreadStation("cl", first.channel, first.threadTs), S);
  // Its runtime and model are the connect's; no profile of H's.
  assert.deepEqual([s.rig.session(key).runtime, s.rig.session(key).connect], ["claude", id]);

  // A reply that does not mention the bot: S's session hears it all the same.
  await h.connects.receive("cl", { type: "message", message: reply(first, "1700.9", "and the tests", { addressed: false }) });
  await settle();
  const thread = s.rig.store.threadAt("slack:T1", first.channel, first.threadTs)!;
  assert.deepEqual(s.rig.said(thread.id).map((m) => m.text), ["<@UBOT> look at the build", "and the tests"]);

  // What the agent says, and a file with it, are posted by H's bot.
  s.rig.claude.last().reads();
  const file = join(s.rig.dir, "report.txt");
  writeFileSync(file, "all green");
  const answer = await s.rig.call(key, "chat_post", { to: `${first.channel}/${first.threadTs}`, text: "done", files: [file] });
  assert.ok(answer.startsWith("Posted"), answer);
  assert.equal(h.rig.chat.lastText(), "done");
  assert.deepEqual(h.rig.chat.files.at(-1), ["report.txt"]);
  assert.deepEqual(readdirSync(join(h.rig.dir, "run", "connect-uploads")), [], "the file is not kept after it is posted");
  // The bot S's hub knows is H's bot.
  assert.equal(s.rig.hub.chatOf(id)?.botUserId(), "UBOT");
  await close();
});

test("a conversation that began before stays where it is; one the station named cannot take runs on the connect's own", async () => {
  const { h, s, close } = workspace();
  const before = message({ text: "<@UBOT> hi" });
  await h.connects.receive("cl", { type: "message", message: before });
  await settle();
  const local = sessionKey("cl", before.channel, before.threadTs);
  assert.ok(h.rig.store.getSession(local), "with no station named: here");

  h.rig.raw.connects.find((c: Json) => c.id === "cl").station = S;
  await h.connects.receive("cl", { type: "message", message: reply(before, "1701.1", "<@UBOT> more") });
  await settle();
  assert.equal(h.rig.said(h.rig.thread(before.channel, before.threadTs).id).length, 2, "its thread goes on here");

  s.up = false;
  const fresh = message({ text: "<@UBOT> new" });
  await h.connects.receive("cl", { type: "message", message: fresh });
  await settle();
  assert.ok(h.rig.store.getSession(sessionKey("cl", fresh.channel, fresh.threadTs)), "S off: it runs here");
  assert.equal(h.rig.store.connectThreadStation("cl", fresh.channel, fresh.threadTs), null);
  await close();
});

test("a message for a chat on a station that is off is not lost silently: the thread is told", async () => {
  const { h, s, close } = workspace();
  h.rig.raw.connects.find((c: Json) => c.id === "cl").station = S;
  const first = message({ text: "<@UBOT> go" });
  await h.connects.receive("cl", { type: "message", message: first });
  await settle();
  s.up = false;
  await h.connects.receive("cl", { type: "message", message: reply(first, "1702.1", "still there?", { addressed: false }) });
  assert.match(h.rig.chat.lastText(), /desktop/);
  await close();
});

test("a connect moved to another station runs there, under the id the workspace knows it by; the chats here go on through it", async () => {
  const { h, s, close } = workspace();
  const here = message({ text: "<@UBOT> hi" });
  await h.connects.receive("cl", { type: "message", message: here });
  await settle();
  const key = sessionKey("cl", here.channel, here.threadTs);

  await h.connects.move("cl", S, "ws");
  assert.equal(h.rig.raw.connects.some((c: Json) => c.id === "cl"), false);
  const moved = s.rig.raw.connects.find((c: Json) => c.id === `cl@${H}`);
  assert.equal(moved?.kind ?? "slack", "slack");
  assert.equal(moved.workspace, undefined, "of S's home workspace: none said");
  assert.equal(s.rig.store.connectThreadStation(`cl@${H}`, here.channel, here.threadTs), H, "H's chat stays H's");

  // S runs the connect now (its own surface, as its Slack part would connect it).
  const local = new Map([[`cl@${H}`, s.rig.chat]]);
  s.rig.hub = s.rig.newHub({ chats: (c) => local.get(c) ?? s.connects.remote.surface(c) });
  // What H's chat says goes out through S's connection.
  const answer = await h.rig.call(key, "chat_post", { to: `${here.channel}/${here.threadTs}`, text: "from H" });
  assert.ok(answer.startsWith("Posted"), answer);
  assert.equal(s.rig.chat.lastText(), "from H");
  // And what comes in its thread reaches H's session.
  await s.connects.receive(`cl@${H}`, { type: "message", message: reply(here, "1703.1", "thanks", { addressed: false }) });
  await settle();
  assert.deepEqual(h.rig.said(h.rig.thread(here.channel, here.threadTs).id).map((m) => m.text).at(-1), "thanks");
  await close();
});

test("a connect is added on one station of the workspace: the same bot on another is refused, named by where it is", async () => {
  const { h, s, close } = workspace();
  h.rig.raw.connects.find((c: Json) => c.id === "cl").slack = { botToken: "xoxb-1", appToken: "xapp-1" };
  assert.equal(await s.connects.heldBy("ws", "slack", { botToken: "xoxb-1" }), "laptop");
  assert.equal(await s.connects.heldBy("ws", "slack", { botToken: "xoxb-2" }), null);
  assert.equal(fingerprint("slack", {}), null, "one with no token yet is not asked about");
  await close();
});

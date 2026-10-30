// A chat's grant of a person's phone (adb/grants.ts, docs/adb-share.md): asked with a card in the chat, decided by the
// person the chat's agent works for, ended as its scope runs out, as its chat is archived or as it is taken back; and
// a grant's adb server alone let into the phone's port (adb/servers.ts `allowed`).
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import net from "node:net";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PhoneGrants, type PhoneRequest } from "../src/adb/grants.ts";
import { platform } from "../src/platform/index.ts";
import { STILLFAIL_SURFACE } from "../src/store/store.ts";

function world() {
  let now = 1_800_000_000_000;
  const cards: { ts: string; card: any }[] = [];
  const told: string[] = [];
  const heard: PhoneRequest[] = [];
  const sessions = new Map<string, { archivedAt?: number | null }>([["s1", {}], ["s2", {}]]);
  const subscribers: ((c: { type: string; key: string }) => void)[] = [];
  let n = 0;
  const hub = {
    store: {
      getSession: (k: string) => sessions.get(k) ?? null,
      participants: (s: string) => new Map([[s, ["Pat@Example.com"]]]),
      latestThread: () => ({ connect: "c", thread: { id: 1, channel: "EMBER", threadTs: "1.0", surface: STILLFAIL_SURFACE } }) as any,
      insertMessage: (m: any) => {
        cards.push({ ts: m.ts, card: m.card });
        return [++n];
      },
      withdrawCard: () => true,
      restateCard: (_a: string, _t: number, ts: string, f: (was: any) => any) => {
        const c = cards.find((x) => x.ts === ts)!;
        c.card = f(c.card);
        return true;
      },
      subscribe: (f: (c: { type: string; key: string }) => void) => void subscribers.push(f),
    },
    chat: () => ({ post: async () => `t${n + 1}` }),
    shared: () => {},
    notify: (_s: string, text: string) => void told.push(text),
  };
  let ids = 0;
  const grants = new PhoneGrants({ db: new DatabaseSync(":memory:"), hub, now: () => now, told: (r) => void heard.push({ ...r }), id: () => `p${++ids}` });
  return {
    grants, cards, told, heard,
    pass: (ms: number) => void (now += ms),
    archive: (s: string) => {
      sessions.set(s, { archivedAt: now });
      for (const f of subscribers) f({ type: "session", key: s });
    },
  };
}

test("a phone asked for in a chat: a card to the person its agent works for, granted to that chat alone", async () => {
  const w = world();
  // Asked: answered at once, the card posted, nothing decided (the agent goes on; it is told of the decision).
  const asked = await w.grants.ask("s1", "install the build and look at its first screen");
  assert.equal(asked.status, "pending");
  assert.equal(asked.owner, "pat@example.com");
  assert.equal(w.cards.length, 1);
  assert.equal(w.cards[0]!.card.assignee, "pat@example.com");
  assert.deepEqual(w.cards[0]!.card.adb, { request: "p1", reason: "install the build and look at its first screen", lasts: "chat" });
  assert.deepEqual(w.cards[0]!.card.options.map((o: any) => o.label), ["本对话 1 小时内", "本对话直到归档", "拒绝"]);
  // Asked again before it is decided: the same request, no second card.
  assert.equal((await w.grants.ask("s1", "again")).id, "p1");
  assert.equal(w.cards.length, 1);
  // Only its person decides it.
  assert.match(w.grants.decide("someone@example.com", "p1", "chat")!, /only the person/);
  assert.equal(w.grants.decide("pat@example.com", "p1", "hour"), null);
  assert.equal(w.grants.get("p1")!.status, "granted");
  assert.deepEqual(w.cards[0]!.card.adb.outcome, { status: "granted", scope: "hour" });
  assert.match(w.told.at(-1)!, /granted \(for an hour\)/);
  // That chat's alone: another chat holds nothing, and asks for its own.
  assert.equal(w.grants.held("s1").length, 1);
  assert.equal(w.grants.held("s2").length);
  assert.equal((await w.grants.ask("s1", "more")).id, "p1");
  // Its hour over, it ends; the agent is told.
  w.pass(3600_000);
  assert.equal(w.grants.held("s1").length);
  assert.equal(w.grants.get("p1")!.status, "ended");
  assert.match(w.told.at(-1)!, /ended \(授权已到期\)/);
});

test("a grant until the chat is archived ends with it, and its owner takes one back", async () => {
  const w = world();
  await w.grants.ask("s1", "debug the crash");
  assert.equal(w.grants.decide("pat@example.com", "p1", "chat"), null);
  await w.grants.ask("s2", "screenshots");
  assert.equal(w.grants.decide("pat@example.com", "p2", "chat"), null);
  assert.deepEqual(w.grants.ofOwner("PAT@example.com").map((r) => r.id), ["p1", "p2"]);
  w.archive("s1");
  assert.equal(w.grants.get("p1")!.status, "ended");
  assert.equal(w.grants.get("p1")!.why, "对话已归档");
  assert.match(w.grants.revoke("other@example.com", "p2")!, /only its owner/);
  assert.equal(w.grants.revoke("pat@example.com", "p2"), null);
  assert.equal(w.grants.get("p2")!.status, "ended");
  assert.deepEqual(w.cards[1]!.card.adb.outcome, { status: "ended", scope: "chat", why: "已收回" });
  assert.deepEqual(w.grants.ofOwner("pat@example.com"), []);
  // Each change heard (the owner's devices are told: `adb-grant`).
  assert.deepEqual(w.heard.map((r) => `${r.id} ${r.status}`), ["p1 pending", "p1 granted", "p2 pending", "p2 granted", "p1 ended", "p2 ended"]);
});

test("its owner's 默认最长授权: the card offers no longer, and a longer grant is refused", async () => {
  const w = world();
  assert.equal(w.grants.lastsOf("pat@example.com"), "chat");
  assert.equal(w.grants.setLasts("Pat@example.com", "hour", 10), null);
  // an older setting (another device's, said late) does not take its place
  assert.equal(w.grants.setLasts("pat@example.com", "chat", 5), null);
  assert.equal(w.grants.lastsOf("pat@example.com"), "hour");
  await w.grants.ask("s1", "x");
  assert.deepEqual(w.cards[0]!.card.options.map((o: any) => o.label), ["本对话 1 小时内", "拒绝"]);
  assert.equal(w.cards[0]!.card.adb.lasts, "hour");
  assert.match(w.grants.decide("pat@example.com", "p1", "chat")!, /默认最长授权/);
  assert.equal(w.grants.decide("pat@example.com", "p1", "hour"), null);
});

test("refused, the agent is told, and a request of an archived chat is not granted", async () => {
  const w = world();
  await w.grants.ask("s1", "x");
  assert.equal(w.grants.decide("pat@example.com", "p1", null), null);
  assert.equal(w.grants.get("p1")!.status, "denied");
  assert.match(w.told.at(-1)!, /refused/);
  await w.grants.ask("s2", "y");
  w.archive("s2");
  assert.equal(w.grants.get("p2")!.status, "denied");
  assert.match(w.grants.decide("pat@example.com", "p2", "chat")!, /denied already/);
  await assert.rejects(w.grants.ask("s1", " "), /reason/);
});

test("who holds the other end of a loopback connection is told by its port", async () => {
  const server = net.createServer();
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const port = (server.address() as net.AddressInfo).port;
  const accepted = new Promise<net.Socket>((r) => server.once("connection", r));
  // Another process connects (as an adb server would), and stays until killed.
  const child = spawn(process.execPath, ["-e", `require("net").connect(${port}, "127.0.0.1"); setInterval(() => {}, 1000)`], { stdio: "ignore" });
  try {
    const socket = await accepted;
    const pids = await platform.tcpPortPids(socket.remotePort!);
    assert.ok(pids.includes(child.pid!), `${socket.remotePort}: ${pids.join(", ")}`);
    assert.ok(!pids.includes(process.pid));
    socket.destroy();
  } finally {
    child.kill("SIGKILL");
    server.close();
  }
});

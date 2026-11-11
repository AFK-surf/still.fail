// A chat's grant of a person's phone (adb/grants.ts): asked with a card in the chat, decided by the
// person the chat's agent works for, ended as its scope runs out, as its chat is archived or as it is taken back; and
// a grant's adb server alone let into the phone's port (adb/servers.ts `allowed`).
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import net from "node:net";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PhoneGrants, type PhoneRequest } from "../src/adb/grants.ts";
import { phoneTools } from "../src/adb/tool.ts";
import { platform } from "../src/platform/index.ts";
import { STILLFAIL_SURFACE } from "../src/store/store.ts";

function world() {
  let now = 1_800_000_000_000;
  const cards: { ts: string; card: any }[] = [];
  const told: string[] = [];
  const heard: PhoneRequest[] = [];
  const audiences: (string | null | undefined)[] = [];
  const changes: string[] = [];
  const titles = new Map([["s1", "First chat"], ["s2", "Second chat"], ["s3", "Home chat"]]);
  const sessions = new Map<string, { archivedAt?: number | null; ws: string | null; workspace: string }>([
    ["s1", { ws: "work-a", workspace: "/chat/s1" }],
    ["s2", { ws: "work-b", workspace: "/chat/s2" }],
    ["s3", { ws: null, workspace: "/chat/s3" }],
  ]);
  const subscribers: ((c: { type: string; key?: string; id?: number; ws?: string | null }) => void)[] = [];
  let n = 0;
  let hidden = false;
  let latestReads = 0;
  let hasChats = true;
  let originalJoined = true;
  const hub = {
    store: {
      getSession: (k: string) => sessions.get(k) ?? null,
      starter: () => "pat@example.com",
      latestThread: () => {
        latestReads++;
        return hasChats ? ({ connect: "c", thread: { id: 1, channel: "CHAT", threadTs: "1.0", surface: STILLFAIL_SURFACE } }) as any : null;
      },
      sessionThreadById: () => originalJoined ? ({ connect: "c", thread: { id: 1, channel: "CHAT", threadTs: "1.0", surface: STILLFAIL_SURFACE } }) as any : null,
      insertMessage: (m: any) => {
        cards.push({ ts: m.ts, card: m.card });
        hidden = false;
        return [++n];
      },
      pendingCardHeader: (): [{ ts: string }, unknown] | null => hidden || cards.length === 0 ? null : [{ ts: cards.at(-1)!.ts }, cards.at(-1)!.card],
      withdrawCard: () => true,
      restateCard: (_a: string, _t: number, ts: string, f: (was: any) => any) => {
        const c = cards.find((x) => x.ts === ts)!;
        c.card = f(c.card);
        return true;
      },
      threadSessions: (thread: number) => thread === 1 ? [{ session: "s1" }] : [],
      subscribe: (f: (c: { type: string; key?: string; id?: number; ws?: string | null }) => void) => void subscribers.push(f),
    },
    chat: () => ({ post: async () => `t${n + 1}` }),
    shared: () => {},
    notify: (_s: string, text: string) => void told.push(text),
  };
  let ids = 0;
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE thread_sessions(thread INTEGER NOT NULL,session TEXT NOT NULL,joined_at INTEGER NOT NULL,PRIMARY KEY(thread,session)); INSERT INTO thread_sessions VALUES(1,'s1',1)");
  const grants = new PhoneGrants({ db, hub, home: () => "home", title: (r) => titles.get(r.session) ?? null, now: () => now, told: (r, workspace, change) => { heard.push({ ...r }); audiences.push(workspace); changes.push(change); }, id: () => `p${++ids}` });
  return {
    db, hub, grants, cards, told, heard, audiences, changes, hideCard: () => { hidden = true; }, showCard: () => { hidden = false; },
    latestReads: () => latestReads,
    withoutOriginal: () => { originalJoined = false; },
    withoutChats: () => { hasChats = false; },
    pass: (ms: number) => void (now += ms),
    archive: (s: string) => {
      sessions.set(s, { ...sessions.get(s)!, archivedAt: now });
      for (const f of subscribers) f({ type: "session", key: s });
    },
    remove: (s: string) => {
      const ws = sessions.get(s)!.ws;
      sessions.delete(s);
      for (const f of subscribers) f({ type: "sessionRemoved", key: s, ws });
    },
    rename: (s: string, title: string) => {
      titles.set(s, title);
      for (const f of subscribers) f({ type: "thread", id: 1 });
    },
  };
}

test("what the person's device signed goes with the grant to their phone, read by no one here", async () => {
  const w = world();
  try {
    await w.grants.ask("s1", "debug the screen");
    const signed = { body: { v: 1, request: "p1" }, sig: { key: "ed25519:aa", sig: "bb" } };
    assert.equal(w.grants.decide("pat@example.com", "p1", "hour", "work-a", signed), null);
    assert.deepEqual(w.grants.get("p1")!.signed, signed);
    assert.deepEqual(w.grants.shown(w.grants.get("p1")!).signed, signed);
  } finally {
    w.db.close();
  }
});

test("phone request status stays consistent as it is asked, granted and ended", async () => {
  const w = world();
  try {
    const status = () => {
      const row = w.db.prepare("SELECT status,body FROM adb_requests WHERE id='p1'").get() as { status: string; body: string };
      assert.equal(JSON.parse(row.body).status, row.status);
      return row.status;
    };
    await w.grants.ask("s1", "debug the screen");
    assert.equal(status(), "pending");
    assert.equal(w.grants.decide("pat@example.com", "p1", "hour", "work-a"), null);
    assert.equal(status(), "granted");
    w.pass(3600_000);
    assert.deepEqual(w.grants.held("s1"), []);
    assert.equal(status(), "ended");
  } finally { w.db.close(); }
});

test("internal owner grant reads end expired grants and retain the other live ones", async () => {
  const w = world();
  try {
    await w.grants.ask("s1", "one hour");
    assert.equal(w.grants.decide("pat@example.com", "p1", "hour", "work-a"), null);
    await w.grants.ask("s2", "until archived");
    assert.equal(w.grants.decide("pat@example.com", "p2", "chat", "work-b"), null);
    w.pass(3600_000);
    assert.deepEqual(w.grants.grantedOfOwner("PAT@example.com").map((r) => r.id), ["p2"]);
    assert.equal(w.grants.get("p1")!.status, "ended");
    assert.equal(w.heard.at(-1)!.status, "ended");
    assert.equal(w.audiences.at(-1), "work-a");
  } finally { w.db.close(); }
});

test("an internal owner grant read does not cause a title notification for an unseen request", () => {
  const w = world();
  try {
    const request: PhoneRequest = { id: "old", session: "s1", chat: "CHAT/1.0", owner: "pat@example.com",
      reason: "test", at: 1, status: "granted", exp: 1_800_003_600 };
    w.db.prepare("INSERT INTO adb_requests(id,session,owner,status,body) VALUES(?,?,?,?,?)")
      .run(request.id, request.session, request.owner, request.status, JSON.stringify(request));
    assert.deepEqual(w.grants.grantedOfOwner("pat@example.com").map((r) => r.id), ["old"]);
    w.rename("s1", "Renamed");
    assert.deepEqual(w.heard, []);
  } finally { w.db.close(); }
});

test("reusing a pending phone request does not find the latest of the session's other chats", async () => {
  const w = world();
  const first = await w.grants.ask("s1", "debug the screen");
  const before = w.latestReads();
  assert.equal((await w.grants.ask("s1", "again")).id, first.id);
  assert.equal(w.latestReads(), before, "the original joined chat is enough to reuse the request");
  w.hideCard();
  assert.equal((await w.grants.ask("s1", "again", true)).id, first.id);
  assert.equal(w.latestReads(), before, "asking again puts the card in its original chat");
  assert.equal(w.cards.length, 2);
});

test("a pending phone request still needs a joined chat when its original chat is gone", async () => {
  const w = world();
  const first = await w.grants.ask("s1", "debug the screen");
  w.withoutOriginal();
  assert.equal((await w.grants.ask("s1", "again")).id, first.id, "another joined chat still permits reuse");
  await assert.rejects(w.grants.ask("s1", "again", true), /original conversation is no longer available/);
  w.withoutChats();
  await assert.rejects(w.grants.ask("s1", "again"), /no chat to ask in/);
});

test("phone grants are listed, decided and announced only in their chat's workspace", async () => {
  const w = world();
  await w.grants.ask("s1", "debug here");
  await w.grants.ask("s2", "debug there");
  await w.grants.ask("s3", "debug in the home workspace");
  const listed = (ws: string) => w.grants.ofOwner("pat@example.com", ws).map((r) => r.id);
  assert.deepEqual(listed("work-a"), ["p1"]);
  assert.deepEqual(listed("work-b"), ["p2"]);
  assert.deepEqual(listed("home"), ["p3"]);
  assert.deepEqual(w.audiences, ["work-a", "work-b", "home"]);
  assert.match(w.grants.decide("pat@example.com", "p1", "chat", "work-b")!, /no such request/);
  assert.equal(w.grants.get("p1")!.status, "pending");
  assert.equal(w.grants.decide("pat@example.com", "p1", "chat", "work-a"), null);
  assert.equal(w.audiences.at(-1), "work-a");
  assert.match(w.grants.revoke("pat@example.com", "p1", "work-b")!, /no such request/);
  assert.equal(w.grants.get("p1")!.status, "granted");
  // Deletion removes the session row before notifying: the end still goes to that chat's workspace.
  w.remove("s1");
  assert.equal(w.grants.get("p1")!.status, "ended");
  assert.equal(w.audiences.at(-1), "work-a");
  assert.deepEqual(listed("work-a"), []);
});

test("a still-needed phone request can be asked again after its card stopped waiting", async () => {
  const w = world();
  const first = await w.grants.ask("s1", "debug the screen");
  w.hideCard();
  const tool = phoneTools(w.grants, async () => "ready")[0]!;
  assert.match(await tool.run("s1", { reason: "debug the screen" }), /card is no longer pending/);
  assert.equal(w.cards.length, 1, "checking does not ask the person again");
  w.cards.push({ ts: "another", card: { type: "text" } });
  w.showCard();
  await assert.rejects(w.grants.ask("s1", "debug the screen", true), /Another card is pending/);
  w.hideCard();
  const again = await w.grants.ask("s1", "debug the screen", true);
  assert.equal(again.id, first.id, "the existing authorization request is reused");
  assert.equal(w.cards.length, 3, "there is an actionable new card");
  assert.equal(w.cards[2]!.card.adb.request, first.id);
  assert.equal(w.grants.decide("pat@example.com", first.id, "hour", "work-a"), null);
  assert.equal(w.cards[2]!.card.adb.outcome.status, "granted");
});

test("a phone reask rechecks its request after old card preparation", async () => {
  const w = world(), started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  try {
    const first = await w.grants.ask("s1", "debug the screen");
    w.hideCard();
    let ready = false;
    (w.hub.store as any).pendingCardHeaderIfReady = () => ready ? w.hub.store.pendingCardHeader() : undefined;
    (w.hub as any).prepareCardPosts = async () => { started.resolve(); await release.promise; ready = true; };
    const reask = w.grants.ask("s1", "debug the screen", true);
    const waiting = await Promise.race([started.promise.then(() => true), reask.then(() => false)]);
    assert.equal(waiting, true, "the reask waits for old card preparation");
    assert.equal(w.grants.decide("pat@example.com", first.id, "hour", "work-a"), null);
    release.resolve();
    assert.equal((await reask).status, "granted");
    assert.equal(w.cards.length, 1, "a decided request is not asked again");
  } finally { release.resolve(); w.db.close(); }
});

test("a cancelled phone reask does not post after old card preparation", async () => {
  const w = world(), started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  const controller = new AbortController();
  try {
    await w.grants.ask("s1", "debug the screen");
    w.hideCard();
    let ready = false, passed: AbortSignal | undefined;
    (w.hub.store as any).pendingCardHeaderIfReady = () => ready ? w.hub.store.pendingCardHeader() : undefined;
    (w.hub as any).prepareCardPosts = async (_threads: number[], signal?: AbortSignal) => { passed = signal; started.resolve(); await release.promise; ready = true; };
    const tool = phoneTools(w.grants, async () => "ready")[0]!;
    const reask = tool.run("s1", { reason: "debug the screen", reask: true }, controller.signal);
    void reask.catch(() => {});
    assert.equal(await Promise.race([started.promise.then(() => true), reask.then(() => false, () => false)]), true);
    assert.equal(passed, controller.signal, "the background preparation can release this caller's wait");
    controller.abort();
    release.resolve();
    const error = await reask.then(() => null, (e: Error) => e);
    assert.equal(w.cards.length, 1, "the cancelled call did not issue a new card");
    assert.equal(error?.name, "AbortError");
  } finally { release.resolve(); w.db.close(); }
});

test("a cancelled phone card check leaves old card preparation", async () => {
  const w = world(), started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  const controller = new AbortController();
  try {
    await w.grants.ask("s1", "debug the screen");
    w.hideCard();
    let ready = false, passed: AbortSignal | undefined;
    (w.hub.store as any).pendingCardHeaderIfReady = () => ready ? w.hub.store.pendingCardHeader() : undefined;
    (w.hub as any).prepareCardPosts = async (_threads: number[], signal?: AbortSignal) => { passed = signal; started.resolve(); await release.promise; ready = true; };
    const tool = phoneTools(w.grants, async () => "ready")[0]!;
    const checking = tool.run("s1", { reason: "debug the screen" }, controller.signal);
    void checking.catch(() => {});
    assert.equal(await Promise.race([started.promise.then(() => true), checking.then(() => false, () => false)]), true);
    assert.equal(passed, controller.signal);
    controller.abort();
    release.resolve();
    await assert.rejects(checking, { name: "AbortError" });
    assert.equal(w.cards.length, 1);
  } finally { release.resolve(); w.db.close(); }
});

test("a phone reask does not record a card decided during final old-card preparation", async () => {
  const w = world(), started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  try {
    const first = await w.grants.ask("s1", "debug the screen");
    w.hideCard();
    let reads = 0, ready = false;
    (w.hub.store as any).pendingCardHeaderIfReady = () => ++reads === 1 || ready ? w.hub.store.pendingCardHeader() : undefined;
    (w.hub as any).prepareCardPosts = async () => { started.resolve(); await release.promise; ready = true; };
    const reask = w.grants.ask("s1", "debug the screen", true);
    const waiting = await Promise.race([started.promise.then(() => true), reask.then(() => false)]);
    assert.equal(waiting, true, "the final card check waits for preparation");
    assert.equal(w.grants.decide("pat@example.com", first.id, "hour", "work-a"), null);
    release.resolve();
    assert.equal((await reask).status, "granted");
    assert.equal(w.cards.length, 1, "a card for the decided request was not recorded");
  } finally { release.resolve(); w.db.close(); }
});

test("a cancelled phone reask does not record a card after final old-card preparation", async () => {
  const w = world(), started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  const controller = new AbortController();
  try {
    await w.grants.ask("s1", "debug the screen");
    w.hideCard();
    let reads = 0, ready = false;
    (w.hub.store as any).pendingCardHeaderIfReady = () => ++reads === 1 || ready ? w.hub.store.pendingCardHeader() : undefined;
    (w.hub as any).prepareCardPosts = async () => { started.resolve(); await release.promise; ready = true; };
    const tool = phoneTools(w.grants, async () => "ready")[0]!;
    const reask = tool.run("s1", { reason: "debug the screen", reask: true }, controller.signal);
    void reask.catch(() => {});
    assert.equal(await Promise.race([started.promise.then(() => true), reask.then(() => false, () => false)]), true);
    controller.abort();
    release.resolve();
    const error = await reask.then(() => null, (e: Error) => e);
    assert.equal(w.cards.length, 1, "no card was recorded after cancellation");
    assert.equal(error?.name, "AbortError");
  } finally { release.resolve(); w.db.close(); }
});

test("a grant reports its chat title and actual use, and follows a rename", async () => {
  const w = world();
  await w.grants.ask("s1", "look at the keyboard");
  assert.equal(w.grants.decide("pat@example.com", "p1", "chat", "work-a"), null);
  assert.equal(w.grants.ofOwner("pat@example.com", "work-a")[0]!.chatTitle, "First chat");
  assert.equal(w.grants.get("p1")!.lastUsedAt, undefined);
  w.pass(5000);
  w.grants.used("p1", true);
  const at = w.grants.get("p1")!.lastUsedAt;
  assert.equal(at, 1_800_000_005_000);
  assert.equal(w.changes.at(-1), "used");
  assert.equal(w.audiences.at(-1), "work-a");
  // A rename is sent even while no command is run, without changing the use time.
  w.rename("s1", "Keyboard investigation");
  assert.equal((w.heard.at(-1) as PhoneRequest & { chatTitle: string }).chatTitle, "Keyboard investigation");
  assert.equal(w.changes.at(-1), "title");
  assert.equal(w.grants.get("p1")!.lastUsedAt, at);
  assert.equal(w.grants.revoke("pat@example.com", "p1", "work-a"), null);
  assert.equal(w.grants.get("p1")!.lastUsedAt, undefined);
  w.pass(5000);
  w.grants.used("p1", true);
  assert.equal(w.grants.get("p1")!.lastUsedAt, undefined);
});

test("a phone asked for in a chat: a card to the person its agent works for, granted to that chat alone", async () => {
  const w = world();
  // Asked: answered at once, the card posted, nothing decided (the agent goes on; it is told of the decision).
  const asked = await w.grants.ask("s1", "install the build and look at its first screen");
  assert.equal(asked.status, "pending");
  assert.equal(asked.owner, "pat@example.com");
  assert.equal(w.cards.length, 1);
  assert.equal(w.cards[0]!.card.assignee, "pat@example.com");
  assert.deepEqual(w.cards[0]!.card.adb, { request: "p1", reason: "install the build and look at its first screen", lasts: "chat" });
  assert.deepEqual(w.cards[0]!.card.options.map((o: any) => o.label), ["本对话 1 小时内", "闲置 1 小时后失效", "本对话 8 小时内", "本对话直到归档", "拒绝"]);
  // (an hour unused recommended, as a device's grant is)
  assert.deepEqual(w.cards[0]!.card.options.filter((o: any) => o.recommended).map((o: any) => o.label), ["闲置 1 小时后失效"]);
  // Asked again before it is decided: the same request, no second card.
  assert.equal((await w.grants.ask("s1", "again")).id, "p1");
  assert.equal(w.cards.length, 1);
  // Only its person decides it.
  assert.match(w.grants.decide("someone@example.com", "p1", "chat", "work-a")!, /only the person/);
  assert.equal(w.grants.decide("pat@example.com", "p1", "hour", "work-a"), null);
  assert.equal(w.grants.get("p1")!.status, "granted");
  assert.deepEqual(w.cards[0]!.card.adb.outcome, { status: "granted", scope: "hour" });
  assert.match(w.told.at(-1)!, /granted \(for an hour\)/);
  // That chat's alone: another chat holds nothing, and asks for its own.
  assert.equal(w.grants.held("s1").length, 1);
  assert.equal(w.grants.held("s2").length, 0);
  assert.equal((await w.grants.ask("s1", "more")).id, "p1");
  // Its hour over, it ends; the agent is told.
  w.pass(3600_000);
  assert.equal(w.grants.held("s1").length, 0);
  assert.equal(w.grants.get("p1")!.status, "ended");
  assert.match(w.told.at(-1)!, /ended \(授权已到期\)/);
});

test("a grant until the chat is archived ends with it, and its owner takes one back", async () => {
  const w = world();
  await w.grants.ask("s1", "debug the crash");
  assert.equal(w.grants.decide("pat@example.com", "p1", "chat", "work-a"), null);
  await w.grants.ask("s2", "screenshots");
  assert.equal(w.grants.decide("pat@example.com", "p2", "chat", "work-b"), null);
  assert.deepEqual(w.grants.ofOwner("PAT@example.com").map((r) => r.id), ["p1", "p2"]);
  w.archive("s1");
  assert.equal(w.grants.get("p1")!.status, "ended");
  assert.equal(w.grants.get("p1")!.why, "对话已归档");
  assert.match(w.grants.revoke("other@example.com", "p2", "work-b")!, /only its owner/);
  assert.equal(w.grants.revoke("pat@example.com", "p2", "work-b"), null);
  assert.equal(w.grants.get("p2")!.status, "ended");
  assert.deepEqual(w.cards[1]!.card.adb.outcome, { status: "ended", scope: "chat", why: "已收回" });
  assert.deepEqual(w.grants.ofOwner("pat@example.com"), []);
  // Each change heard (the owner's devices are told: `adb-grant`).
  assert.deepEqual(w.heard.map((r) => `${r.id} ${r.status}`), ["p1 pending", "p1 granted", "p2 pending", "p2 granted", "p1 ended", "p2 ended"]);
});

test("its agent hands the phone back when done: the grant ends, its card says so, and its comings and goings wake it no more", async () => {
  const w = world();
  const [tool] = phoneTools(w.grants, async () => "reached");
  // Nothing held: nothing to hand back.
  assert.match(await tool!.run("s1", { done: true }) as string, /nothing to hand back/);
  await tool!.run("s1", { reason: "check the login screen" });
  assert.equal(w.grants.decide("pat@example.com", "p1", "chat", "work-a"), null);
  w.grants.linked("pat@example.com", { adb: "connected" });
  const told = w.told.length;
  assert.match(await tool!.run("s1", { done: true }) as string, /Handed back: p1/);
  assert.equal(w.grants.get("p1")!.status, "ended");
  assert.deepEqual(w.cards[0]!.card.adb.outcome, { status: "ended", scope: "chat", why: "agent 已交还" });
  // Its owner's devices hear it (their phone stops being lent for it); the agent, who asked, is not told again.
  assert.equal(w.heard.at(-1)!.status, "ended");
  assert.deepEqual(w.grants.ofOwner("pat@example.com"), []);
  w.grants.linked("pat@example.com", null);
  w.grants.linked("pat@example.com", { adb: "unpaired" });
  w.grants.linked("pat@example.com", { adb: "connected" });
  assert.equal(w.told.length, told);
  // A request not yet decided is withdrawn the same way; another chat's grant is not touched.
  await tool!.run("s1", { reason: "again" });
  await tool!.run("s2", { reason: "screenshots" });
  assert.equal(w.grants.decide("pat@example.com", "p3", "hour", "work-b"), null);
  await tool!.run("s1", { done: true });
  assert.equal(w.grants.get("p2")!.status, "denied");
  assert.equal(w.grants.get("p3")!.status, "granted");
  // Asking needs a reason still.
  await assert.rejects(tool!.run("s1", {}), /reason/);
});

test("a granted card says how its station's adb holds the phone, and its agent is told as it is reached", async () => {
  const w = world();
  await w.grants.ask("s1", "install the mod");
  assert.equal(w.grants.decide("pat@example.com", "p1", "chat", "work-a"), null);
  assert.deepEqual(w.cards[0]!.card.adb.outcome, { status: "granted", scope: "chat" });
  const told = w.told.length;
  // Lent here, this station's adb not paired with it: the card says so, the agent is told to leave it to the card.
  w.grants.linked("Pat@Example.com", { adb: "connecting" });
  assert.equal(w.grants.get("p1")!.link, undefined);
  w.grants.linked("Pat@Example.com", { adb: "unpaired", message: "not paired" });
  assert.deepEqual(w.cards[0]!.card.adb.outcome, { status: "granted", scope: "chat", link: "unpaired" });
  assert.equal(w.told.length, told + 1);
  assert.match(w.told.at(-1)!, /pairing is still needed.*card under the phone request/);
  // Tried again and again while unpaired: said once.
  w.grants.linked("pat@example.com", { adb: "connecting" });
  w.grants.linked("pat@example.com", { adb: "unpaired" });
  assert.equal(w.told.length, told + 1);
  // Paired: connected, said on the card and told.
  w.grants.linked("pat@example.com", { adb: "connected" });
  assert.deepEqual(w.cards[0]!.card.adb.outcome, { status: "granted", scope: "chat", link: "connected" });
  assert.match(w.told.at(-1)!, /is connected to this station's adb now/);
  // Offered no longer: the card says so, the agent is not woken for it.
  w.grants.linked("pat@example.com", null);
  assert.equal(w.cards[0]!.card.adb.outcome.link, "gone");
  assert.equal(w.told.length, told + 2);
  // Ended, the card's outcome says no more of it.
  assert.equal(w.grants.revoke("pat@example.com", "p1", "work-a"), null);
  assert.deepEqual(w.cards[0]!.card.adb.outcome, { status: "ended", scope: "chat", why: "已收回" });
});

test("every card offers every length (默认最长授权 went), and any is granted", async () => {
  const w = world();
  await w.grants.ask("s1", "x");
  assert.deepEqual(w.cards[0]!.card.options.map((o: any) => o.label), ["本对话 1 小时内", "闲置 1 小时后失效", "本对话 8 小时内", "本对话直到归档", "拒绝"]);
  assert.equal(w.cards[0]!.card.options.find((o: any) => o.recommended)?.label, "闲置 1 小时后失效");
  assert.equal(w.cards[0]!.card.adb.lasts, "chat");
  assert.equal(w.grants.decide("pat@example.com", "p1", "chat", "work-a"), null);
});

test("refused, the agent is told, and a request of an archived chat is not granted", async () => {
  const w = world();
  await w.grants.ask("s1", "x");
  assert.equal(w.grants.decide("pat@example.com", "p1", null, "work-a"), null);
  assert.equal(w.grants.get("p1")!.status, "denied");
  assert.match(w.told.at(-1)!, /refused/);
  await w.grants.ask("s2", "y");
  w.archive("s2");
  assert.equal(w.grants.get("p2")!.status, "denied");
  assert.match(w.grants.decide("pat@example.com", "p2", "chat", "work-b")!, /denied already/);
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

test("any member's phone asked for (device_use): the card goes to that person, named in the chat; one request each, handed back alone", async () => {
  const w = world();
  try {
    const r = await w.grants.ask("s1", "check the Pixel", false, undefined, "Kim@Example.com");
    assert.equal(r.owner, "kim@example.com");
    assert.equal(w.cards.at(-1)!.card.assignee, "kim@example.com");
    // Asked again of the same person: that request; of another: one more.
    assert.equal((await w.grants.ask("s1", "again", false, undefined, "kim@example.com")).id, r.id);
    const mine = await w.grants.ask("s1", "my own phone");
    assert.equal(mine.owner, "pat@example.com");
    assert.notEqual(mine.id, r.id);
    assert.equal(w.grants.decide("kim@example.com", r.id, "hour", "work-a"), null);
    // Handed back by whose: that one alone ends.
    assert.deepEqual(w.grants.release("s1", "kim@example.com").map((x) => x.id), [r.id]);
    assert.equal(w.grants.get(mine.id)!.status, "pending");
  } finally {
    w.db.close();
  }
});

test("a phone granted until idle an hour: kept while the chat uses it, ended an hour after it last did; eight hours fixed", async () => {
  const w = world();
  try {
    await w.grants.ask("s1", "debug the screen");
    assert.equal(w.grants.decide("pat@example.com", "p1", "idle", "work-a"), null);
    w.pass(50 * 60_000);
    w.grants.used("p1", true);
    w.pass(50 * 60_000);
    assert.equal(w.grants.held("s1").length, 1, "used 50 minutes ago: held");
    w.pass(11 * 60_000);
    assert.deepEqual(w.grants.held("s1"), []);
    assert.equal(w.grants.get("p1")!.why, "闲置超时");
    await w.grants.ask("s1", "again");
    assert.equal(w.grants.decide("pat@example.com", "p2", "eight", "work-a"), null);
    w.pass(7 * 3600_000);
    assert.equal(w.grants.held("s1").length, 1);
    w.pass(3600_000);
    assert.deepEqual(w.grants.held("s1"), []);
    assert.match(w.grants.decide("pat@example.com", "p2", "week" as any, "work-a")!, /no such request|scope|already/);
  } finally {
    w.db.close();
  }
});

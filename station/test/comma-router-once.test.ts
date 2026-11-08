import assert from "node:assert/strict";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { ROUTER_TARGETS_INSERT, routerSays, routerSaysAfter } from "../src/comma/chats.ts";
import { CommaStats } from "../src/comma/stats.ts";
import { MANUAL, MessageWriteBusy, Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

const nothing = async () => ({ stations: [], unread: [] });
const quiet = () => () => {};

function member(rig: Rig, key: string) {
  rig.store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
    createdAt: 1, lastActiveAt: 1, ws: null } as never);
}

test("recording Router targets seeks the key and only visits the provided members", async () => {
  const rig = new Rig();
  try {
    const plan = (rig.store.db.prepare(`EXPLAIN QUERY PLAN ${ROUTER_TARGETS_INSERT}`)
      .all('["a"]', "cm:key") as { detail: string }[]).map((row) => row.detail);
    assert.ok(plan.some((row) => row.startsWith("SEARCH o ") && row.includes("(key=?)")), plan.join(" | "));
    assert.ok(plan.some((row) => row.startsWith("SCAN j VIRTUAL TABLE")), plan.join(" | "));
  } finally { await rig.close(); }
});

test("a Router write treats an older session without a workspace as part of home", async () => {
  const rig = new Rig({ workspaces: ["home"] });
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const n = routerSays(rig.hub, stats, "home", { thread: thread.id, text: "home", key: "cm:old-home", requester: "Router", connect: "cm" });
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => m.message.n), [n]);
  } finally { stats.close(); await rig.close(); }
});

test("a Router retry after the deduplication database is locked does not repeat its message", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  const blocker = new DatabaseSync(join(rig.dir, "comma-stats.db"));
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const home = rig.hub.wsOf("a");
    const w = { thread: thread.id, text: "send once", key: "cm:k1", requester: "Router", connect: "cm" };
    const put = blocker.prepare("INSERT INTO stats_index (key,source,kind,rev,json) VALUES (?,'stillfail','task',?,'{}')");
    put.run("one", 1); put.run("two", 2);
    const cursor = blocker.prepare("SELECT key FROM stats_index ORDER BY rev").iterate();
    assert.equal(cursor.next().done, false);
    try { assert.throws(() => routerSays(rig.hub, stats, home, w), /database is locked/); }
    finally { cursor.return?.(); }
    const n = routerSays(rig.hub, stats, home, w);
    assert.equal(routerSays(rig.hub, stats, home, w), n);
    assert.equal(stats.said(w.key), n);
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0).filter((e) => e.kind === "message").map((e) => [e.n, e.text]), [[n, "send once"]]);
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => [m.message.n, m.message.text]), [[n, "send once"]]);
  } finally { blocker.close(); stats.close(); await rig.close(); }
});

test("a retry finishes delivery of the original message even if its text and recipients changed", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a"); member(rig, "b"); member(rig, "c");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember"); rig.store.joinThread(thread.id, "b", "ember");
    const home = rig.hub.wsOf("a");
    const w = { thread: thread.id, text: "original", key: "cm:k2", requester: "Router", connect: "cm" };
    const deliver = rig.hub.deliver;
    rig.hub.deliver = () => { throw new Error("interrupted before delivery"); };
    try { assert.throws(() => routerSays(rig.hub, stats, home, w), /interrupted before delivery/); }
    finally { rig.hub.deliver = deliver; }
    rig.store.joinThread(thread.id, "c", "ember");
    const n = routerSays(rig.hub, stats, home, { ...w, thread: -1, text: "-stop" });
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0).filter((e) => e.kind === "message").map((e) => [e.n, e.text]), [[n, "original"]]);
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => [m.message.n, m.message.text]), [[n, "original"]]);
    assert.deepEqual(rig.store.pendingMessages("b").map((m) => [m.message.n, m.message.text]), [[n, "original"]]);
    assert.deepEqual(rig.store.pendingMessages("c"), []);
  } finally { stats.close(); await rig.close(); }
});

test("a retry does not deliver an earlier message to a session that rejoined after it was recorded", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a"); member(rig, "b"); member(rig, "c");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember"); rig.store.joinThread(thread.id, "b", "ember"); rig.store.joinThread(thread.id, "c", "ember");
    rig.store.leaveThread(thread.id, "b");
    rig.store.setArchived("c", true, MANUAL);
    const w = { thread: thread.id, text: "before rejoining", key: "cm:rejoin", requester: "Router", connect: "cm" };
    const deliver = rig.hub.deliver;
    rig.hub.deliver = () => { throw new Error("delivery interrupted"); };
    try { assert.throws(() => routerSays(rig.hub, stats, rig.hub.wsOf("a"), w), /delivery interrupted/); }
    finally { rig.hub.deliver = deliver; }
    rig.store.joinThread(thread.id, "b", "ember");
    rig.store.setArchived("c", false, MANUAL);
    const n = routerSays(rig.hub, stats, rig.hub.wsOf("a"), w);
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => m.message.n), [n]);
    assert.deepEqual(rig.store.pendingMessages("b"), []);
    assert.deepEqual(rig.store.pendingMessages("c"), []);
  } finally { stats.close(); await rig.close(); }
});

test("a Router message includes a member who joined before the message was recorded", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a"); member(rig, "b");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const insert = rig.store.insertMessage;
    rig.store.insertMessage = (...args) => {
      rig.store.joinThread(thread.id, "b", "ember");
      return insert.apply(rig.store, args);
    };
    let n: number;
    try {
      n = routerSays(rig.hub, stats, rig.hub.wsOf("a"), { thread: thread.id, text: "after joining", key: "cm:join-before", requester: "Router", connect: "cm" });
    } finally { rig.store.insertMessage = insert; }
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => m.message.n), [n]);
    assert.deepEqual(rig.store.pendingMessages("b").map((m) => m.message.n), [n]);
  } finally { stats.close(); await rig.close(); }
});

test("a Router message is not recorded if its chat moved workspaces before the write", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const home = rig.hub.wsOf("a");
    const insert = rig.store.insertMessage;
    rig.store.insertMessage = (...args) => {
      rig.store.db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run("another-workspace", "a");
      return insert.apply(rig.store, args);
    };
    try {
      assert.throws(() => routerSays(rig.hub, stats, home, { thread: thread.id, text: "not here", key: "cm:move-before", requester: "Router", connect: "cm" }), /no such chat of the workspace/);
    } finally { rig.store.insertMessage = insert; }
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0), []);
    assert.deepEqual(rig.store.pendingMessages("a"), []);
  } finally { stats.close(); await rig.close(); }
});

test("a Router message is not recorded if its chat was archived before the write", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const insert = rig.store.insertMessage;
    rig.store.insertMessage = (...args) => {
      rig.store.setThreadHidden(thread.id, true, MANUAL);
      return insert.apply(rig.store, args);
    };
    try {
      assert.throws(() => routerSays(rig.hub, stats, rig.hub.wsOf("a"), { thread: thread.id, text: "not now", key: "cm:archive-before", requester: "Router", connect: "cm" }));
    } finally { rig.store.insertMessage = insert; }
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0), []);
    assert.deepEqual(rig.store.pendingMessages("a"), []);
  } finally { stats.close(); await rig.close(); }
});

test("a Router delivery waits if the chat moves workspaces after recording", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const home = rig.hub.wsOf("a");
    const w = { thread: thread.id, text: "one message", key: "cm:move-before-delivery", requester: "Router", connect: "cm" };
    const deliver = rig.store.deliver;
    rig.store.deliver = (...args) => {
      rig.store.db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run("another-workspace", "a");
      return deliver.apply(rig.store, args);
    };
    try { assert.throws(() => routerSays(rig.hub, stats, home, w), /no such chat of the workspace/); }
    finally { rig.store.deliver = deliver; }
    assert.deepEqual(rig.store.pendingMessages("a"), []);
    rig.store.db.prepare("UPDATE sessions SET ws = NULL WHERE key = ?").run("a");
    const n = routerSays(rig.hub, stats, home, w);
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0).map((e) => [e.n, e.text]), [[n, "one message"]]);
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => m.message.n), [n]);
  } finally { stats.close(); await rig.close(); }
});

test("a retry after reopening the station finishes the original interrupted delivery", async () => {
  const rig = new Rig({ fileStore: true });
  let stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const w = { thread: thread.id, text: "survives restart", key: "cm:restart", requester: "Router", connect: "cm" };
    const deliver = rig.hub.deliver;
    rig.hub.deliver = () => { throw new Error("delivery interrupted"); };
    try { assert.throws(() => routerSays(rig.hub, stats, rig.hub.wsOf("a"), w), /delivery interrupted/); }
    finally { rig.hub.deliver = deliver; }
    stats.close();
    await rig.hub.shutdown();
    rig.store.close();
    rig.store = Store.open(join(rig.dir, "stillfail.db"), null);
    rig.hub = rig.newHub({ chats: () => undefined });
    rig.hub.hold("drain");
    stats = CommaStats.at(rig.dir, nothing, quiet);
    const n = routerSays(rig.hub, stats, rig.hub.wsOf("a"), { ...w, text: "different retry" });
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0).map((e) => [e.n, e.text]), [[n, "survives restart"]]);
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => [m.message.n, m.message.text]), [[n, "survives restart"]]);
  } finally { stats.close(); await rig.close(); }
});

test("an interrupted Router write is not delivered after its chat moves to another workspace", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const home = rig.hub.wsOf("a");
    const w = { thread: thread.id, text: "original", key: "cm:workspace", requester: "Router", connect: "cm" };
    const deliver = rig.hub.deliver;
    rig.hub.deliver = () => { throw new Error("delivery interrupted"); };
    try { assert.throws(() => routerSays(rig.hub, stats, home, w), /delivery interrupted/); }
    finally { rig.hub.deliver = deliver; }
    rig.store.db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run("another-workspace", "a");
    assert.throws(() => routerSays(rig.hub, stats, home, w), /no such chat of the workspace/);
    assert.deepEqual(rig.store.pendingMessages("a"), []);
    rig.store.db.prepare("UPDATE sessions SET ws = NULL WHERE key = ?").run("a");
    const n = routerSays(rig.hub, stats, home, w);
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => m.message.n), [n]);
  } finally { stats.close(); await rig.close(); }
});

for (const text of ["queued message", "-stop"]) test(`retry wakes a queued ${text === "-stop" ? "command" : "message"} after interruption`, async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const actor = rig.hub.actor(rig.session("a"));
    const kick = actor.kick, stop = actor.stop;
    let kicks = 0, stops = 0;
    actor.kick = async () => { kicks++; };
    actor.stop = async () => { stops++; };
    const deliver = rig.hub.deliver;
    rig.hub.deliver = (t, n, sessions) => { rig.store.deliver(t, n, sessions); throw new Error("interrupted before wake"); };
    const w = { thread: thread.id, text, key: "cm:wake", requester: "Router", connect: "cm" };
    try {
      assert.throws(() => routerSays(rig.hub, stats, rig.hub.wsOf("a"), w), /interrupted before wake/);
      rig.hub.deliver = deliver;
      const n = routerSays(rig.hub, stats, rig.hub.wsOf("a"), w);
      assert.equal(routerSays(rig.hub, stats, rig.hub.wsOf("a"), w), n);
      assert.equal(kicks, text === "-stop" ? 0 : 1);
      assert.equal(stops, text === "-stop" ? 1 : 0);
      assert.equal(rig.store.deliveryPending(thread.id, n, "a"), text !== "-stop");
    } finally { rig.hub.deliver = deliver; actor.kick = kick; actor.stop = stop; }
  } finally { stats.close(); await rig.close(); }
});

test("failure to record the key rolls the message back, so a later write can complete", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const home = rig.hub.wsOf("a");
    const w = { thread: thread.id, text: "only after commit", key: "cm:atomic", requester: "Router", connect: "cm" };
    rig.store.db.exec("CREATE TRIGGER fail_router_key BEFORE INSERT ON comma_router_once BEGIN SELECT RAISE(ABORT, 'key write failed'); END");
    assert.throws(() => routerSays(rig.hub, stats, home, w), /key write failed/);
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0), []);
    assert.deepEqual(rig.store.pendingMessages("a"), []);
    rig.store.db.exec("DROP TRIGGER fail_router_key");
    const n = routerSays(rig.hub, stats, home, w);
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0).map((e) => [e.n, e.text]), [[n, "only after commit"]]);
    assert.equal(routerSays(rig.hub, stats, home, w), n);
  } finally { stats.close(); await rig.close(); }
});

for (const first of ["other connection", "write lock"] as const) test(`two connections racing with one key: ${first} first`, async () => {
  const rig = new Rig({ fileStore: true });
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  const otherStats = CommaStats.at(rig.dir, nothing, quiet);
  const otherStore = Store.open(join(rig.dir, "stillfail.db"), null);
  const ownStore = rig.store;
  rig.store = otherStore;
  const otherHub = rig.newHub({ chats: () => undefined });
  rig.store = ownStore;
  try {
    rig.hub.hold("drain"); otherHub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const home = rig.hub.wsOf("a");
    const w = { thread: thread.id, text: "one message", key: "cm:race", requester: "Router", connect: "cm" };
    const insert = rig.store.insertMessage;
    const threadSessions = rig.store.threadSessions;
    let other: number | null = null;
    let attempted = false;
    if (first === "other connection") rig.store.insertMessage = (...args) => {
      if (!attempted) { attempted = true; other = routerSays(otherHub, otherStats, home, w); }
      return insert.apply(rig.store, args);
    };
    else rig.store.threadSessions = (id) => {
      if (!attempted) {
        attempted = true;
        assert.throws(() => routerSays(otherHub, otherStats, home, w), /retry the Router request with the same key/);
      }
      return threadSessions.call(rig.store, id);
    };
    let n: number;
    try { n = routerSays(rig.hub, stats, home, w); }
    finally { rig.store.insertMessage = insert; rig.store.threadSessions = threadSessions; }
    assert.equal(attempted, true);
    if (first === "write lock") other = routerSays(otherHub, otherStats, home, w);
    assert.equal(n, other);
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0).filter((e) => e.kind === "message").map((e) => [e.n, e.text]), [[n, "one message"]]);
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => m.message.n), [n]);
  } finally { await otherHub.shutdown(); otherStore.close(); otherStats.close(); stats.close(); await rig.close(); }
});

test("a busy delivery or completion can be retried with the same Router key", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const home = rig.hub.wsOf("a");
    const w = { thread: thread.id, text: "send once", key: "cm:busy-delivery", requester: "Router", connect: "cm" };
    const deliver = rig.store.deliver;
    rig.store.deliver = () => { throw new MessageWriteBusy(); };
    try { assert.throws(() => routerSays(rig.hub, stats, home, w), /retry the Router request with the same key/); }
    finally { rig.store.deliver = deliver; }
    assert.equal(rig.store.entriesAfter(thread.id, 0).length, 1);
    assert.deepEqual(rig.store.pendingMessages("a"), []);
    const complete = rig.store.completeRouterWrite;
    rig.store.completeRouterWrite = () => { throw new MessageWriteBusy(); };
    try { assert.throws(() => routerSays(rig.hub, stats, home, w), /retry the Router request with the same key/); }
    finally { rig.store.completeRouterWrite = complete; }
    const n = routerSays(rig.hub, stats, home, w);
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0).map((e) => [e.n, e.text]), [[n, "send once"]]);
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => m.message.n), [n]);
  } finally { stats.close(); await rig.close(); }
});

test("a Router write is refused until the old process has actually exited", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    let exited!: () => void;
    const gone = new Promise<void>((resolve) => { exited = resolve; });
    const said = routerSaysAfter(rig.hub, stats, () => rig.hub.wsOf("a"), gone);
    const w = { thread: thread.id, text: "after handover", key: "cm:handover", requester: "Router", connect: "cm" };
    assert.throws(() => said(w), /still handing over/);
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0), []);
    exited();
    await gone;
    const n = said(w);
    assert.deepEqual(rig.store.entriesAfter(thread.id, 0).map((e) => [e.n, e.text]), [[n, "after handover"]]);
    assert.equal(said(w), n);
  } finally { stats.close(); await rig.close(); }
});

test("deleting a session also removes it from an interrupted Router delivery", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a"); member(rig, "b");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember"); rig.store.joinThread(thread.id, "b", "ember");
    const w = { thread: thread.id, text: "original", key: "cm:delete", requester: "Router", connect: "cm" };
    const deliver = rig.hub.deliver;
    rig.hub.deliver = () => { throw new Error("delivery interrupted"); };
    try { assert.throws(() => routerSays(rig.hub, stats, rig.hub.wsOf("a"), w), /delivery interrupted/); }
    finally { rig.hub.deliver = deliver; }
    const targets = () => (rig.store.db.prepare("SELECT session FROM comma_router_once_targets ORDER BY session").all() as { session: string }[]).map((r) => r.session);
    assert.deepEqual(targets(), ["a", "b"]);
    rig.store.deleteSession("b");
    assert.deepEqual(targets(), ["a"]);
    rig.store.deleteSession("a");
    assert.deepEqual(targets(), []);
    assert.equal((rig.store.db.prepare("SELECT COUNT(*) AS n FROM comma_router_once").get() as { n: number }).n, 0);
  } finally { stats.close(); await rig.close(); }
});

test("a session removed after the Router message is recorded is not recreated as a delivery", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a"); member(rig, "b");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember"); rig.store.joinThread(thread.id, "b", "ember");
    const home = rig.hub.wsOf("a");
    const deliver = rig.hub.deliver;
    rig.hub.deliver = (...args) => {
      rig.store.deleteSession("b");
      return deliver.apply(rig.hub, args);
    };
    let n: number;
    try { n = routerSays(rig.hub, stats, home, { thread: thread.id, text: "one message", key: "cm:removed-during-write", requester: "Router", connect: "cm" }); }
    finally { rig.hub.deliver = deliver; }
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => m.message.n), [n]);
    assert.equal(rig.store.db.prepare("SELECT 1 FROM deliveries WHERE session = ?").get("b"), undefined);
  } finally { stats.close(); await rig.close(); }
});

test("a removed member from an older station is not reintroduced by a retry", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a"); member(rig, "b");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember"); rig.store.joinThread(thread.id, "b", "ember");
    const w = { thread: thread.id, text: "original", key: "cm:old-deletion", requester: "Router", connect: "cm" };
    const deliver = rig.hub.deliver;
    rig.hub.deliver = () => { throw new Error("delivery interrupted"); };
    try { assert.throws(() => routerSays(rig.hub, stats, rig.hub.wsOf("a"), w), /delivery interrupted/); }
    finally { rig.hub.deliver = deliver; }
    // An older station does not know about the new targets table when it removes a session.
    rig.store.db.prepare("DELETE FROM thread_sessions WHERE session = ?").run("b");
    rig.store.db.prepare("DELETE FROM sessions WHERE key = ?").run("b");
    const n = routerSays(rig.hub, stats, rig.hub.wsOf("a"), w);
    assert.deepEqual(rig.store.pendingMessages("a").map((m) => m.message.n), [n]);
    assert.equal(rig.store.db.prepare("SELECT 1 FROM deliveries WHERE session = 'b'").get(), undefined);
  } finally { stats.close(); await rig.close(); }
});

test("expiration of a large interrupted delivery is bounded and cannot deliver a partial target list", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const home = rig.hub.wsOf("a");
    rig.store.db.prepare("INSERT INTO comma_router_once (key, thread, n, at, pending) VALUES (?, ?, 1, ?, 1)")
      .run("cm:expired", thread.id, Date.now() - 32 * 24 * 60 * 60_000);
    const put = rig.store.db.prepare(`INSERT INTO comma_router_once_targets (id, position, session)
      SELECT id, ?, ? FROM comma_router_once WHERE key = 'cm:expired'`);
    for (let i = 0; i < 100; i++) put.run(i, `old-${i}`);
    const w = { thread: thread.id, text: "new", key: "cm:new-1", requester: "Router", connect: "cm" };
    routerSays(rig.hub, stats, home, w);
    const old = rig.store.db.prepare("SELECT pending FROM comma_router_once WHERE key = 'cm:expired'").get() as { pending: number };
    assert.equal(old.pending, 2);
    assert.equal((rig.store.db.prepare("SELECT COUNT(*) AS n FROM comma_router_once_targets").get() as { n: number }).n, 36);
    assert.throws(() => routerSays(rig.hub, stats, home, { ...w, key: "cm:expired" }), /write has expired/);
    routerSays(rig.hub, stats, home, { ...w, key: "cm:new-2" });
    assert.equal(rig.store.db.prepare("SELECT 1 FROM comma_router_once WHERE key = 'cm:expired'").get(), undefined);
    assert.equal((rig.store.db.prepare("SELECT COUNT(*) AS n FROM comma_router_once_targets").get() as { n: number }).n, 0);
  } finally { stats.close(); await rig.close(); }
});

test("a retry finishing an expired write cannot complete a newer write that reused its key", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(rig.dir, nothing, quiet);
  try {
    rig.hub.hold("drain");
    member(rig, "a");
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const home = rig.hub.wsOf("a");
    const w = { thread: thread.id, text: "old write", key: "cm:reuse", requester: "Router", connect: "cm" };
    const deliver = rig.hub.deliver;
    rig.hub.deliver = () => { throw new Error("interrupted before delivery"); };
    try { assert.throws(() => routerSays(rig.hub, stats, home, w), /interrupted before delivery/); }
    finally { rig.hub.deliver = deliver; }
    rig.store.db.prepare("UPDATE comma_router_once SET at = ? WHERE key = ?")
      .run(Date.now() - 32 * 24 * 60 * 60_000, w.key);

    // Between the old retry reading its targets and finishing, a second connection could expire the marker and
    // accept this key as a new write. Interrupt that newer write before delivery too.
    const members = rig.store.threadSessions.bind(rig.store);
    let raced = false;
    rig.store.threadSessions = (id) => {
      if (!raced) {
        raced = true;
        routerSays(rig.hub, stats, home, { ...w, key: "cm:cleanup", text: "cleanup" });
        rig.hub.deliver = () => { throw new Error("new delivery interrupted"); };
        try { assert.throws(() => routerSays(rig.hub, stats, home, { ...w, text: "new write" }), /new delivery interrupted/); }
        finally { rig.hub.deliver = deliver; }
      }
      return members(id);
    };
    try {
      try { routerSays(rig.hub, stats, home, w); }
      catch (error) { assert.match(String(error), /expired|changed/); }
    } finally { rig.store.threadSessions = members; }

    const n = routerSays(rig.hub, stats, home, { ...w, text: "different retry" });
    assert.equal(rig.store.pendingMessages("a").some((m) => m.message.n === n && m.message.text === "new write"), true);
  } finally { stats.close(); await rig.close(); }
});

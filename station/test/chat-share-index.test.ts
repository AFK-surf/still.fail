import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { chatShareIndexReady, chatShareIndexStep, dueChatShareRows, installChatShareIndex, lapsedChatShareWorkspaces, liveChatShareRows } from "../src/store/chat-share-index.ts";
import { XSHARE_IDLE_MS, liveShare, shareLive, toChatShare } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";
import { ChatShareIndexBuilder } from "../src/xshare/index-builder.ts";
import { testClock } from "./hub-fakes.ts";

const add = "INSERT INTO chat_shares(session,shared,write,by,at) VALUES (?,?,0,'a',?)";
const share = (...to: { workspace: string; used: number }[]) => JSON.stringify(to);
const finish = (db: DatabaseSync) => { while (!chatShareIndexReady(db)) assert.ok(chatShareIndexStep(db, 3).visited <= 3); };
const legacy = (db: DatabaseSync, now: number, since: number, guests: string[]) => {
  const rows = db.prepare("SELECT * FROM chat_shares").all();
  const live = rows.flatMap((row) => {
    const value = liveShare(toChatShare(row), now);
    return value === null ? [] : [[row.session, value] as const];
  });
  const lapsed = new Set(rows.flatMap((row) => toChatShare(row).to
    .filter((t) => guests.includes(t.workspace) && !shareLive(t, now)).map((t) => t.workspace)));
  let next: number | null = null;
  const due: string[] = [];
  for (const row of rows) {
    const ends = toChatShare(row).to.map((t) => t.used + XSHARE_IDLE_MS);
    if (ends.some((end) => end > since && end <= now)) due.push(row.session as string);
    for (const end of ends) if (end > now && (next === null || end < next)) next = end;
  }
  return { live, lapsed: [...lapsed].sort(), due, next };
};

for (const recursive of [false, true]) test(`share lookup follows old writes and replacements (recursive triggers ${recursive})`, () => {
  const dir = mkdtempSync(join(tmpdir(), "share-index-")), path = join(dir, "store.db"), time = testClock();
  const store = Store.open(path, null, time.clock), db = store.db, old = new DatabaseSync(path), now = store.now();
  const insert = old.prepare(add), replace = old.prepare(add.replace("INSERT INTO", "INSERT OR REPLACE INTO"));
  const guests = ["one", "two", "three", "never"];
  const check = () => {
    const expected = legacy(db, now, now - 200, guests);
    assert.deepEqual([...store.chatShares()], expected.live);
    assert.deepEqual([...store.lapsedShareWorkspaces(guests)].sort(), expected.lapsed);
    assert.equal(store.lapseChatShares(now - 200), expected.next);
    const actual = dueChatShareRows(db, now - 200, now);
    assert.notEqual(actual, null);
    const due = actual!.rows.filter((row) => toChatShare(row).to.some((t) => t.used + XSHARE_IDLE_MS > now - 200 && t.used + XSHARE_IDLE_MS <= now))
      .map((row) => row.session);
    assert.deepEqual(due, expected.due);
  };
  try {
    old.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    insert.run("a", share({ workspace: "one", used: now - XSHARE_IDLE_MS - 100 }), now);
    insert.run("b", share({ workspace: "two", used: now - 1000 }, { workspace: "three", used: now - XSHARE_IDLE_MS - 500 }), now);
    installChatShareIndex(db);
    assert.equal(chatShareIndexStep(db, 1).visited, 1);
    insert.run("0-before", share({ workspace: "three", used: now - 10 }), now);
    insert.run("z-after", share({ workspace: "one", used: now - XSHARE_IDLE_MS - 1000 }), now);
    finish(db);
    check();
    replace.run("b", share({ workspace: "one", used: now - 100 }), now);
    old.prepare("UPDATE chat_shares SET shared = ? WHERE session = ?")
      .run(share({ workspace: "two", used: now - XSHARE_IDLE_MS - 10 }), "a");
    old.prepare("DELETE FROM chat_shares WHERE session = ?").run("z-after");
    check(); // Current dirty keys overlay stale index entries without waiting for the worker.
    finish(db);
    check();
    const rowid = old.prepare("SELECT rowid FROM chat_shares WHERE session = 'b'").get()?.rowid;
    old.prepare("INSERT OR REPLACE INTO chat_shares(rowid,session,shared,write,by,at) VALUES (?,?,?,0,'a',?)")
      .run(rowid!, "replaced-rowid", share({ workspace: "three", used: now - 50 }), now);
    check();
    finish(db);
    check();
    for (let i = 0; i < 65; i++) insert.run(`dirty-${i}`, share({ workspace: "one", used: now - 1 }), now);
    assert.equal(liveChatShareRows(db, now), null);
    assert.equal(dueChatShareRows(db, now - 200, now), null);
    assert.equal(lapsedChatShareWorkspaces(db, guests, now), null);
    finish(db);
    check();
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("unusual old share values keep the old JavaScript deadline rule", () => {
  const time = testClock(), store = Store.open(":memory:", null, time.clock), db = store.db, now = store.now();
  try {
    const insert = db.prepare(add);
    insert.run("invalid", "not json", now);
    insert.run("old", JSON.stringify([{ workspace: "one" }]), "not-a-number");
    installChatShareIndex(db); finish(db);
    assert.equal(liveChatShareRows(db, now), null);
    const expected = legacy(db, now, now - 200, ["one"]);
    assert.deepEqual([...store.chatShares()], expected.live);
    assert.deepEqual([...store.lapsedShareWorkspaces(["one"])].sort(), expected.lapsed);
    assert.equal(store.lapseChatShares(now - 200), expected.next);
    db.prepare("DELETE FROM chat_shares WHERE session = 'old'").run();
    finish(db);
    assert.notEqual(liveChatShareRows(db, now), null);
  } finally { store.close(); }
});

test("share preparation waits for handover and a closed builder settles its wait", async () => {
  const store = Store.open(":memory:"), previous = Promise.withResolvers<void>();
  const builder = new ChatShareIndexBuilder(store, previous.promise);
  try {
    const insert = store.db.prepare(add);
    for (let i = 0; i < 40; i++) insert.run(`share-${i}`, share({ workspace: "one", used: 1 }), 1);
    builder.request();
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'chat_share_index_meta'").get(), undefined);
    await builder.close();
    previous.resolve();
    await builder.settled();
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'chat_share_index_meta'").get(), undefined);
  } finally { previous.resolve(); await builder.close(); store.close(); }
});

test("a failed share batch rolls its index entries and cursor back together", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const insert = db.prepare(add);
    for (let i = 0; i < 3; i++) insert.run(`s${i}`, share({ workspace: "one", used: i }), i);
    installChatShareIndex(db);
    db.exec("CREATE TRIGGER fail_share BEFORE INSERT ON chat_share_targets BEGIN SELECT RAISE(ABORT, 'fail'); END");
    assert.throws(() => chatShareIndexStep(db, 2), /fail/);
    assert.equal(db.prepare("SELECT cursor FROM chat_share_index_meta").get()?.cursor, null);
    assert.equal(db.prepare("SELECT count(*) AS n FROM chat_share_targets").get()?.n, 0);
    db.exec("DROP TRIGGER fail_share");
    finish(db);
    assert.equal(db.prepare("SELECT count(*) AS n FROM chat_share_targets").get()?.n, 3);
  } finally { store.close(); }
});

test("each share decision and its pending changes use one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "share-snapshot-")), path = join(dir, "store.db");
  const store = Store.open(path), db = store.db, old = new DatabaseSync(path), now = 10_000;
  try {
    old.prepare(add).run("first", share({ workspace: "one", used: now - XSHARE_IDLE_MS - 100 }), now);
    installChatShareIndex(db); finish(db);
    const observed = (change: () => void) => {
      let changed = false;
      return new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          if (!sql.startsWith("SELECT 1 FROM chat_share_index_meta")) return statement;
          return new Proxy(statement, { get(stmt, part) {
            if (part === "get") return (...args: Parameters<typeof statement.get>) => {
              const result = stmt.get(...args);
              if (!changed) { changed = true; change(); }
              return result;
            };
            const value = Reflect.get(stmt, part, stmt);
            return typeof value === "function" ? value.bind(stmt) : value;
          } });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
    };
    const insert = old.prepare(add), update = old.prepare("UPDATE chat_shares SET shared = ? WHERE session = ?");
    const beforeInsert = observed(() => insert.run("later", share({ workspace: "two", used: now - 1 }), now));
    assert.deepEqual(liveChatShareRows(beforeInsert, now)?.map((row) => row.session), []);
    assert.deepEqual(liveChatShareRows(db, now)?.map((row) => row.session), ["later"]);
    const beforeChange = observed(() => update.run(share({ workspace: "three", used: now - 10 }), "first"));
    assert.deepEqual(dueChatShareRows(beforeChange, now - 200, now)?.rows.map((row) => row.session).sort(), ["first", "later"]);
    // The overlay includes the still-dirty later row, but the deadline filter rejects it.
    const afterChange = dueChatShareRows(db, now - 200, now)!;
    assert.deepEqual(afterChange.rows.filter((row) => toChatShare(row).to.some((t) => t.used + XSHARE_IDLE_MS > now - 200 && t.used + XSHARE_IDLE_MS <= now)), []);
    finish(db);
    const beforeLapse = observed(() => update.run(share({ workspace: "one", used: now - XSHARE_IDLE_MS - 1 }), "first"));
    assert.deepEqual([...lapsedChatShareWorkspaces(beforeLapse, ["one", "three"], now)!], []);
    assert.deepEqual([...lapsedChatShareWorkspaces(db, ["one", "three"], now)!], ["one"]);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a share with two targets tells its chat once when one lapses and keeps its other target", () => {
  const time = testClock(), store = Store.open(":memory:", null, time.clock), db = store.db, now = store.now();
  try {
    db.prepare(add).run("chat", share({ workspace: "due", used: now - XSHARE_IDLE_MS - 100 },
      { workspace: "live", used: now - 1000 }), now);
    installChatShareIndex(db); finish(db);
    const changes: unknown[] = [], stop = store.subscribe((change) => changes.push(change));
    assert.equal(store.lapseChatShares(now - 200), now - 1000 + XSHARE_IDLE_MS);
    stop();
    assert.deepEqual(changes, [
      { type: "session", key: "chat" },
      { type: "chatMark", thread: null, session: "chat", share: { to: [{ workspace: "live", name: "live" }], write: false } },
    ]);
  } finally { store.close(); }
});

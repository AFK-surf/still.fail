import assert from "node:assert/strict";
import { test } from "node:test";
import { failedTurnOf } from "../src/feedback/notice.ts";
import { FAILED_TURN_NEAR, Store } from "../src/store/store.ts";

test("a failure notice does not reread old turns to find its nearest failed turn", () => {
  const visits: number[] = [];
  for (const history of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    let old = 0;
    db.function("old_notice_turn_seen", (id) => { if (String(id).startsWith("old-")) old++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(
        sql === "SELECT * FROM turns WHERE session_key = ? ORDER BY started_at"
          ? sql.replace("WHERE session_key = ?", "WHERE session_key = ? AND old_notice_turn_seen(id)")
          : sql === FAILED_TURN_NEAR ? sql.replace("session_key = ?1", "session_key = ?1 AND old_notice_turn_seen(id)") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      store.insertSession({ key: "mine", connect: "ember", runtime: "codex", profile: "p", workspace: "/w", token: "t", createdAt: 1, lastActiveAt: 1 } as any);
      const chat = store.openThread("ember", "CHAT", "1", null, "a");
      store.joinThread(chat.id, "mine", "ember");
      const add = db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,detail) VALUES (?,'mine','message',?,?,'failed',?)");
      for (let i = 0; i < history; i++) add.run(`old-${i}`, i, i, "old");
      add.run("first", 1_000_000, 1_999_000, "first");
      add.run("second", 1_000_001, 2_001_000, "second");
      Object.defineProperty(store, "db", { value: observed });
      const found = failedTurnOf(store, chat.id, 2_000_000);
      assert.equal(found?.session.key, "mine");
      assert.equal(found?.turn?.detail, "first", "equal distance keeps the earlier-started turn");
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${FAILED_TURN_NEAR}`).all("mine", 1_400_000, 2_005_000, 2_000_000) as { detail: string }[])
        .map((row) => row.detail).join(" | ");
      assert.match(plan, /turns_by_end \(session_key=\? AND ended_at>\? AND ended_at<\?\)/);
      visits.push(old);
    } finally { store.close(); }
  }
  assert.deepEqual(visits, [0, 0]);
});

test("a notice keeps the nearest failure, boundary and tie rules across sessions", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const key of ["a", "b"]) store.insertSession({ key, connect: "ember", runtime: "codex", profile: "p", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1 } as any);
    const chat = store.openThread("ember", "CHAT", "1", null, "a");
    store.joinThread(chat.id, "a", "ember");
    store.joinThread(chat.id, "b", "ember");
    const add = db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,detail) VALUES (?,?,'message',?,?,'failed',?)");
    add.run("outside-before", "a", 1, 1_399_999, "outside-before");
    add.run("boundary-before", "a", 2, 1_400_000, "boundary-before");
    add.run("boundary-after", "b", 3, 2_005_000, "boundary-after");
    db.exec("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,detail) VALUES ('success','a','message',0,2000000,'completed','success')");
    const found = () => failedTurnOf(store, chat.id, 2_000_000);
    assert.equal(found()?.turn?.detail, "boundary-after", "a failure five seconds after the notice is eligible");
    db.prepare("UPDATE turns SET ended_at = 2005001 WHERE id = 'boundary-after'").run();
    assert.equal(found()?.turn?.detail, "boundary-before", "ten minutes before is eligible but one millisecond earlier is not");
    add.run("earlier-start", "a", 5, 1_999_000, "earlier-start");
    add.run("later-start", "a", 6, 2_001_000, "later-start");
    add.run("other-session", "b", 4, 2_001_000, "other-session");
    assert.equal(found()?.turn?.detail, "earlier-start", "equal distances keep session and turn ordering");
    assert.equal(failedTurnOf(store, chat.id, 2_000_000.5)?.turn?.detail, "later-start", "a non-integer notice uses the original rule");
    const none = failedTurnOf(store, chat.id, 5_000_000);
    assert.equal(none?.session.key, "a");
    assert.equal(none?.turn, null);
  } finally { store.close(); }
});

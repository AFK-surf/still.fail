import assert from "node:assert/strict";
import { test } from "node:test";
import { autoArchive } from "../src/sessions/lifecycle.ts";
import { saidScanStep, type SaidScan } from "../src/store/said-state.ts";
import { Rig } from "./hub-fakes.ts";

const later = () => Date.now() + 3 * 86_400_000;

function chat(r: Rig, name: string, who: "agent" | "person", firstOther = false) {
  const thread = r.store.openThread("ember", "EMBER", name, null, "me").id;
  const put = r.store.db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message',?,?,?,?)");
  r.store.db.exec("BEGIN");
  if (firstOther) put.run(thread, 1, "agent", "a", "first", 1);
  for (let n = 2; n <= 5_001; n++) put.run(thread, n, who, who === "agent" ? "a" : "me", "hello", n);
  r.store.db.exec("COMMIT");
  return thread;
}

function track(r: Rig) {
  const db = r.store.db;
  let visited = 0;
  db.function("visit_archive_unread", (_n) => { visited++; return 1; });
  Object.defineProperty(r.store, "db", { configurable: true, value: new Proxy(db, {
    get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(
        sql.includes("SELECT COUNT(*) AS c FROM entries")
          ? sql.replace("AND NOT (author_kind", "AND visit_archive_unread(n) IS NOT NULL AND NOT (author_kind")
          : sql.includes("INDEXED BY entries_said") && sql.includes("ORDER BY n DESC")
            ? sql.replace("ORDER BY n DESC", "AND visit_archive_unread(n) IS NOT NULL ORDER BY n DESC")
            : sql,
      );
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) });
  return { visited: () => visited, restore: () => Object.defineProperty(r.store, "db", { configurable: true, value: db }) };
}

test("auto-archive does not count a long run of unread messages", async () => {
  const r = new Rig();
  try {
    const thread = chat(r, "unread", "agent");
    const trace = track(r);
    try {
      autoArchive(r.hub, later());
      assert.equal(r.store.getThread(thread)?.hiddenAt, null);
      assert.ok(trace.visited() <= 64, `the decision visited ${trace.visited()} messages`);
    } finally { trace.restore(); }
  } finally { await r.close(); }
});

test("auto-archive does not scan a long run of the starter's messages", async () => {
  const r = new Rig();
  try {
    const thread = chat(r, "own", "person", true);
    r.store.setRead("me", thread, 1);
    const trace = track(r);
    try {
      autoArchive(r.hub, later());
      assert.notEqual(r.store.getThread(thread)?.hiddenAt, null);
      assert.ok(trace.visited() <= 64, `the decision visited ${trace.visited()} messages`);
    } finally { trace.restore(); }
  } finally { await r.close(); }
});

test("an old unknown boundary is prepared before archiving", async () => {
  const r = new Rig();
  try {
    const thread = chat(r, "old", "person", true);
    r.store.db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(thread);
    const need: number[] = [];
    const trace = track(r);
    try {
      autoArchive(r.hub, later(), (id: number) => need.push(id));
      assert.equal(r.store.getThread(thread)?.hiddenAt, null, "unknown is not treated as read");
      assert.deepEqual(need, [thread]);
      assert.ok(trace.visited() <= 65, `the foreground visited ${trace.visited()} messages`);
    } finally { trace.restore(); }
    let scan: SaidScan | null = null;
    for (;;) {
      const next = saidScanStep(r.store.db, thread, scan);
      if (next.done) break;
      scan = next.scan;
    }
    autoArchive(r.hub, later());
    assert.equal(r.store.getThread(thread)?.hiddenAt, null, "the older unread message still keeps it open");
    r.store.setRead("me", thread, 1);
    autoArchive(r.hub, later());
    assert.notEqual(r.store.getThread(thread)?.hiddenAt, null, "once known, the read chat can be archived");
  } finally { await r.close(); }
});

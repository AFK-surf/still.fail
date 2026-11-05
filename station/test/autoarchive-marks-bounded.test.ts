import assert from "node:assert/strict";
import { test } from "node:test";
import { autoArchive } from "../src/sessions/lifecycle.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

test("auto-archiving reads marks for its visible candidates, not old chats", async () => {
  const r = new Rig();
  const db = r.store.db;
  try {
    r.store.insertSession({ key: "live", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w/live", token: "live", createdAt: 1, lastActiveAt: 1 });
    const own = r.store.openThread("ember", "EMBER", "own", null, null).id;
    const pin = db.prepare("INSERT INTO pins(viewer,session,at) VALUES (?,?,1)");
    const keep = db.prepare("INSERT INTO kept_chats(viewer,thread) VALUES (?,?)");
    db.exec("BEGIN");
    for (let n = 0; n < 5_000; n++) {
      const viewer = `viewer-${n % 40}`;
      pin.run(viewer, `old-${n}`);
      keep.run(viewer, n + 100);
    }
    pin.run("viewer-39", "live");
    keep.run("viewer-39", own);
    db.exec("COMMIT");
    let pins = 0;
    let kept = 0;
    const queries = new Map<string, string>();
    db.function("visit_pin", () => { pins++; return 1; });
    db.function("visit_keep", () => { kept++; return 1; });
    Object.defineProperty(r.store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (source: string) => {
          let sql = source;
          for (const [table, visit] of [["archive_pin_rows", "visit_pin"], ["archive_keep_rows", "visit_keep"]]) {
            if (sql.includes(`SELECT 1 FROM ${table}`)) queries.set(table!, sql);
            sql = sql.replace(`SELECT 1 FROM ${table}`, `SELECT ${visit}() FROM ${table}`);
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    try {
      assert.equal(autoArchive(r.hub, Date.now() + 3 * 86_400_000), null);
      assert.equal(r.store.getSession("live")?.archivedAt, null);
      assert.equal(r.store.getThread(own)?.hiddenAt, null);
      assert.ok(pins > 0 && pins <= 512 && kept > 0 && kept <= 512, `the archive check read ${pins} pins and ${kept} kept chats`);
      for (const [table, value, key] of [["archive_pin_rows", "live", "session"], ["archive_keep_rows", own, "thread"]] as const) {
        const query = queries.get(table);
        assert.ok(query, `a targeted ${table} lookup was made`);
        const plan = (db.prepare(`EXPLAIN QUERY PLAN ${query}`).all(value) as { detail: string }[])
          .map((row) => row.detail).join(" | ");
        assert.match(plan, new RegExp(`SEARCH ${table} USING PRIMARY KEY \\(${key}=\\?\\)`));
      }
    } finally { Object.defineProperty(r.store, "db", { configurable: true, value: db }); }
  } finally { await r.close(); }
});

for (const viewers of [2, 40, 300]) {
  test(`the archive mark check agrees with all marks for ${viewers} viewers`, () => {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      const pin = db.prepare("INSERT INTO pins(viewer,session,at) VALUES (?,?,1)");
      const keep = db.prepare("INSERT INTO kept_chats(viewer,thread) VALUES (?,?)");
      db.exec("BEGIN");
      for (let i = 0; i < viewers; i++) {
        const viewer = i === 0 ? "" : `viewer-${i}`;
        for (let n = 0; n < 150; n++) {
          pin.run(viewer, `old-${n}`);
          keep.run(viewer, n + 1000);
        }
        pin.run(viewer, `visible-${i}`);
        keep.run(viewer, i);
      }
      db.exec("COMMIT");
      db.exec("UPDATE pins SET rowid = -rowid; UPDATE kept_chats SET rowid = -rowid");
      const expectedPins = store.pinnedSessions();
      const expectedKept = store.keptChats(null);
      const { pinned, kept } = store.archiveMarks();
      if (viewers === 300) {
        Object.defineProperty(store, "pinnedSessions", { configurable: true, value: () => { throw new Error("read all pins"); } });
        Object.defineProperty(store, "keptChats", { configurable: true, value: () => { throw new Error("read all kept chats"); } });
        try {
          assert.equal(pinned("visible-299"), true);
          assert.equal(kept(299), true);
        } finally {
          delete (store as any).pinnedSessions;
          delete (store as any).keptChats;
        }
      }
      for (let i = 0; i < viewers + 20; i++) {
        assert.equal(pinned(`visible-${i}`), expectedPins.has(`visible-${i}`));
        assert.equal(kept(i), expectedKept.has(i));
      }
      assert.equal(pinned("old-30"), true);
      assert.equal(kept(1030), true);
      assert.equal(pinned("missing"), false);
      assert.equal(kept(-1), false);
    } finally { store.close(); }
  });
}

test("an empty automatic archive pass does not read any marks or jobs", async () => {
  const r = new Rig();
  const guarded = ["pinnedSessions", "keptChats", "jobsUp", "listBindings"] as const;
  try {
    for (const name of guarded) {
      Object.defineProperty(r.store, name, { configurable: true, value: () => { throw new Error(`${name} read`); } });
    }
    assert.equal(autoArchive(r.hub, Date.now()), null);
  } finally {
    for (const name of guarded) delete (r.store as any)[name];
    await r.close();
  }
});

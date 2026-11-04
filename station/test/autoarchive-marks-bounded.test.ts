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
    db.function("visit_pin", (_viewer, _session) => { pins++; return 1; });
    db.function("visit_keep", (_viewer, _thread) => { kept++; return 1; });
    Object.defineProperty(r.store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (source: string) => {
          let sql = source;
          for (const [table, key, visit] of [["pins", "session", "visit_pin"], ["kept_chats", "thread", "visit_keep"]]) {
            const check = `${visit}(viewer, ${key}) IS NOT NULL`;
            sql = sql.replace(`SELECT DISTINCT ${key} FROM ${table}`, `SELECT DISTINCT ${key} FROM ${table} WHERE ${check}`)
              .replaceAll(`SELECT MAX(rowid) FROM ${table}`, `SELECT MAX(rowid) FROM ${table} WHERE ${check}`)
              .replaceAll(`SELECT MIN(rowid) FROM ${table}`, `SELECT MIN(rowid) FROM ${table} WHERE ${check}`)
              .replaceAll(`SELECT viewer FROM ${table} ORDER BY viewer LIMIT 1`, `SELECT viewer FROM ${table} WHERE ${check} ORDER BY viewer LIMIT 1`)
              .replaceAll(`SELECT viewer FROM ${table} WHERE viewer >`, `SELECT viewer FROM ${table} WHERE ${check} AND viewer >`)
              .replace(`SELECT 1 FROM ${table} WHERE viewer IN`, `SELECT 1 FROM ${table} WHERE ${check} AND viewer IN`);
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
  try {
    for (const name of ["pinnedSessions", "keptChats", "jobsUp", "listBindings"] as const) {
      Object.defineProperty(r.store, name, { configurable: true, value: () => { throw new Error(`${name} read`); } });
    }
    assert.equal(autoArchive(r.hub, Date.now()), null);
  } finally { await r.close(); }
});

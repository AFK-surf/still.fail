import assert from "node:assert/strict";
import { test } from "node:test";
import { autoArchive, startAutoArchiveTimer } from "../src/sessions/lifecycle.ts";
import { archiveMarksReady, archiveMarksStep, installArchiveMarkIndex } from "../src/store/archive-mark-index.ts";
import { Rig } from "./hub-fakes.ts";

test("automatic archive does not read marks belonging only to other viewers' chats", async () => {
  const r = new Rig(), db = r.store.db;
  try {
    r.store.insertSession({ key: "mine", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/mine",
      token: "mine", createdAt: 1, lastActiveAt: 1 });
    const own = r.store.openThread("ember", "EMBER", "own", null, null).id;
    const pin = db.prepare("INSERT INTO pins(viewer,session,at) VALUES (?,?,1)");
    const keep = db.prepare("INSERT INTO kept_chats(viewer,thread) VALUES (?,?)");
    const add = (from: number, to: number) => {
      for (let i = from; i < to; i++) { pin.run(`v${i}`, `other-${i}`); keep.run(`v${i}`, 10_000 + i); }
    };
    add(0, 40);
    pin.run("person", "mine"); keep.run("person", own);
    let pins = 0, kept = 0;
    db.function("visit_pin_candidate", () => { pins++; return 1; });
    db.function("visit_keep_candidate", () => { kept++; return 1; });
    Object.defineProperty(r.store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (source: string) => {
          let sql = source;
          for (const [table, key, visit, lookup] of [
            ["pins", "session", "visit_pin_candidate", "archive_pin_rows"],
            ["kept_chats", "thread", "visit_keep_candidate", "archive_keep_rows"],
          ]) {
            const check = `${visit}() IS NOT NULL`;
            sql = sql.replace(`SELECT DISTINCT ${key} FROM ${table}`, `SELECT DISTINCT ${key} FROM ${table} WHERE ${check}`)
              .replaceAll(`SELECT MAX(rowid) FROM ${table}`, `SELECT MAX(rowid) FROM ${table} WHERE ${check}`)
              .replaceAll(`SELECT MIN(rowid) FROM ${table}`, `SELECT MIN(rowid) FROM ${table} WHERE ${check}`)
              .replaceAll(`SELECT viewer FROM ${table} ORDER BY viewer LIMIT 1`, `SELECT viewer FROM ${table} WHERE ${check} ORDER BY viewer LIMIT 1`)
              .replaceAll(`SELECT viewer FROM ${table} WHERE viewer >`, `SELECT viewer FROM ${table} WHERE ${check} AND viewer >`)
              .replace(`SELECT 1 FROM ${table} WHERE viewer IN`, `SELECT 1 FROM ${table} WHERE ${check} AND viewer IN`)
              .replace(`SELECT 1 FROM ${lookup}`, `SELECT ${visit}() FROM ${lookup}`);
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    try {
      autoArchive(r.hub, Date.now() + 3 * 86_400_000);
      const before = { pins, kept };
      assert.ok(before.pins > 0 && before.kept > 0, "both mark checks were observed");
      assert.equal(r.store.getSession("mine")?.archivedAt, null);
      assert.equal(r.store.getThread(own)?.hiddenAt, null);
      add(40, 400); pins = 0; kept = 0;
      autoArchive(r.hub, Date.now() + 3 * 86_400_000);
      assert.deepEqual({ pins, kept }, before, "unrelated viewers do not add mark visits");
      assert.equal(r.store.getSession("mine")?.archivedAt, null);
      assert.equal(r.store.getThread(own)?.hiddenAt, null);
    } finally { Object.defineProperty(r.store, "db", { configurable: true, value: db }); }
  } finally { await r.close(); }
});

test("automatic archive waits for old marks, then keeps pinned sessions", async () => {
  const r = new Rig(), db = r.store.db, ready = Promise.withResolvers<void>();
  let timer: { ms: number; run: () => void } | null = null, signal: AbortSignal | undefined, calls = 0;
  const time = { after(ms: number, run: () => void) {
    const next = { ms, run }; timer = next;
    return () => { if (timer === next) timer = null; };
  } };
  const fire = (ms: number) => { const task = timer; assert.ok(task); assert.equal(task.ms, ms); timer = null; task.run(); };
  let stop = () => {};
  try {
    for (const key of ["pinned", "free"]) r.store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
      workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
    for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND (name LIKE 'archive_pin_%' OR name LIKE 'archive_keep_%')").all() as { name: string }[]) db.exec(`DROP TRIGGER ${row.name}`);
    db.exec("DROP TABLE archive_pin_rows; DROP TABLE archive_keep_rows; DROP TABLE archive_pin_replaced; DROP TABLE archive_keep_replaced; DROP TABLE archive_mark_meta");
    db.exec("INSERT INTO pins(viewer,session,at) VALUES('person','pinned',1)");
    installArchiveMarkIndex(db);
    assert.equal(archiveMarksReady(db), false);
    stop = startAutoArchiveTimer(r.hub, time, {
      prepareSaid: async () => {}, prepareSessionBindings: async () => {}, prepareSessionUpJobs: async () => {},
      prepareArchiveMarks: (s) => { calls++; signal = s; return ready.promise; },
    });
    fire(60_000);
    assert.equal(calls, 1);
    assert.equal(r.store.getSession("free")?.archivedAt, null);
    fire(600_000);
    assert.equal(calls, 1);
    while (!archiveMarksReady(db)) archiveMarksStep(db, 1);
    ready.resolve();
    await ready.promise;
    await Promise.resolve();
    fire(0);
    assert.equal(r.store.getSession("pinned")?.archivedAt, null);
    assert.notEqual(r.store.getSession("free")?.archivedAt, null);
    stop();
    assert.equal(signal?.aborted, true);
    assert.equal(timer, null);
  } finally { stop(); ready.resolve(); await r.close(); }
});

test("stopping the archive timer cancels pending mark preparation", async () => {
  const r = new Rig(), db = r.store.db, ready = Promise.withResolvers<void>();
  let timer: { ms: number; run: () => void } | null = null, signal: AbortSignal | undefined;
  const time = { after(ms: number, run: () => void) {
    const next = { ms, run }; timer = next;
    return () => { if (timer === next) timer = null; };
  } };
  let stop = () => {};
  try {
    r.store.insertSession({ key: "pinned", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w/pinned", token: "pinned", createdAt: 1, lastActiveAt: 1 });
    for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND (name LIKE 'archive_pin_%' OR name LIKE 'archive_keep_%')").all() as { name: string }[]) db.exec(`DROP TRIGGER ${row.name}`);
    db.exec("DROP TABLE archive_pin_rows; DROP TABLE archive_keep_rows; DROP TABLE archive_pin_replaced; DROP TABLE archive_keep_replaced; DROP TABLE archive_mark_meta");
    db.exec("INSERT INTO pins(viewer,session,at) VALUES('person','pinned',1)");
    installArchiveMarkIndex(db);
    stop = startAutoArchiveTimer(r.hub, time, {
      prepareSaid: async () => {}, prepareSessionBindings: async () => {}, prepareSessionUpJobs: async () => {},
      prepareArchiveMarks: (s) => { signal = s; return ready.promise; },
    });
    const task = timer as { ms: number; run: () => void } | null;
    assert.ok(task); assert.equal(task.ms, 60_000); timer = null; task.run();
    stop();
    assert.equal(signal?.aborted, true);
    ready.resolve();
    await ready.promise;
    await Promise.resolve();
    assert.equal(timer, null);
    assert.equal(r.store.getSession("pinned")?.archivedAt, null);
  } finally { stop(); ready.resolve(); await r.close(); }
});

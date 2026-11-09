import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PhoneGrants } from "../src/adb/grants.ts";
import { installLegacyEdits } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

for (const legacy of [false, true]) for (const editedCard of [false, true]) {
  test(`an authorization result keeps an edit committed just before its write (legacy ${legacy}, card ${editedCard})`, () => {
    const dir = mkdtempSync(join(tmpdir(), "restate-concurrent-")), path = join(dir, "station.db");
    const store = Store.open(path), raw = store.db;
    const writer = new DatabaseSync(path, { timeout: 5000 });
    try {
      const thread = store.openThread("ember", "CHAT", "concurrent", null, null).id;
      raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
        VALUES(?,1,'message','card','agent','a','old text',1,?)`)
        .run(thread, JSON.stringify({ type: "text", adb: { reason: "original" } }));
      if (legacy) {
        raw.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits");
        installLegacyEdits(raw);
        addClientColumn(raw);
      }
      const attachments = [{ name: "new.txt", path: "/new.txt", size: 3 }];
      const quotes = [{ author: "person", text: "new quote", comment: "" }];
      let wrote = false, transforms = 0;
      const observed = new Proxy(raw, { get(target, property) {
        if (property === "exec") return (sql: string) => {
          target.exec(sql);
          // Commit a real edit after the read snapshot and before the station obtains its write transaction.
          if (sql === "RELEASE restate_card_read" && !wrote) {
            wrote = true;
            writer.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,attachments,quotes,at,card)
              VALUES(?,2,'edit',1,'agent','a','new text',?,?,2,?)`)
              .run(thread, JSON.stringify(attachments), JSON.stringify(quotes), editedCard
                ? JSON.stringify({ type: "text", adb: { reason: "updated" }, extra: "kept" }) : null);
          }
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      (store as any).db = observed;
      assert.equal(store.restateCard("a", thread, "card", (card) => {
        transforms++;
        return { ...card, adb: { ...card.adb, outcome: "granted" } };
      }), true);
      assert.equal(wrote, true, "the competing connection committed its edit");
      assert.equal(transforms, 1);
      const last = raw.prepare("SELECT text,attachments,quotes,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
      assert.equal(last.text, "new text");
      assert.deepEqual(JSON.parse(String(last.attachments)), attachments);
      assert.deepEqual(JSON.parse(String(last.quotes)), quotes);
      assert.deepEqual(JSON.parse(String(last.card)), editedCard
        ? { type: "text", adb: { reason: "updated", outcome: "granted" }, extra: "kept" }
        : { type: "text", adb: { reason: "original", outcome: "granted" } });
    } finally {
      (store as any).db = raw;
      writer.close();
      store.close();
      rmSync(dir, { recursive: true, force: true });
    }
  });
}

test("an authorization result still finishes while unrelated writes keep committing", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-busy-")), path = join(dir, "station.db");
  const store = Store.open(path), raw = store.db, writer = new DatabaseSync(path, { timeout: 5000 });
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    const other = store.openThread("ember", "CHAT", "other", null, null).id;
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`)
      .run(thread, JSON.stringify({ type: "text", adb: { reason: "original" } }));
    let writes = 0, transforms = 0;
    const observed = new Proxy(raw, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && writes < 10) {
          writer.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,?,'message','person','p','unrelated',?)")
            .run(other, ++writes, writes);
        }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    assert.equal(store.restateCard("a", thread, "card", (card) => {
      transforms++;
      return { ...card, adb: { ...card.adb, outcome: "granted" } };
    }), true);
    assert.ok(writes > 0 && writes < 10, `finished before unrelated writes stopped (${writes})`);
    assert.equal(transforms, 1);
    const last = raw.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(last.text, "question");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "original", outcome: "granted" });
  } finally {
    (store as any).db = raw;
    writer.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("an authorization result does not recreate a post removed before the write", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-removed-")), path = join(dir, "station.db");
  const store = Store.open(path), raw = store.db, writer = new DatabaseSync(path, { timeout: 5000 });
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`)
      .run(thread, JSON.stringify({ type: "text", adb: {} }));
    let removed = false, transforms = 0;
    const observed = new Proxy(raw, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && !removed) {
          removed = true;
          writer.prepare("DELETE FROM entries WHERE thread=? AND n=1").run(thread);
        }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    assert.equal(store.restateCard("a", thread, "card", () => { transforms++; return {}; }), false);
    assert.equal(removed, true);
    assert.equal(transforms, 0);
    assert.equal(raw.prepare("SELECT count(*) AS n FROM entries WHERE thread=?").get(thread)?.n, 0);
  } finally {
    (store as any).db = raw;
    writer.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("two connections restating the same card preserve both outcomes", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-two-")), path = join(dir, "station.db");
  const store = Store.open(path), raw = store.db, other = Store.open(path);
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`)
      .run(thread, JSON.stringify({ type: "text", adb: { reason: "original" } }));
    let second = false, firstTransforms = 0, secondTransforms = 0;
    const observed = new Proxy(raw, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && !second) {
          second = true;
          assert.equal(other.restateCard("a", thread, "card", (card) => { secondTransforms++; return { ...card, other: "kept" }; }), true);
        }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    assert.equal(store.restateCard("a", thread, "card", (card) => {
      firstTransforms++;
      return { ...card, adb: { ...card.adb, outcome: "granted" } };
    }), true);
    assert.equal(second, true);
    assert.deepEqual([firstTransforms, secondTransforms], [1, 1]);
    const last = raw.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.deepEqual(JSON.parse(String(last.card)), { type: "text", adb: { reason: "original", outcome: "granted" }, other: "kept" });
    assert.equal(raw.prepare("SELECT COUNT(*) AS n FROM restate_guard").get()?.n, 0);
  } finally {
    (store as any).db = raw;
    other.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("two connections can install the restatement guard at the same time", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-guard-install-")), path = join(dir, "station.db");
  const store = Store.open(path), raw = store.db, other = Store.open(path);
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    let second = false;
    const observed = new Proxy(raw, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        if (sql === "BEGIN IMMEDIATE" && !second) {
          second = true;
          assert.equal(other.restateCard("a", thread, "card", (card) => ({ ...card, other: true })), true);
        }
        target.exec(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    assert.equal(store.restateCard("a", thread, "card", (card) => ({ ...card, first: true })), true);
    assert.equal(second, true);
    const last = raw.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.deepEqual(JSON.parse(String(last.card)), { type: "text", adb: {}, other: true, first: true });
    assert.equal(raw.prepare("SELECT COUNT(*) AS n FROM restate_guard").get()?.n, 0);
  } finally {
    (store as any).db = raw;
    other.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a removed guard trigger is restored before an authorization result is written", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-guard-drop-")), path = join(dir, "station.db");
  const store = Store.open(path), raw = store.db, writer = new DatabaseSync(path, { timeout: 5000 });
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','old text',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    let dropped = false, transforms = 0;
    const observed = new Proxy(raw, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && !dropped) {
          dropped = true;
          writer.exec("DROP TRIGGER restate_guard_add");
          writer.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
            VALUES(?,2,'edit',1,'agent','a','new text',2)`).run(thread);
        }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    assert.equal(store.restateCard("a", thread, "card", (card) => { transforms++; return { ...card, done: true }; }), true);
    assert.equal(dropped, true);
    assert.equal(transforms, 1);
    assert.equal(raw.prepare("SELECT text FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)?.text, "new text");
    assert.ok(raw.prepare("SELECT 1 FROM sqlite_master WHERE type='trigger' AND name='restate_guard_add'").get());
    assert.equal(raw.prepare("SELECT COUNT(*) AS n FROM restate_guard").get()?.n, 0);
  } finally {
    (store as any).db = raw;
    writer.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a guard trigger removed between its check and registration cannot hide an edit", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-guard-install-race-")), path = join(dir, "station.db");
  const store = Store.open(path), raw = store.db, writer = new DatabaseSync(path, { timeout: 5000 });
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','old text',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    let dropped = false, edited = false;
    const observed = new Proxy(raw, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const stmt = target.prepare(sql);
        if (!sql.includes("INSERT INTO restate_guard(thread,token,dirty)")) return stmt;
        return new Proxy(stmt, { get(statement, member) {
          if (member === "run") return (...args: Parameters<typeof statement.run>) => {
            if (!dropped) { dropped = true; writer.exec("DROP TRIGGER restate_guard_add"); }
            return statement.run(...args);
          };
          const value = Reflect.get(statement, member, statement);
          return typeof value === "function" ? value.bind(statement) : value;
        } });
      };
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && dropped && !edited) {
          edited = true;
          writer.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
            VALUES(?,2,'edit',1,'agent','a','new text',2)`).run(thread);
        }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    assert.equal(store.restateCard("a", thread, "card", (card) => ({ ...card, done: true })), true);
    assert.equal(dropped, true);
    assert.equal(edited, true);
    assert.equal(raw.prepare("SELECT text FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)?.text, "new text");
    assert.ok(raw.prepare("SELECT 1 FROM sqlite_master WHERE type='trigger' AND name='restate_guard_add'").get());
  } finally {
    (store as any).db = raw;
    writer.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a replaced guard trigger cannot hide an edit", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-guard-replaced-")), path = join(dir, "station.db");
  const store = Store.open(path), raw = store.db, writer = new DatabaseSync(path, { timeout: 5000 });
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','old text',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    let reads = 0;
    const observed = new Proxy(raw, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && ++reads <= 2) {
          if (reads === 1) writer.exec(`DROP TRIGGER restate_guard_add;
            CREATE TRIGGER restate_guard_add BEFORE INSERT ON entries BEGIN SELECT 1; END`);
          writer.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
            VALUES(?,?,'edit',1,'agent','a',?,?)`).run(thread, reads + 1, `new text ${reads}`, reads + 1);
        }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    assert.equal(store.restateCard("a", thread, "card", (card) => ({ ...card, done: true })), true);
    assert.equal(reads, 2);
    assert.equal(raw.prepare("SELECT text FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)?.text, "new text 2");
  } finally {
    (store as any).db = raw;
    writer.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("an authorization result finishes if the same conversation keeps changing", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-thread-busy-")), path = join(dir, "station.db");
  const store = Store.open(path), raw = store.db, writer = new DatabaseSync(path, { timeout: 5000 });
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','old',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    let writes = 0, transforms = 0;
    const observed = new Proxy(raw, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && writes < 10) {
          const n = ++writes + 1;
          writer.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
            VALUES(?,?,'edit',1,'agent','a',?,?)`).run(thread, n, `edit-${writes}`, n);
        }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    assert.equal(store.restateCard("a", thread, "card", (card) => { transforms++; return { ...card, done: true }; }), true);
    assert.ok(writes > 1 && writes < 10, `finished while the other writer was still active (${writes})`);
    assert.equal(transforms, 1);
    assert.equal(raw.prepare("SELECT text FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)?.text, `edit-${writes}`);
    assert.equal(raw.prepare("SELECT COUNT(*) AS n FROM restate_guard").get()?.n, 0);
  } finally {
    (store as any).db = raw;
    writer.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

for (const recursive of [false, true]) for (const operation of ["insert", "update"]) {
  test(`a rowid ${operation} replacement in another conversation invalidates a pending restatement (recursive ${recursive})`, () => {
    const dir = mkdtempSync(join(tmpdir(), "restate-replace-")), path = join(dir, "station.db");
    const store = Store.open(path), raw = store.db, writer = new DatabaseSync(path, { timeout: 5000 });
    try {
      writer.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
      const thread = store.openThread("ember", "CHAT", "card", null, null).id;
      const other = store.openThread("ember", "CHAT", "other", null, null).id;
      raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
        VALUES(?,1,'message','card','agent','a','old',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
      if (operation === "update") raw.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
        VALUES(?,1,'message','person','p','replacement',1)`).run(other);
      const rowid = raw.prepare("SELECT rowid FROM entries WHERE thread=? AND n=1").get(thread)!.rowid as number;
      let replaced = false, transforms = 0;
      const observed = new Proxy(raw, { get(target, property) {
        if (property === "exec") return (sql: string) => {
          target.exec(sql);
          if (sql === "RELEASE restate_card_read" && !replaced) {
            replaced = true;
            if (operation === "insert") writer.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,text,at)
              VALUES(?,?,1,'message','person','p','replacement',1)`).run(rowid, other);
            else writer.prepare("UPDATE OR REPLACE entries SET rowid=? WHERE thread=? AND n=1").run(rowid, other);
          }
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      (store as any).db = observed;
      assert.equal(store.restateCard("a", thread, "card", () => { transforms++; return {}; }), false);
      assert.equal(replaced, true);
      assert.equal(transforms, 0);
      assert.equal(raw.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread=?").get(thread)?.n, 0);
      assert.equal(raw.prepare("SELECT COUNT(*) AS n FROM restate_guard").get()?.n, 0);
    } finally {
      (store as any).db = raw;
      writer.close();
      store.close();
      rmSync(dir, { recursive: true, force: true });
    }
  });
}

test("a failed card transformation releases its guard and records no edit", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-guard-failure-")), path = join(dir, "station.db");
  const store = Store.open(path);
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','old',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    assert.throws(() => store.restateCard("a", thread, "card", () => { throw new Error("cannot transform"); }), /cannot transform/);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread=?").get(thread)?.n, 1);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM restate_guard").get()?.n, 0);
    assert.equal(store.restateCard("a", thread, "card", (card) => ({ ...card, done: true })), true);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a phone authorization keeps a concurrently edited card and closes it", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-phone-")), path = join(dir, "station.db");
  const store = Store.open(path), raw = store.db, writer = new DatabaseSync(path, { timeout: 5000 });
  try {
    const thread = store.openThread("ember", "CHAT", "phone", null, null).id;
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','agent','old question',1,?)`)
      .run(thread, JSON.stringify({ type: "options", adb: { request: "p1", reason: "original" } }));
    let edited = false;
    const observed = new Proxy(raw, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && !edited) {
          edited = true;
          writer.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
            VALUES(?,2,'edit',1,'agent','agent','new question',2,?)`)
            .run(thread, JSON.stringify({ type: "options", adb: { request: "p1", reason: "updated" } }));
        }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    const hub = { store: { getSession: () => ({ ws: "work", archivedAt: null }),
      withdrawCard: store.withdrawCard.bind(store), restateCard: store.restateCard.bind(store), subscribe: () => {} }, notify: () => {} } as any;
    const grants = new PhoneGrants({ db: raw, hub, home: () => "work", title: () => null, now: () => 1_800_000_000_000 });
    const request = { id: "p1", session: "agent", chat: "chat", owner: "person@example.com", reason: "debug",
      at: 1_800_000_000, status: "pending", thread, cardTs: "card" };
    raw.prepare("INSERT INTO adb_requests(id,session,owner,status,body) VALUES(?,?,?,?,?)")
      .run(request.id, request.session, request.owner, request.status, JSON.stringify(request));
    assert.equal(grants.decide(request.owner, request.id, "hour", "work"), null);
    assert.equal(edited, true);
    assert.equal(grants.get(request.id)?.status, "granted");
    const last = raw.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(last.text, "new question");
    assert.deepEqual(JSON.parse(String(last.card)).adb,
      { request: "p1", reason: "updated", outcome: { status: "granted", scope: "hour" } });
    assert.equal(raw.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=1").get(thread)?.n, 1);
  } finally {
    (store as any).db = raw;
    writer.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

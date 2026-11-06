import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { PeopleSinceBuilder } from "../src/read/card-posts-builder.ts";
import { Readers } from "../src/read/pool.ts";
import { answersSince, makeStore } from "../src/read/store.ts";
import { PEOPLE_TIME_PENDING, peopleSinceReady, peopleSinceStep } from "../src/store/legacy-people-since.ts";
import { Store } from "../src/store/store.ts";
import { referenceAnswersSince } from "./card-answer-reference.ts";

function oldStore(dir: string, short = false) {
  const path = join(dir,"stillfail.db"), initial = Store.open(path);
  const threads = ["first","second"].map((key) => initial.openThread("ember","CHAT",key,null,null).id);
  const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,card) VALUES(?,?,'message',?,?,?, ?,?)");
  const card = JSON.stringify({ type: "text" });
  for (const [i,thread] of threads.entries()) {
    put.run(thread,1,"agent","a","choose",1,card);
    put.run(thread,2,"person","p","answer",100,null);
    if (!short || i !== 0) for (let n=3;n<=200;n++) put.run(thread,n,"agent","a","ordinary",1,!short && n<=66 ? card : null);
  }
  initial.db.exec("DROP INDEX entries_people_since");
  initial.close();
  return { path, threads };
}

test("old writes and read snapshots agree as requested people-time lookups are prepared", async () => {
  const dir = mkdtempSync(join(tmpdir(),"old-people-time-store-")), { path,threads } = oldStore(dir);
  const old = new DatabaseSync(path);
  const write = old.prepare("UPDATE entries SET at=? WHERE thread=? AND n=2");
  const store = Store.open(path), builder = new PeopleSinceBuilder(path);
  let snapshot: DatabaseSync | null = null;
  try {
    const read = makeStore(store.db,dir), before = referenceAnswersSince(store,50);
    assert.throws(() => answersSince(read,50,threads), (error: Error) => {
      assert.match(error.message,/^people time pending:/);
      assert.deepEqual(JSON.parse(error.message.slice(PEOPLE_TIME_PENDING.length)),threads);
      return true;
    });
    assert.deepEqual(peopleSinceStep(store.db,threads[0]!,2), { done:false, visited:2 });
    write.run(0,threads[0]!);
    await builder.ready(threads);
    assert.ok(threads.every((thread) => peopleSinceReady(store.db,thread)));
    assert.deepEqual(answersSince(read,50,threads),referenceAnswersSince(store,50));
    assert.notDeepEqual(answersSince(read,50,threads),before);
    snapshot = new DatabaseSync(path,{ readOnly:true });
    snapshot.exec("BEGIN");
    const snap = makeStore(snapshot,dir), saved = answersSince(snap,50,threads);
    write.run(0,threads[1]!);
    assert.deepEqual(answersSince(snap,50,threads),saved);
    snapshot.exec("COMMIT");
    assert.deepEqual(answersSince(snap,50,threads),referenceAnswersSince(store,50));
  } finally { snapshot?.close(); await builder.close(); store.close(); old.close(); rmSync(dir,{ recursive:true, force:true }); }
});

test("a short old chat answers without preparing its people-time lookup", () => {
  const dir = mkdtempSync(join(tmpdir(),"old-people-time-short-")), { path,threads } = oldStore(dir,true);
  const store = Store.open(path);
  try {
    const expected = referenceAnswersSince(store,50).filter((a) => a.question.thread === threads[0]);
    assert.equal(expected.length,1);
    assert.deepEqual(answersSince(makeStore(store.db,dir),50,[threads[0]!]),expected);
    assert.equal(store.db.prepare("SELECT 1 FROM legacy_people_time_scopes WHERE thread=?").get(threads[0]!),undefined);
  } finally { store.close(); rmSync(dir,{ recursive:true, force:true }); }
});

test("a long old chat with a short card history answers without preparing its people-time lookup", () => {
  const dir = mkdtempSync(join(tmpdir(),"old-people-time-few-cards-")), { path,threads } = oldStore(dir,true);
  const store = Store.open(path);
  try {
    const thread = threads[0]!;
    const put = store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,?,'message','agent','a','ordinary',1)");
    for (let n=3;n<=200;n++) put.run(thread,n);
    const expected = referenceAnswersSince(store,50).filter((answer) => answer.question.thread === thread);
    assert.equal(expected.length,1);
    assert.deepEqual(answersSince(makeStore(store.db,dir),50,[thread]),expected);
    assert.equal(store.db.prepare("SELECT 1 FROM legacy_people_time_scopes WHERE thread=?").get(thread),undefined);
  } finally { store.close(); rmSync(dir,{ recursive:true, force:true }); }
});

test("a long chat's short-card read seeks the person after each card, regardless of ordinary history", () => {
  const calls: number[] = [];
  const sql = "SELECT n, at FROM entries WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND n > ? ORDER BY n LIMIT 1";
  for (const size of [200,2000]) {
    const dir = mkdtempSync(join(tmpdir(),"old-people-time-card-seek-")), { path,threads } = oldStore(dir,true);
    const store = Store.open(path);
    try {
      const thread = threads[0]!, put = store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,?,'message','agent','a','ordinary',1)");
      for (let n=3;n<=size;n++) put.run(thread,n);
      const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(thread,1).map((row) => row.detail).join(" ");
      assert.match(plan,/SEARCH entries USING INDEX entries_people_by_n \(thread=\? AND n>\?\)/);
      let seeks = 0;
      const traced = new Proxy(store.db,{ get(target,key) {
        if (key !== "prepare") {
          const value = Reflect.get(target,key,target);
          return typeof value === "function" ? value.bind(target) : value;
        }
        return (query: string) => {
          const statement = target.prepare(query);
          if (query !== sql) return statement;
          return new Proxy(statement,{ get(value,method) {
            if (method === "get") return (...args: any[]) => { seeks++; return value.get(...args); };
            const member = Reflect.get(value,method,value);
            return typeof member === "function" ? member.bind(value) : member;
          } });
        };
      } });
      assert.equal(answersSince(makeStore(traced,dir),50,[thread]).length,1);
      calls.push(seeks);
    } finally { store.close(); rmSync(dir,{ recursive:true, force:true }); }
  }
  assert.deepEqual(calls,[1,1]);
});

test("a short chat uses SQLite time comparisons and skips out-of-window 64-bit keys", () => {
  const dir = mkdtempSync(join(tmpdir(),"old-people-time-values-")), { path,threads } = oldStore(dir,true);
  const store = Store.open(path);
  try {
    const thread = threads[0]!;
    store.db.prepare("UPDATE entries SET at='later' WHERE thread=? AND n=2").run(thread);
    store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,9223372036854775806,'message','person','p','old',0)").run(thread);
    const expected = referenceAnswersSince(store,50).filter((answer) => answer.question.thread === thread);
    assert.equal(expected.length,1);
    assert.deepEqual(answersSince(makeStore(store.db,dir),50,[thread]),expected);
    assert.equal(store.db.prepare("SELECT 1 FROM legacy_people_time_scopes WHERE thread=?").get(thread),undefined);
  } finally { store.close(); rmSync(dir,{ recursive:true, force:true }); }
});

test("64 cards can be checked immediately but 65 cards ask for preparation", () => {
  const dir = mkdtempSync(join(tmpdir(),"old-people-time-limit-")), { path,threads } = oldStore(dir,true);
  const store = Store.open(path);
  try {
    const thread = threads[0]!;
    const put = store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,card) VALUES(?,?,'message','agent','a','ordinary',1,?)");
    const card = JSON.stringify({ type:"text" });
    for (let n=3;n<=65;n++) put.run(thread,n,card);
    const expected = referenceAnswersSince(store,50).filter((answer) => answer.question.thread === thread);
    assert.deepEqual(answersSince(makeStore(store.db,dir),50,[thread]),expected);
    put.run(thread,66,card);
    assert.throws(() => answersSince(makeStore(store.db,dir),50,[thread]), (error: Error) => {
      assert.match(error.message,/^people time pending:/);
      assert.deepEqual(JSON.parse(error.message.slice(PEOPLE_TIME_PENDING.length)),[thread]);
      return true;
    });
    assert.equal(store.db.prepare("SELECT count(*) AS n FROM legacy_people_time_scopes").get()?.n,0);
  } finally { store.close(); rmSync(dir,{ recursive:true, force:true }); }
});

test("handover and cancellation keep another request through a stopped worker", async () => {
  const dir = mkdtempSync(join(tmpdir(),"old-people-time-worker-")), { path,threads } = oldStore(dir);
  const store = Store.open(path), previous = Promise.withResolvers<void>(), abort = new AbortController();
  const worker = join(dir,"worker.mjs"), marker = join(dir,"stopped");
  const real = new URL("../src/read/card-posts-worker.ts",import.meta.url).href;
  writeFileSync(worker,`import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  const builder = new PeopleSinceBuilder(path,{ previousGone:previous.promise },pathToFileURL(worker));
  try {
    const dropped = builder.ready([threads[0]!],abort.signal), kept = builder.ready([threads[0]!]);
    abort.abort();
    await assert.rejects(dropped,/read cancelled/);
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(peopleSinceReady(store.db,threads[0]!),false);
    previous.resolve();
    await kept;
    assert.equal(peopleSinceReady(store.db,threads[0]!),true);
    assert.equal(peopleSinceReady(store.db,threads[1]!),false);
  } finally { abort.abort(); previous.resolve(); await builder.close(); store.close(); rmSync(dir,{ recursive:true, force:true }); }
});

test("a native index removed during a direct read is prepared again", async () => {
  const dir = mkdtempSync(join(tmpdir(),"old-people-time-race-"));
  const path = join(dir,"stillfail.db"), store = Store.open(path), other = new DatabaseSync(path);
  const builder = new PeopleSinceBuilder(path);
  try {
    const thread = store.openThread("ember","CHAT","index-race",null,null).id;
    const put = store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,card) VALUES(?,?,'message',?,?,?, ?,?)");
    put.run(thread,1,"agent","a","choose",1,JSON.stringify({ type:"text" }));
    put.run(thread,2,"person","p","answer",100,null);
    for (let n=3;n<=100;n++) put.run(thread,n,"agent","a","ordinary",1,null);
    let dropped = false;
    const traced = new Proxy(store.db,{ get(target,key) {
      if (key !== "prepare") {
        const value = Reflect.get(target,key,target);
        return typeof value === "function" ? value.bind(target) : value;
      }
      return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== "SELECT 1 FROM sqlite_master WHERE type=? AND name=?") return statement;
        return new Proxy(statement,{ get(query,method) {
          if (method === "get") return (...args: any[]) => {
            const found = query.get(...args);
            if (!dropped && args[1] === "entries_people_since" && found) {
              dropped = true;
              other.exec("DROP INDEX entries_people_since");
            }
            return found;
          };
          const value = Reflect.get(query,method,query);
          return typeof value === "function" ? value.bind(query) : value;
        } });
      };
    } });
    assert.throws(() => answersSince(makeStore(traced,dir),50,[thread]),/^Error: people time pending:/);
    assert.equal(dropped,true);
    await builder.ready([thread]);
    assert.deepEqual(answersSince(makeStore(store.db,dir),50,[thread]),referenceAnswersSince(store,50));
  } finally { await builder.close(); other.close(); store.close(); rmSync(dir,{ recursive:true, force:true }); }
});

test("readers retry the requested old chats after their people-time lookups are prepared", async () => {
  const dir = mkdtempSync(join(tmpdir(),"old-people-time-reader-")), { path,threads } = oldStore(dir);
  const store = Store.open(path), readers = new Readers(dir,1);
  try {
    const sessions = threads.map((thread,i) => {
      const key = `s${i}`;
      store.insertSession({ key,connect:"ember",runtime:"claude",profile:"cc",workspace:`/w/${key}`,
        token:key,createdAt:1,lastActiveAt:1 });
      store.joinThread(thread,key,"ember");
      return key;
    });
    const batches: number[][] = [], prepare = readers.preparePeopleSince.bind(readers);
    readers.preparePeopleSince = (items,signal) => { batches.push([...items]); return prepare(items,signal); };
    const viewer = { sub:"me",email:"me",name:"Me",role:"owner",workspace:"w",device:"d" };
    await readers.read("chatMarks", { viewer,scope:{ sessions,threads } }, "en");
    assert.equal(batches.length,1);
    assert.deepEqual(new Set(batches[0]),new Set(threads));
    assert.ok(threads.every((thread) => peopleSinceReady(store.db,thread)));
  } finally { readers.close(); store.close(); rmSync(dir,{ recursive:true, force:true }); }
});

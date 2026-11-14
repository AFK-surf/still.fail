// One look of the auto-archive (`archiveLook`) by the MoonBit reader (station/mb src/readops/archive.mbt; read/pool.ts
// MOVED) as the worker reads it, on the same database: sessions quiet by their activity or by when they were shown,
// running, archived, bound, pinned, with chats kept and not, messages and letters undelivered, a last turn that waits
// and one that ended, a job up; chats of their own idle, kept, hidden, empty, a tail of edits; waits of none, of
// either kind, and how far the next look is.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads a look of the auto-archive as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-archive-look-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const db = store.db;
  const session = (key: string, at: number, extra: Record<string, unknown> = {}) =>
    store.insertSession({ key, connect: key.startsWith("slack") ? "team" : "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: at, ...extra } as Parameters<Store["insertSession"]>[0]);
  session("old", 1000);
  session("shown", 1000);
  db.prepare("UPDATE sessions SET shown_at = 9500 WHERE key = 'shown'").run();
  session("fresh", 9900);
  session("running", 1000);
  store.setRunning("running", true);
  session("archived", 1000);
  db.prepare("UPDATE sessions SET archived_at = 2000 WHERE key = 'archived'").run();
  session("bound", 2000);
  store.setBinding("team", "bound");
  session("pinned", 3000);
  store.setPin("me@x", "pinned", true);
  session("slack-one", 7000, { fast: true, model: "m" });
  session("waiting", 1500);
  db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,need,about_thread,about_n,about_ts,wait_seconds,wait_for,wait_watch) VALUES ('w1','waiting','input',1400,1450,'completed','need_decision','a call',1,2,'3',60,'ci',1)").run();
  db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared) VALUES ('o1','old','input',900,950,'completed','final')").run();
  db.prepare("INSERT INTO jobs(id,session_key,name,command,cwd,port,token,state,started_at,restarts,log,watch) VALUES ('up','old','svc','true','/',9000,'tok','running',1,0,'/dev/null',0)").run();
  const chat = (key: string, title: string, at: number) => {
    const id = store.openThread("ember", "CHAT", key, title, null).id;
    db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(at, id);
    return id;
  };
  let ts = 0;
  const say = (t: number, at: number, extra: Record<string, unknown> = {}) => {
    const n = String(++ts);
    store.insertMessage({ ...newMessage(t, n, "person", "p@x", `m${ts}`), at, ...extra } as ReturnType<typeof newMessage>);
    return n;
  };
  const joined = chat("joined", "Joined", 500);
  store.joinThread(joined, "old", "ember");
  store.joinThread(joined, "bound", "ember");
  const keptJoined = chat("kept-joined", "Kept joined", 500);
  store.joinThread(keptJoined, "old", "ember");
  store.keepChat("me@x", keptJoined);
  say(joined, 800);
  db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES (?,1,'bound',NULL)").run(joined);
  const idleOwn = chat("idle", "Idle", 100);
  say(idleOwn, 1200);
  const recentOwn = chat("recent", "Recent", 100);
  say(recentOwn, 9800);
  const keptOwn = chat("kept", "Kept", 100);
  store.keepChat("me@x", keptOwn);
  chat("empty", "Empty", 300);
  const hidden = chat("hidden", "Hidden", 100);
  db.prepare("UPDATE threads SET hidden_at = 5 WHERE id = ?").run(hidden);
  const edited = chat("edited", "Edited", 100);
  const first = say(edited, 1100);
  for (let i = 0; i < 70; i++) store.editMessage("ember", "CHAT", "edited", first, `edit ${i}`);
  // A chat in many threads (a release posted to Slack in a new one each time): its recent ones, its own chat first, the
  // one it heard from last whether or not that order is prepared, the newest it joined.
  session("releases", 1000);
  const releasesHome = chat("releases-home", "Releases", 100);
  db.prepare("UPDATE threads SET home = 'releases' WHERE id = ?").run(releasesHome);
  store.joinThread(releasesHome, "releases", "ember");
  const releases: number[] = [];
  for (let i = 0; i < 40; i++) {
    const t = store.openThread("slack:T1", "C2", `5000.${i}`, null, "releases").id;
    store.joinThread(t, "releases", "team");
    releases.push(t);
  }
  db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES (?,1,'releases',1)").run(releases[2]);
  for (const [i, t] of releases.entries()) if (i % 9 === 0) store.keepChat("me@x", t);
  session("releases-prepared", 1000);
  for (let i = 0; i < 40; i++) store.joinThread(releases[i]!, "releases-prepared", "ember");
  db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES (?,1,'releases-prepared',1)").run(releases[5]);
  while (!prepareLatestThreadStep(db, "releases-prepared").done) { /* bounded batches */ }
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (readers: Readers) => {
    const out: unknown[] = [];
    for (const [now, after, slackAfter] of [[10_000, 5000, 2000], [10_000, 0, 0], [10_000, 9000, -1], [10_000, 100_000, 3000], [2000, 1000, 500], ["10000", "5000", "2000"]])
      out.push(await read(readers, "archiveLook", { now, after, slackAfter }));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["\"key\":\"old\"", "\"quietLong\":true", "\"pinned\":true", "\"bound\":true", "\"pending\":true", "\"upJob\":true", "\"ending\":\"need_help\"", "\"declared\":\"block\"", "\"title\":\"Idle\"", "\"next\":", "\"marksReady\":true"])
      assert.ok(said.includes(sign), sign);
    assert.ok(!said.includes("\"title\":\"Kept\""));
    const look = first[0] as { sessions: { row: { key: string }; facts: { threads: { thread: { id: number } }[] } }[] };
    for (const key of ["releases", "releases-prepared"]) {
      const threads = look.sessions.find((s) => s.row.key === key)!.facts.threads.map((t) => t.thread.id);
      assert.equal(threads.length, 20, key);
      assert.ok(threads.includes(releases.at(-1)!), key);
    }
    const prepared = look.sessions.find((s) => s.row.key === "releases-prepared")!.facts.threads.map((t) => t.thread.id);
    assert.equal(prepared[0], releases[5], "the one it heard from last first, where it has no chat of its own");
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

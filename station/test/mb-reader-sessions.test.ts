// A session's summary and the session list (`summary`, `sessions`: GET /sessions) by the MoonBit reader (station/mb
// src/readops/summaries.mbt; read/pool.ts MOVED) as the worker reads them, on the same database: sessions of either
// runtime, pinned to a profile or given several, quick or not, capped, archived, of a connect, of a workspace or of
// none, started by a person, the local page or a Slack user; with turns, messages not delivered, bindings, people
// in its chats and Slack threads, watches, transcripts read and calls used (one usage that does not read); a session
// that is not there; every list by connect, archive and viewer, in either language.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads sessions' summaries and the session list as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-sessions-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ connects: [{ id: "team", slack: { botName: "Helper", team: { id: "T1", name: "Team" } } }] }));
  writeFileSync(join(data, "slack-names.json"), JSON.stringify({ "u:T1:U1": { person: { name: "Una", email: "una@x" } } }));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const db = store.db;
  const session = (key: string, extra: Record<string, unknown> = {}) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 100, ...extra } as Parameters<Store["insertSession"]>[0]);
  session("a1", { ws: "w", createdBy: "p@x", model: "opus", lastActiveAt: 500 });
  session("a2", { ws: "w", runtime: "codex", createdBy: "local", lastActiveAt: 500 });
  session("a3", { ws: null, runtime: "dsh", createdBy: "slack:team:U1", lastActiveAt: 400 });
  session("s1", { connect: "team", ws: "w", lastActiveAt: 300 });
  session("old", { ws: "w", lastActiveAt: 200 });
  db.prepare("UPDATE sessions SET archived_at = 900, archived_by = 'manual' WHERE key = 'old'").run();
  db.prepare("UPDATE sessions SET profile_pinned = 1, fast = 1, afresh = 0, context = 200000, context_before = 0, cwd = '/w/sub', title = 'One' WHERE key = 'a1'").run();
  db.prepare("UPDATE sessions SET profiles = '[\"cc\",\"\",3,\"cx\"]', running = 1 WHERE key = 'a2'").run();
  db.prepare("UPDATE sessions SET profiles = 'not json' WHERE key = 'a3'").run();
  const chat = store.openThread("ember", "CHAT", "c", "Chat", null).id;
  store.joinThread(chat, "a1", "ember");
  store.joinThread(chat, "a2", "ember");
  let ts = 0;
  const say = (t: number, kind: "person" | "agent", author: string, text: string, at: number) => {
    store.insertMessage({ ...newMessage(t, String(++ts), kind, author, text), at } as ReturnType<typeof newMessage>);
  };
  say(chat, "person", "z@x", "first", 50);
  say(chat, "person", "b@x", "second", 70);
  // A second chat of a1's: someone who wrote here first, and someone at the same time as another.
  const chat2 = store.openThread("ember", "CHAT", "c2", "Chat two", null).id;
  store.joinThread(chat2, "a1", "ember");
  say(chat2, "person", "b@x", "earlier", 10);
  say(chat2, "person", "m@x", "same time", 50);
  say(chat, "agent", "a1", "reply", 60);
  const slack = store.openThread("slack:T1", "C1", "1.1", null, null).id;
  store.joinThread(slack, "s1", "team");
  store.joinThread(slack, "a1", "team");
  say(slack, "person", "U1", "from slack", 30);
  db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES (?,1,'a2',NULL)").run(chat);
  db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,need,wait_seconds,wait_for,wait_watch) VALUES ('t1','a1','input',10,20,'completed','need_help','a key',30,'ci',0)").run();
  db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared) VALUES ('t2','a1','input',30,NULL,NULL,NULL)").run();
  store.setBinding("team", "s1");
  store.setBinding("other", "s1");
  db.prepare("INSERT INTO jobs(id,session_key,name,command,cwd,port,token,state,started_at,restarts,log,watch) VALUES ('w1','a2','ci','true','/',NULL,'t','running',100,0,'/dev/null',1)").run();
  store.setTranscriptLength("a1", 42);
  db.prepare("INSERT INTO session_usage(session, usage) VALUES ('a1', ?)").run(JSON.stringify({ input: 5, output: 7, models: { opus: 1 } }));
  const readers = (mb: string | null) => {
    const r = new Readers(data, 1);
    r.mbReader = mb;
    r.names.set("p@x", "Pat");
    r.processes = () => new Map([["a1", "running"]]);
    return r;
  };
  const worker = readers(null);
  const program = readers(binary);
  const read = (r: Readers, op: string, args: unknown, lang: "zh" | "en") => r.read(op, args, lang).then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (r: Readers) => {
    const out: unknown[] = [];
    for (const lang of ["zh", "en"] as const) {
      for (const key of ["a1", "a2", "a3", "s1", "old", "nobody"]) out.push(await read(r, "summary", { key }, lang));
      for (const connect of [null, "team", "ember"])
        for (const archived of [false, true, 0, 1])
          for (const viewer of [null, { workspace: "w", home: true }, { workspace: "x", home: false }, { workspace: "x" }])
            out.push(await read(r, "sessions", { connect, archived, viewer, lang }, lang));
    }
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["\"process\":\"running\"", "\"boundTo\":[\"team\",\"other\"]", "\"transcriptLength\":42", "\"usage\":{", "\"watch\":", "\"name\":\"Pat\"", "\"name\":\"Una\"",
      "\"profiles\":[\"cc\",\"cx\"]", "\"profiles\":[\"cc\"]", "\"contextActions\":[\"clear\"]", "\"status\":404", "\"fast\":true", "\"afresh\":false", "\"context\":200000", "\"cwd\":\"/w/sub\"",
      "\"pending\":1", "\"turns\":2", "\"archivedBy\":\"manual\""])
      assert.ok(said.includes(sign), sign);
    // A usage that does not read: none of them.
    db.prepare("INSERT INTO session_usage(session, usage) VALUES ('a2', 'nope')").run();
    assert.deepEqual(await all(program), await all(worker));
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

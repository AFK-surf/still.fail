// A session's page and the threads as a viewer reads them (`session`, `threads`, `thread`: GET /sessions/:key,
// /threads, /threads/:id) by the MoonBit reader (station/mb src/readops/threadviews.mbt; read/pool.ts MOVED) as the
// worker reads them, on the same database: a chat of two agents read in part by the viewer, with letters in both logs,
// shared with a workspace, copying to the Slack thread its agent is in (their copy destinations prepared as the read
// asks), a Slack thread with a Slack self of the viewer's; threads of another workspace; a session with turns and more
// jobs than a page, some still up; ids and counts read and refused; viewers of either workspace, in either language.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { wall } from "../src/ops/fibers.ts";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads a session's page and the threads as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-threads-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ connects: [{ id: "team", slack: { botName: "Helper", team: { id: "T1", name: "Team" } } }] }));
  writeFileSync(join(data, "slack-names.json"), JSON.stringify({ "u:T1:U1": { person: { name: "Una" } }, "c:T1:C1": { channel: "general" } }));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const db = store.db;
  const now = wall.now();
  const session = (key: string, extra: Record<string, unknown> = {}) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 100, ...extra } as Parameters<Store["insertSession"]>[0]);
  session("a1", { ws: "w", createdBy: "p@x" });
  session("a2", { ws: null });
  session("s1", { connect: "team", ws: "w" });
  session("far", { ws: "x" });
  let ts = 0;
  const say = (t: number, kind: "person" | "agent", author: string, text: string) => {
    store.insertMessage({ ...newMessage(t, String(++ts), kind, author, text), at: 1000 + ts } as ReturnType<typeof newMessage>);
  };
  const chat = store.openThread("ember", "CHAT", "c", "Chat", "p@x").id;
  db.prepare("UPDATE threads SET home = 'a1', auto_title = 'Auto' WHERE id = ?").run(chat);
  store.joinThread(chat, "a1", "ember");
  store.joinThread(chat, "a2", "ember");
  for (let i = 0; i < 5; i++) say(chat, i % 2 === 0 ? "person" : "agent", i % 2 === 0 ? (i === 4 ? "q@x" : "p@x") : "a1", `m${i}`);
  db.prepare("INSERT INTO reads (viewer, thread, n, at) VALUES ('p@x', ?, 2, 1)").run(chat);
  db.prepare("INSERT INTO letters (thread, n, ts, author_kind, author, text, attachments, at, letter) VALUES (?, 1, 'l1', 'agent', 'a1', 'in', NULL, 5, ?)").run(chat, JSON.stringify({ way: "in", title: "From far" }));
  db.prepare("INSERT INTO chat_shares(session,shared,write,by,at) VALUES ('a1',?,1,'p@x',?)").run(JSON.stringify([{ workspace: "w2", name: 7, used: now }, { workspace: "w3", used: now }, { workspace: "w4", used: 1 }]), now);
  const slack = store.openThread("slack:T1", "C1", "1.1", null, null).id;
  store.joinThread(slack, "s1", "team");
  store.joinThread(slack, "a1", "team");
  say(slack, "person", "U1", "from slack");
  say(slack, "person", "U2", "another");
  db.prepare("INSERT INTO identities (viewer, slack_user, at) VALUES ('p@x', 'U1', 1)").run();
  const far = store.openThread("ember", "CHAT", "f", "Far", null).id;
  store.joinThread(far, "far", "ember");
  say(far, "person", "z@x", "elsewhere");
  db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared) VALUES ('t1','a1','input',10,20,'completed','all_done')").run();
  db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,about_thread,about_n,about_ts) VALUES ('t2','a1','input',30,40,'completed','need_help',1,2,'2')").run();
  for (let i = 0; i < 55; i++)
    db.prepare("INSERT INTO jobs(id,session_key,name,command,cwd,port,token,state,started_at,restarts,log,watch) VALUES (?,'a1',?,'true','/',?,?,?,?,0,'/dev/null',0)")
      .run(`j${i}`, `job ${i}`, i === 2 ? 9000 : null, `t${i}`, i < 3 ? "running" : "exited", i === 5 ? 50 : 100 + i);
  const readers = (mb: string | null) => {
    const r = new Readers(data, 1);
    r.mbReader = mb;
    r.names.set("p@x", "Pat");
    return r;
  };
  const worker = readers(null);
  const program = readers(binary);
  const read = (r: Readers, op: string, args: unknown, lang: "zh" | "en") => r.read(op, args, lang).then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (r: Readers) => {
    const out: unknown[] = [];
    for (const lang of ["zh", "en"] as const) {
      for (const viewer of [{ email: "p@x", workspace: "w", home: true }, { email: "q@x", workspace: "x", home: false }, { email: "z@x", workspace: "x" }]) {
        for (const s of [null, "a1", "a2", "far", "nobody"]) out.push(await read(r, "threads", { viewer, session: s, lang }, lang));
        for (const id of [String(chat), `+${slack}`, String(far), "abc", "99999999999999999999", "-1", "0099"]) out.push(await read(r, "thread", { id, viewer, lang }, lang));
        for (const key of ["a1", "a2", "far", "nobody"])
          for (const [turns, jobs] of [[undefined, undefined], ["2", "now"], ["abc", undefined], ["1234567", "now"]])
            out.push(await read(r, "session", { key, viewer, lang, turns, jobs }, lang));
      }
    }
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["\"cc\":[", "\"channelName\":\"general\"", "\"xshare\":{", "\"name\":\"7\"", "\"name\":\"w3\"", "\"letters\":1", "\"lettersLast\":1", "\"unread\":2", "\"autoTitle\":\"Auto\"",
      "\"home\":\"a1\"", "\"status\":404", "\"name\":\"Una\"", "\"jobs\":[", "\"turns\":[", "\"port\":9000", "\"name\":\"Pat\""])
      assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

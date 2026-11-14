// The chat list as the station makes it for everyone (`sharedOf`, and `sharedChats`: what a viewer's workspace sees of
// it) and what a viewer's own of it is (`chatMarks`) by the MoonBit reader (station/mb src/readops/shared.mbt,
// chatmarks.mbt; read/pool.ts MOVED) as the worker reads them, on the same database: chats of several agents, one archived beside them, a card waiting and its options, one answered, one
// closed, one withdrawn, a need without a card, a message that only quotes, the local page's; a Slack thread its agent
// came from, named by the station's names book, with its people; agents with no chat, named or by their thread; a
// watch, a chat opened and one shared, the archive review's marks, process states, client keys and the cloud's names;
// a viewer's let-go card, kept, hidden, muted and read chats, pins and Slack self; whole and of some sessions and
// threads, in either language, with the cards kept from before they were kept, and with the edits' index gone.
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

test("the MoonBit reader reads the shared chat list as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-shared-chats-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({
    connects: [{ id: "team", kind: "slack", slack: { botName: "Helper", team: { id: "T1", name: "Team One" } } }, { id: "plain" }, { id: "blank", slack: { botName: "" } },
      { id: "fs", kind: "feishu", feishu: { tenant: { name: "Co" } } }],
    automaticDecisions: { completion: { enabled: true } },
  }));
  writeFileSync(join(data, "slack-names.json"), JSON.stringify({
    "u:T1:U1": { person: { name: "Una", email: "una@x", picture: "https://p/una.png" } },
    "u:T1:U2": { person: { name: "" } },
    "c:T1:C1": { channel: "general" },
  }));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const db = store.db;
  const now = wall.now();
  const session = (key: string, extra: Record<string, unknown> = {}) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1000, ...extra } as Parameters<Store["insertSession"]>[0]);
  session("a1", { ws: "w", createdBy: "p@x", model: "opus", lastActiveAt: 5000 });
  session("a2", { ws: "w", runtime: "codex", connect: "blank", createdBy: "slack:team:U1", lastActiveAt: 5000 });
  session("a3", { ws: null, createdBy: "local", lastActiveAt: 4000 });
  session("s1", { connect: "team", ws: "w", lastActiveAt: 3000 });
  session("solo", { ws: "w", title: "  Solo  ", lastActiveAt: 2000 });
  session("lone", { ws: "w", title: "  Lone  ", createdBy: "slack:fs:F1", lastActiveAt: 2000 });
  session("t1", { ws: "w", lastActiveAt: 1500 });
  session("gone", { ws: "w", lastActiveAt: 6000 });
  db.prepare("UPDATE sessions SET archived_at = 7000 WHERE key = 'gone'").run();
  let ts = 0;
  const say = (t: number, kind: "person" | "agent" | "ember", author: string, text: string, extra: Record<string, unknown> = {}) => {
    const at = String(++ts);
    store.insertMessage({ ...newMessage(t, at, kind, author, text), at: now - 100_000 + ts * 10, ...extra } as ReturnType<typeof newMessage>);
    return Number(db.prepare("SELECT MAX(n) AS n FROM entries WHERE thread = ?").get(t)!.n);
  };
  const chat = (key: string, title: string | null, members: string[]) => {
    const id = store.openThread("ember", "CHAT", key, title, null).id;
    for (const m of members) store.joinThread(id, m, "ember");
    return id;
  };
  const options = { type: "options", options: [{ label: "yes" }, { label: "no" }] };
  // A chat of two agents (one archived beside them): a card answered, one closed, one withdrawn, then one waiting.
  const both = chat("both", "Both", ["a1", "a2", "gone"]);
  say(both, "person", "p@x", "hello");
  say(both, "agent", "a1", "pick one", { card: options, agentIdentity: { runtime: "claude", model: "opus" } });
  say(both, "person", "p@x", "yes please", { quotes: [{ author: "a1", text: "pick one", comment: "", ts: "2" }] });
  const shut = say(both, "agent", "a2", "and this", { card: { type: "text", placeholder: "x" } });
  db.prepare("INSERT INTO closed_cards (thread, n, viewer, at) VALUES (?, ?, 'q@x', ?)").run(both, shut, now - 5000);
  const withdrawn = say(both, "agent", "a1", "never mind", { card: options });
  db.prepare("INSERT INTO closed_cards (thread, n, viewer, at) VALUES (?, ?, 'a1', ?)").run(both, withdrawn, now - 4000);
  say(both, "agent", "a1", "last one?", { card: options, declared: "need_decision" });
  const last = Number(db.prepare("SELECT MAX(n) AS n FROM entries WHERE thread = ?").get(both)!.n);
  db.prepare("INSERT INTO archive_suggestions (thread, version, at) VALUES (?, ?, 1)").run(both, last);
  db.prepare("INSERT INTO archive_verdicts (thread, version, at, verdict) VALUES (?, ?, 2, ?)").run(both, last, JSON.stringify({ option: 1, name: "keep", archive: false }));
  // A need without a card: the agent's turn ended needing help, its message the latest.
  const need = chat("need", null, ["a3"]);
  say(need, "person", "local", "can you");
  say(need, "agent", "a3", "I need a key");
  db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,need) VALUES ('n1','a3','input',?,?,'completed','need_help','a key')").run(now - 200_000, now);
  // A message that only quotes, by someone the cloud names.
  const quoted = chat("quoted", "Quoted", ["solo"]);
  say(quoted, "agent", "solo", "hi");
  say(quoted, "person", "p@x", "  ", { quotes: [{ author: "x", text: "y", comment: "" }] });
  db.prepare("INSERT INTO archive_verdicts (thread, version, at, verdict) VALUES (?, 0, 2, '[1,2]')").run(quoted);
  // Two cards before a person writes: the first is not the one answered.
  const twice = chat("twice", "Twice", ["t1"]);
  say(twice, "agent", "t1", "one", { card: options });
  say(twice, "agent", "t1", "two", { card: options });
  say(twice, "person", "slack:team:U1", "two it is");
  // A Slack thread an agent came from (s1 has no chat of its own), its people by the names book.
  const slack = store.openThread("slack:T1", "C1", "1000.1", null, null).id;
  store.joinThread(slack, "s1", "team");
  store.joinThread(slack, "a2", "team");
  say(slack, "person", "U1", "<@U9> first line\nsecond");
  say(slack, "person", "U2", "me too");
  // A watch, a chat opened from another, one shared, process states, client keys, the cloud's names.
  db.prepare("INSERT INTO jobs(id,session_key,name,command,cwd,port,token,state,started_at,restarts,log,watch) VALUES ('w1','a1','ci','true','/',NULL,'t','running',100,0,'/dev/null',1)").run();
  db.prepare("INSERT INTO jobs(id,session_key,name,command,cwd,port,token,state,started_at,restarts,log,watch) VALUES ('w2','a1','deploy','true','/',NULL,'t2','running',50,0,'/dev/null',1)").run();
  db.prepare("INSERT INTO job_notices(job_id,at,text) VALUES ('w1',900,'green')").run();
  db.prepare("INSERT INTO opened_chats(child_station,child,parent_station,parent,key,title,created_at) VALUES ('','a2','','a1','k','Asked',1)").run();
  db.prepare("INSERT INTO opened_chats(child_station,child,parent_station,parent,key,title,created_at) VALUES ('','a3','','a1','k3',NULL,3)").run();
  db.prepare("INSERT INTO opened_chats(child_station,child,parent_station,parent,key,title,created_at) VALUES ('st2','far','','a1','k2',NULL,2)").run();
  db.prepare("INSERT INTO chat_shares(session,shared,write,by,at) VALUES ('a1',?,1,'p@x',?)").run(JSON.stringify([{ workspace: "w2", name: "Two", used: now }, { workspace: "w3", used: 1 }]), now);
  // What is the viewers' own.
  db.prepare("INSERT INTO dismissed (viewer, thread, n, at) VALUES ('p@x', ?, ?, 1)").run(both, last);
  db.prepare("INSERT INTO kept_chats (viewer, thread) VALUES ('p@x', ?)").run(quoted);
  db.prepare("INSERT INTO hidden_chats (viewer, thread) VALUES ('p@x', ?)").run(need);
  db.prepare("INSERT INTO muted_chats (viewer, thread) VALUES ('q@x', ?)").run(both);
  db.prepare("INSERT INTO reads (viewer, thread, n, at) VALUES ('p@x', ?, 2, 1)").run(both);
  db.prepare("INSERT INTO pins (viewer, session, at) VALUES ('p@x', 'a1', 5)").run();
  db.prepare("INSERT INTO identities (viewer, slack_user, at) VALUES ('p@x', 'U1', 1)").run();
  // The archive: a session archived with its own chat, a chat archived alone, the archived one beside a chat's agents.
  session("arch", { ws: "w", lastActiveAt: 900 });
  const archChat = chat("arch", "Archived", ["arch"]);
  db.prepare("UPDATE threads SET home = 'arch' WHERE id = ?").run(archChat);
  say(archChat, "person", "p@x", "before it went");
  db.prepare("UPDATE sessions SET archived_at = 6500, archived_by = 'auto' WHERE key = 'arch'").run();
  db.prepare("UPDATE threads SET hidden_at = 6500, hidden_by = 'auto' WHERE id = ?").run(archChat);
  // An agent come of a Feishu group, with nothing said there yet: named by the group.
  writeFileSync(join(data, "feishu-names.json"), JSON.stringify({ "c:fs:oc_abc": { channel: "The group" } }));
  session("fsess", { connect: "fs", ws: "w", lastActiveAt: 950 });
  store.joinThread(store.openThread("feishu:fs", "oc_abc", "f.1", null, null).id, "fsess", "fs");
  const lonely = chat("lonely", null, ["a3"]);
  say(lonely, "person", "p@x", "alone");
  db.prepare("UPDATE threads SET hidden_at = 6600 WHERE id = ?").run(lonely);
  const readers = (mb: string | null) => {
    const r = new Readers(data, 1);
    r.mbReader = mb;
    r.names.set("p@x", "Pat");
    r.processes = () => new Map([["a1", "running"]]);
    r.clientKeys = () => new Map([["a1", "ck-1"]]);
    return r;
  };
  const worker = readers(null);
  const program = readers(binary);
  const read = (r: Readers, op: string, args: unknown, lang: "zh" | "en") => r.read(op, args, lang).then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (r: Readers) => {
    const out: unknown[] = [];
    for (const lang of ["zh", "en"] as const) {
      out.push(await read(r, "sharedOf", { sessions: null, threads: null }, lang));
      out.push(await read(r, "sharedOf", { sessions: ["a1"], threads: [need] }, lang));
      out.push(await read(r, "sharedOf", { sessions: ["solo", "nobody"], threads: [9999] }, lang));
      out.push(await read(r, "sharedOf", { sessions: [], threads: [] }, lang));
      for (const viewer of [{ workspace: "w", home: true }, { workspace: "x", home: false }, { workspace: "x" }]) {
        out.push(await read(r, "sharedChats", { viewer, sessions: null, threads: null }, lang));
        out.push(await read(r, "sharedChats", { viewer, sessions: ["s1"], threads: [slack] }, lang));
      }
      for (const viewer of [{ email: "p@x", workspace: "w", home: true }, { email: "Q@X", workspace: "w" }, { email: "u@x", workspace: "x", home: false }]) {
        out.push(await read(r, "chatMarks", { viewer, scope: null }, lang));
        out.push(await read(r, "chatMarks", { viewer, scope: { sessions: ["a1", "a3", "gone"], threads: [need, twice] } }, lang));
        // A device that does not make its list itself, and the archive a page at a time.
        out.push(await read(r, "chats", { viewer, archived: false }, lang));
        out.push(await read(r, "chats", { viewer, archived: true }, lang));
        for (const page of ["", "  :x", "6600:", "6500:arch", "abc:x", " 7000 :zzz", "0x1F00:a", "9999999999999999:z"]) out.push(await read(r, "chats", { viewer, archived: true, page }, lang));
        out.push(await read(r, "chatRows", { viewer, sessions: ["a1", "s1"], threads: [need, slack] }, lang));
      }
    }
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["\"decision\":", "\"answeredBy\":", "\"closed\":true", "\"quoted\":true", "\"need\":", "\"quotedOnly\":true", "\"name\":\"Una\"",
      "\"channelName\":\"general\"", "\"teamName\":\"Team One\"", "\"authorName\":\"Pat\"", "\"watch\":", "\"opener\":", "\"opened\":", "\"xshare\":",
      "\"archiveRecommended\":true", "\"archiveCheck\":", "\"process\":\"running\"", "\"clientKey\":\"ck-1\"", "\"title\":\"Lone\"", "\"authorModel\":\"opus\"",
      "\"authorRuntime\":", "\"said\":{", "\"via\":\"local\"", "\"picture\":\"https://p/una.png\"", "\"via\":\"feishu\"", "\"authorName\":\"blank\"", "\"dismissed\":true", "\"selves\":[\"U1\"]", "\"team\":\"Team One\"", "\"fs\":\"Co\"", "\"hidden\":[", "\"muted\":[", "\"pins\":{\"a1\":5}"])
      assert.ok(said.includes(sign), sign);
    // A chat whose card the store no longer keeps waiting: none shown, whatever its posts say.
    db.prepare("DELETE FROM pending_cards WHERE thread = ?").run(both);
    assert.deepEqual(await all(program), await all(worker));
    // Cards posted before the store kept them: each found as it was before.
    db.exec("UPDATE pending_cards_from SET entry = 1000000000; DELETE FROM pending_cards");
    assert.deepEqual(await all(program), await all(worker));
    // A store whose chats' unread boundaries are not kept (one from before): found among the messages near the latest.
    db.exec("UPDATE thread_state SET said_other_known = 0; DELETE FROM said_state_guard");
    assert.deepEqual(await all(program), await all(worker));
    // Without the edits' index (a store whose lookup must be repaired): messages read bounded, or refused alike.
    db.exec("DROP INDEX IF EXISTS entries_edits");
    assert.deepEqual(await all(program), await all(worker));
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

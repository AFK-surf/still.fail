// The jobs up of a viewer's workspace (`openJobs`: GET /jobs), and the resources page's chats (`resourceChats`), by the MoonBit reader (station/mb src/readops/openjobs.mbt;
// read/pool.ts MOVED) as the worker reads them, on the same database: commands running, services up and down, of
// sessions of the workspace, the home one and another; with the chat each is in for a device from before (its own chat
// named or not, one it only takes part in, one archived, an agent named by the Slack thread it came from, one with no
// chat at all), and without; for viewers of either workspace, in either language.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads the open jobs as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-open-jobs-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ connects: [{ id: "team", slack: { team: { id: "T1", name: "Team" } } }] }));
  writeFileSync(join(data, "slack-names.json"), JSON.stringify({ "c:T1:C1": { channel: "general" } }));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const db = store.db;
  const session = (key: string, extra: Record<string, unknown> = {}) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 100, ...extra } as Parameters<Store["insertSession"]>[0]);
  let ts = 0;
  const say = (t: number, author: string, text: string, at: number) =>
    store.insertMessage({ ...newMessage(t, String(++ts), "person", author, text), at } as ReturnType<typeof newMessage>);
  const chat = (key: string, title: string | null, members: string[], home: string | null = null) => {
    const id = store.openThread("ember", "CHAT", key, title, null).id;
    if (home !== null) db.prepare("UPDATE threads SET home = ? WHERE id = ?").run(home, id);
    for (const m of members) store.joinThread(id, m, "ember");
    return id;
  };
  session("named", { ws: "w", lastActiveAt: 500 });
  session("plain", { ws: "w", lastActiveAt: 400 });
  session("helper", { ws: "w", lastActiveAt: 300 });
  session("slacky", { ws: "w", connect: "team", lastActiveAt: 200 });
  session("lone", { ws: null, title: " Lone ", lastActiveAt: 150 });
  session("gone", { ws: "w", lastActiveAt: 120 });
  session("far", { ws: "x", lastActiveAt: 110 });
  const named = chat("named", "Named chat", ["named", "helper"], "named");
  say(named, "p@x", "hi", 1000);
  const plain = chat("plain", null, ["plain"], "plain");
  say(plain, "p@x", "hey", 900);
  const old = chat("gone", "Gone chat", ["gone"], "gone");
  say(old, "p@x", "before", 800);
  db.prepare("UPDATE sessions SET archived_at = 5000 WHERE key = 'gone'").run();
  db.prepare("UPDATE threads SET hidden_at = 5000 WHERE id = ?").run(old);
  const slack = store.openThread("slack:T1", "C1", "1.1", null, null).id;
  store.joinThread(slack, "slacky", "team");
  say(slack, "U1", "<@U9> please   look\nat this", 700);
  chat("far", "Far", ["far"], "far");
  // an agent whose latest thread is the Slack thread, unnamed: titled by its first words
  session("listener", { ws: "w", connect: "team", lastActiveAt: 80 });
  store.joinThread(slack, "listener", "team");
  // and one whose Slack thread has no words yet: by its channel
  const quiet = store.openThread("slack:T1", "C1", "1.2", null, null).id;
  session("quiet", { ws: "w", connect: "team", lastActiveAt: 70 });
  store.joinThread(quiet, "quiet", "team");
  // helper's own chat archived (its job named by it over the one it takes part in); an unnamed chat of slacky's own,
  // named by the thread it came from; a chat archived alone, of an agent not archived.
  const helperOld = chat("helper-old", "Helper's old", ["helper"]);
  db.prepare("UPDATE threads SET hidden_at = 4000 WHERE id = ?").run(helperOld);
  chat("sl", null, ["slacky"], "slacky");
  session("solo2", { ws: "w", lastActiveAt: 90 });
  const alone = chat("alone", "Alone archived", ["solo2"]);
  say(alone, "p@x", "x", 600);
  db.prepare("UPDATE threads SET hidden_at = 4100 WHERE id = ?").run(alone);
  let n = 0;
  const job = (key: string, state: string, port: number | null, started: number) =>
    db.prepare("INSERT INTO jobs(id,session_key,name,command,cwd,port,token,state,started_at,restarts,log,watch) VALUES (?,?,?,'true','/',?,?,?,?,0,'/dev/null',0)")
      .run(`j${++n}`, key, `job ${n}`, port, `t${n}`, state, started);
  job("named", "running", null, 100);
  job("helper", "running", 9001, 200);
  job("plain", "exited", 9002, 300);
  job("plain", "exited", null, 310);
  job("slacky", "running", null, 400);
  job("lone", "running", null, 500);
  job("gone", "running", null, 600);
  job("far", "running", null, 700);
  job("nobody", "running", null, 800);
  job("solo2", "running", null, 900);
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (r: Readers, op: string, args: unknown, lang: "zh" | "en") => r.read(op, args, lang).then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (r: Readers) => {
    const out: unknown[] = [];
    for (const lang of ["zh", "en"] as const)
      for (const viewer of [{ email: "p@x", workspace: "w", home: true }, { email: "p@x", workspace: "x", home: false }, { email: "q@x", workspace: "w" }, { email: "p@x", workspace: "wé", home: true }])
        for (const chats of [true, false]) out.push(await read(r, "openJobs", { viewer, lang, chats }, lang));
    // The resources page's chats: each session's latest thread and its title.
    for (const lang of ["zh", "en"] as const)
      for (const viewer of [null, { email: "p@x", workspace: "w", home: true }, { email: "p@x", workspace: "x", home: false }])
        out.push(await read(r, "resourceChats", { sessions: ["named", "plain", "helper", "slacky", "lone", "gone", "far", "solo2", "listener", "quiet", "nobody"], viewer }, lang));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["\"title\":\"Named chat\"", "\"title\":\"please look\"", "\"title\":\"Lone\"", "\"archived\":true", "\"port\":9001", "\"chat\":"])
      assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

// What the people of the station's own chats hear about (`turnNotices`, `saidNotices`; src/cloud/notify.ts asks them)
// by the MoonBit reader (station/mb src/readops/notices.mbt; read/pool.ts MOVED) as the worker makes them, on the same
// database: turns ending done with something said, done with nothing, blocked on a card, on a message it asks with,
// on what was told before, failed; a person's message (with words and a file alone), the station's ⚠️ and its other
// words; chats named, unnamed and hidden, people muted, a Slack person who started an agent; ends before `since` and
// one already told; in either language.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader makes chats' notices as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-notices-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ connects: [{ id: "team", slack: { botName: "Helper", team: { id: "T1", name: "Team" } } }] }));
  writeFileSync(join(data, "slack-names.json"), JSON.stringify({ "u:T1:U1": { person: { name: "Una", email: "Una@X" } } }));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const db = store.db;
  const session = (key: string, extra: Record<string, unknown> = {}) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 100, ...extra } as Parameters<Store["insertSession"]>[0]);
  for (const [key, by] of [["done", "p@x"], ["quiet", "p@x"], ["card", "slack:team:U1"], ["ask", "local"], ["told", "p@x"], ["failed", "p@x"], ["hidden", "p@x"]] as const) session(key, { createdBy: by });
  let ts = 0;
  const say = (t: number, kind: "person" | "agent" | "ember", author: string, text: string, at: number, extra: Record<string, unknown> = {}) => {
    store.insertMessage({ ...newMessage(t, String(++ts), kind, author, text), at, ...extra } as ReturnType<typeof newMessage>);
    return Number(db.prepare("SELECT MAX(n) AS n FROM entries WHERE thread = ?").get(t)!.n);
  };
  const chat = (key: string, title: string | null, member: string) => {
    const id = store.openThread("ember", "CHAT", key, title, "q@x").id;
    store.joinThread(id, member, "ember");
    return id;
  };
  const turn = (id: string, key: string, started: number, ended: number, declared: string | null, outcome = "completed", need: string | null = null) =>
    db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,need) VALUES (?,?,'input',?,?,?,?,?)").run(id, key, started, ended, outcome, declared, need);
  const done = chat("done", "Done chat", "done");
  say(done, "person", "r@x", "please", 1000);
  say(done, "agent", "done", "x".repeat(450), 2100);
  turn("d1", "done", 2000, 2200, "all_done");
  const quiet = chat("quiet", null, "quiet");
  say(quiet, "agent", "quiet", "   ", 2100);
  turn("q1", "quiet", 2000, 2200, "final");
  const card = chat("card", "Card chat", "card");
  say(card, "agent", "card", "pick", 2100, { card: { type: "options", options: [{ label: "a" }] } });
  turn("c1", "card", 2000, 2200, "need_decision", "completed", "  ");
  const ask = chat("ask", "Ask chat", "ask");
  say(ask, "person", "m@x", "hi", 1000);
  say(ask, "agent", "ask", "what key?", 2100);
  turn("a1", "ask", 2000, 2200, "need_help", "completed", "a key");
  const told = chat("told", "Told chat", "told");
  const waiting = say(told, "agent", "told", "still waiting", 1500);
  turn("t0", "told", 1400, 1600, "need_help");
  turn("t1", "told", 2000, 2200, "need_help");
  db.prepare("UPDATE turns SET about_thread = ?, about_n = ?, about_ts = 'x' WHERE id = 't1'").run(told, waiting);
  const failed = chat("failed", "Failed chat", "failed");
  say(failed, "agent", "failed", "oops", 2100);
  turn("f1", "failed", 2000, 2200, "final", "failed");
  const hidden = chat("hidden", "Hidden", "hidden");
  say(hidden, "agent", "hidden", "said in a hidden chat", 2100);
  // (hidden after: something said brings a chat back)
  db.prepare("UPDATE threads SET hidden_at = 5 WHERE id = ?").run(hidden);
  turn("h1", "hidden", 2000, 2200, "final");
  session("talker", { createdBy: "p@x" });
  const talk = chat("talk", null, "talker");
  db.prepare("INSERT INTO muted_chats (viewer, thread) VALUES ('r@x', ?)").run(talk);
  say(talk, "person", "r@x", "earlier", 1000);
  const person = say(talk, "person", "r@x", "a word", 3000);
  const file = say(talk, "person", "s@x", "  ", 3001, { attachments: [{ name: "a.png", path: "/a.png", size: 1 }] });
  const wrong = say(talk, "ember", "ember", "⚠️ The model failed  \n\nwhat it said", 3002);
  const plain = say(talk, "ember", "ember", "just a note", 3003);
  const entry = (n: number, kind: string, authorKind: string, author: string, text: string | null, at: number) => ({ n, kind, authorKind, author, text, at });
  const readers = (mb: string | null) => {
    const r = new Readers(data, 1);
    r.mbReader = mb;
    r.names.set("p@x", "Pat");
    return r;
  };
  const worker = readers(null);
  const program = readers(binary);
  const read = (r: Readers, op: string, args: unknown, lang: "zh" | "en") => r.read(op, args, lang, { told: true }).then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  // (`at`: the time each was made, ours alone)
  const strip = (v: unknown): unknown => JSON.parse(JSON.stringify(v, (k, x) => (k === "at" && typeof x === "number" && x > 1e12 ? 0 : x)));
  const all = async (r: Readers) => {
    const out: unknown[] = [];
    for (const lang of ["zh", "en"] as const) {
      for (const key of ["done", "quiet", "card", "ask", "told", "failed", "hidden", "nobody"]) {
        out.push(await read(r, "turnNotices", { key, since: 0, ended: null, lang }, lang));
        out.push(await read(r, "turnNotices", { key, since: 2300, ended: null, lang }, lang));
        out.push(await read(r, "turnNotices", { key, since: 0, ended: 2200, lang }, lang));
      }
      const entries = [entry(person, "message", "person", "r@x", "a word", 3000), entry(file, "message", "person", "s@x", "  ", 3001),
        entry(wrong, "message", "ember", "ember", "⚠️ The model failed  \n\nwhat it said", 3002), entry(plain, "message", "ember", "ember", "just a note", 3003)];
      for (const [thread, list, since] of [[talk, entries, 0], [talk, entries.slice(0, 1), 0], [talk, entries.slice(2), 0], [talk, entries, 5000], [hidden, entries, 0], [quiet, [], 0], [9999, entries, 0]] as const)
        out.push(await read(r, "saidNotices", { thread, entries: list, since, lang }, lang));
    }
    return strip(out);
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["\"kind\":\"done\"", "\"kind\":\"block\"", "\"text\":\"a key\"", "\"kind\":\"message\"", "\"kind\":\"failed\"", "\"text\":\"The model failed\"", "\"title\":\"Done chat\"",
      "una@x", "x".repeat(400) + "\""])
      assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

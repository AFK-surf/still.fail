// A chat's entries and its own log of letters (`entries`, `letters`: GET /threads/:id/entries, /letters) by the
// MoonBit reader (station/mb src/readops/entries.mbt; read/pool.ts MOVED) as the worker reads them, on the same
// database: messages of people, agents (with and without what they ran said, of a session that went on in another
// runtime, of one gone), the station and the local page, edits, cards and options from before cards, attachments and
// quotes (one list not as it should be), a letter in and out, a notice's change; every way of paging (since, back,
// a gap, the latest), limits of none, zero, a few, many, not a number, infinite, and numbers it refuses, in either
// language; a chat that is not there.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads a chat's entries and letters as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-entries-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ connects: [{ id: "team", slack: { botName: "Helper", team: { id: "T1", name: "Team" } } }] }));
  writeFileSync(join(data, "slack-names.json"), JSON.stringify({ "u:T1:U1": { person: { name: "Una", picture: "https://p/u.png" } } }));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const db = store.db;
  const session = (key: string, extra: Record<string, unknown> = {}) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ...extra } as Parameters<Store["insertSession"]>[0]);
  session("a1", { model: "opus", title: "Agent one" });
  session("a2", { runtime: "codex", model: "gpt" });
  db.prepare("UPDATE sessions SET original_runtime = 'claude' WHERE key = 'a2'").run();
  session("s1", { connect: "team" });
  const chat = store.openThread("ember", "CHAT", "c", "Chat", null).id;
  store.joinThread(chat, "a1", "ember");
  store.joinThread(chat, "a2", "ember");
  let ts = 0;
  const say = (t: number, kind: "person" | "agent" | "ember", author: string, text: string, extra: Record<string, unknown> = {}) => {
    const at = String(++ts);
    store.insertMessage({ ...newMessage(t, at, kind, author, text), at: 1000 + ts, ...extra } as ReturnType<typeof newMessage>);
    return at;
  };
  const first = say(chat, "person", "p@x", "hello", { attachments: [{ name: "a.png", path: "/a.png", size: 3, width: 2, height: 1 }], client: "web" });
  store.editMessage("ember", "CHAT", "c", first, "hello, edited");
  say(chat, "person", "local", "from the page", { quotes: [{ author: "a1", text: "t", comment: "c", ts: "1" }] });
  say(chat, "agent", "a1", "said with what ran", { agentIdentity: { runtime: "claude", model: "sonnet" }, declared: "all_done" });
  say(chat, "agent", "a2", "said before what ran was kept", { card: { type: "options", options: [{ label: "x" }] }, declared: "need_decision" });
  say(chat, "agent", "a2", "options from before cards");
  db.prepare("UPDATE entries SET options = ? WHERE thread = ? AND n = (SELECT MAX(n) FROM entries WHERE thread = ?)").run(JSON.stringify(["a", "b"]), chat, chat);
  say(chat, "agent", "gone", "of a session no more");
  say(chat, "agent", "a1", "identity null", { profile: "cc", runtime: "claude" });
  db.prepare("UPDATE entries SET agent_identity = 'null' WHERE thread = ? AND n = (SELECT MAX(n) FROM entries WHERE thread = ?)").run(chat, chat);
  say(chat, "ember", "ember", "a notice");
  db.prepare("UPDATE entries SET change = ? WHERE thread = ? AND n = (SELECT MAX(n) FROM entries WHERE thread = ?)").run(JSON.stringify({ was: { model: "a" }, now: { model: "b" } }), chat, chat);
  say(chat, "person", "p@x", "bad list");
  db.prepare("UPDATE entries SET quotes = '[{\"author\":1}]', attachments = 'nope' WHERE thread = ? AND n = (SELECT MAX(n) FROM entries WHERE thread = ?)").run(chat, chat);
  for (let i = 0; i < 60; i++) say(chat, "person", "q@x", `more ${i}`);
  // (messages of before what ran was kept with each)
  db.prepare("UPDATE entries SET agent_identity = NULL WHERE author = 'a2'").run();
  db.prepare("INSERT INTO letters (thread, n, ts, author_kind, author, text, attachments, at, letter) VALUES (?, 1, 'l1', 'agent', 'a1', 'in', NULL, 5, ?)").run(chat, JSON.stringify({ way: "in", title: "From far", link: "x" }));
  db.prepare("INSERT INTO letters (thread, n, ts, author_kind, author, text, attachments, at, letter) VALUES (?, 2, 'l2', 'person', 'p@x', 'out', NULL, 6, ?)").run(chat, JSON.stringify({ way: "out", title: "To far" }));
  db.prepare("INSERT INTO letters (thread, n, ts, author_kind, author, text, attachments, at, letter) VALUES (?, 3, 'l3', 'person', 'p@x', 'odd', NULL, 7, 'not json')").run(chat);
  const slack = store.openThread("slack:T1", "C1", "1.1", null, null).id;
  store.joinThread(slack, "s1", "team");
  say(slack, "person", "U1", "from slack");
  say(slack, "agent", "s1", "the bot");
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  for (const r of [worker, program]) r.names.set("p@x", "Pat");
  const read = (r: Readers, op: string, args: unknown, lang: "zh" | "en") => r.read(op, args, lang).then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const queries: [string, string][][] = [
    [], [["limit", "3"]], [["limit", "0"]], [["limit", "abc"]], [["limit", "inf"]], [["limit", "Infinity"]], [["limit", "-infinity"]], [["limit", "-4"]], [["limit", "2.7"]], [["limit", "1e3"]], [["limit", "nan"]],
    [["after", "3"]], [["after", "3"], ["limit", "2"]], [["after", "9223372036854775807"]], [["after", "1e30"]],
    [["before", "10"], ["limit", "4"]], [["before", "+5"]], [["from", "2"], ["to", "6"]], [["from", "2"]],
    [["after", "-1"]], [["before", "1.5"]], [["to", " 3"]], [["after", "0x10"]], [["after", "inf"]], [["after", "3"], ["after", "abc"]], [["from", ".5e1"], ["to", "6."]],
  ];
  const all = async (r: Readers) => {
    const out: unknown[] = [];
    for (const lang of ["zh", "en"] as const) {
      for (const params of queries) {
        for (const thread of [chat, slack]) {
          out.push(await read(r, "entries", { thread, params }, lang));
          out.push(await read(r, "letters", { thread, params }, lang));
        }
      }
      out.push(await read(r, "entries", { thread: 9999, params: [] }, lang));
      out.push(await read(r, "letters", { thread: 9999, params: [] }, lang));
      out.push(await read(r, "entries", { thread: chat, params: { limit: "2", before: "8" } }, lang));
    }
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["hello, edited", "\"authorName\":\"Pat\"", "\"authorName\":\"Una\"", "\"authorPicture\":", "\"authorModel\":\"sonnet\"", "\"authorRuntime\":\"claude\"",
      "\"authorModel\":\"opus\"", "\"ending\":\"need_help\"", "\"declared\":\"final\"", "\"card\":{\"type\":\"options\",\"options\":[\"a\",\"b\"]}", "\"change\":", "\"letter\":{\"way\":\"in\"",
      "\"status\":400", "\"status\":404", "\"authorName\":\"still.fail\"", "\"client\":\"web\"", "\"agentIdentity\":null"])
      assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

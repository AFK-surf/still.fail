// A chat's messages as the Router reads a Task (`outflowMessages`), by the MoonBit reader (station/mb
// src/readops/outflow.mbt; read/pool.ts MOVED) as the worker reads them, on the same data: a long chat of messages,
// edits and letters, entries or messages alone, after a message, limits past their bounds; who wrote each as the names
// books know them (a Slack connect's, a Feishu one's, another station's, someone unknown, the page's, a cloud person);
// a chat of another workspace, one with no members, one not there; before and after the letters' page lookup is prepared.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";
import { pageLetterStep } from "../src/store/page-letter-index.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads a chat's messages for the Router as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-outflow-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ connects: [
    { id: "team", slack: { team: { id: "T1", name: "Team" } } }, { id: "fs", kind: "feishu", feishu: { tenant: { name: "Co" } } }, { id: "nameless", slack: { team: { id: "" } } },
  ] }));
  writeFileSync(join(data, "remote-connects.json"), JSON.stringify({ far: { described: { kind: "slack", team: "T9", identity: { team: "Far" } } }, team: { described: { kind: "slack", team: "T0" } } }));
  writeFileSync(join(data, "slack-names.json"), JSON.stringify({
    "u:T1:U1": { person: { name: "Ann", email: "ann@x" } }, "u:T1:U2": { person: { name: "U2" } }, "u:T9:U3": { person: { name: "", email: "" } },
    "u:?:U4": { person: { name: "Lost" } },
  }));
  writeFileSync(join(data, "feishu-names.json"), JSON.stringify({ "u:fs:ou_1": { person: { name: "Fei", email: "fei@x" } } }));
  for (const [key, ws] of [["mine", "w1"], ["home", null], ["other", "w2"]] as const)
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws } as Parameters<Store["insertSession"]>[0]);
  const thread = store.openThread("ember", "CHAT", "long", "Long", null).id;
  store.joinThread(thread, "mine", "ember");
  const homeChat = store.openThread("ember", "CHAT", "home", "Home", null).id;
  store.joinThread(homeChat, "home", "ember");
  const empty = store.openThread("ember", "CHAT", "empty", "Empty", null).id;
  const elsewhere = store.openThread("ember", "CHAT", "else", "Else", null).id;
  store.joinThread(elsewhere, "other", "ember");
  const authors = ["slack:team:U1", "slack:team:U2", "slack:far:U3", "slack:team:U9", "slack:nowhere:U4", "slack:fs:ou_1", "slack::x", "slack:team:", "local", "p@x"];
  let ts = 0;
  const say = (t: number, kind: "person" | "agent", author: string, text: string, extra: Record<string, unknown> = {}) => {
    const at = String(++ts);
    store.insertMessage({ ...newMessage(t, at, kind, author, text), at: ts * 10, ...extra } as ReturnType<typeof newMessage>);
    return at;
  };
  for (let i = 0; i < 120; i++) {
    const at = say(thread, i % 4 === 0 ? "agent" : "person", i % 4 === 0 ? "mine" : authors[i % authors.length]!, `message ${i}`,
      i % 13 === 0 ? { letter: { way: "out", title: "To Y", link: null } } : {});
    if (i % 9 === 0) store.editMessage("ember", "CHAT", "long", at, `message ${i}, edited`);
  }
  say(homeChat, "person", "local", "at home");
  say(elsewhere, "person", "p@x", "elsewhere");
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (readers: Readers) => {
    const out: unknown[] = [];
    const w1 = { workspace: "w1", home: false };
    for (const messagesOnly of [false, true])
      for (const [after, limit] of [[0, 500], [0, 7], [50, 20], [130, 10], [119, 1], [0, 0], [0, 900], [-5, 3], [1.5, 2.5]])
        out.push(await read(readers, "outflowMessages", { thread, after, limit, ws: w1, messagesOnly }));
    for (const [t, ws] of [[homeChat, undefined], [homeChat, w1], [empty, undefined], [empty, w1], [elsewhere, w1], [elsewhere, { workspace: "w2" }], [9999, undefined], ["1", undefined]] as const)
      out.push(await read(readers, "outflowMessages", { thread: t, after: 0, limit: 10, ws }));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    // Once the letters' page lookup is prepared, and with letters written since (its dirty rows).
    while (!pageLetterStep(store.db, thread).done);
    for (let i = 120; i < 126; i++) say(thread, "person", "p@x", `message ${i}`, i % 2 === 0 ? { letter: { way: "in", title: "From Z", link: null } } : {});
    const prepared = await all(program);
    assert.deepEqual(prepared, await all(worker));
    assert.ok(JSON.stringify(prepared).includes("message 125"));
    for (const sign of ["\"name\":\"Ann\"", "\"email\":\"ann@x\"", "\"name\":\"Fei\"", "\"via\":\"feishu\"", "\"via\":\"local\"", "\"via\":\"cloud\"", "edited", "\"kind\":\"edit\"", "\"messagesOnly\":true", "\"more\":true", "at home"])
      assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

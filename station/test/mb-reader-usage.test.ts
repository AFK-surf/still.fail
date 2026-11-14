// A session's usage read by the MoonBit reader (station/mb src/readops/usage.mbt; read/pool.ts MOVED) as the worker reads
// it, on the same database: the turns a part of a transcript's calls were made in (turns of their own people and
// threads, of none, taken from what was delivered or the one before, a session with no turns or none at all), and pages
// of its calls (the same time across a page, earlier ones, the extremes, a limit beyond its bounds, another workspace).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();
const I64_MAX = "9223372036854775807";
const I64_MIN = "-9223372036854775808";

test("the MoonBit reader reads a session's usage as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-usage-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const db = store.db;
  for (const [key, ws] of [["a", "mine"], ["b", null], ["empty", "mine"]] as const)
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, createdBy: "maker@x", ws } as Parameters<Store["insertSession"]>[0]);
  const home = store.openThread("ember", "chat", "home", null, null).id;
  store.joinThread(home, "a", "ember");
  const slack = store.openThread("slack:T", "C", "1", null, null).id;
  store.joinThread(slack, "a", "team");
  const message = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message',?,?,'hi',?)");
  const deliver = db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES (?,?,?,?)");
  message.run(home, 1, "person", "p1@x", 90); deliver.run(home, 1, "a", 100);
  message.run(slack, 1, "person", "U7", 290); deliver.run(slack, 1, "a", 300);
  message.run(home, 2, "agent", "a", 350); deliver.run(home, 2, "a", 360);
  message.run(home, 3, "person", "p3@x", 590); deliver.run(home, 3, "a", 600);
  const turn = db.prepare("INSERT INTO turns(id,session_key,kind,started_at,profile,person,thread) VALUES (?,?,?,?,?,?,?)");
  turn.run("t1", "a", "input", 100, null, null, null);
  turn.run("t2", "a", "input", 300, "other", null, null);
  turn.run("t3", "a", "steer", 400, null, null, null);
  turn.run("t4", "a", "input", 500, null, "named@x", 42);
  turn.run("t5", "a", "input", 550, null, null, null);
  // A message delivered as the next turn begins is that turn's, not the one before's.
  turn.run("t6", "a", "input", 800, null, null, null);
  turn.run("t7", "a", "steer", 900, null, null, null);
  message.run(home, 4, "person", "p4@x", 890); deliver.run(home, 4, "a", 900);
  turn.run("u1", "b", "input", 100, null, "b@x", null);
  const call = (id: string, at: number) => ({ id, at, model: "m", subagent: id.endsWith("s"), fast: id.endsWith("f"), input: 1, cacheRead: 2, cacheWrite: 3, cacheWriteLong: 4, output: at, calls: 1, context: 10, window: null });
  const of = { turn: "t1", person: "p1@x", thread: home, profile: "cc" };
  store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: "m" }, "claude",
    [...Array.from({ length: 12 }, (_, i) => [call(`c${i}`, 1000 + Math.floor(i / 3) * 10), of] as [ReturnType<typeof call>, typeof of]),
      [call("cs", 2000), of], [call("cf", 2000), { turn: null, person: null, thread: null, profile: null }]]);
  store.recordUsage("/b.jsonl", { session: "b", offset: 1, model: "m" }, "claude", [[call("d1", 1500), of]]);
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (readers: Readers) => {
    const out: unknown[] = [];
    for (const session of ["a", "b", "empty", "missing"])
      for (const [from, until] of [[0, 50], [0, 2000], [350, 550], [650, 650], [850, 950], [900, 100], [Number.NaN, 400]])
        out.push(await read(readers, "usageTurns", { session, from, until }));
    out.push(await read(readers, "usageTurns", { session: "a", from: "300", until: "650" }));
    const page = (session: string, extra: object = {}) => ({ session, from: I64_MIN, to: I64_MAX, beforeAt: I64_MAX, beforeSeq: I64_MAX, limit: 100, viewer: { workspace: "mine", home: false }, ...extra });
    for (const args of [page("a"), page("a", { limit: 4 }), page("a", { limit: 0 }), page("a", { limit: 500 }), page("a", { limit: 1.5 }),
      page("a", { beforeAt: "1010", beforeSeq: "6", limit: 2 }), page("a", { beforeAt: "1010", beforeSeq: "1", limit: 5 }),
      page("a", { from: "1010", to: "1030" }), page("a", { from: "1010", beforeAt: "1010", beforeSeq: "6" }), page("a", { to: "1000" }), page("a", { viewer: null }), page("b"), page("b", { viewer: { workspace: "x", home: true } }),
      page("missing"), page("a", { viewer: { workspace: "elsewhere", home: false } })])
      out.push(await read(readers, "usageCalls", args));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["\"person\":\"slack:team:U7\"", "\"person\":\"named@x\"", "\"person\":\"p3@x\"", "\"person\":\"maker@x\"", "\"profile\":\"other\"", "\"subagent\":true", "\"fast\":true", "\"next\":{\"at\":\"1010\""])
      assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

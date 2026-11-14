// The reads the station's own parts ask in the background, by the MoonBit reader (station/mb src/readops/background.mbt;
// read/pool.ts MOVED) as the worker reads them, on the same database: the sessions at work (a turn, a process, a job of
// each kind, a wait; archived; before the running jobs' lookup is prepared), a week's archive-policy checks (failed,
// recommended, past twenty chats an option, another workspace's, the home one's, before their lookups), and the people
// of a connect's recent threads (still.fail's own, a platform's, another connect's).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads what the station asks in the background as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-background-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const db = store.db;
  const session = (key: string, at: number, ws: string | null = "mine") =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: at, ws } as Parameters<Store["insertSession"]>[0]);
  const job = (id: string, sessionKey: string, extra: { port?: number; watch?: boolean; state?: string } = {}) =>
    store.insertJob({ id, sessionKey, name: id, command: "true", cwd: "/", port: extra.port ?? null, token: id, state: extra.state ?? "running", pgid: null,
      exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: extra.watch ?? false } as Parameters<Store["insertJob"]>[0]);
  for (const [i, key] of ["idle", "turn", "process", "service", "watcher", "ended", "waiting", "archived", "home-1"].entries()) session(key, 10 + i, key === "home-1" ? null : "mine");
  store.setRunning("turn", true);
  job("service-job", "service", { port: 9000 });
  job("watch-job", "watcher", { watch: true });
  job("ended-job", "ended", { state: "exited" });
  db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared) VALUES ('t','waiting','user',0,1,'completed','waiting')").run();
  db.prepare("UPDATE sessions SET archived_at=1 WHERE key='archived'").run();
  const now = store.now();
  const check = db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES (?, ?, ?)");
  for (let i = 0; i < 70; i++) {
    const key = `c${i}`;
    session(key, 100 + i, i % 7 === 0 ? "elsewhere" : i % 11 === 0 ? null : "mine");
    check.run(key, now - 3 * 86_400_000, JSON.stringify({ result: { selected: "agent_work" } }));
    check.run(key, now - 86_400_000 + i, i % 5 === 0 ? "not json" : JSON.stringify(i % 6 === 0 ? { error: "x" } : { result: { selected: i % 2 === 0 ? "complete" : i % 3 === 0 ? 7 : "human_needed" }, accepted: i % 4 === 0 }));
  }
  check.run("gone", now - 1000, JSON.stringify({ result: { selected: "complete" } }));
  const message = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message','person',?,'hi',?)");
  for (let n = 0; n < 12; n++) {
    const id = n % 4 === 0 ? store.openThread("ember", "chat", String(n), null, null).id : store.openThread("slack:T", "C", String(n), null, null).id;
    store.joinThread(id, "agent", n % 3 === 0 ? "other" : "team");
    if (n % 4 === 0) {
      message.run(id, 1, "slack:team:U1", n + 1);
      message.run(id, 2, "someone@x", n + 2);
    } else if (n !== 5) {
      message.run(id, 1, `U${n}`, n + 1);
      message.run(id, 2, "U0", n + 2);
    }
  }
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const since = now - 7 * 86_400_000;
  const all = async (readers: Readers) => {
    const out: unknown[] = [];
    for (const processes of [[], ["process", "nobody"], ["idle\"quoted"]]) out.push(await read(readers, "sessionsAtWork", { processes }));
    for (const viewer of [{ workspace: "mine", home: false }, { workspace: "mine", home: true }, { workspace: "elsewhere", home: false }, { workspace: "none", home: false }])
      out.push(await read(readers, "policyChecks", { since, viewer }));
    for (const [connect, limit] of [["team", 200], ["team", 5], ["other", 200], ["nobody", 10]] as const) out.push(await read(readers, "recentConnectPeople", { connect, limit }));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["\"key\":\"process\"", "\"key\":\"watcher\"", "\"key\":\"waiting\"", "\"human_needed\"", "\"recommended\":true", "\"people\":[\"U1\"", "\"U0\""])
      assert.ok(said.includes(sign), sign);
    // Before their lookups are prepared: the jobs' by the old way, the checks' none.
    db.exec("DROP TABLE active_watch_jobs; DROP TABLE active_other_jobs; DROP INDEX decision_checks_lately");
    const before = await all(program);
    assert.deepEqual(before, await all(worker));
    assert.ok(JSON.stringify(before).includes("\"key\":\"watcher\""));
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

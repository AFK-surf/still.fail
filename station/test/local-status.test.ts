import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { test } from "node:test";
import { SETTLE_MS, TASKS_MOST, routeOf, statusOf, statusServer, type LocalStatus, type StatusInput } from "../src/api/status.ts";
import { Fibers } from "../src/ops/fibers.ts";
import { Store, WAITING_FOR_PEOPLE } from "../src/store/store.ts";
import { testClock } from "./hub-fakes.ts";

const DAY = 24 * 60 * 60_000;
const input = (o: Partial<StatusInput> = {}): StatusInput => ({
  version: "0.1.9", cloud: { origin: "https://cloud.example", workspace: "w1", workspace_name: "Lab", station: "st" }, reached: true,
  running: [], processes: new Map(), waiting: [], ...o,
});

test("the local status counts agents at work, warm and waiting, each once, and lists their tasks", () => {
  const s = statusOf(input({
    running: [{ key: "a", title: "build", since: 10 }, { key: "b", title: "lint", since: 20 }],
    processes: new Map([["a", "running"], ["b", "running"], ["c", "warm"], ["d", "running"]]),
    waiting: [{ key: "e", title: "deploy?", need: "may I deploy", endedAt: 5 }, { key: "a", title: "build", need: "old", endedAt: 1 }],
  }));
  assert.deepEqual(s.agents, { busy: 3, warm: 1, total: 5 });
  assert.equal(s.waiting, 1, "one at work again is not waiting");
  assert.equal(s.enrolled, true);
  assert.equal(s.workspaceName, "Lab");
  assert.deepEqual(s.tasks.map((t) => [t.session, t.state]), [["b", "working"], ["a", "working"], ["d", "working"], ["e", "waiting"]]);
  assert.equal(s.tasks.at(-1)?.need, "may I deploy");
});

test("a station in no workspace, or removed from it, is not enrolled", () => {
  assert.equal(statusOf(input({ cloud: null })).enrolled, false);
  assert.equal(statusOf(input({ cloud: { origin: "https://c", workspace: "w", removed_at: 3 } })).enrolled, false);
  assert.equal(statusOf(input({ cloud: { origin: "https://c", workspace: "" } })).enrolled, false);
});

test("the tasks said are at most TASKS_MOST, the counts of all", () => {
  const running = Array.from({ length: TASKS_MOST + 5 }, (_, n) => ({ key: `s${n}`, title: null, since: n }));
  const s = statusOf(input({ running }));
  assert.equal(s.tasks.length, TASKS_MOST);
  assert.equal(s.agents.busy, TASKS_MOST + 5);
});

test("the socket answers GET /v1/status, its stream and /healthz, nothing else", () => {
  assert.equal(routeOf("GET", "/v1/status"), "status");
  assert.equal(routeOf("GET", "/v1/status?watch=1"), "watch");
  assert.equal(routeOf("GET", "/v1/status?watch=0"), "status");
  assert.equal(routeOf("GET", "/healthz"), "health");
  assert.equal(routeOf("POST", "/v1/status"), null);
  assert.equal(routeOf("GET", "/admin/api/overview"), null);
});

test("the sessions waiting for a person: their latest turn asked, nobody answered, not archived, lately", () => {
  const time = testClock(), store = Store.open(":memory:", null, time.clock);
  try {
    const now = store.now();
    const session = (key: string, title: string) => {
      store.insertSession({ key, connect: "chat", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: now, lastActiveAt: now });
      store.setTitle(key, title);
    };
    const turn = (id: string, key: string, declared: string | null, need: string | null = null) => {
      store.startTurn(id, key, "message");
      store.endTurn(id, "completed", null, declared, null);
      if (need !== null) store.db.prepare("UPDATE turns SET need = ? WHERE id = ?").run(need, id);
    };
    session("asks", "deploy"); turn("t1", "asks", "all_done"); turn("t2", "asks", "need_human", "may I deploy");
    session("done", "done"); turn("t3", "done", "need_human"); turn("t4", "done", "all_done");
    session("answered", "answered"); turn("t5", "answered", "need_help");
    const thread = store.openThread("chat", "C", "x", null, null);
    store.db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'answered',NULL)").run(thread.id);
    session("archived", "archived"); turn("t6", "archived", "need_human"); store.setArchived("archived", true, "p");
    const got = store.waitingForPeople(now - DAY, 10);
    assert.deepEqual(got.map((w) => [w.key, w.need]), [["asks", "may I deploy"]]);
    assert.deepEqual(store.waitingForPeople(now + 1, 10), [], "a turn that ended before `since` is not looked at");
  } finally {
    store.close();
  }
});

test("the waiting sessions' read goes by the turns that ended lately", () => {
  const store = Store.open(":memory:");
  try {
    const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${WAITING_FOR_PEOPLE}`).all(0, 10).map((r: any) => String(r.detail));
    assert.ok(plan.some((d) => /SEARCH t USING INDEX turns_ended/.test(d)), plan.join("\n"));
    assert.ok(!plan.some((d) => /^SCAN (t|u|d|s)\b/.test(d)), plan.join("\n"));
  } finally {
    store.close();
  }
});

/// A request and a response, as statusServer's handler takes them, with what was written to it.
function exchange(url: string) {
  const req = Object.assign(new EventEmitter(), { method: "GET", url });
  const res = Object.assign(new EventEmitter(), {
    status: 0, lines: [] as string[], ended: false,
    writeHead(status: number) { this.status = status; return this; },
    write(text: string) { this.lines.push(text); return true; },
    end(text?: string) { if (text !== undefined) this.lines.push(text); this.ended = true; return this; },
  });
  return { req, res };
}

test("a watcher is told the status now, then once a burst of changes settles, and only when it changed", async () => {
  const time = testClock(), fibers = new Fibers("status-test", time.clock);
  let busy = 0;
  let listener = () => {};
  const now = (): LocalStatus => statusOf(input({ running: Array.from({ length: busy }, (_, n) => ({ key: `s${n}`, title: null, since: n })) }));
  const s = statusServer(now, (f) => { listener = f; return () => { listener = () => {}; }; }, fibers);
  try {
    const one = exchange("/v1/status");
    s.server.emit("request", one.req, one.res);
    assert.equal(one.res.status, 200);
    assert.equal(one.res.ended, true);
    assert.equal(JSON.parse(one.res.lines[0]).agents.busy, 0);

    const w = exchange("/v1/status?watch=1");
    s.server.emit("request", w.req, w.res);
    assert.equal(w.res.lines.length, 1);
    busy = 1; listener(); busy = 2; listener(); listener();
    await time.adjust(SETTLE_MS - 1);
    assert.equal(w.res.lines.length, 1, "nothing before the burst settles");
    await time.adjust(1);
    assert.equal(w.res.lines.length, 2);
    assert.equal(JSON.parse(w.res.lines[1]).agents.busy, 2);
    listener();
    await time.adjust(SETTLE_MS);
    assert.equal(w.res.lines.length, 2, "the same status is not said again");

    const gone = exchange("/nothing");
    s.server.emit("request", gone.req, gone.res);
    assert.equal(gone.res.status, 404);
  } finally {
    s.close();
    await fibers.close();
  }
});

import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { working } from "../src/ops/awake.ts";
import { Hub } from "../src/sessions/hub.ts";
import { autoArchive } from "../src/sessions/lifecycle.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

function session(store: Store, key: string) {
  store.insertSession({ key, connect: "cl", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
}

function deliveries(store: Store, key: string) {
  const insert = store.db.prepare("INSERT INTO deliveries (thread, n, session) VALUES (999, ?, ?)");
  store.db.exec("BEGIN");
  for (let n = 1; n <= 2_000; n++) insert.run(n, key);
  store.db.exec("COMMIT");
}

test("the awake check needs the latest turns, not a count of pending messages", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "waiting");
    store.startTurn("wait", "waiting", "input");
    store.endTurn("wait", "completed", null, "waiting", 600);
    deliveries(store, "waiting");
    store.statsOf = () => { throw new Error("counted pending deliveries"); };
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && (table === "deliveries" || table === "letter_deliveries") ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      assert.equal(working(store, store.now()), true, "an unexpired wait keeps the machine awake");
      assert.equal(working(store, store.now() + 3_600_000), false, "an expired wait does not");
    } finally { store.db.setAuthorizer(null); }
  } finally { store.close(); }
});

test("latest turns keep same-time ordering, empty sessions and missing sessions distinct", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "s");
    session(store, "empty");
    store.startTurn("first", "s", "input");
    store.endTurn("first", "completed", null, "final", null);
    store.startTurn("second", "s", "input");
    store.endTurn("second", "completed", null, "waiting", 10);
    store.db.prepare("UPDATE turns SET started_at = 1 WHERE session_key = 's'").run();
    const turns = store.lastTurnsOf(["s", "empty", "missing", "s"]);
    assert.deepEqual([...turns.keys()], ["s", "empty"]);
    assert.deepEqual(turns.get("s"), store.lastTurn("s"));
    assert.equal(turns.get("s")?.declared, "waiting");
    assert.equal(turns.get("empty"), null);
  } finally { store.close(); }
});

test("a job whose session is missing uses its own start time, even if an old turn remains", () => {
  const store = Store.open(":memory:");
  try {
    const now = store.now();
    store.db.prepare("INSERT INTO turns (id, session_key, kind, started_at, ended_at, outcome, declared) VALUES ('old', 'gone', 'input', ?, ?, 'completed', 'final')").run(now - 20_000_000, now - 19_000_000);
    store.insertJob({ id: "job", sessionKey: "gone", name: "work", command: "true", cwd: "/", port: null, token: "job", state: "running", pgid: null, exitCode: null, startedAt: now, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
    store.statsOf = () => { throw new Error("counted pending deliveries"); };
    assert.equal(working(store, now), true);
  } finally { store.close(); }
});

test("restart recovery reads each latest turn without counting pending messages", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "waiting");
    session(store, "refill");
    store.startTurn("wait", "waiting", "input");
    store.endTurn("wait", "completed", null, "waiting", 600);
    store.startTurn("limited", "refill", "input");
    store.endTurn("limited", "failed", "rate_limit:quota", null, null);
    deliveries(store, "waiting");
    store.statsOf = () => { throw new Error("counted pending deliveries"); };
    const called: string[] = [];
    const hub = {
      store, adopted: new Set(), online: () => true,
      actor: (row: { key: string }) => ({
        recover: async () => { called.push(`recover:${row.key}`); },
        kick: async () => { called.push(`kick:${row.key}`); },
        takeWait: async () => { called.push(`wait:${row.key}`); },
        takeRefill: async () => { called.push(`refill:${row.key}`); },
      }),
    };
    Hub.prototype.recover.call(hub as unknown as Hub);
    assert.deepEqual(called.sort(), ["kick:waiting", "refill:refill", "wait:waiting"]);
  } finally { store.close(); }
});

test("idle archiving checks for a pending message without counting the queue", async () => {
  const r = new Rig();
  const stats = r.store.statsOf;
  const db = r.store.db;
  try {
    session(r.store, "idle");
    deliveries(r.store, "idle");
    r.store.db.prepare("INSERT INTO letter_deliveries (thread, n, session) VALUES (999, 1, 'idle')").run();
    assert.equal(r.store.statsOf(["idle"]).get("idle")?.pending, 2_001, "callers asking for the exact count still get it");
    let examined = 0;
    db.function("archive_examined", (n) => { examined++; return n; });
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          /(?:letter_)?deliveries_pending/.test(sql)
            ? sql.replace(/((?:\w+\.)?delivered_at IS NULL)/g, (where) => {
                const alias = /\w+\./.exec(where)?.[0] ?? "";
                return `${where} AND archive_examined(${alias}n) IS NOT NULL`;
              }) : sql,
        );
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(r.store, "db", { value: traced, configurable: true });
    r.store.statsOf = () => { throw new Error("counted pending deliveries"); };
    const later = Date.now() + 3 * 86_400_000;
    autoArchive(r.hub, later);
    assert.equal(r.session("idle").archivedAt, null, "an orphaned message delivery still prevents archiving");
    assert.equal(examined, 1, "the first pending message is enough, even when there are 2,000");
    r.store.db.prepare("DELETE FROM deliveries WHERE session = 'idle'").run();
    examined = 0;
    autoArchive(r.hub, later);
    assert.equal(r.session("idle").archivedAt, null, "an orphaned letter also prevents archiving");
    assert.equal(examined, 1);
    r.store.db.prepare("DELETE FROM letter_deliveries WHERE session = 'idle'").run();
    autoArchive(r.hub, later);
    assert.notEqual(r.session("idle").archivedAt, null, "the idle session is archived when nothing remains");
  } finally {
    r.store.statsOf = stats;
    Object.defineProperty(r.store, "db", { value: db, configurable: true });
    await r.close();
  }
});

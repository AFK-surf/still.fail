import assert from "node:assert/strict";
import { homedir } from "node:os";
import { test } from "node:test";
import { ResourceWatch } from "../src/resources/watch.ts";
import { SessionDirectoryBuilder } from "../src/sessions/session-directory-builder.ts";
import { SESSION_DIR_ARGUMENTS } from "../src/store/session-directory.ts";
import { LIVE_SESSIONS, Store } from "../src/store/store.ts";

test("a resources check does not read unrelated session directories", async () => {
  const counts: { steady: number; changed: number }[] = [];
  for (const unrelated of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    let observed = false, now = 0;
    const read = new Set<string>();
    db.function("resource_place_seen", (key) => { if (observed && String(key).startsWith("other:")) read.add(String(key)); return 1; });
    const proxy = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === LIVE_SESSIONS
        ? sql.replace("archived_at IS NULL", "archived_at IS NULL AND resource_place_seen(key)")
        : sql === SESSION_DIR_ARGUMENTS ? sql.replaceAll("s.archived_at IS NULL", "resource_place_seen(s.key) AND s.archived_at IS NULL")
        : sql === "SELECT workspace FROM sessions WHERE key = ?" ? sql.replace("WHERE key = ?", "WHERE resource_place_seen(key) AND key = ?") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const put = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
      VALUES (?,'connected','thread','codex','default',?,?,0,0)`);
    put.run("mine", "/sessions/mine/workspace", "mine-token");
    for (let i = 0; i < unrelated; i++) put.run(`other:${i}`, `/sessions/other-${i}/workspace`, `token-${i}`);
    Object.defineProperty(store, "db", { value: proxy });
    const builder = new SessionDirectoryBuilder(store, Promise.resolve());
    const watch = new ResourceWatch({
      clock: { currentTimeMillisUnsafe: () => now } as never,
      table: async () => [
        { pid: 1, ppid: 0, pgid: 1, bytes: 0, command: "launchd" },
        { pid: 70, ppid: 1, pgid: 70, bytes: 0, command: "sh" },
      ],
      args: async () => new Map([[70, "sh /sessions/mine/workspace/run.sh"]]),
      places: () => store.liveSessions().flatMap((s) =>
        s.workspace && s.workspace !== "/" && s.workspace !== homedir() ? [{ dir: s.workspace, session: s.key }] : []),
      placesInArguments: (lines) => builder.findArguments(lines, homedir()),
      usage: (pids) => pids.map(() => ({ cpuNs: now * 1e6, footprint: 1 })),
      runners: async () => [], jobs: () => [], isApp: () => false, self: [],
    });
    try {
      await watch.look();
      await builder.settled();
      observed = true;
      now += 5000;
      await watch.look();
      assert.deepEqual(await watch.end(70, "mine", () => {}), { name: "sh" });
      await assert.rejects(watch.end(70, "other", () => {}), /not a chat's/);
      observed = false;
      assert.equal(watch.snapshot().groups[0]?.key, "chat:mine");
      const steady = read.size;
      put.run("other:new", "/sessions/new/workspace", "new-token");
      read.clear();
      observed = true;
      now += 5000;
      await watch.look();
      observed = false;
      counts.push({ steady, changed: read.size });
    } finally { await watch.close(); await builder.close(); store.close(); }
  }
  assert.deepEqual(counts, [{ steady: 0, changed: 1 }, { steady: 0, changed: 1 }]);
});

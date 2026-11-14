import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { liveMemory } from "../src/jobs/memory.ts";
import type { Jobs } from "../src/jobs/jobs.ts";
import { platform } from "../src/platform/index.ts";
import { SessionDirectoryBuilder } from "../src/sessions/session-directory-builder.ts";
import { sessionDirectoryCandidate } from "../src/store/session-directory.ts";
import { LIVE_SESSIONS, Store } from "../src/store/store.ts";

test("rechecking a shared runner's command directory does not reread unrelated sessions", async () => {
  const counts: { steady: number; changed: number }[] = [];
  const original = { pressure: platform.memoryPressure, table: platform.processTable, cwds: platform.cwds };
  const data = mkdtempSync(join(tmpdir(), "memory-dirs-"));
  let size = 1024 ** 4;
  try {
    mkdirSync(join(data, "run", "runners"), { recursive: true });
    writeFileSync(join(data, "run", "runners", "codex-shared.json"), JSON.stringify({
      id: "codex-shared", runner: process.pid, pid: 1010100, pgid: 1010100,
      startedAt: 0, program: "codex", args: [], socket: "",
    }));
    platform.memoryPressure = async () => "normal";
    platform.processTable = async () => [
      { pid: 1010100, ppid: 1, pgid: 1010100, bytes: 0, command: "codex" },
      { pid: 1010101, ppid: 1010100, pgid: 1010101, bytes: size, command: "build" },
    ];
    platform.cwds = async () => new Map([[1010101, "/sessions/target/workspace/sub"]]);
    for (const unrelated of [40, 400]) {
      size = 1024 ** 4;
      const store = Store.open(":memory:"), db = store.db;
      let seen = 0, observing = false;
      db.function("memory_dir_seen", (key) => { if (observing && String(key).startsWith("other:")) seen++; return 1; });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          sql === LIVE_SESSIONS ? sql.replace("archived_at IS NULL", "memory_dir_seen(key) AND archived_at IS NULL")
            : sql === sessionDirectoryCandidate(true) || sql === sessionDirectoryCandidate(false)
              ? sql.replace("WHERE d.root = ?", "WHERE d.root = ? AND memory_dir_seen(s.key)")
              : sql === "SELECT workspace, cwd FROM sessions WHERE key = ?"
                ? sql.replace("WHERE key = ?", "WHERE memory_dir_seen(key) AND key = ?") : sql);
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      const told: string[] = [];
      try {
        const put = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
          VALUES (?,'connected','thread','codex','default',?,?,0,0)`);
        put.run("target", "/sessions/target/workspace", "target-token");
        for (let i = 0; i < unrelated; i++) put.run(`other:${i}`, `/sessions/other-${i}/workspace`, `token-${i}`);
        Object.defineProperty(store, "db", { value: observed });
        const builder = new SessionDirectoryBuilder(store, Promise.resolve());
        const watch = liveMemory({ data, store, jobs: { memorySeen: () => {} } as unknown as Jobs, runnerNames: () => new Map(), directory: (dir) => builder.find(dir), notify: (session) => told.push(session) });
        try {
          await watch.look();
          assert.deepEqual(told, ["target"]);
          await builder.settled();
          size *= 2;
          observing = true;
          await watch.look();
          observing = false;
          const steady = seen;
          put.run("other:new", "/sessions/new/workspace", "new-token");
          seen = 0;
          size *= 2;
          observing = true;
          await watch.look();
          observing = false;
          counts.push({ steady, changed: seen });
          await builder.settled();
        } finally { await watch.close(); await builder.close(); }
      } finally { store.close(); }
    }
  } finally {
    platform.memoryPressure = original.pressure;
    platform.processTable = original.table;
    platform.cwds = original.cwds;
    rmSync(data, { recursive: true, force: true });
  }
  assert.deepEqual(counts, [{ steady: 0, changed: 1 }, { steady: 0, changed: 1 }]);
});

test("a live directory takes precedence while the old archived answer remains cached", async () => {
  const original = { pressure: platform.memoryPressure, table: platform.processTable, cwds: platform.cwds };
  const data = mkdtempSync(join(tmpdir(), "memory-dirs-cache-"));
  const store = Store.open(":memory:"), builder = new SessionDirectoryBuilder(store, Promise.resolve());
  const told: string[] = [];
  let size = 1024 ** 4;
  try {
    mkdirSync(join(data, "run", "runners"), { recursive: true });
    writeFileSync(join(data, "run", "runners", "codex-shared.json"), JSON.stringify({
      id: "codex-shared", runner: process.pid, pid: 1010100, pgid: 1010100,
      startedAt: 0, program: "codex", args: [], socket: "",
    }));
    platform.memoryPressure = async () => "normal";
    platform.processTable = async () => [
      { pid: 1010100, ppid: 1, pgid: 1010100, bytes: 0, command: "codex" },
      { pid: 1010101, ppid: 1010100, pgid: 1010101, bytes: size, command: "build" },
    ];
    platform.cwds = async () => new Map([[1010101, "/same/sub"]]);
    const put = store.db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,archived_at)
      VALUES (?,'connected','thread','codex','default','/same',?,0,?,?)`);
    put.run("old", "old", 1, 1);
    const watch = liveMemory({ data, store, jobs: { memorySeen: () => {} } as unknown as Jobs, runnerNames: () => new Map(), directory: (dir) => builder.find(dir), notify: (session) => told.push(session) });
    try {
      await watch.look();
      await builder.settled();
      store.db.prepare("DELETE FROM sessions WHERE key = 'old'").run();
      put.run("new-archived", "new-archived", 2, 1);
      size *= 2;
      await watch.look(); // The old all-session answer stays cached, as it did before the index.
      put.run("live", "live", 3, null);
      size *= 2;
      await watch.look(); // A live match always wins over that cached archived answer.
      assert.deepEqual(told, ["old", "old", "live"]);
      await builder.settled();
    } finally { await watch.close(); }
  } finally {
    await builder.close();
    store.close();
    platform.memoryPressure = original.pressure;
    platform.processTable = original.table;
    platform.cwds = original.cwds;
    rmSync(data, { recursive: true, force: true });
  }
});

import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import type { LiveHub } from "../src/sessions/live.ts";
import type { UsageCounter } from "../src/usage/counter.ts";
import { MinuteReader } from "../src/usage/minute-reader.ts";
import { keepCounted, keepUsage } from "../src/usage/module.ts";

test("incomplete statistics stay unavailable without a background history writer", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-no-fill-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  let reader: MinuteReader | null = null;
  try {
    store.insertSession({ key: "old", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "old", createdAt: 1, lastActiveAt: 1 });
    store.recordUsage("/old", { session: "old", offset: 1, model: null }, "claude", [[{
      id: "old-call", at: 1, model: "m", subagent: false, fast: false, input: 1, cacheRead: 0, cacheWrite: 0,
      cacheWriteLong: 0, output: 1, calls: 1, context: 1, window: 100,
    }, { turn: null, thread: null, person: null, profile: "cc" }]]);
    store.db.exec(`UPDATE usage_detail_all SET after_session = NULL, done = 0;
      UPDATE usage_chat_progress SET stage = 0, done = 0;
      UPDATE usage_minute_all SET after_session = NULL, done = 0;
      UPDATE remote_run_progress SET after_seq = NULL, done = 0`);
    const progress = (table: string) => store.db.prepare(`SELECT * FROM ${table}`).get();
    const tables = ["usage_detail_all", "usage_chat_progress", "usage_minute_all", "remote_run_progress"];
    const before = tables.map(progress);
    reader = new MinuteReader(path);
    await assert.rejects(reader.ready(null), /minute.*unavailable/i);
    await assert.rejects(reader.readyDetail(null), /detail.*unavailable/i);
    await assert.rejects(reader.readyChats(null), /chat.*unavailable/i);
    await assert.rejects(reader.readyRemote(), /remote.*unavailable/i);
    assert.deepEqual(tables.map(progress), before);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage").get() as { n: number }).n, 1,
      "the original call remains intact");
  } finally {
    if (reader !== null) await reader.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("startup leaves saved session summaries alone and live reads use those summaries", () => {
  const store = Store.open(":memory:");
  let of: ((key: string) => unknown) | undefined;
  const told: unknown[] = [];
  const live = {
    countWith(count: { of: (key: string) => unknown }) { of = count.of; },
    usageCounted() { told.push(of!("s")); },
  } as unknown as LiveHub;
  let stop = () => {};
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", createdAt: 1, lastActiveAt: 1 });
    store.recordUsage("/s", { session: "s", offset: 1, model: null }, "claude", [[{
      id: "call", at: 1, model: "m", subagent: false, fast: false, input: 2, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 2, window: 100,
    }, { turn: null, thread: null, person: null, profile: "cc" }]]);
    keepUsage(store, "s", true);
    const saved = store.sessionUsage("s");
    store.sessionKeys = () => { throw new Error("startup enumerated sessions"); };
    stop = keepCounted(store, live, {} as UsageCounter);
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && (table === "usage" || table === "usage_main_calls")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.deepEqual(of!("s"), saved); }
    finally { store.db.setAuthorizer(null); }
    store.db.prepare("UPDATE usage SET output = 9 WHERE id = 'call'").run();
    store.usageChanged(["s"]);
    assert.equal((told.at(-1) as { outputTokens: number }).outputTokens, 9,
      "a change is told after its new summary is saved");
  } finally { stop(); store.close(); }
});

test("a partially built old context index is unavailable without scanning its calls", () => {
  const store = Store.open(":memory:");
  try {
    store.db.exec("UPDATE usage_compaction_backfill SET done = 0 WHERE id = 1");
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.deepEqual(store.lastContexts("old", 5), []); }
    finally { store.db.setAuthorizer(null); }
  } finally { store.close(); }
});

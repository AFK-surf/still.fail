import assert from "node:assert/strict";
import { test } from "node:test";
import { XSHARE_IDLE_MS } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";
import { testClock } from "./hub-fakes.ts";

test("reconciling shares and their next expiry does not reread long-lapsed chats", () => {
  const counts: { live: number; expiry: number; workspaces: number }[] = [];
  for (const oldShares of [40, 400]) {
    const clock = testClock(), store = Store.open(":memory:", null, clock.clock), db = store.db;
    try {
      const now = store.now(), put = db.prepare("INSERT INTO chat_shares (session, shared, write, by, at) VALUES (?, ?, 0, 'a', 0)");
      const shared = (workspace: string, used: number) => JSON.stringify([{ workspace, name: workspace, used }]);
      for (let i = 0; i < oldShares; i++) put.run(`old:${i}`, shared("old-workspace", now - XSHARE_IDLE_MS - 10_000));
      put.run("due", shared("due-workspace", now - XSHARE_IDLE_MS - 100));
      put.run("live", shared("live-workspace", now - 1_000));
      let phase: "none" | "live" | "expiry" | "workspaces" = "none";
      const seen = { live: 0, expiry: 0, workspaces: 0 };
      db.function("share_seen", (session) => { if (phase !== "none" && String(session).startsWith("old:")) seen[phase]++; return 1; });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(sql === "SELECT * FROM chat_shares"
          ? `${sql} WHERE share_seen(session)` : sql);
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      Object.defineProperty(store, "db", { value: observed });
      // These same reads happen when sharing starts, when a title changes, and again on a retry.
      store.chatShares(); store.lapseChatShares(now - 200); store.lapsedShareWorkspaces();
      phase = "live";
      assert.deepEqual([...store.chatShares().keys()], ["live"]);
      phase = "expiry";
      assert.equal(store.lapseChatShares(now - 200), now - 1_000 + XSHARE_IDLE_MS);
      phase = "workspaces";
      assert.deepEqual([...store.lapsedShareWorkspaces()].sort(), ["due-workspace", "old-workspace"]);
      phase = "none";
      counts.push(seen);
    } finally { store.close(); }
  }
  assert.deepEqual(counts, [
    { live: 0, expiry: 0, workspaces: 0 },
    { live: 0, expiry: 0, workspaces: 0 },
  ]);
});

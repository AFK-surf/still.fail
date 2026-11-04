import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { makeStore, openStore } from "../src/read/store.ts";
import { historyHits } from "../src/search/sources.ts";
import { Store } from "../src/store/store.ts";

function fixture(keys: string[]) {
  const data = mkdtempSync(join(tmpdir(), "history-visibility-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const home = join(data, "profile");
  const dir = join(home, "projects", "w");
  mkdirSync(dir, { recursive: true });
  for (const [index, key] of keys.entries()) {
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
      token: `token-${key}`, createdAt: 100 - index, lastActiveAt: 100 - index, ws: "mine" });
    store.setRuntimeSessionId(key, key);
    writeFileSync(join(dir, `${key}.jsonl`), `${JSON.stringify({ type: "assistant", message: { content: [{ type: "text", text: `needle ${key}` }] } })}\n`);
  }
  const read = openStore(data);
  return { data, store, read, profiles: [{ id: "cc", home, runtime: "claude" }],
    close: () => { read.db.close(); store.close(); rmSync(data, { recursive: true, force: true }); } };
}

test("a history search stops if a session moves before its history is read", async () => {
  const f = fixture(["moving"]);
  try {
    setImmediate(() => f.store.setSessionsWs("mine", "other"));
    await assert.rejects(historyHits(f.read, f.profiles, ["needle"],
      { workspace: "mine", home: false, scopes: [] }, { limit: 5, offset: 0, ms: 10_000, now: () => 0 })
      .then((result) => assert.fail(`returned ${JSON.stringify(result)}`)), /session changed while searching/);
  } finally { f.close(); }
});

test("a history search stops if a session is deleted before its history is read", async () => {
  const f = fixture(["moving"]);
  try {
    setImmediate(() => f.store.deleteSession("moving"));
    await assert.rejects(historyHits(f.read, f.profiles, ["needle"],
      { workspace: "mine", home: false, scopes: [] }, { limit: 5, offset: 0, ms: 10_000, now: () => 0 }), /session changed while searching/);
  } finally { f.close(); }
});

test("a timed-out history search checks the session it was about to read", async () => {
  const f = fixture(["moving"]);
  try {
    let moved = false;
    setImmediate(() => { f.store.setSessionsWs("mine", "other"); moved = true; });
    await assert.rejects(historyHits(f.read, f.profiles, ["needle"],
      { workspace: "mine", home: false, scopes: [] }, { limit: 5, offset: 0, ms: 10, now: () => moved ? 100 : 0 }), /session changed while searching/);
  } finally { f.close(); }
});

for (const timeout of [false, true]) test(`a ${timeout ? "timed-out" : "completed"} history search does not return a hit whose session moved while another was searched`, async () => {
  const f = fixture(["moving", "other"]);
  try {
    let moved = false;
    let scheduled = false;
    const db = f.read.db;
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (!scheduled && sql.startsWith("SELECT t.* FROM thread_sessions ts JOIN threads t")) {
            scheduled = true;
            setImmediate(() => { f.store.db.prepare("UPDATE sessions SET ws='other' WHERE key='moving'").run(); moved = true; });
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    await assert.rejects(historyHits(makeStore(traced, f.data), f.profiles, ["needle"],
      { workspace: "mine", home: false, scopes: [] }, { limit: 5, offset: 0, ms: 10, now: () => moved && timeout ? 100 : 0 })
      .then((result) => assert.fail(`returned ${JSON.stringify(result)}`)), /session changed while searching/);
  } finally { f.close(); }
});

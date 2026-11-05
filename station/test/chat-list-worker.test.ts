import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { RecentChatBuilder } from "../src/read/recent-chat-builder.ts";
import { recentChatIds } from "../src/store/chat-list.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
import { Store } from "../src/store/store.ts";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "recent-chat-worker-")), path = join(dir, "station.db");
  const store = Store.open(path);
  store.insertSession({ key: "here", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
    token: "here", createdAt: 1, lastActiveAt: 1, ws: "here" });
  store.openThreadOf("ember", "CHAT", "chat", "Chat", null, "here");
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

test("recent chat requests wait for handover and share preparation when one leaves", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>();
  const builder = new RecentChatBuilder(f.path, { previousGone: previous.promise });
  const controller = new AbortController(), scope = { ws: "here", home: "home" };
  try {
    const abandoned = builder.readyScope(scope, controller.signal), kept = builder.readyScope(scope);
    assert.equal(f.store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'recent_scope_tracked'").get(), undefined);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    await kept;
    assert.deepEqual(readPreparedRecentWorkspace(f.store.db, "here", 5), recentChatIds(f.store.db, "here", "home", 5));
  } finally { previous.resolve(); await builder.close(); f.close(); }
});

test("a short requested scope can finish while another has many sessions to prepare", async () => {
  const f = fixture(), builder = new RecentChatBuilder(f.path), controller = new AbortController();
  try {
    f.store.db.exec("BEGIN");
    for (let i = 0; i < 300; i++) {
      const key = `busy-${i}`;
      f.store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "busy" });
    }
    f.store.db.exec("COMMIT");
    const abandoned = builder.readyScope({ ws: "busy", home: "home" }, controller.signal);
    const rejected = assert.rejects(abandoned, /read cancelled/);
    await builder.readyScope({ ws: "here", home: "home" });
    assert.deepEqual(readPreparedRecentWorkspace(f.store.db, "here", 5), recentChatIds(f.store.db, "here", "home", 5));
    assert.equal(f.store.db.prepare("SELECT scan_done FROM recent_scope_tracked WHERE kind = 1 AND ws = 'busy'").get()?.scan_done, 0);
    controller.abort();
    await rejected;
  } finally { controller.abort(); await builder.close(); f.close(); }
});

test("a stopped recent chat worker resumes its pending request", async () => {
  const f = fixture(), file = join(f.dir, "worker.mjs"), marker = join(f.dir, "exited");
  const real = new URL("../src/read/recent-chat-worker.ts", import.meta.url).href;
  writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  const builder = new RecentChatBuilder(f.path, {}, pathToFileURL(file));
  try {
    await builder.readyScope({ ws: "here", home: "home" });
    assert.ok(existsSync(marker));
    assert.deepEqual(readPreparedRecentWorkspace(f.store.db, "here", 5), recentChatIds(f.store.db, "here", "home", 5));
  } finally { await builder.close(); f.close(); }
});

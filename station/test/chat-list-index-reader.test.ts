import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "recent-chat-reader-"));
  const store = Store.open(join(dir, "stillfail.db"));
  for (const [key, ws] of [["here", "here"], ["away", "away"]] as const)
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: key, createdAt: 1, lastActiveAt: 1, ws });
  const named = store.openThreadOf("ember", "EMBER", "named", "Named", null, "here").id;
  const shared = store.openThread("ember", "EMBER", "shared", "Shared", null).id;
  store.joinThread(shared, "here", "ember");
  store.joinThread(shared, "missing", "ember");
  const orphan = store.openThread("ember", "EMBER", "orphan", "Orphan", null).id;
  store.openThreadOf("ember", "EMBER", "away", "Away", null, "away");
  return { dir, store, named, shared, orphan, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

test("a recent list releases its reader while it waits for handover and shares the requested build", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const args = { ws: "here", home: "home", limit: 5 };
    let answered = false;
    const one = readers.read("recentChatList", args, "en").then((text) => { answered = true; return text; });
    const two = readers.read("recentChatList", args, "en");
    const empty = JSON.parse(await readers.read("recentChatList", { ...args, limit: 0 }, "en"));
    assert.deepEqual(empty, { threads: [], sessions: [], total: 0 });
    assert.equal(answered, false, "the list is not returned before the previous station hands over");
    assert.equal(f.store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'recent_scope_tracked'").get(), undefined);
    previous.resolve();
    const [first, second] = await Promise.all([one, two]);
    assert.equal(first, second);
    assert.deepEqual(JSON.parse(first), JSON.parse(JSON.stringify(f.store.recentChatList("here", "home", 5))));
  } finally { readers.close(); previous.resolve(); f.close(); }
});

test("an abandoned recent list does not start preparation after handover", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), controller = new AbortController();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const pending = readers.read("recentChatList", { ws: "here", home: "home", limit: 5 }, "en", { signal: controller.signal });
    await readers.read("recentChatList", { ws: "here", home: "home", limit: 0 }, "en");
    controller.abort();
    await assert.rejects(pending, /read cancelled/);
    previous.resolve();
    await Promise.resolve();
    assert.equal(f.store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'recent_scope_tracked'").get(), undefined);
  } finally { readers.close(); previous.resolve(); f.close(); }
});

test("recent readers return exact global, workspace and home pages after changes", async () => {
  const f = fixture(), readers = new Readers(f.dir, 1);
  try {
    const scopes = [{ ws: null, home: "home" }, { ws: "here", home: "home" }, { ws: "home", home: "home" }];
    const check = async () => {
      for (const scope of scopes) {
        const actual = JSON.parse(await readers.read("recentChatList", { ...scope, limit: 5 }, "en"));
        const expected = JSON.parse(JSON.stringify(f.store.recentChatList(scope.ws, scope.home, 5)));
        assert.deepEqual(actual, expected);
      }
    };
    await check();
    f.store.db.prepare("UPDATE threads SET home = 'away' WHERE id = ?").run(f.named);
    f.store.db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'missing'").run(f.shared);
    f.store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',100)").run(f.orphan);
    await check();
  } finally { readers.close(); f.close(); }
});

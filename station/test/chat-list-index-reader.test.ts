import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import type { Hub } from "../src/sessions/hub.ts";
import { Store } from "../src/store/store.ts";
import { chatTools } from "../src/tools/chat.ts";
import { openAgentsDoor } from "../src/tools/http.ts";
import { McpEndpoint } from "../src/tools/mcp.ts";
import { installRecentChatIndex } from "../src/store/chat-list-index.ts";

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

test("a recent reader reports an incompatible index instead of retrying preparation", async () => {
  const f = fixture();
  installRecentChatIndex(f.store.db);
  f.store.db.prepare("UPDATE recent_chat_versions SET version = 2 WHERE part = 'global'").run();
  const readers = new Readers(f.dir, 1);
  try {
    await assert.rejects(readers.read("recentChatList", { ws: null, home: "home", limit: 5 }, "en"), /recent chat.*version/i);
  } finally { readers.close(); f.close(); }
});

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

test("a disconnected chat_list stops its requested preparation before handover", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), called = Promise.withResolvers<void>();
  const cancelled = Promise.withResolvers<void>(), controller = new AbortController();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  const hub = { store: f.store, workspaces: () => ["here"], wsOf: (key: string | null) => key === null ? "home" : "here",
    recentChatList: async (ws: string | null, home: string | null, limit: number, signal?: AbortSignal) => {
      signal?.addEventListener("abort", () => cancelled.resolve(), { once: true });
      called.resolve();
      return JSON.parse(await readers.read("recentChatList", { ws, home, limit }, "en", { signal }));
    },
  } as unknown as Hub;
  const endpoint = new McpEndpoint(() => "here", chatTools(hub));
  const door = await openAgentsDoor({ port: 0 }, endpoint, () => ({ status: 404, body: undefined }));
  try {
    const call = fetch(door.url, { method: "POST", headers: { authorization: "Bearer token", "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "chat_list", arguments: { limit: 5 } } }),
      signal: controller.signal });
    const rejected = assert.rejects(call);
    await called.promise;
    await readers.read("recentChatList", { ws: "here", home: "home", limit: 0 }, "en");
    assert.equal(f.store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'recent_scope_tracked'").get(), undefined);
    controller.abort();
    await rejected;
    await cancelled.promise;
    previous.resolve();
    await readers.read("recentChatList", { ws: "here", home: "home", limit: 0 }, "en");
    assert.equal(f.store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'recent_scope_tracked'").get(), undefined);
  } finally {
    controller.abort(); previous.resolve();
    await door.close(); readers.close(); f.close();
  }
});

test("one disconnected chat_list does not cancel another request for the same page", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), firstCalled = Promise.withResolvers<void>(), bothCalled = Promise.withResolvers<void>();
  const stopped = Promise.withResolvers<void>(), controller = new AbortController();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  let calls = 0;
  const hub = { store: f.store, workspaces: () => ["here"], wsOf: (key: string | null) => key === null ? "home" : "here",
    outsideChats: () => [], link: () => undefined,
    recentChatList: async (ws: string | null, home: string | null, limit: number, signal?: AbortSignal) => {
      if (++calls === 1) { signal?.addEventListener("abort", () => stopped.resolve(), { once: true }); firstCalled.resolve(); }
      if (calls === 2) bothCalled.resolve();
      return JSON.parse(await readers.read("recentChatList", { ws, home, limit }, "en", { signal }));
    },
  } as unknown as Hub;
  const door = await openAgentsDoor({ port: 0 }, new McpEndpoint(() => "here", chatTools(hub)), () => ({ status: 404, body: undefined }));
  const options = { method: "POST", headers: { authorization: "Bearer token", "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "chat_list", arguments: { limit: 5 } } }) };
  try {
    const abandoned = fetch(door.url, { ...options, signal: controller.signal });
    const rejected = assert.rejects(abandoned);
    await firstCalled.promise;
    const kept = fetch(door.url, options);
    await bothCalled.promise;
    await readers.read("recentChatList", { ws: "here", home: "home", limit: 0 }, "en");
    controller.abort();
    await rejected;
    await stopped.promise;
    previous.resolve();
    const answer = await (await kept).json() as { result: { content: { text: string }[]; isError?: boolean } };
    assert.equal(answer.result.isError, undefined);
    assert.match(answer.result.content[0]!.text, /Named/);
  } finally {
    controller.abort(); previous.resolve();
    await door.close(); readers.close(); f.close();
  }
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

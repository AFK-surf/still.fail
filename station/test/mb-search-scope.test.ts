// The MoonBit builder of the search's candidate scopes (station/mb, src/searchscope) installs them and prepares their
// old state as `SearchScopePreparation` does: on the same store, changed the same way between steps (sessions moving
// workspace, memberships added and removed, chats gone, keys with a NUL or not plain ASCII, members of no session), the
// same answers step by step and the same tables and schema.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { SearchScopeBuilder } from "../src/search/scope-builder.ts";
import { SearchScopePreparation } from "../src/search/scope-prepare.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A store from before the scopes: 300 chats, 200 sessions in three workspaces and none, members of each.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-search-scope-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive"));
  const key = (i: number) => i % 37 === 0 ? `with\u0000nul-${i}` : i % 41 === 0 ? `ключ-${i}` : `session-${i}`;
  for (let i = 0; i < 200; i++)
    store.insertSession({ key: key(i), connect: "ember", runtime: "claude", profile: "cc", workspace: "/work", token: `t-${i}`,
      createdAt: i, lastActiveAt: i, ws: i % 4 === 3 ? null : i % 29 === 0 ? `wś-${i % 3}` : `ws-${i % 3}` } as Parameters<Store["insertSession"]>[0]);
  const threads: number[] = [];
  for (let i = 0; i < 300; i++) threads.push(store.openThread("ember", "CHAT", `t-${i}`, `T${i}`, null).id);
  for (let i = 0; i < 300; i++) {
    if (i % 9 === 0) continue;
    for (let j = 0; j < 1 + (i % 3); j++) store.joinThread(threads[i]!, j === 2 && i % 5 === 0 ? `gone-${i}` : key((i * 7 + j * 13) % 200), "ember");
  }
  return { dir, path, store, threads, key, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function tables(store: Store): string {
  const all = (sql: string) => JSON.stringify(store.db.prepare(sql).all());
  return [
    all("SELECT thread, hex(session) AS session, kind, ws FROM search_scope_members ORDER BY thread, session"),
    all("SELECT kind, ws, thread, refs FROM search_scope_threads ORDER BY kind, ws, thread"),
    all("SELECT thread FROM search_scope_orphans ORDER BY thread"),
    all("SELECT thread, hex(session) AS session FROM search_scope_members_dirty ORDER BY thread, session"),
    all("SELECT thread FROM search_scope_threads_dirty ORDER BY thread"),
    all("SELECT hex(session) AS session, after_rowid FROM search_scope_sessions_dirty ORDER BY session"),
    all("SELECT * FROM search_scope_meta"),
  ].join("\n");
}

const schema = (store: Store) => (store.db.prepare("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name LIKE 'search_scope_%' ORDER BY name").all() as { sql: string }[])
  .map((r) => ({ ...r, sql: r.sql.replace(/\s+/g, " ") }));

/// The same change made on a store between steps.
function change(f: ReturnType<typeof old>, at: number) {
  const { store, threads, key } = f;
  if (at === 3) store.db.prepare("UPDATE sessions SET ws = 'moved' WHERE key IN (?, ?, ?)").run(key(5), key(37), key(6));
  if (at === 5) { store.joinThread(threads[9]!, key(1), "ember"); store.joinThread(threads[18]!, "never", "ember"); }
  if (at === 7) store.db.prepare("DELETE FROM thread_sessions WHERE thread = ?").run(threads[1]!);
  if (at === 9) store.db.prepare("DELETE FROM threads WHERE id = ?").run(threads[2]!);
  if (at === 11) store.db.prepare("UPDATE sessions SET ws = NULL WHERE key = ?").run(key(41));
  if (at === 13) store.db.prepare("DELETE FROM sessions WHERE key = ?").run(key(7));
}

test("the MoonBit builder prepares the search scopes as the TypeScript steps do", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "search-scope", "--db", mb.path]);
  try {
    const preparation = new SearchScopePreparation(ts.store.db);
    const steps: [boolean, boolean][] = [];
    for (let i = 0; i < 400; i++) {
      const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
      builder.postMessage({ scope: "all" });
      const ours = await answered;
      assert.equal(ours.error, undefined);
      steps.push([preparation.step().done, ours.done]);
      if (i === 0) assert.deepEqual(schema(mb.store), schema(ts.store));
      assert.equal(tables(mb.store), tables(ts.store), `after step ${i}`);
      change(ts, i); change(mb, i);
      if (ours.done && i > 14) break;
    }
    assert.ok(steps.length > 14, JSON.stringify(steps));
    assert.deepEqual(steps.map((s) => s[1]), steps.map((s) => s[0]));
    assert.equal(steps.at(-1)![1], true);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("the station's search scope builder finishes by the MoonBit program", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const f = old();
  const builder = new SearchScopeBuilder(f.path, {});
  try {
    await builder.prepare();
    assert.equal((f.store.db.prepare("SELECT threads_done, members_done FROM search_scope_meta").get() as { threads_done: number; members_done: number }).members_done, 1);
    assert.ok((f.store.db.prepare("SELECT count(*) AS n FROM search_scope_members").get() as { n: number }).n > 300);
  } finally {
    await builder.close();
    f.close();
  }
});

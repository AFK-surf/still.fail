import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { SigninSaveBuilder } from "../src/vault/signin-save-builder.ts";
import { installSigninSaveIndex, queueSigninSave, signinSaveComplete, stepSigninSaveIndex } from "../src/vault/signin-save-index.ts";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "signin-save-"));
  const path = join(dir, "station.db");
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE signin_asks (id TEXT PRIMARY KEY, session TEXT NOT NULL, owner TEXT NOT NULL, status TEXT NOT NULL, body TEXT NOT NULL);
    CREATE INDEX signin_asks_by_session ON signin_asks (session, status);`);
  const insert = db.prepare("INSERT INTO signin_asks VALUES (?, ?, 'p', 'done', ?)");
  const add = (id: string, session: string, save: string) => insert.run(id, session, JSON.stringify({ id, session, save }));
  return { dir, db, add, close: () => { db.close(); rmSync(dir, { recursive: true, force: true }); } };
}

test("a saved decision waits for the previous station even when its index is complete", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), answered = Promise.withResolvers<string | null>();
  let builder: SigninSaveBuilder | null = null;
  try {
    f.add("old", "s", "save");
    installSigninSaveIndex(f.db);
    assert.deepEqual(stepSigninSaveIndex(f.db, "s"), { done: true, visited: 1 });
    queueSigninSave(f.db, "s", "save", "granted");
    const calls: string[] = [];
    builder = new SigninSaveBuilder(f.db, (_pending, body) => { calls.push("answered"); answered.resolve(body); }, { previousGone: previous.promise });
    await Promise.resolve();
    assert.deepEqual(calls, [], "the old station may still be writing its card");
    previous.resolve();
    assert.equal(JSON.parse((await answered.promise)!).id, "old");
    assert.deepEqual(calls, ["answered"]);
  } finally { previous.resolve(); await builder?.close(); f.close(); }
});

test("a stopped sign-in index worker retries a persisted decision", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), answered = Promise.withResolvers<string | null>();
  const file = join(f.dir, "worker.mjs"), marker = join(f.dir, "exited");
  const real = new URL("../src/vault/signin-save-worker.ts", import.meta.url).href;
  writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  let builder: SigninSaveBuilder | null = null;
  try {
    for (let n = 0; n < 130; n++) f.add(`old-${n}`, "s", `save-${n}`);
    installSigninSaveIndex(f.db);
    assert.deepEqual(stepSigninSaveIndex(f.db, "s", 2), { done: false, visited: 2 });
    builder = new SigninSaveBuilder(f.db, (_pending, body) => answered.resolve(body), { previousGone: previous.promise }, pathToFileURL(file));
    builder.wait("s", "save-129", "granted");
    await Promise.resolve();
    assert.equal(existsSync(marker), false);
    previous.resolve();
    assert.equal(JSON.parse((await answered.promise)!).id, "old-129");
    assert.equal(existsSync(marker), true);
    assert.equal(signinSaveComplete(f.db, "s"), true);
    assert.equal(f.db.prepare("SELECT 1 FROM signin_save_pending").get(), undefined);
  } finally { previous.resolve(); await builder?.close(); f.close(); }
});

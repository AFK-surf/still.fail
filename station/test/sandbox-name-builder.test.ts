import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { keyPart, sandboxName } from "../src/agents/sandbox-name.ts";
import { SandboxNameBuilder } from "../src/sessions/sandbox-name-builder.ts";
import { Store } from "../src/store/store.ts";

const add = `INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
  VALUES (?,'connected','thread','claude','default','.',?,0,0)`;
const name = (key: string) => sandboxName(keyPart(key));
const tick = () => new Promise<void>((resolve) => setImmediate(resolve));

test("a sandbox sweep waits for the previous writer, then prepares its names on a worker", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sandbox-name-worker-"));
  const path = join(dir, "store.db");
  const store = Store.open(path), old = new DatabaseSync(path);
  const previous = Promise.withResolvers<void>();
  const builder = new SandboxNameBuilder(store, previous.promise);
  try {
    const put = old.prepare(add);
    put.run("before", "token-before");
    const results = [builder.sessions([name("before"), name("after")]), builder.sessions([name("after")])];
    await tick();
    assert.deepEqual(await Promise.all(results), ["fallback", "fallback"]);
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'sandbox_name_meta'").get(), undefined);
    put.run("after", "token-after");
    previous.resolve();
    await tick();
    assert.deepEqual(await Promise.all([builder.sessions([name("before"), name("after")]), builder.sessions([name("after")])]), [
      new Map([[name("before"), "before"], [name("after"), "after"]]),
      new Map([[name("after"), "after"]]),
    ]);
  } finally {
    previous.resolve();
    await builder.close();
    old.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a foreground writer can finish while the sandbox lookup is being installed", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sandbox-name-lock-"));
  const path = join(dir, "store.db");
  const store = Store.open(path), writer = new DatabaseSync(path);
  const builder = new SandboxNameBuilder(store, Promise.resolve());
  try {
    writer.exec("BEGIN IMMEDIATE");
    writer.prepare(add).run("held", "token-held");
    const pending = builder.sessions([name("held")]);
    await tick();
    writer.exec("COMMIT");
    assert.deepEqual(await pending, new Map([[name("held"), "held"]]));
  } finally {
    try { writer.exec("ROLLBACK"); } catch {}
    await builder.close();
    writer.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("closing a sandbox lookup while the previous station is up settles its wait", async () => {
  const store = Store.open(":memory:");
  const previous = Promise.withResolvers<void>();
  const builder = new SandboxNameBuilder(store, previous.promise);
  try {
    const pending = builder.sessions([name("s")]);
    await tick();
    await builder.close();
    assert.equal(await pending, "fallback");
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'sandbox_name_meta'").get(), undefined);
  } finally { previous.resolve(); await builder.close(); store.close(); }
});

test("switching sandbox mode off during preparation stops it and a later sweep repairs the lookup", async () => {
  const store = Store.open(":memory:");
  let enabled = true;
  const builder = new SandboxNameBuilder(store, Promise.resolve(), () => enabled);
  try {
    const put = store.db.prepare(add);
    for (let i = 0; i < 200; i++) put.run(`s-${i}`, `token-${i}`);
    const pending = builder.sessions([name("s-0")]);
    await tick();
    enabled = false;
    await builder.disable();
    assert.equal(await pending, null);
    store.db.prepare("DELETE FROM sessions WHERE key = ?").run("s-0");
    put.run("later", "token-later");
    enabled = true;
    assert.deepEqual(await builder.sessions([name("s-0"), name("later")]), new Map([[name("later"), "later"]]));
  } finally { await builder.close(); store.close(); }
});

test("a runner appearing while the sandbox lookup is being turned off keeps it prepared", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sandbox-name-runner-race-"));
  const path = join(dir, "store.db");
  const store = Store.open(path), writer = new DatabaseSync(path);
  let enabled = true;
  const builder = new SandboxNameBuilder(store, Promise.resolve(), () => enabled);
  try {
    store.db.prepare(add).run("session", "token");
    assert.deepEqual(await builder.sessions([name("session")]), new Map([[name("session"), "session"]]));
    writer.exec("BEGIN IMMEDIATE");
    enabled = false;
    const off = builder.disable();
    await tick();
    assert.deepEqual(builder.runners([{ id: "claude-session", part: "session" }]), new Map([["claude-session", "session"]]));
    writer.exec("COMMIT");
    await off;
    await builder.settled();
    assert.equal(store.db.prepare("SELECT enabled FROM sandbox_name_meta WHERE id = 1").get()?.enabled, 1);
    assert.deepEqual(builder.runners([{ id: "claude-session", part: "session" }]), new Map([["claude-session", "session"]]));
  } finally {
    try { writer.exec("ROLLBACK"); } catch {}
    await builder.close();
    writer.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a stopped sandbox lookup worker can be started again", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sandbox-name-retry-"));
  const store = Store.open(join(dir, "store.db"));
  const worker = join(dir, "worker.mjs");
  writeFileSync(worker, "process.exit(1);\n");
  const builder = new SandboxNameBuilder(store, Promise.resolve(), () => true, pathToFileURL(worker));
  try {
    store.db.prepare(add).run("session", "token");
    assert.equal(await builder.sessions([name("session")]), "fallback");
    const actual = new URL("../src/sessions/workspace-activity-worker.ts", import.meta.url).href;
    writeFileSync(worker, `import ${JSON.stringify(actual)};\n`);
    assert.deepEqual(await builder.sessions([name("session")]), new Map([[name("session"), "session"]]));
  } finally {
    await builder.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

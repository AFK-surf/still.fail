import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { keyPart, placeIn, sandboxConfig, sandboxName } from "../src/agents/sandbox.ts";
import { Hub } from "../src/sessions/hub.ts";
import { Store } from "../src/store/store.ts";
import { SANDBOX_SESSION } from "../src/store/sandbox-index.ts";
import type { SandboxNameBuilder } from "../src/sessions/sandbox-name-builder.ts";

test("rechecking an idle sandbox does not reread unrelated session history", async () => {
  const reads: number[] = [];
  for (const unrelated of [40, 400]) {
    const dir = mkdtempSync(join(tmpdir(), "sandbox-sweep-"));
    const store = Store.open(":memory:"), db = store.db;
    const path = process.env.PATH, fixture = process.env.SANDBOX_SWEEP_FIXTURE;
    let count = 0, observing = false;
    db.function("sweep_session_seen", () => { if (observing) count++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(
        sql === "SELECT * FROM sessions ORDER BY last_active_at DESC"
          ? sql.replace(" ORDER BY", " WHERE sweep_session_seen() ORDER BY")
          : sql === SANDBOX_SESSION ? sql.replace("WHERE n.name = ?", "WHERE n.name = ? AND sweep_session_seen()") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    writeFileSync(join(dir, "ssh"), `#!/bin/sh
for a; do last=$a; done
if [ "$last" = ls ]; then cat "$SANDBOX_SWEEP_FIXTURE/ls"; else printf '%s\\n' "$last" >> "$SANDBOX_SWEEP_FIXTURE/stopped"; exit 1; fi
`);
    chmodSync(join(dir, "ssh"), 0o755);
    process.env.PATH = `${dir}:${path}`;
    process.env.SANDBOX_SWEEP_FIXTURE = dir;
    const unplace = placeIn(dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host", warm: 0 } }), () => []);
    try {
      const put = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
        VALUES (?,'connected','thread','claude','default','.',?,0,0)`);
      put.run("target", "token-target");
      for (let i = 0; i < unrelated; i++) put.run(`unrelated-${i}`, `token-${i}`);
      const name = sandboxName(keyPart("target"));
      writeFileSync(join(dir, "ls"), "");
      Object.defineProperty(store, "db", { value: observed });
      const hub = Object.assign(Object.create(Hub.prototype), { store, config: () => ({ dataDir: dir }), actors: new Map() });
      await hub.sweepSandboxes();
      assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'sandbox_name_meta'").get(), undefined);
      writeFileSync(join(dir, "ls"), `${name} running 0% deleted in 50 min if unused\ns-someone-else-0123456789 running 0% deleted in 50 min if unused\n`);
      await hub.sweepSandboxes(); // An earlier station's names may need to be discovered once.
      observing = true;
      await hub.sweepSandboxes(); // The failed stop leaves the same sandbox for the next sweep.
      observing = false;
      assert.deepEqual(readFileSync(join(dir, "stopped"), "utf8").trim().split("\n"), [name, name]);
      reads.push(count);
    } finally {
      unplace();
      if (path === undefined) delete process.env.PATH; else process.env.PATH = path;
      if (fixture === undefined) delete process.env.SANDBOX_SWEEP_FIXTURE; else process.env.SANDBOX_SWEEP_FIXTURE = fixture;
      store.close();
      rmSync(dir, { recursive: true, force: true });
    }
  }
  assert.deepEqual(reads, [1, 1]);
});

test("a sweep still stops its idle sandbox before the previous station exits", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sandbox-sweep-handover-"));
  const store = Store.open(":memory:");
  const previous = Promise.withResolvers<void>();
  const path = process.env.PATH, fixture = process.env.SANDBOX_SWEEP_FIXTURE;
  const name = sandboxName(keyPart("target"));
  writeFileSync(join(dir, "ssh"), `#!/bin/sh
for a; do last=$a; done
if [ "$last" = ls ]; then cat "$SANDBOX_SWEEP_FIXTURE/ls"; else printf '%s\\n' "$last" >> "$SANDBOX_SWEEP_FIXTURE/stopped"; exit 1; fi
`);
  chmodSync(join(dir, "ssh"), 0o755);
  writeFileSync(join(dir, "ls"), `${name} running 0% deleted in 50 min if unused\n`);
  process.env.PATH = `${dir}:${path}`;
  process.env.SANDBOX_SWEEP_FIXTURE = dir;
  const unplace = placeIn(dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host", warm: 0 } }), () => []);
  const hub = Object.assign(Object.create(Hub.prototype), {
    store, config: () => ({ dataDir: dir }), actors: new Map(), options: { previous: previous.promise },
  });
  try {
    store.db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
      VALUES ('target','connected','thread','claude','default','.','token',0,0)`).run();
    await hub.sweepSandboxes();
    assert.equal(readFileSync(join(dir, "stopped"), "utf8").trim(), name);
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'sandbox_name_meta'").get(), undefined);
    previous.resolve();
    await new Promise<void>((resolve) => setImmediate(resolve));
    await hub.sweepSandboxes();
    assert.deepEqual(readFileSync(join(dir, "stopped"), "utf8").trim().split("\n"), [name, name]);
  } finally {
    previous.resolve();
    await (hub as { sandboxNames?: SandboxNameBuilder }).sandboxNames?.close();
    unplace();
    if (path === undefined) delete process.env.PATH; else process.env.PATH = path;
    if (fixture === undefined) delete process.env.SANDBOX_SWEEP_FIXTURE; else process.env.SANDBOX_SWEEP_FIXTURE = fixture;
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

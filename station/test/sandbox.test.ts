// What of execution in sandboxes is the same every run (src/agents/sandbox.ts): their names, the setting, and that
// nothing goes to one for a station that has not placed itself. Running there, against a stand-in ssh of real processes,
// is the side run's (side/sandbox.test.ts).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";
import { checkSandbox, inSandbox, keyOfRunner, placeIn, sandboxConfig, sandboxName, sshArgs, syncFor } from "../src/agents/sandbox.ts";
import { runnerId } from "../src/agents/process.ts";
import { routes } from "../src/api/routes/sandbox.ts";
import { ConfigFile } from "../src/ops/config.ts";

const dirs: string[] = [];
const cleanups: (() => unknown)[] = [];
after(() => {
  for (const c of cleanups.reverse()) c();
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function tempdir(): string {
  const d = mkdtempSync(join(tmpdir(), "sbx-"));
  dirs.push(d);
  return d;
}

describe("sandbox names", () => {
  test("a key's sandbox has a name the front door takes, the same each time, apart from a key cleaning up the same", () => {
    const keys = ["C0AQ0C0KVMH-1792584359-921939", "c0aq0c0kvmh-1792584359-921939", "CHAT/1791455700.319000", "-", "a".repeat(80)];
    const names = keys.map(sandboxName);
    for (const n of names) assert.match(n, /^[a-z][a-z0-9-]{0,30}$/, n);
    assert.equal(new Set(names).size, keys.length);
    assert.equal(sandboxName(keys[0]), names[0]);
  });

  test("a session's processes and its jobs go to one sandbox", () => {
    const key = "CHAT/1791455700.319000";
    assert.equal(keyOfRunner(runnerId("claude", key)), keyOfRunner(runnerId("cursor", key)));
  });
});

describe("the setting", () => {
  test("only a destination with {name} switches it on; off keeps what was set", () => {
    assert.equal(sandboxConfig({}), null);
    assert.equal(sandboxConfig({ sandbox: { ssh: "dev@host" } }), null);
    assert.equal(sandboxConfig({ sandbox: { ssh: "{name}.ws@host", enabled: false } }), null);
    assert.deepEqual(sandboxConfig({ sandbox: { ssh: "{name}.ws@host", identity: "/k" } }), { enabled: true, ssh: "{name}.ws@host", identity: "/k", idleMinutes: 10, warm: 1 });
    assert.throws(() => checkSandbox({ sandbox: { ssh: "{name}@host", idleMinutes: 0 } }), /idleMinutes/);
    assert.throws(() => checkSandbox({ sandbox: { ssh: "host" } }), /\{name\}/);
    assert.throws(() => checkSandbox({ sandbox: { ssh: "{name}@host", enabled: "yes" } }), /enabled/);
    checkSandbox({ sandbox: { ssh: "{name}.ws@l4es.afk.surf", enabled: false } });
    assert.deepEqual(sandboxConfig({ sandbox: { ssh: "{name}.ws@host", labels: ["lax2"] } })?.labels, ["lax2"]);
    assert.equal(sandboxConfig({ sandbox: { ssh: "{name}.ws@host", labels: [] } })?.labels, undefined);
    checkSandbox({ sandbox: { ssh: "{name}.ws@host", labels: ["lax2", "fast"] } });
    assert.throws(() => checkSandbox({ sandbox: { ssh: "{name}.ws@host", labels: "lax2" } }), /labels/);
    assert.throws(() => checkSandbox({ sandbox: { ssh: "{name}.ws@host", labels: ["LAX 2"] } }), /labels/);
    // One sandbox kept warm unless it says otherwise, from none to eight.
    assert.equal(sandboxConfig({ sandbox: { ssh: "{name}.ws@host", warm: 3 } })?.warm, 3);
    checkSandbox({ sandbox: { ssh: "{name}.ws@host", warm: 0 } });
    for (const warm of [-1, 1.5, 9, "2"]) assert.throws(() => checkSandbox({ sandbox: { ssh: "{name}.ws@host", warm } }), /warm/);
  });

  test("ssh is asked for the sandbox by name, with the key and host keys given", () => {
    const args = sshArgs({ enabled: true, ssh: "{name}.ws@host", identity: "/id", knownHosts: "/kh", idleMinutes: 10, warm: 0 }, "s-a-1");
    assert.equal(args[0], "ssh");
    assert.equal(args.at(-1), "s-a-1.ws@host");
    assert.ok(args.includes("BatchMode=yes") && args.includes("/id") && args.includes("UserKnownHostsFile=/kh"));
  });

  test("switching on is refused while a sandbox does not see the data directory, and kept when it does", async () => {
    const data = tempdir();
    const config = new ConfigFile(data);
    let sees = false;
    const [, put] = routes({ config, reach: async () => (sees ? { ok: true } : { ok: false, why: "it does not see it" }) });
    const ask = (role: string, body: object) =>
      put.handle({ method: "PUT", path: "/sandbox", query: [], headers: {}, body: Buffer.from(JSON.stringify(body)), viewer: { sub: "u", email: "", name: "", role, workspace: "w", device: "d" }, lang: "en" } as any, []);
    assert.equal((await ask("member", { ssh: "{name}.ws@host" })).status, 403);
    const refused = await ask("owner", { ssh: "{name}.ws@host" });
    assert.equal(refused.status, 409);
    assert.equal(config.raw().sandbox, undefined);
    sees = true;
    assert.equal((await ask("owner", { ssh: "{name}.ws@host" })).status, 200);
    assert.deepEqual(config.raw().sandbox, { ssh: "{name}.ws@host" });
    // Switching off asks nothing of the sandbox.
    sees = false;
    assert.equal((await ask("owner", { enabled: false })).status, 200);
    assert.equal(sandboxConfig(config.raw()), null);
  });
});

describe("placing", () => {
  test("nothing goes to a sandbox for a station that has not placed itself, or has it off", () => {
    assert.equal(inSandbox(tempdir(), "k", "claude", [], "/"), null);
    const data = tempdir();
    cleanups.push(placeIn(data, () => null, () => []));
    assert.equal(inSandbox(data, "k", "claude", [], "/"), null);
  });

  test("syncs Antigravity's gemini config dir while skipping its runtime caches and databases", () => {
    const data = tempdir();
    const entries = syncFor(data, "agy", { ANTIGRAVITY_GEMINI_DIR: "/h/agy/.gemini" }, "/tmp/cwd");
    const agyEntry = entries.find((e) => e.path === "/h/agy/.gemini");
    assert.ok(agyEntry);
    assert.equal(agyEntry.mode, "whole");
    for (const ignored of ["bin", "brain", "builtin", "cache", "cli.log", "conversations", "log", "conversation_summaries.db", "conversation_summaries.db-wal"]) {
      assert.ok(agyEntry.skip?.includes(ignored), `expected ${ignored} in skip`);
    }
  });
});

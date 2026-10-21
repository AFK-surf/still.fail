// Execution in sandboxes (src/agents/sandbox.ts, src/agents/sandbox-bridge.mjs) against a stand-in for ssh that runs
// the far side on this machine as sshd would: in a session of its own, its stdio the connection's, so it outlives the
// connection unless the bridge there ends it.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { after, describe, test } from "node:test";
import { BRIDGE, checkSandbox, inSandbox, keyOfRunner, placeIn, sandboxConfig, sandboxName, sshArgs } from "../src/agents/sandbox.ts";
import { runnerId } from "../src/agents/process.ts";
import { ClaudeDriver } from "../src/agents/claude.ts";
import type { RuntimeEvent } from "../src/agents/runtime.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import { routes } from "../src/api/routes/sandbox.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { signalGroup } from "../src/ops/group.ts";
import { Store } from "../src/store/store.ts";

const dirs: string[] = [];
const cleanups: (() => unknown)[] = [];
after(async () => {
  for (const c of cleanups.reverse()) await c();
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function tempdir(): string {
  // Short: a runner's socket is in it (104 bytes on macOS).
  const d = mkdtempSync("/tmp/sbx-");
  dirs.push(d);
  return d;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Waits for what a real process does, looking every 5 ms. No deadline: it comes, however slow the machine.
async function until(_what: string, check: () => boolean) {
  while (!check()) await sleep(5);
}

/// A stand-in `ssh` in `dir`: writes the destination it was given to `<dir>/destinations`, then runs the remote
/// command detached (a session of its own, as sshd's), its stdio passed through; ends with it. To the front door
/// (`_…`) it answers as l4es does a `create`: it writes the command to `<dir>/made` and is done.
function fakeSsh(dir: string): string {
  const program = join(dir, "ssh");
  writeFileSync(
    program,
    `#!${process.execPath}
const { spawn } = require("node:child_process");
const { appendFileSync } = require("node:fs");
const args = process.argv.slice(2);
const at = args.findIndex((a) => a.includes("@"));
const destination = args[at];
const command = args.slice(at + 1).join(" ");
if (destination.startsWith("_")) {
  appendFileSync(${JSON.stringify(join(dir, "made"))}, destination + " " + command + "\\n");
  process.exit(0);
}
appendFileSync(${JSON.stringify(join(dir, "destinations"))}, destination + "\\n");
const far = spawn("/bin/sh", ["-c", command], { detached: true, stdio: ["pipe", "pipe", "inherit"] });
process.stdin.pipe(far.stdin);
far.stdin.on("error", () => {});
far.stdout.pipe(process.stdout);
far.on("exit", (code) => process.exit(code ?? 1));
`,
  );
  chmodSync(program, 0o755);
  return program;
}

const destinations = (dir: string) => (existsSync(join(dir, "destinations")) ? readFileSync(join(dir, "destinations"), "utf8").trim().split("\n") : []);

function listening(handler: (path: string) => string): Promise<Server> {
  const server = createServer((q, r) => r.end(handler(q.url ?? "")));
  cleanups.push(() => new Promise((r) => server.close(r)));
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

/// The bridge's host side run as a runner would run it: what it said and how it ended.
function bridge(spec: object, stdin: string): Promise<{ out: string; err: string; code: number | null }> {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [BRIDGE, "host", JSON.stringify(spec)], { stdio: ["pipe", "pipe", "pipe"] });
    let out = "";
    let err = "";
    child.stdout.on("data", (b) => (out += b));
    child.stderr.on("data", (b) => (err += b));
    child.on("close", (code) => resolve({ out, err, code }));
    child.stdin.end(stdin);
  });
}

describe("sandbox names", () => {
  test("a key's sandbox has a name the front door takes, the same each time, apart from a key cleaning up the same", () => {
    const keys = ["C0AQ0C0KVMH-1792584359-921939", "c0aq0c0kvmh-1792584359-921939", "EMBER/1791455700.319000", "-", "a".repeat(80)];
    const names = keys.map(sandboxName);
    for (const n of names) assert.match(n, /^[a-z][a-z0-9-]{0,30}$/, n);
    assert.equal(new Set(names).size, keys.length);
    assert.equal(sandboxName(keys[0]), names[0]);
  });

  test("a session's processes and its jobs go to one sandbox", () => {
    const key = "EMBER/1791455700.319000";
    assert.equal(keyOfRunner(runnerId("claude", key)), keyOfRunner(runnerId("cursor", key)));
  });
});

describe("the setting", () => {
  test("only a destination with {name} switches it on; off keeps what was set", () => {
    assert.equal(sandboxConfig({}), null);
    assert.equal(sandboxConfig({ sandbox: { ssh: "dev@host" } }), null);
    assert.equal(sandboxConfig({ sandbox: { ssh: "{name}.ws@host", enabled: false } }), null);
    assert.deepEqual(sandboxConfig({ sandbox: { ssh: "{name}.ws@host", identity: "/k" } }), { enabled: true, ssh: "{name}.ws@host", identity: "/k" });
    assert.throws(() => checkSandbox({ sandbox: { ssh: "host" } }), /\{name\}/);
    assert.throws(() => checkSandbox({ sandbox: { ssh: "{name}@host", enabled: "yes" } }), /enabled/);
    checkSandbox({ sandbox: { ssh: "{name}.ws@l4es.afk.surf", enabled: false } });
  });

  test("ssh is asked for the sandbox by name, with the key and host keys given", () => {
    const args = sshArgs({ enabled: true, ssh: "{name}.ws@host", identity: "/id", knownHosts: "/kh" }, "s-a-1");
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

describe("the bridge", () => {
  test("the program's stdio, its exit and its connections to the station's ports go through one connection", async () => {
    const dir = tempdir();
    const ssh = fakeSsh(dir);
    const station = await listening((path) => `door ${path}`);
    const here = (station.address() as AddressInfo).port;
    // On one machine the far side cannot listen at the station's own port: another stands for it there.
    const there = await listening(() => "").then((s) => {
      const p = (s.address() as AddressInfo).port;
      return new Promise<number>((r) => s.close(() => r(p)));
    });
    const script = `echo out; echo err >&2; head -c 5; echo; curl -s http://127.0.0.1:${there}/mcp; echo; exit 3`;
    const ran = await bridge({ ssh: [ssh, "s-x.ws@host"], program: "/bin/sh", args: ["-c", script], cwd: dir, ports: [{ sandbox: there, here }] }, "hello world");
    assert.equal(ran.code, 3);
    assert.equal(ran.out, `out\nhello\ndoor /mcp\n`);
    assert.equal(ran.err, "err\n");
    assert.deepEqual(destinations(dir), ["s-x.ws@host"]);
  });

  test("a working directory the sandbox does not have is said, not run elsewhere", async () => {
    const dir = tempdir();
    const ran = await bridge({ ssh: [fakeSsh(dir), "s-x.ws@host"], program: "/bin/pwd", args: [], cwd: join(dir, "nowhere"), ports: [] }, "");
    assert.equal(ran.code, 127);
    assert.match(ran.err, /is not in the sandbox/);
  });

  test("the connection gone, the program in the sandbox is ended", async () => {
    const dir = tempdir();
    const pidFile = join(dir, "pid");
    const child = spawn(process.execPath, [BRIDGE, "host", JSON.stringify({ ssh: [fakeSsh(dir), "s-x.ws@host"], program: "/bin/sh", args: ["-c", `echo $$ > ${pidFile}; exec tail -f /dev/null`], cwd: dir, ports: [] })], {
      stdio: ["pipe", "ignore", "ignore"], detached: true,
    });
    await until("the program runs", () => existsSync(pidFile) && readFileSync(pidFile, "utf8").trim() !== "");
    const pid = Number(readFileSync(pidFile, "utf8"));
    // As the station ends an agent: its group, here the bridge and ssh. The far side is in a session of its own.
    signalGroup(child.pid!, "SIGKILL");
    const alive = () => {
      try {
        process.kill(pid, 0);
        return true;
      } catch {
        return false;
      }
    };
    await until("the program in the sandbox ends", () => !alive());
  });
});

describe("jobs", () => {
  test("a session's job runs in its sandbox; a service stays here", async () => {
    const dir = tempdir();
    const ssh = fakeSsh(dir);
    const path = process.env.PATH;
    process.env.PATH = `${dir}:${path}`;
    cleanups.push(() => (process.env.PATH = path));
    const store = Store.open(":memory:");
    cleanups.push(() => store.close());
    const jobs = new Jobs({ store, data: dir, notify: () => {}, link: () => null });
    cleanups.push(() => jobs.shutdown().catch(() => undefined));
    const unplace = placeIn(dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host" } }), () => []);
    cleanups.push(unplace);
    assert.ok(ssh.endsWith("/ssh"));
    const work = join(dir, "work");
    mkdirSync(work);

    const job = jobs.start("s1", "build", "echo built; exit 4", work, null, false);
    await until("it ends", () => store.getJob(job.id)!.state === "exited");
    assert.equal(store.getJob(job.id)!.exitCode, 4);
    assert.equal(readFileSync(store.getJob(job.id)!.log, "utf8").trim(), "built");
    assert.deepEqual(destinations(dir), [`${sandboxName(keyOfRunner(runnerId("claude", "s1")))}.ws@host`]);

    const service = jobs.start("s1", "web", "echo serving", work, 45999, false);
    await until("it ends", () => store.getJob(service.id)!.state === "exited");
    assert.equal(destinations(dir).length, 1);
  });

  test("a job that asks for a size gets a sandbox of its own of that size, made first", async () => {
    const dir = tempdir();
    fakeSsh(dir);
    const path = process.env.PATH;
    process.env.PATH = `${dir}:${path}`;
    cleanups.push(() => (process.env.PATH = path));
    const store = Store.open(":memory:");
    cleanups.push(() => store.close());
    const jobs = new Jobs({ store, data: dir, notify: () => {}, link: () => null });
    cleanups.push(() => jobs.shutdown().catch(() => undefined));
    const work = join(dir, "work");
    mkdirSync(work);
    // Not while the station runs its jobs here.
    assert.throws(() => jobs.start("s1", "build", "true", work, null, false, false, { cpus: 8 }), /only a job this station runs in a sandbox/);
    cleanups.push(placeIn(dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host" } }), () => []));
    assert.throws(() => jobs.start("s1", "web", "true", work, 45998, false, false, { cpus: 8 }), /not a service/);

    const job = jobs.start("s1", "build", "echo big", work, null, false, false, { cpus: 8, memoryGib: 32 });
    await until("it ends", () => store.getJob(job.id)!.state === "exited");
    assert.deepEqual(store.getJob(job.id)!.size, { cpus: 8, memoryGib: 32 });
    const name = sandboxName(`${keyOfRunner(runnerId("claude", "s1"))}|c8m32`);
    assert.notEqual(name, sandboxName(keyOfRunner(runnerId("claude", "s1"))));
    assert.deepEqual(readFileSync(join(dir, "made"), "utf8").trim().split("\n"), [`_.ws@host create ${name} --cpus 8 --mem 32`]);
    assert.deepEqual(destinations(dir), [`${name}.ws@host`]);
    assert.equal(readFileSync(store.getJob(job.id)!.log, "utf8").trim(), "big");
  });

  test("nothing goes to a sandbox for a station that has not placed itself, or has it off", () => {
    assert.equal(inSandbox(tempdir(), "k", "claude", [], "/"), null);
    const data = tempdir();
    cleanups.push(placeIn(data, () => null, () => []));
    assert.equal(inSandbox(data, "k", "claude", [], "/"), null);
  });
});

describe("a runtime's process", () => {
  test("a session's claude runs in its sandbox, its turns as they would be here", async () => {
    const dir = tempdir();
    fakeSsh(dir);
    const fake = join(dirname(fileURLToPath(import.meta.url)), "fake");
    const path = process.env.PATH;
    process.env.PATH = `${dir}:${fake}:${path}`;
    cleanups.push(() => (process.env.PATH = path));
    cleanups.push(placeIn(dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host" } }), () => []));
    const driver = new ClaudeDriver({ data: dir });
    cleanups.push(() => driver.shutdown());
    const home = join(dir, "home");
    mkdirSync(home);
    writeFileSync(join(home, ".credentials.json"), "{}");
    const key = "EMBER/1791455700.319000";
    const events: RuntimeEvent[] = [];
    const session = await driver.open(
      { key, profile: { id: "cc", runtime: "claude", home, access: { kind: "opencode-go", key: "k1" } }, cwd: dir, instructions: "", mcpToken: "tok", mcpUrl: "http://127.0.0.1:4750/mcp", route: "r" },
      (e) => void events.push(e),
    );
    await session.prompt("say:hello");
    await until("the turn ends", () => events.some((e) => e.type === "turnEnded"));
    assert.deepEqual(events.find((e) => e.type === "turnEnded"), { type: "turnEnded", outcome: { kind: "completed" } });
    assert.deepEqual(events.flatMap((e) => (e.type === "live" && e.event.kind === "delta" ? [e.event.text] : [])), ["hello"]);
    assert.deepEqual(destinations(dir), [`${sandboxName(keyOfRunner(runnerId("claude", key)))}.ws@host`]);
  });
});

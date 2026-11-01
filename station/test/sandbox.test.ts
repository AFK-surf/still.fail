// Execution in sandboxes (src/agents/sandbox.ts, src/agents/sandbox-bridge.mjs) against a stand-in for ssh that runs
// the far side on this machine as sshd would: in a session of its own, its stdio the connection's, so it outlives the
// connection unless the bridge there ends it.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { appendFileSync, chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { after, describe, test } from "node:test";
import { BRIDGE, CONNECTION_LOST, LOST_EXIT, checkSandbox, fetchFiles, keyPart, sessionSync, stationPath, syncChanged, syncFor, inSandbox, keyOfRunner, placeIn, sandboxConfig, sandboxName, sshArgs } from "../src/agents/sandbox.ts";
import { runnerId } from "../src/agents/process.ts";
import { ClaudeDriver } from "../src/agents/claude.ts";
import { CodexDriver } from "../src/agents/codex.ts";
import type { RuntimeEvent } from "../src/agents/runtime.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import { routes } from "../src/api/routes/sandbox.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { signalGroup } from "../src/ops/group.ts";
import { Store } from "../src/store/store.ts";
import { Rig, say, settle } from "./hub-fakes.ts";
import { sessionKey } from "../src/sessions/hub.ts";

const dirs: string[] = [];
const cleanups: (() => unknown)[] = [];
after(async () => {
  for (const c of cleanups.reverse()) await c();
  // What the stand-in sandboxes still run (a far side copying what its program left, after the test): ended, and
  // waited for, before their files go.
  for (const d of dirs) {
    const far = existsSync(join(d, "far-pids")) ? readFileSync(join(d, "far-pids"), "utf8").trim().split("\n").map(Number) : [];
    for (const pid of far) signalGroup(pid, "SIGKILL");
    await until("the stand-in sandboxes' processes end", () => far.every((pid) => !alive(pid)));
    rmSync(d, { recursive: true, force: true });
  }
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
/// command detached (a session of its own, as sshd's), its stdio passed through, its runtime directory the
/// destination's own (each sandbox its machine); ends with it. To the front door
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
appendFileSync(${JSON.stringify(join(dir, "ssh-pids"))}, process.pid + "\\n");
// Each sandbox a machine of its own: the bridge there keeps its runtimes' groups in its runtime directory.
const own = ${JSON.stringify(dir)} + "/run-" + destination;
require("node:fs").mkdirSync(own, { recursive: true });
process.env.XDG_RUNTIME_DIR = own;
// And its files apart from the station's: the station's paths under a directory of its own.
process.env.STILLFAIL_SANDBOX_PREFIX = own + "/fs";
const far = spawn("/bin/sh", ["-c", command], { detached: true, stdio: ["pipe", "pipe", "inherit"] });
appendFileSync(${JSON.stringify(join(dir, "far-pids"))}, far.pid + "\\n");
process.stdin.pipe(far.stdin);
far.stdin.on("error", () => {});
far.stdout.pipe(process.stdout);
far.on("exit", (code) => process.exit(code ?? 1));
`,
  );
  chmodSync(program, 0o755);
  return program;
}

/// The stand-in ssh's processes, in the order they started: killing one is the connection breaking.
const sshPids = (dir: string) => (existsSync(join(dir, "ssh-pids")) ? readFileSync(join(dir, "ssh-pids"), "utf8").trim().split("\n").map(Number) : []);

const alive = (pid: number) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

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
    assert.deepEqual(sandboxConfig({ sandbox: { ssh: "{name}.ws@host", identity: "/k" } }), { enabled: true, ssh: "{name}.ws@host", identity: "/k", idleMinutes: 10 });
    assert.throws(() => checkSandbox({ sandbox: { ssh: "{name}@host", idleMinutes: 0 } }), /idleMinutes/);
    assert.throws(() => checkSandbox({ sandbox: { ssh: "host" } }), /\{name\}/);
    assert.throws(() => checkSandbox({ sandbox: { ssh: "{name}@host", enabled: "yes" } }), /enabled/);
    checkSandbox({ sandbox: { ssh: "{name}.ws@l4es.afk.surf", enabled: false } });
  });

  test("ssh is asked for the sandbox by name, with the key and host keys given", () => {
    const args = sshArgs({ enabled: true, ssh: "{name}.ws@host", identity: "/id", knownHosts: "/kh", idleMinutes: 10 }, "s-a-1");
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

  test("a working directory the sandbox does not have is made there, at the same path", async () => {
    const dir = tempdir();
    const ran = await bridge({ ssh: [fakeSsh(dir), "s-x.ws@host"], program: "/bin/pwd", args: [], cwd: join(dir, "nowhere", "yet"), ports: [] }, "");
    assert.equal(ran.code, 0);
    assert.ok(ran.out.trim().endsWith(`/run-s-x.ws@host/fs${join(dir, "nowhere", "yet")}`), ran.out);
    assert.ok(!existsSync(join(dir, "nowhere")), "not here");
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

describe("a connection lost", () => {
  test("the bridge says so apart from the program ending, writes its file, and the program there is ended", async () => {
    const dir = tempdir();
    fakeSsh(dir);
    const pidFile = join(dir, "pid");
    const lostFile = join(dir, "lost");
    // The program says it runs on its stdout: the bridge here passes that on only after it heard the program started
    // (the far side says so first, on the same stream), while its pid file is written before the bridge may have.
    const spec = { ssh: [join(dir, "ssh"), "s-x.ws@host"], program: "/bin/sh", args: ["-c", `echo $$ > ${pidFile}; echo runs; exec tail -f /dev/null`], cwd: dir, ports: [], lostFile };
    const child = spawn(process.execPath, [BRIDGE, "host", JSON.stringify(spec)], { stdio: ["pipe", "pipe", "pipe"] });
    let err = "";
    let out = "";
    child.stderr.on("data", (b) => (err += b));
    child.stdout.on("data", (b) => (out += b));
    const ended = new Promise<number | null>((r) => child.on("close", (code) => r(code)));
    await until("the bridge heard the program runs", () => out.includes("runs"));
    const pid = Number(readFileSync(pidFile, "utf8"));
    process.kill(sshPids(dir)[0], "SIGKILL");
    assert.equal(await ended, LOST_EXIT);
    assert.ok(err.includes(CONNECTION_LOST), err);
    assert.ok(existsSync(lostFile));
    await until("the program in the sandbox ends", () => !alive(pid));
  });

  test("a sandbox that could not be reached is not a connection lost", async () => {
    const dir = tempdir();
    const ran = await bridge({ ssh: ["/usr/bin/false", "s-x.ws@host"], program: "/bin/true", args: [], cwd: dir, ports: [], lostFile: join(dir, "lost") }, "");
    assert.equal(ran.code, 255);
    assert.ok(!ran.err.includes(CONNECTION_LOST), ran.err);
    assert.ok(!existsSync(join(dir, "lost")));
  });

  test("a runtime started in a sandbox ends the ones started there before, with what they started", async () => {
    const dir = tempdir();
    fakeSsh(dir);
    const run = join(dir, "xdg");
    mkdirSync(run);
    const start = (name: string) => {
      const pidFile = join(dir, name);
      const spec = { ssh: [join(dir, "ssh"), "s-x.ws@host"], program: "/bin/sh", args: ["-c", `sleep 1000 & echo $! > ${pidFile}.child; echo $$ > ${pidFile}; wait`], cwd: dir, ports: [], agent: true };
      const child = spawn(process.execPath, [BRIDGE, "host", JSON.stringify(spec)], { stdio: ["pipe", "ignore", "ignore"], env: { ...process.env, XDG_RUNTIME_DIR: run } });
      cleanups.push(() => child.kill("SIGKILL"));
      return { pid: () => (existsSync(pidFile) && existsSync(`${pidFile}.child`) && readFileSync(`${pidFile}.child`, "utf8").trim() !== "" ? [Number(readFileSync(pidFile, "utf8")), Number(readFileSync(`${pidFile}.child`, "utf8"))] : null) };
    };
    const first = start("first");
    await until("the first runs", () => first.pid() !== null);
    const [shell, sleeper] = first.pid()!;
    // Its connection gone without the sandbox being told (no end of input): it would run on beside the next.
    process.kill(sshPids(dir)[0], "SIGSTOP");
    cleanups.push(() => process.kill(sshPids(dir)[0], "SIGKILL"));
    const second = start("second");
    await until("the second runs", () => second.pid() !== null);
    assert.ok(!alive(shell) && !alive(sleeper), "the first and what it started were ended");
    assert.ok(alive(second.pid()![0]));
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

  test("a job whose connection to its sandbox was lost starts again there once", async () => {
    const dir = tempdir();
    fakeSsh(dir);
    const path = process.env.PATH;
    process.env.PATH = `${dir}:${path}`;
    cleanups.push(() => (process.env.PATH = path));
    const store = Store.open(":memory:");
    cleanups.push(() => store.close());
    const told: string[] = [];
    const jobs = new Jobs({ store, data: dir, notify: (_s, t) => void told.push(t), link: () => null });
    cleanups.push(() => jobs.shutdown().catch(() => undefined));
    cleanups.push(placeIn(dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host" } }), () => []));
    const work = join(dir, "work");
    mkdirSync(work);
    const runs = join(dir, "runs");
    const job = jobs.start("s1", "build", `echo run >> ${runs}; [ "$(wc -l < ${runs})" -ge 2 ] || exec tail -f /dev/null`, work, null, false);
    await until("it runs", () => existsSync(runs));
    process.kill(sshPids(dir)[0], "SIGKILL");
    await until("it ends the second time", () => store.getJob(job.id)!.state === "exited" && store.getJob(job.id)!.restarts === 1);
    assert.equal(store.getJob(job.id)!.exitCode, 0);
    assert.equal(readFileSync(runs, "utf8"), "run\nrun\n");
    assert.ok(told.some((t) => t.includes("lost the connection to the sandbox")), told.join("\n"));
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
    assert.throws(() => jobs.start("s1", "build", "true", work, null, false, false, "large"), /only a job this station runs in a sandbox/);
    cleanups.push(placeIn(dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host" } }), () => []));
    assert.throws(() => jobs.start("s1", "web", "true", work, 45998, false, false, "large"), /not a service/);

    const job = jobs.start("s1", "build", "echo big", work, null, false, false, "large");
    await until("it ends", () => store.getJob(job.id)!.state === "exited");
    assert.equal(store.getJob(job.id)!.size, "large");
    const name = sandboxName(`${keyOfRunner(runnerId("claude", "s1"))}|large`);
    assert.notEqual(name, sandboxName(keyOfRunner(runnerId("claude", "s1"))));
    assert.deepEqual(readFileSync(join(dir, "made"), "utf8").trim().split("\n"), [`_.ws@host create ${name} --size large`]);
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

describe("Codex", () => {
  test("in sandboxes each session has an app-server of its own, in its sandbox, ended with its thread", async () => {
    const dir = tempdir();
    fakeSsh(dir);
    const fake = join(dirname(fileURLToPath(import.meta.url)), "fake");
    const path = process.env.PATH;
    process.env.PATH = `${dir}:${fake}:${path}`;
    cleanups.push(() => (process.env.PATH = path));
    cleanups.push(placeIn(dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host" } }), () => []));
    writeFileSync(join(dir, "cert.pem"), "");
    // A bundle here (the driver names it SSL_CERT_FILE) that the stand-in sandbox does not have at that path.
    const driver = new CodexDriver({ data: dir, hostSkills: join(dir, "skills"), caBundle: join(dir, "cert.pem") });
    cleanups.push(() => driver.shutdown());
    const dump = join(dir, "dump");
    const profile = { id: "cx", runtime: "codex" as const, home: join(dir, "home"), access: { kind: "opencode-go", key: "k" }, env: { FAKE_DUMP: dump } };
    const open = (key: string, events: RuntimeEvent[]) =>
      driver.open({ key, profile, cwd: dir, instructions: "", mcpToken: "tok", mcpUrl: "http://127.0.0.1:4750/mcp", route: "r" }, (e) => void events.push(e));
    const a: RuntimeEvent[] = [];
    const b: RuntimeEvent[] = [];

    const one = await open("EMBER/1.1", a);
    await open("EMBER/2.2", b);
    const started = () => readFileSync(dump, "utf8").trim().split("\n").map((l) => JSON.parse(l));
    assert.equal(started().length, 2, "an app-server each");
    // The station's certificate file is not the sandbox's: not named to it.
    assert.equal(started()[0].env.SSL_CERT_FILE, undefined);
    // Its state database on the sandbox's own disk, not in its home (on NFS there).
    const sqlite = started()[0].env.CODEX_SQLITE_HOME;
    assert.ok(typeof sqlite === "string" && sqlite.includes("/.cache/stillfail/codex-sqlite/") && !sqlite.startsWith(profile.home), sqlite);
    assert.deepEqual(new Set(destinations(dir)), new Set(["EMBER/1.1", "EMBER/2.2"].map((k) => `${sandboxName(keyOfRunner(runnerId("codex", k)))}.ws@host`)));
    await one.prompt("say:hi");
    await until("its turn ends", () => a.some((e) => e.type === "turnEnded"));
    assert.deepEqual(a.find((e) => e.type === "turnEnded"), { type: "turnEnded", outcome: { kind: "completed" } });
    const pid = started()[0].pid;
    await one.dispose();
    await until("its app-server ends", () => !alive(pid));
    assert.ok(alive(started()[1].pid), "the other session's goes on");
  });
});

describe("the station's GitHub login", () => {
  test("lent to a program there as GH_TOKEN, with git's credentials from gh there; nothing when gh here is not signed in", async () => {
    const dir = tempdir();
    const ssh = fakeSsh(dir);
    const bin = join(dir, "bin");
    mkdirSync(bin);
    const show = "printf '%s|%s\\n' \"$GH_TOKEN\" \"$(git config --get credential.https://github.com.helper)\"";
    const run = (env: NodeJS.ProcessEnv) =>
      new Promise<string>((resolve) => {
        const spec = { ssh: [ssh, "s-x.ws@host"], program: "/bin/sh", args: ["-c", show], cwd: dir, ports: [], gh: true };
        const child = spawn(process.execPath, [BRIDGE, "host", JSON.stringify(spec)], { stdio: ["ignore", "pipe", "ignore"], env });
        let out = "";
        child.stdout.on("data", (b) => (out += b));
        child.on("close", () => resolve(out.trim()));
      });
    // gh here signed in: its token.
    writeFileSync(join(bin, "gh"), "#!/bin/sh\n[ \"$1 $2\" = \"auth token\" ] && echo gho_lent && exit 0\nexit 1\n");
    chmodSync(join(bin, "gh"), 0o755);
    // git's own configuration here left out: only what is lent counts.
    const env = { ...process.env, PATH: `${bin}:${process.env.PATH}`, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
    assert.equal(await run(env), "gho_lent|!gh auth git-credential");
    // Not signed in: nothing lent.
    writeFileSync(join(bin, "gh"), "#!/bin/sh\nexit 1\n");
    assert.equal(await run(env), "|");
  });
});

describe("paths in a sandbox with persist", () => {
  test("its data directory is a link into persist there, a shell there says the station's path, and a path under persist is the station's", async () => {
    const dir = tempdir();
    const data = join(dir, "data");
    mkdirSync(join(data, "sessions", "s", "workspace"), { recursive: true });
    const cwd = join(data, "sessions", "s", "workspace");
    const ran = await bridge({ ssh: [fakeSsh(dir), "s-x.ws@host"], program: "/bin/sh", args: ["-c", "pwd; pwd -P"], cwd, ports: [], root: { path: data, persist: "/mnt/sf/st" }, dirs: [], sync: [] }, "");
    assert.equal(ran.code, 0, ran.err);
    const [logical, physical] = ran.out.trim().split("\n");
    assert.ok(logical!.endsWith(`/fs${cwd}`), logical);
    assert.ok(physical!.includes("/fs/mnt/sf/st/sessions/s/workspace"), physical);
    cleanups.push(placeIn(data, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host", persist: "/mnt/sf/st/" } }), () => []));
    assert.equal(stationPath(data, "/mnt/sf/st/sessions/s/workspace/a.png"), join(cwd, "a.png"));
    assert.equal(stationPath(data, "/mnt/sf/st"), data);
    assert.equal(stationPath(data, "/mnt/sf/stx/a"), "/mnt/sf/stx/a");
    assert.equal(stationPath(data, join(cwd, "a.png")), join(cwd, "a.png"));
  });
});

describe("files, never shared", () => {
  /// Where the stand-in sandbox for destination `dest` has the station's path `path`.
  const there = (dir: string, dest: string, path: string) => `${dir}/run-${dest}/fs${path}`;

  test("a runtime's home and the agent home go there, credentials do not; transcripts and what the agent writes come back", async () => {
    const dir = tempdir();
    fakeSsh(dir);
    const path = process.env.PATH;
    process.env.PATH = `${dir}:${path}`;
    cleanups.push(() => (process.env.PATH = path));
    const agentHome = join(dir, "agent");
    mkdirSync(join(agentHome, "skills", "ours"), { recursive: true });
    writeFileSync(join(agentHome, "MEMORY.md"), "remember\n");
    writeFileSync(join(agentHome, "skills", "ours", "SKILL.md"), "ours\n");
    const home = join(dir, "homes", "cc");
    mkdirSync(join(home, "projects", "p"), { recursive: true });
    writeFileSync(join(home, "settings.json"), "{}");
    writeFileSync(join(home, ".credentials.json"), "secret");
    symlinkSync(join(agentHome, "MEMORY.md"), join(home, "CLAUDE.md"));
    symlinkSync(join(agentHome, "skills"), join(home, "skills"));
    writeFileSync(join(home, "projects", "p", "t.jsonl"), "{\"a\":1}\n");
    const cwd = join(dir, "sessions", "s1", "workspace");
    mkdirSync(join(cwd, "uploads"), { recursive: true });
    writeFileSync(join(cwd, "uploads", "in.txt"), "from a person");
    cleanups.push(placeIn(dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host" } }), () => [], agentHome));
    const placed = inSandbox(dir, "s1", "/bin/sh", ["-c", [
      // What it was given (relative: the sandbox has the station's paths at its own place).
      "cat ../../../homes/cc/settings.json uploads/in.txt; [ -e ../../../homes/cc/.credentials.json ] && echo LEAKED; readlink ../../../homes/cc/CLAUDE.md",
      // What it writes: its transcript grows, a skill and its memory change, a file of its own in the workspace.
      "printf '{\"b\":2}\\n' >> ../../../homes/cc/projects/p/t.jsonl; echo mine > ../../../agent/skills/ours/new.md; echo more >> ../../../homes/cc/CLAUDE.md; echo work > out.txt",
    ].join("; ")], cwd, { sync: syncFor(dir, "claude", { CLAUDE_CONFIG_DIR: home }, cwd) })!;
    const ran = await new Promise<{ out: string; code: number | null }>((resolve) => {
      const child = spawn(placed.program, placed.args, { stdio: ["ignore", "pipe", "inherit"] });
      let out = "";
      child.stdout.on("data", (b) => (out += b));
      child.on("close", (code) => resolve({ out, code }));
    });
    assert.equal(ran.code, 0);
    assert.equal(ran.out, `{}from a person${join(agentHome, "MEMORY.md")}\n`.replace(join(agentHome, "MEMORY.md"), there(dir, `${sandboxName("s1")}.ws@host`, join(agentHome, "MEMORY.md"))));
    // Back here: the transcript as it grew, the new skill, the memory through its link; the credentials untouched.
    assert.equal(readFileSync(join(home, "projects", "p", "t.jsonl"), "utf8"), '{"a":1}\n{"b":2}\n');
    assert.equal(readFileSync(join(agentHome, "skills", "ours", "new.md"), "utf8"), "mine\n");
    assert.equal(readFileSync(join(agentHome, "MEMORY.md"), "utf8"), "remember\nmore\n");
    assert.equal(readFileSync(join(home, ".credentials.json"), "utf8"), "secret");
    // What it made in the workspace stays there.
    assert.ok(!existsSync(join(cwd, "out.txt")));
    assert.ok(existsSync(there(dir, `${sandboxName("s1")}.ws@host`, join(cwd, "out.txt"))));
  });

  test("what the station puts in a workspace goes there before the agent's input, only when it changed; what the agent attaches comes here", async () => {
    const dir = tempdir();
    fakeSsh(dir);
    const path = process.env.PATH;
    process.env.PATH = `${dir}:${path}`;
    cleanups.push(() => (process.env.PATH = path));
    cleanups.push(placeIn(dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host" } }), () => []));
    const cwd = join(dir, "sessions", "s2", "workspace");
    mkdirSync(join(cwd, "uploads"), { recursive: true });
    writeFileSync(join(cwd, "uploads", "a.png"), "png");
    const key = keyPart("s2");
    const dest = `${sandboxName(key)}.ws@host`;
    await syncChanged(dir, key, sessionSync(dir, cwd));
    assert.equal(readFileSync(there(dir, dest, join(cwd, "uploads", "a.png")), "utf8"), "png");
    const connections = sshPids(dir).length;
    await syncChanged(dir, key, sessionSync(dir, cwd));
    assert.equal(sshPids(dir).length, connections, "nothing new: no connection");
    appendFileSync(join(cwd, "uploads", "a.png"), "!");
    await syncChanged(dir, key, sessionSync(dir, cwd));
    assert.equal(readFileSync(there(dir, dest, join(cwd, "uploads", "a.png")), "utf8"), "png!");
    // A file only the sandbox has, attached: brought here at its path.
    mkdirSync(there(dir, dest, cwd), { recursive: true });
    writeFileSync(there(dir, dest, join(cwd, "chart.svg")), "<svg/>");
    await fetchFiles(dir, key, [join(cwd, "chart.svg")]);
    assert.equal(readFileSync(join(cwd, "chart.svg"), "utf8"), "<svg/>");
  });
});

describe("a message's files from the sandbox", () => {
  for (const persist of [false, true]) {
    test(`a file only the session's sandbox has is posted${persist ? ", named by where the data directory's link leads there" : ""}`, async () => {
      const r = new Rig();
      fakeSsh(r.dir);
      const path = process.env.PATH;
      process.env.PATH = `${r.dir}:${path}`;
      const unplace = placeIn(r.dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host", ...(persist ? { persist: "/mnt/sf/st" } : {}) } }), () => []);
      try {
        const m = say("<@UBOT> chart it");
        await r.accept(m);
        await settle();
        const key = sessionKey("cl", "C1", m.threadTs);
        const workspace = r.session(key).workspace;
        const fs = `${r.dir}/run-${sandboxName(keyPart(key))}.ws@host/fs`;
        // Made by the agent there: in the data directory there, which with persist is a link into it.
        const rel = workspace.slice(r.dir.length + 1);
        const there = persist ? `${fs}/mnt/sf/st/${rel}` : `${fs}${workspace}`;
        mkdirSync(there, { recursive: true });
        if (persist) {
          mkdirSync(dirname(`${fs}${r.dir}`), { recursive: true });
          symlinkSync(`${fs}/mnt/sf/st`, `${fs}${r.dir}`);
        }
        writeFileSync(join(there, "chart.svg"), "<svg/>");
        const named = persist ? `/mnt/sf/st/${rel}/chart.svg` : join(workspace, "chart.svg");
        await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "图在这", files: [named] });
        assert.deepEqual([r.chat.lastText(), r.chat.files.at(-1)], ["图在这", ["chart.svg"]]);
        assert.equal(readFileSync(join(workspace, "chart.svg"), "utf8"), "<svg/>");
      } finally {
        unplace();
        process.env.PATH = path;
        await r.close();
      }
    });
  }
});

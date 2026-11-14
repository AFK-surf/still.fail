// Sandboxes (src/agents/sandbox.ts) end to end against a stand-in for ssh that runs the far side on this machine
// as sshd would: a chat's station_task to a sandbox is taken by the station itself, its command run in the
// chat's sandbox through src/agents/sandbox-bridge.mjs, the task's directory copied there and what it brings back
// copied here. Real processes, signals and sockets on real time: the side run's (scripts/side.sh); what of sandboxes
// is the same every run is test/sandbox.test.ts.
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { after, test } from "node:test";
import type { Sandbox } from "../src/agents/sandbox.ts";
import { sandboxOf } from "../src/agents/sandbox.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import { Remote } from "../src/jobs/remote.ts";
import { signalGroup } from "../src/ops/group.ts";
import { type Json, Store } from "../src/store/store.ts";
import { remoteTools } from "../src/tools/remote.ts";

const dirs: string[] = [];
const cleanups: (() => unknown)[] = [];
after(async () => {
  for (const c of cleanups.reverse()) await c();
  for (const d of dirs) {
    const far = existsSync(join(d, "far-pids")) ? readFileSync(join(d, "far-pids"), "utf8").trim().split("\n").map(Number) : [];
    for (const pid of far) signalGroup(pid, "SIGKILL");
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
async function until(_what: string, check: () => boolean | Promise<boolean>) {
  while (!(await check())) await sleep(5);
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


const made = (dir: string) => (existsSync(join(dir, "made")) ? readFileSync(join(dir, "made"), "utf8").trim().split("\n") : []);
const destinations = (dir: string) => (existsSync(join(dir, "destinations")) ? readFileSync(join(dir, "destinations"), "utf8").trim().split("\n") : []);

/// A station with a sandbox `box` (front door `{name}.ws@host`, size large) and a chat `s1` whose workspace is
/// `home`; `use` calls its agent's station tools.
function stationWithBox() {
  const dir = tempdir();
  fakeSsh(dir);
  const path = process.env.PATH;
  process.env.PATH = `${dir}:${path}`;
  cleanups.push(() => (process.env.PATH = path));
  const store = Store.open(":memory:");
  const jobs = new Jobs({ store, data: dir, notify: () => {}, link: () => null });
  const told: [string, string][] = [];
  const remote = new Remote({ data: dir, store, jobs, notify: (session, text) => void told.push([session, text]) });
  cleanups.push(async () => {
    await remote.close();
    for (const job of store.listJobs(null)) if (job.pgid !== null) signalGroup(job.pgid, "SIGKILL");
    await jobs.shutdown();
    store.close();
  });
  mkdirSync(join(dir, "mesh"), { recursive: true });
  writeFileSync(join(dir, "mesh", "cloud.json"), JSON.stringify({ workspace: "ws", station: "A" }));
  remote.attach(async (target, _workspace, request) => {
    if (target === "" && request.method === "peers") return { workspace: "ws", stations: [{ id: "A" }], current: true };
    throw new Error("no other station");
  });
  const box: Sandbox = { name: "box", target: "{name}.ws@host", size: "large" };
  remote.setSandboxes(() => [box]);
  jobs.setSandboxes((name) => (name === box.name ? box : null));
  const home = join(dir, "work");
  mkdirSync(home);
  store.insertSession({ key: "s1", connect: "ds", runtime: "claude", profile: "cc", workspace: home, token: "t1", createdBy: "ann", createdAt: Date.now(), lastActiveAt: Date.now() });
  const tools = remoteTools(remote);
  const use = async (name: string, args: Json): Promise<Json> => JSON.parse(await tools.find((t) => t.name === name)!.run("s1", args));
  return { dir, home, box, store, use, told };
}

test("station_list shows a sandbox, and station_task runs its task in the chat's sandbox there: the directory copied there, what it brings back here", async () => {
  const { dir, home, box, use } = stationWithBox();
  const listed = await use("station_list", {});
  assert.ok(listed.stations.some((s: Json) => s.id === `sandbox:${box.name}` && s.name === "box" && s.kind === "sandbox"), JSON.stringify(listed));
  const src = join(dir, "src");
  mkdirSync(src);
  writeFileSync(join(src, "a.txt"), "from here\n");
  const task = { station: "box", key: "k1" };
  await use("station_task", { ...task, action: "prepare", command: "cat a.txt > out.txt; echo built; uname -s > /dev/null", dir: src, back: ["out.txt"] });
  let started = await use("station_task", { ...task, action: "start" });
  while (started.syncing === true) started = await use("station_task", { ...task, action: "start" });
  await until("it ends", async () => ["exited", "failed"].includes((await use("station_task", { ...task, action: "get" })).job?.state));
  const got = await use("station_task", { ...task, action: "get" });
  assert.equal(got.job.exitCode, 0, JSON.stringify(got));
  assert.match((await use("station_task", { ...task, action: "log" })).log, /built/);
  // Made of its size, at its front door, then connected to by its name; ran where the sandbox's files are.
  const name = sandboxOf(box, "s1");
  assert.ok(made(dir).includes(`_.ws@host create ${name} --size large`), made(dir).join("\n"));
  assert.ok(destinations(dir).every((d) => d === `${name}.ws@host`) && destinations(dir).length >= 2, destinations(dir).join("\n"));
  // What it brought back, here in the chat's workspace.
  await until("its results are here", () => existsSync(join(home, "station-back", "k1", "out.txt")));
  assert.equal(readFileSync(join(home, "station-back", "k1", "out.txt"), "utf8"), "from here\n");
});

test("a sandbox has no screen: a task that asks for one is refused", async () => {
  const { use } = stationWithBox();
  await assert.rejects(use("station_task", { station: "box", key: "k2", action: "prepare", command: "true", screen: true }).then((p) => use("station_task", { station: "box", key: "k2", action: "start" })), /no screen/);
});

// A grant's adb server behind its door (src/adb/door.ts): another chat's adb, knowing the port, is refused; the grant's
// session goes through, by its agent, its jobs, or (a runtime shared by sessions) its own directory.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { failure, gate, type GateDeps, openDoor } from "../src/adb/door.ts";
import { platform } from "../src/platform/index.ts";
import type { ProcessInfo } from "../src/platform/index.ts";

const row = (pid: number, ppid: number, pgid = pid): ProcessInfo => ({ pid, ppid, pgid, bytes: 0, command: "adb" });
const STATION = 100;
const deps = (over: Partial<GateDeps> = {}): GateDeps => ({
  session: () => ({ workspace: "/chats/a" }),
  // 1 ─ 200 (a's runner) ─ 201 (its runtime) ─ 202 (its shell) ─ 203 (its adb); 300 ─ 301: b's; 100 ─ 101: the station's
  // adb; 400 (a's job's group) ─ 401; 500 (b's job, its shell gone: adb straight under the station).
  table: async () => [row(1, 1), row(STATION, 1), row(101, STATION), row(200, 1), row(201, 200), row(202, 201), row(203, 202), row(300, 1), row(301, 300), row(400, 1), row(401, 400, 400), row(500, STATION, 500)],
  runners: () => [200, 201],
  jobs: () => [{ pgid: 400, mine: () => true }, { pgid: 500, mine: () => false }],
  cwds: async () => new Map(),
  self: STATION,
  ...over,
});

test("under the session's agent, in its job, or the station's own adb: let in", async () => {
  assert.equal(await gate(deps(), "g", [203]), null);
  assert.equal(await gate(deps(), "g", [401]), null);
  assert.equal(await gate(deps(), "g", [101]), null);
});

test("another chat's agent, its job, and a process no one knows are refused", async () => {
  for (const pid of [301, 500, 999]) assert.match((await gate(deps(), "g", [pid]))!, /granted to another chat/);
  assert.match((await gate(deps(), "g", []))!, /granted to another chat/);
});

test("a shared runtime's command is the session's only in the session's own directory", async () => {
  const dir = mkdtempSync(join(tmpdir(), "adb-gate-"));
  try {
    const own = realpathSync(dir);
    const at = (cwd: string) => deps({ session: () => ({ workspace: dir }), cwds: async () => new Map([[301, cwd]]) });
    assert.equal(await gate(at(own), "g", [301]), null);
    assert.equal(await gate(at(join(own, "repo")), "g", [301]), null);
    assert.match((await gate(at(`${own}-other`), "g", [301]))!, /granted to another chat/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("processes not read, or a grant gone: refused", async () => {
  assert.match((await gate(deps({ table: async () => null }), "g", [203]))!, /could not tell/);
  assert.match((await gate(deps({ session: () => null }), "g", [203]))!, /granted to another chat/);
});

test("a refusal is adb's FAIL with its length", () => {
  assert.equal(failure("no"), "FAIL0002no");
});

/// What a client gets for sending `ask` through `port`, once its connection is closed.
const through = (port: number, ask: string) => new Promise<string>((resolve, reject) => {
  const c = net.connect({ host: "127.0.0.1", port, allowHalfOpen: true }, () => c.end(ask));
  const got: Buffer[] = [];
  c.on("data", (b) => got.push(b));
  c.once("error", reject);
  c.once("close", () => resolve(Buffer.concat(got).toString()));
});

test("the door puts a client through to the server, half-close and all, or says why not", { skip: process.platform === "win32" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "adb-door-"));
  const path = join(dir, "s");
  // A server that answers once its client has finished saying.
  const server = net.createServer({ allowHalfOpen: true }, (c) => {
    const got: Buffer[] = [];
    c.on("data", (b) => got.push(b));
    c.once("end", () => c.end(`OKAY${Buffer.concat(got)}`));
  });
  await new Promise<void>((r) => server.listen(path, r));
  let why: string | null = null;
  const seen: number[][] = [];
  const door = await openDoor("g", path, (p) => platform.tcpPortPids(p), async (_id, holders) => (seen.push(holders), why));
  try {
    assert.equal(await through(door.port, "000chost:version"), "OKAY000chost:version");
    why = "not this chat";
    assert.equal(await through(door.port, "000chost:version"), failure("not this chat"));
    assert.equal(seen.length, 2);
  } finally {
    door.close();
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the door finds the real client: a process of another directory is told, one of the session's let in", { skip: process.platform === "win32" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "adb-door-"));
  const path = join(dir, "s");
  const own = join(dir, "own");
  const other = join(dir, "other");
  for (const d of [own, other]) mkdirSync(d);
  const server = net.createServer((c) => {
    c.once("data", () => c.end("OKAY"));
  });
  await new Promise<void>((r) => server.listen(path, r));
  const admit = (id: string, holders: number[]) => gate({
    session: () => ({ workspace: own }),
    table: () => platform.processTable(false),
    runners: () => [],
    jobs: () => [],
    cwds: (pids) => platform.cwds(pids),
    self: -1,
  }, id, holders);
  const door = await openDoor("g", path, (p) => platform.tcpPortPids(p), admit);
  // A client of its own process, in `cwd`, as adb's: it says what it asks and waits for the answer (a client gone or
  // half-closed holds no connection `tcpPortPids` finds).
  const client = (cwd: string) => new Promise<string>((resolve, reject) => {
    const script = `const c=require("node:net").connect({host:"127.0.0.1",port:${door.port}},()=>c.write("000chost:version"));c.on("data",(b)=>process.stdout.write(b));`;
    const child = spawn(process.execPath, ["-e", script], { cwd, stdio: ["ignore", "pipe", "inherit"] });
    let said = "";
    child.stdout.on("data", (b) => (said += b));
    child.once("error", reject);
    child.once("close", () => resolve(said));
  });
  try {
    assert.equal(await client(own), "OKAY");
    assert.match(await client(other), /^FAIL[0-9a-f]{4}this phone is granted to another chat/);
  } finally {
    door.close();
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a server gone: the door says so rather than leaving adb to start its own", { skip: process.platform === "win32" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "adb-door-"));
  const door = await openDoor("g", join(dir, "none"), async () => [], async () => null);
  try {
    assert.match(await through(door.port, "000chost:version"), /^FAIL[0-9a-f]{4}this chat's adb server is gone/);
  } finally {
    door.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

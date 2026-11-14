// The grants' adb servers a station process before left running (src/adb/servers.ts `reap`): stopped by the next, as
// written down; another process given one's pid since is left alone.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fsModule, { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { GrantServers, type Server } from "../src/adb/servers.ts";
import { platform } from "../src/platform/index.ts";
import { settle } from "./hub-fakes.ts";

test("the grants' adb servers a station before left are stopped by the next; a pid now another's is left", { skip: process.platform === "win32" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "adb-reap-"));
  const record = join(dir, "adb-servers.json");
  const left = spawn("sleep", ["60"], { stdio: "ignore" });
  const other = spawn("sleep", ["60"], { stdio: "ignore" });
  try {
    await new Promise((r) => setTimeout(r, 200));
    const exited = new Promise<number | null>((resolve) => left.once("exit", (code, signal) => resolve(signal === "SIGTERM" ? 15 : code)));
    writeFileSync(record, JSON.stringify([
      { pid: left.pid, port: 1, started: await platform.startTimeOf(left.pid!) },
      // As written down, started long before: not this process.
      { pid: other.pid, port: 2, started: ((await platform.startTimeOf(other.pid!)) ?? 0) - 3_600_000 },
    ]));
    const servers = new GrantServers(() => null, record);
    assert.equal(await servers.reap(), 1);
    assert.equal(await exited, 15, "the one left stopped");
    assert.equal(other.exitCode, null, "the other runs on");
  } finally {
    left.kill("SIGKILL");
    other.kill("SIGKILL");
    rmSync(dir, { recursive: true, force: true });
  }
});

/// An adb that serves on the port it is given (`adb -P <port> server nodaemon`), in `dir`.
function fakeAdb(dir: string): string {
  const adb = join(dir, "adb");
  writeFileSync(adb, `#!${process.execPath}\nrequire("node:net").createServer((c) => c.destroy()).listen(Number(process.argv[3]), "127.0.0.1");\n`, { mode: 0o755 });
  return adb;
}

/// Grants a and b's servers started, each in `started` for the test to end whatever comes of it (one left running
/// keeps the test's process, and so the run, from ending), and both ended, as heard here.
async function both(servers: GrantServers, started: Server[]): Promise<{ gone: Promise<unknown> }> {
  const [a, b] = await Promise.all([servers.ensure("a"), servers.ensure("b")]);
  started.push(...[a, b].filter((s) => s !== null));
  assert.ok(a !== null && b !== null, "both started");
  return { gone: Promise.all([a, b].map((s) => new Promise((resolve) => s.child.once("exit", resolve)))) };
}

const read = (record: string) => JSON.parse(readFileSync(record, "utf8"));

test("the grants' servers stopped together, as a station process hands over, are written down without it ending", { skip: process.platform === "win32" }, async () => {
  // On ccvm (2026-11-04) two of them ended at once as the station handed over: both wrote the record through the same
  // temporary file, the second's rename found none, and its rejection ended the process before it handed its sessions
  // over (the next took up every agent as after a crash, its main thread held 11 s).
  const dir = mkdtempSync(join(tmpdir(), "adb-servers-"));
  const record = join(dir, "adb-servers.json");
  const adb = fakeAdb(dir);
  const started: Server[] = [];
  // A rejection nothing took is heard here alone while this runs: node:test's own listener fails the test with the
  // rejection itself as it comes, before the test says what it was looking for.
  const unhandled: unknown[] = [];
  const caught = (reason: unknown) => void unhandled.push(reason);
  const others = process.listeners("unhandledRejection");
  process.removeAllListeners("unhandledRejection");
  process.on("unhandledRejection", caught);
  try {
    const servers = new GrantServers(() => adb, record);
    // The record once what was asked written of it is, and what was asked outside that (both writes were, on
    // 2026-11-04) has come to its end too, a rejection of it heard here.
    const written = async () => {
      await servers.written();
      await settle();
      assert.deepEqual(unhandled, [], "no write of the record rejected with nothing to take it");
      return read(record);
    };
    const { gone } = await both(servers, started);
    // Written down as each started (not waited on there).
    assert.equal((await written()).length, 2);
    await servers.close();
    await gone;
    // Written down again as each ended, not waited on there either. (The record was looked at 200 ms after the ends
    // until 2026-11-14: check-station 3/6 found one still written down, the write after the second end not come yet.)
    assert.deepEqual(await written(), [], "none left written down");
  } finally {
    process.off("unhandledRejection", caught);
    for (const other of others) process.on("unhandledRejection", other);
    for (const s of started) s.child.kill("SIGKILL");
    rmSync(dir, { recursive: true, force: true });
  }
});

test("what was asked written of the grants' servers is not done before the disk is, however long it takes", { skip: process.platform === "win32" }, async () => {
  // The wait the test above stands on: the record's renames are held until both servers have ended, as a busy disk
  // held the last one in CI.
  const dir = mkdtempSync(join(tmpdir(), "adb-servers-"));
  const record = join(dir, "adb-servers.json");
  const adb = fakeAdb(dir);
  const started: Server[] = [];
  let open = () => {};
  const held = new Promise<void>((resolve) => void (open = resolve));
  const rename = fsModule.promises.rename;
  fsModule.promises.rename = (async (from, to) => {
    if (to === record) await held;
    return rename(from, to);
  }) as typeof rename;
  syncBuiltinESMExports();
  try {
    const servers = new GrantServers(() => adb, record);
    const { gone } = await both(servers, started);
    await servers.close();
    await gone;
    let written = false;
    const writing = servers.written().then(() => void (written = true));
    // (A turn of the loop, for what could be done to be: this cannot, its writes held.)
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(written, false, "not done while the record's writes wait");
    assert.equal(existsSync(record), false, "nothing written yet");
    open();
    await writing;
    assert.deepEqual(read(record), [], "none left written down");
  } finally {
    open();
    fsModule.promises.rename = rename;
    syncBuiltinESMExports();
    for (const s of started) s.child.kill("SIGKILL");
    rmSync(dir, { recursive: true, force: true });
  }
});

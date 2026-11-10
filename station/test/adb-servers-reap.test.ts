// The grants' adb servers a station process before left running (read/adb/servers.ts `reap`): stopped by the next, as
// written down; another process given one's pid since is left alone.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { GrantServers } from "../src/adb/servers.ts";
import { platform } from "../src/platform/index.ts";

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

test("the grants' servers stopped together, as a station process hands over, are written down without it ending", { skip: process.platform === "win32" }, async () => {
  // On ccvm (2026-11-04) two of them ended at once as the station handed over: both wrote the record through the same
  // temporary file, the second's rename found none, and its rejection ended the process before it handed its sessions
  // over (the next took up every agent as after a crash, its main thread held 11 s).
  const dir = mkdtempSync(join(tmpdir(), "adb-servers-"));
  const record = join(dir, "adb-servers.json");
  // An adb that serves on the port it is given (`adb -P <port> server nodaemon`).
  const adb = join(dir, "adb");
  writeFileSync(adb, `#!${process.execPath}\nrequire("node:net").createServer((c) => c.destroy()).listen(Number(process.argv[3]), "127.0.0.1");\n`, { mode: 0o755 });
  const unhandled: unknown[] = [];
  const caught = (reason: unknown) => void unhandled.push(reason);
  process.on("unhandledRejection", caught);
  try {
    const servers = new GrantServers(() => adb, record);
    const [a, b] = await Promise.all([servers.ensure("a"), servers.ensure("b")]);
    assert.ok(a !== null && b !== null, "both started");
    // Written down as each started (not waited on there).
    const written = () => { try { return JSON.parse(readFileSync(record, "utf8")).length as number; } catch { return -1; } };
    for (let i = 0; i < 50 && written() !== 2; i++) await new Promise((r) => setTimeout(r, 20));
    assert.equal(written(), 2);
    const ended = Promise.all([a!, b!].map((s) => new Promise((resolve) => s.child.once("exit", resolve))));
    await servers.close();
    await ended;
    await new Promise((r) => setTimeout(r, 200));
    assert.deepEqual(unhandled, []);
    assert.deepEqual(JSON.parse(readFileSync(record, "utf8")), [], "none left written down");
  } finally {
    process.off("unhandledRejection", caught);
    rmSync(dir, { recursive: true, force: true });
  }
});

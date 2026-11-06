import assert from "node:assert/strict";
import fs from "node:fs";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { CodexDriver } from "../src/agents/codex.ts";
import { runnerId } from "../src/agents/process.ts";
import type { RunnerInfo } from "../src/agents/runner.ts";
import { Rig } from "./hub-fakes.ts";

test("finding runners for recovery does not read their files on the station thread", async () => {
  const r = new Rig();
  const hub = r.newHub({ chats: () => undefined, internal: false });
  delete hub.options.runners;
  const dir = join(r.dir, "run", "runners");
  mkdirSync(dir, { recursive: true });
  const socket = join(r.dir, "runner-socket");
  writeFileSync(socket, "");
  const info: RunnerInfo = { id: runnerId("codex", "profile"), runner: process.pid, pid: process.pid,
    pgid: process.pid, startedAt: 1, program: "test", args: [], socket };
  const file = join(dir, `${info.id}.json`);
  writeFileSync(file, JSON.stringify(info));
  const driver = new CodexDriver({ data: r.dir, hostSkills: r.dir, caBundle: join(r.dir, "ca") });
  const read = fs.readFileSync;
  let syncReads = 0;
  fs.readFileSync = ((path: fs.PathOrFileDescriptor, ...args: unknown[]) => {
    if (String(path) === file) syncReads++;
    return (read as (...args: any[]) => any)(path, ...args);
  }) as typeof read;
  syncBuiltinESMExports();
  try {
    const left = await (driver as unknown as { leftRunners(key: string): Promise<RunnerInfo[]> }).leftRunners("profile");
    assert.deepEqual(left.map((runner) => runner.id), [info.id]);
    await hub.takeUp();
    assert.equal(syncReads, 0, "neither recovery path waits for runner files on the station thread");
  } finally {
    fs.readFileSync = read;
    syncBuiltinESMExports();
    await hub.shutdown();
    await driver.shutdown();
    await r.close();
  }
});

test("a runner directory that cannot be read is not treated as an empty directory", async () => {
  const data = mkdtempSync(join(tmpdir(), "runners-unreadable-"));
  mkdirSync(join(data, "run"));
  writeFileSync(join(data, "run", "runners"), "not a directory");
  const driver = new CodexDriver({ data, hostSkills: data, caBundle: join(data, "ca") });
  const r = new Rig();
  const hub = r.newHub({ chats: () => undefined, internal: false });
  delete hub.options.runners;
  mkdirSync(join(r.dir, "run"), { recursive: true });
  writeFileSync(join(r.dir, "run", "runners"), "not a directory");
  try {
    await assert.rejects(async () => (driver as unknown as { leftRunners(key: string): Promise<RunnerInfo[]> }).leftRunners("profile"),
      { code: "ENOTDIR" });
    await assert.rejects(hub.takeUp(), { code: "ENOTDIR" });
  } finally {
    await hub.shutdown();
    await driver.shutdown();
    await r.close();
    rmSync(data, { recursive: true, force: true });
  }
});

import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { workspaceIndex } from "../src/comma/workspace-index.ts";
import { CommaStats, type StationRows } from "../src/comma/stats.ts";

const quiet = () => () => {};
const empty = async () => ({ stations: [], unread: [] });
const row = (thread: number, title: string): StationRows => ({
  usage: { rows: [] }, chats: [{ thread, title, surface: "stillfail", createdAt: 1, lastActiveAt: 2, agents: [] }],
});

test("a home uses only its own persistent index, including on restart", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-home-index-"));
  const legacy = CommaStats.at(dir, empty, quiet);
  try { legacy.apply([row(1, "unknown owner")], [], 0); } finally { legacy.close(); }
  const old = CommaStats.inWorkspace(dir, "old-home", empty, quiet);
  try { old.apply([row(2, "old home")], [], 0); } finally { old.close(); }
  let home = "new-home", version = 1;
  const next = workspaceIndex(dir, home, () => true, () => version, empty, quiet);
  try {
    assert.equal(next.stats.taskTitle("1"), "");
    assert.equal(next.stats.taskTitle("2"), "");
    next.stats.apply([row(3, "new home")], [], 0);
  } finally { next.stats.close(); }
  home = "old-home"; version++;
  const reopened = workspaceIndex(dir, home, () => true, () => version, empty, quiet);
  try {
    assert.equal(reopened.stats.taskTitle("2"), "old home");
    assert.equal(reopened.stats.taskTitle("3"), "");
  } finally { reopened.stats.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("different workspace strings do not share an index when UTF-8 would replace a surrogate", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-home-keys-"));
  const first = CommaStats.inWorkspace(dir, "workspace-\ud800", empty, quiet);
  const second = CommaStats.inWorkspace(dir, "workspace-\ufffd", empty, quiet);
  try {
    first.apply([row(1, "only first")], [], 0);
    assert.equal(second.taskTitle("1"), "");
  } finally { first.close(); second.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a read spanning a home change is discarded, even if that home returns", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-home-read-"));
  let home = "one", version = 0, calls = 0;
  let release!: (value: { stations: StationRows[]; unread: string[] }) => void;
  const pending = new Promise<{ stations: StationRows[]; unread: string[] }>((resolve) => { release = resolve; });
  const index = workspaceIndex(dir, "one", () => home === "one", () => version,
    async () => ++calls === 1 ? pending : { stations: [row(1, "current")], unread: [] }, quiet);
  const written: string[] = [];
  const stop = index.stats.tasks.listen(() => written.push(index.stats.taskTitle("1")));
  try {
    index.indexes.start();
    home = "two"; version++;
    home = "one"; version++;
    index.indexes.start();
    release({ stations: [row(1, "obsolete")], unread: [] });
    await index.stats.settled();
    assert.deepEqual(written, ["current"]);
    assert.equal(index.stats.taskTitle("1"), "current");
  } finally { release({ stations: [], unread: [] }); stop(); index.stats.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a home change during bounded index preparation discards the old build", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-home-prepare-"));
  let home = "one", version = 0, read = false;
  const index = workspaceIndex(dir, "one", () => home === "one", () => version,
    async () => { read = true; return { stations: [row(9, "obsolete")], unread: [] }; }, quiet);
  try {
    const usage = Array.from({ length: 512 }, (_, i) => ({ day: "9999-12-31", session: `s${i}`, runtime: "test", calls: 1 }));
    index.stats.apply([{ usage: { rows: usage }, chats: row(1, "kept").chats }], [], 0);
    index.indexes.start();
    await new Promise<void>((resolve) => setImmediate(() => { assert.ok(read); home = "two"; version++; resolve(); }));
    await index.stats.settled();
    assert.equal(index.stats.taskTitle("1"), "kept");
    assert.equal(index.stats.taskTitle("9"), "");
  } finally { index.stats.close(); rmSync(dir, { recursive: true, force: true }); }
});

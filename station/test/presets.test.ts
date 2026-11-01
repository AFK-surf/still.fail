// Presets (src/sessions/presets.ts, docs/presets.md): what a chat starts knowing, chosen as it is opened, kept with it.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { RepoIndex, candidates, presetCopyOf, presetInput, repoName } from "../src/sessions/presets.ts";
import { newSession, say as sayIn } from "../src/sessions/lifecycle.ts";
import { Rig, settle } from "./hub-fakes.ts";

/// A clone at `dir/name` of `origin`, with worktrees in the chats `sessions` (their session workspaces').
function clone(dir: string, name: string, origin: string, sessions: string[] = []): string {
  const path = join(dir, name);
  mkdirSync(join(path, ".git"), { recursive: true });
  writeFileSync(join(path, ".git", "config"), `[core]\n\tbare = false\n[remote "origin"]\n\turl = ${origin}\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n`);
  for (const [i, s] of sessions.entries()) {
    mkdirSync(join(path, ".git", "worktrees", `w${i}`), { recursive: true });
    writeFileSync(join(path, ".git", "worktrees", `w${i}`, "gitdir"), `/data/sessions/ember/${s}/workspace/${name}/.git\n`);
  }
  return path;
}

test("a chat opened with a preset is told its directories and instructions, and keeps them as they were", async () => {
  const r = new Rig();
  const repos = mkdtempSync(join(tmpdir(), "presets-"));
  const app = clone(repos, "app", "git@github.com:acme/app.git");
  const docs = join(repos, "docs");
  mkdirSync(docs);
  const preset = r.hub.presets.add(null, { name: "App work", dirs: [app, docs], instructions: "Screenshots before merging." }, "local");
  assert.deepEqual(preset.dirs, [{ path: app, repo: "github.com/acme/app" }, { path: docs, repo: null }]);

  const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "local", preset: preset.id });
  sayIn(r.hub, thread.id, "local", "fix the login page");
  await settle();
  const opened = r.claude.last().options;
  assert.ok(opened.instructions.includes(`opened with the preset "App work"`), opened.instructions);
  assert.ok(opened.instructions.includes(`${app} (a clone of github.com/acme/app`), opened.instructions);
  assert.ok(opened.instructions.includes(`  - ${docs}\n`), opened.instructions);
  assert.ok(opened.instructions.includes("<preset-instructions>\nScreenshots before merging.\n</preset-instructions>"), opened.instructions);
  assert.deepEqual(opened.dirs, [app, docs]);
  assert.equal(opened.cwd, r.session(key).workspace, "it still runs in its own workspace");

  // Changed later: the chat opened before keeps what it was opened with; a new one has it as it is now.
  r.hub.presets.put(null, preset.id, { name: "App work", dirs: [docs], instructions: "" });
  r.claude.last().complete();
  await settle();
  const [, second] = newSession(r.hub, { runtime: "claude", createdBy: "local", preset: preset.id });
  sayIn(r.hub, second.id, "local", "and the docs");
  await settle();
  const now = r.claude.last().options;
  assert.deepEqual(now.dirs, [docs]);
  assert.ok(!now.instructions.includes("<preset-instructions>"), now.instructions);
  assert.equal(r.hub.presets.list(null).length, 1);
  assert.deepEqual(presetCopyOf(r.session(key).workspace)?.dirs.map((d) => d.path), [app, docs], "the first chat keeps what it was opened with");
  await r.close();
});

test("a chat with no preset is told of none, and one naming no preset of its workspace is not made", async () => {
  const r = new Rig();
  const [, thread] = newSession(r.hub, { runtime: "claude", createdBy: "local" });
  sayIn(r.hub, thread.id, "local", "hi");
  await settle();
  assert.ok(!r.claude.last().options.instructions.includes("preset"));
  assert.equal(r.claude.last().options.dirs, undefined);
  const before = r.store.listSessions().length;
  assert.throws(() => newSession(r.hub, { runtime: "claude", createdBy: "local", preset: "p-none" }), /no preset p-none/);
  assert.equal(r.store.listSessions().length, before);
  await r.close();
});

test("a preset is a name and directories of this station", () => {
  const dir = mkdtempSync(join(tmpdir(), "presets-"));
  assert.throws(() => presetInput({ name: " ", dirs: [dir] }), /needs a name/);
  assert.throws(() => presetInput({ name: "x", dirs: [join(dir, "gone")] }), /no directory on this station/);
  assert.deepEqual(presetInput({ name: " x ", dirs: [dir, { path: dir }] }), { name: "x", dirs: [{ path: dir, repo: null }], instructions: "" });
  assert.equal(repoName("https://github.com/acme/app.git"), "github.com/acme/app");
  assert.equal(repoName("git@github.com:acme/app.git"), "github.com/acme/app");
});

test("the directories offered are the station's clones, those its chats worked in most first", async () => {
  const repos = mkdtempSync(join(tmpdir(), "presets-"));
  clone(repos, "lib", "https://github.com/acme/lib.git", ["c-1"]);
  clone(repos, "app", "https://github.com/acme/app.git", ["c-1", "c-2", "c-2"]);
  mkdirSync(join(repos, "not-a-clone"));
  const elsewhere = mkdtempSync(join(tmpdir(), "presets-"));
  const offered = await candidates(repos, [{ id: "p", name: "p", dirs: [{ path: elsewhere, repo: null }], instructions: "", createdBy: "", createdAt: 0, updatedAt: 0 }]);
  assert.deepEqual(offered.map((c) => [c.name, c.repo, c.chats]), [["app", "github.com/acme/app", 2], ["lib", "github.com/acme/lib", 1], [elsewhere.split("/").pop(), null, 0]]);
});

test("the repositories on the machine are found under its home, a few levels down, kept and offered after the cache's", async () => {
  const home = mkdtempSync(join(tmpdir(), "presets-home-"));
  clone(join(home, "code"), "app", "git@github.com:acme/app.git");
  clone(join(home, "code", "app", "sub"), "inner", "https://github.com/acme/inner.git");
  clone(join(home, "a", "b", "c"), "deep", "https://github.com/acme/deep.git");
  clone(join(home, "a", "b", "c", "d"), "deeper", "https://github.com/acme/deeper.git");
  clone(join(home, "code", "node_modules"), "dep", "https://github.com/acme/dep.git");
  clone(join(home, "Documents"), "asked", "https://github.com/acme/asked.git");
  clone(join(home, ".hidden"), "x", "https://github.com/acme/x.git");
  const data = join(home, "station");
  clone(join(data, "repos"), "cached", "https://github.com/acme/cached.git", ["c-1"]);
  let now = 1_000;
  const index = new RepoIndex({ roots: () => [home], file: () => join(home, "index.json"), now: () => now, besides: () => [data] });
  const found = await index.repos();
  // a clone's own tree is not looked into; nor what is too deep, what holds dependencies, what macOS asks before
  // reading, hidden directories and the station's own data
  assert.deepEqual(found.map((c) => [c.name, c.repo]).sort(), [["app", "github.com/acme/app"], ["deep", "github.com/acme/deep"]]);
  const offered = await candidates(join(data, "repos"), [], found);
  assert.equal(offered[0]!.name, "cached", "the cache's clone its chats worked in first");
  assert.deepEqual(offered.slice(1).map((c) => c.name).sort(), ["app", "deep"]);
  // kept: another index reads what the first found without walking again
  clone(join(home, "code"), "later", "https://github.com/acme/later.git");
  const again = new RepoIndex({ roots: () => [home], file: () => join(home, "index.json"), now: () => now, besides: () => [data] });
  assert.deepEqual((await again.repos()).map((c) => c.name).sort(), ["app", "deep"]);
  // old: what is held is answered, a new pass found the new one
  now += 11 * 60 * 1000;
  assert.deepEqual((await again.repos()).map((c) => c.name).sort(), ["app", "deep"]);
  await again.walk();
  assert.deepEqual((await again.repos()).map((c) => c.name).sort(), ["app", "deep", "later"]);
});

// Cold storage through the hub (the Rust station's hub/tests.rs: archiving compresses owned history and restores it before
// resuming, cleans what can be made again, keeps running jobs and shared projects, the auto-archive timer does not sweep;
// a session archived long enough keeps only its history and the files sent in its chat).
import assert from "node:assert/strict";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { packed, workspaceArchive, workspaceFile } from "../src/sessions/archive.ts";
import { ColdRooms } from "../src/sessions/cold.ts";
import { sessionKey } from "../src/sessions/hub.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { archive, autoArchive, deleteSession, expireArchived } from "../src/sessions/lifecycle.ts";
import { TranscriptTail } from "../src/sessions/live.ts";
import { writeCompressed } from "../src/store/archive.ts";
import { MANUAL } from "../src/store/store.ts";
import { Rig, message, reply, settle } from "./hub-fakes.ts";

/// A rig whose hub keeps archived sessions cold, as the station's does.
function coldRig(): [Rig, ColdRooms] {
  let r!: Rig;
  const cold = new ColdRooms(() => r.hub);
  r = new Rig({ cold });
  return [r, cold];
}

function transcriptOf(r: Rig, key: string, text: string): string {
  const path = join(r.config.profiles[0]!.home, "projects", "x", `${r.session(key).runtimeSessionId}.jsonl`);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
  return path;
}

/// hub.rs `finish_archive`: the archive operation already asked for, waited on.
async function finishArchive(r: Rig, key: string) {
  const actor = r.hub.actor(r.session(key));
  await actor.evict();
  await actor.cleanArchive();
}

/// A session whose turn has ended (it said final).
async function idleSession(r: Rig) {
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await r.call(key, "chat_state", { kind: "final" });
  r.claude.last().complete();
  await settle();
  return { m, key };
}

test("archiving a session compresses owned history and restores it before resuming", async () => {
  const [r] = coldRig();
  const { m, key } = await idleSession(r);
  const transcript = transcriptOf(r, key, '{"type":"user","message":{"content":"history"}}\n');
  const workspace = r.session(key).workspace;
  writeFileSync(join(workspace, "uncommitted.txt"), "keep this");
  // A key is no file name on Windows (its `:`): no station there ever left this legacy copy.
  const legacy = process.platform !== "win32";
  const copy = join(r.store.archiveDir(), "transcripts", `${key}.jsonl.zst`);
  if (legacy) writeCompressed(copy, "old redundant copy");
  await archive(r.hub, key, true);
  await finishArchive(r, key);
  assert.ok(!existsSync(transcript), "compression replaces the original rather than adding another copy");
  assert.ok(existsSync(packed(transcript)));
  if (legacy) assert.ok(!existsSync(copy), "legacy redundant copy removed only after successful compression");
  assert.equal(new TranscriptTail("claude", transcript).read()[1][0]!.text, "history");
  assert.ok(!existsSync(join(workspace, "uncommitted.txt")));
  assert.ok(existsSync(workspaceArchive(dirname(workspace))));
  assert.ok(existsSync(join(dirname(workspace), "cold")));
  assert.ok(r.hub.cold.isCold(key));
  await r.accept(reply(m, "9999.9", "<@UBOT> continue", { addressed: true }));
  await r.hub.actor(r.session(key)).warm();
  assert.ok(existsSync(transcript), "new input restores runtime history before opening the agent");
  assert.equal(readFileSync(join(workspace, "uncommitted.txt"), "utf8"), "keep this");
  assert.ok(!existsSync(workspaceArchive(dirname(workspace))));
  assert.ok(!existsSync(join(dirname(workspace), "cold")));
  assert.ok(!r.hub.cold.isCold(key));
  await r.close();
});

test("archiving a session cleans what can be made again from its directory", async () => {
  const [r, cold] = coldRig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const workspace = r.session(key).workspace;
  mkdirSync(join(workspace, "app/node_modules/x"), { recursive: true });
  writeFileSync(join(workspace, "app/node_modules/x/index.js"), Buffer.alloc(50_000, 1));
  writeFileSync(join(workspace, "notes.md"), "kept");
  assert.equal(await cold.cleanRebuildable(key), 0, "not while in the lists");
  await archive(r.hub, key, true);
  await settle();
  assert.equal(await cold.cleanRebuildable(key), 0, "not while at work");
  assert.ok(existsSync(join(workspace, "app/node_modules")));
  await r.call(key, "chat_state", { kind: "final" });
  r.claude.last().complete();
  await settle();
  await archive(r.hub, key, false);
  await archive(r.hub, key, true);
  // Cleaned once archived (in the background, on the file system: looked at every 10 ms, no deadline).
  while (existsSync(join(workspace, "app/node_modules"))) await new Promise((res) => setTimeout(res, 10));
  await finishArchive(r, key);
  assert.deepEqual(await workspaceFile(dirname(workspace), "notes.md"), Buffer.from("kept"));
  await archive(r.hub, key, false);
  assert.equal(readFileSync(join(workspace, "notes.md"), "utf8"), "kept");
  await r.close();
});

test("archive cleanup keeps running jobs and shared projects", async () => {
  const [r] = coldRig();
  const { key } = await idleSession(r);
  const workspace = r.session(key).workspace;
  mkdirSync(join(workspace, "app/node_modules"), { recursive: true });
  writeFileSync(join(workspace, "app/node_modules/dependency.js"), Buffer.alloc(50_000, 1));
  writeFileSync(join(workspace, "unfinished.rs"), "uncommitted work");
  // The archive operation is deferred while another task still needs these files.
  r.store.setArchived(key, true, MANUAL);
  const job = {
    id: "archive_job", sessionKey: "another-session", name: "preview", command: "serve", cwd: join(workspace, "app"), port: 9123,
    token: "archive_job_token", state: "running", pgid: null, exitCode: null, startedAt: Date.now(), endedAt: null, restarts: 0,
    log: "/dev/null", watch: false,
  };
  r.store.insertJob(job);
  await finishArchive(r, key);
  assert.ok(existsSync(join(workspace, "app/node_modules")), "another session's service uses this directory");
  r.store.jobEnded(job.id, "exited", 1);
  await finishArchive(r, key);
  assert.ok(existsSync(join(workspace, "app/node_modules")), "a service waiting to restart still needs its files");
  r.store.jobEnded(job.id, "stopped", null);
  r.store.insertSession({
    key: "shared_archive_project", connect: "cl", runtime: "claude", profile: "cc", token: "shared_archive_token", workspace: r.dir,
    cwd: join(workspace, "app"), createdAt: Date.now(), lastActiveAt: Date.now(),
  });
  await finishArchive(r, key);
  assert.ok(existsSync(join(workspace, "app/node_modules")), "another session is working inside the archived directory");
  r.store.deleteSession("shared_archive_project");
  await finishArchive(r, key);
  assert.ok(!existsSync(join(workspace, "app/node_modules")), "old archive cleaned after the job stops");
  assert.deepEqual(await workspaceFile(dirname(workspace), "unfinished.rs"), Buffer.from("uncommitted work"));
  await finishArchive(r, key);
  await archive(r.hub, key, false);
  assert.equal(readFileSync(join(workspace, "unfinished.rs"), "utf8"), "uncommitted work");
  mkdirSync(join(workspace, "app/node_modules"), { recursive: true });
  await finishArchive(r, key);
  assert.ok(existsSync(join(workspace, "app/node_modules")), "restored sessions are left alone");
  await r.close();
});

test("the auto-archive timer does not sweep previously archived workspaces", async () => {
  const [r] = coldRig();
  const { key } = await idleSession(r);
  const workspace = r.session(key).workspace;
  mkdirSync(join(workspace, "node_modules"), { recursive: true });
  writeFileSync(join(workspace, "source.rs"), "old archive");
  r.store.setArchived(key, true, MANUAL);
  autoArchive(r.hub, Date.now() + 3 * 86_400_000);
  await settle();
  assert.ok(existsSync(join(workspace, "node_modules")), "a timer must not clean old archives");
  assert.ok(existsSync(join(workspace, "source.rs")));
  assert.ok(!existsSync(workspaceArchive(dirname(workspace))));
  await archive(r.hub, key, true);
  await finishArchive(r, key);
  assert.ok(!existsSync(join(workspace, "node_modules")), "an explicit archive does clean");
  assert.ok(existsSync(workspaceArchive(dirname(workspace))));
  await r.close();
});

test("the Rust station's transcript copies are let go once the transcripts are packed, the workspace left as it is", { skip: process.platform === "win32" && "no station there ever left these copies" }, async () => {
  const [r, cold] = coldRig();
  const { key } = await idleSession(r);
  const workspace = r.session(key).workspace;
  mkdirSync(join(workspace, "node_modules"), { recursive: true });
  writeFileSync(join(workspace, "source.rs"), "old archive");
  const transcript = transcriptOf(r, key, '{"type":"user","message":{"content":"history"}}\n');
  // Archived by the Rust station: its copy made, the transcript and the workspace left as they were.
  const copy = join(r.store.archiveDir(), "transcripts", `${key}.jsonl.zst`);
  writeCompressed(copy, "old redundant copy");
  r.store.setArchived(key, true, MANUAL);
  // A copy whose session is back in the lists stays.
  const { key: shown } = await idleSession(r);
  const shownCopy = join(r.store.archiveDir(), "transcripts", `${shown}.jsonl.zst`);
  writeCompressed(shownCopy, "another copy");
  await cold.finishLegacyCopies();
  assert.ok(!existsSync(transcript) && existsSync(packed(transcript)), "the transcript packed in place");
  assert.equal(new TranscriptTail("claude", transcript).read()[1][0]!.text, "history");
  assert.ok(!existsSync(copy), "its copy let go");
  assert.ok(existsSync(shownCopy));
  assert.ok(existsSync(join(workspace, "node_modules")) && existsSync(join(workspace, "source.rs")), "the workspace left as it is");
  assert.ok(!existsSync(workspaceArchive(dirname(workspace))));
  await r.close();
});

test("deleting an archived session lets go of the git worktrees it locked and removes its directory", async () => {
  const [r] = coldRig();
  const { key } = await idleSession(r);
  const workspace = r.session(key).workspace;
  const gitdir = join(r.dir, "repo.git", "worktrees", "project");
  mkdirSync(gitdir, { recursive: true });
  mkdirSync(join(workspace, "project"));
  writeFileSync(join(workspace, "project", ".git"), `gitdir: ${gitdir}\n`);
  await archive(r.hub, key, true);
  await finishArchive(r, key);
  assert.ok(existsSync(join(gitdir, "locked")));
  await deleteSession(r.hub, key);
  assert.ok(!existsSync(join(gitdir, "locked")));
  assert.ok(!existsSync(dirname(workspace)));
  await r.close();
});

const DAY = 86_400_000;

/// An idle session archived and packed, with work of its own, a file sent in its chat and a git worktree.
async function packedSession(r: Rig) {
  const { m, key } = await idleSession(r);
  const transcript = transcriptOf(r, key, '{"type":"user","message":{"content":"history"}}\n');
  const workspace = r.session(key).workspace;
  mkdirSync(join(workspace, "uploads"), { recursive: true });
  writeFileSync(join(workspace, "uploads", "shot.png"), "a picture");
  mkdirSync(join(workspace, "app", "src"), { recursive: true });
  writeFileSync(join(workspace, "app", "src", "main.rs"), "work");
  const gitdir = join(r.dir, "repo.git", "worktrees", "project");
  mkdirSync(gitdir, { recursive: true });
  mkdirSync(join(workspace, "project"));
  writeFileSync(join(workspace, "project", ".git"), `gitdir: ${gitdir}\n`);
  await archive(r.hub, key, true);
  await finishArchive(r, key);
  assert.ok(existsSync(workspaceArchive(dirname(workspace))));
  assert.ok(existsSync(join(gitdir, "locked")));
  return { m, key, workspace, transcript, gitdir };
}

test("a session archived long enough keeps only its history and the files sent in its chat", async () => {
  const [r] = coldRig();
  const { m, key, workspace, transcript, gitdir } = await packedSession(r);
  const archivedAt = r.session(key).archivedAt!;
  assert.equal(await expireArchived(r.hub, archivedAt + 6 * DAY), archivedAt + 7 * DAY, "not yet: it comes due a week after");
  assert.ok(existsSync(workspaceArchive(dirname(workspace))));
  assert.equal(await expireArchived(r.hub, archivedAt + 7 * DAY), null);
  assert.ok(!existsSync(workspaceArchive(dirname(workspace))), "its workspace's archive is gone");
  assert.deepEqual(readdirSync(workspace), ["uploads"]);
  assert.equal(readFileSync(join(workspace, "uploads", "shot.png"), "utf8"), "a picture", "the files sent in its chat are on the disk again");
  assert.ok(!existsSync(join(gitdir, "locked")), "its worktrees are let go");
  assert.ok(existsSync(packed(transcript)), "its history stays");
  assert.ok(r.hub.cold.isCold(key));
  // Nothing left to do the next time.
  assert.equal(await r.hub.cold.holdsMore!(key), false);
  // Brought back, it goes on in its history, with the files of its chat.
  await r.accept(reply(m, "9999.9", "<@UBOT> continue", { addressed: true }));
  await r.hub.actor(r.session(key)).warm();
  assert.ok(existsSync(transcript));
  assert.equal(readFileSync(join(workspace, "uploads", "shot.png"), "utf8"), "a picture");
  assert.ok(!existsSync(join(workspace, "app")));
  await r.close();
});

test("a workspace archived long enough is emptied even when it was never packed, and one shown again is not", async () => {
  const [r, cold] = coldRig();
  const { key, workspace } = await packedSession(r);
  await archive(r.hub, key, false);
  assert.ok(existsSync(join(workspace, "app", "src", "main.rs")));
  const shownAt = Date.now();
  await expireArchived(r.hub, shownAt + 30 * DAY);
  assert.ok(existsSync(join(workspace, "app", "src", "main.rs")), "shown again, it is not archived");
  // Archived again, and left unpacked (as when packing could not finish): emptied all the same once due.
  r.store.setArchived(key, true, MANUAL);
  writeFileSync(join(dirname(workspace), "cold"), "workspace and history may be compressed\n");
  const archivedAt = r.session(key).archivedAt!;
  await cold.expire(key, archivedAt - 1);
  assert.ok(existsSync(join(workspace, "app")), "archived after the cutoff: not yet");
  await expireArchived(r.hub, archivedAt + 7 * DAY);
  assert.deepEqual(readdirSync(workspace), ["uploads"]);
  await r.close();
});

test("archivedWorkspaceDays 0 keeps archived workspaces", async () => {
  const [r] = coldRig();
  const { key, workspace } = await packedSession(r);
  r.config = hubConfig({ ...r.raw, archivedWorkspaceDays: 0 }, r.dir);
  assert.equal(await expireArchived(r.hub, r.session(key).archivedAt! + 365 * DAY), null);
  assert.ok(existsSync(workspaceArchive(dirname(workspace))));
  assert.deepEqual(await workspaceFile(dirname(workspace), "app/src/main.rs"), Buffer.from("work"));
  await r.close();
});

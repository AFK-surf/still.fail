import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { installWorkspaceUpJobs, workspaceUpJobsReady } from "../src/store/workspace-up-jobs.ts";
import { Store } from "../src/store/store.ts";

test("a job list answers during handover and prepares the old workspace lookup once", async () => {
  const dir = mkdtempSync(join(tmpdir(), "workspace-up-reader-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const preparing = Promise.withResolvers<void>(), prepared = Promise.withResolvers<void>();
  void prepared.promise.catch(() => {});
  const prepare = readers.prepareWorkspaceUpJobs.bind(readers);
  let calls = 0;
  readers.prepareWorkspaceUpJobs = (signal) => {
    calls++; preparing.resolve();
    const pending = prepare(signal);
    void pending.then(() => prepared.resolve(), prepared.reject);
    return pending;
  };
  try {
    const triggers = store.db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'workspace_up_%'")
      .all() as Array<{ name: string }>;
    for (const { name } of triggers) store.db.exec(`DROP TRIGGER ${name}`);
    store.db.exec("DROP TABLE workspace_up_session_replaced; DROP TABLE workspace_up_sessions; DROP TABLE workspace_up_meta");
    for (const [key, ws] of [["mine", "A"], ["other", "B"]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
        token: key, ws, createdAt: 1, lastActiveAt: 1 });
      store.insertJob({ id: `job-${key}`, sessionKey: key, name: "job", command: "true", cwd: "/", port: null,
        token: `job-token-${key}`, state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null,
        restarts: 0, log: "/dev/null", watch: false });
    }
    store.db.exec("DELETE FROM session_up_job_rows; UPDATE session_up_job_meta SET fresh=0");
    installWorkspaceUpJobs(store.db);
    const viewer = { sub: "u", email: "u@example.com", name: "U", role: "owner", workspace: "A", device: "d", home: false };
    const args = { viewer, chats: false };
    const answer = JSON.parse(await readers.read("openJobs", args, "en"));
    assert.deepEqual(answer.map((j: { id: string }) => j.id), ["job-mine"]);
    await preparing.promise;
    assert.equal(workspaceUpJobsReady(store.db), false);
    assert.deepEqual(JSON.parse(await readers.read("openJobs", args, "en")), answer);
    assert.equal(calls, 1);
    previous.resolve(); await prepared.promise;
    assert.equal(workspaceUpJobsReady(store.db), true);
    assert.deepEqual(JSON.parse(await readers.read("openJobs", args, "en")), answer);
    assert.equal(calls, 1);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

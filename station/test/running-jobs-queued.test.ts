// A task still in the queue has not started: what other stations are told of this one's load leaves it out (#4355).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

test("queued remote tasks are not counted as running", () => {
  const store = Store.open(":memory:");
  try {
    const job = (id: string, queued: boolean) => ({
      id, sessionKey: "remote:w:s:k", name: id, command: "true", cwd: "/", port: null, token: id, state: "running" as const,
      pgid: null, exitCode: null, startedAt: store.now(), endedAt: null, restarts: 0, log: "/dev/null", watch: false,
      ...(queued ? { queued: true, screen: false } : {}),
    });
    store.insertJob(job("remote_a", false));
    store.insertJob(job("remote_b", true));
    store.insertJob({ ...job("local", false), sessionKey: "mine" });
    assert.deepEqual(store.runningJobs(), { remote: 1, jobs: 1, services: 0 });
  } finally { store.close(); }
});

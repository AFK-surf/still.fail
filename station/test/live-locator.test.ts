import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { transcriptSources } from "../src/read/transcript.ts";
import { LiveLocator } from "../src/sessions/live-locator.ts";
import { Store } from "../src/store/store.ts";

test("the live locator reads a session's ordered sources in a worker and can be cancelled", async () => {
  const data = mkdtempSync(join(tmpdir(), "live-locator-")), store = Store.open(join(data, "stillfail.db"));
  const profiles = [{ id: "cc", home: join(data, "home") }];
  const locator = new LiveLocator(data, (key) => store.getSession(key), () => profiles);
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const put = store.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    store.db.exec("BEGIN");
    for (let i = 0; i < 131; i++) put.run("one", `source-${i}`, "cc", i, "claude");
    store.setRuntimeSessionId("one", "source-130");
    store.db.exec("COMMIT");
    for (const id of ["source-0", "source-64", "source-130"]) {
      const path = join(data, "transcripts", "claude", "-w", `${id}.jsonl`);
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, "");
    }
    const expected = transcriptSources(data, profiles, store.runtimeSessionSources("one"), ["/w"], { anywhere: false });
    assert.deepEqual(await locator.locate("one"), { runtime: "claude", ...expected });

    const stop = new AbortController();
    const cancelled = locator.locate("one", stop.signal);
    stop.abort();
    await assert.rejects(cancelled, /cancelled/);
    assert.deepEqual(await locator.locate("one"), { runtime: "claude", ...expected }, "a cancelled worker does not strand later requests");
  } finally {
    await locator.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("the live locator uses the current session when it changes while the worker starts", async () => {
  const data = mkdtempSync(join(tmpdir(), "live-locator-")), store = Store.open(join(data, "stillfail.db"));
  const profiles: { id: string; home: string }[] = [];
  const locator = new LiveLocator(data, (key) => store.getSession(key), () => profiles);
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    store.setRuntimeSessionId("one", "old");
    const path = join(data, "transcripts", "claude", "-w", "new.jsonl");
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, "");
    const locating = locator.locate("one");
    store.setRuntimeSessionId("one", "new");
    assert.deepEqual(await locating, { runtime: "claude", paths: [{ path, runtime: "claude" }], current: true });
  } finally {
    await locator.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("a location is retried if its session changes after the worker takes its snapshot", async () => {
  const data = mkdtempSync(join(tmpdir(), "live-locator-")), store = Store.open(join(data, "stillfail.db"));
  let change = true;
  const locator = new LiveLocator(data, (key) => {
    if (change) { change = false; store.setRuntimeSessionId(key, "new"); }
    return store.getSession(key);
  }, () => []);
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    store.setRuntimeSessionId("one", "old");
    const path = join(data, "transcripts", "claude", "-w", "new.jsonl");
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, "");
    assert.deepEqual(await locator.locate("one"), { runtime: "claude", paths: [{ path, runtime: "claude" }], current: true });
    assert.equal(change, false);
  } finally {
    await locator.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("a session replaced under the same key cannot receive its predecessor's paths", async () => {
  const data = mkdtempSync(join(tmpdir(), "live-locator-")), store = Store.open(join(data, "stillfail.db"));
  let replace = true;
  const locator = new LiveLocator(data, (key) => {
    if (replace) {
      replace = false;
      store.db.prepare("UPDATE sessions SET token=? WHERE key=?").run("replacement", key);
      store.db.prepare("DELETE FROM runtime_sessions WHERE session_key=?").run(key);
      store.ranIn(key, "new", "cc");
    }
    return store.getSession(key);
  }, () => []);
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "original", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    store.ranIn("one", "old", "cc");
    const directory = join(data, "transcripts", "claude", "-w");
    mkdirSync(directory, { recursive: true });
    for (const name of ["old", "new"]) writeFileSync(join(directory, `${name}.jsonl`), "");
    assert.deepEqual(await locator.locate("one"), { runtime: "claude", paths: [{ path: join(directory, "new.jsonl"), runtime: "claude" }], current: true });
  } finally {
    await locator.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("a short live location can finish while a longer one is being resolved", async () => {
  const data = mkdtempSync(join(tmpdir(), "live-locator-")), store = Store.open(join(data, "stillfail.db"));
  const locator = new LiveLocator(data, (key) => store.getSession(key), () => []);
  try {
    for (const [key, count] of [["large", 1025], ["small", 1]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws: "mine" });
      const put = store.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
      store.db.exec("BEGIN");
      for (let i = 0; i < count; i++) put.run(key, `${key}-${i}`, "cc", i, "claude");
      store.setRuntimeSessionId(key, `${key}-${count - 1}`);
      store.db.exec("COMMIT");
      const path = join(data, "transcripts", "claude", "-w", `${key}-${count - 1}.jsonl`);
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, "");
    }
    const smallPath = join(data, "transcripts", "claude", "-w", "small-0.jsonl");
    await locator.locate("small"); // Start the worker before comparing requests.
    const order: string[] = [];
    const large = locator.locate("large").then((value) => { order.push("large"); return value; });
    const small = locator.locate("small").then((value) => { order.push("small"); return value; });
    const [largeResult, smallResult] = await Promise.all([large, small]);
    assert.deepEqual(order, ["small", "large"]);
    assert.equal(largeResult?.current, true);
    assert.deepEqual(smallResult, { runtime: "claude", paths: [{ path: smallPath, runtime: "claude" }], current: true });
    const pair = await Promise.all([locator.locate("large"), locator.locate("large")]);
    assert.deepEqual(pair, [largeResult, largeResult], "overlapping temporary snapshots stay independent");

    const stop = new AbortController();
    const stopped = locator.locate("large", stop.signal);
    const other = locator.locate("small");
    stop.abort();
    await assert.rejects(stopped, /cancelled/);
    assert.deepEqual(await other, smallResult, "cancelling one location leaves another in progress");
  } finally {
    await locator.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

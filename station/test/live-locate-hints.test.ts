import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { rememberCodexRollout, transcriptLocationHints, transcriptPaths, transcriptSources, type TranscriptLocationHints } from "../src/read/transcript.ts";

test("a live locator in another thread keeps the process's transcript path hints", async () => {
  const data = mkdtempSync(join(tmpdir(), "live-hints-")), home = join(data, "home"), shared = join(data, "transcripts", "codex");
  const reported = join(home, "sessions", "2026", "11", "rollout-reported-hint-test.jsonl");
  const path = join(shared, "2026", "11", "rollout-reported-hint-test.jsonl");
  const moved = join(shared, "2026", "11", "rollout-moved-hint-test.jsonl");
  const profiles = [{ id: "cx", home }], sources = [{ id: "hint-test", runtime: "codex", profile: "cx" }], places = ["/w"];
  mkdirSync(dirname(path), { recursive: true });
  mkdirSync(home, { recursive: true });
  symlinkSync(shared, join(home, "sessions"), "dir");
  writeFileSync(moved, "");
  const worker = new Worker(new URL("./live-locate-hints-worker.ts", import.meta.url));
  const locate = (hints: TranscriptLocationHints) => new Promise<{ found: ReturnType<typeof transcriptSources>; hints: TranscriptLocationHints }>((resolve, reject) => {
    worker.once("message", resolve);
    worker.once("error", reject);
    worker.postMessage({ data, profiles, sources, places, hints });
  });
  try {
    assert.equal(rememberCodexRollout(home, "hint-test", reported), reported);
    let snapshot = transcriptLocationHints(data, profiles, sources);
    let result = await locate(snapshot.value);
    assert.deepEqual(result.found, { paths: [], current: false }, "an as-yet unwritten reported file is not searched for elsewhere");
    assert.equal(snapshot.merge(result.hints), true);

    writeFileSync(path, "");
    snapshot = transcriptLocationHints(data, profiles, sources);
    result = await locate(snapshot.value);
    assert.deepEqual(result.found, { paths: [{ path, runtime: "codex" }], current: true });
    assert.equal(snapshot.merge(result.hints), true);
    rmSync(path);
    snapshot = transcriptLocationHints(data, profiles, sources);
    result = await locate(snapshot.value);
    assert.deepEqual(result.found, { paths: [{ path: moved, runtime: "codex" }], current: true }, "a reported file once seen may move");
    assert.equal(snapshot.merge(result.hints), true);
    assert.deepEqual(transcriptSources(data, profiles, sources, places, { anywhere: false }), result.found);

    const stale = transcriptLocationHints(data, profiles, sources);
    const newer = join(home, "sessions", "2026", "11", "rollout-new-hint-test.jsonl");
    assert.equal(rememberCodexRollout(home, "hint-test", newer), newer);
    assert.equal(stale.merge(result.hints), false, "an older worker response cannot overwrite a new report");
    assert.deepEqual(transcriptSources(data, profiles, sources, places, { anywhere: false }), { paths: [], current: false });
  } finally {
    await worker.terminate();
    rmSync(data, { recursive: true, force: true });
  }
});

test("a worker keeps a Claude transcript previously found outside its current places", async () => {
  const data = mkdtempSync(join(tmpdir(), "live-hints-")), file = join(data, "transcripts", "claude", "other", "outside.jsonl");
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, "");
  const profiles: { id: string; home: string }[] = [], sources = [{ id: "outside", runtime: "claude", profile: null }], places = ["/w"];
  const worker = new Worker(new URL("./live-locate-hints-worker.ts", import.meta.url));
  try {
    assert.deepEqual(transcriptPaths("claude", data, [], ["outside"], places).paths, [file]);
    const snapshot = transcriptLocationHints(data, profiles, sources);
    const result = await new Promise<{ found: ReturnType<typeof transcriptSources>; hints: TranscriptLocationHints }>((resolve, reject) => {
      worker.once("message", resolve);
      worker.once("error", reject);
      worker.postMessage({ data, profiles, sources, places, hints: snapshot.value });
    });
    assert.deepEqual(result.found, { paths: [{ path: file, runtime: "claude" }], current: true });
    assert.equal(snapshot.merge(result.hints), true);
  } finally {
    await worker.terminate();
    rmSync(data, { recursive: true, force: true });
  }
});

// A session's widget state and transcript file read by the MoonBit reader (station/mb src/readops/sessions.mbt;
// read/pool.ts MOVED) as the worker reads them: states kept, not JSON, missing, a session not there; a transcript in its
// place, in a project of no place, in a profile's own home, not written yet, of a runtime session not recorded.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();
const put = (path: string) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, ""); };

test("the MoonBit reader reads a session's widget state and transcript file as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-session-files-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "own", home: "homes/own" }, { id: "abs", home: join(data, "abs") }] }));
  const session = (key: string, runtime: string, current: string | null, workspace: string, cwd: string | null = null) => {
    store.insertSession({ key, connect: "ember", runtime, profile: "own", workspace, cwd: cwd ?? undefined, token: key, createdAt: 1, lastActiveAt: 1, ws: null } as Parameters<Store["insertSession"]>[0]);
    if (current !== null) store.setRuntimeSessionId(key, current);
  };
  session("placed", "claude", "c1", "/w/placed");
  store.ranIn("placed", "c1", "own");
  put(join(data, "transcripts", "claude", "-w-placed", "c1.jsonl"));
  session("elsewhere", "claude", "c2", "/w/x", "/w/y");
  store.ranIn("elsewhere", "c2", null);
  put(join(data, "transcripts", "claude", "-some-project", "c2.jsonl"));
  session("ownhome", "codex", "x1", "/w/o");
  store.ranIn("ownhome", "x1", "own");
  put(join(data, "homes", "own", "sessions", "2026", "11", "09", "rollout-2026-11-09T00-00-00-x1.jsonl"));
  session("unwritten", "claude", "c3", "/w/u");
  store.ranIn("unwritten", "c3", "own");
  session("unrecorded", "claude", "c4", "/w/r");
  session("fresh", "claude", null, "/w/f");
  const putState = store.db.prepare("INSERT INTO widget_states (session, path, state, updated_at) VALUES (?, ?, ?, 1)");
  putState.run("placed", "a/b", JSON.stringify({ n: 1, "2": [true, null], s: "x" }));
  putState.run("placed", "", "not json");
  putState.run("placed", "dup", '{"k":1,"k":2}');
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (readers: Readers) => {
    const out: unknown[] = [];
    for (const key of ["placed", "elsewhere", "ownhome", "unwritten", "unrecorded", "fresh", "missing"]) out.push(await read(readers, "transcriptFile", { key, lang: "en" }));
    for (const [key, path] of [["placed", "a/b"], ["placed", undefined], ["placed", "dup"], ["placed", "none"], ["missing", "a/b"]] as const)
      out.push(await read(readers, "widgetState", { key, path, lang: "en" }));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["c1.jsonl", "c2.jsonl", "x1.jsonl", "\"k\":2", "unknown session missing"]) assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

// The MoonBit program in the live locator's worker's place (station/mb, src/locate; sessions/live-locator.ts) finds
// what live-locator-worker.ts finds, on the same stores and the same transcripts: each runtime's layout (Claude's
// places, reached through a link too, and a project found elsewhere by a history read; Codex's days, a rollout put
// away, one a thread said; DeepSeek Harness's versions; Grok Build's; Cursor's and the others'), homes of their own and
// homes linked to the shared place, sources past a page with the current one among them, sources of no runtime.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { rememberCodexRollout, transcriptSources } from "../src/read/transcript.ts";
import { LiveLocator } from "../src/sessions/live-locator.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

const put = (path: string) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, ""); };

test("the MoonBit live locator finds what the worker finds", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-live-locator-")), store = Store.open(join(data, "stillfail.db"));
  const own = join(data, "own-home"), linked = join(data, "linked-home"), real = join(data, "real-work");
  const profiles = [{ id: "own", home: own }, { id: "linked", home: linked }, { id: "gone", home: join(data, "no-home") }];
  const shared = (runtime: string) => join(data, "transcripts", runtime);
  mkdirSync(real, { recursive: true });
  symlinkSync(real, join(data, "work"));
  mkdirSync(linked, { recursive: true });
  mkdirSync(shared("claude"), { recursive: true });
  symlinkSync(shared("claude"), join(linked, "projects"));
  const work = join(data, "work"), project = (dir: string) => dir.replace(/[^a-zA-Z0-9]/g, "-");
  const sessions: [string, string, string | null, string][] = [];
  const session = (key: string, runtime: string, cwd: string | null, workspace: string, sources: [string, string | null, string | null][], current: string | null) => {
    store.insertSession({ key, connect: "ember", runtime, profile: "own", workspace, cwd: cwd ?? undefined, token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const row = store.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    sources.forEach(([id, rt, profile], i) => row.run(key, id, profile, i, rt));
    if (current !== null) store.setRuntimeSessionId(key, current);
    sessions.push([key, runtime, cwd, workspace]);
  };
  try {
    // Claude: in its place by the link and by the real directory, in its working directory, in a home of its own, in
    // a project of no place (found only after a history read), put away.
    put(join(shared("claude"), project(realpathSync(real)), "c-real.jsonl"));
    put(join(shared("claude"), project(work), "c-link.jsonl"));
    put(join(shared("claude"), project("/elsewhere"), "c-else.jsonl"));
    put(join(own, "projects", project(work), "c-own.jsonl"));
    put(join(shared("claude"), project(work), "c-zst.jsonl.zst"));
    put(join(shared("claude"), project("/moved"), "c-moved.jsonl"));
    session("claude", "claude", "/moved", work, [["c-real", "claude", "own"], ["c-link", null, "linked"], ["c-else", "claude", null],
      ["c-own", "claude", "own"], ["c-zst", "claude", "gone"], ["c-moved", "claude", "linked"], ["c-none", "claude", null]], "c-zst");
    transcriptSources(data, profiles, [{ id: "c-else", runtime: "claude", profile: null }], [work]);
    // Codex: by day, through a linked day, put away, said by a running thread before and after its file is there.
    put(join(shared("codex"), "2026", "11", "01", "rollout-2026-11-01T00-00-00-x-1.jsonl"));
    put(join(data, "days", "02", "rollout-2026-11-02T00-00-00-x-2.jsonl"));
    mkdirSync(join(shared("codex"), "2026", "11"), { recursive: true });
    symlinkSync(join(data, "days", "02"), join(shared("codex"), "2026", "11", "02"));
    put(join(shared("codex"), "2026", "11", "03", "rollout-2026-11-03T00-00-00-x-3.jsonl.zst"));
    put(join(own, "sessions", "2026", "10", "09", "rollout-2026-10-09T00-00-00-x-4.jsonl"));
    put(join(shared("codex"), "2026", "11", "04", "rollout-2026-11-04T00-00-00-x-5.jsonl"));
    rememberCodexRollout(data, "x-5", join(shared("codex"), "2026", "11", "04", "rollout-2026-11-04T00-00-00-x-5.jsonl"));
    rememberCodexRollout(own, "x-6", join(own, "sessions", "2026", "11", "05", "rollout-2026-11-05T00-00-00-x-6.jsonl"));
    session("codex", "codex", null, "/w", [["x-1", null, null], ["x-2", "codex", "own"], ["x-3", "codex", null], ["x-4", "codex", "own"],
      ["x-5", "codex", null], ["x-6", "codex", "own"]], "x-6");
    // DeepSeek Harness's versions, Grok Build's directories, Cursor's, Devin's, Hermes', Antigravity's, one of no runtime.
    for (const v of ["2", "10", "010", "9"]) put(join(shared("dsh"), "-w", "d-1", `session.v${v}.jsonl`));
    put(join(shared("dsh"), "-w", "d-1", "session.vx.jsonl"));
    put(join(shared("grok"), "-w", "g-1", "chat_history.jsonl.zst"));
    for (const rt of ["cursor", "devin", "hermes", "agy"]) put(join(shared(rt), `${rt}-1.jsonl`));
    put(join(own, "cursor", "sessions", "cursor-2.jsonl"));
    session("mixed", "dsh", "/w", "/w", [["d-1", "dsh", null], ["g-1", "grok", null], ["cursor-1", "cursor", null], ["cursor-2", "cursor", "own"],
      ["devin-1", "devin", null], ["hermes-1", "hermes", null], ["agy-1", "agy", null], ["u-1", "unknown", null]], "agy-1");
    // Past a page of sources, the current one among them.
    const many: [string, string | null, string | null][] = [];
    for (let i = 0; i < 140; i++) many.push([i === 7 ? "m-current" : `m-${i}`, "claude", null]);
    for (const id of ["m-0", "m-64", "m-128", "m-current"]) put(join(shared("claude"), project("/w"), `${id}.jsonl`));
    session("many", "claude", null, "/w", many, "m-current");
    session("unknown", "unknown", null, "/w", [["u-2", "claude", null]], "u-2");
    session("empty", "claude", null, "/w", [], null);

    const worker = new LiveLocator(data, (key) => store.getSession(key), () => profiles, new URL("../src/sessions/live-locator-worker.ts", import.meta.url));
    const program = new LiveLocator(data, (key) => store.getSession(key), () => profiles);
    try {
      for (const [key] of [...sessions, ["missing"]]) {
        const before = await worker.locate(key!);
        const found = await program.locate(key!);
        assert.deepEqual(found, before, key);
        if (key === "claude") assert.ok(found?.paths.some((p) => p.path.endsWith("c-real.jsonl")), "found by the real directory");
        assert.deepEqual(await worker.locate(key!), found, `${key} again`);
      }
      const all = await Promise.all(sessions.map(([key]) => program.locate(key)));
      assert.deepEqual(all, await Promise.all(sessions.map(([key]) => worker.locate(key))), "several at once");
      assert.ok(all.every((l, i) => sessions[i]![0] === "unknown" || sessions[i]![0] === "empty" || (l?.paths.length ?? 0) > 0), "each finds some");
    } finally {
      await worker.close();
      await program.close();
    }
  } finally {
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

import assert from "node:assert/strict";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { classifyResult } from "../src/agents/claude.ts";
import { Rig, message, settle } from "./hub-fakes.ts";

test("switching accounts looks up only the runtime source it is leaving", async () => {
  const rig = new Rig();
  try {
    rig.edit((raw) => { raw.profiles[0].models = ["opus"]; raw.profiles.push({ ...raw.profiles[0], id: "cc2", name: "second" }); });
    await rig.accept(message());
    await settle();
    const first = rig.claude.last(), key = first.options.route;
    const db = rig.store.db, put = db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    db.exec("BEGIN");
    for (let i = 0; i < 513; i++) put.run(key, `old-${i}`, "cc", i, "claude");
    db.exec("COMMIT");
    const original = rig.store.runtimeSessionSources.bind(rig.store);
    let visited = 0;
    rig.store.runtimeSessionSources = (session) => { const sources = original(session); visited += sources.length; return sources; };
    const moved = rig.hub.live.moved.bind(rig.hub.live);
    let beforeMove: number | undefined;
    rig.hub.live.moved = (session) => { beforeMove = visited; moved(session); };
    // Ending the first turn also asks the live view to find its transcripts (read off the main thread, before the turn
    // is said to be over). Measure the later account switch itself.
    const ended = rig.hub.live.turnEnded.bind(rig.hub.live);
    rig.hub.live.turnEnded = (session) => ended(session).then(() => { visited = 0; });
    first.end({ kind: "failed", reason: classifyResult("usage limit reached"), message: "usage limit reached" });
    await settle();
    const second = rig.claude.last();
    assert.notEqual(second.options.profile.id, first.options.profile.id);
    assert.notEqual(second.id(), first.id());
    assert.notEqual(beforeMove, undefined);
    assert.ok(beforeMove! <= 2, `read ${beforeMove} runtime sources before moving to the new session`);
  } finally { await rig.close(); }
});

for (const source of ["without point lookup", "missing", "other runtime", "without point lookup and another runtime"] as const) {
  test(`switching accounts keeps subagent behavior with a source ${source}`, async () => {
    const rig = new Rig();
    try {
      rig.edit((raw) => { raw.profiles[0].models = ["opus"]; raw.profiles.push({ ...raw.profiles[0], id: "cc2", name: "second" }); });
      await rig.accept(message());
      await settle();
      const first = rig.claude.last(), key = first.options.route;
      const project = join(rig.config.profiles[0]!.home, "projects", "-w");
      mkdirSync(join(project, first.id(), "subagents"), { recursive: true });
      writeFileSync(join(project, `${first.id()}.jsonl`), "{}\n");
      writeFileSync(join(project, first.id(), "subagents", "agent-a1.jsonl"), "{}\n");
      first.tasks = [{ id: "a1", kind: "agent", description: "profile the build" }];

      // The switch is decided before the new process opens; change what the actor can read when that open returns.
      const open = rig.claude.open.bind(rig.claude);
      rig.claude.open = async (...args) => {
        const next = await open(...args);
        if (source === "other runtime" || source === "without point lookup and another runtime")
          rig.store.db.prepare("UPDATE runtime_sessions SET runtime='codex' WHERE session_key=? AND id=?").run(key, first.id());
        if (source === "without point lookup" || source === "without point lookup and another runtime")
          Object.defineProperty(rig.store, "runtimeSessionSource", { value: undefined, configurable: true });
        else if (source === "missing") rig.store.runtimeSessionSource = () => null;
        return next;
      };
      first.end({ kind: "failed", reason: classifyResult("usage limit reached"), message: "usage limit reached" });
      await settle();
      const second = rig.claude.last();
      assert.notEqual(second.id(), first.id());
      const copied = existsSync(join(project, second.id(), "subagents", "agent-a1.jsonl"));
      assert.equal(copied, source !== "other runtime" && source !== "without point lookup and another runtime");
    } finally { await rig.close(); }
  });
}

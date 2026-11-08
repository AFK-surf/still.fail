import assert from "node:assert/strict";
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { join } from "node:path";
import { test } from "node:test";
import { Rig } from "./hub-fakes.ts";

test("a live subscription yields while locating a session's many old transcripts", async () => {
  const rig = new Rig();
  const exists = fs.existsSync;
  let id: number | undefined;
  try {
    rig.store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const db = rig.store.db, put = db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    db.exec("BEGIN");
    for (let i = 0; i < 513; i++) put.run("one", `source-${i}`, "cc", i, "claude");
    rig.store.setRuntimeSessionId("one", "source-512");
    db.exec("COMMIT");
    const home = rig.config.profiles.find((profile) => profile.id === "cc")!.home;
    const dir = join(home, "projects", "-w");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(join(dir, "source-512.jsonl"), "");
    rig.hub.live.history = { state: async () => null, page: async () => ({ start: 0, entries: [], end: 0 }) };
    const original = rig.store.runtimeSessionSources.bind(rig.store);
    let rows = 0, paths = 0;
    rig.store.runtimeSessionSources = (key) => { const sources = original(key); rows += sources.length; return sources; };
    fs.existsSync = ((path) => {
      if (String(path).includes("source-") && String(path).endsWith(".jsonl")) paths++;
      return exists(path);
    }) as typeof fs.existsSync;
    syncBuiltinESMExports();
    let finished = false, maxRows = 0, maxPaths = 0;
    const sample = () => {
      maxRows = Math.max(maxRows, rows); maxPaths = Math.max(maxPaths, paths);
      rows = 0; paths = 0;
      if (!finished) setImmediate(sample);
    };
    setImmediate(sample);
    let joined = () => {};
    const timeline = new Promise<void>((resolve) => { joined = resolve; });
    id = rig.hub.live.subscribe("one", 0, 0, (message) => { if (message.type === "timeline") joined(); });
    let timeout: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([timeline, new Promise<never>((_, reject) => { timeout = setTimeout(() => reject(new Error("subscription did not join")), 5000); })]);
    } finally { if (timeout !== undefined) clearTimeout(timeout); finished = true; sample(); }
    assert.ok(maxRows <= 256 && maxPaths <= 256, `read ${maxRows} source rows and checked ${maxPaths} paths between event-loop turns`);
  } finally {
    fs.existsSync = exists;
    syncBuiltinESMExports();
    if (id !== undefined) rig.hub.live.unsubscribe("one", id);
    await rig.close();
  }
});

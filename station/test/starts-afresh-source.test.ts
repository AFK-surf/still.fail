import assert from "node:assert/strict";
import { test } from "node:test";
import { afresh } from "../src/agents/instructions.ts";
import { startsAfresh } from "../src/sessions/afresh.ts";
import { Rig } from "./hub-fakes.ts";

test("deciding whether to start afresh reads only the requested runtime source", async () => {
  const rig = new Rig();
  try {
    rig.store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const db = rig.store.db, put = db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    db.exec("BEGIN");
    for (let i = 0; i < 513; i++) put.run("one", `old-${i}`, "cc", i, "claude");
    put.run("one", "current", "cc", 1000, "claude");
    rig.store.setRuntimeSessionId("one", "current");
    db.exec("COMMIT");
    const original = rig.store.runtimeSessionSources.bind(rig.store);
    let visited = 0;
    rig.store.runtimeSessionSources = (key) => { const sources = original(key); visited += sources.length; return sources; };
    const profile = rig.config.profiles.find((item) => item.id === "cc");
    assert.ok(profile);
    assert.equal(startsAfresh(rig.hub, "one", "current", profile, "cc"), null);
    assert.ok(visited <= 2, `read ${visited} runtime sources to decide about one`);
  } finally { await rig.close(); }
});

test("starting afresh still follows the recorded runtime, profile and missing source", async () => {
  const rig = new Rig();
  try {
    rig.store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const db = rig.store.db;
    db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES('one','current','cc',1,'claude')").run();
    rig.store.setRuntimeSessionId("one", "current");
    const profile = rig.config.profiles.find((item) => item.id === "cc");
    assert.ok(profile);
    const decide = (id: string, was: string | null) => startsAfresh(rig.hub, "one", id, profile, was);
    assert.equal(decide("current", "cc"), null);
    db.prepare("UPDATE runtime_sessions SET runtime='codex' WHERE session_key='one' AND id='current'").run();
    assert.equal(decide("current", "cc"), afresh("one", []));
    db.prepare("UPDATE runtime_sessions SET runtime='claude', profile='other' WHERE session_key='one' AND id='current'").run();
    assert.equal(decide("current", "cc"), afresh("one", []));
    db.prepare("UPDATE runtime_sessions SET profile=NULL WHERE session_key='one' AND id='current'").run();
    assert.equal(decide("current", null), null);
    assert.equal(decide("current", "other"), afresh("one", []));
    rig.store.setRuntimeSessionId("one", "missing");
    assert.equal(decide("missing", "cc"), null);
    assert.equal(decide("missing", "other"), afresh("one", []));
  } finally { await rig.close(); }
});

test("a single source keeps the ordered reader's identity rules on the station connection", async () => {
  const rig = new Rig();
  try {
    rig.store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const db = rig.store.db;
    const put = db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES('one',CAST(? AS TEXT),?,?,?)");
    put.run(Buffer.from("target\0old"), "earlier", 1, "codex");
    put.run(Buffer.from("target"), "cc", 2, "claude");
    put.run(Buffer.from("\0old"), "empty-prefix", 3, "claude");
    put.run(Buffer.from([0x61, 0xff, 0x62]), "invalid", 4, "codex");
    put.run(Buffer.from("emoji-😀"), "emoji", 5, null);
    db.prepare("UPDATE sessions SET original_runtime='codex' WHERE key='one'").run();
    for (const current of ["target", "target\0old", "", "a\ufffdb", "\ud800", "emoji-😀", "missing", null]) {
      rig.store.setRuntimeSessionId("one", current);
      for (const id of ["target", "target\0old", "", "a\ufffdb", "\ud800", "emoji-😀", "missing", "absent"]) {
        assert.deepEqual(rig.store.runtimeSessionSource("one", id),
          rig.store.runtimeSessionSources("one").find((source) => source.id === id) ?? null);
      }
    }
    rig.store.setRuntimeSessionId("one", "target");
    const first = rig.store.runtimeSessionSources("one").find((source) => source.id === "target");
    const profile = rig.config.profiles.find((item) => item.id === "cc");
    assert.ok(first); assert.ok(profile);
    assert.equal(startsAfresh(rig.hub, "one", "target", profile, "cc"), first.runtime === "claude" ? null : afresh("one", []));
    db.prepare("UPDATE sessions SET runtime_session_id=CAST(X'0102' AS BLOB) WHERE key='one'").run();
    assert.deepEqual(rig.store.runtimeSessionSource("one", "target"),
      rig.store.runtimeSessionSources("one").find((source) => source.id === "target") ?? null);
  } finally { await rig.close(); }
});

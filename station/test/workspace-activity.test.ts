import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { installWorkspaceActivity, workspaceActivityReady, workspaceActivityStep, WORKSPACE_ACTIVITY } from "../src/store/workspace-activity.ts";

function fixture() {
  const store = Store.open(":memory:");
  const db = store.db;
  const add = (key: string, ws: string | null, token = key) => store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token, createdAt: 1, lastActiveAt: 1, ws });
  const actual = () => (db.prepare("SELECT home, ws, session FROM workspace_activity ORDER BY home, ws, session").all() as any[]).map((r) => [r.home, r.ws, r.session]);
  const expected = () => (db.prepare(`SELECT s.ws IS NULL AS home, COALESCE(s.ws, '') AS ws, s.key AS session FROM sessions s
    WHERE s.running = 1 OR EXISTS (SELECT 1 FROM deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL)
      OR EXISTS (SELECT 1 FROM letter_deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL)
    ORDER BY home, ws, session`).all() as any[]).map((r) => [r.home, r.ws, r.session]);
  return { store, db, add, actual, expected };
}

for (const recursive of [false, true]) test(`workspace activity follows older writers and replacements (recursive triggers ${recursive})`, () => {
  const { store, db, add, actual, expected } = fixture();
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    add("message", "W1"); add("letter", "W2"); add("run", null); add("idle", "W1");
    assert.equal(workspaceActivityReady(db), true);
    const insert = db.prepare("INSERT INTO deliveries (thread,n,session,delivered_at) VALUES (1,?,?,?)");
    const letter = db.prepare("INSERT INTO letter_deliveries (thread,n,session,delivered_at) VALUES (1,?,?,?)");
    const same = () => assert.deepEqual(actual(), expected());
    insert.run(1, "message", null); insert.run(2, "message", null); letter.run(1, "letter", null);
    db.prepare("UPDATE sessions SET running=1 WHERE key='run'").run(); same();
    db.prepare("UPDATE deliveries SET delivered_at=2 WHERE n=1 AND session='message'").run(); same();
    db.prepare("UPDATE deliveries SET delivered_at=2 WHERE n=2 AND session='message'").run(); same();
    db.prepare("UPDATE deliveries SET delivered_at=NULL WHERE n=1 AND session='message'").run(); same();
    db.prepare("UPDATE sessions SET ws='W2' WHERE key='message'").run(); same();
    db.prepare("UPDATE sessions SET ws='', running=0 WHERE key='run'").run(); same();
    db.prepare("DELETE FROM letter_deliveries WHERE session='letter'").run(); same();
    db.prepare("INSERT OR REPLACE INTO deliveries (thread,n,session,delivered_at) VALUES (1,1,'message',2)").run(); same();
    add("collision", "W1");
    insert.run(20, "collision", null); insert.run(21, "collision", 2); same();
    db.prepare("UPDATE OR REPLACE deliveries SET n=20 WHERE n=21 AND session='collision'").run(); same();

    // A replacement may displace a different key through its token. A rejected insert must leave the old marker.
    db.prepare("UPDATE sessions SET running=1 WHERE key='run'").run();
    db.prepare("INSERT OR IGNORE INTO sessions (key, connect, scope, runtime, profile, workspace, token, created_at, last_active_at, ws) VALUES ('ignored','ember','thread','claude','cc','/w','run',1,1,'W1')").run(); same();
    db.prepare("INSERT OR REPLACE INTO sessions (key, connect, scope, runtime, profile, workspace, token, created_at, last_active_at, ws) VALUES ('replacement','ember','thread','claude','cc','/w','run',1,1,'W2')").run(); same();
    db.prepare("UPDATE sessions SET running=1 WHERE key='replacement'").run(); same();
    db.prepare("INSERT OR REPLACE INTO sessions (key, connect, scope, runtime, profile, workspace, token, created_at, last_active_at, ws) VALUES ('replacement','ember','thread','claude','cc','/w','run',1,1,'W2')").run(); same();
    db.prepare("UPDATE sessions SET running=1 WHERE key IN ('replacement','idle')").run();
    db.prepare("INSERT OR REPLACE INTO sessions (key, connect, scope, runtime, profile, workspace, token, created_at, last_active_at, ws) VALUES ('idle','ember','thread','claude','cc','/w','run',1,1,'W1')").run(); same();
    db.prepare("DELETE FROM sessions WHERE key='message'").run(); same();
  } finally { store.close(); }
});

test("an older store builds only active sessions in bounded steps while writes continue", () => {
  const { store, db, add, actual, expected } = fixture();
  try {
    // Leave the deliveries and sessions as an older station had them, before the new index was installed.
    for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'workspace_activity_%'").all() as {name:string}[]) db.exec(`DROP TRIGGER ${row.name}`);
    db.exec("DROP TABLE workspace_activity; DROP TABLE workspace_activity_replaced; DROP TABLE workspace_activity_meta");
    for (let i=0; i<300; i++) add(`old-${String(i).padStart(3, "0")}`, "W1");
    for (const key of ["b", "d", "f", "h"]) add(key, "W2");
    db.prepare("UPDATE sessions SET running=1 WHERE key='b'").run();
    db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (1,1,'d'),(1,2,'f')").run();
    db.prepare("INSERT INTO letter_deliveries (thread,n,session) VALUES (1,3,'h')").run();
    installWorkspaceActivity(db);
    assert.equal(workspaceActivityReady(db), false);
    assert.deepEqual(actual(), [], "installation does not synchronously scan old rows");
    assert.deepEqual(workspaceActivityStep(db, 2), { done: false, visited: 2 });
    add("a", "W2");
    db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (1,4,'a')").run(); // before the cursor
    db.prepare("DELETE FROM deliveries WHERE session='f'").run();
    db.prepare("UPDATE sessions SET ws='W1' WHERE key='h'").run();
    let steps = 1;
    while (!workspaceActivityReady(db)) {
      const result = workspaceActivityStep(db, 2);
      assert.ok(result.visited <= 2);
      assert.ok(++steps < 10);
    }
    assert.deepEqual(actual(), expected());
    assert.deepEqual(workspaceActivityStep(db, 2), { done: true, visited: 0 });
  } finally { store.close(); }
});

test("workspace activity lookup visits only the selected workspace's active sessions", () => {
  const { store, db, add } = fixture();
  try {
    add("target", "W2"); add("other-active", "W1");
    db.prepare("UPDATE sessions SET running=1 WHERE key IN ('target','other-active')").run();
    for (let i=0; i<2000; i++) add(`history-${i}`, "W2");
    const insert = db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (1,?,?)");
    for (let i=0; i<2000; i++) { const key=`pending-${i}`; add(key, "W1"); insert.run(i,key); }
    let visited = 0;
    db.function("visit_workspace_activity", (key) => { visited++; return key; });
    const traced = WORKSPACE_ACTIVITY.replace("SELECT s.*", "SELECT s.*, visit_workspace_activity(a.session) AS visited");
    const rows = db.prepare(traced).all("W2") as {key:string}[];
    assert.deepEqual(rows.map((r) => r.key), ["target"]);
    assert.equal(visited, 1);
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${WORKSPACE_ACTIVITY}`).all("W2") as {detail:string}[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /SEARCH a USING PRIMARY KEY \(home=\? AND ws=\?\)/);
    assert.match(plan, /SEARCH s USING INDEX .* \(key=\?(?: AND ws=\?)?\)/);
  } finally { store.close(); }
});

test("the workspace activity builder waits for the previous station and resumes a partial index", async () => {
  const { mkdtempSync, rmSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const { buildWorkspaceActivity } = await import("../src/sessions/workspace-activity-builder.ts");
  const dir = mkdtempSync(join(tmpdir(), "workspace-activity-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  let builder: ReturnType<typeof buildWorkspaceActivity> | null = null;
  try {
    const db = store.db;
    for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'workspace_activity_%'").all() as {name:string}[]) db.exec(`DROP TRIGGER ${row.name}`);
    db.exec("DROP TABLE workspace_activity; DROP TABLE workspace_activity_replaced; DROP TABLE workspace_activity_meta");
    const insert = db.prepare("INSERT INTO sessions (key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws,running) VALUES (?,'ember','thread','claude','cc','/w',?,1,1,'W2',1)");
    db.exec("BEGIN");
    for (let i=0; i<130; i++) { const key=`active-${String(i).padStart(3, "0")}`; insert.run(key,key); }
    db.exec("COMMIT");
    installWorkspaceActivity(db);
    assert.deepEqual(workspaceActivityStep(db, 1), { done: false, visited: 1 });
    store.close();
    store = Store.open(path);
    const previous = Promise.withResolvers<void>();
    builder = buildWorkspaceActivity(store, previous.promise);
    let settled = false;
    void builder.ready.then(() => { settled = true; });
    await Promise.resolve();
    assert.equal(settled, false, "no worker starts while the previous station may write");
    previous.resolve();
    assert.equal(await builder.ready, true);
    assert.equal(workspaceActivityReady(store.db), true);
    assert.equal(store.returningSessionsIn("W2")?.length, 130);
  } finally {
    await builder?.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("closing an unfinished workspace activity builder settles its wait", async () => {
  const { buildWorkspaceActivity } = await import("../src/sessions/workspace-activity-builder.ts");
  const { store, db } = fixture();
  try {
    db.prepare("UPDATE workspace_activity_meta SET complete=0, cursor=NULL WHERE id=1").run();
    const previous = Promise.withResolvers<void>();
    const builder = buildWorkspaceActivity(store, previous.promise);
    await builder.close();
    assert.equal(await builder.ready, false);
    previous.resolve();
  } finally { store.close(); }
});

test("rejoining reads the active index and pending deliveries from one snapshot", async () => {
  const { DatabaseSync } = await import("node:sqlite");
  const { mkdtempSync, rmSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const dir = mkdtempSync(join(tmpdir(), "workspace-snapshot-"));
  const path = join(dir, "station.db");
  const store = Store.open(path);
  const writer = new DatabaseSync(path);
  const has = store.hasPending;
  try {
    for (const key of ["a-old", "z-new"]) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws: "W2" });
    const thread = store.openThread("ember", "ember", "chat", null, null).id;
    for (const key of ["a-old", "z-new"]) store.joinThread(thread, key, "ember");
    store.db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','a','body',1)").run(thread);
    store.db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (?,1,'a-old')").run(thread);
    let changed = false;
    store.hasPending = function (key) {
      if (!changed) {
        changed = true;
        writer.exec("BEGIN IMMEDIATE");
        writer.prepare("UPDATE deliveries SET delivered_at=1 WHERE session='a-old'").run();
        writer.prepare("INSERT INTO deliveries (thread,n,session) VALUES (?,1,'z-new')").run(thread);
        writer.exec("COMMIT");
      }
      return has.call(this, key);
    };
    assert.deepEqual(store.returningSessionsIn("W2")?.map((row) => row.key), ["a-old"]);
    assert.equal(changed, true);
    assert.deepEqual(store.returningSessionsIn("W2")?.map((row) => row.key), ["z-new"]);
  } finally {
    store.hasPending = has;
    writer.close(); store.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a stopped workspace activity worker retries and finishes its saved work", async () => {
  const { mkdtempSync, rmSync, writeFileSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const { pathToFileURL } = await import("node:url");
  const { buildWorkspaceActivity } = await import("../src/sessions/workspace-activity-builder.ts");
  const dir = mkdtempSync(join(tmpdir(), "workspace-retry-"));
  const store = Store.open(join(dir, "station.db"));
  const file = join(dir, "worker.mjs");
  const marker = join(dir, "exited");
  const real = new URL("../src/sessions/workspace-activity-worker.ts", import.meta.url).href;
  writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  let builder: ReturnType<typeof buildWorkspaceActivity> | null = null;
  try {
    store.insertSession({ key: "active", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "active", createdAt: 1, lastActiveAt: 1, ws: "W2" });
    store.db.prepare("UPDATE sessions SET running=1 WHERE key='active'").run();
    store.db.prepare("DELETE FROM workspace_activity").run();
    store.db.prepare("UPDATE workspace_activity_meta SET cursor=NULL, complete=0 WHERE id=1").run();
    builder = buildWorkspaceActivity(store, Promise.resolve(), pathToFileURL(file));
    assert.equal(await builder.ready, true);
    assert.deepEqual(store.returningSessionsIn("W2")?.map((row) => row.key), ["active"]);
  } finally {
    await builder?.close(); store.close(); rmSync(dir, { recursive: true, force: true });
  }
});

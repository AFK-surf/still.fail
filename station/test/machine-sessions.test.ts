// The machine's own sessions as the pages list them (src/read/machine.ts), where a transcript's lines are huge: a Codex
// rollout keeps screenshots and tools' outputs in a line each (seen at 16 MB, its first 400 lines at 51 MB), which a
// reader's bounded heap (read/pool.ts) cannot hold. Such a line is passed over; what a listing wants is around it.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { after, test } from "node:test";
import { find, machineSessions } from "../src/read/machine.ts";
import { makeStore } from "../src/read/store.ts";
import { SESSION_OF_RUNTIME } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

const dirs: string[] = [];
after(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

test("listing machine sessions finds only the station sessions that could own them", () => {
  const root = mkdtempSync(join(tmpdir(), "machine-owner-"));
  dirs.push(root);
  const roots = { claude: join(root, "claude"), codex: join(root, "codex", "sessions") };
  const claude = join(roots.claude, "project");
  const codex = join(roots.codex, "2026", "09", "02");
  mkdirSync(claude, { recursive: true });
  mkdirSync(codex, { recursive: true });
  const a = "11111111-aaaa-bbbb-cccc-000000000001";
  const b = "22222222-aaaa-bbbb-cccc-000000000002";
  const c = "33333333-aaaa-bbbb-cccc-000000000003";
  const d = "44444444-aaaa-bbbb-cccc-000000000004";
  for (const id of [a, c, d]) writeFileSync(join(claude, `${id}.jsonl`), `${JSON.stringify({ type: "user", cwd: root, message: { content: "hello" } })}\n`);
  writeFileSync(join(codex, `rollout-2026-09-02T00-00-00-${b}.jsonl`), [
    { type: "session_meta", payload: { id: b, cwd: root } },
    { type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "hello" }] } },
  ].map((r) => `${JSON.stringify(r)}\n`).join(""));
  const store = Store.open(":memory:", null);
  try {
    const insert = (key: string, runtime: string, id: string | null, at: number) => store.insertSession({ key, connect: "ds", runtime, profile: "p", runtimeSessionId: id, workspace: root, token: key, createdAt: at, lastActiveAt: at });
    insert("earlier-first", "claude", a, 10);
    insert("earlier-last", "claude", a, 10);
    insert("later", "claude", a, 20);
    insert("changed-runtime", "claude", null, 30);
    store.db.prepare("INSERT INTO runtime_sessions (session_key, id, at, runtime) VALUES (?, ?, ?, ?)").run("changed-runtime", b, 1, "codex");
    insert("inherited-runtime", "codex", c, 40);
    store.db.prepare("UPDATE sessions SET original_runtime = 'claude' WHERE key = ?").run("inherited-runtime");
    store.db.prepare("INSERT INTO runtime_sessions (session_key, id, at, runtime) VALUES (?, ?, ?, NULL)").run("inherited-runtime", c, 1);
    for (let i = 0; i < 200; i++) insert(`unrelated-${i}`, "claude", `other-${i}`, 100 + i);
    const read = makeStore(store.db, root);
    const owners = () => Object.fromEntries(machineSessions(read, roots).sessions.map((v: any) => [v.id, v.session]));
    assert.deepEqual(owners(), { [a]: "later", [b]: "changed-runtime", [c]: "inherited-runtime", [d]: null });
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${SESSION_OF_RUNTIME}`).all("claude", a) as { detail: string }[]).map((r) => r.detail);
    assert.ok(plan.some((p) => p.includes("sessions_by_runtime_id")), plan.join(" | "));
    assert.ok(plan.some((p) => p.includes("runtime_sessions_by_id")), plan.join(" | "));
    assert.ok(!plan.some((p) => /^SCAN (s|r)( |$)/.test(p)), plan.join(" | "));
    // A list used to materialize every station session including its token just to match the three above.
    store.db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "sessions" && column === "token" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.deepEqual(owners(), { [a]: "later", [b]: "changed-runtime", [c]: "inherited-runtime", [d]: null }); }
    finally { store.db.setAuthorizer(null); }
  } finally { store.close(); }
});

test("machine session owners remain readable before runtime history's fields or table exist", () => {
  const root = mkdtempSync(join(tmpdir(), "machine-owner-old-"));
  dirs.push(root);
  const roots = { claude: join(root, "claude"), codex: join(root, "codex") };
  const project = join(roots.claude, "project");
  mkdirSync(project, { recursive: true });
  const id = "11111111-aaaa-bbbb-cccc-000000000001";
  writeFileSync(join(project, `${id}.jsonl`), `${JSON.stringify({ type: "user", cwd: root, message: { content: "hello" } })}\n`);
  for (const version of ["runtime", "history", "none"] as const) {
    const db = new DatabaseSync(":memory:");
    try {
      db.exec(`CREATE TABLE sessions (key TEXT PRIMARY KEY, runtime TEXT, runtime_session_id TEXT, last_active_at INTEGER);
        CREATE INDEX sessions_by_runtime_id ON sessions (runtime_session_id) WHERE runtime_session_id IS NOT NULL;`);
      db.prepare("INSERT INTO sessions VALUES (?, ?, ?, ?)").run("current", "claude", id, 20);
      if (version !== "none") {
        db.exec(`CREATE TABLE runtime_sessions (session_key TEXT, id TEXT${version === "runtime" ? ", runtime TEXT" : ""}, PRIMARY KEY (session_key, id));
          CREATE INDEX runtime_sessions_by_id ON runtime_sessions (id);`);
        db.prepare("INSERT INTO sessions VALUES (?, ?, ?, ?)").run("old", "claude", null, 10);
        if (version === "runtime") db.prepare("INSERT INTO runtime_sessions VALUES (?, ?, ?)").run("old", id, "claude");
        else db.prepare("INSERT INTO runtime_sessions VALUES (?, ?)").run("old", id);
      }
      assert.equal(machineSessions(makeStore(db, root), roots).sessions[0].session, "current", version);
    } finally { db.close(); }
  }
});

test("a huge line in a rollout's head is passed over: the session is still found, with what was said around it", () => {
  const root = mkdtempSync(join(tmpdir(), "machine-"));
  dirs.push(root);
  const roots = { claude: join(root, ".claude", "projects"), codex: join(root, ".codex", "sessions") };
  const day = join(roots.codex, "2026", "09", "02");
  mkdirSync(day, { recursive: true });
  const id = "33333333-aaaa-bbbb-cccc-000000000001";
  const huge = { type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_image", image_url: `data:image/png;base64,${"A".repeat(2 << 20)}` }] } };
  const records = [
    { type: "session_meta", payload: { id, cwd: root } },
    huge,
    { type: "response_item", timestamp: "2026-09-02T00:00:01.000Z", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "after the picture" }] } },
    { type: "turn_context", payload: { model: "gpt-5.5" } },
  ];
  writeFileSync(join(day, `rollout-2026-09-02T00-00-00-${id}.jsonl`), records.map((r) => `${JSON.stringify(r)}\n`).join(""));
  const found = find(roots, "codex", id);
  assert.ok(found, "found");
  assert.equal(found.first, "after the picture");
  assert.equal(found.cwd, root);
  assert.equal(found.model, "gpt-5.5");
});

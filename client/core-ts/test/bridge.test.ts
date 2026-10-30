// The core on a shell's bridge (hosts/bridge.ts), the shell here in JavaScript (node-shell.ts) as the Android app's is
// in C++ and Rust: storage, the database, still.fail cloud over HTTP and its WebSocket, and the mesh to a station.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { DatabaseSync } from "node:sqlite";
import { Effect, Fiber } from "effect";
import { FakeCloud } from "../harness/cloud.ts";
import { apply } from "../src/delta.ts";
import { Bridge, BridgeHost, bridgeIroh, startBridged } from "../src/hosts/bridge.ts";
import { loadAddon } from "../src/hosts/node-iroh.ts";
import { holdLanguage } from "../src/i18n.ts";
import { Mesh } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { FakeHost } from "../src/testing.ts";
import { Tracer } from "../src/trace.ts";
import { Wakes } from "../src/wake.ts";
import { Station } from "./mesh-station.ts";
import { NodeShell } from "./node-shell.ts";
import { run } from "./run.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const bytes = (s: string) => new TextEncoder().encode(s);
const text = (b: Uint8Array | null) => (b === null ? null : new TextDecoder().decode(b));

function shell() {
  const dir = mkdtempSync(join(tmpdir(), "bridge-"));
  const native = new NodeShell(dir);
  const bridge = new Bridge(native);
  native.bridge = bridge;
  return { dir, native, bridge, host: new BridgeHost(bridge, "http://127.0.0.1:1", false) };
}

test("interrupting_a_fetch_cancels_that_native_request", async () => {
  const { dir, native, bridge } = shell();
  const pending: number[] = [];
  const cancelled: number[] = [];
  native.call = (id) => { pending.push(id); };
  native.callSync = (op, json) => {
    assert.equal(op, "fetch.cancel");
    cancelled.push(JSON.parse(json).id);
    return '{"value":true}';
  };
  try {
    const first = Effect.runFork(bridge.call("fetch", {}));
    const second = Effect.runFork(bridge.call("fetch", {}));
    await run(Fiber.interrupt(first));
    assert.deepEqual(cancelled, [pending[0]]);
    // A late answer to the cancelled call is harmless; the other call still gets its own answer.
    bridge.complete(pending[0]!, '{"status":200}', null, null);
    bridge.complete(pending[1]!, '{"status":201}', null, null);
    assert.deepEqual((await run(Fiber.join(second))).json, { status: 201 });
    assert.deepEqual(cancelled, [pending[0]], "completed requests must not be cancelled");
  } finally {
    native.host.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("storage_and_the_database_go_through_the_bridge", async () => {
  const { dir, host, native } = shell();
  assert.equal(await run(host.storageGet("accounts")), null);
  await run(host.storageSet("accounts", bytes("[1]")));
  assert.equal(text(await run(host.storageGet("accounts"))), "[1]");
  await run(host.storageDelete("accounts"));
  assert.equal(await run(host.storageGet("accounts")), null);
  // The former records store: only read, through the bridge.
  {
    const db = new DatabaseSync(join(dir, "core.db"));
    db.exec("CREATE TABLE records (tbl TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (tbl, key)) WITHOUT ROWID");
    for (const [k, v] of [["s\u0001a", "1"], ["s\u0001c", ""], ["t\u0001a", "333"]]) db.prepare("INSERT INTO records VALUES ('row', ?, ?)").run(k, bytes(v));
    db.close();
  }
  const rows = await run(host.legacyRead({ table: "row", from: "s\u0001", to: "s\u0002" }));
  assert.deepEqual(rows.map(([k, v]) => [k, text(v)]), [["s\u0001a", "1"], ["s\u0001c", ""]]);
  // An account's database: SQLite in the shell, asked synchronously (beside the storage keys' files, `accounts` one).
  await run(host.storageSet("accounts", bytes("[]")));
  const sql = await run(host.openDb("account-a"));
  sql.exec("CREATE TABLE t (k TEXT PRIMARY KEY, n INTEGER, j TEXT)");
  assert.equal(sql.run("INSERT INTO t VALUES (?, ?, ?)", ["a", 1, '{"x":"中"}']), 1);
  assert.deepEqual(sql.all("SELECT k, n, j FROM t", []), [["a", 1, '{"x":"中"}']]);
  assert.throws(() => sql.run("INSERT INTO t VALUES (?, 2, null)", ["a"]), /UNIQUE/);
  sql.close();
  await run(host.deleteDb("account-a"));
  assert.deepEqual(native.calls.slice(0, 3), ["storage.get", "storage.set", "storage.get"]);
  native.host.close();
  rmSync(dir, { recursive: true, force: true });
});

test("a_core_on_the_bridge_signs_in_and_hears_the_cloud", async () => {
  const cloud = new FakeCloud();
  // A port of its own: another run of these tests at once on this machine has its cloud too.
  await cloud.listen(0);
  const dir = mkdtempSync(join(tmpdir(), "bridge-core-"));
  const native = new NodeShell(dir);
  const fatal: string[] = [];
  const core = startBridged(native, `http://127.0.0.1:${cloud.port()}`, false, "android", (r) => fatal.push(r));
  native.bridge = core.bridge;
  const client = core.connect();
  const states = new Map<number, unknown>();
  const answers = new Map<number, J>();
  const read = () => {
    for (const [, json] of native.emitted.splice(0)) {
      const m = JSON.parse(json);
      if ("value" in m) states.set(m.id, m.value);
      else if ("delta" in m) states.set(m.id, apply(states.get(m.id), m.delta));
      else if ("ok" in m || "error" in m) answers.set(m.id, m.ok ?? m.error);
    }
  };
  // What the core emits, read as it comes until it says so: no deadline, only the test's own timeout for a hang.
  const until = async (done: () => boolean) => {
    for (read(); !done(); read()) await native.heard();
  };
  core.receive(client, JSON.stringify({ id: 1, subscribe: { topic: "accounts" } }));
  core.receive(client, JSON.stringify({ id: 50, call: "auth.begin", params: { redirect_uri: "stillfail://auth/callback", return_to: "/" } }));
  await until(() => answers.has(50));
  const state = new URL(String(answers.get(50).url)).searchParams.get("state");
  core.receive(client, JSON.stringify({ id: 51, call: "auth.complete", params: { query: `?code=code-alice&state=${state}` } }));
  core.receive(client, JSON.stringify({ id: 2, subscribe: { topic: "workspace", workspace: "ws1" } }));
  await until(() => (states.get(2) as J)?.name === "研发");
  assert.deepEqual((states.get(1) as J[]).map((a) => a.email), ["alice@x.test"]);
  // The events socket is open through the bridge: a rename the cloud tells of comes in.
  await cloud.socketOpen();
  cloud.workspaces.get("ws1")!.name = "研发部";
  cloud.push({ type: "workspace", id: "ws1" });
  await until(() => (states.get(2) as J)?.name === "研发部");
  assert.equal((states.get(2) as J).name, "研发部");
  assert.deepEqual(fatal, []);
  for (const op of ["storage.get", "db.read", "fetch", "ws.open", "ws.next"]) assert.ok(native.calls.includes(op), op);
  await cloud.close();
  native.host.close();
  rmSync(dir, { recursive: true, force: true });
});

test("a_file_picked_in_the_app_is_read_from_there_as_it_goes_up", async (t) => {
  // Hermes has no Blob (2026-10-22: every file picked on the phone failed at composer.add).
  const blob = Object.getOwnPropertyDescriptor(globalThis, "Blob")!;
  delete (globalThis as { Blob?: unknown }).Blob;
  t.after(() => Object.defineProperty(globalThis, "Blob", blob));
  const dir = mkdtempSync(join(tmpdir(), "bridge-picked-"));
  const native = new NodeShell(dir);
  const core = startBridged(native, "http://127.0.0.1:1", false, "android", () => {});
  native.bridge = core.bridge;
  native.picked.set(7, bytes("abc"));
  const client = core.connect();
  const states = new Map<number, J>();
  const read = () => {
    for (const [, json] of native.emitted.splice(0)) {
      const m = JSON.parse(json);
      if ("value" in m) states.set(m.id, m.value);
      else if ("delta" in m) states.set(m.id, apply(states.get(m.id), m.delta));
      else if ("error" in m) errors.set(m.id, m.error);
    }
  };
  const errors = new Map<number, J>();
  const until = async (done: () => boolean) => {
    for (read(); !done(); read()) await native.heard();
  };
  core.receive(client, JSON.stringify({ id: 1, subscribe: { topic: "composer", key: "phone-1" } }));
  // A picture: its size is read from its head too.
  core.receive(client, JSON.stringify({ id: 2, call: "composer.add", params: { key: "phone-1", station: "ws/st", files: [{ id: "f1", name: "a.png", size: 3, blob: { hostFile: 7, size: 3, type: "image/png" } }] } }));
  // No such station here: it fails once its first part is read from the app.
  await until(() => errors.has(2) || states.get(1)?.files?.[0]?.error != null);
  assert.equal(errors.get(2), undefined);
  // Named first (the station may have it already), read from the app as it goes (a picture's head before, for its size).
  assert.ok(native.calls.indexOf("picked.hash") >= 0 && native.calls.indexOf("picked.hash") < native.calls.lastIndexOf("picked.read"));
  assert.ok(native.picked.has(7), "a failed upload keeps its file, to go again");
  core.receive(client, JSON.stringify({ id: 3, call: "composer.remove", params: { key: "phone-1", id: "f1" } }));
  await until(() => !native.picked.has(7));
  native.host.close();
  rmSync(dir, { recursive: true, force: true });
});

test("a_file_held_whole_by_the_app_goes_up_from_the_bytes_beside_its_call", async (t) => {
  const blob = Object.getOwnPropertyDescriptor(globalThis, "Blob")!;
  delete (globalThis as { Blob?: unknown }).Blob;
  t.after(() => Object.defineProperty(globalThis, "Blob", blob));
  const dir = mkdtempSync(join(tmpdir(), "bridge-held-"));
  const native = new NodeShell(dir);
  const core = startBridged(native, "http://127.0.0.1:1", false, "android", () => {});
  native.bridge = core.bridge;
  const client = core.connect();
  const states = new Map<number, J>();
  const errors = new Map<number, J>();
  const read = () => {
    for (const [, json] of native.emitted.splice(0)) {
      const m = JSON.parse(json);
      if ("value" in m) states.set(m.id, m.value);
      else if ("delta" in m) states.set(m.id, apply(states.get(m.id), m.delta));
      else if ("error" in m) errors.set(m.id, m.error);
    }
  };
  const until = async (done: () => boolean) => {
    for (read(); !done(); read()) await native.heard();
  };
  core.receive(client, JSON.stringify({ id: 1, subscribe: { topic: "composer", key: "mbui-1" } }));
  // two files in one call, each its own run of the bytes
  const sha = "a".repeat(64);
  core.receive(client, JSON.stringify({ id: 2, call: "composer.add", params: { key: "mbui-1", station: "ws/st", files: [
    { id: "f1", name: "a.txt", size: 3, blob: { hostBytes: [0, 3], type: "text/plain", sha256: sha } },
    { id: "f2", name: "b.txt", size: 2, blob: { hostBytes: [3, 2], type: "text/plain" } },
  ] } }), bytes("abcde"));
  // taken (no such station here: each fails as it goes up), never asked of the app
  await until(() => errors.has(2) || (states.get(1)?.files?.length === 2 && states.get(1).files.every((f: J) => f.error != null)));
  assert.equal(errors.get(2), undefined);
  assert.deepEqual(states.get(1).files.map((f: J) => [f.id, f.size]), [["f1", 3], ["f2", 2]]);
  assert.ok(!native.calls.some((c) => c.startsWith("picked.")));
  native.host.close();
  rmSync(dir, { recursive: true, force: true });
});

const skip = loadAddon() === null ? "the mesh addon is not built here" : false;

test("the_mesh_goes_through_the_bridges_iroh", { skip }, async () => {
  const station = await Station.start();
  const { dir, native, bridge } = shell();
  const host = new FakeHost();
  const runner = new Runner();
  const mesh = await runner.run(Mesh.make({ host, runner, tracer: new Tracer(host, runner, 1), iroh: bridgeIroh(bridge), wakes: new Wakes() }, []));
  mesh.addAddr(station.addr());
  const link = await runner.run(mesh.link(station.id(), (device) => Effect.succeed({ credential: `ok-${device.length}`, issued_at: 0, expires_at: 0, relay_url: "" } as J)));
  const reply = await runner.run(link.request({ method: "POST", path: "/admin/api/x", headers: [] }, bytes("hi")));
  assert.equal(reply.status, 200);
  let all = "";
  for (;;) {
    const chunk = await runner.run(reply.body.take);
    if (chunk === null) break;
    all += text(chunk);
  }
  assert.ok(all.endsWith("|hi|one|two|three"), all);
  assert.deepEqual(station.grants, ["ok-64"]);
  for (const op of ["iroh.bind", "iroh.connect", "conn.openBi", "istream.write", "istream.read"]) assert.ok(native.calls.includes(op), op);
  await station.close();
  await runner.run(mesh.close());
  runner.shutdown();
  native.host.close();
  rmSync(dir, { recursive: true, force: true });
});

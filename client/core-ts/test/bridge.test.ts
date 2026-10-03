// The core on a shell's bridge (hosts/bridge.ts), the shell here in JavaScript (node-shell.ts) as the Android app's is
// in C++ and Rust: storage, the database, still.fail cloud over HTTP and its WebSocket, and the mesh to a station.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { DatabaseSync } from "node:sqlite";
import { Effect } from "effect";
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
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const bytes = (s: string) => new TextEncoder().encode(s);
const text = (b: Uint8Array | null) => (b === null ? null : new TextDecoder().decode(b));

function shell() {
  const dir = mkdtempSync(join(tmpdir(), "bridge-"));
  const native = new NodeShell(dir);
  const bridge = new Bridge(native);
  native.bridge = bridge;
  return { dir, native, bridge, host: new BridgeHost(bridge, "http://127.0.0.1:1", false) };
}

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
  // An account's database: SQLite in the shell, asked synchronously.
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
  await cloud.listen(47_331);
  const dir = mkdtempSync(join(tmpdir(), "bridge-core-"));
  const native = new NodeShell(dir);
  const fatal: string[] = [];
  const core = startBridged(native, "http://127.0.0.1:47331", false, "android", (r) => fatal.push(r));
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
  const quiet = async (until: () => boolean) => {
    for (let i = 0; i < 200 && !until(); i++) {
      await sleep(25);
      read();
    }
  };
  core.receive(client, JSON.stringify({ id: 1, subscribe: { topic: "accounts" } }));
  core.receive(client, JSON.stringify({ id: 50, call: "auth.begin", params: { redirect_uri: "stillfail://auth/callback", return_to: "/" } }));
  await quiet(() => answers.has(50));
  const state = new URL(String(answers.get(50).url)).searchParams.get("state");
  core.receive(client, JSON.stringify({ id: 51, call: "auth.complete", params: { query: `?code=code-alice&state=${state}` } }));
  core.receive(client, JSON.stringify({ id: 2, subscribe: { topic: "workspace", workspace: "ws1" } }));
  await quiet(() => (states.get(2) as J)?.name === "研发");
  assert.deepEqual((states.get(1) as J[]).map((a) => a.email), ["alice@x.test"]);
  // The events socket is open through the bridge: a rename the cloud tells of comes in.
  await quiet(() => cloud.sockets.size > 0);
  cloud.workspaces.get("ws1")!.name = "研发部";
  cloud.push({ type: "workspace", id: "ws1" });
  await quiet(() => (states.get(2) as J)?.name === "研发部");
  assert.equal((states.get(2) as J).name, "研发部");
  assert.deepEqual(fatal, []);
  for (const op of ["storage.get", "db.read", "fetch", "ws.open", "ws.next"]) assert.ok(native.calls.includes(op), op);
  await cloud.close();
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

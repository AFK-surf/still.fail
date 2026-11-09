import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

function fixture() {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "mine", seq: 0, members: ["alice"] } as never);
  vaults.putVault({ ws: "w", id: "theirs", seq: 0, members: ["bob"] } as never);
  const lock = { ws: "w" } as never;
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  const put = (id: string, fields: string) => db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','granted',?)")
    .run(id, `{"ws":"w","id":"${id}","session":"s",${fields},"item":"${id}","mode":"env","status":"granted"}`);
  const read = async (vault: string, sub: string, email: string, limit = 10) =>
    (await secrets.uses("w", vault === "plain" ? null : lock, vault, { sub, email }, limit)).map((r) => r.item);
  return { db, secrets, put, read };
}

test("a use with duplicate vault fields follows its last vault for both members", async () => {
  const f = fixture();
  try {
    f.put("r", '"vault":"mine","vault":"theirs","at":10');
    assert.deepEqual(await f.read("mine", "alice", "alice@example.test"), []);
    assert.deepEqual(await f.read("theirs", "bob", "bob@example.test"), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a use with duplicate vault fields remains visible to the last vault's members", async () => {
  const f = fixture();
  try {
    f.put("r", '"vault":"mine","vault":"theirs","at":10');
    assert.deepEqual(await f.read("theirs", "bob", "bob@example.test"), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a NUL-suffixed property is not the vault field of a use", async () => {
  const f = fixture();
  try {
    f.put("r", '"vault\\u0000ignored":"mine","vault":"theirs","at":10');
    assert.deepEqual(await f.read("mine", "alice", "alice@example.test"), []);
    assert.deepEqual(await f.read("theirs", "bob", "bob@example.test"), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a plain use with duplicate owner fields follows its last owner", async () => {
  const f = fixture();
  try {
    f.put("r", '"vault":"plain","owner":"alice@example.test","owner":"bob@example.test","at":10');
    assert.deepEqual(await f.read("plain", "alice", "alice@example.test"), []);
    assert.deepEqual(await f.read("plain", "bob", "bob@example.test"), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a duplicate save field uses its last value when choosing use history", async () => {
  const f = fixture();
  try {
    f.put("save", '"vault":"mine","save":null,"save":{"typed":true},"at":10');
    f.put("use", '"vault":"mine","save":{"typed":true},"save":null,"at":9');
    assert.deepEqual(await f.read("mine", "alice", "alice@example.test"), ["use"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a duplicate time field uses its last value when applying the page limit", async () => {
  const f = fixture();
  try {
    f.put("old", '"vault":"mine","at":100,"at":1');
    f.put("new", '"vault":"mine","at":50');
    assert.deepEqual(await f.read("mine", "alice", "alice@example.test", 1), ["new"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a plain-use owner with an isolated surrogate keeps JavaScript identity", async () => {
  const f = fixture();
  try {
    const email = `${String.fromCharCode(0xd800)}@example.test`;
    f.put("r", `"vault":"plain","owner":${JSON.stringify(email)},"at":10`);
    assert.deepEqual(await f.read("plain", "alice", email), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a vault-use identity with an isolated surrogate keeps JavaScript identity", async () => {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db), id = String.fromCharCode(0xd800);
  vaults.putVault({ ws: "w", id, seq: 0, members: ["alice"] } as never);
  const lock = { ws: "w" } as never;
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    const body = JSON.stringify({ ws: "w", id: "r", session: "s", vault: id, at: 10, item: "r", mode: "env", status: "granted" });
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','granted',?)").run(body);
    assert.deepEqual((await secrets.uses("w", lock, id, { sub: "alice", email: "alice@example.test" })).map((r) => r.item), ["r"]);
  } finally { await secrets.close(); db.close(); }
});

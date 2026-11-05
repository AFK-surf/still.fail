import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
import { Store } from "../src/store/store.ts";
import { PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

for (const operation of ["ask", "save"] as const) {
  test(`a secret ${operation} waits for an old session's latest chat without sorting its memberships`, async () => {
    for (const older of [40, 400]) {
      const store = Store.open(":memory:"), db = store.db;
      const dir = mkdtempSync(join(tmpdir(), "vault-latest-"));
      const gate = Promise.withResolvers<void>();
      let asking: Promise<unknown> | undefined;
      try {
        store.insertSession({ key: "s", connect: "slack", runtime: "claude", profile: "cc", workspace: "/w/s",
          token: "s", createdAt: 1, lastActiveAt: 1 });
        const first = store.openThread("slack", "C", "first", null, null);
        store.joinThread(first.id, "s", "slack");
        db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',1)").run(first.id);
        db.exec("BEGIN");
        let later = first;
        for (let n = 0; n < older; n++) {
          const old = store.openThread("slack", "C", `old-${n}`, null, null);
          store.joinThread(old.id, "s", "slack");
          if (n === 0) later = old;
        }
        db.exec("COMMIT");
        let slowReads = 0;
        const traced = new Proxy(db, {
          get(target, property) {
            if (property === "prepare") return (sql: string) => {
              if (sql.includes("ORDER BY (SELECT d.rowid FROM deliveries")) slowReads++;
              return target.prepare(sql);
            };
            const value = Reflect.get(target, property, target);
            return typeof value === "function" ? value.bind(target) : value;
          },
        });
        Object.defineProperty(store, "db", { value: traced, configurable: true });
        const plain = new PlainStore(db), vaults = new VaultStore(db);
        plain.put({ ws: "w", id: "i_00000000000000000000000001", owner: "p@example.test", version: 0,
          kind: "token", name: "test key", fields: { value: "fake" }, notes: "",
          listing: { name: "test key", kind: "token", modes: ["env"], hosts: [] }, at: 1 });
        const requested: string[][] = [], posted: string[] = [];
        const hub = {
          store: {
            getSession: store.getSession.bind(store), starter: () => "p@example.test",
            latestThread: store.latestThread.bind(store), latestThreadIfReady: store.latestThreadIfReady.bind(store),
            sessionThreadById: store.sessionThreadById.bind(store), pendingCard: () => null,
            insertMessage: () => [1], withdrawCard: () => true, restateCard: () => true, subscribe: () => {},
          },
          prepareLatestThreads: async (sessions: readonly string[]) => {
            requested.push([...sessions]);
            await gate.promise;
            while (!prepareLatestThreadStep(db, "s", 64, { existingSession: true }).done) { /* bounded worker batches */ }
          },
          chat: () => ({ post: async (where: { threadTs: string }) => { posted.push(where.threadTs); return "posted"; } }),
          shared: () => {}, notify: () => {},
        } as any;
        const secrets = new Secrets({ db, vaults, plain, hub, data: dir, home: () => "w", lock: () => null, now: () => 1_800_000_000_000 });
        asking = operation === "ask"
          ? secrets.ask("s", { item: "test key", reason: "test" })
          : secrets.save("s", { name: "new key", kind: "token", reason: "test", value: "fake", cwd: dir });
        await Promise.resolve();
        assert.equal(slowReads, 0, `${older} older memberships must not reach the original sort`);
        assert.deepEqual(requested, [["s"]]);
        assert.deepEqual(posted, []);
        db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',2)").run(later.id);
        gate.resolve();
        await asking;
        assert.deepEqual(posted, ["old-0"]);
      } finally {
        gate.resolve();
        await asking?.catch(() => undefined);
        Object.defineProperty(store, "db", { value: db, configurable: true });
        store.close();
        rmSync(dir, { recursive: true, force: true });
      }
    }
  });
}

function waitingVault() {
  const db = new DatabaseSync(":memory:");
  const dir = mkdtempSync(join(tmpdir(), "vault-wait-"));
  const gate = Promise.withResolvers<void>(), cookies = Promise.withResolvers<string>();
  const plain = new PlainStore(db), vaults = new VaultStore(db);
  plain.put({ ws: "w", id: "i_00000000000000000000000001", owner: "p@example.test", version: 0,
    kind: "token", name: "test key", fields: { value: "fake" }, notes: "",
    listing: { name: "test key", kind: "token", modes: ["env"], hosts: [] }, at: 1 });
  let present = true, workspace = "w", owner = "p@example.test", ready = false, prepared = 0, captured = 0;
  let lock: any = null;
  let now = 1_800_000_000_000;
  const posts: string[] = [];
  const thread = { connect: "slack", thread: { id: 1, channel: "C", threadTs: "latest", surface: "slack" } };
  const hub = {
    store: {
      getSession: () => present ? { ws: workspace, archivedAt: null } : null,
      starter: () => owner, latestThread: () => { throw new Error("unbounded latest read"); },
      latestThreadIfReady: () => ready ? thread : undefined, subscribe: () => {},
      sessionThreadById: () => thread, pendingCard: () => null, insertMessage: () => [1],
      withdrawCard: () => true, restateCard: () => true,
    },
    prepareLatestThreads: async () => { prepared++; await gate.promise; },
    chat: () => ({ post: async (where: { threadTs: string }) => { posts.push(where.threadTs); return "posted"; } }),
    shared: () => {}, notify: () => {},
  } as any;
  const secrets = new Secrets({ db, vaults, plain, hub, data: dir, home: () => "w", lock: () => lock,
    now: () => now, browsers: {
      cookies: async () => { captured++; return cookies.promise; }, signIn: async () => {},
    } });
  return { db, dir, gate, cookies, secrets, posts, prepared: () => prepared, captured: () => captured,
    ready: () => { ready = true; }, remove: () => { present = false; },
    move: () => { workspace = "other"; }, changeOwner: () => { owner = "other@example.test"; },
    advance: (ms: number) => { now += ms; },
    lockWithoutOwner: () => { lock = { members: new Map() }; },
    lockWithOwner: () => { lock = { ws: "w", members: new Map([["p", { sub: "p", email: "p@example.test" }]]), devices: new Map() }; } };
}

function noRequest(w: ReturnType<typeof waitingVault>) {
  assert.equal(w.db.prepare("SELECT COUNT(*) AS n FROM vault_requests").get()?.n, 0);
  assert.deepEqual(w.posts, []);
  assert.deepEqual(w.secrets.carried().unsaved, []);
  assert.deepEqual(w.secrets.carried().keeper.boxes, []);
}

for (const operation of ["ask", "save"] as const) {
  test(`a failed secret ${operation} preparation leaves no request or held secret`, async () => {
    const w = waitingVault();
    try {
      const asking = operation === "ask" ? w.secrets.ask("s", { item: "test key", reason: "test" })
        : w.secrets.save("s", { name: "new key", kind: "token", reason: "test", value: "fake", cwd: w.dir });
      assert.equal(w.prepared(), 1);
      w.gate.reject(new Error("preparation stopped"));
      await assert.rejects(asking, /preparation stopped/);
      noRequest(w);
    } finally { w.db.close(); rmSync(w.dir, { recursive: true, force: true }); }
  });
}

test("a removed session or changed owner cannot receive a secret use after preparation", async () => {
  for (const change of ["remove", "changeOwner"] as const) {
    const w = waitingVault();
    try {
      const asking = w.secrets.ask("s", { item: "test key", reason: "test" });
      w[change](); w.ready(); w.gate.resolve();
      await assert.rejects(asking);
      noRequest(w);
    } finally { w.gate.resolve(); w.db.close(); rmSync(w.dir, { recursive: true, force: true }); }
  }
});

test("a secret save does not survive deletion or a change of workspace, owner or membership during preparation", async () => {
  for (const change of ["remove", "move", "changeOwner", "lockWithoutOwner"] as const) {
    const w = waitingVault();
    try {
      const asking = w.secrets.save("s", { name: "new key", kind: "token", reason: "test", value: "fake", cwd: w.dir });
      w[change](); w.ready(); w.gate.resolve();
      await assert.rejects(asking, /archived or gone|owner or workspace changed|not in the workspace/);
      noRequest(w);
    } finally { w.gate.resolve(); w.db.close(); rmSync(w.dir, { recursive: true, force: true }); }
  }
});

test("a secret save starts its expiry when the request is made after preparation", async () => {
  const w = waitingVault();
  try {
    const asking = w.secrets.save("s", { name: "new key", kind: "token", reason: "test", value: "fake", cwd: w.dir });
    w.advance(2 * 86_400_000); w.ready(); w.gate.resolve();
    await asking;
    assert.equal(w.secrets.pending("w", null, { sub: "p", email: "p@example.test" }).length, 1);
  } finally { w.gate.resolve(); w.db.close(); rmSync(w.dir, { recursive: true, force: true }); }
});

test("a secret save uses security mode enabled while its chat order is prepared", async () => {
  const w = waitingVault();
  try {
    const asking = w.secrets.save("s", { name: "new key", kind: "token", reason: "test", value: "fake", cwd: w.dir });
    w.lockWithOwner(); w.ready(); w.gate.resolve();
    await asking;
    const row = w.db.prepare("SELECT body FROM vault_requests").get() as { body: string };
    const request = JSON.parse(row.body);
    assert.equal(request.vault, "", "the owner has no vault set up yet");
    assert.notEqual(request.box, "", "the request is for a vault, not the plain library");
    assert.equal(w.secrets.carried().keeper.boxes.length, 1);
  } finally { w.gate.resolve(); w.db.close(); rmSync(w.dir, { recursive: true, force: true }); }
});

test("a ready secret request does not prepare the chat order", async () => {
  for (const operation of ["ask", "save"] as const) {
    const w = waitingVault();
    try {
      w.ready();
      if (operation === "ask") await w.secrets.ask("s", { item: "test key", reason: "test" });
      else await w.secrets.save("s", { name: "new key", kind: "token", reason: "test", value: "fake", cwd: w.dir });
      assert.equal(w.prepared(), 0);
      assert.deepEqual(w.posts, ["latest"]);
    } finally { w.gate.resolve(); w.db.close(); rmSync(w.dir, { recursive: true, force: true }); }
  }
});

test("a session removed during browser capture does not keep the secret", async () => {
  const w = waitingVault();
  try {
    const asking = w.secrets.save("s", { name: "test site", kind: "browser", reason: "test", hosts: ["example.com"], cwd: w.dir });
    w.remove();
    w.cookies.resolve(JSON.stringify([{ name: "fake", value: "fake", domain: "example.com", path: "/" }]));
    await assert.rejects(asking, /archived or gone/);
    assert.equal(w.prepared(), 0);
    noRequest(w);
  } finally { w.gate.resolve(); w.db.close(); rmSync(w.dir, { recursive: true, force: true }); }
});

test("a browser sign-in is captured once even if its chat needs preparation afterwards", async () => {
  const w = waitingVault();
  try {
    const asking = w.secrets.save("s", { name: "test site", kind: "browser", reason: "test", hosts: ["example.com"], cwd: w.dir });
    assert.equal(w.captured(), 1);
    w.cookies.resolve(JSON.stringify([{ name: "fake", value: "fake", domain: "example.com", path: "/" }]));
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(w.prepared(), 1);
    noRequest(w);
    w.ready(); w.gate.resolve();
    await asking;
    assert.equal(w.captured(), 1);
    assert.deepEqual(w.posts, ["latest"]);
    assert.equal(w.db.prepare("SELECT COUNT(*) AS n FROM vault_requests").get()?.n, 1);
  } finally { w.gate.resolve(); w.db.close(); rmSync(w.dir, { recursive: true, force: true }); }
});

// Agents asking to keep a secret in the vault ( agent 存入; src/vault/secrets.ts `save`): sealed to the
// devices of whoever started the chat and decided by them alone, kept once their app wrote it into their vault (or,
// without security mode, written into their plain library here), sealed to a device set up later, a command's output
// taken without being shown, or one its owner types in on the card. Nothing waits on time: a request's answer is awaited
// only once it is decided.
import assert from "node:assert/strict";
import { createPublicKey, generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { type Entry, apply as applyLock, entryHash, genesis, signedBytes as lockBytes } from "../src/cloud/lock.ts";
import { routes as requestRoutes } from "../src/api/routes/vault-requests.ts";
import { routes as vaultRoutes } from "../src/api/routes/vault.ts";
import { type BoxCert, type Deny, type Grant, type Item, type Request, type Sig, type Vault, TAG, encryptWith, grantContext, itemContext, keyContext, newBoxPair, openSeal, saveContext, seal, signedBytes } from "../src/vault/crypto.ts";
import { PLAIN, PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { vaultTools } from "../src/vault/tool.ts";
import { VaultStore } from "../src/vault/store.ts";
import { STILLFAIL_SURFACE } from "../src/store/store.ts";
import { isFor } from "../src/api/events.ts";
import { withoutUseReader } from "./vault-no-reader.ts";

const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ";
const VAULT = "v_01HZZZZZZZZZZZZZZZZZZZZZZZ";
const PASSWORD = "correct-horse-battery-staple-7";

function ed() {
  const key = generateKeyPairSync("ed25519").privateKey;
  const hex = Buffer.from(createPublicKey(key).export({ format: "jwk" }).x as string, "base64url").toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Buffer) => nodeSign(null, bytes, key).toString("hex") };
}
type Key = ReturnType<typeof ed>;
type Person = { sub: string; signer: Key; base: Key; box: { pub: string; priv: Uint8Array } };
const fill = (b: number, n = 32) => new Uint8Array(n).fill(b);
const tick = () => new Promise((r) => setImmediate(r));

function signed<T extends Record<string, unknown>>(o: T, tag: string, key: Key): T & { sig: Sig } {
  return { ...o, sig: { key: key.id, alg: "Ed25519", sig: key.sign(signedBytes(o, tag)) } };
}

/// A lock: alice and bob, each with a device; alice's vault, keyed to her device.
function world(otherDevices = 0, sameEmail = false) {
  const [alice, bob] = ["alice", "bob"].map((sub) => ({ sub, signer: ed(), base: ed(), box: newBoxPair() })) as [Person, Person];
  const extras = Array.from({ length: otherDevices }, (_, i) => ({ id: i.toString(16).padStart(64, "0"), sub: "bob", kind: "app", label: "bob", sign_key: bob.signer.id }));
  const body = {
    owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: [{ sub: "alice", email: "alice@x.com", role: "owner" }, { sub: "bob", email: sameEmail ? "alice@x.com" : "bob@x.com", role: "member" },
      ...Array.from({ length: otherDevices }, (_, i) => ({ sub: `other-${i}`, email: `other-${i}@x.com`, role: "member" }))],
    devices: [...[alice, bob].map((p) => ({ id: p.base.hex, sub: p.sub, kind: "app", label: p.sub, sign_key: p.signer.id })), ...extras],
    passkeys: [], stations: [], gateways: [],
  };
  const e = { v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body } as Omit<Entry, "sig">;
  const state = genesis({ ...e, sig: { key: alice.signer.id, alg: "Ed25519" as const, sig: alice.signer.sign(lockBytes(entryHash(e as Entry))) } });
  const cert = (p: Person): BoxCert => signed({ v: 1 as const, ws: WS, device: p.base.hex, box: p.box.pub, at: 1000 }, TAG.box, p.signer);
  const vault: Vault = signed(
    { v: 1 as const, ws: WS, id: VAULT, seq: 0, owner: "alice", name: "Personal", members: ["alice"], epoch: 0, keys: [{ cert: cert(alice), wrapped: seal(alice.box.pub, fill(4), keyContext(WS, VAULT, 0)) }], at: 1000 },
    TAG.vault, alice.signer,
  );
  return { alice, bob, state, vault, cert, extras };
}

/// The item alice's app writes for request `r`: what the station sealed to her, under the request's item id.
function written(r: Request, by: Person, fields: Record<string, string>): Item {
  const plain = { kind: r.save!.kind, name: r.save!.name, fields, domains: [], notes: "" };
  return signed(
    { v: 1 as const, ws: WS, vault: VAULT, id: r.item, version: 0, epoch: 0, ct: encryptWith(fill(4), Buffer.from(JSON.stringify(plain)), itemContext(WS, VAULT, r.item, 0, 0), fill(5, 12)), listing: { name: r.save!.name, kind: r.save!.kind, modes: r.save!.modes, hosts: r.save!.hosts }, at: 1000 },
    TAG.item, by.signer,
  );
}

function harness(lock: (ws: string | null) => ReturnType<typeof world>["state"] | null, starter = "alice@x.com", dbFile = ":memory:", observe?: (db: DatabaseSync) => DatabaseSync) {
  const db = new DatabaseSync(dbFile);
  const connection = observe?.(db) ?? db;
  const vaults = new VaultStore(connection);
  const plain = new PlainStore(connection);
  const notified: [string, string][] = [];
  const cards: { text: string; card: any }[] = [];
  const withdrawn: string[] = [];
  let hidden = false;
  let onPost: (() => void) | null = null;
  let sessionWs: string | null = null;
  // Who wrote in the session's chats, as creator references (`Store.participants`).
  const people: string[] = [starter.toLowerCase()];
  const hub = {
    store: {
      getSession: (k: string) => (k === "s1" ? { key: "s1", ws: sessionWs, workspace: "/tmp", archivedAt: null } : null),
      starter: () => starter.toLowerCase(),
      participants: (k: string) => new Map(k === "s1" ? [["s1", people]] : []),
      latestThread: () => ({ connect: "c", thread: { id: 1, channel: "CHAT", threadTs: "1.0", surface: STILLFAIL_SURFACE } }),
      sessionThreadById: () => ({ connect: "c", thread: { id: 1, channel: "CHAT", threadTs: "1.0", surface: STILLFAIL_SURFACE } }),
      withdrawCard: (_session: string, _thread: number, ts: string) => (withdrawn.push(ts), true),
      restateCard: () => true,
      insertMessage: (m: { text: string; card: unknown }) => (cards.push({ text: m.text, card: m.card }), hidden = false, [cards.length]),
      pendingCardHeader: () => hidden || cards.length === 0 ? null : [{ ts: String(cards.length) }, cards.at(-1)!.card],
      subscribe: () => () => {},
    },
    chat: () => ({ post: async () => { onPost?.(); return String(cards.length + 1); } }),
    shared: () => {},
    notify: (k: string, text: string) => notified.push([k, text]),
  };
  const dir = mkdtempSync(join(tmpdir(), "vault-save-"));
  // The chats' browsers: the cookies each was asked for (`jar`, as JSON) and the sign-ins put in.
  const browser = { jar: "[]", at: 1_000_000, asked: [] as [string, string[], boolean][], signedIn: [] as [string, { request: string; workspace?: string; sites: string[]; cookies: string; until: number }][], extended: [] as [string, string, number][] };
  const browsers = {
    cookies: async (session: string, sites: string[], station: boolean) => (browser.asked.push([session, sites, station]), browser.jar),
    signIn: async (session: string, d: { request: string; sites: string[]; cookies: string; until: number }) => void browser.signedIn.push([session, d]),
    extendSignIn: (session: string, request: string, until: number) => void browser.extended.push([session, request, until]),
  };
  // (a database in a file: the use index's work on this connection, no reader's process beside it; ./vault-no-reader.ts)
  const make = (backfill?: { previousGone?: Promise<void> }) => new Secrets({ db: withoutUseReader(connection), vaults, plain, home: () => WS, hub: hub as never, data: dir, lock, now: () => browser.at, browsers, ...(backfill ? { backfill } : {}) });
  return { db, hub, vaults, plain, notified, people, cards, withdrawn, dir, make, browser, secrets: make(), hideCard: () => { hidden = true; }, occupyCard: () => { cards.push({ text: "another question", card: { type: "text" } }); hidden = false; }, onPost: (f: (() => void) | null) => { onPost = f; }, setSessionWs: (ws: string | null) => { sessionWs = ws; } };
}

function requestWriteHook() {
  let before: (() => void) | undefined;
  const observe = (db: DatabaseSync) => new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!/^(?:INSERT INTO|UPDATE) vault_requests\b/i.test(sql.trim())) return statement;
      return new Proxy(statement, { get(inner, key) {
        if (key === "run") return (...args: any[]) => {
          const go = before; before = undefined; go?.();
          return (inner.run as (...args: any[]) => unknown).apply(inner, args);
        };
        const value = Reflect.get(inner, key, inner);
        return typeof value === "function" ? value.bind(inner) : value;
      } });
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  return { observe, before: (f: () => void) => { before = f; } };
}

/// What the agent was told of request `asked` once decided: secret_save answers at once that it waits, and the decision
/// comes to the session as a notice.
const decided = async (h: { notified: [string, string][] }, asked: Promise<string>) => {
  assert.match(await asked, /You are told in this session when it is decided/);
  const [session, text] = h.notified.at(-1)!;
  assert.equal(session, "s1");
  return text;
};
const pendingOf = (secrets: Secrets, lock: ReturnType<typeof world>["state"] | null, email: string, sub = email.split("@")[0]!) => secrets.pending(WS, lock, { sub, email });
const opened = (r: Request, p: Person) => JSON.parse(Buffer.from(openSeal(p.box.priv, r.sealed!.find((s) => s.box === p.box.pub)!.secret, saveContext(WS, r.id))).toString());

for (const change of ["member.remove", "device.remove", "member"] as const) test(`a pending-request read checks ${change} while old requests are prepared`, async () => {
  const w = world();
  let current = w.state;
  let ready!: () => void;
  const preparing = new Promise<void>((resolve) => { ready = resolve; });
  const secrets = { preparePending: () => preparing, pending: () => [{ id: "private" }] };
  const route = requestRoutes({ secrets: secrets as never, plain: {} as never, lock: () => current })
    .find((r) => r.method === "GET" && r.pattern.test("/vault/requests"))!;
  const answer = route.handle({ viewer: { sub: "bob", email: "bob@x.com", workspace: WS, device: w.bob.base.hex } } as never, []);
  const body = change === "member.remove" ? { sub: "bob" } : change === "device.remove" ? { id: w.bob.base.hex } : { sub: "carol", email: "carol@x.com", role: "member" };
  const entry = { v: 1 as const, ws: WS, seq: current.seq + 1, prev: current.head, at: 1001, kind: change, body };
  current = applyLock(current, { ...entry, sig: { key: w.alice.signer.id, alg: "Ed25519", sig: w.alice.signer.sign(lockBytes(entryHash(entry as Entry))) } }, 1001);
  ready();
  assert.equal((await answer).status, change === "member" ? 200 : 403);
});

test("a cancelled pending-request read does not settle requests after preparation", async () => {
  let ready!: () => void;
  const preparing = new Promise<void>((resolve) => { ready = resolve; });
  let read = false;
  const secrets = { preparePending: () => preparing, pending: () => { read = true; return []; } };
  const route = requestRoutes({ secrets: secrets as never, plain: {} as never, lock: () => null })
    .find((r) => r.method === "GET" && r.pattern.test("/vault/requests"))!;
  const controller = new AbortController();
  const answer = route.handle({ viewer: { sub: "bob", email: "bob@x.com", workspace: WS }, signal: controller.signal } as never, []);
  controller.abort();
  const result = await Promise.race([answer, tick().then(() => null)]);
  ready();
  assert.equal(result?.status, 503);
  assert.equal(read, false);
});

test("cancelling one pending-request read leaves another caller's preparation intact", async () => {
  let ready!: () => void;
  const preparing = new Promise<void>((resolve) => { ready = resolve; });
  let reads = 0;
  const secrets = { preparePending: () => preparing, pending: () => { reads++; return []; } };
  const route = requestRoutes({ secrets: secrets as never, plain: {} as never, lock: () => null })
    .find((r) => r.method === "GET" && r.pattern.test("/vault/requests"))!;
  const controller = new AbortController(), viewer = { sub: "bob", email: "bob@x.com", workspace: WS };
  const cancelled = route.handle({ viewer, signal: controller.signal } as never, []);
  const remaining = route.handle({ viewer } as never, []);
  controller.abort();
  assert.equal((await cancelled).status, 503);
  ready();
  assert.equal((await remaining).status, 200);
  assert.equal(reads, 1);
});

test("a pending-request read retries if security mode ends while old requests are prepared", async () => {
  const w = world();
  let current: typeof w.state | null = w.state, ready!: () => void;
  const preparing = new Promise<void>((resolve) => { ready = resolve; });
  const secrets = { preparePending: () => preparing, pending: () => { throw new Error("must not read"); } };
  const route = requestRoutes({ secrets: secrets as never, plain: {} as never, lock: () => current })
    .find((r) => r.method === "GET" && r.pattern.test("/vault/requests"))!;
  const answer = route.handle({ viewer: { sub: "bob", email: "bob@x.com", workspace: WS, device: w.bob.base.hex } } as never, []);
  current = null;
  ready();
  assert.equal((await answer).status, 409);
});

test("a pending-request read prepares vault membership if security mode starts while it waits", async () => {
  const w = world();
  let current: typeof w.state | null = null, ready!: () => void;
  const preparing = new Promise<void>((resolve) => { ready = resolve; });
  const scopes: boolean[] = [];
  const secrets = { preparePending: (_ws: string, members: boolean) => { scopes.push(members); return scopes.length === 1 ? preparing : Promise.resolve(); }, pending: () => [] };
  const route = requestRoutes({ secrets: secrets as never, plain: {} as never, lock: () => current })
    .find((r) => r.method === "GET" && r.pattern.test("/vault/requests"))!;
  const answer = route.handle({ viewer: { sub: "bob", email: "bob@x.com", workspace: WS, device: w.bob.base.hex } } as never, []);
  current = w.state;
  ready();
  assert.equal((await answer).status, 200);
  assert.deepEqual(scopes, [false, true]);
});

test("a still-needed secret save can be asked again without reading the secret again", async () => {
  const h = harness(() => null);
  try {
    await h.secrets.save("s1", { name: "Test key", kind: "token", reason: "keep it", value: "test-key", cwd: h.dir });
    const request = h.cards[0]!.card.vault.request;
    h.hideCard();
    const tool = vaultTools(h.secrets, () => h.dir).find((t) => t.name === "secret_reask")!;
    await tool.run("s1", { request });
    assert.equal(h.cards.length, 2);
    assert.equal(h.cards[1]!.card.vault.request, request, "the same request and secret are used");
    await tool.run("s1", { request });
    assert.equal(h.cards.length, 2, "an active card is not posted again");
    h.occupyCard();
    await assert.rejects(tool.run("s1", { request }), /Another card is pending/);
    assert.equal(h.cards.length, 3, "a different question was not replaced");
    assert.notEqual(typeof h.secrets.savedPlain(WS, null, "alice@x.com", { request }), "string");
    await assert.rejects(tool.run("s1", { request }), /no longer pending/i);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a secret reask rechecks its decision after old card preparation", async () => {
  const h = harness(() => null), started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  try {
    await h.secrets.save("s1", { name: "Test key", kind: "token", reason: "keep it", value: "test-key", cwd: h.dir });
    const request = h.cards[0]!.card.vault.request;
    h.hideCard();
    let ready = false;
    (h.hub.store as any).pendingCardHeaderIfReady = () => ready ? h.hub.store.pendingCardHeader() : undefined;
    (h.hub as any).prepareCardPosts = async () => { started.resolve(); await release.promise; ready = true; };
    const reask = h.secrets.reask("s1", request);
    void reask.catch(() => {});
    const waiting = await Promise.race([started.promise.then(() => true), reask.then(() => false, () => false)]);
    assert.equal(waiting, true, "the reask waits for old card preparation");
    assert.notEqual(typeof h.secrets.savedPlain(WS, null, "alice@x.com", { request }), "string");
    release.resolve();
    await assert.rejects(reask, /no longer pending/);
    assert.equal(h.cards.length, 1);
  } finally { release.resolve(); rmSync(h.dir, { recursive: true, force: true }); }
});

test("a cancelled secret reask does not post after old card preparation", async () => {
  const h = harness(() => null), started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  const controller = new AbortController();
  try {
    await h.secrets.save("s1", { name: "Test key", kind: "token", reason: "keep it", value: "test-key", cwd: h.dir });
    const request = h.cards[0]!.card.vault.request;
    h.hideCard();
    let ready = false, passed: AbortSignal | undefined;
    (h.hub.store as any).pendingCardHeaderIfReady = () => ready ? h.hub.store.pendingCardHeader() : undefined;
    (h.hub as any).prepareCardPosts = async (_threads: number[], signal?: AbortSignal) => { passed = signal; started.resolve(); await release.promise; ready = true; };
    const tool = vaultTools(h.secrets, () => h.dir).find((t) => t.name === "secret_reask")!;
    const reask = tool.run("s1", { request }, controller.signal);
    void reask.catch(() => {});
    assert.equal(await Promise.race([started.promise.then(() => true), reask.then(() => false, () => false)]), true);
    assert.equal(passed, controller.signal);
    controller.abort();
    release.resolve();
    const error = await reask.then(() => null, (e: Error) => e);
    assert.equal(h.cards.length, 1, "the cancelled call did not issue a new card");
    assert.equal(error?.name, "AbortError");
  } finally { release.resolve(); rmSync(h.dir, { recursive: true, force: true }); }
});

test("a secret reask does not record a card decided during final old-card preparation", async () => {
  const h = harness(() => null), started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  try {
    await h.secrets.save("s1", { name: "Test key", kind: "token", reason: "keep it", value: "test-key", cwd: h.dir });
    const request = h.cards[0]!.card.vault.request;
    h.hideCard();
    let reads = 0, ready = false;
    (h.hub.store as any).pendingCardHeaderIfReady = () => ++reads === 1 || ready ? h.hub.store.pendingCardHeader() : undefined;
    (h.hub as any).prepareCardPosts = async () => { started.resolve(); await release.promise; ready = true; };
    const reask = h.secrets.reask("s1", request);
    void reask.catch(() => {});
    const waiting = await Promise.race([started.promise.then(() => true), reask.then(() => false, () => false)]);
    assert.equal(waiting, true, "the final card check waits for preparation");
    assert.notEqual(typeof h.secrets.savedPlain(WS, null, "alice@x.com", { request }), "string");
    release.resolve();
    await assert.rejects(reask, /no longer pending/);
    assert.equal(h.cards.length, 1, "a card for the decided request was not recorded");
  } finally { release.resolve(); rmSync(h.dir, { recursive: true, force: true }); }
});

test("a secret kept for and used by the person the agent names, who wrote in the chat; left out, the chat's starter", async () => {
  // A chat started in Slack (its starter no still.fail account), bob writing in it from the still.fail app.
  const h = harness(() => null, "slack:c:u1");
  h.people.push("bob@x.com");
  try {
    const tools = vaultTools(h.secrets, () => h.dir);
    const list = tools.find((t) => t.name === "secret_list")!, use = tools.find((t) => t.name === "secret_use")!, save = tools.find((t) => t.name === "secret_save")!;
    await assert.rejects(save.run("s1", { name: "Kimi key", about: "Kimi 的 API key", kind: "token", reason: "keep it", value: "test-key", person: "carol@x.com" }), /carol@x\.com has not written in this chat: name one of the people who wrote in it from still\.fail: bob@x\.com/);
    assert.equal(h.cards.length, 0);

    await save.run("s1", { name: "Kimi key", about: "Kimi 的 API key", kind: "token", reason: "keep it", value: "test-key", person: "Bob@x.com" });
    const request = h.cards[0]!.card.vault.request;
    assert.equal(h.cards[0]!.card.assignee, "bob@x.com", "the card is bob's to decide");
    assert.match(h.secrets.savedPlain(WS, null, "alice@x.com", { request }) as string, /only the person it is kept for/);
    assert.notEqual(typeof h.secrets.savedPlain(WS, null, "bob@x.com", { request }), "string");

    // His, not the starter's: listed and asked for only by naming him.
    // (kept, this chat holds its grant either way)
    const listed = async (args: Record<string, unknown>) => JSON.parse(await list.run("s1", args) as string).secrets.map((x: { name: string }) => x.name);
    assert.deepEqual(await listed({}), []);
    assert.deepEqual(await listed({ person: "bob@x.com" }), ["Kimi key"]);
    await assert.rejects(use.run("s1", { item: "Kimi key", reason: "use it" }), /No secret named "Kimi key"/);
    await use.run("s1", { item: "Kimi key", reason: "use it", command: "true", person: "bob@x.com" });
    assert.equal(h.cards[1]!.card.assignee, "bob@x.com");

    // Left out, it is the starter's as before.
    await save.run("s1", { name: "Other", about: "另一个", kind: "token", reason: "keep it", value: "other" });
    assert.equal(h.cards[2]!.card.assignee, "slack:c:u1");
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a still-needed secret use can be asked again as the same request", async () => {
  const h = harness(() => null);
  try {
    await h.secrets.save("s1", { name: "Test key", kind: "token", reason: "keep it", value: "test-key", cwd: h.dir });
    const saved = h.secrets.savedPlain(WS, null, "alice@x.com", { request: h.cards[0]!.card.vault.request });
    assert.notEqual(typeof saved, "string");
    await h.secrets.ask("s1", { item: "Test key", reason: "use it", command: "true" });
    const request = h.cards[1]!.card.vault.request;
    h.hideCard();
    const tool = vaultTools(h.secrets, () => h.dir).find((t) => t.name === "secret_reask")!;
    await tool.run("s1", { request });
    assert.equal(h.cards[2]!.card.vault.request, request);
    assert.equal(h.cards[2]!.card.vault.command, "true");
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a vanished secret is not reasked after a restart", async () => {
  const h = harness(() => null);
  try {
    await h.secrets.save("s1", { name: "Test key", kind: "token", reason: "keep it", value: "test-key", cwd: h.dir });
    const request = h.cards[0]!.card.vault.request;
    h.hideCard();
    const restarted = h.make();
    await assert.rejects(restarted.reask("s1", request), /no longer pending/);
    assert.equal(h.cards.length, 1);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a decision arriving while a secret card is reissued is not reset", async () => {
  const h = harness(() => null);
  try {
    await h.secrets.save("s1", { name: "Test key", kind: "token", reason: "keep it", value: "test-key", cwd: h.dir });
    const request = h.cards[0]!.card.vault.request;
    h.hideCard();
    h.onPost(() => {
      h.onPost(null);
      assert.notEqual(typeof h.secrets.savedPlain(WS, null, "alice@x.com", { request }), "string");
    });
    await assert.rejects(h.secrets.reask("s1", request), /no longer pending/);
    assert.deepEqual(h.withdrawn, ["1"], "the old card was closed");
    assert.equal(h.cards.length, 1, "no new card was recorded after the decision");
    assert.equal(h.secrets.held("s1")[0]!.request.id, request, "the decision survived");
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a decision after the last reask read is not overwritten by the new card", async () => {
  const h = harness(() => null);
  try {
    await h.secrets.save("s1", { name: "Test key", kind: "token", reason: "keep it", value: "test-key", cwd: h.dir });
    const request = h.cards[0]!.card.vault.request;
    h.hideCard();
    const insert = h.hub.store.insertMessage;
    let posted = false, reads = 0;
    h.hub.store.insertMessage = (message) => { const result = insert(message); posted = true; return result; };
    const prepare = h.db.prepare.bind(h.db);
    (h.db as any).prepare = (sql: string) => {
      const stmt = prepare(sql);
      if (sql !== "SELECT body, thread, card_ts FROM vault_requests WHERE ws = ? AND id = ?") return stmt;
      return new Proxy(stmt, { get(target, property) {
        if (property === "get") return (...args: any[]) => {
          const row = target.get(...args);
          if (posted && ++reads === 2 && row !== undefined) {
            const body = { ...JSON.parse(String(row.body)), status: "denied" };
            prepare("UPDATE vault_requests SET status='denied',body=? WHERE ws=? AND id=?").run(JSON.stringify(body), WS, request);
          }
          return row;
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
    };
    await assert.rejects(h.secrets.reask("s1", request), /changed|no longer pending/);
    assert.equal(prepare("SELECT status FROM vault_requests WHERE ws=? AND id=?").get(WS, request)?.status, "denied");
    assert.deepEqual(h.withdrawn, ["2"]);
  } finally { rmSync(h.dir, { recursive: true, force: true }); }
});

test("a new question arriving while a secret card is reissued is not replaced", async () => {
  const h = harness(() => null);
  try {
    await h.secrets.save("s1", { name: "Test key", kind: "token", reason: "keep it", value: "test-key", cwd: h.dir });
    const request = h.cards[0]!.card.vault.request;
    h.hideCard();
    h.onPost(() => { h.onPost(null); h.occupyCard(); });
    await assert.rejects(h.secrets.reask("s1", request), /Another card is pending/);
    assert.equal(h.cards.length, 2);
    assert.equal(h.cards[1]!.text, "another question");
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a secret to keep in a vault: sealed to its owner's devices, decided by them alone, kept once their app wrote it", async () => {
  const w = world();
  const h = harness(() => w.state);
  h.vaults.putVault(w.vault);
  h.vaults.putBox(w.cert(w.alice));
  h.vaults.putBox(w.cert(w.bob));
  try {
    assert.equal(h.secrets.status("s1"), "on");
    await assert.rejects(h.secrets.save("s1", { name: "UX7", kind: "login", reason: "x", value: "p", command: "true", cwd: h.dir }), /not both/);
    await assert.rejects(h.secrets.save("s1", { name: "UX7", kind: "login", reason: "x", value: "p", modes: ["ssh"], cwd: h.dir }), /SSH key is given by ssh/);
    await assert.rejects(h.secrets.save("s1", { name: "UX7", kind: "token", reason: "x", value: "p", modes: ["proxy"], cwd: h.dir }), /names its hosts/);

    const asked = h.secrets.save("s1", { name: "测试服务登录", kind: "login", reason: "log in to the test service", value: PASSWORD, username: "demo-user", env: "SERVICE_PASSWORD", cwd: h.dir });
    await tick();
    const [r] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.ok(r && r.save && r.vault === VAULT && r.owner === "alice@x.com" && r.box !== "");
    assert.deepEqual(r.save, { kind: "login", name: "测试服务登录", modes: ["env"], hosts: [], env: "SERVICE_PASSWORD", username: "demo-user" });
    // Sealed to her device alone (bob's is his), nothing of it in the clear.
    assert.deepEqual(r.sealed!.map((s) => s.device), [w.alice.base.hex]);
    assert.deepEqual(opened(r, w.alice), { username: "demo-user", password: PASSWORD });
    assert.ok(!JSON.stringify(r).includes(PASSWORD));
    // The card: what it is and whose, to keep or turn down.
    const { text, card } = h.cards[0]!;
    assert.equal(text, "申请将「测试服务登录」存入密钥库（登录 · demo-user）：log in to the test service");
    assert.equal(card.assignee, "alice@x.com");
    assert.deepEqual(card.options.map((o: { label: string }) => o.label), ["存入密钥库", "拒绝"]);
    assert.deepEqual(card.vault.save, { kind: "login", username: "demo-user" });

    // bob neither sees nor decides it; alice's word comes only once the item is in her vault here.
    assert.deepEqual(pendingOf(h.secrets, w.state, "bob@x.com"), []);
    assert.match(h.secrets.saved(w.state, "bob", { request: r.id, vault: VAULT })!, /only the person it is kept for/);
    assert.match(h.secrets.grant(w.state, "alice", { request: r.id } as never)!, /POST vault\/saves/);
    assert.match(h.secrets.saved(w.state, "alice", { request: r.id, vault: VAULT })!, /not in that vault here/);
    h.vaults.putItem(written(r, w.alice, { username: "demo-user", password: PASSWORD }));
    // Her app's grant to this chat comes with it, sealed to the request's box.
    const grant: Grant = signed(
      { v: 1 as const, ws: WS, request: r.id, vault: VAULT, item: r.item, mode: "env" as const, hosts: [], scope: "chat" as const, exp: 1000 + 30 * 86400, secret: seal(r.box, Buffer.from(JSON.stringify({ kind: "login", name: "测试服务登录", fields: { username: "demo-user", password: PASSWORD } })), grantContext(WS, r.id)), at: 1000 },
      TAG.grant, w.alice.signer,
    );
    assert.equal(h.secrets.saved(w.state, "alice", { request: r.id, vault: VAULT, grant }), null);
    assert.match(await decided(h, asked), /Kept: 「测试服务登录」 is in alice@x.com's vault now \(item i_\w+\)\. This chat may use it now: secret_run \{grant: "r_/);
    assert.deepEqual(h.secrets.held("s1").map((x) => [x.request.id, x.grant.scope, x.secret.fields.password]), [[r.id, "chat", PASSWORD]]);
    // Now one agents may ask for; the save is no use of it.
    assert.deepEqual(h.secrets.listings("s1").map((l) => l.listing.name), ["测试服务登录"]);
    assert.deepEqual(await h.secrets.uses(WS, w.state, VAULT, { sub: "alice", email: "alice@x.com" }), []);
    assert.match(h.secrets.saved(w.state, "alice", { request: r.id, vault: VAULT })!, /the request is granted/);

    // Turned down from one of her devices, signed; not by bob.
    const again = h.secrets.save("s1", { name: "Other", kind: "token", reason: "y", value: "tok", cwd: h.dir });
    await tick();
    const [second] = pendingOf(h.secrets, w.state, "alice@x.com");
    const deny = (by: Person): Deny => signed({ v: 1 as const, ws: WS, request: second!.id, at: 1000 }, TAG.deny, by.signer);
    assert.match(h.secrets.deny(w.state, "bob", deny(w.bob))!, /only the person it is kept for/);
    assert.match(h.secrets.deny(w.state, "alice", deny(w.bob))!, /one of their devices/);
    assert.equal(h.secrets.deny(w.state, "alice", deny(w.alice)), null);
    assert.match(await decided(h, again), /chose not to keep 「Other」/);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a secret to keep while the vault is not turned on: it waits, sealed to the device once it is set up; a restart forgets one sealed to none", async () => {
  const w = world();
  const h = harness(() => w.state);
  try {
    assert.equal(h.secrets.status("s1"), "off");
    const asked = h.secrets.save("s1", { name: "测试服务登录", kind: "login", reason: "test service", value: PASSWORD, cwd: h.dir });
    await tick();
    let [r] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.ok(r && r.vault === "" && r.sealed!.length === 0);

    // A device of bob's changes nothing of alice's; hers gets it sealed.
    const told: Request[] = [];
    h.secrets.listen((x) => told.push(x));
    h.secrets.boxed(w.state, w.cert(w.bob));
    assert.equal(told.length, 0);
    h.vaults.putBox(w.cert(w.alice));
    h.secrets.boxed(w.state, w.cert(w.alice));
    [r] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.deepEqual(opened(r!, w.alice), { password: PASSWORD });
    assert.equal(told.length, 1);

    // Turned on now: kept from that device as any.
    h.vaults.putVault(w.vault);
    h.vaults.putItem(written(r!, w.alice, { password: PASSWORD }));
    assert.equal(h.secrets.saved(w.state, "alice", { request: r!.id, vault: VAULT }), null);
    assert.match(await decided(h, asked), /Kept: 「测试服务登录」.*When you need it, ask with secret_use/);

    // One sealed to no device is gone with a restart; one sealed to a device stays.
    void h.secrets.save("s1", { name: "Lost", kind: "token", reason: "z", value: "tok", cwd: h.dir });
    void h.secrets.save("s1", { name: "Stays", kind: "token", reason: "z", value: "tok", cwd: h.dir });
    await tick();
    h.db.prepare("UPDATE vault_requests SET body = json_set(body, '$.sealed', json('[]')) WHERE json_extract(body, '$.save.name') = 'Lost'").run();
    const after = h.make();
    assert.deepEqual(pendingOf(after, w.state, "alice@x.com").map((x) => x.save!.name), ["Stays"]);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a device registered while the save card is being posted can approve the secret", async () => {
  const w = world();
  const h = harness(() => w.state);
  try {
    h.onPost(() => {
      const other = w.cert(w.bob);
      h.vaults.putBox(other);
      h.secrets.boxed(w.state, other);
      const cert = w.cert(w.alice);
      h.vaults.putBox(cert);
      h.secrets.boxed(w.state, cert);
    });
    const asked = h.secrets.save("s1", { name: "During post", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    assert.match(await asked, /You are told in this session when it is decided/);
    const [request] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.ok(request);
    assert.equal(request.sealed?.length, 1);
    assert.deepEqual(opened(request, w.alice), { value: "sample" });
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a stale certificate cannot replace the key a waiting save was sealed to", async () => {
  const w = world();
  const h = harness(() => w.state);
  try {
    const old = { ...w.alice, box: newBoxPair() }, newer = { ...w.alice, box: newBoxPair() };
    const cert = (p: Person, at: number) => signed({ v: 1 as const, ws: WS, device: p.base.hex, box: p.box.pub, at }, TAG.box, p.signer);
    const staleCert = cert(old, 1100), newCert = cert(newer, 1200);
    await h.secrets.save("s1", { name: "Pending", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    assert.deepEqual(pendingOf(h.secrets, w.state, "alice@x.com")[0]!.sealed, []);
    let raced = false;
    const interleaved = new Proxy(h.vaults, { get(target, property) {
      if (property === "putBoxIf") return (incoming: BoxCert, previous: string | null) => {
        if (!raced) {
          raced = true;
          target.putBox(newCert);
          h.secrets.boxed(w.state, newCert);
        }
        return target.putBoxIf(incoming, previous);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const put = vaultRoutes({ vaults: interleaved, lock: () => w.state, boxed: (lock, value) => h.secrets.boxed(lock, value) })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/boxes"))!;
    const answer = await put.handle({ method: "PUT", path: "/vault/boxes", query: [], headers: {}, body: Buffer.from(JSON.stringify(staleCert)),
      viewer: { sub: "alice", workspace: WS, email: "alice@x.com", name: "Alice", role: "owner", device: w.alice.base.hex }, lang: "en" }, []);
    assert.equal(answer.status, 200);
    assert.equal(raced, true);
    const [request] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.deepEqual(request!.sealed!.map((s) => s.box), [newer.box.pub]);
    assert.deepEqual(opened(request!, newer), { value: "sample" });
  } finally { rmSync(h.dir, { recursive: true, force: true }); }
});

test("a newer certificate written before reboxing keeps its key on a waiting save", async () => {
  const w = world();
  const dir = mkdtempSync(join(tmpdir(), "vault-box-concurrent-"));
  const path = join(dir, "data.sqlite");
  const h = harness(() => w.state, "alice@x.com", path);
  h.db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path), otherVaults = new VaultStore(other);
  try {
    const old = { ...w.alice, box: newBoxPair() }, newer = { ...w.alice, box: newBoxPair() };
    const cert = (p: Person, at: number) => signed({ v: 1 as const, ws: WS, device: p.base.hex, box: p.box.pub, at }, TAG.box, p.signer);
    const staleCert = cert(old, 1100), newCert = cert(newer, 1200);
    await h.secrets.save("s1", { name: "Pending", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    let raced = false;
    const interleaved = new Proxy(h.vaults, { get(target, property) {
      if (property === "putBoxIf") return (incoming: BoxCert, previous: string | null) => {
        const saved = target.putBoxIf(incoming, previous);
        if (saved && !raced) {
          raced = true;
          otherVaults.putBox(newCert);
          h.secrets.boxed(w.state, newCert);
        }
        return saved;
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const put = vaultRoutes({ vaults: interleaved, lock: () => w.state, boxed: (lock, value) => h.secrets.boxed(lock, value) })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/boxes"))!;
    await put.handle({ method: "PUT", path: "/vault/boxes", query: [], headers: {}, body: Buffer.from(JSON.stringify(staleCert)),
      viewer: { sub: "alice", workspace: WS, email: "alice@x.com", name: "Alice", role: "owner", device: w.alice.base.hex }, lang: "en" }, []);
    assert.equal(raced, true);
    const [request] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.deepEqual(request!.sealed!.map((s) => s.box), [newer.box.pub]);
    assert.deepEqual(opened(request!, newer), { value: "sample" });
  } finally { await h.secrets.close(); other.close(); h.db.close(); rmSync(h.dir, { recursive: true, force: true }); rmSync(dir, { recursive: true, force: true }); }
});

test("a certificate changed between reboxing and its write is checked again", async () => {
  const w = world(), dir = mkdtempSync(join(tmpdir(), "vault-box-rebox-")), path = join(dir, "data.sqlite");
  const hook = requestWriteHook();
  const h = harness(() => w.state, "alice@x.com", path, hook.observe);
  h.db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path), otherVaults = new VaultStore(other);
  try {
    const old = { ...w.alice, box: newBoxPair() }, newer = { ...w.alice, box: newBoxPair() };
    const cert = (p: Person, at: number) => signed({ v: 1 as const, ws: WS, device: p.base.hex, box: p.box.pub, at }, TAG.box, p.signer);
    const staleCert = cert(old, 1100), newCert = cert(newer, 1200);
    await h.secrets.save("s1", { name: "Pending", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    h.vaults.putBox(staleCert);
    let raced = false;
    hook.before(() => { raced = true; otherVaults.putBox(newCert); });
    h.secrets.boxed(w.state, staleCert);
    assert.equal(raced, true);
    const [request] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.deepEqual(request!.sealed!.map((s) => s.box), [newer.box.pub]);
    assert.deepEqual(opened(request!, newer), { value: "sample" });
  } finally {
    await h.secrets.close(); other.close(); h.db.close();
    rmSync(h.dir, { recursive: true, force: true }); rmSync(dir, { recursive: true, force: true });
  }
});

test("reboxing does not restore a request decided by another connection", async () => {
  const w = world(), dir = mkdtempSync(join(tmpdir(), "vault-box-decided-")), path = join(dir, "data.sqlite");
  const hook = requestWriteHook();
  const h = harness(() => w.state, "alice@x.com", path, hook.observe);
  h.db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path);
  try {
    await h.secrets.save("s1", { name: "Pending", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    const [request] = pendingOf(h.secrets, w.state, "alice@x.com");
    const cert = w.cert(w.alice);
    h.vaults.putBox(cert);
    let raced = false, notifications = 0;
    h.secrets.listen(() => { notifications++; });
    hook.before(() => {
      raced = true;
      other.prepare("UPDATE vault_requests SET status='denied', body=json_set(body, '$.status', 'denied') WHERE ws=? AND id=?").run(WS, request!.id);
    });
    assert.equal(h.secrets.boxed(w.state, cert), true);
    const row = other.prepare("SELECT status, body FROM vault_requests WHERE ws=? AND id=?").get(WS, request!.id) as { status: string; body: string };
    assert.equal(raced, true);
    assert.equal(row.status, "denied");
    assert.equal(JSON.parse(row.body).status, "denied");
    assert.deepEqual(JSON.parse(row.body).sealed, []);
    assert.equal(notifications, 0);
  } finally {
    await h.secrets.close(); other.close(); h.db.close();
    rmSync(h.dir, { recursive: true, force: true }); rmSync(dir, { recursive: true, force: true });
  }
});

test("a busy reboxing retries even if the device does not send its certificate again", async () => {
  const w = world(), dir = mkdtempSync(join(tmpdir(), "vault-box-busy-")), path = join(dir, "data.sqlite");
  const hook = requestWriteHook(), h = harness(() => w.state, "alice@x.com", path, hook.observe);
  h.db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path);
  try {
    await h.secrets.save("s1", { name: "Pending", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    const [request] = pendingOf(h.secrets, w.state, "alice@x.com");
    const cert = w.cert(w.alice);
    let attempts = 0, notifications = 0;
    const told = Promise.withResolvers<void>();
    h.secrets.listen(() => { notifications++; told.resolve(); });
    const interfere = () => {
      attempts++;
      other.prepare("UPDATE vault_requests SET body=json_set(body, '$.reason', ?) WHERE ws=? AND id=?").run(`changed-${attempts}`, WS, request!.id);
      if (attempts < 3) hook.before(interfere);
    };
    hook.before(interfere);
    const put = vaultRoutes({ vaults: h.vaults, lock: () => w.state, boxed: (lock, value) => h.secrets.boxed(lock, value) })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/boxes"))!;
    const answer = await put.handle({ method: "PUT", path: "/vault/boxes", query: [], headers: {}, body: Buffer.from(JSON.stringify(cert)),
      viewer: { sub: "alice", workspace: WS, email: "alice@x.com", name: "Alice", role: "owner", device: w.alice.base.hex }, lang: "en" }, []);
    assert.equal(answer.status, 503);
    const [busy] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.equal(attempts, 3);
    assert.equal(busy!.reason, "changed-3");
    assert.deepEqual(busy!.sealed, []);
    assert.equal(notifications, 0);
    let timer: ReturnType<typeof setTimeout> | undefined;
    try { await Promise.race([told.promise, new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error("reboxing was not retried")), 5000); })]); }
    finally { if (timer !== undefined) clearTimeout(timer); }
    const [finished] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.deepEqual(opened(finished!, w.alice), { value: "sample" });
    assert.equal(finished!.reason, "changed-3");
    assert.equal(notifications, 1);
  } finally {
    await h.secrets.close(); other.close(); h.db.close();
    rmSync(h.dir, { recursive: true, force: true }); rmSync(dir, { recursive: true, force: true });
  }
});

test("a queued reboxing checks that the device is still admitted", async () => {
  const w = world(), dir = mkdtempSync(join(tmpdir(), "vault-box-revoked-")), path = join(dir, "data.sqlite");
  const hook = requestWriteHook();
  let lock = w.state;
  const h = harness(() => lock, "alice@x.com", path, hook.observe);
  h.db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path);
  try {
    await h.secrets.save("s1", { name: "Pending", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    const [request] = pendingOf(h.secrets, w.state, "alice@x.com"), cert = w.cert(w.alice);
    h.vaults.putBox(cert);
    let attempts = 0, notifications = 0;
    h.secrets.listen(() => { notifications++; });
    const interfere = () => {
      attempts++;
      other.prepare("UPDATE vault_requests SET body=json_set(body, '$.reason', ?) WHERE ws=? AND id=?").run(`changed-${attempts}`, WS, request!.id);
      if (attempts < 3) hook.before(interfere);
    };
    hook.before(interfere);
    assert.equal(h.secrets.boxed(lock, cert), false);
    lock = { ...lock, devices: new Map([...lock.devices].filter(([id]) => id !== cert.device)) };
    const retried = Promise.withResolvers<void>(), box = h.vaults.box.bind(h.vaults);
    h.vaults.box = (ws, device) => { retried.resolve(); return box(ws, device); };
    let timer: ReturnType<typeof setTimeout> | undefined;
    try { await Promise.race([retried.promise, new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error("reboxing was not retried")), 5000); })]); }
    finally { if (timer !== undefined) clearTimeout(timer); }
    const row = other.prepare("SELECT body FROM vault_requests WHERE ws=? AND id=?").get(WS, request!.id) as { body: string };
    assert.deepEqual(JSON.parse(row.body).sealed, []);
    assert.equal(notifications, 0);
  } finally {
    await h.secrets.close(); other.close(); h.db.close();
    rmSync(h.dir, { recursive: true, force: true }); rmSync(dir, { recursive: true, force: true });
  }
});

test("stopping the station cancels a queued reboxing", async () => {
  const w = world(), dir = mkdtempSync(join(tmpdir(), "vault-box-stopped-")), path = join(dir, "data.sqlite");
  const hook = requestWriteHook(), h = harness(() => w.state, "alice@x.com", path, hook.observe);
  h.db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path);
  try {
    await h.secrets.save("s1", { name: "Pending", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    const [request] = pendingOf(h.secrets, w.state, "alice@x.com"), cert = w.cert(w.alice);
    h.vaults.putBox(cert);
    let attempts = 0, notifications = 0;
    h.secrets.listen(() => { notifications++; });
    const interfere = () => {
      attempts++;
      other.prepare("UPDATE vault_requests SET body=json_set(body, '$.reason', ?) WHERE ws=? AND id=?").run(`changed-${attempts}`, WS, request!.id);
      if (attempts < 3) hook.before(interfere);
    };
    hook.before(interfere);
    assert.equal(h.secrets.boxed(w.state, cert), false);
    await h.secrets.close();
    await new Promise<void>((resolve) => setTimeout(resolve, 50));
    const row = other.prepare("SELECT body FROM vault_requests WHERE ws=? AND id=?").get(WS, request!.id) as { body: string };
    assert.deepEqual(JSON.parse(row.body).sealed, []);
    assert.equal(notifications, 0);
  } finally {
    await h.secrets.close(); other.close(); h.db.close();
    rmSync(h.dir, { recursive: true, force: true }); rmSync(dir, { recursive: true, force: true });
  }
});

test("a replacement certificate is checked before a waiting secret is sealed to it", async () => {
  const w = world(), h = harness(() => w.state);
  try {
    await h.secrets.save("s1", { name: "Pending", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    const original = w.cert(w.alice), forged = { ...w.cert(w.bob), device: w.alice.base.hex };
    h.vaults.putBox(forged);
    assert.equal(h.secrets.boxed(w.state, original), false);
    assert.deepEqual(pendingOf(h.secrets, w.state, "alice@x.com")[0]!.sealed, []);
  } finally { await h.secrets.close(); h.db.close(); rmSync(h.dir, { recursive: true, force: true }); }
});

test("a save made by the new station during handover receives a certificate from the old station", async () => {
  const w = world(), exit = Promise.withResolvers<void>();
  const dir = mkdtempSync(join(tmpdir(), "vault-save-handover-"));
  const path = join(dir, "data.sqlite");
  const old = harness(() => w.state, "alice@x.com", path);
  old.db.exec("PRAGMA journal_mode=WAL");
  const next = harness(() => w.state, "alice@x.com", path);
  const secrets = next.make({ previousGone: exit.promise });
  let oldClosed = false;
  try {
    await secrets.save("s1", { name: "New save", kind: "token", reason: "test", value: "sample", cwd: next.dir });
    assert.deepEqual(pendingOf(secrets, w.state, "alice@x.com")[0]!.sealed, []);
    const cert = w.cert(w.alice);
    old.vaults.putBox(cert);
    old.secrets.boxed(w.state, cert);
    // The old station did not hold the new station's fields and cannot rebox this save.
    assert.deepEqual(pendingOf(secrets, w.state, "alice@x.com")[0]!.sealed, []);
    await old.secrets.close();
    old.db.close();
    oldClosed = true;
    exit.resolve();
    await tick();
    const [request] = pendingOf(secrets, w.state, "alice@x.com");
    assert.deepEqual(request!.sealed!.map((s) => s.box), [w.alice.box.pub]);
    assert.deepEqual(opened(request!, w.alice), { value: "sample" });
  } finally {
    exit.resolve();
    await secrets.close();
    await next.secrets.close();
    if (!oldClosed) { await old.secrets.close(); old.db.close(); }
    next.db.close();
    rmSync(old.dir, { recursive: true, force: true });
    rmSync(next.dir, { recursive: true, force: true });
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a save still posting when the old station exits includes its last certificate", async () => {
  const w = world(), exit = Promise.withResolvers<void>(), posting = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  const dir = mkdtempSync(join(tmpdir(), "vault-save-posting-")), path = join(dir, "data.sqlite");
  const old = harness(() => w.state, "alice@x.com", path);
  old.db.exec("PRAGMA journal_mode=WAL");
  const next = harness(() => w.state, "alice@x.com", path);
  const secrets = next.make({ previousGone: exit.promise });
  let oldClosed = false;
  try {
    (next.hub as any).chat = () => ({ post: async () => { posting.resolve(); await release.promise; return "1"; } });
    const asked = secrets.save("s1", { name: "Posting", kind: "token", reason: "test", value: "sample", cwd: next.dir });
    await posting.promise;
    const cert = w.cert(w.alice);
    old.vaults.putBox(cert);
    old.secrets.boxed(w.state, cert);
    await old.secrets.close();
    old.db.close();
    oldClosed = true;
    exit.resolve();
    await tick();
    release.resolve();
    await asked;
    const [request] = pendingOf(secrets, w.state, "alice@x.com");
    assert.deepEqual(request!.sealed!.map((s) => s.box), [w.alice.box.pub]);
    assert.deepEqual(opened(request!, w.alice), { value: "sample" });
  } finally {
    release.resolve(); exit.resolve();
    await secrets.close(); await next.secrets.close();
    if (!oldClosed) { await old.secrets.close(); old.db.close(); }
    next.db.close();
    rmSync(old.dir, { recursive: true, force: true });
    rmSync(next.dir, { recursive: true, force: true });
    rmSync(dir, { recursive: true, force: true });
  }
});

test("saving a secret does not read other people's device certificates or traverse their lock devices", async () => {
  const work: { certificates: number; devices: number; members: number; previousKeys: number }[] = [];
  for (const count of [10, 100]) {
    const w = world(count);
    const h = harness(() => w.state);
    try {
      h.vaults.putBox(w.cert(w.alice));
      for (const d of w.extras) h.vaults.putBox(signed({ v: 1 as const, ws: WS, device: d.id, box: w.bob.box.pub, at: 1000 }, TAG.box, w.bob.signer));
      let reading = false, certificates = 0, devices = 0, members = 0, previousKeys = 0;
      const boxes = h.vaults.boxes.bind(h.vaults), box = h.vaults.box.bind(h.vaults);
      h.vaults.boxes = (ws) => { const rows = boxes(ws); if (reading) certificates += rows.length; return rows; };
      h.vaults.box = (ws, id) => { const row = box(ws, id); if (reading && row !== null) certificates++; return row; };
      const entries = w.state.devices[Symbol.iterator].bind(w.state.devices);
      w.state.devices[Symbol.iterator] = function* () { for (const entry of entries()) { if (reading) devices++; yield entry; } return undefined; };
      const memberEntries = w.state.members[Symbol.iterator].bind(w.state.members), memberValues = w.state.members.values.bind(w.state.members);
      w.state.members[Symbol.iterator] = function* () { for (const entry of memberEntries()) { if (reading) members++; yield entry; } return undefined; };
      w.state.members.values = function* () { for (const member of memberValues()) { if (reading) members++; yield member; } return undefined; };
      w.state.signKeys.set(w.alice.base.hex, new Proxy([...Array.from({ length: count }, (_, i) => `old-${i}`), w.alice.signer.id], {
        get(target, property, receiver) { if (reading && typeof property === "string" && /^\d+$/.test(property)) previousKeys++; return Reflect.get(target, property, receiver); },
      }));
      reading = true;
      await h.secrets.save("s1", { name: "Bounded", kind: "token", reason: "test", value: "sample", cwd: h.dir });
      reading = false;
      const [request] = pendingOf(h.secrets, w.state, "alice@x.com");
      assert.ok(request);
      assert.deepEqual(opened(request, w.alice), { value: "sample" });
      work.push({ certificates, devices, members, previousKeys });
    } finally {
      rmSync(h.dir, { recursive: true, force: true });
    }
  }
  assert.deepEqual(work[0], work[1]);
  assert.ok(work[0]!.certificates <= 2);
  assert.ok(work[0]!.devices <= 2);
  assert.ok(work[0]!.members <= 2);
  assert.equal(work[0]!.previousKeys, 0);
});

test("a waiting save is available after a handover before requests are reboxed", async () => {
  const w = world();
  const h = harness(() => w.state);
  try {
    await h.secrets.save("s1", { name: "Carried", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    const next = h.make();
    next.carry(JSON.parse(JSON.stringify(h.secrets.carried())));
    const cert = w.cert(w.alice);
    h.vaults.putBox(cert);
    next.boxed(w.state, cert);
    const [request] = pendingOf(next, w.state, "alice@x.com");
    assert.ok(request);
    assert.deepEqual(opened(request, w.alice), { value: "sample" });
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a device registered during a handover receives a save the old process has yet to write", async () => {
  const w = world();
  const h = harness(() => w.state);
  let exited!: () => void;
  const previousGone = new Promise<void>((resolve) => { exited = resolve; });
  try {
    let next!: Secrets;
    h.onPost(() => {
      h.onPost(null);
      next = h.make({ previousGone });
      next.carry(JSON.parse(JSON.stringify(h.secrets.carried())));
      next.reboxed();
      const cert = w.cert(w.alice);
      h.vaults.putBox(cert);
      next.boxed(w.state, cert);
    });
    await h.secrets.save("s1", { name: "Handover", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    exited();
    await tick();
    const [request] = pendingOf(next, w.state, "alice@x.com");
    assert.ok(request);
    assert.deepEqual(opened(request, w.alice), { value: "sample" });
  } finally {
    exited();
    rmSync(h.dir, { recursive: true, force: true });
  }
});

for (const legacy of [false, true]) for (const afterExit of [false, true]) {
  test(`a device registered before ${legacy ? "an older" : "a scoped"} handover arrives receives its save${afterExit ? " even when the handover arrives after exit" : ""}`, async () => {
    const w = world();
    const h = harness(() => w.state);
    let exited!: () => void;
    const previousGone = new Promise<void>((resolve) => { exited = resolve; });
    try {
      let next!: Secrets;
      let carried!: ReturnType<Secrets["carried"]>;
      h.onPost(() => {
        h.onPost(null);
        next = h.make({ previousGone });
        carried = JSON.parse(JSON.stringify(h.secrets.carried()));
        if (legacy) carried.unsaved = carried.unsaved.map(([id, fields]) => [id, fields]);
        const cert = w.cert(w.alice);
        h.vaults.putBox(cert);
        next.boxed(w.state, cert);
        if (!afterExit) {
          next.carry(carried);
          next.reboxed();
        }
      });
      await h.secrets.save("s1", { name: "Early device", kind: "token", reason: "test", value: "sample", cwd: h.dir });
      exited();
      await tick();
      if (afterExit) {
        next.carry(carried);
        next.reboxed();
        await tick();
      }
      const [request] = pendingOf(next, w.state, "alice@x.com");
      assert.ok(request);
      assert.deepEqual(opened(request, w.alice), { value: "sample" });
    } finally {
      exited();
      rmSync(h.dir, { recursive: true, force: true });
    }
  });
}

test("an early device of another member with the same email receives a carried save", async () => {
  const w = world(0, true);
  const h = harness(() => w.state);
  let exited!: () => void;
  const previousGone = new Promise<void>((resolve) => { exited = resolve; });
  try {
    let next!: Secrets;
    h.onPost(() => {
      h.onPost(null);
      next = h.make({ previousGone });
      const cert = w.cert(w.bob);
      h.vaults.putBox(cert);
      next.boxed(w.state, cert);
      next.carry(JSON.parse(JSON.stringify(h.secrets.carried())));
      next.reboxed();
    });
    await h.secrets.save("s1", { name: "Shared email", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    exited();
    await tick();
    const [request] = pendingOf(next, w.state, "alice@x.com");
    assert.ok(request);
    assert.deepEqual(opened(request, w.bob), { value: "sample" });
  } finally {
    exited();
    rmSync(h.dir, { recursive: true, force: true });
  }
});

for (const legacy of [false, true, "mixed"] as const) test(`an early device tells ${legacy === "mixed" ? "mixed older and scoped" : legacy ? "older" : "scoped"} carried saves in their existing request order`, async () => {
  const w = world();
  const h = harness(() => w.state);
  let exited!: () => void;
  const previousGone = new Promise<void>((resolve) => { exited = resolve; });
  try {
    await h.secrets.save("s1", { name: "First", kind: "token", reason: "test", value: "one", cwd: h.dir });
    await h.secrets.save("s1", { name: "Second", kind: "token", reason: "test", value: "two", cwd: h.dir });
    const carried = JSON.parse(JSON.stringify(h.secrets.carried()));
    carried.unsaved.sort((a: [string], b: [string]) => a[0] < b[0] ? 1 : -1);
    const ids = carried.unsaved.map(([id]: [string]) => id).sort();
    carried.unsaved = carried.unsaved.map(([id, fields, scopes]: [string, Record<string, string>, unknown], i: number) => legacy === true || (legacy === "mixed" && i === 0) ? [id, fields] : [id, fields, scopes]);
    const next = h.make({ previousGone });
    const told: string[] = [];
    next.listen((request) => told.push(request.id));
    const cert = w.cert(w.alice);
    h.vaults.putBox(cert);
    next.boxed(w.state, cert);
    next.carry(carried);
    next.reboxed();
    exited();
    await tick();
    assert.deepEqual(told, ids);
  } finally {
    exited();
    rmSync(h.dir, { recursive: true, force: true });
  }
});

for (const removed of [false, true]) {
  test(`an early device ${removed ? "removed" : "given a new certificate"} before carry is checked again`, async () => {
    const w = world();
    let lock = w.state;
    const h = harness(() => lock);
    const newer = { ...w.alice, box: newBoxPair() };
    let exited!: () => void;
    const previousGone = new Promise<void>((resolve) => { exited = resolve; });
    try {
      let next!: Secrets;
      h.onPost(() => {
        h.onPost(null);
        next = h.make({ previousGone });
        const cert = w.cert(w.alice);
        h.vaults.putBox(cert);
        next.boxed(lock, cert);
        if (removed) lock = { ...lock, devices: new Map([...lock.devices].filter(([id]) => id !== w.alice.base.hex)) };
        else h.vaults.putBox(w.cert(newer));
        next.carry(JSON.parse(JSON.stringify(h.secrets.carried())));
        next.reboxed();
      });
      await h.secrets.save("s1", { name: "Early device", kind: "token", reason: "test", value: "sample", cwd: h.dir });
      exited();
      await tick();
      const [request] = pendingOf(next, lock, "alice@x.com");
      assert.ok(request);
      if (removed) assert.deepEqual(request.sealed, []);
      else {
        assert.equal(request.sealed?.length, 1);
        assert.deepEqual(opened(request, newer), { value: "sample" });
      }
    } finally {
      exited();
      rmSync(h.dir, { recursive: true, force: true });
    }
  });
}

for (const legacy of [false, true]) {
  test(`a failed save after an early device and ${legacy ? "an older" : "a scoped"} handover leaves no secret`, async () => {
    const w = world();
    const h = harness(() => w.state);
    let exited!: () => void;
    const previousGone = new Promise<void>((resolve) => { exited = resolve; });
    try {
      let next!: Secrets;
      h.onPost(() => {
        h.onPost(null);
        next = h.make({ previousGone });
        const cert = w.cert(w.alice);
        h.vaults.putBox(cert);
        next.boxed(w.state, cert);
        const carried = JSON.parse(JSON.stringify(h.secrets.carried()));
        if (legacy) carried.unsaved = carried.unsaved.map(([id, fields]: [string, Record<string, string>]) => [id, fields]);
        next.carry(carried);
        next.reboxed();
        throw new Error("post failed");
      });
      await assert.rejects(h.secrets.save("s1", { name: "Failed early", kind: "token", reason: "test", value: "sample", cwd: h.dir }), /post failed/);
      exited();
      await tick();
      assert.deepEqual(next.carried().unsaved, []);
      assert.deepEqual(next.carried().keeper.boxes, []);
    } finally {
      exited();
      rmSync(h.dir, { recursive: true, force: true });
    }
  });
}

for (const legacy of [false, true]) {
  test(`a save granted before ${legacy ? "an older" : "a scoped"} handover arrives keeps its grant`, async () => {
    const w = world();
    const h = harness(() => w.state);
    let exited!: () => void;
    const previousGone = new Promise<void>((resolve) => { exited = resolve; });
    try {
      h.vaults.putBox(w.cert(w.alice));
      h.vaults.putVault(w.vault);
      await h.secrets.save("s1", { name: "Already approved", kind: "token", reason: "test", value: "sample", cwd: h.dir });
      const carried = JSON.parse(JSON.stringify(h.secrets.carried()));
      if (legacy) carried.unsaved = carried.unsaved.map(([id, fields]: [string, Record<string, string>]) => [id, fields]);
      const next = h.make({ previousGone });
      next.reboxed();
      const [request] = pendingOf(next, w.state, "alice@x.com");
      assert.ok(request);
      h.vaults.putItem(written(request, w.alice, { value: "sample" }));
      const grant: Grant = signed({ v: 1 as const, ws: WS, request: request.id, vault: VAULT, item: request.item, mode: "env" as const, hosts: [], scope: "chat" as const, exp: 1000 + 30 * 86400, secret: seal(request.box, Buffer.from(JSON.stringify({ kind: "token", name: "Already approved", fields: { value: "sample" } })), grantContext(WS, request.id)), at: 1000 }, TAG.grant, w.alice.signer);
      assert.equal(next.saved(w.state, "alice", { request: request.id, vault: VAULT, grant }), null);
      assert.equal(next.held("s1").length, 1);
      next.carry(carried);
      exited();
      await tick();
      assert.deepEqual(next.held("s1").map((held) => held.secret.fields), [{ value: "sample" }]);
      assert.deepEqual(next.carried().unsaved, []);
      assert.deepEqual(next.carried().keeper.boxes, []);
    } finally {
      exited();
      rmSync(h.dir, { recursive: true, force: true });
    }
  });
}

test("an older handover retries a device registered before its save is written", async () => {
  const w = world();
  const h = harness(() => w.state);
  let exited!: () => void;
  const previousGone = new Promise<void>((resolve) => { exited = resolve; });
  try {
    let next!: Secrets;
    h.onPost(() => {
      h.onPost(null);
      next = h.make({ previousGone });
      const carried = JSON.parse(JSON.stringify(h.secrets.carried()));
      carried.unsaved = carried.unsaved.map(([id, fields]: [string, Record<string, string>]) => [id, fields]);
      next.carry(carried);
      next.reboxed();
      const cert = w.cert(w.alice);
      h.vaults.putBox(cert);
      next.boxed(w.state, cert);
    });
    await h.secrets.save("s1", { name: "Old handover", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    exited();
    await tick();
    const [request] = pendingOf(next, w.state, "alice@x.com");
    assert.ok(request);
    assert.deepEqual(opened(request, w.alice), { value: "sample" });
  } finally {
    exited();
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("only the latest device certificate receives a save carried during handover", async () => {
  const w = world();
  const h = harness(() => w.state);
  let exited!: () => void;
  const previousGone = new Promise<void>((resolve) => { exited = resolve; });
  try {
    let next!: Secrets;
    const newer = { ...w.alice, box: newBoxPair() };
    h.onPost(() => {
      h.onPost(null);
      next = h.make({ previousGone });
      next.carry(JSON.parse(JSON.stringify(h.secrets.carried())));
      next.reboxed();
      const old = w.cert(w.alice), latest = w.cert(newer);
      h.vaults.putBox(old);
      next.boxed(w.state, old);
      h.vaults.putBox(latest);
      next.boxed(w.state, latest);
    });
    await h.secrets.save("s1", { name: "Replaced", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    exited();
    await tick();
    const [request] = pendingOf(next, w.state, "alice@x.com");
    assert.ok(request);
    assert.equal(request.sealed?.length, 1);
    assert.deepEqual(opened(request, newer), { value: "sample" });
  } finally {
    exited();
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a device removed before the previous process exits is not sent a carried save", async () => {
  const w = world();
  let lock = w.state;
  const h = harness(() => lock);
  let exited!: () => void;
  const previousGone = new Promise<void>((resolve) => { exited = resolve; });
  try {
    let next!: Secrets;
    h.onPost(() => {
      h.onPost(null);
      next = h.make({ previousGone });
      next.carry(JSON.parse(JSON.stringify(h.secrets.carried())));
      next.reboxed();
      const cert = w.cert(w.alice);
      h.vaults.putBox(cert);
      next.boxed(lock, cert);
      lock = { ...lock, devices: new Map([...lock.devices].filter(([id]) => id !== w.alice.base.hex)) };
    });
    await h.secrets.save("s1", { name: "Removed", kind: "token", reason: "test", value: "sample", cwd: h.dir });
    exited();
    await tick();
    const [request] = pendingOf(next, lock, "alice@x.com");
    assert.ok(request);
    assert.deepEqual(request.sealed, []);
  } finally {
    exited();
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a failed save during handover leaves no carried secret once the old process exits", async () => {
  const w = world();
  const h = harness(() => w.state);
  let exited!: () => void;
  const previousGone = new Promise<void>((resolve) => { exited = resolve; });
  try {
    let next!: Secrets;
    h.onPost(() => {
      h.onPost(null);
      next = h.make({ previousGone });
      next.carry(JSON.parse(JSON.stringify(h.secrets.carried())));
      next.reboxed();
      const cert = w.cert(w.alice);
      h.vaults.putBox(cert);
      next.boxed(w.state, cert);
      throw new Error("post failed");
    });
    await assert.rejects(h.secrets.save("s1", { name: "Failed handover", kind: "token", reason: "test", value: "sample", cwd: h.dir }), /post failed/);
    exited();
    await tick();
    assert.deepEqual(next.carried().unsaved, []);
    assert.deepEqual(next.carried().keeper.boxes, []);
  } finally {
    exited();
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a failed save card does not leave the secret or its request box in memory", async () => {
  const w = world();
  const h = harness(() => w.state);
  try {
    h.onPost(() => { throw new Error("post failed"); });
    await assert.rejects(h.secrets.save("s1", { name: "Failed", kind: "token", reason: "test", value: "sample", cwd: h.dir }), /post failed/);
    assert.deepEqual(h.secrets.carried().unsaved, []);
    assert.deepEqual(h.secrets.carried().keeper.boxes, []);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a secret to keep printed by a command: taken without being shown; a command that fails says so with it hidden", async () => {
  const w = world();
  const h = harness(() => w.state);
  h.vaults.putVault(w.vault);
  h.vaults.putBox(w.cert(w.alice));
  try {
    const command = "printf '%s\\n' \"$TOKEN_FOR_TEST\"";
    process.env.TOKEN_FOR_TEST = PASSWORD;
    // (made once the command has ended: told then)
    const made = new Promise<Request>((resolve) => h.secrets.listen((x) => x.status === "pending" && resolve(x)));
    void h.secrets.save("s1", { name: "Token", kind: "token", reason: "x", command, hosts: ["api.github.com"], cwd: h.dir });
    const r = await made;
    delete process.env.TOKEN_FOR_TEST;
    assert.deepEqual(opened(r, w.alice), { value: PASSWORD });
    assert.equal(r.command, command);
    assert.deepEqual(r.save!.modes, ["proxy"]);

    await assert.rejects(h.secrets.save("s1", { name: "T2", kind: "token", reason: "x", command: `printf '${PASSWORD}'; echo "bad ${PASSWORD}" >&2; exit 3`, cwd: h.dir }), (e: Error) => /exit code 3/.test(e.message) && !e.message.includes(PASSWORD) && e.message.includes("bad [已隐藏]"));
    await assert.rejects(h.secrets.save("s1", { name: "T3", kind: "token", reason: "x", command: "true", cwd: h.dir }), /empty/);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a secret to keep without security mode: written into the owner's plain library here once they approve; a restart forgets it", async () => {
  const h = harness(() => null, "bob@x.com");
  try {
    assert.equal(h.secrets.status("s1"), "plain");
    const asked = h.secrets.save("s1", { name: "Slack", kind: "token", reason: "post", value: "xoxb-1", hosts: ["slack.com"], cwd: h.dir });
    await tick();
    const [r] = pendingOf(h.secrets, null, "bob@x.com");
    assert.ok(r && r.vault === PLAIN && r.sealed === undefined && !JSON.stringify(r).includes("xoxb-1"));
    assert.equal(h.secrets.savedPlain(WS, null, "carol@x.com", { request: r.id }), "only the person it is kept for decides it");
    assert.match(h.secrets.grantPlain(WS, null, "bob@x.com", { request: r.id, scope: "once" })!, /POST vault\/plain\/saves/);
    const kept = h.secrets.savedPlain(WS, null, "bob@x.com", { request: r.id });
    assert.ok(typeof kept !== "string");
    assert.deepEqual([kept.id, kept.owner, kept.fields, kept.listing], [r.item, "bob@x.com", { value: "xoxb-1" }, { name: "Slack", kind: "token", modes: ["proxy"], hosts: ["slack.com"] }]);
    assert.match(await decided(h, asked), /Kept: 「Slack」.*This chat may use it now/);
    assert.deepEqual(h.secrets.listings("s1").map((l) => l.listing.name), ["Slack"]);
    assert.deepEqual(h.secrets.held("s1").map((x) => [x.request.id, x.grant.scope, x.grant.hosts]), [[r.id, "hour", ["slack.com"]]]);

    // Waiting through a restart: gone, so let go.
    void h.secrets.save("s1", { name: "Other", kind: "token", reason: "x", value: "v", cwd: h.dir });
    await tick();
    const after = h.make();
    assert.deepEqual(pendingOf(after, null, "bob@x.com"), []);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a secret its owner types in: nothing of it held or sealed here, the card asking for it; kept as their app writes it, waiting through a restart", async () => {
  const w = world();
  const h = harness(() => w.state);
  h.vaults.putVault(w.vault);
  h.vaults.putBox(w.cert(w.alice));
  try {
    const asked = h.secrets.save("s1", { name: "OpenCode Go", kind: "token", reason: "在 OpenCode 控制台的 API Keys 里新建一个", hosts: ["opencode.ai"], cwd: h.dir });
    await tick();
    const [r] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.ok(r && r.vault === VAULT && r.box !== "" && r.sealed === undefined && r.command === undefined);
    assert.deepEqual(r.save, { kind: "token", name: "OpenCode Go", modes: ["proxy"], hosts: ["opencode.ai"], typed: true });
    const { text, card } = h.cards[0]!;
    assert.equal(text, "请填入「OpenCode Go」（Token）并存入密钥库：在 OpenCode 控制台的 API Keys 里新建一个");
    assert.deepEqual(card.vault.save, { kind: "token", typed: true });

    // Held nowhere until typed in: a restart lets it wait on.
    const after = h.make();
    assert.deepEqual(pendingOf(after, w.state, "alice@x.com").map((x) => x.id), [r.id]);
    // Her app writes what she typed into her vault, as for any secret to keep.
    h.vaults.putItem(written(r, w.alice, { value: PASSWORD }));
    assert.equal(h.secrets.saved(w.state, "alice", { request: r.id, vault: VAULT }), null);
    assert.match(await decided(h, asked), /Kept: 「OpenCode Go」/);
    assert.deepEqual(h.secrets.listings("s1").map((l) => [l.listing.name, l.listing.hosts]), [["OpenCode Go", ["opencode.ai"]]]);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a secret its owner types in without security mode: written into their plain library with the fields their app sends, its secret not empty", async () => {
  const h = harness(() => null, "bob@x.com");
  try {
    const asked = h.secrets.save("s1", { name: "Router", kind: "login", reason: "test service", cwd: h.dir });
    await tick();
    const [r] = pendingOf(h.secrets, null, "bob@x.com");
    assert.ok(r && r.vault === PLAIN && r.save?.typed === true);
    // An app from before sends none; nor is an empty secret, or a field the kind has not, kept.
    assert.match(h.secrets.savedPlain(WS, null, "bob@x.com", { request: r.id }) as string, /typed in on its card/);
    assert.match(h.secrets.savedPlain(WS, null, "bob@x.com", { request: r.id, fields: { username: "admin", password: " " } }) as string, /typed in on its card/);
    assert.match(h.secrets.savedPlain(WS, null, "bob@x.com", { request: r.id, fields: { password: "p", value: "v" } }) as string, /a login's fields are/);
    assert.equal(h.secrets.savedPlain(WS, null, "carol@x.com", { request: r.id, fields: { password: "p" } }), "only the person it is kept for decides it");
    const kept = h.secrets.savedPlain(WS, null, "bob@x.com", { request: r.id, fields: { username: "admin", password: PASSWORD } });
    assert.ok(typeof kept !== "string");
    assert.deepEqual([kept.id, kept.fields], [r.item, { username: "admin", password: PASSWORD }]);
    assert.match(await decided(h, asked), /Kept: 「Router」.*This chat may use it now.* The login's account is "admin", in STILLFAIL_USERNAME too\./);
    assert.deepEqual(h.secrets.held("s1").map((x) => x.secret.fields.password), [PASSWORD]);
    // The account it was typed in with goes to each command beside the password, not hidden: it is not secret.
    const [grant] = h.secrets.held("s1");
    assert.equal(await h.secrets.run("s1", { grant: grant!.request.id, command: 'printf "%s %s" "$STILLFAIL_USERNAME" "$STILLFAIL_SECRET"', cwd: h.dir }), "exit code 0\nadmin [已隐藏]");
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a file to keep: read from its path as its bytes, kept as base64 under its name, and written out for each command alone, its path in the variable and the content hidden", async () => {
  const h = harness(() => null, "bob@x.com");
  try {
    // A file not all text: its bytes kept as they are.
    const bytes = Buffer.concat([Buffer.from(`apiVersion: v1\ntoken: ${PASSWORD}\n`), Buffer.from([0, 255, 254])]);
    writeFileSync(join(h.dir, "kube config"), bytes);
    const asked = h.secrets.save("s1", { name: "集群", kind: "file", reason: "部署", path: "kube config", env: "KUBECONFIG", cwd: h.dir });
    const r = await new Promise<Request>((resolve) => h.secrets.listen((x) => x.status === "pending" && resolve(x)));
    assert.deepEqual(r.save, { kind: "file", name: "集群", modes: ["file"], hosts: [], env: "KUBECONFIG", filename: "kube config" });
    assert.equal(h.cards[0]!.text, "申请将「集群」存入密钥库（文件 · kube config）：部署");
    assert.deepEqual(h.cards[0]!.card.vault.save, { kind: "file", filename: "kube config" });
    const kept = h.secrets.savedPlain(WS, null, "bob@x.com", { request: r.id });
    assert.ok(typeof kept !== "string");
    assert.deepEqual(kept.fields, { content: bytes.toString("base64"), filename: "kube config" });
    assert.match(await decided(h, asked), /Kept: 「集群」.*as a file/);

    const ran = await h.secrets.run("s1", { grant: r.id, command: 'test "$KUBECONFIG" = "$STILLFAIL_SECRET" && ls -l "$KUBECONFIG" | cut -c1-10 && basename "$KUBECONFIG" && head -2 "$KUBECONFIG" && echo "$KUBECONFIG" > where', cwd: h.dir });
    assert.match(ran, /^exit code 0\n-rw-------\nkube config\napiVersion: v1\ntoken: /);
    // (the file is not text, so only its bytes' base64 is hidden; a line of it printed is the agent's to see, as an env value's would be)
    const where = readFileSync(join(h.dir, "where"), "utf8").trim();
    assert.ok(where.endsWith("/kube config") && !existsSync(where), "written for the command alone");

    // A text file printed whole comes back hidden; one too big, or a path not a file, is not kept.
    writeFileSync(join(h.dir, "sa.json"), `{"key": "${PASSWORD}"}\n`);
    const made = new Promise<Request>((resolve) => h.secrets.listen((x) => x.status === "pending" && x.save?.name === "SA" && resolve(x)));
    const second = h.secrets.save("s1", { name: "SA", kind: "file", reason: "x", path: join(h.dir, "sa.json"), cwd: h.dir });
    const r2 = await made;
    assert.ok(typeof h.secrets.savedPlain(WS, null, "bob@x.com", { request: r2.id }) !== "string");
    await second;
    assert.equal(await h.secrets.run("s1", { grant: r2.id, command: 'cat "$STILLFAIL_SECRET"', cwd: h.dir }), "exit code 0\n[已隐藏]\n");
    writeFileSync(join(h.dir, "big"), Buffer.alloc(64 * 1024 + 1));
    await assert.rejects(h.secrets.save("s1", { name: "Big", kind: "file", reason: "x", path: "big", cwd: h.dir }), /more than 64 KB/);
    await assert.rejects(h.secrets.save("s1", { name: "None", kind: "file", reason: "x", path: "missing", cwd: h.dir }), /could not be read/);
    await assert.rejects(h.secrets.save("s1", { name: "T", kind: "token", reason: "x", path: "sa.json", cwd: h.dir }), /give kind file/);
    await assert.rejects(h.secrets.save("s1", { name: "E", kind: "file", reason: "x", path: "sa.json", modes: ["env"], cwd: h.dir }), /given as a file/);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a file its owner picks without security mode: kept with the fields their app sends, its content base64 of 64 KB at most", async () => {
  const h = harness(() => null, "bob@x.com");
  try {
    const asked = h.secrets.save("s1", { name: "证书", kind: "file", reason: "签名", env: "CERT", cwd: h.dir });
    await tick();
    const [r] = pendingOf(h.secrets, null, "bob@x.com");
    assert.deepEqual(r!.save, { kind: "file", name: "证书", modes: ["file"], hosts: [], env: "CERT", typed: true });
    assert.equal(h.cards[0]!.text, "请填入「证书」（文件）并存入密钥库：签名");
    assert.match(h.secrets.savedPlain(WS, null, "bob@x.com", { request: r!.id, fields: { content: "not base64!", filename: "a.p12" } }) as string, /base64/);
    assert.match(h.secrets.savedPlain(WS, null, "bob@x.com", { request: r!.id, fields: { content: Buffer.alloc(64 * 1024 + 1).toString("base64") } }) as string, /at most 64 KB/);
    assert.match(h.secrets.savedPlain(WS, null, "bob@x.com", { request: r!.id, fields: { content: "eA==", filename: "../a" } }) as string, /not a path/);
    const content = Buffer.alloc(64 * 1024, 7).toString("base64");
    const kept = h.secrets.savedPlain(WS, null, "bob@x.com", { request: r!.id, fields: { content, filename: "a.p12" } });
    assert.ok(typeof kept !== "string");
    assert.deepEqual(kept.fields, { content, filename: "a.p12" });
    assert.match(await decided(h, asked), /Kept: 「证书」/);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a sign-in to keep: its sites' cookies read from the chat's browser (or the station's), never given, printed or typed; kept, it goes into the chat's browser; its new cookies kept as it comes out", async () => {
  const h = harness(() => null, "bob@x.com");
  try {
    await assert.rejects(h.secrets.save("s1", { name: "GitHub", kind: "browser", reason: "x", value: "v", hosts: ["github.com"], cwd: h.dir }), /read from this chat's browser/);
    await assert.rejects(h.secrets.save("s1", { name: "GitHub", kind: "browser", reason: "x", cwd: h.dir }), /names the sites/);
    await assert.rejects(h.secrets.save("s1", { name: "GitHub", kind: "browser", reason: "x", hosts: ["*.github.com"], cwd: h.dir }), /names the sites/);
    await assert.rejects(h.secrets.save("s1", { name: "GitHub", kind: "browser", reason: "x", hosts: ["github.com"], cwd: h.dir }), /holds no cookies or passkeys of github.com: sign in there first/);
    h.browser.jar = JSON.stringify([{ name: "user_session", value: "abc", domain: "github.com", path: "/" }]);
    const asked = h.secrets.save("s1", { name: "GitHub · bob", kind: "browser", reason: "登录 GitHub", hosts: ["github.com"], browser: "station", cwd: h.dir });
    await tick();
    assert.deepEqual(h.browser.asked.at(-1), ["s1", ["github.com"], true], "read from the station's own browser");
    const [r] = pendingOf(h.secrets, null, "bob@x.com");
    assert.ok(r && r.mode === "browser" && !JSON.stringify(r).includes("abc"));
    assert.match(h.cards.at(-1)!.text, /登录态/);
    assert.deepEqual(h.cards.at(-1)!.card.vault.hosts, ["github.com"]);
    const kept = h.secrets.savedPlain(WS, null, "bob@x.com", { request: r.id });
    assert.ok(typeof kept !== "string");
    assert.deepEqual([kept.kind, kept.fields, kept.listing], ["browser", { cookies: h.browser.jar }, { name: "GitHub · bob", kind: "browser", modes: ["browser"], hosts: ["github.com"] }]);
    assert.match(await decided(h, asked), /Kept/);
    // Kept, the chat that asked has it in its browser, for as long as its grant lasts.
    assert.deepEqual(h.browser.signedIn.map(([s, d]) => [s, d.request, d.sites, d.cookies]), [["s1", r.id, ["github.com"], h.browser.jar]]);
    assert.equal(h.browser.signedIn[0]![1].workspace, WS);
    await assert.rejects(h.secrets.run("s1", { grant: r.id, command: "true", cwd: h.dir }), /is not run with/);
    // Asked again (another chat would): its card says where it goes, and it goes in once granted.
    void h.secrets.ask("s1", { item: "GitHub · bob", reason: "看 PR" });
    await tick();
    const [use] = pendingOf(h.secrets, null, "bob@x.com");
    assert.ok(use && use.mode === "browser");
    assert.match(h.cards.at(-1)!.text, /放进这个对话的浏览器（限 github.com/);
    assert.equal(h.secrets.grantPlain(WS, null, "bob@x.com", { request: use.id, scope: "hour", timeout: { kind: "idle", seconds: 3600 } }), null);
    assert.equal(h.browser.signedIn.length, 2);
    assert.equal(h.browser.signedIn[1]![1].until, 1000 + 3600);
    // Taken out with new cookies: the item keeps them; the same again is no new version.
    const renewed = JSON.stringify([{ name: "user_session", value: "renewed", domain: "github.com", path: "/" }]);
    h.secrets.renewed("s1", use.id, renewed);
    assert.deepEqual([h.plain.item(WS, kept.id)!.version, h.plain.item(WS, kept.id)!.fields.cookies], [1, renewed]);
    h.secrets.renewed("s1", use.id, renewed);
    assert.equal(h.plain.item(WS, kept.id)!.version, 1);
    // A context made anew: what is still granted goes in again.
    h.secrets.signInAgain("s1");
    assert.equal(h.browser.signedIn.length, 4);
    assert.ok(h.browser.signedIn.every(([, d]) => d.workspace === WS));
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a vault sign-in returns to its original workspace after its chat moves", () => {
  const w = world();
  const h = harness((ws) => ws === null || ws === WS ? w.state : null);
  try {
    h.vaults.putVault(w.vault);
    h.vaults.putBox(w.cert(w.alice));
    const item = `i_${"0".repeat(26)}`;
    h.db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES(?,?,?,?,?)").run(WS, "request", "s1", "granted", JSON.stringify({
      ws: WS, id: "request", session: "s1", vault: VAULT, item, owner: "alice@x.com", mode: "browser", status: "granted",
    }));
    h.setSessionWs("another-workspace");
    const cookies = JSON.stringify([{ name: "session", value: "renewed", domain: "github.com", path: "/" }]);
    h.secrets.renewed("s1", "request", cookies, WS);
    const row = h.db.prepare("SELECT body FROM vault_renewals WHERE ws = ? AND item = ?").get(WS, item) as { body: string } | undefined;
    assert.ok(row);
    const renewal = JSON.parse(row.body) as { id: string; sealed: { secret: string }[] };
    assert.deepEqual(JSON.parse(Buffer.from(openSeal(w.alice.box.priv, renewal.sealed[0]!.secret, saveContext(WS, renewal.id))).toString()), { cookies });
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a sign-in in a vault: its newer cookies, which the station cannot write, sealed to its members' devices and carried by its next request, kept until a grant carries them", async () => {
  const w = world();
  const h = harness(() => w.state);
  h.vaults.putVault(w.vault);
  h.vaults.putBox(w.cert(w.alice));
  try {
    h.browser.jar = JSON.stringify([{ name: "user_session", value: "abc", domain: "github.com", path: "/" }]);
    const asked = h.secrets.save("s1", { name: "GitHub", kind: "browser", reason: "登录 GitHub", hosts: ["github.com"], cwd: h.dir });
    await tick();
    const [r] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.deepEqual(opened(r!, w.alice), { cookies: h.browser.jar });
    h.vaults.putItem(written(r!, w.alice, { cookies: h.browser.jar }));
    const grantOf = (req: Request, cookies: string, scope: "hour" | "chat") => signed(
      { v: 1 as const, ws: WS, request: req.id, vault: VAULT, item: req.item, mode: "browser" as const, hosts: ["github.com"], scope, exp: 1000 + 3600, ...(req.timeout ? { timeout: { kind: "idle" as const, seconds: 3600 } } : {}), secret: seal(req.box, Buffer.from(JSON.stringify({ kind: "browser", name: "GitHub", fields: { cookies } })), grantContext(WS, req.id)), at: 1000 },
      TAG.grant, w.alice.signer,
    );
    assert.equal(h.secrets.saved(w.state, "alice", { request: r!.id, vault: VAULT, grant: grantOf(r!, h.browser.jar, "hour") }), null);
    await decided(h, asked);
    // Taken out with newer cookies: sealed to her device, nothing of them in the clear.
    const renewed = JSON.stringify([{ name: "user_session", value: "renewed", domain: "github.com", path: "/" }]);
    h.secrets.renewed("s1", r!.id, renewed);
    const ask = async () => {
      void h.secrets.ask("s1", { item: "GitHub", reason: "看 PR" });
      await tick();
      return pendingOf(h.secrets, w.state, "alice@x.com").at(-1)!;
    };
    const next = await ask();
    assert.ok(next.renewal && !JSON.stringify(next).includes("renewed"));
    assert.deepEqual(next.renewal.sealed.map((x) => x.device), [w.alice.base.hex]);
    assert.deepEqual(JSON.parse(Buffer.from(openSeal(w.alice.box.priv, next.renewal.sealed[0]!.secret, saveContext(WS, next.renewal.id))).toString()), { cookies: renewed });
    // Granted with the cookies it had (an app from before renewals): they stay for the next.
    assert.equal(h.secrets.grant(w.state, "alice", grantOf(next, h.browser.jar, "hour")), null);
    h.browser.at += 3000_000;
    h.secrets.browserUsed("s1", "notgithub.com");
    assert.deepEqual(h.browser.extended, []);
    h.secrets.browserUsed("s1", "github.com");
    assert.deepEqual(h.browser.extended, [["s1", next.id, 7600]]);
    h.browser.at -= 3000_000;
    const after = await ask();
    assert.equal(after.renewal?.id, next.renewal.id);
    // Granted with them (the app wrote them as the item's next version): kept no longer.
    assert.equal(h.secrets.grant(w.state, "alice", grantOf(after, renewed, "hour")), null);
    assert.deepEqual(h.browser.signedIn.at(-1)![1].cookies, renewed);
    assert.equal((await ask()).renewal, undefined);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a request's changes are told to whom decides it: its owner, nobody without one, its vault's members as they are as each is told", () => {
  const w = world();
  const h = harness(() => w.state);
  try {
    h.vaults.putVault(w.vault);
    const request = (over: Partial<Request>): Request => ({ id: "r_1", ws: WS, vault: VAULT, item: "i_1", session: "s1", chat: "", mode: "env", reason: "", box: "", at: 1000, status: "pending", ...over });
    const viewer = (sub: string) => ({ sub, email: `${sub}@x.com`, name: sub, role: "member", workspace: WS, device: "d" });
    /// Whose streams are told of `r`, of alice's and bob's.
    const told = (r: Request) => {
      const to = h.secrets.tells(r);
      return to === null ? [] : ["alice", "bob"].filter((sub) => isFor(to, { viewer: viewer(sub), lang: "en" }, { inVault: (v, vault) => h.secrets.inVault(v, vault) }));
    };
    // The plain library's, and a secret to keep: its owner's; without one, nobody's (not the whole workspace's).
    assert.deepEqual(told(request({ vault: PLAIN, owner: "bob@x.com" })), ["bob"]);
    assert.deepEqual(told(request({ vault: PLAIN })), []);
    assert.deepEqual(told(request({ save: { kind: "login", name: "UX7", modes: ["env"], hosts: [] }, owner: "alice@x.com" })), ["alice"]);
    assert.deepEqual(told(request({ save: { kind: "login", name: "UX7", modes: ["env"], hosts: [] } })), []);
    // A vault's: its members as they are when it is told (again, to a stream that comes back), as written over to the
    // next process.
    const to = h.secrets.tells(request({}));
    assert.deepEqual(JSON.parse(JSON.stringify(to)), to);
    assert.deepEqual(told(request({})), ["alice"]);
    h.vaults.putVault({ ...w.vault, seq: 1, members: ["alice", "bob"] });
    assert.deepEqual(told(request({})), ["alice", "bob"]);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("an item's about: asked with the secret to keep, kept as its notes and its listing's about; secret_list says it", async () => {
  const h = harness(() => null, "bob@x.com");
  try {
    const about = "家里 UniFi 后台：先在 Studio 上开 8443 转发，再打开 https://127.0.0.1:8443/";
    const asked = h.secrets.save("s1", { name: "UniFi 后台", about, kind: "token", reason: "post", value: "t-1", hosts: ["unifi.local"], cwd: h.dir });
    await tick();
    const [r] = pendingOf(h.secrets, null, "bob@x.com");
    assert.equal(r!.save!.about, about);
    assert.match(h.cards[0]!.text, /说明：家里 UniFi 后台/);
    assert.equal(h.cards[0]!.card.vault.about, about);
    const kept = h.secrets.savedPlain(WS, null, "bob@x.com", { request: r!.id });
    assert.ok(typeof kept !== "string");
    assert.equal(kept.notes, about);
    assert.equal(kept.listing!.about, about);
    await decided(h, asked);
    const list = vaultTools(h.secrets, () => h.dir).find((t) => t.name === "secret_list")!;
    assert.equal(JSON.parse(await list.run("s1", {}) as string).secrets[0].about, about);
    // secret_save asks for it.
    const save = vaultTools(h.secrets, () => h.dir).find((t) => t.name === "secret_save")!;
    await assert.rejects(save.run("s1", { name: "x", kind: "token", reason: "r", value: "v" }) as Promise<unknown>, /about is required/);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("an item renamed in the plain library: its card says what would change, its owner's approval writes it here, and it grants nothing", async () => {
  const h = harness(() => null, "bob@x.com");
  try {
    void h.secrets.save("s1", { name: "127.0.0.1 登录态", kind: "token", reason: "x", value: "t-1", hosts: ["127.0.0.1"], cwd: h.dir });
    await tick();
    const [saving] = pendingOf(h.secrets, null, "bob@x.com");
    assert.ok(typeof h.secrets.savedPlain(WS, null, "bob@x.com", { request: saving!.id }) !== "string");
    await assert.rejects(h.secrets.describe("s1", { item: "127.0.0.1 登录态", reason: "r" }), /nothing to change/);
    await assert.rejects(h.secrets.describe("s1", { item: "none", name: "x", reason: "r" }), /secret_list/);
    const asked = h.secrets.describe("s1", { item: "127.0.0.1 登录态", name: "UniFi 后台登录态", about: "经 Studio 转发", reason: "认不出来" });
    await tick();
    const [r] = pendingOf(h.secrets, null, "bob@x.com");
    assert.deepEqual(r!.describe, { name: "UniFi 后台登录态", about: "经 Studio 转发", was: { name: "127.0.0.1 登录态", about: "" } });
    const { text, card } = h.cards.at(-1)!;
    assert.equal(text, "申请修改密钥「127.0.0.1 登录态」的名称与说明：认不出来\n\n名称改为：UniFi 后台登录态\n\n说明改为：经 Studio 转发");
    assert.deepEqual(card.options.map((o: { label: string }) => o.label), ["确认修改", "保持不变"]);
    assert.deepEqual(card.vault.describe, { name: "UniFi 后台登录态", about: "经 Studio 转发", wasAbout: "" });
    // No grant of the item comes of it, nor anyone's but its owner's word.
    assert.match(h.secrets.grantPlain(WS, null, "bob@x.com", { request: r!.id, scope: "once" })!, /grants nothing/);
    assert.match(h.secrets.describedPlain(WS, null, "carol@x.com", { request: r!.id }) as string, /only the item's owner/);
    const kept = h.secrets.describedPlain(WS, null, "bob@x.com", { request: r!.id });
    assert.ok(typeof kept !== "string");
    assert.deepEqual([kept.version, kept.name, kept.notes, kept.listing!.name, kept.listing!.about, kept.fields], [1, "UniFi 后台登录态", "经 Studio 转发", "UniFi 后台登录态", "经 Studio 转发", { value: "t-1" }]);
    assert.match(await decided(h, asked), /Changed: the item i_\w+ is 「UniFi 后台登录态」 now, described as: 经 Studio 转发/);
    assert.deepEqual(h.secrets.held("s1").filter((x) => x.request.id === r!.id), []);
    assert.deepEqual(h.secrets.listings("s1").map((l) => [l.listing.name, l.listing.about]), [["UniFi 后台登录态", "经 Studio 转发"]]);
    assert.deepEqual(await h.secrets.uses(WS, null, PLAIN, { sub: "bob", email: "bob@x.com" }), []);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("an item of a vault renamed: decided by its vault's members, taken once the item here says so, never granted", async () => {
  const w = world();
  const h = harness(() => w.state);
  h.vaults.putVault(w.vault);
  h.vaults.putBox(w.cert(w.alice));
  try {
    const item = (version: number, name: string, about?: string): Item => signed(
      { v: 1 as const, ws: WS, vault: VAULT, id: "i_01HZZZZZZZZZZZZZZZZZZZZZZZ", version, epoch: 0, ct: encryptWith(fill(4), Buffer.from("{}"), itemContext(WS, VAULT, "i_01HZZZZZZZZZZZZZZZZZZZZZZZ", version, 0), fill(5, 12)), listing: { name, kind: "browser" as const, modes: ["browser" as const], hosts: ["127.0.0.1"], ...(about ? { about } : {}) }, at: 1000 },
      TAG.item, w.alice.signer,
    );
    h.vaults.putItem(item(0, "127.0.0.1 登录态"));
    const asked = h.secrets.describe("s1", { item: "127.0.0.1 登录态", name: "UniFi 后台登录态", about: "经 Studio 转发", reason: "认不出来" });
    await tick();
    const [r] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.ok(r && r.describe && r.box === "" && r.vault === VAULT);
    assert.equal(h.cards.at(-1)!.card.assignee, "alice@x.com");
    assert.match(h.secrets.grant(w.state, "alice", { request: r.id } as never)!, /grants nothing/);
    assert.match(h.secrets.described(w.state, "bob", { request: r.id })!, /vault's members/);
    assert.match(h.secrets.described(w.state, "alice", { request: r.id })!, /bring its copy first/);
    h.vaults.putItem(item(1, "UniFi 后台登录态", "经 Studio 转发"));
    assert.equal(h.secrets.described(w.state, "alice", { request: r.id }), null);
    assert.match(await decided(h, asked), /Changed: .*「UniFi 后台登录态」/);
    // (a sign-in's request granted puts nothing into the chat's browser)
    assert.deepEqual(h.browser.signedIn, []);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("an item deleted from the plain library: its card names it, its owner's approval deletes it here, and it grants nothing", async () => {
  const h = harness(() => null, "bob@x.com");
  try {
    void h.secrets.save("s1", { name: "旧的管理员密码", kind: "token", reason: "x", value: "t-1", hosts: ["example.com"], cwd: h.dir });
    await tick();
    const [saving] = pendingOf(h.secrets, null, "bob@x.com");
    assert.ok(typeof h.secrets.savedPlain(WS, null, "bob@x.com", { request: saving!.id }) !== "string");
    await assert.rejects(h.secrets.remove("s1", { item: "none", reason: "r" }), /secret_list/);
    await assert.rejects(h.secrets.remove("s1", { item: "旧的管理员密码", reason: " " }), /reason is required/);
    const asked = h.secrets.remove("s1", { item: "旧的管理员密码", reason: "登不上，换了新的" });
    await tick();
    const [r] = pendingOf(h.secrets, null, "bob@x.com");
    assert.deepEqual(r!.remove, { name: "旧的管理员密码" });
    const { text, card } = h.cards.at(-1)!;
    assert.equal(text, "申请删除密钥「旧的管理员密码」：登不上，换了新的");
    assert.deepEqual(card.options.map((o: { label: string }) => o.label), ["删除", "保留"]);
    assert.deepEqual(card.vault.remove, { name: "旧的管理员密码" });
    assert.match(h.secrets.grantPlain(WS, null, "bob@x.com", { request: r!.id, scope: "once" })!, /grants nothing/);
    assert.match(h.secrets.removedPlain(WS, "carol@x.com", { request: r!.id }) as string, /only the item's owner/);
    const gone = h.secrets.removedPlain(WS, "bob@x.com", { request: r!.id });
    assert.ok(typeof gone !== "string");
    assert.deepEqual([gone.deleted, gone.version, gone.fields], [true, 1, {}]);
    assert.match(await decided(h, asked), /Deleted: 「旧的管理员密码」 \(i_\w+\) is no longer in the vault/);
    assert.deepEqual(h.secrets.listings("s1"), []);
    assert.deepEqual(pendingOf(h.secrets, null, "bob@x.com"), []);
    assert.deepEqual(await h.secrets.uses(WS, null, PLAIN, { sub: "bob", email: "bob@x.com" }), []);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("an item of a vault deleted: decided by its vault's members, taken once the item here is deleted, never granted", async () => {
  const w = world();
  const h = harness(() => w.state);
  h.vaults.putVault(w.vault);
  h.vaults.putBox(w.cert(w.alice));
  try {
    const id = "i_01HZZZZZZZZZZZZZZZZZZZZZZZ";
    h.vaults.putItem(signed(
      { v: 1 as const, ws: WS, vault: VAULT, id, version: 0, epoch: 0, ct: encryptWith(fill(4), Buffer.from("{}"), itemContext(WS, VAULT, id, 0, 0), fill(5, 12)), listing: { name: "branded", kind: "token" as const, modes: ["env" as const], hosts: [] }, at: 1000 },
      TAG.item, w.alice.signer,
    ));
    const asked = h.secrets.remove("s1", { item: "branded", reason: "登不上" });
    await tick();
    const [r] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.ok(r && r.remove && r.box === "" && r.vault === VAULT);
    assert.equal(h.cards.at(-1)!.card.assignee, "alice@x.com");
    assert.match(h.secrets.grant(w.state, "alice", { request: r.id } as never)!, /grants nothing/);
    assert.match(h.secrets.removed(w.state, "bob", { request: r.id })!, /vault's members/);
    assert.match(h.secrets.removed(w.state, "alice", { request: r.id })!, /bring its copy first/);
    h.vaults.putItem(signed({ v: 1 as const, ws: WS, vault: VAULT, id, version: 1, epoch: 0, deleted: true as const, ct: "", at: 1001 }, TAG.item, w.alice.signer));
    assert.equal(h.secrets.removed(w.state, "alice", { request: r.id }), null);
    assert.match(await decided(h, asked), /Deleted: 「branded」/);
    assert.deepEqual(pendingOf(h.secrets, w.state, "alice@x.com"), []);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

test("a request withdrawn by the agent that asked: its card closed, gone from its owner's waiting requests, nobody told", async () => {
  const h = harness(() => null, "bob@x.com");
  try {
    void h.secrets.save("s1", { name: "Office-Host-2 管理员登录", kind: "login", reason: "装 git", hosts: [], cwd: h.dir });
    await tick();
    const [r] = pendingOf(h.secrets, null, "bob@x.com");
    assert.ok(r);
    const told = h.notified.length;
    assert.throws(() => h.secrets.cancel("s2", r.id), /No such request in this chat/);
    assert.throws(() => h.secrets.cancel("s1", "r_none"), /No such request in this chat/);
    assert.match(h.secrets.cancel("s1", r.id), /Withdrew request r_\w+/);
    assert.deepEqual(pendingOf(h.secrets, null, "bob@x.com"), []);
    assert.deepEqual(h.withdrawn, ["1"]);
    assert.equal(h.notified.length, told);
    assert.throws(() => h.secrets.cancel("s1", r.id), /no longer pending \(withdrawn\)/);
    // (decided once withdrawn: nothing to approve)
    assert.match(h.secrets.savedPlain(WS, null, "bob@x.com", { request: r.id, fields: { username: "u", password: "p" } }) as string, /withdrawn/);
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
});

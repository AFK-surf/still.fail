// Agents asking to keep a secret in the vault (docs/vault.md agent 存入; src/vault/secrets.ts `save`): sealed to the
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
import { type Entry, entryHash, genesis, signedBytes as lockBytes } from "../src/cloud/lock.ts";
import { type BoxCert, type Deny, type Grant, type Item, type Request, type Sig, type Vault, TAG, encryptWith, grantContext, itemContext, keyContext, newBoxPair, openSeal, saveContext, seal, signedBytes } from "../src/vault/crypto.ts";
import { PLAIN, PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { vaultTools } from "../src/vault/tool.ts";
import { VaultStore } from "../src/vault/store.ts";
import { STILLFAIL_SURFACE } from "../src/store/store.ts";
import { isFor } from "../src/api/events.ts";

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
function world() {
  const [alice, bob] = ["alice", "bob"].map((sub) => ({ sub, signer: ed(), base: ed(), box: newBoxPair() })) as [Person, Person];
  const body = {
    owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: [{ sub: "alice", email: "alice@x.com", role: "owner" }, { sub: "bob", email: "bob@x.com", role: "member" }],
    devices: [alice, bob].map((p) => ({ id: p.base.hex, sub: p.sub, kind: "app", label: p.sub, sign_key: p.signer.id })),
    passkeys: [], stations: [], gateways: [],
  };
  const e = { v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body } as Omit<Entry, "sig">;
  const state = genesis({ ...e, sig: { key: alice.signer.id, alg: "Ed25519" as const, sig: alice.signer.sign(lockBytes(entryHash(e as Entry))) } });
  const cert = (p: Person): BoxCert => signed({ v: 1 as const, ws: WS, device: p.base.hex, box: p.box.pub, at: 1000 }, TAG.box, p.signer);
  const vault: Vault = signed(
    { v: 1 as const, ws: WS, id: VAULT, seq: 0, owner: "alice", name: "Personal", members: ["alice"], epoch: 0, keys: [{ cert: cert(alice), wrapped: seal(alice.box.pub, fill(4), keyContext(WS, VAULT, 0)) }], at: 1000 },
    TAG.vault, alice.signer,
  );
  return { alice, bob, state, vault, cert };
}

/// The item alice's app writes for request `r`: what the station sealed to her, under the request's item id.
function written(r: Request, by: Person, fields: Record<string, string>): Item {
  const plain = { kind: r.save!.kind, name: r.save!.name, fields, domains: [], notes: "" };
  return signed(
    { v: 1 as const, ws: WS, vault: VAULT, id: r.item, version: 0, epoch: 0, ct: encryptWith(fill(4), Buffer.from(JSON.stringify(plain)), itemContext(WS, VAULT, r.item, 0, 0), fill(5, 12)), listing: { name: r.save!.name, kind: r.save!.kind, modes: r.save!.modes, hosts: r.save!.hosts }, at: 1000 },
    TAG.item, by.signer,
  );
}

function harness(lock: () => ReturnType<typeof world>["state"] | null, starter = "alice@x.com") {
  const db = new DatabaseSync(":memory:");
  const vaults = new VaultStore(db);
  const plain = new PlainStore(db);
  const notified: [string, string][] = [];
  const cards: { text: string; card: any }[] = [];
  const withdrawn: string[] = [];
  let hidden = false;
  let onPost: (() => void) | null = null;
  const hub = {
    store: {
      getSession: (k: string) => (k === "s1" ? { key: "s1", ws: null, workspace: "/tmp", archivedAt: null } : null),
      starter: () => starter.toLowerCase(),
      latestThread: () => ({ connect: "c", thread: { id: 1, channel: "EMBER", threadTs: "1.0", surface: STILLFAIL_SURFACE } }),
      sessionThreads: () => [{ connect: "c", thread: { id: 1, channel: "EMBER", threadTs: "1.0", surface: STILLFAIL_SURFACE } }],
      withdrawCard: (_session: string, _thread: number, ts: string) => (withdrawn.push(ts), true),
      restateCard: () => true,
      insertMessage: (m: { text: string; card: unknown }) => (cards.push({ text: m.text, card: m.card }), hidden = false, [cards.length]),
      pendingCard: () => hidden || cards.length === 0 ? null : [{ ts: String(cards.length) }, cards.at(-1)!.card],
      subscribe: () => () => {},
    },
    chat: () => ({ post: async () => { onPost?.(); return String(cards.length + 1); } }),
    shared: () => {},
    notify: (k: string, text: string) => notified.push([k, text]),
  };
  const dir = mkdtempSync(join(tmpdir(), "vault-save-"));
  // The chats' browsers: the cookies each was asked for (`jar`, as JSON) and the sign-ins put in.
  const browser = { jar: "[]", asked: [] as [string, string[], boolean][], signedIn: [] as [string, { request: string; sites: string[]; cookies: string; until: number }][] };
  const browsers = {
    cookies: async (session: string, sites: string[], station: boolean) => (browser.asked.push([session, sites, station]), browser.jar),
    signIn: async (session: string, d: { request: string; sites: string[]; cookies: string; until: number }) => void browser.signedIn.push([session, d]),
  };
  const make = () => new Secrets({ db, vaults, plain, home: () => WS, hub: hub as never, data: dir, lock, now: () => 1_000_000, browsers });
  return { db, vaults, plain, notified, cards, withdrawn, dir, make, browser, secrets: make(), hideCard: () => { hidden = true; }, occupyCard: () => { cards.push({ text: "another question", card: { type: "text" } }); hidden = false; }, onPost: (f: (() => void) | null) => { onPost = f; } };
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
    assert.deepEqual(h.withdrawn, ["1", "2"], "both the old card and the raced new card were closed");
    assert.equal(h.secrets.held("s1")[0]!.request.id, request, "the decision survived");
  } finally {
    rmSync(h.dir, { recursive: true, force: true });
  }
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

    const asked = h.secrets.save("s1", { name: "UniFi UX7", kind: "login", reason: "log in to the router", value: PASSWORD, username: "zzj", env: "UX7_PASSWORD", cwd: h.dir });
    await tick();
    const [r] = pendingOf(h.secrets, w.state, "alice@x.com");
    assert.ok(r && r.save && r.vault === VAULT && r.owner === "alice@x.com" && r.box !== "");
    assert.deepEqual(r.save, { kind: "login", name: "UniFi UX7", modes: ["env"], hosts: [], env: "UX7_PASSWORD", username: "zzj" });
    // Sealed to her device alone (bob's is his), nothing of it in the clear.
    assert.deepEqual(r.sealed!.map((s) => s.device), [w.alice.base.hex]);
    assert.deepEqual(opened(r, w.alice), { username: "zzj", password: PASSWORD });
    assert.ok(!JSON.stringify(r).includes(PASSWORD));
    // The card: what it is and whose, to keep or turn down.
    const { text, card } = h.cards[0]!;
    assert.equal(text, "申请将「UniFi UX7」存入密钥库（登录 · zzj）：log in to the router");
    assert.equal(card.assignee, "alice@x.com");
    assert.deepEqual(card.options.map((o: { label: string }) => o.label), ["存入密钥库", "拒绝"]);
    assert.deepEqual(card.vault.save, { kind: "login", username: "zzj" });

    // bob neither sees nor decides it; alice's word comes only once the item is in her vault here.
    assert.deepEqual(pendingOf(h.secrets, w.state, "bob@x.com"), []);
    assert.match(h.secrets.saved(w.state, "bob", { request: r.id, vault: VAULT })!, /only the person it is kept for/);
    assert.match(h.secrets.grant(w.state, "alice", { request: r.id } as never)!, /POST vault\/saves/);
    assert.match(h.secrets.saved(w.state, "alice", { request: r.id, vault: VAULT })!, /not in that vault here/);
    h.vaults.putItem(written(r, w.alice, { username: "zzj", password: PASSWORD }));
    // Her app's grant to this chat comes with it, sealed to the request's box.
    const grant: Grant = signed(
      { v: 1 as const, ws: WS, request: r.id, vault: VAULT, item: r.item, mode: "env" as const, hosts: [], scope: "chat" as const, exp: 1000 + 30 * 86400, secret: seal(r.box, Buffer.from(JSON.stringify({ kind: "login", name: "UniFi UX7", fields: { username: "zzj", password: PASSWORD } })), grantContext(WS, r.id)), at: 1000 },
      TAG.grant, w.alice.signer,
    );
    assert.equal(h.secrets.saved(w.state, "alice", { request: r.id, vault: VAULT, grant }), null);
    assert.match(await decided(h, asked), /Kept: 「UniFi UX7」 is in alice@x.com's vault now \(item i_\w+\)\. This chat may use it now: secret_run \{grant: "r_/);
    assert.deepEqual(h.secrets.held("s1").map((x) => [x.request.id, x.grant.scope, x.secret.fields.password]), [[r.id, "chat", PASSWORD]]);
    // Now one agents may ask for; the save is no use of it.
    assert.deepEqual(h.secrets.listings("s1").map((l) => l.listing.name), ["UniFi UX7"]);
    assert.deepEqual(h.secrets.uses(WS, w.state, VAULT, { sub: "alice", email: "alice@x.com" }), []);
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
    const asked = h.secrets.save("s1", { name: "UniFi UX7", kind: "login", reason: "router", value: PASSWORD, cwd: h.dir });
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
    assert.match(await decided(h, asked), /Kept: 「UniFi UX7」.*When you need it, ask with secret_use/);

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
    assert.deepEqual(h.secrets.held("s1").map((x) => [x.request.id, x.grant.scope, x.grant.hosts]), [[r.id, "chat", ["slack.com"]]]);

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
    const asked = h.secrets.save("s1", { name: "Router", kind: "login", reason: "router", cwd: h.dir });
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
    await assert.rejects(h.secrets.run("s1", { grant: r.id, command: "true", cwd: h.dir }), /is not run with/);
    // Asked again (another chat would): its card says where it goes, and it goes in once granted.
    void h.secrets.ask("s1", { item: "GitHub · bob", reason: "看 PR" });
    await tick();
    const [use] = pendingOf(h.secrets, null, "bob@x.com");
    assert.ok(use && use.mode === "browser");
    assert.match(h.cards.at(-1)!.text, /放进这个对话的浏览器（限 github.com/);
    assert.equal(h.secrets.grantPlain(WS, null, "bob@x.com", { request: use.id, scope: "hour" }), null);
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
      { v: 1 as const, ws: WS, request: req.id, vault: VAULT, item: req.item, mode: "browser" as const, hosts: ["github.com"], scope, exp: 1000 + 3600, secret: seal(req.box, Buffer.from(JSON.stringify({ kind: "browser", name: "GitHub", fields: { cookies } })), grantContext(WS, req.id)), at: 1000 },
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

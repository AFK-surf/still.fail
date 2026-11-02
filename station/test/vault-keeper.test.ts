// Agents using the vault's secrets (docs/vault.md, agent 用密钥; src/vault/keeper.ts, proxy.ts, ssh-agent.ts, scrub.ts,
// run.ts, secrets.ts): whose grant is taken and for what, the proxy putting the value in only for the granted hosts,
// the ssh-agent's signatures, output with the value hidden, and a request from the tool to the grant. Servers listen on
// loopback ports of the run's own; nothing waits on time (the keeper's clock is the test's).
import assert from "node:assert/strict";
import { type KeyObject, X509Certificate, createPublicKey, generateKeyPairSync, randomBytes, sign as nodeSign, verify } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { type IncomingMessage, request as httpRequest } from "node:http";
import { createServer as httpsServer } from "node:https";
import { type Socket, connect as netConnect } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { connect as tlsConnect } from "node:tls";
import { type Entry, entryHash, genesis, signedBytes as lockBytes } from "../src/cloud/lock.ts";
import { type BoxCert, type Grant, type Item, type Request, type Sig, type Vault, TAG, encryptWith, grantContext, itemContext, keyContext, newBoxPair, seal, signedBytes } from "../src/vault/crypto.ts";
import { Keeper, hostAllowed } from "../src/vault/keeper.ts";
import { Proxy, placeholder, swap } from "../src/vault/proxy.ts";
import { runWith } from "../src/vault/run.ts";
import { HIDDEN, Scrubber, scrub } from "../src/vault/scrub.ts";
import { PLAIN, PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { answer, parseSshKey, serveAgent } from "../src/vault/ssh-agent.ts";
import { VaultStore } from "../src/vault/store.ts";
import { STILLFAIL_SURFACE } from "../src/store/store.ts";
import { makeCa, makeLeaf, pem } from "../src/vault/x509.ts";

const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ";
const VAULT = "v_01HZZZZZZZZZZZZZZZZZZZZZZZ";
const ITEM = "i_01HZZZZZZZZZZZZZZZZZZZZZZZ";
const TOKEN = "ghp_0123456789abcdefghijklmnopqrstuvwxyz";

function ed() {
  const key = generateKeyPairSync("ed25519").privateKey;
  const hex = Buffer.from(createPublicKey(key).export({ format: "jwk" }).x as string, "base64url").toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Buffer) => nodeSign(null, bytes, key).toString("hex") };
}
type Key = ReturnType<typeof ed>;
type Person = { sub: string; signer: Key; base: Key };
const fill = (b: number, n = 32) => new Uint8Array(n).fill(b);

function signed<T extends Record<string, unknown>>(o: T, tag: string, key: Key): T & { sig: Sig } {
  return { ...o, sig: { key: key.id, alg: "Ed25519", sig: key.sign(signedBytes(o, tag)) } };
}

/// A lock: alice (the vault's owner) and bob, members; carol, a member of the workspace but not of the vault.
function world() {
  const [alice, bob, carol] = ["alice", "bob", "carol"].map((sub) => ({ sub, signer: ed(), base: ed() })) as [Person, Person, Person];
  const body = {
    owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: [{ sub: "alice", email: "alice@x.com", role: "owner" }, { sub: "bob", email: "bob@x.com", role: "member" }, { sub: "carol", email: "carol@x.com", role: "member" }],
    devices: [alice, bob, carol].map((p) => ({ id: p.base.hex, sub: p.sub, kind: "app", label: p.sub, sign_key: p.signer.id })),
    passkeys: [], stations: [], gateways: [],
  };
  const e = { v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body } as Omit<Entry, "sig">;
  const state = genesis({ ...e, sig: { key: alice.signer.id, alg: "Ed25519" as const, sig: alice.signer.sign(lockBytes(entryHash(e as Entry))) } });
  const cert = (p: Person): BoxCert => signed({ v: 1 as const, ws: WS, device: p.base.hex, box: newBoxPair().pub, at: 1000 }, TAG.box, p.signer);
  const vault: Vault = signed(
    { v: 1 as const, ws: WS, id: VAULT, seq: 0, owner: "alice", name: "Personal", members: ["alice", "bob"], epoch: 0, keys: [alice, bob].map((p) => { const c = cert(p); return { cert: c, wrapped: seal(c.box, fill(4), keyContext(WS, VAULT, 0)) }; }), at: 1000 },
    TAG.vault, alice.signer,
  );
  const plain = { kind: "token", name: "GitHub", fields: { value: TOKEN }, domains: [], notes: "" };
  const item: Item = signed(
    { v: 1 as const, ws: WS, vault: VAULT, id: ITEM, version: 0, epoch: 0, ct: encryptWith(fill(4), Buffer.from(JSON.stringify(plain)), itemContext(WS, VAULT, ITEM, 0, 0), fill(5, 12)), listing: { name: "GitHub", kind: "token" as const, modes: ["proxy" as const, "env" as const], hosts: ["api.github.com", "*.example.com"], env: "GH_TOKEN" }, at: 1000 },
    TAG.item, alice.signer,
  );
  return { alice, bob, carol, state, vault, item, plain };
}

const requestOf = (id: string, box: string, o: Partial<Request> = {}): Request => ({ id, ws: WS, vault: VAULT, item: ITEM, session: "s1", chat: "EMBER/1.0", mode: "proxy", reason: "test", box, at: 1000, status: "pending", ...o });

function grantOf(r: Request, by: Person, secret: unknown, o: Partial<Grant> = {}): Grant {
  const g = { v: 1 as const, ws: WS, request: r.id, vault: VAULT, item: ITEM, mode: r.mode, hosts: ["api.github.com"], scope: "once" as const, exp: 1500, secret: seal(r.box, Buffer.from(JSON.stringify(secret)), grantContext(WS, r.id)), at: 1000, ...o };
  return signed(g, TAG.grant, by.signer);
}

test("idle grants renew on use while fixed grants expire at the approved deadline", () => {
  const w = world();
  let now = 1000;
  const keeper = new Keeper(() => now);
  const idle = requestOf("r_idle", keeper.open("r_idle"));
  const fixed = requestOf("r_fixed", keeper.open("r_fixed"));
  const policy = (kind: string) => ({ scope: "hour", exp: 4600, timeout: { kind, seconds: 3600 } }) as unknown as Partial<Grant>;
  assert.equal(keeper.accept(w.state, w.vault, w.item, idle, grantOf(idle, w.alice, w.plain, policy("idle"))), null);
  assert.equal(keeper.accept(w.state, w.vault, w.item, fixed, grantOf(fixed, w.alice, w.plain, policy("fixed"))), null);
  now = 4000;
  keeper.spend(idle.id);
  keeper.spend(fixed.id);
  keeper.renew("s1", idle.id);
  keeper.renew("s1", fixed.id);
  now = 4600;
  assert.equal(typeof keeper.usable("s1", idle.id), "object");
  assert.match(keeper.usable("s1", fixed.id) as string, /ran out/);
  now = 7600;
  assert.match(keeper.usable("s1", idle.id) as string, /ran out/);
  keeper.renew("s1", idle.id);
  assert.match(keeper.usable("s1", idle.id) as string, /no such grant/);
  const tooLong = requestOf("r_long", keeper.open("r_long"));
  assert.match(keeper.accept(w.state, w.vault, w.item, tooLong, grantOf(tooLong, w.alice, w.plain, {
    scope: "chat", at: now, exp: now + 30 * 86400 + 1, timeout: { kind: "idle", seconds: 30 * 86400 + 1 },
  }))!, /invalid grant timeout/);
  const asked = requestOf("r_old_app", keeper.open("r_old_app"), { timeout: { kind: "idle", seconds: 3600 } });
  assert.match(keeper.accept(w.state, w.vault, w.item, asked, grantOf(asked, w.alice, w.plain, { scope: "chat", at: now, exp: now + 3600 }))!, /update the app/);
});

test("hidden output: the value and its usual encodings, however the output is cut into chunks", () => {
  const forms = [TOKEN, Buffer.from(TOKEN).toString("base64"), encodeURIComponent(TOKEN), Buffer.from(`x-access-token:${TOKEN}`).toString("base64"), Buffer.from(`ab:${TOKEN}`).toString("base64url")];
  for (const form of forms) {
    const text = `before ${form} after`;
    const out = scrub(text, [TOKEN]);
    assert.ok(out.includes(HIDDEN), `hidden: ${form}`);
    assert.ok(!out.includes(TOKEN) && !out.includes(Buffer.from(TOKEN).toString("base64").slice(4, 30)), `nothing of it left: ${out}`);
    // Every way of cutting it in two gives the same.
    for (let cut = 0; cut <= text.length; cut++) {
      const s = new Scrubber([TOKEN]);
      const got = Buffer.concat([s.push(Buffer.from(text.slice(0, cut))), s.push(Buffer.from(text.slice(cut))), s.end()]).toString();
      assert.equal(got, out, `cut at ${cut}`);
    }
  }
  assert.equal(scrub("nothing secret here", [TOKEN]), "nothing secret here");
  // Byte by byte, the value twice.
  const s = new Scrubber([TOKEN]);
  const parts = [...Buffer.from(`${TOKEN}${TOKEN}!`)].map((b) => s.push(Buffer.from([b])));
  assert.equal(Buffer.concat([...parts, s.end()]).toString(), `${HIDDEN}${HIDDEN}!`);
});

test("the keeper takes a grant only as asked, signed by a member of the vault, within what the item allows", () => {
  const w = world();
  let now = 1000;
  const keeper = new Keeper(() => now);
  const fresh = (id: string, o: Partial<Request> = {}) => requestOf(id, keeper.open(id), o);
  const take = (r: Request, g: Grant) => keeper.accept(w.state, w.vault, w.item, r, g);

  const r1 = fresh("r_1");
  assert.equal(take(r1, grantOf(r1, w.alice, w.plain)), null);
  // Only its session uses it; once, for a grant for one use.
  assert.match(keeper.usable("s2", "r_1") as string, /another session's/);
  const held = keeper.usable("s1", "r_1");
  assert.ok(typeof held !== "string" && held.secret.fields.value === TOKEN);
  keeper.spend("r_1");
  assert.match(keeper.usable("s1", "r_1") as string, /one use/);
  assert.match(take(r1, grantOf(r1, w.alice, w.plain))!, /no longer holds|pending/, "taken once");

  // Another member of the vault may grant; one outside it, or a forged signature, may not.
  const r2 = fresh("r_2");
  assert.equal(take(r2, grantOf(r2, w.bob, w.plain, { scope: "hour", exp: 1000 + 3600 })), null);
  const r3 = fresh("r_3");
  assert.match(take(r3, grantOf(r3, w.carol, w.plain))!, /vault member's device/);
  assert.match(take(r3, { ...grantOf(r3, w.alice, w.plain), hosts: ["api.github.com", "evil.com"] })!, /hosts/);
  assert.match(take(r3, { ...grantOf(r3, w.alice, w.plain), scope: "chat" })!, /signature/);
  // Within the request and the item.
  assert.match(take(r3, grantOf(r3, w.alice, w.plain, { mode: "env" }))!, /not for this request/);
  assert.match(take(r3, grantOf(r3, w.alice, w.plain, { hosts: ["evil.com"] }))!, /hosts/);
  assert.match(take(r3, grantOf(r3, w.alice, w.plain, { hosts: ["*.github.com"] }))!, /hosts/, "a wildcard the item does not have");
  assert.equal(take(fresh("r_3a"), grantOf(requestOf("r_3a", newBoxPair().pub), w.alice, w.plain, { hosts: ["a.example.com"] })), "the grant's secret does not open", "sealed to another box");
  assert.match(take(r3, grantOf(r3, w.alice, w.plain, { hosts: [] }))!, /names its hosts/);
  assert.match(take(r3, grantOf(r3, w.alice, w.plain, { exp: 1000 + 7200 }))!, /expiry/);
  assert.match(take(r3, grantOf(r3, w.alice, w.plain, { exp: 999 }))!, /expiry/);
  assert.match(take(r3, grantOf(r3, w.alice, { kind: "token", name: "x", fields: {} }))!, /no value/);
  assert.match(take({ ...r3, mode: "ssh" }, grantOf({ ...r3, mode: "ssh" }, w.alice, w.plain))!, /not given by ssh/);
  assert.equal(take(r3, grantOf(r3, w.alice, w.plain, { hosts: ["a.example.com"] })), null);

  // It runs out with time.
  const r4 = fresh("r_4");
  assert.equal(take(r4, grantOf(r4, w.alice, w.plain, { scope: "hour", exp: 1000 + 3600 })), null);
  keeper.spend("r_4");
  assert.ok(typeof keeper.usable("s1", "r_4") !== "string", "an hour's grant is used again");
  now = 1000 + 3600;
  assert.match(keeper.usable("s1", "r_4") as string, /ran out/);
  assert.deepEqual(keeper.held("s1").map((h) => h.request.id), []);
  now = 1000;

  // The chat's, until it is archived (30 days at most); none longer than the item allows.
  const r5 = fresh("r_5");
  assert.match(take(r5, grantOf(r5, w.alice, w.plain, { scope: "chat", exp: 1000 + 31 * 86400 }))!, /expiry/);
  assert.equal(take(r5, grantOf(r5, w.alice, w.plain, { scope: "chat", exp: 1000 + 30 * 86400 })), null);
  const short = { ...w.item, listing: { ...w.item.listing!, lasts: "hour" as const } };
  const r6 = fresh("r_6");
  assert.match(keeper.accept(w.state, w.vault, short, r6, grantOf(r6, w.alice, w.plain, { scope: "chat", exp: 1000 + 600 }))!, /hour at most/);
  assert.equal(keeper.accept(w.state, w.vault, short, r6, grantOf(r6, w.alice, w.plain, { scope: "hour", exp: 1000 + 600 })), null);
  // An item that says none follows its vault's; one that says its own, its own.
  const once = { ...w.vault, lasts: "once" as const };
  const r7 = fresh("r_7");
  assert.match(keeper.accept(w.state, once, w.item, r7, grantOf(r7, w.alice, w.plain, { scope: "hour", exp: 1000 + 600 }))!, /once at most/);
  assert.equal(keeper.accept(w.state, once, { ...w.item, listing: { ...w.item.listing!, lasts: "chat" } }, r7, grantOf(r7, w.alice, w.plain, { scope: "hour", exp: 1000 + 600 })), null);

  assert.ok(hostAllowed("api.github.com", ["api.github.com"]));
  assert.ok(hostAllowed("a.b.example.com", ["*.example.com"]));
  assert.ok(!hostAllowed("example.com", ["*.example.com"]));
  assert.ok(!hostAllowed("evilexample.com", ["*.example.com"]));
});

test("the CA and a host's certificate: as verifiers want them", async () => {
  const ca = makeCa(Date.UTC(2026, 9, 17));
  const leaf = makeLeaf(ca, "still.fail station vault", "api.github.com", Date.UTC(2026, 9, 17));
  const caCert = new X509Certificate(ca.cert);
  const leafCert = new X509Certificate(leaf.cert);
  assert.ok(caCert.ca && !leafCert.ca);
  assert.ok(caCert.verify(caCert.publicKey));
  assert.ok(leafCert.verify(caCert.publicKey));
  assert.ok(leafCert.checkIssued(caCert));
  assert.equal(leafCert.checkHost("api.github.com"), "api.github.com");
  assert.equal(leafCert.checkHost("evil.com"), undefined);
  assert.match(leafCert.validTo, /2026/);
  assert.match(caCert.validTo, /2036/);
});

/// A host on loopback that answers with the Authorization header it got, its certificate from `ca`.
async function echoHost(ca: ReturnType<typeof makeCa>, name: string) {
  const leaf = makeLeaf(ca, "test ca", name, Date.now());
  const server = httpsServer({ key: leaf.key.export({ format: "pem", type: "pkcs8" }), cert: pem(leaf.cert) }, (req, res) => res.end(`auth=${req.headers.authorization ?? ""};host=${req.headers.host}`));
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  return { server, port: (server.address() as { port: number }).port };
}

/// GET https://`host`:`port`/ through the proxy at `proxyUrl` (CONNECT), trusting `ca`; the body, or the CONNECT's status.
function viaProxy(proxyUrl: string, host: string, port: number, ca: string, authorization: string): Promise<string> {
  const u = new URL(proxyUrl);
  return new Promise((resolve, reject) => {
    const headers: Record<string, string> = u.username ? { "proxy-authorization": `Basic ${Buffer.from(`${u.username}:${u.password}`).toString("base64")}` } : {};
    const req = httpRequest({ host: "127.0.0.1", port: Number(u.port), method: "CONNECT", path: `${host}:${port}`, headers });
    req.on("connect", (res: IncomingMessage, socket: Socket) => {
      if (res.statusCode !== 200) return resolve(`status ${res.statusCode}`);
      const tls = tlsConnect({ socket, servername: host, ca }, () => {
        tls.write(`GET / HTTP/1.1\r\nHost: ${host}:${port}\r\nAuthorization: ${authorization}\r\nConnection: close\r\n\r\n`);
      });
      let got = "";
      tls.on("data", (b) => (got += b.toString()));
      tls.on("end", () => resolve(got.split("\r\n\r\n").slice(1).join("\r\n\r\n")));
      tls.on("error", reject);
    });
    req.on("error", reject);
    req.end();
  });
}

test("the proxy: the value goes in only on HTTPS to a granted host; elsewhere the placeholder passes untouched", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-proxy-"));
  const upstreamCa = makeCa(Date.now(), "test ca");
  // "localhost" resolves to the loopback the hosts listen on; the proxy reaches them by that name, so the hosts'
  // certificates are for it, and a second name stands for a host not granted.
  const host = await echoHost(upstreamCa, "localhost");
  const proxy = new Proxy(dir, Date.now, [pem(upstreamCa.cert)]);
  try {
    await proxy.start();
    const used: string[] = [];
    let allowed = true;
    const granted = proxy.admit({ hosts: ["localhost"], placeholder: placeholder("r_9"), value: TOKEN, used: (h) => used.push(h), allowed: () => allowed });
    const trustProxy = readFileSync(proxy.bundle, "utf8");
    // A granted host: the proxy's own certificate for it, the value in the header.
    assert.equal(await viaProxy(granted.url, "localhost", host.port, trustProxy, `Bearer ${placeholder("r_9")}`), `auth=Bearer ${TOKEN};host=localhost:${host.port}`);
    const basic = await viaProxy(granted.url, "localhost", host.port, trustProxy, `Basic ${Buffer.from(`x-access-token:${placeholder("r_9")}`).toString("base64")}`);
    assert.equal(Buffer.from(basic.slice("auth=Basic ".length).split(";")[0]!, "base64").toString(), `x-access-token:${TOKEN}`);
    assert.deepEqual(used, ["localhost", "localhost"]);
    allowed = false;
    assert.match(await viaProxy(granted.url, "localhost", host.port, trustProxy, `Bearer ${placeholder("r_9")}`), /grant expired/);
    assert.equal(used.length, 2, "an expired command cannot use its already opened proxy");
    // Without the run's credentials: nothing.
    assert.equal(await viaProxy(`http://127.0.0.1:${new URL(granted.url).port}`, "localhost", host.port, trustProxy, "x"), "status 407");
    // A run whose grant is for other hosts: carried through unopened (the host's own certificate), placeholder as sent.
    const other = proxy.admit({ hosts: ["api.github.com"], placeholder: placeholder("r_8"), value: TOKEN, used: (h) => used.push(h) });
    assert.equal(await viaProxy(other.url, "localhost", host.port, pem(upstreamCa.cert), `Bearer ${placeholder("r_8")}`), `auth=Bearer ${placeholder("r_8")};host=localhost:${host.port}`);
    assert.equal(used.length, 2);
    // Ended: its credentials no longer let it through.
    granted.end();
    assert.equal(await viaProxy(granted.url, "localhost", host.port, trustProxy, "x"), "status 407");
    // Plain HTTP is not carried.
    const plain = await new Promise<number>((resolve) => httpRequest({ host: "127.0.0.1", port: Number(new URL(other.url).port), path: "http://localhost/" }, (res) => resolve(res.statusCode!)).end());
    assert.equal(plain, 405);
  } finally {
    proxy.close();
    host.server.close();
    rmSync(dir, { recursive: true, force: true });
  }
  assert.equal(swap("token stillfail-secret:r_1", { placeholder: "stillfail-secret:r_1", value: "v" }), "token v");
});

/// An unencrypted OpenSSH private key file for a node key, as ssh-keygen writes it.
function openssh(key: KeyObject): string {
  const u32 = (n: number) => { const b = Buffer.alloc(4); b.writeUInt32BE(n); return b; };
  const str = (b: Buffer | string) => { const v = typeof b === "string" ? Buffer.from(b) : b; return Buffer.concat([u32(v.length), v]); };
  const mp = (b64: string) => { const v = Buffer.from(b64, "base64url"); return str(v[0]! & 0x80 ? Buffer.concat([Buffer.from([0]), v]) : v); };
  const jwk = key.export({ format: "jwk" });
  let pub: Buffer, priv: Buffer;
  if (jwk.kty === "OKP") {
    const x = Buffer.from(jwk.x!, "base64url"), d = Buffer.from(jwk.d!, "base64url");
    pub = Buffer.concat([str("ssh-ed25519"), str(x)]);
    priv = Buffer.concat([str("ssh-ed25519"), str(x), str(Buffer.concat([d, x])), str("test@ed")]);
  } else {
    pub = Buffer.concat([str("ssh-rsa"), mp(jwk.e!), mp(jwk.n!)]);
    priv = Buffer.concat([str("ssh-rsa"), mp(jwk.n!), mp(jwk.e!), mp(jwk.d!), mp(jwk.qi!), mp(jwk.p!), mp(jwk.q!), str("test@rsa")]);
  }
  let section = Buffer.concat([u32(7), u32(7), priv]);
  for (let i = 1; section.length % 8 !== 0; i++) section = Buffer.concat([section, Buffer.from([i])]);
  const body = Buffer.concat([Buffer.from("openssh-key-v1\0"), str("none"), str("none"), str(""), u32(1), str(pub), str(section)]);
  return `-----BEGIN OPENSSH PRIVATE KEY-----\n${body.toString("base64").replace(/.{70}/g, "$&\n")}\n-----END OPENSSH PRIVATE KEY-----\n`;
}

test("the ssh-agent lists the granted key and signs with it, Ed25519 and RSA, and nothing else", async () => {
  const u32 = (n: number) => { const b = Buffer.alloc(4); b.writeUInt32BE(n); return b; };
  const str = (b: Buffer) => Buffer.concat([u32(b.length), b]);
  const read = (b: Buffer, at: number) => [b.subarray(at + 4, at + 4 + b.readUInt32BE(at)), at + 4 + b.readUInt32BE(at)] as const;
  for (const kind of ["ed25519", "rsa"] as const) {
    const { privateKey, publicKey } = kind === "rsa" ? generateKeyPairSync("rsa", { modulusLength: 2048 }) : generateKeyPairSync("ed25519");
    const k = parseSshKey(openssh(privateKey));
    assert.equal(k.comment, `test@${kind === "rsa" ? "rsa" : "ed"}`);
    const listed = answer(k, Buffer.from([11]), () => true);
    assert.equal(listed[0], 12);
    assert.equal(listed.readUInt32BE(1), 1);
    assert.deepEqual(read(listed, 5)[0], k.blob);
    const data = randomBytes(64);
    const flags = kind === "rsa" ? 2 : 0;
    const signedReply = answer(k, Buffer.concat([Buffer.from([13]), str(k.blob), str(data), u32(flags)]), () => true);
    assert.equal(signedReply[0], 14);
    const [sigBlob] = read(signedReply, 1);
    const [alg, at] = read(sigBlob, 0);
    const [sig] = read(sigBlob, at);
    assert.equal(alg.toString(), kind === "rsa" ? "rsa-sha2-256" : "ssh-ed25519");
    assert.ok(verify(kind === "rsa" ? "sha256" : null, data, publicKey, sig));
    // Refused: when not allowed, for another key, or anything else asked.
    assert.deepEqual(answer(k, Buffer.concat([Buffer.from([13]), str(k.blob), str(data), u32(0)]), () => false), Buffer.from([5]));
    assert.deepEqual(answer(k, Buffer.concat([Buffer.from([13]), str(Buffer.from("other")), str(data), u32(0)]), () => true), Buffer.from([5]));
    assert.deepEqual(answer(k, Buffer.from([17]), () => true), Buffer.from([5]));
  }
  // Over its socket.
  const k = parseSshKey(openssh(generateKeyPairSync("ed25519").privateKey));
  const dir = mkdtempSync(join(tmpdir(), "vault-ssh-"));
  const server = await serveAgent(join(dir, "a.sock"), k, () => true);
  try {
    const reply = await new Promise<Buffer>((resolve) => {
      const s = netConnect(join(dir, "a.sock"), () => s.write(Buffer.concat([u32(1), Buffer.from([11])])));
      let got = Buffer.alloc(0);
      s.on("data", (b) => {
        got = Buffer.concat([got, b]);
        if (got.length >= 4 && got.length >= 4 + got.readUInt32BE(0)) {
          s.end();
          resolve(got.subarray(4));
        }
      });
    });
    assert.equal(reply[0], 12);
  } finally {
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a command run with a grant in its environment: its output comes back with the value hidden, its exit code as it was", async () => {
  const w = world();
  const keeper = new Keeper(() => 1000);
  const r = requestOf("r_env", keeper.open("r_env"), { mode: "env" });
  assert.equal(keeper.accept(w.state, w.vault, w.item, r, grantOf(r, w.alice, w.plain, { mode: "env", hosts: [] })), null);
  const held = keeper.usable("s1", "r_env");
  assert.ok(typeof held !== "string");
  const dir = mkdtempSync(join(tmpdir(), "vault-run-"));
  const used: string[] = [];
  try {
    const ran = await runWith(held, { command: 'printf "%s\\n" "$GH_TOKEN"; printf "%s" "$STILLFAIL_SECRET" | base64; echo done >&2; exit 3', cwd: dir, env: "GH_TOKEN", timeoutMs: 60_000 }, new Proxy(dir, Date.now), { PATH: process.env.PATH ?? "" }, (d) => used.push(d));
    assert.equal(ran.code, 3);
    assert.ok(!ran.output.includes(TOKEN) && !ran.output.includes(Buffer.from(TOKEN).toString("base64").slice(0, 40)), ran.output);
    assert.equal(ran.output.split(HIDDEN).length - 1, 2, ran.output);
    assert.match(ran.output, /done/);
    assert.deepEqual(used, ["environment"]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a request from secret_use to the grant: listed for the chat's starter, decided by the vault's member, refused otherwise", async () => {
  const w = world();
  const db = new DatabaseSync(":memory:");
  const vaults = new VaultStore(db);
  vaults.putVault(w.vault);
  vaults.putItem(w.item);
  const notified: [string, string][] = [];
  let starter = "bob@x.com";
  const hub = {
    store: {
      getSession: (k: string) => (k === "s1" ? { key: "s1", ws: null, workspace: "/tmp" } : null),
      starter: () => starter.toLowerCase(),
      latestThread: () => null,
      withdrawCard: () => true,
      subscribe: () => () => {},
    },
    notify: (k: string, text: string) => notified.push([k, text]),
  };
  const dir = mkdtempSync(join(tmpdir(), "vault-secrets-"));
  const secrets = new Secrets({ db, vaults, plain: new PlainStore(db), home: () => w.state.ws, hub: hub as never, data: dir, lock: () => w.state, now: () => 1_000_000 });
  const seen: Request[] = [];
  secrets.listen((r) => seen.push(r));
  try {
    assert.deepEqual(secrets.listings("s1").map((l) => l.listing.name), ["GitHub"]);
    // carol is in no vault: nothing for her chats.
    starter = "carol@x.com";
    assert.deepEqual(secrets.listings("s1"), []);
    await assert.rejects(secrets.ask("s1", { item: "GitHub", reason: "x" }), /No secret named/);
    starter = "bob@x.com";
    await assert.rejects(secrets.ask("s1", { item: "GitHub", reason: "x", mode: "ssh" }), /only by proxy, env/);

    // Asked: the tool answers at once, not holding the agent's turn (and with it the chat) until someone decides
    // (2026-10-30: 「密钥存储申请不是异步的，没法在 agent 申请的时候询问其它事项」).
    const asked = secrets.ask("s1", { item: "github", reason: "rerun CI", command: "gh run rerun 1" });
    const first = await Promise.race([asked, new Promise((r) => setImmediate(r)).then(() => "still held")]);
    assert.match(first, /^Asked for 「GitHub」 .*You are told in this session when it is decided: meanwhile go on with what does not need it/);
    const [request] = secrets.pending(w.state.ws, w.state, { sub: "alice", email: "alice@x.com" });
    assert.ok(request && request.status === "pending" && request.command === "gh run rerun 1" && request.hosts?.join() === "api.github.com,*.example.com");
    assert.deepEqual(secrets.pending(w.state.ws, w.state, { sub: "carol", email: "carol@x.com" }), [], "only the vault's members see it");
    assert.match(secrets.grant(w.state, "carol", grantOf(request, w.carol, w.plain, { exp: 1000 + 600 }))!, /members decide/);
    assert.equal(notified.length, 0);
    // Granted by alice: the agent is told in its session.
    assert.equal(secrets.grant(w.state, "alice", grantOf(request, w.alice, w.plain, { exp: 1000 + 600 })), null);
    assert.equal(notified.length, 1);
    assert.equal(notified[0]![0], "s1");
    assert.match(notified[0]![1], /^Granted: 「GitHub」, grant r_/);
    assert.deepEqual(secrets.held("s1").map((h) => h.request.id), [request.id]);
    assert.deepEqual(seen.map((r) => r.status), ["pending", "granted"]);
    assert.deepEqual(secrets.pending(w.state.ws, w.state, { sub: "alice", email: "alice@x.com" }), []);
    assert.match(secrets.grant(w.state, "alice", grantOf(request, w.alice, w.plain, { exp: 1000 + 600 }))!, /granted/);
    assert.equal(notified.length, 1, "told once");

    // Still waiting when the station restarted: its box went with the old process, so it gets a new one, told to the
    // vault's members; the app's grant sealed to the old one does not open, one sealed to the new one is taken.
    const lost = requestOf("r_01HZZZZZZZZZZZZZZZZZZZZLOST", newBoxPair().pub, { session: "s1" });
    db.prepare("INSERT INTO vault_requests (ws, id, session, status, body, thread, card_ts) VALUES (?, ?, ?, ?, ?, NULL, NULL)").run(lost.ws, lost.id, lost.session, lost.status, JSON.stringify(lost));
    seen.length = 0;
    secrets.reboxed();
    const [again] = secrets.pending(w.state.ws, w.state, { sub: "alice", email: "alice@x.com" });
    assert.ok(again && again.id === lost.id && again.box !== "" && again.box !== lost.box, JSON.stringify(again));
    assert.deepEqual(seen.map((r) => [r.id, r.box]), [[lost.id, again.box]]);
    assert.match(secrets.grant(w.state, "alice", grantOf(lost, w.alice, w.plain, { exp: 1000 + 600 }))!, /does not open/);
    assert.equal(secrets.grant(w.state, "alice", grantOf(again, w.alice, w.plain, { exp: 1000 + 600 })), null);
    assert.deepEqual(secrets.held("s1").map((h) => h.request.id).sort(), [request.id, lost.id].sort());
    // Told in its session, as every decision is.
    assert.deepEqual(notified.map(([k]) => k), ["s1", "s1"]);
    assert.match(notified[1]![1], /^Granted: 「GitHub」, grant r_01HZZZZZZZZZZZZZZZZZZZZLOST/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("at a handover a vault's grants and the requests still waiting go over to the next process, never written down", async () => {
  const w = world();
  const db = new DatabaseSync(":memory:");
  const vaults = new VaultStore(db);
  vaults.putVault(w.vault);
  vaults.putItem(w.item);
  const hub = {
    store: {
      getSession: (k: string) => (k === "s1" ? { key: "s1", ws: null, workspace: "/tmp" } : null),
      starter: () => "bob@x.com",
      latestThread: () => null,
      withdrawCard: () => true,
      subscribe: () => () => {},
    },
    notify: () => {},
  };
  const dir = mkdtempSync(join(tmpdir(), "vault-carry-"));
  let coming = false;
  const make = () => new Secrets({ db, vaults, plain: new PlainStore(db), home: () => w.state.ws, hub: hub as never, data: dir, lock: () => w.state, now: () => 1_000_000, coming: () => coming });
  const alice = { sub: "alice", email: "alice@x.com" };
  try {
    const before = make();
    const asked = before.ask("s1", { item: "github", reason: "rerun CI" });
    await new Promise((r) => setImmediate(r));
    const [first] = before.pending(w.state.ws, w.state, alice);
    assert.equal(before.grant(w.state, "alice", grantOf(first!, w.alice, w.plain, { scope: "chat", exp: 1000 + 3600, timeout: { kind: "idle", seconds: 3600 } })), null);
    await asked;
    // Asked again, not decided yet as the process hands over.
    void before.ask("s1", { item: "github", reason: "and again" });
    await new Promise((r) => setImmediate(r));
    const [second] = before.pending(w.state.ws, w.state, alice);
    const carried = JSON.stringify(before.carried());

    // The next process, before what the one before held comes: the waiting request is not let go meanwhile.
    coming = true;
    const after = make();
    assert.match(after.keeper.usable("s1", first!.id) as string, /no such grant/);
    assert.deepEqual(after.pending(w.state.ws, w.state, alice).map((r) => r.id), [second!.id]);
    after.carry(JSON.parse(carried));
    coming = false;
    const held = after.keeper.usable("s1", first!.id);
    assert.ok(typeof held !== "string" && held.secret.fields.value === TOKEN, String(held));
    assert.deepEqual(after.pending(w.state.ws, w.state, alice).map((r) => r.id), [second!.id]);
    assert.equal(after.grant(w.state, "alice", grantOf(second!, w.alice, w.plain, { exp: 1000 + 600 })), null);
    assert.deepEqual(after.held("s1").map((h) => h.request.id).sort(), [first!.id, second!.id].sort());

    // Nothing of the value is in the database; a restart (nothing carried) forgets them, as ever.
    const tables = db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all() as { name: string }[];
    for (const { name } of tables) assert.ok(!JSON.stringify(db.prepare(`SELECT * FROM ${name}`).all()).includes(TOKEN), name);
    assert.deepEqual(make().held("s1"), []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the plain library (no security mode): listed for its owner's chats, decided by the owner alone, its uses kept; locked, nothing given", async () => {
  const db = new DatabaseSync(":memory:");
  const plain = new PlainStore(db);
  const ws = "ws1";
  const item = { ws, id: "i_01JAPLAIN0000000000000000GH", owner: "bob@x.com", version: 0, kind: "token" as const, name: "GitHub", fields: { value: TOKEN }, notes: "", listing: { name: "GitHub", kind: "token" as const, modes: ["proxy" as const, "env" as const], hosts: ["api.github.com"], env: "GH_TOKEN" }, at: 1000 };
  plain.put(item);
  plain.put({ ...item, id: "i_01JAPLAIN0000000000000000XX", name: "Private", listing: undefined as never });
  let lock: ReturnType<typeof world>["state"] | null = null;
  let starter = "bob@x.com";
  const notified: [string, string][] = [];
  const hub = {
    store: {
      getSession: (k: string) => (k === "s1" ? { key: "s1", ws: null, workspace: "/tmp" } : null),
      starter: () => starter.toLowerCase(),
      latestThread: () => null,
      withdrawCard: () => true,
      subscribe: () => () => {},
    },
    notify: (k: string, text: string) => notified.push([k, text]),
  };
  const dir = mkdtempSync(join(tmpdir(), "vault-plain-"));
  const secrets = new Secrets({ db, vaults: new VaultStore(db), plain, home: () => ws, hub: hub as never, data: dir, lock: () => lock, now: () => 1_000_000, title: () => "修 CI" });
  try {
    assert.deepEqual(secrets.listings("s1").map((l) => [l.vault, l.listing.name, l.owner]), [[PLAIN, "GitHub", "bob@x.com"]], "only the listed one");
    starter = "carol@x.com";
    assert.deepEqual(secrets.listings("s1"), [], "another's chat lists none of bob's");
    starter = "bob@x.com";

    const asked = secrets.ask("s1", { item: "GitHub", reason: "rerun CI", command: "gh run rerun 1" });
    await new Promise((r) => setImmediate(r));
    const bob = { sub: "bob", email: "Bob@x.com" };
    const [request] = secrets.pending(ws, null, bob);
    assert.ok(request && request.vault === PLAIN && request.owner === "bob@x.com" && request.box === "");
    assert.deepEqual(secrets.pending(ws, null, { sub: "carol", email: "carol@x.com" }), [], "only its owner sees it");
    assert.match(secrets.grantPlain(ws, null, "carol@x.com", { request: request.id, scope: "once" })!, /owner decides/);
    assert.equal(secrets.grantPlain(ws, null, bob.email, { request: request.id, scope: "once" }), null);
    await asked;
    assert.match(notified.at(-1)![1], /^Granted: 「GitHub」, grant r_/);
    const held = secrets.held("s1")[0]!;
    assert.equal(held.grant.mode, "proxy");
    assert.deepEqual(held.grant.hosts, ["api.github.com"]);

    // Turned down: a use too, said so.
    const again = secrets.ask("s1", { item: "GitHub", reason: "again" });
    await new Promise((r) => setImmediate(r));
    const [second] = secrets.pending(ws, null, bob);
    assert.equal(secrets.denyPlain(ws, bob.email, { request: second!.id }), null);
    await again;
    assert.match(notified.at(-1)![1], /refused/);
    const uses = secrets.uses(ws, null, PLAIN, bob);
    // Both asked in the same second: in either order.
    assert.deepEqual(uses.map((u) => [u.item, u.denied, u.chatTitle, u.command]).sort((x, y) => Number(x[1]) - Number(y[1])), [[item.id, false, "修 CI", "gh run rerun 1"], [item.id, true, "修 CI", null]]);
    assert.deepEqual(secrets.uses(ws, null, PLAIN, { sub: "carol", email: "carol@x.com" }), [], "not carol's to see");

    // Security mode on: the plain library is no longer offered, and nothing of it is granted.
    const third = secrets.ask("s1", { item: "GitHub", reason: "once more" });
    await new Promise((r) => setImmediate(r));
    const [pending] = secrets.pending(ws, null, bob);
    lock = world().state;
    assert.match(secrets.grantPlain(ws, lock, bob.email, { request: pending!.id, scope: "once" })!, /security mode is on/);
    assert.equal(secrets.denyPlain(ws, bob.email, { request: pending!.id }), null);
    await third;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a grant for the chat: offered as far as the item allows, kept across a restart (the plain library's), ended when the chat is archived", async () => {
  const db = new DatabaseSync(":memory:");
  const plain = new PlainStore(db);
  const ws = "ws1";
  const listing = { name: "Slack", kind: "token" as const, modes: ["proxy" as const], hosts: ["slack.com"] };
  const item = { ws, id: "i_01JAPLAIN0000000000000000SL", owner: "bob@x.com", version: 0, kind: "token" as const, name: "Slack", fields: { value: TOKEN }, notes: "", listing, at: 1000 };
  plain.put(item);
  const sessions = new Map<string, { archivedAt: number | null }>([["s1", { archivedAt: null }], ["s2", { archivedAt: null }]]);
  let listener: (c: { type: string; key: string }) => void = () => {};
  const cards: { options: { label: string; recommended?: boolean }[] }[] = [];
  let thread: unknown = null;
  const hub = {
    store: {
      getSession: (k: string) => (sessions.has(k) ? { key: k, ws: null, workspace: "/tmp", ...sessions.get(k) } : null),
      starter: () => "bob@x.com",
      latestThread: () => thread,
      withdrawCard: () => true,
      restateCard: () => true,
      insertMessage: (m: { card: (typeof cards)[number] }) => (cards.push(m.card), [1]),
      subscribe: (f: typeof listener) => ((listener = f), () => {}),
    },
    chat: () => ({ post: async () => "1.0" }),
    shared: () => {},
    notify: () => {},
  };
  const dir = mkdtempSync(join(tmpdir(), "vault-chat-"));
  let now = 1_000_000;
  const make = () => new Secrets({ db, vaults: new VaultStore(db), plain, home: () => ws, hub: hub as never, data: dir, lock: () => null, now: () => now });
  const grant = async (secrets: Secrets, session: string, scope: string) => {
    const asked = secrets.ask(session, { item: "Slack", reason: "backfill" });
    await new Promise((r) => setImmediate(r));
    const [request] = secrets.pending(ws, null, { sub: "bob", email: "bob@x.com" });
    const why = secrets.grantPlain(ws, null, "bob@x.com", { request: request!.id, scope, ...(scope === "once" ? {} : { timeout: { kind: "fixed", seconds: scope === "hour" ? 3600 : 30 * 86400 } }) });
    // Refused: turned down, so nothing is left waiting.
    if (why !== null) secrets.denyPlain(ws, "bob@x.com", { request: request!.id });
    await asked;
    return [why, request!.id] as const;
  };
  try {
    // The card offers every scope, the longest recommended; an item that stops at an hour, those up to it.
    thread = { connect: "c", thread: { id: 1, channel: "EMBER", threadTs: "1.0", surface: STILLFAIL_SURFACE } };
    let secrets = make();
    const [, first] = await grant(secrets, "s1", "chat");
    assert.deepEqual(cards[0]!.options.map((o) => [o.label, !!o.recommended]), [["仅本次", false], ["本对话 1 小时内", false], ["本对话直到归档", true], ["拒绝", false]]);
    plain.put({ ...item, version: 1, listing: { ...listing, lasts: "hour" } });
    const [refused] = await grant(secrets, "s2", "chat");
    assert.match(refused!, /hour at most/);
    assert.deepEqual(cards[1]!.options.map((o) => [o.label, !!o.recommended]), [["仅本次", false], ["本对话 1 小时内", true], ["拒绝", false]]);
    // The owner's longest grant, for the items that say none (the latest word kept); an item's own goes first.
    plain.put({ ...item, version: 2 });
    assert.equal(plain.setLasts(ws, "bob@x.com", "once", 10), null);
    assert.equal(plain.setLasts(ws, "bob@x.com", "chat", 5), null);
    assert.match(plain.setLasts(ws, "bob@x.com", "week", 20)!, /once, hour or chat/);
    assert.deepEqual(plain.lasts(ws, "bob@x.com"), { lasts: "once", at: 10 });
    const [refusedOnce] = await grant(secrets, "s2", "hour");
    assert.match(refusedOnce!, /once at most/);
    assert.deepEqual(cards[2]!.options.map((o) => o.label), ["仅本次", "拒绝"]);
    plain.put({ ...item, version: 3, listing: { ...listing, lasts: "chat" } });
    assert.equal((await grant(secrets, "s2", "hour"))[0], null);
    assert.equal(plain.setLasts(ws, "bob@x.com", "chat", 30), null);
    plain.put({ ...item, version: 4 });
    thread = null;

    // After a restart a grant for one use, used, stays used; a day later the chat's is still held, its value read again.
    const [, once] = await grant(secrets, "s2", "once");
    secrets.keeper.spend(once);
    assert.match(make().keeper.usable("s2", once) as string, /one use/);
    now += 86400_000;
    secrets = make();
    assert.deepEqual(secrets.held("s1").map((h) => [h.request.id, h.grant.scope, h.secret.fields.value]), [[first, "chat", TOKEN]]);

    // Archived: it ends, and is not taken up by the next restart.
    sessions.set("s1", { archivedAt: now });
    listener({ type: "session", key: "s1" });
    assert.deepEqual(secrets.held("s1"), []);
    sessions.set("s1", { archivedAt: null });
    assert.deepEqual(make().held("s1"), []);
    // Run out after 30 days, restart or not.
    const [, second] = await grant(secrets, "s1", "chat");
    now += 30 * 86400_000;
    assert.match(make().keeper.usable("s1", second) as string, /no such grant/);

    const waiting = secrets.ask("s2", { item: "Slack", reason: "daily check", timeout: { kind: "idle", seconds: 3600 } });
    await new Promise((r) => setImmediate(r));
    const [idleRequest] = secrets.pending(ws, null, { sub: "bob", email: "bob@x.com" });
    assert.equal(secrets.grantPlain(ws, null, "bob@x.com", { request: idleRequest!.id, scope: "hour", timeout: { kind: "idle", seconds: 3600 } }), null);
    await waiting;
    now += 3500_000;
    secrets.keeper.renew("s2", idleRequest!.id);
    now += 200_000;
    const restored = make();
    assert.equal(typeof restored.keeper.usable("s2", idleRequest!.id), "object", "renewed deadline survives a restart");
    now += 3400_000;
    assert.match(restored.keeper.usable("s2", idleRequest!.id) as string, /ran out/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

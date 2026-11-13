// The vault on the device (src/vault/, src/views/vault.ts): the formats on the values the stations are tested on
// (station/test/fixtures/vault-vectors.json), the lock checked entry by entry before a key is sealed to anyone, and the
// calls against a station that keeps what it is given, on the testing host's secure storage; and turning the lock off,
// on the same rig, asking the person first. Its time is the test clock.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { apply as applyOps } from "../src/delta.ts";
import { HostError } from "../src/error.ts";
import { jsonResponse } from "../src/testing.ts";
import { t } from "../src/i18n.ts";
import type { HttpRequest } from "../src/host.ts";
import type { StationAddr } from "../src/station/addr.ts";
import { HostWire, type RequestHead, type StationWire } from "../src/station/wire.ts";
import type { FakeHost } from "../src/testing.ts";
import { type Entry, Signer, entryHash, next, signedBytes } from "../src/lock.ts";
import { bodyHash, wsTag } from "../src/lock-moved.ts";
import { hex, utf8 } from "../src/util.ts";
import {
  type BoxCert, type Item, type Request, type Vault, TAG, boxPublic, decrypt, encryptWith, fromWords, grantContext, itemContext, keyContext,
  openSeal, recoveryPair, rulesCrypto, saveContext, sealWith, sign, signedOk, toWords, verifies,
} from "../src/vault/crypto.ts";
import { checkLock } from "../src/vault/lock-check.ts";
import { checkWith, forgetVerifiedHere, keepVerified } from "../src/vault/verified.ts";
import { BOX_KEY, BOX_PUB, UNLOCK_MS, waitingAs, waitingChecks } from "../src/views/vault.ts";
import { inForceOf, read as readLock } from "../src/views/lock.ts";
import { subscribe, call } from "./helpers.ts";
import { type Answers, base, entry, started, stationLater, stationReplies, status } from "./station-fixture.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";

const V = JSON.parse(readFileSync(new URL("../../../station/test/fixtures/vault-vectors.json", import.meta.url), "utf8"));
const unhex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));
const fill = (b: number, n = 32) => new Uint8Array(n).fill(b);

/// An Ed25519 key from a seed: a lock device's signing key.
function key(seed: Uint8Array) {
  const id = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
  return { id, hex: hex(ed25519.getPublicKey(seed)), signBytes: (b: Uint8Array) => hex(ed25519.sign(b, seed)) };
}

test("a_signature_is_checked_once_for_what_it_is_over_not_again_each_time_it_is_asked", () => {
  // A chat's vault cards checked their device's certificate (a P-256 signature, in JS) twice each time the chat was
  // made: 0.87 s of opening one on a phone (2026-10-31).
  const signer = key(fill(7));
  const record = sign({ device: "d-once", ws: "w", box: "x25519:" + "00".repeat(32) }, TAG.box, signer);
  const before = verifies.count;
  for (let i = 0; i < 5; i++) assert.ok(signedOk(record, TAG.box));
  assert.equal(verifies.count - before, 1, "checked once");
  // what it is over changed, or under another tag: checked, and not good
  assert.equal(signedOk({ ...record, device: "d-other" }, TAG.box), false);
  assert.equal(signedOk(record, TAG.vault), false);
  assert.equal(verifies.count - before, 3);
});

test("a_signature_is_checked_by_the_hosts_own_where_it_has_one_and_by_nobles_where_it_says_it_cannot", () => {
  // A native app's shell checks by libcrux (formally verified); what it says is what counts, true or false.
  const signer = key(fill(8));
  const record = sign({ device: "d-host", ws: "w", box: "x25519:" + "00".repeat(32) }, TAG.box, signer);
  const asked: string[] = [];
  checkWith((alg) => (asked.push(alg), false));
  assert.equal(signedOk(record, TAG.box), false, "the host's answer, though noble's would be yes");
  assert.deepEqual(asked, ["Ed25519"]);
  // One that cannot (null): noble's.
  checkWith(() => null);
  assert.equal(signedOk({ ...record, device: "d-host2" }, TAG.box), false);
  assert.equal(signedOk(sign({ device: "d-host3", ws: "w", box: "x25519:" + "00".repeat(32) }, TAG.box, signer), TAG.box), true);
  checkWith(null);
});

test("a_signature_checked_on_this_device_is_kept_past_the_run_not_checked_again_as_the_app_starts", () => {
  // The lock's entries and a device's certificate were checked again each time the app started, the first chat with
  // vault cards waiting for it: 0.87 s on a phone (0.1.6339, 2026-10-31).
  const kept = new Map<string, unknown>();
  keepVerified({ get: (k) => kept.get(k), put: (k, ok) => void kept.set(k, ok) });
  try {
    const signer = key(fill(9));
    const record = sign({ device: "d-kept", ws: "w", box: "x25519:" + "11".repeat(32) }, TAG.box, signer);
    const before = verifies.count;
    assert.ok(signedOk(record, TAG.box));
    assert.equal(kept.size, 1);
    // the app started anew: what this run found is gone, what is kept answers
    forgetVerifiedHere();
    assert.ok(signedOk(record, TAG.box));
    assert.equal(verifies.count - before, 1, "checked once");
    assert.equal(signedOk({ ...record, device: "d-kept-2" }, TAG.box), false);
  } finally {
    keepVerified(null);
  }
});

test("the formats: the core makes and checks the stations' vectors", () => {
  const signer = key(unhex(V.signer.seed));
  assert.equal(signer.id, V.signer.key);
  assert.equal(boxPublic(unhex(V.box.priv)), V.box.pub);
  const vaultKey = unhex(V.vaultKey);
  const ctx = keyContext(V.ws, V.vault.id, 0);
  assert.equal(sealWith(V.box.pub, vaultKey, ctx, unhex(V.eph.wrap)), V.vault.keys[0].wrapped);
  assert.equal(sealWith(recoveryPair(unhex(V.recovery[1].entropy)).pub, vaultKey, ctx, unhex(V.eph.recovery)), V.vault.recovery);
  assert.equal(encryptWith(vaultKey, utf8(V.plain), itemContext(V.ws, V.vault.id, V.item.id, 0, 0), unhex(V.nonce)), V.item.ct);
  assert.equal(sealWith(V.requestBox.pub, utf8(V.plain), grantContext(V.ws, V.grant.request), unhex(V.eph.grant)), V.grant.secret);
  // Ed25519 signs the same bytes the same way: the station's signatures are the core's.
  const { sig: _c, ...cert } = V.cert;
  assert.deepEqual(sign(cert, TAG.box, signer), V.cert);
  const { sig: _v, ...vault } = V.vault;
  assert.deepEqual(sign(vault, TAG.vault, signer), V.vault);
  for (const [o, tag] of [[V.cert, TAG.box], [V.vault, TAG.vault], [V.item, TAG.item], [V.grant, TAG.grant], [V.deny, TAG.deny]] as const) assert.ok(signedOk(o, tag), tag);
  assert.equal(signedOk(V.item, TAG.vault), false);
  assert.equal(signedOk({ ...V.item, version: 1 }, TAG.item), false);
  // What the keys open.
  assert.deepEqual(openSeal(unhex(V.box.priv), V.vault.keys[0].wrapped, ctx), vaultKey);
  assert.throws(() => openSeal(unhex(V.box.priv), V.vault.keys[0].wrapped, keyContext(V.ws, V.vault.id, 1)), /does not open/);
  assert.equal(new TextDecoder().decode(decrypt(vaultKey, V.item.ct, itemContext(V.ws, V.vault.id, V.item.id, 0, 0))), V.plain);
  assert.throws(() => decrypt(vaultKey, V.item.ct, itemContext(V.ws, V.vault.id, V.item.id, 1, 0)), /does not open/);
  // The recovery words are BIP-39's, and their keys the stations'.
  for (const r of V.recovery) {
    assert.equal(recoveryPair(unhex(r.entropy)).pub, r.pub);
    assert.equal(toWords(unhex(r.entropy)), V.words[r.entropy]);
    assert.deepEqual(fromWords(`  ${V.words[r.entropy].toUpperCase()} `), unhex(r.entropy));
  }
  const words = V.words[V.recovery[1].entropy].split(" ");
  assert.throws(() => fromWords([...words.slice(0, 23), "abandon"].join(" ")), /do not add up/);
  assert.throws(() => fromWords([...words.slice(0, 23), "notaword"].join(" ")), /not one of/);
  assert.throws(() => fromWords(words.slice(1).join(" ")), /24/);
});

/// A lock: s1 the owner (this app, `me`, and a phone), s2 a member (one app device).
function lockOf(me: { id: string; signBytes(b: Uint8Array): string }, phone: ReturnType<typeof key>, other: ReturnType<typeof key>) {
  const body = {
    owner: "s1", origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: {},
    members: [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "s2", email: "b@x.com", role: "member" }],
    devices: [
      { id: "ab".repeat(32), sub: "s1", kind: "app", label: "this", sign_key: me.id },
      { id: phone.hex, sub: "s1", kind: "app", label: "phone", sign_key: phone.id },
      { id: other.hex, sub: "s2", kind: "app", label: "b", sign_key: other.id },
    ],
    passkeys: [], stations: [], gateways: [],
  };
  const e = next("ws", null, 1000, "genesis", body);
  const genesis: Entry = { ...e, sig: { key: me.id, alg: "Ed25519", sig: me.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } };
  return genesis;
}

test("the lock is checked entry by entry: a device only its signers could add", () => {
  const me = key(fill(1)), phone = key(fill(2)), other = key(fill(3));
  const g = lockOf(me, phone, other);
  const lock = checkLock([g], 2000);
  assert.equal(lock.devices.get(phone.hex)?.sub, "s1");
  const signed = (e: ReturnType<typeof next>, by: ReturnType<typeof key>): Entry => ({ ...e, sig: { key: by.id, alg: "Ed25519", sig: by.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } });
  const head = { seq: 0, hash: entryHash(g), genesis: entryHash(g) };
  // s2, a member, adds a device of their own; not one of s1's.
  const own = signed(next("ws", head, 1001, "device", { id: "cd".repeat(32), sub: "s2", kind: "app", label: "x", sign_key: key(fill(4)).id }), other);
  assert.equal(checkLock([g, own], 2000).devices.get("cd".repeat(32))?.sub, "s2");
  const theirs = signed(next("ws", head, 1001, "device", { id: "cd".repeat(32), sub: "s1", kind: "app", label: "x", sign_key: key(fill(4)).id }), other);
  assert.throws(() => checkLock([g, theirs], 2000), /members add only their own devices/);
  // Signed by a key the lock does not name; changed after signing; not following the head.
  assert.throws(() => checkLock([g, signed(next("ws", head, 1001, "member", { sub: "s3", email: "c", role: "owner" }), key(fill(9)))], 2000), /not signed by a device/);
  assert.throws(() => checkLock([g, { ...own, body: { ...(own.body as object), sub: "s1" } }], 2000), /signature invalid/);
  assert.throws(() => checkLock([g, { ...own, prev: "00".repeat(32) }], 2000), /does not follow/);
  assert.throws(() => checkLock([{ ...g, body: { ...(g.body as object), owner: "s2" } }], 2000), /owner/);
});

/// A station that keeps what it is given (the station's own checks are its tests'): vaults, items, box certificates,
/// the keeper's requests, and the grants and denials it was brought.
function fakeStation() {
  const vaults = new Map<string, Vault>();
  const items = new Map<string, Item>();
  const boxes = new Map<string, BoxCert>();
  const requests: Request[] = [];
  const grants: unknown[] = [];
  const denials: unknown[] = [];
  // The keeper's box for a request, where the test gives one: a grant sealed to another is refused, as the keeper does.
  const keepers = new Map<string, Uint8Array>();
  const locked = { on: true };
  // The plain library (no security mode): items as they are, the owner's decisions, the uses said.
  const plain = new Map<string, any>();
  const plainGrants: unknown[] = [];
  // Secrets agents asked to keep, approved: where they went.
  const saves: unknown[] = [];
  const described: unknown[] = [];
  const plainSaves: unknown[] = [];
  const uses: unknown[] = [];
  const plainLock = { on: false };
  const plainLasts: { lasts?: string; at?: number } = {};
  const reply = (req: HttpRequest): unknown => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (!path.startsWith("/vault/")) return undefined;
    const body = req.body && req.body.length > 0 ? JSON.parse(new TextDecoder().decode(req.body)) : null;
    const [route, query] = path.split("?");
    const key = `${req.method} ${route}`;
    const shown = ({ fields: _, ...rest }: any) => rest;
    switch (key) {
      case "GET /vault/plain":
        return { items: [...plain.values()].map(shown), locked: plainLock.on, ...(plainLasts.lasts ? { lasts: plainLasts.lasts, lastsAt: plainLasts.at } : {}) };
      case "PUT /vault/plain/lasts":
        Object.assign(plainLasts, body);
        return { ok: true };
      case "GET /vault/plain/item":
        return { item: plain.get(new URLSearchParams(query).get("id") ?? "") };
      case "PUT /vault/plain": {
        const prev = plain.get(body.id);
        if (plainLock.on && !body.deleted) return status(409, { error: "locked", code: "vault_locked" });
        if (body.version !== (prev ? prev.version + 1 : 0)) return status(409, { error: "version", code: "vault_conflict" });
        plain.set(body.id, { ...body, owner: "me@x.com" });
        return { item: shown(plain.get(body.id)) };
      }
      case "POST /vault/plain/grants":
        plainGrants.push(body);
        for (const q of requests) if (q.id === body.request) q.status = "granted";
        return { ok: true };
      case "POST /vault/plain/saves":
        plainSaves.push(body);
        for (const q of requests) if (q.id === body.request) q.status = "granted";
        return { ok: true };
      case "GET /vault/uses":
        return { uses: query === "vault=plain" ? uses : [] };
      case "GET /vault/requests":
        return { requests };
    }
    if (!locked.on) return status(409, { error: "no lock", code: "vault_needs_lock" });
    switch (key) {
      case "GET /vault/vaults":
        // (a member's: as the station lists them, those this person is in)
        return { vaults: [...vaults.values()].filter((v) => v.members.includes("s1")) };
      case "POST /vault/vaults/latest":
        return { vaults: (body.held as Vault[]).map((h) => vaults.get(h.id)).filter((v): v is Vault => v !== undefined) };
      case "PUT /vault/vaults": {
        const prev = vaults.get(body.id);
        // A copy from another station: any later version; one no later answered with the one held.
        const copy = query === "copy=1";
        // (of one seq, the one every station keeps: station/src/api/routes/vault.ts)
        if (copy && prev && body.seq <= prev.seq && !(body.seq === prev.seq && rules.vault_supersedes_js(body, prev))) return { vault: prev };
        if (!copy && body.seq !== (prev ? prev.seq + 1 : 0)) return status(409, { error: "seq", code: "vault_conflict", vault: prev ?? null });
        if (!signedOk(body, TAG.vault)) return status(400, { error: "signature", code: "vault_invalid" });
        // (each key's certificate as its device signed it, as the station checks: a field added breaks it; the
        // certificate as the core keeps it carries whose it is, which must not be sealed in, review of #3624)
        for (const k of body.keys ?? []) if (!signedOk(k.cert, TAG.box) || "sub" in k.cert || "own" in k.cert) return status(400, { error: "a key's certificate", code: "vault_invalid" });
        vaults.set(body.id, body);
        return { vault: body };
      }
      case "GET /vault/items":
        return { items: [...items.values()].filter((i) => !query || query === `vault=${i.vault}`) };
      case "PUT /vault/items": {
        const prev = items.get(body.id);
        const copy = query === "copy=1";
        if (!vaults.has(body.vault)) return status(404, { error: "no vault", code: "vault_unknown" });
        if (copy && prev && body.version <= prev.version && !(body.version === prev.version && rules.item_supersedes_js(body, prev))) return { item: prev };
        if (!copy && body.version !== (prev ? prev.version + 1 : 0)) return status(409, { error: "version", code: "vault_conflict", item: prev ?? null });
        if (!signedOk(body, TAG.item)) return status(400, { error: "signature", code: "vault_invalid" });
        items.set(body.id, body);
        return { item: body };
      }
      case "GET /vault/boxes":
        return { boxes: [...boxes.values()] };
      case "PUT /vault/boxes":
        if (!signedOk(body, TAG.box)) return status(400, { error: "signature", code: "vault_invalid" });
        boxes.set(body.device, body);
        return { box: body };
      case "GET /vault/requests":
        return { requests };
      case "POST /vault/grants": {
        const box = keepers.get(body.request);
        if (box) {
          try {
            openSeal(box, body.secret, grantContext("ws", body.request));
          } catch {
            return status(409, { error: "the grant's secret does not open", code: "vault_refused" });
          }
        }
        grants.push(body);
        for (const q of requests) if (q.id === body.request) q.status = "granted";
        return { ok: true };
      }
      case "POST /vault/denials":
        denials.push(body);
        for (const q of requests) if (q.id === body.request) q.status = "denied";
        return { ok: true };
      case "POST /vault/saves": {
        // Kept only once its item is here (its copy brought first).
        const r = requests.find((q) => q.id === body.request);
        if (!r || !items.has(r.item) || items.get(r.item)!.vault !== body.vault) return status(409, { error: "not here", code: "vault_refused" });
        saves.push(body);
        r.status = "granted";
        return { ok: true };
      }
      case "POST /vault/described": {
        // Taken only once its item here says so (its copy brought first).
        const r = requests.find((q) => q.id === body.request);
        const l = r ? items.get(r.item)?.listing : undefined;
        if (!r || !r.describe || l?.name !== r.describe.name || (l.about ?? "") !== r.describe.about) return status(409, { error: "not here", code: "vault_refused" });
        described.push(body);
        r.status = "granted";
        return { ok: true };
      }
    }
    return status(404, { error: `no route ${key}` });
  };
  return { vaults, items, boxes, requests, grants, denials, keepers, locked, plain, plainGrants, plainLasts, uses, plainLock, saves, described, plainSaves, reply };
}

/// A core on an app's host (keys kept, secure storage), reaching `ws/st` (the fake station); its lock put in place.
/// `web`: a web page's host (no secure storage). `two`: a second station, `ws/st2` (`st2`), in the workspace too.
/// `more`: what else the station answers (its chats' posts).
/// `also`: more of what the workspace's view says (its stations by other ids).
async function rig(web = false, two = false, more: Answers = {}, also?: Record<string, unknown>) {
  const st = fakeStation();
  const st2 = fakeStation();
  const me = { signer: null as Signer | null };
  const phone = key(fill(2)), other = key(fill(3));
  // Which station a request is for, as the wire says it (both answer at the same origin here).
  const AT = "x-test-station";
  const wire = two ? (host: FakeHost) => {
    const inner = new HostWire(host);
    return { request: (station: StationAddr, head: RequestHead, body: Uint8Array) => inner.request(station, { ...head, headers: [...head.headers, [AT, station.station]] }, body) } as StationWire;
  } : undefined;
  const s = await started({ ...base(), ...more }, 0, wire, (x) => {
    x.host.appKeys = true;
    me.signer = Effect.runSync(Signer.make(x.host));
    if (web) x.host.secureGet = undefined;
    if (two) x.cloud.also = { stations: [{ id: "st", name: "studio", online: true, last_seen: null }, { id: "st2", name: "mini", online: true, last_seen: null }] };
    if (also) x.cloud.also = { ...x.cloud.also, ...also };
    stationReplies(x.host, (req) => (req.headers.some(([k, v]) => k === AT && v === "st2") ? st2.reply(req) : st.reply(req)));
  });
  const genesis = lockOf({ id: me.signer!.id, signBytes: (b) => me.signer!.signBytes(b) }, phone, other);
  const lock = { head: { seq: 0, hash: entryHash(genesis), genesis: entryHash(genesis) }, entries: [genesis], requests: [] };
  let ui = s.core.connect();
  const values = new Map<number, unknown>();
  const done = new Map<number, Record<string, unknown>>();
  let id = 100;
  const take = () => {
    for (const [, m] of s.host.takeEmitted()) {
      const msg = m as Record<string, unknown>;
      if ("value" in msg) values.set(msg.id as number, msg.value);
      else if ("delta" in msg) values.set(msg.id as number, applyOps(values.get(msg.id as number), msg.delta as never));
      else if ("ok" in msg || "error" in msg) done.set(msg.id as number, msg);
    }
  };
  /// A call's answer: its value, or a failure with its code.
  const ask = async (name: string, params: Record<string, unknown>): Promise<any> => {
    const n = ++id;
    call(s.core, ui, n, name, { workspace: "ws", ...params });
    for (let i = 0; i < 200 && !done.has(n); i++) {
      await s.host.time.pass(10);
      take();
    }
    const a = done.get(n);
    if (!a) throw new Error(`${name}: no answer`);
    // What it changed shown as the store sends it.
    await s.host.time.pass(100);
    take();
    if ("error" in a) {
      const e = new Error((a.error as { message: string }).message) as Error & { code: string };
      e.code = (a.error as { code: string }).code;
      throw e;
    }
    return a.ok;
  };
  const watch = async (n: number, topic: Record<string, unknown>) => {
    subscribe(s.core, ui, n, topic as never);
    await s.host.time.pass(100);
    take();
    return () => {
      take();
      return values.get(n) as any;
    };
  };
  /// The app started anew on the same host: what it keeps (its database, its secure storage) as it was, nothing of the
  /// run before in memory (the keys unsealed). Topics watched before are not watched again.
  const restart = async () => {
    await Effect.runPromise(s.core.inner.data.written);
    s.core.close();
    s.host.takeEmitted();
    s.core = await Core.create(s.host, { clock: s.host.time.clock, sample: 0, wire: () => (wire ? wire(s.host) : new HostWire(s.host)) });
    await s.host.time.pass(500);
    ui = s.core.connect();
    r.core = s.core;
  };
  const r = { ...s, st, st2, phone, other, lock, me, ask, watch, take, restart, putLock: () => s.core.inner.data.put("lock", "ws", lock) };
  return r;
}

/// One more entry of the rig's lock, signed by `by` (this device's signer, the owner's, by default), the lock put in
/// place anew: the core checks it again as it is next asked.
function grow(r: Awaited<ReturnType<typeof rig>>, kind: string, body: unknown, by?: ReturnType<typeof key>): void {
  const signer = by ?? { id: r.me.signer!.id, signBytes: (b: Uint8Array) => r.me.signer!.signBytes(b) };
  const e = next("ws", r.lock.head, 3000 + r.lock.entries.length, kind, body);
  const entry: Entry = { ...e, sig: { key: signer.id, alg: "Ed25519", sig: signer.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } };
  r.lock.entries.push(entry);
  r.lock.head = { seq: entry.seq, hash: entryHash(entry), genesis: r.lock.head.genesis };
  r.putLock();
}

const fails = async (p: Promise<unknown>, code: string) => {
  await assert.rejects(p, (e: Error & { code?: string }) => {
    assert.equal(e.code, code, e.message);
    return true;
  });
};

test("turning the lock off asks the person first; their no signs and sends nothing", async () => {
  const r = await rig();
  r.putLock();
  // The cloud keeps the chain: given as it is, what is posted taken.
  const posted: Entry[] = [];
  stationReplies(r.host, (req) => {
    if (!req.url.endsWith("/v1/workspaces/ws/lock")) return r.st.reply(req);
    if (req.method === "GET") return r.lock;
    posted.push(...JSON.parse(new TextDecoder().decode(req.body!)).entries);
    return { ok: true };
  });
  const sent = () => posted.map((e) => e.kind);
  r.host.secureRefused = true;
  await fails(r.ask("lock.disable", {}), "user_cancelled");
  assert.equal(r.host.secureAsked.at(-1)?.key, "", "asked by itself, no value read");
  assert.ok(r.host.secureAsked.at(-1)?.reason, "the prompt says why");
  assert.deepEqual(sent(), []);
  r.host.secureRefused = false;
  await r.ask("lock.disable", {});
  assert.deepEqual(sent(), ["disable"], "said yes: the entry is signed and sent");
});

test("vault calls: set up, a vault of one's own, an item written, opened, unlocked a while", async () => {
  const r = await rig();
  // No lock yet: refused, saying so.
  await fails(r.ask("vault.setup", {}), "vault_needs_lock");
  r.putLock();
  const setup = await r.ask("vault.setup", {});
  assert.equal(setup.words.split(" ").length, 24);
  assert.equal(setup.device, "ab".repeat(32));
  assert.ok(r.host.secure.get(BOX_KEY)?.user, "the box key asks the person to be read");
  const cert = r.st.boxes.get("ab".repeat(32))!;
  assert.equal(cert.box, new TextDecoder().decode(r.host.storage.get(BOX_PUB)!));
  assert.equal(cert.recovery, recoveryPair(fromWords(setup.words)).pub);
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  assert.equal(vaults().setUp, true);
  // The person's own vault, made as their first device is set up: keyed for this device and the recovery words;
  // unlocked here as it is made.
  const v = r.st.vaults.get(setup.made)!;
  assert.deepEqual([v.owner, v.members, v.seq, v.keys.length], ["s1", ["s1"], 0, 1]);
  assert.ok(signedOk(v, TAG.vault));
  const vaultKey = openSeal(recoveryPair(fromWords(setup.words)).priv, v.recovery!, keyContext("ws", v.id, 0));
  assert.equal(vaults().vaults[0].name, t("core-misc.vault.personal"), "named in the person's words");
  assert.equal(vaults().vaults[0].open, true);
  assert.equal(vaults().vaults[0].keyed, true);
  // An item: its name in the ciphertext, the listing what agents see.
  const asked = r.host.secureAsked.length;
  const put = await r.ask("vault.putItem", { vault: v.id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" }, domains: ["github.com"], notes: "" }, listing: { name: "gh", kind: "token", modes: ["proxy"], hosts: ["api.github.com"] } });
  assert.equal(r.host.secureAsked.length, asked, "unlocked: not asked again");
  const item = r.st.items.get(put.id)!;
  assert.equal(JSON.parse(new TextDecoder().decode(decrypt(vaultKey, item.ct, itemContext("ws", v.id, item.id, 0, 0)))).fields.value, "ghp_x");
  const shown = await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: v.id });
  assert.deepEqual(shown().items.map((i: any) => [i.name, i.kind, i.listed]), [["GitHub", "token", true]]);
  // Five minutes on: locked again, only the listing's name shown, opening asks the person.
  await r.host.time.pass(UNLOCK_MS, 1000);
  assert.equal(shown().open, false);
  assert.equal(shown().items[0].name, "gh");
  const opened = await r.ask("vault.open", { item: put.id });
  assert.equal(opened.plain.fields.value, "ghp_x");
  assert.equal(r.host.secureAsked.at(-1)?.key, BOX_KEY);
  assert.match(r.host.secureAsked.at(-1)?.reason ?? "", /gh/);
  // A second version, then deleted.
  await r.ask("vault.putItem", { vault: v.id, id: put.id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_y" } } });
  assert.equal(r.st.items.get(put.id)!.version, 1);
  await r.ask("vault.deleteItem", { vault: v.id, item: put.id });
  assert.deepEqual([r.st.items.get(put.id)!.version, r.st.items.get(put.id)!.deleted], [2, true]);
  assert.deepEqual(shown().items, []);
  // Turned down by the person: nothing opened.
  await r.ask("vault.lock", {});
  const again = await r.ask("vault.putItem", { vault: v.id, plain: { kind: "login", name: "mail", fields: { username: "a", password: "b" } } });
  r.host.secureRefused = true;
  await r.ask("vault.lock", {});
  await fails(r.ask("vault.open", { item: again.id }), "vault_refused");
  r.core.close();
});

test("a vault version the stations would refuse is not trusted here: one naming someone not in the lock is not shown, though its owner signed it", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  assert.equal(vaults().vaults.length, 1);
  const v = r.st.vaults.get(id)!;
  const { sig: _, ...rest } = v;
  const ghost = sign({ ...rest, seq: v.seq + 1, members: [...v.members, "ghost"], at: v.at + 1 }, TAG.vault, r.me.signer!);
  r.st.vaults.set(id, ghost);
  r.push("vault", ghost);
  await r.host.time.pass(200);
  // (a station would refuse it, member ghost not in the lock: it is not taken, the version before it shown still)
  assert.deepEqual(vaults().vaults.map((x: any) => [x.id, x.members.length]), [[id, 1]]);
  r.core.close();
});

// A station that lies (the attacks of Scarlata et al., "Zero Knowledge (About) Encryption", USENIX Security 2026, on a
// station rather than a password manager's server): what it makes up is not taken, and hides nothing taken before.

test("a later vault version a station made up (signed by a member who is not its owner) neither shows nor hides the one before it", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  const v = r.st.vaults.get(id)!;
  const { sig: _, ...rest } = v;
  // s2's device signs its owner's vault anew, with s2 in it and no key for this device.
  const forged = sign({ ...rest, seq: v.seq + 1, members: [...v.members, "s2"], keys: [], at: v.at + 1 }, TAG.vault, r.other);
  r.st.vaults.set(id, forged);
  r.push("vault", forged);
  await r.host.time.pass(200);
  assert.deepEqual(vaults().vaults.map((x: any) => [x.id, x.keyed]), [[id, true]], "the vault as it was, still keyed here");
  // Nor one it says deleted it: its items are there still.
  const put0 = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "kept", fields: { value: "0" } } });
  const items = await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: id });
  const gone = sign({ ...rest, seq: v.seq + 2, epoch: v.epoch + 1, keys: [], deleted: true, at: v.at + 2 }, TAG.vault, r.other);
  delete (gone as { recovery?: string }).recovery;
  r.push("vault", gone);
  await r.host.time.pass(200);
  assert.deepEqual(items().items.map((x: any) => x.id), [put0.id], "nothing deleted");
  // The station tells the truth again: nothing lost meanwhile; written on from the version it holds.
  r.st.vaults.set(id, v);
  r.push("vault", v);
  await r.host.time.pass(200);
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "x", fields: { value: "1" } } });
  assert.equal(r.st.items.get(put.id)!.epoch, v.epoch);
  assert.deepEqual(r.st.vaults.get(id)!.members, ["s1"], "s2 was never let in");
  r.core.close();
});

test("a vault a station lists no more is let go here only by the version taking this person out; one it hides without one is held still", async () => {
  const r = await rig();
  r.putLock();
  await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  const mine = r.st.boxes.get("ab".repeat(32))!;
  // s2's vault, this person in it, keyed for this device.
  const id = "v_01M4871X3MTC0903ZX5CPB8JH7";
  const key = fill(11);
  const v0 = sign({ v: 1 as const, ws: "ws", id, seq: 0, owner: "s2", name: "Team", members: ["s2", "s1"], epoch: 0, keys: [{ cert: mine, wrapped: sealWith(mine.box, key, keyContext("ws", id, 0), fill(12)) }], at: 2000 }, TAG.vault, r.other);
  r.st.vaults.set(id, v0);
  r.push("vault", v0);
  await r.host.time.pass(200);
  assert.ok(vaults().vaults.some((v: any) => v.id === id));
  // The station hides it (lists it no more, and has no later version to show): held here still.
  r.st.vaults.delete(id);
  const again = await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: id });
  await r.host.time.pass(1000);
  assert.ok(vaults().vaults.some((v: any) => v.id === id), "held still: a station not listing it says nothing of why");
  again();
  // s2 takes this person out: the station lists it no more, and gives the version that did when asked by the one held.
  const v1 = sign({ v: 1 as const, ws: "ws", id, seq: 1, owner: "s2", name: "Team", members: ["s2"], epoch: 1, keys: [], at: 2001 }, TAG.vault, r.other);
  r.st.vaults.set(id, v1);
  await r.watch(3, { topic: "vaultUses", workspace: "ws", vault: id, item: "x" });
  await r.host.time.pass(1000);
  assert.ok(!vaults().vaults.some((v: any) => v.id === id), "let go: the version taking this person out, checked");
  r.core.close();
});

test("a later item version a station made up (its listing sending the secret elsewhere, its signature not its writer's) leaves the item as it was", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } }, listing: { name: "gh", kind: "token", modes: ["proxy"], hosts: ["api.github.com"] } });
  const shown = await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: id });
  const i = r.st.items.get(put.id)!;
  const { sig: _, ...rest } = i;
  const forged = sign({ ...rest, version: i.version + 1, listing: { ...i.listing!, hosts: ["evil.example"] } }, TAG.item, r.other);
  r.st.items.set(put.id, forged);
  r.push("vault-item", forged);
  await r.host.time.pass(200);
  assert.deepEqual(shown().items.map((x: any) => [x.id, x.listed]), [[put.id, true]], "still there, as it was");
  r.st.items.set(put.id, i);
  // Written on: the next version follows the one its writer signed.
  await r.ask("vault.putItem", { vault: id, id: put.id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_y" } } });
  assert.equal(r.st.items.get(put.id)!.version, i.version + 1);
  r.core.close();
});

test("a later box certificate a station made up for a device in the lock (the box key its own) is not sealed to: the key goes to the device's own box", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const phoneBox = fill(7);
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(phoneBox), at: 2000 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneCert);
  r.push("vault-box", phoneCert);
  await r.host.time.pass(200);
  // The station's own box key put in the phone's name, later, signed by another member's device.
  const evil = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(fill(8)), at: 3000 }, TAG.box, r.other);
  r.st.boxes.set(r.phone.hex, evil);
  r.push("vault-box", evil);
  await r.host.time.pass(200);
  await r.ask("vault.addDevice", { vault: id });
  const keys = r.st.vaults.get(id)!.keys.filter((k) => k.cert.device === r.phone.hex);
  assert.deepEqual(keys.map((k) => k.cert.box), [phoneCert.box], "sealed to the phone's own box only");
  assert.equal(openSeal(phoneBox, keys[0]!.wrapped, keyContext("ws", id, r.st.vaults.get(id)!.epoch)).length, 32);
  r.core.close();
});

test("an older vault version a station gives back (from before it was deleted) is not gone back to", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  const v0 = r.st.vaults.get(id)!;
  await r.ask("vault.delete", { vault: id });
  assert.equal(r.st.vaults.get(id)!.deleted, true);
  // The station gives the version before back, as if it had never been deleted.
  r.st.vaults.set(id, v0);
  r.push("vault", v0);
  await r.host.time.pass(200);
  assert.deepEqual(vaults().vaults, [], "still deleted here");
  await fails(r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "x", fields: { value: "y" } } }), "vault_unknown");
  r.core.close();
});

test("what the system said no with is said in the person's words: no screen lock, no vault here", async () => {
  const r = await rig();
  r.putLock();
  r.host.secureSet = () => Effect.fail(new HostError("no_device_lock"));
  await assert.rejects(r.ask("vault.setup", {}), (e: Error & { code?: string }) => {
    assert.equal(e.code, "no_device_lock");
    assert.equal(e.message, t("core-misc.secure.noDeviceLock"));
    return true;
  });
  assert.equal(r.host.secure.get(BOX_KEY), undefined);
  r.core.close();
});

test("vault calls: another device keyed in by the owner, a device keyed back in by the recovery words", async () => {
  const r = await rig();
  r.putLock();
  const { words, made: id } = await r.ask("vault.setup", {});
  // The phone sets itself up: its certificate comes as the station tells it.
  const phoneBox = fill(7);
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(phoneBox), at: 2000 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneCert);
  r.push("vault-box", phoneCert);
  // A certificate the station made up for a device not in the lock is no device of anyone's.
  const forged = sign({ v: 1 as const, ws: "ws", device: "ef".repeat(32), box: boxPublic(fill(8)), at: 2000 }, TAG.box, key(fill(9)));
  r.push("vault-box", forged);
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  // (given at once: the key is in hand here since the vault was made; 授权新设备 then finds none to give)
  assert.equal(vaults().vaults[0].missing, 0);
  assert.deepEqual(await r.ask("vault.addDevice", { vault: id }), { added: 0 });
  const v1 = r.st.vaults.get(id)!;
  assert.equal(v1.seq, 1);
  const phoneKey = v1.keys.find((k) => k.cert.device === r.phone.hex)!;
  assert.equal(openSeal(phoneBox, phoneKey.wrapped, keyContext("ws", id, 0)).length, 32);
  assert.equal(vaults().vaults[0].missing, 0);
  // This device loses its box key (the app was installed anew): set up again, no new words (its person has them). The
  // vault's key locked away first: in hand still, it would be given to the new box key at once.
  await r.ask("vault.lock", {});
  r.host.secure.delete(BOX_KEY);
  r.host.storage.delete(BOX_PUB);
  const again = await r.ask("vault.setup", {});
  assert.deepEqual([again.words, again.made, r.st.vaults.size], [null, null, 1], "no second vault made: its key is given");
  await r.host.time.pass(100);
  assert.equal(vaults().vaults[0].keyed, false);
  await r.ask("vault.lock", {});
  await fails(r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "x", fields: {} } }), "vault_no_key");
  await fails(r.ask("vault.recover", { words: "abandon ".repeat(24) }), "vault_words");
  const rec = await r.ask("vault.recover", { words });
  assert.deepEqual(rec, { recovered: 1, others: 0 });
  assert.equal(r.st.vaults.get(id)!.seq, 2);
  assert.equal(vaults().vaults[0].keyed, true);
  r.core.close();
});

test("a requested timeout is shown and signed exactly as approved", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } }, listing: { name: "gh", kind: "token", modes: ["proxy"], hosts: ["api.github.com"] } });
  const request: Request = { id: "r_timed", ws: "ws", vault: id, item: put.id, session: "k1", chat: "7", mode: "proxy", reason: "daily", hosts: ["api.github.com"], box: boxPublic(fill(5)), at: 1, status: "pending", timeout: { kind: "idle", seconds: 129600 } };
  r.st.requests.push(request);
  r.push("vault-request", request);
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  assert.deepEqual([vaults().requests[0].timeoutKind, vaults().requests[0].timeoutSeconds], ["idle", 129600]);
  await fails(r.ask("vault.approve", { request: request.id, scope: "chat" }), "invalid_params");
  await r.ask("vault.approve", { request: request.id, scope: "chat", timeout: { kind: "fixed", seconds: 86400 } });
  const grant = r.st.grants[0] as any;
  assert.ok(signedOk(grant, TAG.grant));
  assert.deepEqual([grant.timeout, grant.exp - grant.at], [{ kind: "fixed", seconds: 86400 }, 86400]);
  r.core.close();
});

test("vault calls: an agent's request approved (sealed to its keeper, signed) or turned down", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } }, listing: { name: "gh", kind: "token", modes: ["proxy"], hosts: ["api.github.com"] } });
  const keeper = fill(5);
  const request = (rid: string): Request => ({ id: rid, ws: "ws", vault: id, item: put.id, session: "k1", chat: "7", mode: "proxy", reason: "list PRs", hosts: ["api.github.com"], box: boxPublic(keeper), at: 1, status: "pending" });
  r.st.requests.push(request("r_1"), request("r_2"));
  r.push("vault-request", request("r_1"));
  r.push("vault-request", request("r_2"));
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  assert.deepEqual(vaults().requests.map((q: any) => [q.id, q.itemName, q.reason]), [["r_1", "gh", "list PRs"], ["r_2", "gh", "list PRs"]]);
  const asked = r.host.secureAsked.length;
  await r.ask("vault.approve", { request: "r_1", scope: "hour" });
  assert.equal(r.host.secureAsked.length, asked + 1, "the person is asked, though the vault is unlocked");
  const grant = r.st.grants[0] as any;
  assert.ok(signedOk(grant, TAG.grant));
  assert.deepEqual([grant.request, grant.scope, grant.mode, grant.hosts, grant.exp - grant.at], ["r_1", "hour", "proxy", ["api.github.com"], 3600]);
  assert.equal(JSON.parse(new TextDecoder().decode(openSeal(keeper, grant.secret, grantContext("ws", "r_1")))).fields.value, "ghp_x");
  await r.ask("vault.deny", { request: "r_2" });
  const deny = r.st.denials[0] as any;
  assert.ok(signedOk(deny, TAG.deny));
  assert.equal(deny.request, "r_2");
  assert.deepEqual(vaults().requests, []);
  await fails(r.ask("vault.deny", { request: "r_2" }), "vault_no_request");

  // The chat's grant, until it is archived (the station ends it then; 30 days at most); none longer than the item's
  // `lasts`, which the request says so the approval offers no more.
  const short = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "Prod", fields: { value: "p_x" } }, listing: { name: "prod", kind: "token", modes: ["proxy"], hosts: ["api.github.com"], lasts: "hour" } });
  r.st.requests.push(request("r_3"), { ...request("r_4"), item: short.id });
  r.push("vault-request", request("r_3"));
  r.push("vault-request", { ...request("r_4"), item: short.id });
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual(vaults().requests.map((q: any) => [q.id, q.lasts]), [["r_3", "chat"], ["r_4", "hour"]]);
  await r.ask("vault.approve", { request: "r_3", scope: "chat" });
  const chat = r.st.grants[1] as any;
  assert.deepEqual([chat.request, chat.scope, chat.exp - chat.at], ["r_3", "chat", 30 * 86400]);
  await fails(r.ask("vault.approve", { request: "r_4", scope: "chat" }), "vault_scope");

  // The vault's own longest grant, for its items that say none: a new version its owner signs.
  assert.equal(vaults().vaults[0].lasts, "chat");
  await r.ask("vault.setLasts", { vault: id, lasts: "once" });
  const signed = r.st.vaults.get(id)! as any;
  assert.ok(signedOk(signed, TAG.vault));
  assert.deepEqual([signed.lasts, signed.seq], ["once", 1]);
  r.st.requests.push(request("r_5"));
  r.push("vault-request", request("r_5"));
  await r.host.time.pass(500);
  r.take();
  assert.equal(vaults().vaults[0].lasts, "once");
  assert.deepEqual(vaults().requests.map((q: any) => [q.id, q.lasts]), [["r_4", "hour"], ["r_5", "once"]], "an item's own goes first");
  await fails(r.ask("vault.approve", { request: "r_5", scope: "hour" }), "vault_scope");
  await fails(r.ask("vault.setLasts", { vault: id, lasts: "week" }), "invalid_params");

  // The station restarted after the request came: it waits on with a new box, not heard of here yet. The grant sealed
  // to the old one is refused; the request is read again and sealed to the new one, the person asked once.
  r.st.requests.push(request("r_6"));
  r.push("vault-request", request("r_6"));
  await r.host.time.pass(500);
  r.take();
  const restarted = fill(6);
  r.st.keepers.set("r_6", restarted);
  r.st.requests.find((q) => q.id === "r_6")!.box = boxPublic(restarted);
  const before = [r.host.secureAsked.length, r.st.grants.length];
  await r.ask("vault.approve", { request: "r_6", scope: "once" });
  assert.deepEqual([r.host.secureAsked.length, r.st.grants.length], [before[0]! + 1, before[1]! + 1]);
  const again = r.st.grants.at(-1) as any;
  assert.equal(JSON.parse(new TextDecoder().decode(openSeal(restarted, again.secret, grantContext("ws", "r_6")))).fields.value, "ghp_x");
  r.core.close();
});

test("vault calls: a sign-in granted with the newer cookies its request carries: written as its next version, and those granted", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const old = JSON.stringify([{ name: "user_session", value: "abc", domain: "github.com", path: "/" }]);
  const newer = JSON.stringify([{ name: "user_session", value: "renewed", domain: "github.com", path: "/" }]);
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "browser", name: "GitHub", fields: { cookies: old } }, listing: { name: "GitHub", kind: "browser", modes: ["browser"], hosts: ["github.com"] } });
  const here = [...r.st.boxes.values()][0]!;
  const keeper = fill(5);
  const request = (rid: string, renewal?: Request["renewal"]): Request => ({
    id: rid, ws: "ws", vault: id, item: put.id, session: "k1", chat: "7", mode: "browser", reason: "看 PR", hosts: ["github.com"], box: boxPublic(keeper), at: 1, status: "pending", ...(renewal ? { renewal } : {}),
  });
  const renewal = { id: "n_1", sealed: [{ device: here.device, box: here.box, secret: sealWith(here.box, utf8(JSON.stringify({ cookies: newer })), saveContext("ws", "n_1"), fill(6)) }] };
  r.st.requests.push(request("r_b", renewal));
  r.push("vault-request", request("r_b", renewal));
  await r.watch(1, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(500);
  r.take();
  const asked = r.host.secureAsked.length;
  await r.ask("vault.approve", { request: "r_b", scope: "hour" });
  assert.equal(r.host.secureAsked.length, asked + 1, "the person is asked once, for the grant and the new version alike");
  const grant = r.st.grants.at(-1) as any;
  assert.deepEqual([grant.mode, grant.hosts], ["browser", ["github.com"]], "a sign-in's grant names its sites");
  assert.equal(JSON.parse(new TextDecoder().decode(openSeal(keeper, grant.secret, grantContext("ws", "r_b")))).fields.cookies, newer);
  const written = r.st.items.get(put.id)!;
  assert.ok(signedOk(written, TAG.item));
  assert.deepEqual([written.version, written.listing?.modes], [1, ["browser"]]);
  assert.equal((await r.ask("vault.open", { item: put.id })).plain.fields.cookies, newer);
  r.core.close();
});

/// Chat 7's posts as its station answers them: a person's, then an agent's asking to use `gh` (r_1), then one asking to
/// keep a login (r_s), their cards as the station writes them (station/src/vault/secrets.ts).
function cardsInChat(): Answers {
  const card = (request: string, more: Record<string, unknown> = {}) => ({ type: "options", options: [], vault: { request, name: "gh", mode: "proxy", reason: "list PRs", hosts: ["api.github.com"], command: "gh pr list", ...more } });
  const asks = (n: number, c: unknown) => ({ ...entry(n, "要用 gh"), authorKind: "agent", author: "k1", card: c });
  return { "GET /threads/7/entries?limit=50": { last: 3, entries: [entry(1, "存一下"), asks(2, card("r_1")), asks(3, card("r_s", { save: { kind: "login", username: "demo-user" } }))] } };
}

test("a chat's card of an agent's request comes answered with its post, from the vault the core holds; decided here, how it went at once", async () => {
  const r = await rig(false, false, cardsInChat());
  r.putLock();
  const chat = await r.watch(2, { topic: "chat", station: "ws/st", thread: 7 });
  const asks = () => chat().messages.filter((m: any) => m.card?.vaultAsk).map((m: any) => [m.card.vault, m.card.vaultAsk.answer, m.card.vaultAsk.lasts ?? null, m.card.vaultAsk.status ?? null]);
  // This device's vault not on: one to keep turns it on first; one to use is approved, for the chat at the longest
  // while its request is not held here.
  assert.deepEqual(asks(), [["r_1", "approve", "chat", null], ["r_s", "setUp", null, null]]);
  const useAsk = () => chat().messages.find((m: any) => m.card?.vault === "r_1").card.vaultAsk;
  assert.deepEqual([useAsk().reason, useAsk().howText], ["list PRs", "代理 · 限 api.github.com"]);
  // Set up: the chat's cards say so with no one asking.
  const { made: id } = await r.ask("vault.setup", {});
  assert.deepEqual(asks(), [["r_1", "approve", "chat", null], ["r_s", "approve", null, null]]);
  // Its request held, its item given an hour at most: the hour.
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } }, listing: { name: "gh", kind: "token", modes: ["proxy"], hosts: ["api.github.com"], lasts: "hour" } });
  const request: Request = { id: "r_1", ws: "ws", vault: id, item: put.id, session: "k1", chat: "7", mode: "proxy", reason: "list PRs", hosts: ["api.github.com"], box: boxPublic(fill(5)), at: 1, status: "pending" };
  r.st.requests.push(request);
  r.push("vault-request", request);
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual(asks()[0], ["r_1", "approve", "hour", null]);
  // Approved here: how it went on its card at once, before its station restates it.
  await r.ask("vault.approve", { request: "r_1", scope: "once" });
  assert.equal(asks()[0][3], "granted");
  assert.equal(useAsk().scope, "once");
  assert.deepEqual([useAsk().reason, useAsk().howText], ["list PRs", "代理 · 限 api.github.com"], "the original request remains in the chat after approval");
  r.core.close();
  // A web page keeps no keys: approved elsewhere.
  const w = await rig(true, false, cardsInChat());
  w.putLock();
  const there = await w.watch(2, { topic: "chat", station: "ws/st", thread: 7 });
  assert.deepEqual(there().messages.filter((m: any) => m.card?.vaultAsk).map((m: any) => m.card.vaultAsk.answer), ["elsewhere", "elsewhere"]);
  w.core.close();
});

test("a_chat_with_vault_cards_opens_checking_no_signature_once_this_device_checked_them_the_app_started_anew", async () => {
  // The lock's entries and this device's certificate, checked as the first chat with vault cards opened after each
  // start: 0.87 s of it on a phone (2026-10-31). Checked once on this device, opening one checks none.
  const r = await rig(false, false, cardsInChat());
  r.putLock();
  await r.ask("vault.setup", {});
  const chat = await r.watch(2, { topic: "chat", station: "ws/st", thread: 7 });
  assert.equal(chat().messages.filter((m: any) => m.card?.vaultAsk).length, 2);
  await r.core.close();
  forgetVerifiedHere();
  const again = await Core.create(r.host, { clock: r.host.time.clock, sample: 0, wire: () => new HostWire(r.host) });
  try {
    await r.host.time.pass(1000, 100);
    r.host.takeEmitted();
    const before = verifies.count;
    subscribe(again, again.connect(), 2, { topic: "chat", station: "ws/st", thread: 7 });
    await r.host.time.pass(200, 10);
    const value = r.host.takeEmitted().map(([, m]) => m as any).find((m) => m.id === 2 && "value" in m)?.value;
    assert.deepEqual(value.messages.filter((m: any) => m.card?.vaultAsk).map((m: any) => m.card.vaultAsk.answer), ["approve", "approve"]);
    assert.equal(verifies.count - before, 0, "no signature checked");
  } finally {
    await again.close();
  }
});

test("the_lock_is_checked_as_it_comes_so_a_chat_with_vault_cards_opens_checking_none", async () => {
  // Checked as the first chat with vault cards opened, the whole chain once on a version's first run: 1.2 s of it on
  // a phone (0.1.6345, 2026-10-31). Read from the cloud, the lock is checked then, beside what waits.
  const r = await rig(false, false, cardsInChat());
  stationReplies(r.host, (req) => (req.url.includes("/v1/workspaces/ws/lock") ? r.lock : r.st.reply(req)));
  forgetVerifiedHere();
  const before = verifies.count;
  await r.core.inner.runner.run(readLock(r.core.inner, "ws"));
  await r.host.time.pass(100, 10);
  assert.ok(verifies.count > before, "checked as it came");
  const checked = verifies.count;
  const chat = await r.watch(2, { topic: "chat", station: "ws/st", thread: 7 });
  assert.equal(chat().messages.filter((m: any) => m.card?.vaultAsk).length, 2);
  assert.equal(verifies.count - checked, 0, "none as the chat opened");
  r.core.close();
});

test("vault calls: a secret an agent asks to keep, opened with this device's box key, written into a vault of one's own, then told", async () => {
  const r = await rig();
  r.putLock();
  await r.ask("vault.setup", {});
  const here = [...r.st.boxes.values()][0]!;
  const fields = { username: "demo-user", password: "pw-123" };
  const keeper = fill(9);
  const save = (rid: string, item: string, to: { device: string; box: string }): Request => ({
    id: rid, ws: "ws", vault: "", item, session: "k1", chat: "7", mode: "env", reason: "log in to the test service", box: boxPublic(keeper), at: 1, status: "pending", owner: "a@x.com",
    save: { kind: "login", name: "测试服务登录", modes: ["env"], hosts: [], env: "SERVICE_PASSWORD", username: "demo-user" },
    sealed: [{ device: to.device, box: to.box, secret: sealWith(to.box, utf8(JSON.stringify(fields)), saveContext("ws", rid), fill(6)) }],
  });
  const item = "i_01JAKEEP000000000000000AX7";
  r.st.requests.push(save("r_s", item, here));
  r.push("vault-request", save("r_s", item, here));
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual(vaults().requests.map((q: any) => [q.id, q.itemName, q.save]), [["r_s", "测试服务登录", { kind: "login", username: "demo-user" }]]);
  assert.equal(vaults().vaults.length, 1, "one's own, made as this device was set up");

  const asked = r.host.secureAsked.length;
  const kept = await r.ask("vault.approve", { request: "r_s", scope: "once" });
  assert.equal(r.host.secureAsked.length, asked + 1, "the person is asked once");
  const [made] = [...r.st.vaults.values()];
  assert.ok(made && kept.vault === made.id && made.owner === "s1");
  const written = r.st.items.get(item)!;
  assert.ok(signedOk(written, TAG.item));
  assert.deepEqual([written.vault, written.version, written.listing], [made.id, 0, { name: "测试服务登录", kind: "login", modes: ["env"], hosts: [], env: "SERVICE_PASSWORD" }]);
  assert.deepEqual((await r.ask("vault.open", { item })).plain.fields, fields);
  // With the grant that lets the asking chat use it: an hour's idle timeout, sealed to the request's box.
  const saved = r.st.saves[0] as any;
  assert.deepEqual([saved.request, saved.vault, saved.grant.scope, saved.grant.mode, saved.grant.item, saved.grant.timeout], ["r_s", made.id, "hour", "env", item, { kind: "idle", seconds: 3600 }]);
  assert.ok(signedOk(saved.grant, TAG.grant));
  assert.deepEqual(JSON.parse(new TextDecoder().decode(openSeal(keeper, saved.grant.secret, grantContext("ws", "r_s")))).fields, fields);
  assert.deepEqual(vaults().requests, []);

  // Into that vault next time; one sealed to another device is not this one's to open.
  const second = "i_01JAKEEP000000000000000TW2";
  r.st.requests.push(save("r_t", second, here));
  r.push("vault-request", save("r_t", second, here));
  await r.ask("vault.approve", { request: "r_t", scope: "once" });
  assert.equal(r.st.vaults.size, 1);
  assert.equal(r.st.items.get(second)!.vault, made.id);
  const elsewhere = save("r_u", "i_01JAKEEP000000000000000PHN", { device: r.phone.hex, box: boxPublic(fill(8)) });
  r.st.requests.push(elsewhere);
  r.push("vault-request", elsewhere);
  await fails(r.ask("vault.approve", { request: "r_u", scope: "once" }), "vault_no_key");
  r.core.close();
});

test("vault calls: an agent's request to rename an item: answered as one to keep, the item opened and written as its next version saying so (its listing too), then told; nothing granted", async () => {
  const r = await rig();
  r.putLock();
  await r.ask("vault.setup", {});
  const v = [...r.st.vaults.values()][0]!;
  const { id } = (await r.ask("vault.putItem", { vault: v.id, plain: { kind: "token", name: "127.0.0.1 登录态", fields: { value: "t-1" }, domains: [], notes: "" }, listing: { name: "127.0.0.1 登录态", kind: "token", modes: ["proxy"], hosts: ["127.0.0.1"] } })) as { id: string };
  const ask: Request = {
    id: "r_d", ws: "ws", vault: v.id, item: id, session: "k1", chat: "7", mode: "proxy", reason: "认不出来", box: "", at: 1, status: "pending",
    describe: { name: "UniFi 后台", about: "经 Studio 转发到 127.0.0.1:8443", was: { name: "127.0.0.1 登录态", about: "" } },
  };
  r.st.requests.push(ask);
  r.push("vault-request", ask);
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(500);
  r.take();
  const row = vaults().requests[0];
  assert.deepEqual([row.itemName, row.describe, row.howText], ["127.0.0.1 登录态", { name: "UniFi 后台", about: "经 Studio 转发到 127.0.0.1:8443", wasAbout: "" }, "名称改为：UniFi 后台\n说明改为：经 Studio 转发到 127.0.0.1:8443"]);
  await r.ask("vault.approve", { request: "r_d", scope: "once" });
  const written = r.st.items.get(id)!;
  assert.ok(signedOk(written, TAG.item));
  assert.deepEqual([written.version, written.listing], [1, { name: "UniFi 后台", kind: "token", modes: ["proxy"], hosts: ["127.0.0.1"], about: "经 Studio 转发到 127.0.0.1:8443" }]);
  const opened = (await r.ask("vault.open", { item: id })).plain;
  assert.deepEqual([opened.name, opened.notes, opened.fields], ["UniFi 后台", "经 Studio 转发到 127.0.0.1:8443", { value: "t-1" }]);
  assert.deepEqual(r.st.described, [{ request: "r_d" }]);
  assert.deepEqual(r.st.grants, [], "it grants nothing");
  r.core.close();
});

test("vault calls: a secret an agent asks the person to type in: what they typed written into their vault (nothing to open), the chat given it; nothing typed, nothing kept", async () => {
  const r = await rig();
  r.putLock();
  await r.ask("vault.setup", {});
  const keeper = fill(9);
  const typed = (rid: string, item: string, save: Request["save"]): Request => ({
    id: rid, ws: "ws", vault: "", item, session: "k1", chat: "7", mode: "proxy", reason: "在 OpenCode 控制台新建一个", hosts: ["opencode.ai"], box: boxPublic(keeper), at: 1, status: "pending", owner: "a@x.com", save,
  });
  const item = "i_01JAKEEP00000000000000TYPE";
  const asked = typed("r_y", item, { kind: "token", name: "OpenCode Go", modes: ["proxy"], hosts: ["opencode.ai"], typed: true });
  r.st.requests.push(asked);
  r.push("vault-request", asked);
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual(vaults().requests.map((q: any) => [q.id, q.save]), [["r_y", { kind: "token", typed: true }]]);

  // Nothing typed (or only spaces): refused before the person is asked.
  const before = r.host.secureAsked.length;
  await fails(r.ask("vault.approve", { request: "r_y", scope: "once" }), "vault_typed_empty");
  await fails(r.ask("vault.approve", { request: "r_y", scope: "once", typed: { secret: "  " } }), "vault_typed_empty");
  assert.equal(r.host.secureAsked.length, before);
  const kept = await r.ask("vault.approve", { request: "r_y", scope: "once", typed: { secret: " sk-go-1\n" } });
  assert.equal(r.host.secureAsked.length, before + 1, "the person is asked once");
  const [own] = [...r.st.vaults.values()];
  assert.ok(own && kept.vault === own.id);
  assert.deepEqual([r.st.items.get(item)!.vault, r.st.items.get(item)!.listing], [own.id, { name: "OpenCode Go", kind: "token", modes: ["proxy"], hosts: ["opencode.ai"] }]);
  assert.deepEqual((await r.ask("vault.open", { item })).plain.fields, { value: "sk-go-1" });
  const saved = r.st.saves[0] as any;
  assert.deepEqual([saved.request, saved.grant.mode, saved.grant.hosts], ["r_y", "proxy", ["opencode.ai"]]);
  assert.deepEqual(JSON.parse(new TextDecoder().decode(openSeal(keeper, saved.grant.secret, grantContext("ws", "r_y")))).fields, { value: "sk-go-1" });

  // A login with no account given: the one typed in with the password, as typed.
  const login = "i_01JAKEEP00000000000001060N";
  const asksLogin = typed("r_z", login, { kind: "login", name: "Router", modes: ["env"], hosts: [], typed: true });
  r.st.requests.push(asksLogin);
  r.push("vault-request", asksLogin);
  await r.ask("vault.approve", { request: "r_z", scope: "once", typed: { secret: " pw ", username: " admin " } });
  assert.deepEqual((await r.ask("vault.open", { item: login })).plain.fields, { username: "admin", password: " pw " });
  r.core.close();
});

test("one vault of one's own: a device set up later makes none, and is given its key as soon as one of the owner's devices has it in hand: at once, or as it next unseals it; till then it waits on that device, which it may ask again", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  const prompts = await r.watch(2, { topic: "lockPrompts" });
  assert.deepEqual(prompts(), { pairing: [], asks: [] });
  // The phone sets itself up: its certificate comes as the station tells it, and the key, unsealed here since the
  // vault was made, is given to it at once (2026-11-03: it waited for the person to unseal the key for something
  // else), the person asked nothing.
  const phoneBox = fill(7);
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(phoneBox), at: 2000 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneCert);
  const asked = r.host.secureAsked.length;
  r.push("vault-box", phoneCert);
  await r.host.time.pass(500);
  r.take();
  assert.equal(r.host.secureAsked.length, asked);
  const v1 = r.st.vaults.get(id)!;
  assert.ok(signedOk(v1, TAG.vault));
  assert.equal(v1.seq, 1);
  const phoneKey = v1.keys.find((k) => k.cert.device === r.phone.hex)!;
  assert.equal(openSeal(phoneBox, phoneKey.wrapped, keyContext("ws", id, 0)).length, 32);
  // (the certificate carried as the phone signed it: a station checks its signature, which a field more breaks)
  assert.deepEqual(phoneKey.cert, phoneCert);
  assert.ok(v1.keys.every((k) => signedOk(k.cert, TAG.box)));
  assert.equal(vaults().vaults[0].missing, 0);
  // The phone's certificate published anew under the same key (`vault.ask`): nothing to change, no version written.
  const { sig: _p, ...phoneRest } = phoneCert;
  const phoneAgain = sign({ ...phoneRest, at: 2050 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneAgain);
  r.push("vault-box", phoneAgain);
  await r.host.time.pass(500);
  r.take();
  assert.equal(r.st.vaults.get(id)!.seq, 1, "the same key: no version written for it");
  // The phone installed again, its box key kept and its signing key new (back in the lock under it): its fresh
  // certificate takes the old one's place in the vault's keys, the key wrapped as it was (a station checks each
  // certificate of a version against the lock).
  const phone2 = key(fill(12));
  grow(r, "device", { id: r.phone.hex, sub: "s1", kind: "app", label: "phone again", sign_key: phone2.id });
  const phoneCert2 = sign({ ...phoneRest, at: 2060 }, TAG.box, phone2);
  r.st.boxes.set(r.phone.hex, phoneCert2);
  r.push("vault-box", phoneCert2);
  await r.host.time.pass(500);
  r.take();
  const v2 = r.st.vaults.get(id)!;
  assert.equal(v2.seq, 2);
  assert.deepEqual(v2.keys.find((k) => k.cert.device === r.phone.hex), { cert: phoneCert2, wrapped: phoneKey.wrapped });
  assert.equal(r.host.secureAsked.length, asked);
  // The key locked away here; this person's other device set up: not given (no key in hand to give), and waiting on
  // this device, wherever the person is (`lockPrompts` `asks`); the station fixture's phone is the owner's second device,
  // `other` another member's (no member of this vault: it waits for nothing).
  await r.ask("vault.lock", {});
  const otherCert = sign({ v: 1 as const, ws: "ws", device: r.other.hex, box: boxPublic(fill(8)), at: 2100 }, TAG.box, r.other);
  r.st.boxes.set(r.other.hex, otherCert);
  r.push("vault-box", otherCert);
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual([vaults().vaults[0].missing, r.st.vaults.get(id)!.seq, prompts().asks.length], [0, 2, 0], "another member's device: no key of this vault for it");
  // The phone installed anew with a new box key: no key, waiting on this device.
  const phoneBox3 = fill(9);
  const phoneCert3 = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(phoneBox3), at: 2200 }, TAG.box, phone2);
  r.st.boxes.set(r.phone.hex, phoneCert3);
  r.push("vault-box", phoneCert3);
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual([vaults().vaults[0].missing, r.st.vaults.get(id)!.seq], [1, 2]);
  assert.equal(prompts().asks.length, 1);
  const ask = prompts().asks[0];
  assert.deepEqual([ask.workspace, ask.vault, ask.device, ask.deviceText, ask.at], ["ws", id, r.phone.hex, "phone again", 2200]);
  // Put away (the one shown, by its date): shown no more, till the phone asks again (its certificate published anew,
  // dated later).
  await r.ask("vault.hidePrompt", { device: r.phone.hex, at: ask.at });
  assert.equal(prompts().asks.length, 0);
  const { sig: _q, ...phoneRest3 } = phoneCert3;
  const phoneCert4 = sign({ ...phoneRest3, at: 2300 }, TAG.box, phone2);
  r.st.boxes.set(r.phone.hex, phoneCert4);
  r.push("vault-box", phoneCert4);
  await r.host.time.pass(500);
  r.take();
  assert.equal(prompts().asks.length, 1);
  // Given from the prompt (`vault.addDevice {vault, device}`): the key unsealed here (the person asked once), sealed
  // to it; the prompt gone.
  assert.deepEqual(await r.ask("vault.addDevice", { vault: id, device: r.phone.hex }), { added: 1 });
  assert.equal(r.host.secureAsked.length, asked + 1);
  const v3 = r.st.vaults.get(id)!;
  assert.equal(v3.seq, 3);
  assert.equal(openSeal(phoneBox3, v3.keys.find((k) => k.cert.device === r.phone.hex)!.wrapped, keyContext("ws", id, 0)).length, 32);
  assert.deepEqual([vaults().vaults[0].missing, prompts().asks.length], [0, 0]);

  // This device installed anew: set up again, no key to the vault and no second one made; a secret to keep approved
  // here is refused (before the person is asked) till a device that has the key gives it.
  r.host.secure.delete(BOX_KEY);
  r.host.storage.delete(BOX_PUB);
  await r.ask("vault.lock", {});
  const again = await r.ask("vault.setup", {});
  assert.deepEqual([again.made, r.st.vaults.size], [null, 1]);
  // Asking for the key (`vault.ask`): this device's certificate published anew, dated later, so that the owner's
  // devices hearing of it give the key or prompt for it again.
  const at = r.st.boxes.get("ab".repeat(32))!.at;
  assert.deepEqual(await r.ask("vault.ask", {}), { asked: 1 });
  assert.ok(r.st.boxes.get("ab".repeat(32))!.at > at);
  const box = r.st.boxes.get("ab".repeat(32))!.box;
  const rid = "r_k";
  const save: Request = {
    id: rid, ws: "ws", vault: "", item: "i_01JAKEEP000000000000000NEW", session: "k1", chat: "7", mode: "env", reason: "keep it", box: boxPublic(fill(9)), at: 1, status: "pending", owner: "a@x.com",
    save: { kind: "token", name: "Axiom", modes: ["env"], hosts: [] },
    sealed: [{ device: "ab".repeat(32), box, secret: sealWith(box, utf8(JSON.stringify({ value: "xaat" })), saveContext("ws", rid), fill(6)) }],
  };
  r.st.requests.push(save);
  r.push("vault-request", save);
  // One its station sealed to the phone alone (this device not set up there then): said on its row, approved elsewhere.
  const elsewhere: Request = { ...save, id: "r_e", item: "i_01JAKEEP000000000000000E15", sealed: [{ device: r.phone.hex, box: boxPublic(phoneBox3), secret: "x" }] };
  r.st.requests.push(elsewhere);
  r.push("vault-request", elsewhere);
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual(vaults().requests.map((x: any) => [x.id, x.notHere]).sort((a: [string], b: [string]) => (a[0] < b[0] ? -1 : 1)), [["r_e", true], [rid, undefined]]);
  const before = r.host.secureAsked.length;
  await fails(r.ask("vault.approve", { request: rid, scope: "once" }), "vault_no_key");
  assert.deepEqual([r.host.secureAsked.length, r.st.vaults.size, r.st.items.has(save.item)], [before, 1, false]);
  r.core.close();
});

test("a device taken out of the lock that held a vault's key: the owner's device keys the vault anew without it, every item written again under the new key; the vault and its items shown and opened as before", async () => {
  const r = await rig();
  r.putLock();
  const { made: id, words } = await r.ask("vault.setup", {});
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } }, listing: { name: "gh", kind: "token", modes: ["proxy"], hosts: ["api.github.com"] } });
  // The phone set up and given the key (as the vault was unsealed here): its version is the one the stations hold.
  const phoneBox = fill(7);
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(phoneBox), at: 2000 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneCert);
  r.push("vault-box", phoneCert);
  await r.host.time.pass(500);
  r.take();
  const keyed = r.st.vaults.get(id)!;
  assert.deepEqual([keyed.seq, keyed.epoch, keyed.keys.some((k) => k.cert.device === r.phone.hex)], [1, 0, true]);
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  // The phone taken out of the lock, the lock read as the cloud tells of it.
  stationReplies(r.host, (req) => (req.url.includes("/v1/workspaces/ws/lock") ? r.lock : r.st.reply(req)));
  grow(r, "device.remove", { id: r.phone.hex });
  const asked = r.host.secureAsked.length;
  await r.core.inner.runner.run(readLock(r.core.inner, "ws"));
  await r.host.time.pass(500, 10);
  r.take();
  const v = r.st.vaults.get(id)!;
  assert.deepEqual([v.seq, v.epoch, v.keys.map((k) => k.cert.device)], [2, 1, ["ab".repeat(32)]], "a new epoch, sealed to this device alone");
  assert.equal(rules.vault_ok_js(checkLock(r.lock.entries, 4000), keyed, v, false, rulesCrypto), null, "as the stations take it");
  assert.equal(r.host.secureAsked.length, asked, "the key unsealed here: the person not asked");
  const fresh = openSeal(recoveryPair(fromWords(words)).priv, v.recovery!, keyContext("ws", id, 1));
  const item = r.st.items.get(put.id)!;
  assert.deepEqual([item.version, item.epoch], [1, 1]);
  assert.equal(JSON.parse(new TextDecoder().decode(decrypt(fresh, item.ct, itemContext("ws", id, item.id, 1, 1)))).fields.value, "ghp_x", "written again under the new key");
  assert.equal(vaults().vaults.length, 1, "shown still");
  assert.equal((await r.ask("vault.open", { item: put.id })).plain.fields.value, "ghp_x");
  r.core.close();
});

// A keying anew stopped half-way: the vault's next version written under a new key, an item not written again under
// it (the device closed or cut off, or the station refused that write). Nothing wrote it again, and it could not be
// opened anywhere: its key was forgotten here, and the version sealing it for this device let go.

/// The rig's own vault, one item in it, the phone given its key and then taken out of the lock: keyed anew by this
/// device, the station refusing the item's write under the new key once (`also`: what else is put in the vault
/// first). The item left under the earlier key, as the station and this device hold it.
async function keyedAnewHalfWay(r: Awaited<ReturnType<typeof rig>>, also?: (id: string) => Promise<void>) {
  r.putLock();
  const { made: id, words } = await r.ask("vault.setup", {});
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } }, listing: { name: "gh", kind: "token", modes: ["proxy"], hosts: ["api.github.com"] } });
  await also?.(id);
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(fill(7)), at: 2000 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneCert);
  r.push("vault-box", phoneCert);
  await r.host.time.pass(500);
  r.take();
  assert.equal(r.st.vaults.get(id)!.seq, 1, "the phone given the key");
  const refuse = { left: 1 };
  stationReplies(r.host, (req) => {
    if (req.url.includes("/v1/workspaces/ws/lock")) return r.lock;
    if (refuse.left > 0 && req.method === "PUT" && req.url.endsWith("/vault/items")) {
      refuse.left--;
      return status(500, { error: "the link went down" });
    }
    return r.st.reply(req);
  });
  grow(r, "device.remove", { id: r.phone.hex });
  await r.core.inner.runner.run(readLock(r.core.inner, "ws"));
  await r.host.time.pass(500, 10);
  r.take();
  assert.equal(refuse.left, 0, "the item's write refused");
  const v = r.st.vaults.get(id)!;
  assert.deepEqual([v.seq, v.epoch], [2, 1], "keyed anew");
  const i = r.st.items.get(put.id)!;
  assert.deepEqual([i.version, i.epoch], [0, 0], "the item left under the earlier key");
  const fresh = openSeal(recoveryPair(fromWords(words)).priv, v.recovery!, keyContext("ws", id, 1));
  return { id, item: put.id, fresh };
}

/// The vault's record as this device holds it.
const heldVault = (r: Awaited<ReturnType<typeof rig>>) => r.core.inner.data.record("vault", "ws") as { before?: Record<string, Record<string, Vault>> };

/// That the station holds `item` written again under the vault's new key (`fresh`, epoch 1) at its next version,
/// signed by this device, its secret as it was.
function carriedOn(r: Awaited<ReturnType<typeof rig>>, id: string, item: string, fresh: Uint8Array, value: string) {
  const i = r.st.items.get(item)!;
  assert.deepEqual([i.version, i.epoch], [1, 1], "written again under the new key, its next version");
  assert.equal(i.sig.key, r.me.signer!.id);
  assert.equal(JSON.parse(new TextDecoder().decode(decrypt(fresh, i.ct, itemContext("ws", id, item, 1, 1)))).fields.value, value);
}

test("a keying anew stopped half-way (an item's write under the new key refused): the item is carried on as it is opened, with the keys still unsealed here", async () => {
  const r = await rig();
  const { id, item, fresh } = await keyedAnewHalfWay(r);
  const asked = r.host.secureAsked.length;
  assert.equal((await r.ask("vault.open", { item })).plain.fields.value, "ghp_x");
  assert.equal(r.host.secureAsked.length, asked, "the keys unsealed here: the person not asked");
  carriedOn(r, id, item, fresh, "ghp_x");
  r.core.close();
});

test("a keying anew stopped half-way, the app started anew since (no key unsealed): opening the item asks for the box key once, carries it on and opens it", async () => {
  const r = await rig();
  const { id, item, fresh } = await keyedAnewHalfWay(r);
  await r.restart();
  await r.host.time.pass(500);
  assert.deepEqual([r.st.items.get(item)!.version, r.st.items.get(item)!.epoch], [0, 0], "nothing carried on with nobody asked: no key unsealed");
  const asked = r.host.secureAsked.length;
  assert.equal((await r.ask("vault.open", { item })).plain.fields.value, "ghp_x");
  assert.deepEqual(r.host.secureAsked.slice(asked).map((a) => a.key), [BOX_KEY], "asked once");
  carriedOn(r, id, item, fresh, "ghp_x");
  r.core.close();
});

test("a member's device that did not key the vault anew (told the new version while an item is still under the earlier key) carries it on as it opens it", async () => {
  const r = await rig();
  r.putLock();
  await r.ask("vault.setup", {});
  const mine = r.st.boxes.get("ab".repeat(32))!;
  const otherCert = sign({ v: 1 as const, ws: "ws", device: r.other.hex, box: boxPublic(fill(9)), at: 2000 }, TAG.box, r.other);
  r.st.boxes.set(r.other.hex, otherCert);
  r.push("vault-box", otherCert);
  // s2's vault, this person in it, keyed for this device; an item s2's device wrote in it.
  const id = "v_01M4871X3MTC0903ZX5CPB8JH9";
  const [k0, k1] = [fill(11), fill(21)];
  const seal = (c: BoxCert, key: Uint8Array, epoch: number, n: number) => ({ cert: c, wrapped: sealWith(c.box, key, keyContext("ws", id, epoch), fill(n)) });
  const v0 = sign({ v: 1 as const, ws: "ws", id, seq: 0, owner: "s2", name: "Team", members: ["s2", "s1"], epoch: 0, keys: [seal(otherCert, k0, 0, 12), seal(mine, k0, 0, 13)], at: 2000 }, TAG.vault, r.other);
  r.st.vaults.set(id, v0);
  r.push("vault", v0);
  await r.host.time.pass(200);
  const itemId = "i_01JAKEEP000000000000000C4R";
  const plain = { kind: "token", name: "Deploy", fields: { value: "dk_1" }, domains: [], notes: "" };
  const i0 = sign({ v: 1 as const, ws: "ws", vault: id, id: itemId, version: 0, epoch: 0, ct: encryptWith(k0, utf8(JSON.stringify(plain)), itemContext("ws", id, itemId, 0, 0), fill(1, 12)), at: 2000 }, TAG.item, r.other);
  r.st.items.set(itemId, i0);
  r.push("vault-item", i0);
  await r.host.time.pass(200);
  // s2's device keys it anew and stops before writing the item again.
  const v1 = sign({ v: 1 as const, ws: "ws", id, seq: 1, owner: "s2", name: "Team", members: ["s2", "s1"], epoch: 1, keys: [seal(otherCert, k1, 1, 14), seal(mine, k1, 1, 15)], at: 2001 }, TAG.vault, r.other);
  r.st.vaults.set(id, v1);
  r.push("vault", v1);
  await r.host.time.pass(200);
  const asked = r.host.secureAsked.length;
  assert.equal((await r.ask("vault.open", { item: itemId })).plain.fields.value, "dk_1");
  assert.deepEqual(r.host.secureAsked.slice(asked).map((a) => a.key), [BOX_KEY], "asked once");
  carriedOn(r, id, itemId, k1, "dk_1");
  r.core.close();
});

test("an item under the earlier key that the lock did not take then (made up by a station, signed by someone not in the vault) is not carried on: still refused, nothing written", async () => {
  const r = await rig();
  const forgedId = "i_01JAKEEP000000000000000F0G";
  const { id, item, fresh } = await keyedAnewHalfWay(r, async (id) => {
    const plain = { kind: "token", name: "x", fields: { value: "planted" }, domains: [], notes: "" };
    const forged = sign({ v: 1 as const, ws: "ws", vault: id, id: forgedId, version: 0, epoch: 0, ct: encryptWith(fill(5), utf8(JSON.stringify(plain)), itemContext("ws", id, forgedId, 0, 0), fill(2, 12)), at: 2000 }, TAG.item, r.other);
    r.st.items.set(forgedId, forged);
    r.push("vault-item", forged);
    await r.host.time.pass(200);
  });
  const forged = r.st.items.get(forgedId)!;
  await fails(r.ask("vault.open", { item: forgedId }), "vault_untrusted");
  assert.equal(r.st.items.get(forgedId), forged, "not written again");
  // (the item its owner's device wrote, carried on as the vault was looked at)
  carriedOn(r, id, item, fresh, "ghp_x");
  assert.equal((await r.ask("vault.open", { item })).plain.fields.value, "ghp_x");
  r.core.close();
});

test("the version kept of an earlier key is let go once the vault's items, read of its station again, show nothing under that key", async () => {
  const r = await rig();
  const { id, item } = await keyedAnewHalfWay(r);
  const kept = heldVault(r).before?.[id]?.["0"];
  assert.deepEqual([kept?.seq, kept?.epoch], [1, 0], "the last version of the earlier key kept, its item under it");
  await r.ask("vault.open", { item });
  // (not as it is carried on: an item another device wrote under that key meanwhile may be told only after)
  assert.equal(heldVault(r).before?.[id]?.["0"]?.seq, 1, "kept until the station is read again");
  r.core.inner.stations.snapshot("ws/st");
  await r.host.time.pass(500, 10);
  assert.equal(heldVault(r).before?.[id], undefined, "let go: nothing under it any more");
  r.core.close();
});

test("a keying anew stopped half-way: the station read again (its connection opened) while the keys are unsealed here carries the item on, nobody asked", async () => {
  const r = await rig();
  const { id, item, fresh } = await keyedAnewHalfWay(r);
  const asked = r.host.secureAsked.length;
  r.core.inner.stations.snapshot("ws/st");
  await r.host.time.pass(500, 10);
  assert.equal(r.host.secureAsked.length, asked, "nobody asked");
  carriedOn(r, id, item, fresh, "ghp_x");
  r.core.close();
});

test("a device taken out of the lock and put back in as the vault is keyed anew without it: given the new key", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const phoneBox = fill(7);
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(phoneBox), at: 2000 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneCert);
  r.push("vault-box", phoneCert);
  await r.host.time.pass(500);
  r.take();
  stationReplies(r.host, (req) => (req.url.includes("/v1/workspaces/ws/lock") ? r.lock : r.st.reply(req)));
  // The version keyed anew taken by the station only once let go: the phone back in the lock meanwhile, its
  // certificate published anew (as a device let in again does: vault.ask).
  const gate: { letGo: (() => void) | null } = { letGo: null };
  stationLater(r.host, (req) => {
    if (gate.letGo !== null || req.method !== "PUT" || !req.url.includes("/vault/vaults")) return undefined;
    const body = JSON.parse(new TextDecoder().decode(req.body ?? new Uint8Array()));
    if (body.epoch !== 1) return undefined;
    return new Promise((resolve) => (gate.letGo = () => resolve(jsonResponse(200, r.st.reply(req)))));
  });
  grow(r, "device.remove", { id: r.phone.hex });
  r.core.inner.runner.fork(readLock(r.core.inner, "ws"));
  await r.host.time.pass(200, 10);
  assert.ok(gate.letGo !== null, "keyed anew without the phone");
  grow(r, "device", { id: r.phone.hex, sub: "s1", kind: "app", label: "phone", sign_key: r.phone.id });
  r.core.inner.runner.fork(readLock(r.core.inner, "ws"));
  const again = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(phoneBox), at: 5000 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, again);
  r.push("vault-box", again);
  await r.host.time.pass(200, 10);
  gate.letGo!();
  stationLater(r.host, () => undefined);
  await r.host.time.pass(2000, 10);
  r.take();
  const v = r.st.vaults.get(id)!;
  assert.equal(v.epoch, 1, "keyed anew");
  assert.ok(v.keys.some((k) => k.cert.device === r.phone.hex), `the phone given the new key: ${JSON.stringify(v.keys.map((k) => k.cert.device.slice(0, 4)))} seq ${v.seq}`);
  r.core.close();
});

test("a version keyed for this device told before the lock that lets it in again: taken as that lock comes", async () => {
  // A device taken out of the lock and let in again: the owner's device gave it the key in a version the station told
  // it before this device had read the lock with itself in it, and that version, not taken by the lock then, was let
  // go; nothing told it again, and the device went without the key until it was started anew (the locks' end to end,
  // round 3, 2026-11-10).
  const r = await rig();
  r.putLock();
  await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  const mine = r.st.boxes.get("ab".repeat(32))!;
  const otherBox = fill(9);
  const otherCert = sign({ v: 1 as const, ws: "ws", device: r.other.hex, box: boxPublic(otherBox), at: 2000 }, TAG.box, r.other);
  r.st.boxes.set(r.other.hex, otherCert);
  r.push("vault-box", otherCert);
  // s2's vault, this person in it, keyed for s2's device alone so far.
  const id = "v_01M4871X3MTC0903ZX5CPB8JH8";
  const key = fill(11);
  const seal = (c: typeof mine, n: number) => ({ cert: c, wrapped: sealWith(c.box, key, keyContext("ws", id, 0), fill(n)) });
  const v0 = sign({ v: 1 as const, ws: "ws", id, seq: 0, owner: "s2", name: "Team", members: ["s2", "s1"], epoch: 0, keys: [seal(otherCert, 12)], at: 2000 }, TAG.vault, r.other);
  r.st.vaults.set(id, v0);
  r.push("vault", v0);
  await r.host.time.pass(200);
  const team = () => vaults().vaults.find((v: any) => v.id === id);
  assert.equal(team()?.keyed, false);
  // This device taken out of the lock (by the phone, the person's other device), as it is here.
  stationReplies(r.host, (req) => (req.url.includes("/v1/workspaces/ws/lock") ? r.lock : r.st.reply(req)));
  grow(r, "device.remove", { id: "ab".repeat(32) }, r.phone);
  await r.core.inner.runner.run(readLock(r.core.inner, "ws"));
  await r.host.time.pass(200);
  // Let in again: the version keyed for it told first, then the lock with it in it.
  const v1 = sign({ v: 1 as const, ws: "ws", id, seq: 1, owner: "s2", name: "Team", members: ["s2", "s1"], epoch: 0, keys: [seal(otherCert, 12), seal(mine, 13)], at: 2001 }, TAG.vault, r.other);
  r.st.vaults.set(id, v1);
  r.push("vault", v1);
  await r.host.time.pass(200);
  grow(r, "device", { id: "ab".repeat(32), sub: "s1", kind: "app", label: "this", sign_key: r.me.signer!.id }, r.phone);
  await r.core.inner.runner.run(readLock(r.core.inner, "ws"));
  await r.host.time.pass(500, 10);
  assert.equal(team()?.keyed, true, `keyed for this device: ${JSON.stringify(team())}`);
  r.core.close();
});

// A vault waiting to be keyed anew (views/vault.ts `waitingAs`). The owner's decision, 2026-11-10: with the vault's
// station off, a device taken out left the vault gone for everyone (「条目不存在」) until that station was back; the
// devices left now read it meanwhile, and change nothing in it.

/// Vault `id` of `owner`'s (s2, the rig's `other`, by default), this person in it, keyed under `vaultKey` for each of
/// `certs`, and an item of it whose value is `value`, both signed by `by` (s2's device by default); told by the station.
function teamVault(r: Awaited<ReturnType<typeof rig>>, id: string, vaultKey: Uint8Array, certs: BoxCert[], value: string, by: ReturnType<typeof key> = r.other, owner = "s2") {
  const v = sign({ v: 1 as const, ws: "ws", id, seq: 0, owner, name: "Team", members: owner === "s2" ? ["s2", "s1"] : [owner], epoch: 0, keys: certs.map((c, n) => ({ cert: c, wrapped: sealWith(c.box, vaultKey, keyContext("ws", id, 0), fill(30 + n)) })), at: 2000 }, TAG.vault, by);
  const itemId = `i_${id.slice(3)}K`;
  const plain = { kind: "token", name: "Deploy", fields: { value }, domains: [], notes: "" };
  const item = sign({ v: 1 as const, ws: "ws", vault: id, id: itemId, version: 0, epoch: 0, ct: encryptWith(vaultKey, utf8(JSON.stringify(plain)), itemContext("ws", id, itemId, 0, 0), fill(5, 12)), at: 2000 }, TAG.item, by);
  r.st.vaults.set(id, v);
  r.st.items.set(itemId, item);
  r.push("vault", v);
  return { v, item };
}

test("a device taken out while the vault's station takes no write: the devices left list the vault and open its items, change nothing in it and are told the station it waits for; the station back, it is keyed anew and written on", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } }, listing: { name: "gh", kind: "token", modes: ["proxy"], hosts: ["api.github.com"] } });
  // The phone set up and given the key of this person's own vault (unsealed here).
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(fill(7)), at: 2000 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneCert);
  r.push("vault-box", phoneCert);
  await r.host.time.pass(500);
  r.take();
  assert.ok(r.st.vaults.get(id)!.keys.some((k) => k.cert.device === r.phone.hex));
  // s2's vault, this person a member: keyed for s2's device, this one and the phone.
  const mine = r.st.boxes.get("ab".repeat(32))!;
  const otherCert = sign({ v: 1 as const, ws: "ws", device: r.other.hex, box: boxPublic(fill(9)), at: 2000 }, TAG.box, r.other);
  const team = "v_01M4871X3MTC0903ZX5CPB8JH9";
  const { item: teamItem } = teamVault(r, team, fill(11), [otherCert, mine, phoneCert], "dep_1");
  await r.host.time.pass(500);
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  const listed = () => vaults().vaults.map((v: any) => v.id).sort();
  assert.deepEqual(listed(), [id, team].sort());
  // The vault's station takes no write (its machine asleep): what is put there waits for it.
  const waiting: (() => void)[] = [];
  const frozen = { on: true };
  stationLater(r.host, (req) => (frozen.on && req.method === "PUT" && req.url.includes("/vault/") ? new Promise((resolve) => waiting.push(() => resolve(jsonResponse(200, r.st.reply(req))))) : undefined));
  // The phone taken out of the lock, the lock read as the cloud tells of it.
  stationReplies(r.host, (req) => (req.url.includes("/v1/workspaces/ws/lock") ? r.lock : r.st.reply(req)));
  grow(r, "device.remove", { id: r.phone.hex });
  await r.core.inner.runner.run(readLock(r.core.inner, "ws"));
  await r.host.time.pass(500, 10);
  r.take();
  assert.ok(waiting.length >= 1, "the owner's device keys its vault anew, the station not taking it yet");
  assert.deepEqual([r.st.vaults.get(id)!.epoch, r.st.vaults.get(team)!.seq], [0, 0]);
  // Both read meanwhile: the owner's own and s2's, of which this person is a member.
  assert.deepEqual(listed(), [id, team].sort(), "listed still");
  // Each row says it waits, and on which station.
  const waits = (v: string) => vaults().vaults.find((row: any) => row.id === v)?.waits;
  assert.deepEqual([waits(id), waits(team)], ["studio", "studio"]);
  assert.equal((await r.ask("vault.open", { item: put.id })).plain.fields.value, "ghp_x");
  assert.equal((await r.ask("vault.open", { item: teamItem.id })).plain.fields.value, "dep_1");
  const shown = await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: team });
  assert.deepEqual(shown().items.map((i: any) => i.id), [teamItem.id]);
  // Nothing changed in either, the station it waits for named.
  const items = r.st.items.size;
  for (const [v, name] of [[id, t("core-misc.vault.personal")], [team, "Team"]] as const) {
    await assert.rejects(r.ask("vault.putItem", { vault: v, plain: { kind: "token", name: "new", fields: { value: "n" } } }), (e: Error & { code?: string }) => {
      assert.equal(e.code, "vault_waiting", e.message);
      assert.equal(e.message, t("core-misc.vault.waiting", { name, station: "studio" }));
      return true;
    });
  }
  await fails(r.ask("vault.deleteItem", { vault: team, item: teamItem.id }), "vault_waiting");
  await fails(r.ask("vault.setLasts", { vault: id, lasts: "once" }), "vault_waiting");
  await fails(r.ask("vault.delete", { vault: id }), "vault_waiting");
  assert.equal(r.st.items.size, items, "nothing written");

  // The station takes writes again: the owner's vault keyed anew (the next epoch, the phone holding no key), shown,
  // its item opened under the new key, and written on.
  frozen.on = false;
  for (const go of waiting.splice(0)) go();
  await r.host.time.pass(1000, 10);
  r.take();
  const v = r.st.vaults.get(id)!;
  assert.deepEqual([v.epoch, v.keys.map((k) => k.cert.device)], [1, ["ab".repeat(32)]]);
  assert.equal(r.st.items.get(put.id)!.epoch, 1);
  assert.ok(listed().includes(id));
  assert.ok(!("waits" in vaults().vaults.find((row: any) => row.id === id)), "keyed anew, it waits no more");
  assert.equal(waits(team), "studio", "s2's waits on");
  assert.equal((await r.ask("vault.open", { item: put.id })).plain.fields.value, "ghp_x");
  const added = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "new", fields: { value: "n" } } });
  assert.equal(r.st.items.get(added.id)!.epoch, 1);
  // s2's waits on: its owner's device, not here, keys it anew.
  await fails(r.ask("vault.putItem", { vault: team, plain: { kind: "token", name: "new", fields: { value: "n" } } }), "vault_waiting");
  assert.equal((await r.ask("vault.open", { item: teamItem.id })).plain.fields.value, "dep_1");
  r.core.close();
});

test("the device taken out reads nothing of a vault waiting to be keyed anew without it", async () => {
  const r = await rig();
  r.putLock();
  await r.ask("vault.setup", {});
  const mine = r.st.boxes.get("ab".repeat(32))!;
  const otherCert = sign({ v: 1 as const, ws: "ws", device: r.other.hex, box: boxPublic(fill(9)), at: 2000 }, TAG.box, r.other);
  const team = "v_01M4871X3MTC0903ZX5CPB8JHA";
  const { item } = teamVault(r, team, fill(11), [otherCert, mine], "dep_1");
  await r.host.time.pass(500);
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  assert.ok(vaults().vaults.some((v: any) => v.id === team));
  // This device taken out of the lock (by the phone, the person's other device), as it is here.
  stationReplies(r.host, (req) => (req.url.includes("/v1/workspaces/ws/lock") ? r.lock : r.st.reply(req)));
  grow(r, "device.remove", { id: "ab".repeat(32) }, r.phone);
  await r.core.inner.runner.run(readLock(r.core.inner, "ws"));
  await r.host.time.pass(500, 10);
  r.take();
  assert.deepEqual(vaults().vaults, [], "none listed");
  const shown = await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: team });
  assert.deepEqual(shown().items, []);
  await fails(r.ask("vault.open", { item: item.id }), "vault_not_signer");
  r.core.close();
});

test("a vault version no lock ever took (signed by a device never in it) is not read as waiting to be keyed anew: not listed, not opened", async () => {
  const r = await rig();
  r.putLock();
  await r.ask("vault.setup", {});
  const mine = r.st.boxes.get("ab".repeat(32))!;
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(fill(7)), at: 2000 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneCert);
  r.push("vault-box", phoneCert);
  // This person's own, keyed for this device and the phone, signed by a key the lock never named.
  const odd = "v_01M4871X3MTC0903ZX5CPB8JHB";
  const { item } = teamVault(r, odd, fill(11), [mine, phoneCert], "odd_1", key(fill(20)), "s1");
  await r.host.time.pass(500);
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  assert.ok(!vaults().vaults.some((v: any) => v.id === odd));
  // The phone taken out: a key of it for a device no longer in the lock, as one waiting would hold.
  stationReplies(r.host, (req) => (req.url.includes("/v1/workspaces/ws/lock") ? r.lock : r.st.reply(req)));
  grow(r, "device.remove", { id: r.phone.hex });
  await r.core.inner.runner.run(readLock(r.core.inner, "ws"));
  await r.host.time.pass(500, 10);
  r.take();
  const heldOdd = (r.core.inner.data.record("vault", "ws") as any).vaults[odd] as Vault;
  assert.equal(waitingAs(r.core.inner, "ws", checkLock(r.lock.entries, 4000), heldOdd), null, "no prefix of the lock took it");
  assert.ok(!vaults().vaults.some((v: any) => v.id === odd), "not listed");
  await fails(r.ask("vault.open", { item: item.id }), "vault_unknown");
  assert.equal(r.st.vaults.get(odd)!.seq, 0, "not keyed anew either");
  r.core.close();
});

test("whether a vault waits to be keyed anew is found once for a lock's entries and its version, not again as it is asked", async () => {
  const r = await rig();
  r.putLock();
  await r.ask("vault.setup", {});
  const mine = r.st.boxes.get("ab".repeat(32))!;
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(fill(7)), at: 2000 }, TAG.box, r.phone);
  const otherCert = sign({ v: 1 as const, ws: "ws", device: r.other.hex, box: boxPublic(fill(9)), at: 2000 }, TAG.box, r.other);
  const team = "v_01M4871X3MTC0903ZX5CPB8JHC";
  teamVault(r, team, fill(11), [otherCert, mine, phoneCert], "dep_1");
  await r.host.time.pass(500);
  stationReplies(r.host, (req) => (req.url.includes("/v1/workspaces/ws/lock") ? r.lock : r.st.reply(req)));
  grow(r, "device.remove", { id: r.phone.hex });
  await r.core.inner.runner.run(readLock(r.core.inner, "ws"));
  await r.host.time.pass(500, 10);
  const lock = checkLock(r.lock.entries, 4000);
  const v = (r.core.inner.data.record("vault", "ws") as any).vaults[team] as Vault;
  const was = waitingAs(r.core.inner, "ws", lock, v);
  assert.ok(was !== null, "waiting");
  assert.ok(waitingChecks.count >= 1, "the lock's prefixes checked");
  // (the same version as another object, as what is held is made anew at every change: found by what it is)
  const searched = waitingChecks.count;
  assert.equal(waitingAs(r.core.inner, "ws", lock, { ...v }), was, "the same lock found");
  assert.equal(waitingChecks.count, searched, "no prefix checked again");
  r.core.close();
});

test("certificates coming one upon another while a key is being given: given in turn, the key sealed to the last one's box key in the end", async () => {
  // A certificate heard while the vault's next version was being written for the one before was dropped, and only
  // the next event brought it (review of #3624): now each giving waits for the one under way, and reads anew.
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const [a, b] = [fill(7), fill(8)];
  const certA = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(a), at: 2000 }, TAG.box, r.phone);
  const certB = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(b), at: 2010 }, TAG.box, r.phone);
  const asked = r.host.secureAsked.length;
  r.st.boxes.set(r.phone.hex, certA);
  r.push("vault-box", certA);
  r.st.boxes.set(r.phone.hex, certB);
  r.push("vault-box", certB);
  await r.host.time.pass(1000);
  r.take();
  const v = r.st.vaults.get(id)!;
  const k = v.keys.find((x) => x.cert.device === r.phone.hex)!;
  assert.equal(k.cert.box, boxPublic(b), "the box key it has now");
  assert.equal(openSeal(b, k.wrapped, keyContext("ws", id, 0)).length, 32);
  assert.equal(r.host.secureAsked.length, asked);
  r.core.close();
});

test("a device an admin put in the lock under the person's name is no one's: given no key, prompted for nowhere, and what it signs counts for nothing", async () => {
  // An admin adds devices under any member's name with no code typed (lock-check.ts `device`): one under the owner's
  // name, signing with a key of the admin's own, was given the vault's key as its certificate came (review of #3624),
  // then waited on a prompt for one tap (2026-11-04: and it signed as the owner, in the lock and the vault). Now only
  // a person's own devices count: one an admin puts in after their first is in the lock, and is given nothing.
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  const prompts = await r.watch(2, { topic: "lockPrompts" });
  grow(r, "member", { sub: "s2", email: "b@x.com", role: "admin" });
  const evil = key(fill(13));
  grow(r, "device", { id: evil.hex, sub: "s1", kind: "app", label: "iPhone", sign_key: evil.id }, r.other);
  const checked = checkLock(r.lock.entries as Entry[], 4000);
  assert.deepEqual([checked.devices.get(evil.hex)?.own, checked.devices.get(r.phone.hex)?.own], [false, true]);
  // What it signs as the owner keeps the chain going and changes nothing: no one made an owner, the lock still on.
  grow(r, "member", { sub: "s2", email: "b@x.com", role: "owner" }, evil);
  grow(r, "disable", {}, evil);
  const after = checkLock(r.lock.entries as Entry[], 4000);
  assert.deepEqual([after.members.get("s2"), after.disabled], ["admin", false]);
  const evilCert = sign({ v: 1 as const, ws: "ws", device: evil.hex, box: boxPublic(fill(14)), at: 2000 }, TAG.box, evil);
  r.st.boxes.set(evil.hex, evilCert);
  r.push("vault-box", evilCert);
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual([r.st.vaults.get(id)!.seq, vaults().vaults[0].missing, prompts().asks.length], [0, 0, 0], "not given, not waiting");
  // Not given as the person asks either.
  assert.deepEqual(await r.ask("vault.addDevice", { vault: id, device: evil.hex }), { added: 0 });
  // The owner's own phone, added by themselves: given at once, as before.
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(fill(7)), at: 2001 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneCert);
  r.push("vault-box", phoneCert);
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual(r.st.vaults.get(id)!.keys.map((k) => k.cert.device).sort(), ["ab".repeat(32), r.phone.hex].sort());
  for (const k of r.st.vaults.get(id)!.keys) assert.ok(signedOk(k.cert, TAG.box) && !("sub" in k.cert), "each certificate as its device signed it");
  r.core.close();
});

test("a station that lacks this device's certificate (one added since this device was set up) is brought it as it is read", async () => {
  // A request a station made without it could be approved on no page of this device (2026-11-03: 「此申请提出时此设备
  // 尚未开启密钥库」): the station seals what its agents ask to keep to the certificates it holds.
  const r = await rig(false, true);
  r.putLock();
  await r.ask("vault.setup", {});
  const mine = r.st.boxes.get("ab".repeat(32))!;
  assert.deepEqual(r.st2.boxes.get("ab".repeat(32)), mine);
  r.st2.boxes.delete("ab".repeat(32));
  // The vaults page opened: every station read, the second given the certificate it lacks.
  await r.watch(3, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(500);
  assert.deepEqual(r.st2.boxes.get("ab".repeat(32)), mine);
  r.core.close();
});

test("a vault of one's own deleted: its last version sealed to no one, brought to every station; the person asked when it holds secrets", async () => {
  const r = await rig(false, true);
  r.putLock();
  const { made: empty } = await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(1000);
  assert.ok(r.st2.vaults.get(empty), "copied to the other station");
  // Empty: deleted as it is asked, nobody asked again.
  const asked = r.host.secureAsked.length;
  assert.deepEqual(await r.ask("vault.delete", { vault: empty }), { deleted: empty });
  assert.equal(r.host.secureAsked.length, asked);
  await r.host.time.pass(1000);
  r.take();
  const last = r.st.vaults.get(empty)!;
  assert.ok(signedOk(last, TAG.vault));
  assert.deepEqual([last.deleted, last.seq, last.epoch, last.keys, last.recovery], [true, 1, 1, [], undefined]);
  assert.deepEqual(r.st2.vaults.get(empty), last, "the other station brought it too");
  assert.deepEqual(vaults().vaults, []);
  await fails(r.ask("vault.putItem", { vault: empty, plain: { kind: "token", name: "x", fields: { value: "y" } } }), "vault_unknown");
  await fails(r.ask("vault.delete", { vault: empty }), "vault_unknown");
  // Read again from the stations (a page shown anew): still gone.
  await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: empty });
  await r.host.time.pass(1000);
  assert.deepEqual(vaults().vaults, []);

  // One holding a secret: the person asked first; their no keeps it.
  const { id } = await r.ask("vault.create", { name: "Work" });
  await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } } });
  assert.equal(vaults().vaults[0].items, 1);
  r.host.secureRefused = true;
  await fails(r.ask("vault.delete", { vault: id }), "user_cancelled");
  assert.equal(r.st.vaults.get(id)!.deleted, undefined);
  r.host.secureRefused = false;
  await r.ask("vault.delete", { vault: id });
  assert.match(r.host.secureAsked.at(-1)?.reason ?? "", /Work/);
  assert.equal(r.st.vaults.get(id)!.deleted, true);
  assert.deepEqual(vaults().vaults, []);
  r.core.close();
});

test("an item a station keeps back (no longer listed, or given at an older version) is shown here still and brought back to it; a device that held none of it sees it from the other station", async () => {
  const r = await rig(false, true);
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "Slack", fields: { value: "xoxp-1" } } });
  await r.ask("vault.putItem", { vault: id, id: put.id, plain: { kind: "token", name: "Slack", fields: { value: "xoxp-2" } } });
  await r.host.time.pass(1000);
  const latest = r.st.items.get(put.id)!;
  assert.deepEqual(r.st2.items.get(put.id), latest);
  // Its host keeps it back: lists it no more.
  r.st.items.delete(put.id);
  const shown = await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: id });
  await r.host.time.pass(1000);
  assert.deepEqual(shown().items.map((x: any) => x.id), [put.id], "held here, shown still");
  assert.deepEqual(r.st.items.get(put.id), latest, "brought back to the station that kept it back");
  // A device that holds nothing of the vault yet (this one, its records gone): the host gives the older version, the
  // other station the latest; the latest is the one held.
  r.st.items.set(put.id, { ...latest, version: 0 });
  r.core.inner.data.forgetRecord("vault", "ws");
  r.core.inner.data.forgetRecord("vaultItems", `ws/${id}`);
  // (the vaults page shown: the stations read again)
  await r.watch(3, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(1000);
  assert.deepEqual(shown().items.map((x: any) => x.id), [put.id]);
  const opened = await r.ask("vault.open", { item: put.id });
  assert.equal(opened.plain.fields.value, "xoxp-2", "the latest version, as the other station holds it");
  r.core.close();
});

test("a vault made on one station is copied to the workspace's others, so an agent on any of them may ask for its secrets", async () => {
  const r = await rig(false, true);
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  const put = await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "Slack", fields: { value: "xoxp-1" } }, listing: { name: "slack", kind: "token", modes: ["proxy"], hosts: ["slack.com"] } });
  await r.host.time.pass(1000);
  r.take();
  // Written on its host; the same versions on the other, brought as copies.
  assert.equal(r.st.vaults.get(id)!.seq, 0);
  assert.deepEqual(r.st2.vaults.get(id), r.st.vaults.get(id));
  assert.deepEqual(r.st2.items.get(put.id), r.st.items.get(put.id));
  assert.equal(vaults().vaults[0].stationName, "studio", "its host is still the station it was made on");
  // Changed: the next version written on the host only, then brought to the other.
  await r.ask("vault.putItem", { vault: id, id: put.id, plain: { kind: "token", name: "Slack", fields: { value: "xoxp-2" } }, listing: { name: "slack", kind: "token", modes: ["proxy"], hosts: ["slack.com"] } });
  await r.host.time.pass(1000);
  assert.equal(r.st.items.get(put.id)!.version, 1);
  assert.equal(r.st2.items.get(put.id)!.version, 1);
  // A copy behind (the station was away when it changed): read, it is brought the latest; an older copy changes nothing.
  r.st2.items.set(put.id, { ...r.st2.items.get(put.id)!, version: 0 });
  // (A page shown has the stations read again.)
  await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: id });
  await r.host.time.pass(1000);
  assert.equal(r.st2.items.get(put.id)!.version, 1);
  assert.equal(r.st.items.get(put.id)!.version, 1);
  // An agent on the other station asks: approved here, sealed to that station's keeper, the grant sent there.
  const keeper = fill(6);
  r.st2.requests.push({ id: "r_9", ws: "ws", vault: id, item: put.id, session: "k1", chat: "7", mode: "proxy", reason: "sync slack", hosts: ["slack.com"], box: boxPublic(keeper), at: 1, status: "pending" });
  await r.watch(3, { topic: "vaultUses", workspace: "ws", vault: id, item: put.id });
  await r.host.time.pass(1000);
  r.take();
  assert.deepEqual(vaults().requests.map((q: any) => q.id), ["r_9"]);
  await r.ask("vault.approve", { request: "r_9", scope: "once" });
  assert.deepEqual([r.st.grants.length, r.st2.grants.length], [0, 1]);
  const grant = r.st2.grants[0] as any;
  assert.equal(JSON.parse(new TextDecoder().decode(openSeal(keeper, grant.secret, grantContext("ws", "r_9")))).fields.value, "xoxp-2");
  r.core.close();
});

test("a station gone silent (its machine asleep) is not waited on: a device set up on the one that answers", async () => {
  const r = await rig(false, true);
  r.putLock();
  // st2 asked, it never answers: no answer, no close.
  stationLater(r.host, (req) => (req.headers.some(([k, v]) => k === "x-test-station" && v === "st2") ? new Promise(() => {}) : undefined));
  const setup = await r.ask("vault.setup", {});
  assert.ok(r.st.boxes.get(setup.device), "published on the station that answered");
  r.core.close();
});

test("two versions of one seq, written on two stations at once: the one every station keeps is shown here and brought to the other", async () => {
  const r = await rig(false, true);
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(1000);
  const { sig: _, ...rest } = r.st.vaults.get(id)!;
  const a = sign({ ...rest, seq: 1, lasts: "hour" as const, at: rest.at + 1 }, TAG.vault, r.me.signer!);
  const b = sign({ ...rest, seq: 1, lasts: "once" as const, at: rest.at + 1 }, TAG.vault, r.me.signer!);
  const kept = rules.vault_supersedes_js(a, b) ? a : b;
  r.st.vaults.set(id, a);
  r.st2.vaults.set(id, b);
  // (a page shown has the stations read again)
  await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: id });
  await r.host.time.pass(2000);
  r.take();
  assert.deepEqual([r.st.vaults.get(id), r.st2.vaults.get(id)], [kept, kept], "both stations hold the one kept");
  assert.equal(vaults().vaults.length, 1);
  r.core.close();
});

test("a web page keeps no keys: the vault is refused there", async () => {
  const r = await rig(true);
  r.putLock();
  await fails(r.ask("vault.setup", {}), "vault_unavailable");
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  assert.equal(vaults().available, false);
  r.core.close();
});

test("a station without the lock pinned holds no vault, and says so", async () => {
  const r = await rig();
  r.putLock();
  r.st.locked.on = false;
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(500);
  assert.deepEqual(vaults().refused, [{ station: "st", name: "studio", code: "vault_needs_lock" }]);
  await fails(r.ask("vault.setup", {}), "vault_no_station");
  r.core.close();
});

test("the plain library: no security mode, items kept on the station as they are, used by agents, moved into the vault once it is on", async () => {
  const r = await rig();
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(500);
  r.take();
  assert.equal(vaults().plain, true);
  assert.deepEqual(vaults().vaults.map((v: any) => [v.id, v.stationName, v.open]), [["plain", "studio", true]]);
  const put = await r.ask("vault.putItem", { vault: "plain", plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } }, listing: { name: "GitHub", kind: "token", modes: ["proxy"], hosts: ["api.github.com"], env: "GH_TOKEN" } });
  assert.equal(r.st.plain.get(put.id).fields.value, "ghp_x");
  assert.equal(r.host.secureAsked.length, 0, "nothing asked of the person: nothing to unseal");
  const shown = await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: "plain" });
  assert.deepEqual(shown().items.map((i: any) => [i.name, i.kind, i.listed, i.env]), [["GitHub", "token", true, "GH_TOKEN"]]);
  assert.equal((await r.ask("vault.open", { item: put.id })).plain.fields.value, "ghp_x");
  // What the pages say of it, the core's: its kind, how agents may ask for it and get it, its longest grant; opened, its
  // fields as its page shows them; the library's at the settings' row.
  assert.deepEqual(shown().items.map((i: any) => [i.kindText, i.agentText, i.lineText, i.howText, i.lastsText]), [
    ["Token", "允许 agent 申请 · 代理 · api.github.com", "代理 · api.github.com · GH_TOKEN", "代理 · 限 api.github.com", "跟随默认 · 直到对话归档"],
  ]);
  const opened = await r.ask("vault.open", { item: put.id });
  assert.deepEqual([opened.kindText, opened.shown], ["Token", [{ key: "value", label: "值", value: "ghp_x", secret: true, mono: true }]]);
  assert.deepEqual(shown().items[0].shut.map((f: any) => [f.label, f.value.length]), [["值", 20]]);
  assert.deepEqual([vaults().statusText, vaults().statusBad], ["1 条", false]);

  // An agent asks: its owner approves, with nothing signed; the use shown on the item.
  r.st.requests.push({ id: "r_p", ws: "ws", vault: "plain", item: put.id, session: "ember:s", chat: "", mode: "proxy", reason: "ci", hosts: ["api.github.com"], box: "", at: 1000, status: "pending" } as Request);
  await r.ask("vault.approve", { request: "r_p", scope: "once" });
  assert.deepEqual(r.st.plainGrants, [{ request: "r_p", scope: "once" }]);
  // One it asks to keep: written by the station from what it holds, once its owner says so.
  r.st.requests.push({ id: "r_k", ws: "ws", vault: "plain", item: "i_01JAKEEP0000000000000P1A1N", session: "ember:s", chat: "", mode: "env", reason: "slack", box: "", at: 1000, status: "pending", owner: "me@x.com", save: { kind: "token", name: "Slack", modes: ["env"], hosts: [] } } as Request);
  await r.ask("vault.approve", { request: "r_k", scope: "once" });
  assert.deepEqual(r.st.plainSaves, [{ request: "r_k" }]);
  // One its owner types in: sent with what they typed, as the item's fields.
  r.st.requests.push({ id: "r_t", ws: "ws", vault: "plain", item: "i_01JAKEEP0000000000000TYPED", session: "ember:s", chat: "", mode: "env", reason: "go", box: "", at: 1000, status: "pending", owner: "me@x.com", save: { kind: "token", name: "Go", modes: ["env"], hosts: [], typed: true } } as Request);
  await fails(r.ask("vault.approve", { request: "r_t", scope: "once" }), "vault_typed_empty");
  await r.ask("vault.approve", { request: "r_t", scope: "once", typed: { secret: "sk-go" } });
  assert.deepEqual(r.st.plainSaves, [{ request: "r_k" }, { request: "r_t", fields: { value: "sk-go" } }]);
  // The person's longest grant, told to the station keeping the library.
  await r.ask("vault.setLasts", { vault: "plain", lasts: "hour" });
  assert.equal(r.st.plainLasts.lasts, "hour");
  assert.equal(vaults().vaults[0].lasts, "hour");
  assert.deepEqual(r.st.grants, [], "no signed grant");
  r.st.uses.push({ item: put.id, at: 1000, session: "ember:s", chatTitle: "修 CI", mode: "proxy", command: "gh pr list", hosts: ["api.github.com"], denied: false });
  const used = await r.watch(3, { topic: "vaultUses", workspace: "ws", vault: "plain", item: put.id });
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual(used().uses.map((u: any) => [u.chatTitle, u.command, u.station, typeof u.at.ago]), [["修 CI", "gh pr list", "st", "string"]]);
  assert.equal(shown().items[0].lastUse.command, "gh pr list");
  // used: its line says when and in which chat, its use how
  assert.equal(used().uses[0].howText, "gh pr list · 代理");
  assert.match(shown().items[0].lineText, /^代理 · api\.github\.com · GH_TOKEN · .+在「修 CI」用过$/);

  // Security mode on: the vault is the library; what was plain is counted, kept from new writes, and moved.
  r.putLock();
  r.st.plainLock.on = true;
  await r.ask("vault.setup", {});
  assert.equal(vaults().plain, undefined);
  assert.equal(vaults().plainLeft, 1);
  await fails(r.ask("vault.putItem", { vault: "plain", plain: { kind: "token", name: "x", fields: { value: "y" } } }), "vault_locked");
  assert.deepEqual(await r.ask("vault.migrate", {}), { moved: 1, left: 0 });
  assert.equal(r.st.plain.get(put.id).deleted, true);
  const moved = [...r.st.items.values()];
  assert.deepEqual(moved.map((i) => i.listing?.name), ["GitHub"]);
  assert.equal(vaults().plainLeft, undefined);
  r.core.close();
});

test("a file kept: its bytes in base64 under its name; opened, shown as its text, or as binary and its size; too big, refused; one an agent asks for, picked on its card", async () => {
  const r = await rig();
  await r.watch(1, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(500);
  r.take();
  const b64 = (b: Uint8Array | string) => Buffer.from(b).toString("base64");
  const yaml = "apiVersion: v1\nkind: Config\n";
  const put = await r.ask("vault.putItem", { vault: "plain", plain: { kind: "file", name: "集群", fields: { content: b64(yaml), filename: "config" } }, listing: { name: "集群", kind: "file", modes: ["file"], hosts: [], env: "KUBECONFIG" } });
  assert.deepEqual(r.st.plain.get(put.id).fields, { content: b64(yaml), filename: "config" });
  const shown = await r.watch(2, { topic: "vaultItems", workspace: "ws", vault: "plain" });
  assert.deepEqual(shown().items.map((i: any) => [i.kindText, i.agentText, i.lineText]), [["文件", "允许 agent 申请 · 文件", "文件 · KUBECONFIG"]]);
  assert.deepEqual(shown().items[0].shut.map((f: any) => f.label), ["文件名", "内容"]);
  const opened = await r.ask("vault.open", { item: put.id });
  assert.deepEqual([opened.kindText, opened.shown], ["文件", [
    { key: "filename", label: "文件名", value: "config", secret: false, mono: false },
    { key: "content", label: "内容", value: yaml, secret: true, mono: true },
  ]]);
  const p12 = await r.ask("vault.putItem", { vault: "plain", plain: { kind: "file", name: "证书", fields: { content: b64(new Uint8Array(3000).fill(0x80)), filename: "a.p12" } } });
  assert.deepEqual((await r.ask("vault.open", { item: p12.id })).shown[1], { key: "content", label: "内容", value: "二进制 · 3 KB", secret: false, mono: false });
  await fails(r.ask("vault.putItem", { vault: "plain", plain: { kind: "file", name: "大", fields: { content: b64(new Uint8Array(64 * 1024 + 1)) } } }), "vault_file_too_big");
  await fails(r.ask("vault.putItem", { vault: "plain", plain: { kind: "file", name: "坏", fields: { content: "not base64" } } }), "invalid_params");

  // One an agent asks the person for: the file they picked, under the name the agent gave, else its own.
  r.st.requests.push({ id: "r_f", ws: "ws", vault: "plain", item: "i_01JAKEEP00000000000000F11E", session: "ember:s", chat: "", mode: "file", reason: "go", box: "", at: 1000, status: "pending", owner: "me@x.com", save: { kind: "file", name: "SA", modes: ["file"], hosts: [], typed: true } } as Request);
  await fails(r.ask("vault.approve", { request: "r_f", typed: { secret: b64(new Uint8Array(64 * 1024 + 1)), filename: "sa.json" } }), "vault_file_too_big");
  await r.ask("vault.approve", { request: "r_f", typed: { secret: b64("{}"), filename: "sa.json" } });
  assert.deepEqual(r.st.plainSaves.at(-1), { request: "r_f", fields: { content: b64("{}"), filename: "sa.json" } });
  r.core.close();
});

test("turning the lock off: the person's own secrets opened first (asked once), then written into the plain library once it is off", async () => {
  const r = await rig();
  r.putLock();
  const { made } = await r.ask("vault.setup", {});
  await r.ask("vault.putItem", { vault: made, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } }, listing: { name: "GitHub", kind: "token", modes: ["proxy"], hosts: ["api.github.com"] } });
  await r.ask("vault.lock", {});
  // The cloud keeps the chain: the entries posted are taken into it.
  stationReplies(r.host, (req) => {
    if (!req.url.endsWith("/v1/workspaces/ws/lock")) return r.st.reply(req);
    if (req.method === "GET") return r.lock;
    const posted = JSON.parse(new TextDecoder().decode(req.body!)).entries as Entry[];
    r.lock.entries.push(...posted);
    r.lock.head = { ...r.lock.head, seq: r.lock.entries.length - 1, hash: entryHash(r.lock.entries.at(-1)!) };
    return { ok: true };
  });
  r.st.plainLock.on = true;
  const asked = r.host.secureAsked.length;
  await r.ask("lock.disable", {});
  // (asked once, the vault's prompt saying it turns security mode off: no second prompt after it, as there was, two in a
  // row for one tap, till the end-to-end flow on Android found it)
  assert.deepEqual(r.host.secureAsked.slice(asked).map((a) => [a.key, a.reason]), [[BOX_KEY, t("core-misc.lock.reason.disable")]]);
  // The station hears the lock is off a little later: tried again until it takes it.
  assert.equal(r.st.plain.size, 0);
  r.st.plainLock.on = false;
  r.putLock();
  await r.host.time.pass(5000, 1000);
  const back = [...r.st.plain.values()];
  assert.deepEqual(back.map((i) => [i.name, i.fields.value, i.listing?.hosts]), [["GitHub", "ghp_x", ["api.github.com"]]]);
  r.core.close();
});

// ── a workspace whose chain moved to its people's own logs ──

/// The rig's workspace moved (`moved {root}`) to s1's own log, its root: this device on that log (its key's seed sealed
/// as personal-lock.ts keeps it), the log saying the settings and the station `S` (which the workspace's view lists);
/// that station takes the person's own log and its bodies as the real ones do.
const S = "5a".repeat(32);
async function movedRig(secret: boolean) {
  const r = await rig(false, false, {}, { stations: [{ id: S, name: "studio", online: true, last_seen: null }] });
  r.putLock();
  if (secret) {
    const { made } = await r.ask("vault.setup", {});
    await r.ask("vault.putItem", { vault: made, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } }, listing: { name: "GitHub", kind: "token", modes: ["proxy"], hosts: ["api.github.com"] } });
    await r.ask("vault.lock", {});
  }
  const seed = fill(0x51);
  const k = key(seed);
  const sign = (chain: Entry[], kind: string, body: unknown): Entry => {
    const last = chain.at(-1);
    const e = { v: 1 as const, ws: "person:s1", seq: chain.length, prev: last ? entryHash(last) : null, at: 1_790_000_000, kind, body };
    return { ...e, sig: { key: k.id, alg: "Ed25519" as const, sig: hex(ed25519.sign(signedBytes(entryHash(e)), seed)) } };
  };
  let own: Entry[] = [sign([], "genesis", { sub: "s1", device: { key: k.id, id: "ab".repeat(32), label: "this" } })];
  const g = entryHash(own[0]!);
  const bodies: unknown[] = [];
  let prev: string | null = null;
  for (const [i, said] of [{ kind: "open", origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: {}, email: "a@x.com" }, { kind: "station", key: S }].entries()) {
    const b: Record<string, unknown> = { ws: "ws", ...said, prev, salt: (0x7700 + i).toString(16).padStart(32, "0") };
    prev = bodyHash(b)!;
    bodies.push(b);
    own = [...own, sign(own, "ws", { t: wsTag("ws", g), h: prev })];
  }
  r.host.storage.set(`personal-lock-${hex(utf8("s1"))}`, utf8(JSON.stringify(own)));
  r.host.storage.set("personal-signer-id", utf8(k.id));
  r.host.secure.set("personal-signer", { value: seed, user: true });
  stationReplies(r.host, (req) => {
    const path = new URL(req.url).pathname;
    if (path.endsWith("/lock/person") && req.method === "GET") return { chains: [{ genesis: g, entries: own }] };
    if (path.endsWith("/lock/person") && req.method === "POST") {
      const b = JSON.parse(new TextDecoder().decode(req.body!)) as { chain: Entry[]; bodies?: unknown[] };
      if (b.chain.length > own.length) own = b.chain;
      for (const x of b.bodies ?? []) if (!bodies.some((y) => bodyHash(y) === bodyHash(x))) bodies.push(x);
      return { genesis: g, length: b.chain.length };
    }
    if (path.endsWith("/lock/bodies") && req.method === "GET") return { bodies, lacking: [] };
    if (path.endsWith("/lock/logs")) return { chains: [] };
    return r.st.reply(req);
  });
  r.core.inner.data.put("lockBodies", "ws", { bodies });
  grow(r, "moved", { root: g });
  // (started anew: the person's own lock read from what is kept, as an app that had it pinned)
  await r.restart();
  await r.core.inner.runner.run(Effect.ignore(r.core.inner.adb.personal().refresh("s1")));
  await r.host.time.pass(500);
  return r;
}

test("a moved workspace turned off, the person with a secret of their own: it opened first, then off signed in their own log (asked twice, in that order), the secret in the plain library after", async () => {
  const r = await movedRig(true);
  const f = inForceOf(r.core.inner, "ws");
  assert.equal(f.said, "on", `the moved workspace on: ${JSON.stringify({ said: f.said, root: f.root, pinned: r.core.inner.adb.personal().pinnedOf("s1").length, owner: r.core.inner.workspaces.owner("ws"), last: (r.core.inner.data.record("lock", "ws") as { entries: Entry[] }).entries.at(-1)?.kind, why: (f as { why?: unknown }).why })}`);
  const asked = r.host.secureAsked.length;
  await r.ask("lock.disable", {});
  assert.deepEqual(r.host.secureAsked.slice(asked).map((a) => [a.key, a.reason]), [[BOX_KEY, t("core-misc.lock.reason.disable")], ["personal-signer", t("core-misc.lock.reason.disable")]]);
  assert.equal(inForceOf(r.core.inner, "ws").said, "off", "off");
  await r.host.time.pass(5000, 1000);
  assert.deepEqual([...r.st.plain.values()].map((i) => [i.name, i.fields.value]), [["GitHub", "ghp_x"]], "the secret in the plain library");
  r.core.close();
});

test("a moved workspace turned off, the second ask turned down: not off, nothing written; with no secret of their own: asked once", async () => {
  const r = await movedRig(true);
  const get = r.host.secureGet!;
  r.host.secureGet = (k, o) => (k === "personal-signer" ? Effect.fail(new HostError("user_cancelled")) : get(k, o));
  await assert.rejects(r.ask("lock.disable", {}), "turned down");
  assert.equal(inForceOf(r.core.inner, "ws").said, "on", "not off");
  await r.host.time.pass(5000, 1000);
  assert.equal(r.st.plain.size, 0, "nothing written to the plain library");
  r.core.close();
  const n = await movedRig(false);
  const asked = n.host.secureAsked.length;
  await n.ask("lock.disable", {});
  assert.deepEqual(n.host.secureAsked.slice(asked).map((a) => a.key), ["personal-signer"], "asked once");
  assert.equal(inForceOf(n.core.inner, "ws").said, "off");
  n.core.close();
});

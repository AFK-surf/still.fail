// The vault on the device (src/vault/, src/views/vault.ts): the formats on the values the stations are tested on
// (station/test/fixtures/vault-vectors.json), the lock checked entry by entry before a key is sealed to anyone, and the
// calls against a station that keeps what it is given, on the testing host's secure storage; and turning the lock off,
// on the same rig, asking the person first. Its time is the test clock.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
import { apply as applyOps } from "../src/delta.ts";
import { HostError } from "../src/error.ts";
import { t } from "../src/i18n.ts";
import type { HttpRequest } from "../src/host.ts";
import type { StationAddr } from "../src/station/addr.ts";
import { HostWire, type RequestHead, type StationWire } from "../src/station/wire.ts";
import type { FakeHost } from "../src/testing.ts";
import { type Entry, Signer, entryHash, next } from "../src/lock.ts";
import { hex, utf8 } from "../src/util.ts";
import {
  type BoxCert, type Item, type Request, type Vault, TAG, boxPublic, decrypt, encryptWith, fromWords, grantContext, itemContext, keyContext,
  openSeal, recoveryPair, saveContext, sealWith, sign, signedOk, toWords,
} from "../src/vault/crypto.ts";
import { checkLock } from "../src/vault/lock-check.ts";
import { BOX_KEY, BOX_PUB, UNLOCK_MS } from "../src/views/vault.ts";
import { subscribe, call } from "./helpers.ts";
import { type Answers, base, entry, started, stationReplies, status } from "./station-fixture.ts";

const V = JSON.parse(readFileSync(new URL("../../../station/test/fixtures/vault-vectors.json", import.meta.url), "utf8"));
const unhex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));
const fill = (b: number, n = 32) => new Uint8Array(n).fill(b);

/// An Ed25519 key from a seed: a lock device's signing key.
function key(seed: Uint8Array) {
  const id = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
  return { id, hex: hex(ed25519.getPublicKey(seed)), signBytes: (b: Uint8Array) => hex(ed25519.sign(b, seed)) };
}

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
  assert.throws(() => checkLock([g, theirs], 2000), /not its signer's/);
  // Signed by a key the lock does not name; changed after signing; not following the head.
  assert.throws(() => checkLock([g, signed(next("ws", head, 1001, "member", { sub: "s3", email: "c", role: "owner" }), key(fill(9)))], 2000), /not signed by a device/);
  assert.throws(() => checkLock([g, { ...own, body: { ...(own.body as object), sub: "s1" } }], 2000), /not signed/);
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
        return { vaults: [...vaults.values()] };
      case "PUT /vault/vaults": {
        const prev = vaults.get(body.id);
        // A copy from another station: any later version; one no later answered with the one held.
        const copy = query === "copy=1";
        if (copy && prev && body.seq <= prev.seq) return { vault: prev };
        if (!copy && body.seq !== (prev ? prev.seq + 1 : 0)) return status(409, { error: "seq", code: "vault_conflict", vault: prev ?? null });
        if (!signedOk(body, TAG.vault)) return status(400, { error: "signature", code: "vault_invalid" });
        vaults.set(body.id, body);
        return { vault: body };
      }
      case "GET /vault/items":
        return { items: [...items.values()].filter((i) => !query || query === `vault=${i.vault}`) };
      case "PUT /vault/items": {
        const prev = items.get(body.id);
        const copy = query === "copy=1";
        if (!vaults.has(body.vault)) return status(404, { error: "no vault", code: "vault_unknown" });
        if (copy && prev && body.version <= prev.version) return { item: prev };
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
    }
    return status(404, { error: `no route ${key}` });
  };
  return { vaults, items, boxes, requests, grants, denials, keepers, locked, plain, plainGrants, plainLasts, uses, plainLock, saves, plainSaves, reply };
}

/// A core on an app's host (keys kept, secure storage), reaching `ws/st` (the fake station); its lock put in place.
/// `web`: a web page's host (no secure storage). `two`: a second station, `ws/st2` (`st2`), in the workspace too.
/// `more`: what else the station answers (its chats' posts).
async function rig(web = false, two = false, more: Answers = {}) {
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
    stationReplies(x.host, (req) => (req.headers.some(([k, v]) => k === AT && v === "st2") ? st2.reply(req) : st.reply(req)));
  });
  const genesis = lockOf({ id: me.signer!.id, signBytes: (b) => me.signer!.signBytes(b) }, phone, other);
  const lock = { head: { seq: 0, hash: entryHash(genesis), genesis: entryHash(genesis) }, entries: [genesis], requests: [] };
  const ui = s.core.connect();
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
  return { ...s, st, st2, phone, other, lock, ask, watch, take, putLock: () => s.core.inner.data.put("lock", "ws", lock) };
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
  assert.equal(vaults().vaults[0].missing, 1);
  assert.deepEqual(await r.ask("vault.addDevice", { vault: id }), { added: 1 });
  const v1 = r.st.vaults.get(id)!;
  assert.equal(v1.seq, 1);
  const phoneKey = v1.keys.find((k) => k.cert.device === r.phone.hex)!;
  assert.equal(openSeal(phoneBox, phoneKey.wrapped, keyContext("ws", id, 0)).length, 32);
  assert.equal(vaults().vaults[0].missing, 0);
  // This device loses its box key (the app was installed anew): set up again, no new words (its person has them).
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

/// Chat 7's posts as its station answers them: a person's, then an agent's asking to use `gh` (r_1), then one asking to
/// keep a login (r_s), their cards as the station writes them (station/src/vault/secrets.ts).
function cardsInChat(): Answers {
  const card = (request: string, more: Record<string, unknown> = {}) => ({ type: "options", options: [], vault: { request, name: "gh", mode: "proxy", reason: "list PRs", hosts: ["api.github.com"], command: "gh pr list", ...more } });
  const asks = (n: number, c: unknown) => ({ ...entry(n, "要用 gh"), authorKind: "agent", author: "k1", card: c });
  return { "GET /threads/7/entries?limit=50": { last: 3, entries: [entry(1, "存一下"), asks(2, card("r_1")), asks(3, card("r_s", { save: { kind: "login", username: "zzj" } }))] } };
}

test("a chat's card of an agent's request comes answered with its post, from the vault the core holds; decided here, how it went at once", async () => {
  const r = await rig(false, false, cardsInChat());
  r.putLock();
  const chat = await r.watch(2, { topic: "chat", station: "ws/st", thread: 7 });
  const asks = () => chat().messages.filter((m: any) => m.card?.vaultAsk).map((m: any) => [m.card.vault, m.card.vaultAsk.answer, m.card.vaultAsk.lasts ?? null, m.card.vaultAsk.status ?? null]);
  // This device's vault not on: one to keep turns it on first; one to use is approved, for the chat at the longest
  // while its request is not held here.
  assert.deepEqual(asks(), [["r_1", "approve", "chat", null], ["r_s", "setUp", null, null]]);
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
  assert.equal(chat().messages.find((m: any) => m.card?.vault === "r_1").card.vaultAsk.scope, "once");
  r.core.close();
  // A web page keeps no keys: approved elsewhere.
  const w = await rig(true, false, cardsInChat());
  w.putLock();
  const there = await w.watch(2, { topic: "chat", station: "ws/st", thread: 7 });
  assert.deepEqual(there().messages.filter((m: any) => m.card?.vaultAsk).map((m: any) => m.card.vaultAsk.answer), ["elsewhere", "elsewhere"]);
  w.core.close();
});

test("vault calls: a secret an agent asks to keep, opened with this device's box key, written into a vault of one's own, then told", async () => {
  const r = await rig();
  r.putLock();
  await r.ask("vault.setup", {});
  const here = [...r.st.boxes.values()][0]!;
  const fields = { username: "zzj", password: "pw-123" };
  const keeper = fill(9);
  const save = (rid: string, item: string, to: { device: string; box: string }): Request => ({
    id: rid, ws: "ws", vault: "", item, session: "k1", chat: "7", mode: "env", reason: "log in to the router", box: boxPublic(keeper), at: 1, status: "pending", owner: "a@x.com",
    save: { kind: "login", name: "UniFi UX7", modes: ["env"], hosts: [], env: "UX7_PASSWORD", username: "zzj" },
    sealed: [{ device: to.device, box: to.box, secret: sealWith(to.box, utf8(JSON.stringify(fields)), saveContext("ws", rid), fill(6)) }],
  });
  const item = "i_01JAKEEP000000000000000UX7";
  r.st.requests.push(save("r_s", item, here));
  r.push("vault-request", save("r_s", item, here));
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  await r.host.time.pass(500);
  r.take();
  assert.deepEqual(vaults().requests.map((q: any) => [q.id, q.itemName, q.save]), [["r_s", "UniFi UX7", { kind: "login", username: "zzj" }]]);
  assert.equal(vaults().vaults.length, 1, "one's own, made as this device was set up");

  const asked = r.host.secureAsked.length;
  const kept = await r.ask("vault.approve", { request: "r_s", scope: "once" });
  assert.equal(r.host.secureAsked.length, asked + 1, "the person is asked once");
  const [made] = [...r.st.vaults.values()];
  assert.ok(made && kept.vault === made.id && made.owner === "s1");
  const written = r.st.items.get(item)!;
  assert.ok(signedOk(written, TAG.item));
  assert.deepEqual([written.vault, written.version, written.listing], [made.id, 0, { name: "UniFi UX7", kind: "login", modes: ["env"], hosts: [], env: "UX7_PASSWORD" }]);
  assert.deepEqual((await r.ask("vault.open", { item })).plain.fields, fields);
  // With the grant that lets the asking chat use it: for the chat, sealed to the request's box.
  const saved = r.st.saves[0] as any;
  assert.deepEqual([saved.request, saved.vault, saved.grant.scope, saved.grant.mode, saved.grant.item], ["r_s", made.id, "chat", "env", item]);
  assert.ok(signedOk(saved.grant, TAG.grant));
  assert.deepEqual(JSON.parse(new TextDecoder().decode(openSeal(keeper, saved.grant.secret, grantContext("ws", "r_s")))).fields, fields);
  assert.deepEqual(vaults().requests, []);

  // Into that vault next time; one sealed to another device is not this one's to open.
  const second = "i_01JAKEEP000000000000000TWO";
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
  const login = "i_01JAKEEP0000000000000LOGIN";
  const asksLogin = typed("r_z", login, { kind: "login", name: "Router", modes: ["env"], hosts: [], typed: true });
  r.st.requests.push(asksLogin);
  r.push("vault-request", asksLogin);
  await r.ask("vault.approve", { request: "r_z", scope: "once", typed: { secret: " pw ", username: " admin " } });
  assert.deepEqual((await r.ask("vault.open", { item: login })).plain.fields, { username: "admin", password: " pw " });
  r.core.close();
});

test("one vault of one's own: a device set up later makes none, and is given its key as soon as one of the owner's devices that has it unseals it", async () => {
  const r = await rig();
  r.putLock();
  const { made: id } = await r.ask("vault.setup", {});
  const vaults = await r.watch(1, { topic: "vaults", workspace: "ws" });
  // The phone sets itself up: no key to the vault yet.
  const phoneBox = fill(7);
  const phoneCert = sign({ v: 1 as const, ws: "ws", device: r.phone.hex, box: boxPublic(phoneBox), at: 2000 }, TAG.box, r.phone);
  r.st.boxes.set(r.phone.hex, phoneCert);
  r.push("vault-box", phoneCert);
  await r.host.time.pass(100);
  assert.equal(vaults().vaults[0].missing, 1);
  // Its key in hand here as the person writes into it (unsealed when it was made): the phone given its key with it,
  // the person asked nothing more.
  const asked = r.host.secureAsked.length;
  await r.ask("vault.putItem", { vault: id, plain: { kind: "token", name: "GitHub", fields: { value: "ghp_x" } } });
  await r.host.time.pass(500);
  r.take();
  assert.equal(r.host.secureAsked.length, asked);
  const v1 = r.st.vaults.get(id)!;
  assert.ok(signedOk(v1, TAG.vault));
  assert.equal(v1.seq, 1);
  assert.equal(openSeal(phoneBox, v1.keys.find((k) => k.cert.device === r.phone.hex)!.wrapped, keyContext("ws", id, 0)).length, 32);
  assert.equal(vaults().vaults[0].missing, 0);

  // This device installed anew: set up again, no key to the vault and no second one made; a secret to keep approved
  // here is refused (before the person is asked) till a device that has the key gives it.
  r.host.secure.delete(BOX_KEY);
  r.host.storage.delete(BOX_PUB);
  await r.ask("vault.lock", {});
  const again = await r.ask("vault.setup", {});
  assert.deepEqual([again.made, r.st.vaults.size], [null, 1]);
  const box = r.st.boxes.get("ab".repeat(32))!.box;
  const rid = "r_k";
  const save: Request = {
    id: rid, ws: "ws", vault: "", item: "i_01JAKEEP000000000000000NEW", session: "k1", chat: "7", mode: "env", reason: "keep it", box: boxPublic(fill(9)), at: 1, status: "pending", owner: "a@x.com",
    save: { kind: "token", name: "Axiom", modes: ["env"], hosts: [] },
    sealed: [{ device: "ab".repeat(32), box, secret: sealWith(box, utf8(JSON.stringify({ value: "xaat" })), saveContext("ws", rid), fill(6)) }],
  };
  r.st.requests.push(save);
  r.push("vault-request", save);
  await r.host.time.pass(500);
  const before = r.host.secureAsked.length;
  await fails(r.ask("vault.approve", { request: rid, scope: "once" }), "vault_no_key");
  assert.deepEqual([r.host.secureAsked.length, r.st.vaults.size, r.st.items.has(save.item)], [before, 1, false]);
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
  r.st.requests.push({ id: "r_k", ws: "ws", vault: "plain", item: "i_01JAKEEP0000000000000PLAIN", session: "ember:s", chat: "", mode: "env", reason: "slack", box: "", at: 1000, status: "pending", owner: "me@x.com", save: { kind: "token", name: "Slack", modes: ["env"], hosts: [] } } as Request);
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
  r.st.requests.push({ id: "r_f", ws: "ws", vault: "plain", item: "i_01JAKEEP00000000000000FILE", session: "ember:s", chat: "", mode: "file", reason: "go", box: "", at: 1000, status: "pending", owner: "me@x.com", save: { kind: "file", name: "SA", modes: ["file"], hosts: [], typed: true } } as Request);
  await fails(r.ask("vault.approve", { request: "r_f", typed: { secret: b64(new Uint8Array(64 * 1024 + 1)), filename: "sa.json" } }), "vault_file_too_big");
  await r.ask("vault.approve", { request: "r_f", typed: { secret: b64("{}"), filename: "sa.json" } });
  assert.deepEqual(r.st.plainSaves.at(-1), { request: "r_f", fields: { content: b64("{}"), filename: "sa.json" } });
  r.core.close();
});

test("turning the lock off: the person's own secrets opened first, then written into the plain library once it is off", async () => {
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
  assert.deepEqual(r.host.secureAsked.slice(asked).map((a) => a.key), [BOX_KEY, ""], "the vault opened, then the person asked to turn it off");
  // The station hears the lock is off a little later: tried again until it takes it.
  assert.equal(r.st.plain.size, 0);
  r.st.plainLock.on = false;
  r.putLock();
  await r.host.time.pass(5000, 1000);
  const back = [...r.st.plain.values()];
  assert.deepEqual(back.map((i) => [i.name, i.fields.value, i.listing?.hosts]), [["GitHub", "ghp_x", ["api.github.com"]]]);
  r.core.close();
});

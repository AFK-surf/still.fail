// The workspace lock across a person's workspaces (src/views/lock.ts): a device waiting in several of them is put up on
// a trusted device of theirs once, wherever it is, naming each, and approved in all of them with one code; a device
// whose key cannot be kept says its request did not go rather than waiting for nothing; a station's refusal names the
// workspace and where to approve. Against a cloud that keeps chains and requests (the station fixture's host), on the
// test clock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
import { hooks } from "../src/core/execute.ts";
import { apply as applyOps } from "../src/delta.ts";
import { HostError } from "../src/error.ts";
import type { HttpRequest } from "../src/host.ts";
import { type Entry, Signer, entryHash, next, shortCode } from "../src/lock.ts";
import type { FakeHost } from "../src/testing.ts";
import { hex, utf8 } from "../src/util.ts";
import { BEHIND_MS, BEHIND_TRIES } from "../src/views/lock.ts";
import { call, subscribe } from "./helpers.ts";
import { started, stationLater, stationReplies, status } from "./station-fixture.ts";

const unhex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));
/// The base key of the testing core's device (its mesh's).
const ME = "ab".repeat(32);
/// A phone of the member s2's, waiting.
const PHONE = "cd".repeat(32);

/// A workspace's lock: s1 the owner, `signer` (this device's key, when it is in) their app; s2 a member.
function genesis(ws: string, signer: { id: string; signBytes(b: Uint8Array): string }, withMe: boolean, stations: { key: string; name: string }[] = []): Entry {
  const e = next(ws, null, 1000, "genesis", {
    owner: "s1", origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: {},
    members: [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "s2", email: "b@x.com", role: "member" }],
    devices: withMe ? [{ id: ME, sub: "s1", kind: "app", label: "this", sign_key: signer.id }] : [],
    passkeys: [], stations, gateways: [],
  });
  return { ...e, sig: { key: signer.id, alg: "Ed25519", sig: signer.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } };
}

/// A key of nobody's on this device: the owner's elsewhere.
function elsewhere() {
  const seed = new Uint8Array(32).fill(9);
  return { id: `ed25519:${hex(ed25519.getPublicKey(seed))}`, signBytes: (b: Uint8Array) => hex(ed25519.sign(b, seed)) };
}

/// A cloud keeping each workspace's chain and its waiting devices, as /v1/workspaces/:ws/lock… answers.
function lockCloud() {
  const chains = new Map<string, Entry[]>();
  const requests = new Map<string, Record<string, unknown>[]>();
  const posted: { ws: string; kind: string; id?: string }[] = [];
  const asked: string[] = [];
  const head = (ws: string) => {
    const c = chains.get(ws) ?? [];
    return c.length === 0 ? null : { seq: c.length - 1, hash: entryHash(c.at(-1)!), genesis: entryHash(c[0]!) };
  };
  const reply = (req: HttpRequest): unknown => {
    const m = /\/v1\/workspaces\/([^/]+)\/lock(\/requests(?:\/([^/?]+))?)?(\?.*)?$/.exec(req.url);
    if (!m) return undefined;
    const ws = decodeURIComponent(m[1]!);
    const body = req.body ? JSON.parse(new TextDecoder().decode(req.body)) : null;
    if (m[2]) {
      if (req.method === "GET") return { requests: requests.get(ws) ?? [] };
      if (req.method === "DELETE") {
        requests.set(ws, (requests.get(ws) ?? []).filter((r) => r.base !== decodeURIComponent(m[3]!)));
        return { ok: true };
      }
      asked.push(ws);
      const r = { base: body.base, sub: "s1", email: "a@x.com", kind: body.kind, label: body.label, sign_key: body.sign_key, code: shortCode(body.base), created_at: 1000 };
      requests.set(ws, [...(requests.get(ws) ?? []).filter((x) => x.base !== body.base), r]);
      return r;
    }
    if (req.method === "GET") {
      const after = Number(new URL(req.url).searchParams.get("after") ?? -1);
      return { head: head(ws), entries: (chains.get(ws) ?? []).filter((e) => e.seq > after) };
    }
    for (const e of body.entries as Entry[]) {
      chains.set(ws, [...(chains.get(ws) ?? []), e]);
      posted.push({ ws, kind: e.kind, id: (e.body as { id?: string }).id });
    }
    return { ok: true };
  };
  return { chains, requests, posted, asked, head, reply };
}

/// A core on an app's host reaching `ws` (W) and `w2` (日常), each with its lock in the cloud; `before` changes the host.
async function rig(locks: (signer: Signer) => Record<string, Entry>, before?: (host: FakeHost) => void) {
  const cloud = lockCloud();
  const s = await started(undefined, 0, undefined, (x) => {
    x.host.appKeys = true;
    const signer = Effect.runSync(Signer.make(x.host));
    for (const [ws, g] of Object.entries(locks(signer))) cloud.chains.set(ws, [g]);
    x.cloud.also = { name: "W", role: "owner", lock: cloud.head("ws"), lock_requests: 0 };
    x.cloud.more = [{ id: "w2", name: "日常", emoji: "☀️", role: "owner", lock: cloud.head("w2"), lock_requests: 0 }];
    stationReplies(x.host, cloud.reply);
    before?.(x.host);
  });
  // This device's base key, as its mesh's (the fixture reaches its station another way, with no mesh).
  s.core.inner.mesh = () => Effect.succeed({ deviceId: () => ME } as never);
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
  const ask = async (name: string, params: Record<string, unknown>): Promise<any> => {
    const n = ++id;
    call(s.core, ui, n, name, params);
    for (let i = 0; i < 4000 && !done.has(n); i++) {
      await s.host.time.pass(10);
      take();
    }
    const a = done.get(n);
    if (!a) throw new Error(`${name}: no answer`);
    await s.host.time.pass(100);
    take();
    if ("error" in a) throw Object.assign(new Error((a.error as { message: string }).message), { code: (a.error as { code: string }).code });
    return a.ok;
  };
  const watch = async (topic: Record<string, unknown>) => {
    const n = ++id;
    subscribe(s.core, ui, n, topic as never);
    await s.host.time.pass(500);
    take();
    return async () => {
      await s.host.time.pass(200);
      take();
      return values.get(n) as any;
    };
  };
  return { ...s, cloud, ask, watch };
}

const phoneRequest = { base: PHONE, sub: "s2", email: "b@x.com", kind: "app", label: "Pixel 8", sign_key: null, code: shortCode(PHONE), created_at: 1500 };

test("a device waiting in two workspaces is put up once, naming both, and approved in both with its one code", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true), w2: genesis("w2", me, true) }));
  const prompts = await r.watch({ topic: "lockPrompts" });
  assert.deepEqual((await prompts()).waiting, [], "nobody waits yet");
  // The phone asks in both: the workspaces' views say one waits in each.
  r.cloud.requests.set("ws", [phoneRequest]);
  r.cloud.requests.set("w2", [phoneRequest]);
  r.core.inner.data.set({ topic: "workspace", workspace: "ws" }, { ...(r.core.inner.data.shared({ topic: "workspace", workspace: "ws" }) as object), lock_requests: 1 });
  r.core.inner.data.set({ topic: "workspace", workspace: "w2" }, { ...(r.core.inner.data.shared({ topic: "workspace", workspace: "w2" }) as object), lock_requests: 1 });
  const v = await prompts();
  assert.equal(v.waiting.length, 1, "one device, though it waits in two workspaces");
  assert.equal(v.prompt?.device, PHONE, "put up, wherever this device is");
  assert.equal(v.prompt?.code, shortCode(PHONE));
  assert.deepEqual(v.prompt?.workspaces.map((w: { id: string; name: string }) => [w.id, w.name]), [["ws", "W"], ["w2", "日常"]], "each workspace named");
  assert.equal(v.prompt?.workspaces[1].emoji, "☀️");
  // Closed by hand: not put up again, still waiting.
  await r.ask("lockPrompt.shown", { device: PHONE });
  const closed = await prompts();
  assert.equal(closed.prompt ?? null, null);
  assert.equal(closed.waiting.length, 1);
  // A wrong code approves nothing anywhere.
  await assert.rejects(r.ask("lockPrompt.confirm", { device: PHONE, code: "AAA-AAA" }), (e: { code: string }) => e.code === "invalid_params");
  assert.equal(r.cloud.posted.length, 0);
  await r.ask("lockPrompt.confirm", { device: PHONE, code: shortCode(PHONE) });
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE], ["w2", "device", PHONE]], "approved in both");
  assert.deepEqual([r.cloud.requests.get("ws"), r.cloud.requests.get("w2")], [[], []], "no longer waiting anywhere");
  assert.deepEqual((await prompts()).waiting, []);
});

test("a device approves only where it is trusted: a workspace whose lock leaves it out is not among the prompt's", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true), w2: genesis("w2", elsewhere(), false) }));
  const prompts = await r.watch({ topic: "lockPrompts" });
  r.cloud.requests.set("ws", [phoneRequest]);
  r.cloud.requests.set("w2", [phoneRequest]);
  r.core.inner.data.set({ topic: "workspace", workspace: "ws" }, { ...(r.core.inner.data.shared({ topic: "workspace", workspace: "ws" }) as object), lock_requests: 1 });
  r.core.inner.data.set({ topic: "workspace", workspace: "w2" }, { ...(r.core.inner.data.shared({ topic: "workspace", workspace: "w2" }) as object), lock_requests: 2 });
  const v = await prompts();
  assert.deepEqual(v.prompt?.workspaces.map((w: { id: string }) => w.id), ["ws"]);
  await r.ask("lockPrompt.deny", { device: PHONE });
  assert.deepEqual(r.cloud.requests.get("ws"), [], "turned down where it waited on this device");
  assert.ok(r.cloud.requests.get("w2")?.some((x) => x.base === PHONE), "not where this device does not approve");
});

test("a device not in the lock waits and asks only by hand; one that cannot keep its key says its request did not go", async () => {
  let broken = true;
  const r = await rig((_me) => ({ ws: genesis("ws", elsewhere(), false) }), (host) => {
    // No key kept yet, and the keychain refusing to keep one (a host whose `secure.*` does not work).
    const set = host.secureSet!;
    host.secureSet = (key: string, value: Uint8Array, opts: { user: boolean }) => (broken ? Effect.fail(new HostError("secure.set is not supported")) : set(key, value, opts));
    const get = host.secureGet!;
    host.secureGet = (key: string, opts: { user: boolean }) => (key === Signer.KEY ? Effect.succeed(null) : get(key, opts));
  });
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  await r.host.time.pass(15_000);
  const v = await lock();
  assert.deepEqual(r.cloud.asked, [], "nothing asked by itself");
  assert.equal(v.me.waiting, true, "its page shows instead of the workspace's");
  assert.equal(v.me.asked, false);
  // A station refusing it asks nothing either.
  hooks.lockRefused!(r.core.inner, "ws", "st");
  await r.host.time.pass(5_000);
  assert.deepEqual(r.cloud.asked, []);
  // Asked by hand: the key cannot be kept, said; nothing reached the cloud.
  await assert.rejects(r.ask("lock.request", { workspace: "ws" }), (e: { code: string }) => e.code === "lock_key");
  assert.deepEqual(r.cloud.asked, []);
  assert.match((await lock()).me.failed, /secure\.set is not supported/);
  // Again once the keychain keeps it: sent, and what kept it is past.
  broken = false;
  await r.ask("lock.request", { workspace: "ws" });
  assert.deepEqual(r.cloud.asked, ["ws"]);
  const after = await lock();
  assert.equal(after.me.failed ?? null, null);
  assert.equal(after.me.asked, true);
});

test("a station's refusal names the workspace and the code to approve, where the device is not in that workspace's lock", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true), w2: genesis("w2", elsewhere(), false) }));
  await r.watch({ topic: "lock", workspace: "w2" });
  const said = hooks.lockRefused!(r.core.inner, "w2", "st2");
  assert.equal(said?.code, "lock_unconfirmed");
  assert.match(said!.message, /日常/);
  assert.ok(said!.message.includes(shortCode(ME)), said!.message);
  // Not asked again until its lock moves on, saying the same.
  const again = hooks.lockWaiting!(r.core.inner, "w2", "st2");
  assert.equal(again?.message, said!.message);
});


test("an approval is done once the cloud keeps it, not once every station of the lock has heard (one offline held it up)", async () => {
  // `st` is protected, and never answers what it is brought: offline.
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [{ key: "st", name: "studio" }]) }), (host) => {
    stationLater(host, (req) => (req.method === "POST" && req.url.endsWith("/admin/api/lock") ? new Promise(() => {}) : undefined));
  });
  const prompts = await r.watch({ topic: "lockPrompts" });
  r.cloud.requests.set("ws", [phoneRequest]);
  r.core.inner.data.set({ topic: "workspace", workspace: "ws" }, { ...(r.core.inner.data.shared({ topic: "workspace", workspace: "ws" }) as object), lock_requests: 1 });
  assert.equal((await prompts()).prompt?.device, PHONE);
  await r.ask("lockPrompt.confirm", { device: PHONE, code: shortCode(PHONE) });
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
  assert.deepEqual(r.cloud.requests.get("ws"), [], "its request gone with it");
  assert.deepEqual((await prompts()).waiting, []);
});

test("a station that refuses this device though the lock names it has not heard yet: tried again shortly, not held", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  const woke: string[] = [];
  r.core.inner.stations.cameOnline = (address: string) => void woke.push(address);
  const said = hooks.lockRefused!(r.core.inner, "ws", "st");
  assert.equal(said?.code, "lock_unconfirmed");
  assert.equal(hooks.lockWaiting!(r.core.inner, "ws", "st"), null, "asked again as any station would be");
  await r.host.time.pass(BEHIND_MS - 10);
  assert.deepEqual(woke, []);
  await r.host.time.pass(20);
  assert.deepEqual(woke, ["ws/st"], "and woken soon to be");
  // Refused again and again: a few more tries, each later, then no more for this head.
  for (let i = 1; i < 8; i++) {
    hooks.lockRefused!(r.core.inner, "ws", "st");
    await r.host.time.pass(BEHIND_MS * (i + 1) + 10);
  }
  assert.equal(woke.length, BEHIND_TRIES, "as often as BEHIND_TRIES");
});

test("a hello brings what put this device in the lock lately, for a station that has not heard of it yet", async () => {
  const owner = elsewhere();
  const r = await rig(() => ({ ws: genesis("ws", owner, false) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  const g = r.cloud.chains.get("ws")![0]!;
  const head = (e: Entry) => ({ seq: e.seq, hash: entryHash(e), genesis: entryHash(g) });
  const sign = (e: ReturnType<typeof next>): Entry => ({ ...e, sig: { key: owner.id, alg: "Ed25519", sig: owner.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } });
  // Not in the lock: nothing to bring.
  assert.equal(r.core.inner.cloudSync.carry!("ws"), null);
  const approval = sign(next("ws", head(g), r.host.nowMs() / 1000, "device", { id: ME, sub: "s1", kind: "app", label: "this" }));
  const another = sign(next("ws", head(approval), r.host.nowMs() / 1000, "device", { id: PHONE, sub: "s2", kind: "app", label: "phone" }));
  r.cloud.chains.set("ws", [g, approval, another]);
  r.core.inner.data.put("lock", "ws", { head: head(another), entries: [g, approval, another], requests: [] });
  assert.deepEqual(r.core.inner.cloudSync.carry!("ws"), [approval, another], "from the one that put it in on");
  // Put in long since: every station has heard by now.
  const old = sign(next("ws", head(g), r.host.nowMs() / 1000 - 8 * 86400, "device", { id: ME, sub: "s1", kind: "app", label: "this" }));
  r.cloud.chains.set("ws", [g, old]);
  r.core.inner.data.put("lock", "ws", { head: head(old), entries: [g, old], requests: [] });
  assert.equal(r.core.inner.cloudSync.carry!("ws"), null);
});

test("an approval the cloud answers too many requests for is asked again a while later, not failed at once", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true) }));
  const prompts = await r.watch({ topic: "lockPrompts" });
  r.cloud.requests.set("ws", [phoneRequest]);
  r.core.inner.data.set({ topic: "workspace", workspace: "ws" }, { ...(r.core.inner.data.shared({ topic: "workspace", workspace: "ws" }) as object), lock_requests: 1 });
  assert.equal((await prompts()).prompt?.device, PHONE);
  // The account's budget for this minute spent (by its other devices): the next two asks are turned away.
  let limited = 2;
  stationReplies(r.host, (req) => (req.url.includes("/lock") && limited-- > 0 ? status(429, { error: "rate_limited" }) : r.cloud.reply(req)));
  await r.ask("lockPrompt.confirm", { device: PHONE, code: shortCode(PHONE) });
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
});

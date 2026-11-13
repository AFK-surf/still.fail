// The workspace lock's tests' rig (lock-prompts.test.ts, lock-pair.test.ts): a core on an app's host, its locks at a cloud
// that keeps chains and requests, its device's base key ME.
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect, Queue } from "effect";
import { apply as applyOps } from "../src/delta.ts";
import { CoreError } from "../src/error.ts";
import type { HttpRequest } from "../src/host.ts";
import type { StationWire } from "../src/station/wire.ts";
import { type Entry, Signer, entryHash, next, shortCode } from "../src/lock.ts";
import { type InForce, bodyHash, inForce, made, wsTag } from "../src/lock-moved.ts";
import type { FakeHost } from "../src/testing.ts";
import { base64url as toB64url, hex, utf8 } from "../src/util.ts";
import type { Duplex } from "../src/views/pair.ts";
import { call, subscribe } from "./helpers.ts";
import { Status, started, stationReplies } from "./station-fixture.ts";

export const unhex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));
/// The base key of the testing core's device (its mesh's).
export const ME = "ab".repeat(32);
/// A phone of the member s2's, waiting.
export const PHONE = "cd".repeat(32);

/// This fixture reaches its station through fetch, not a mesh; background connection attempts fail normally.
export const withoutMesh = (device: string) => Effect.succeed({
  deviceId: () => device,
  link: () => Effect.fail(new CoreError("unsupported", "this fixture has no mesh")),
} as never);

/// A workspace's lock: s1 the owner, `signer` (this device's key, when it is in) their app; s2 a member; `more` devices.
export function genesis(ws: string, signer: { id: string; signBytes(b: Uint8Array): string }, withMe: boolean, stations: { key: string; name: string }[] = [], cloudKeys: unknown = {}, me = ME, more: Record<string, unknown>[] = []): Entry {
  const e = next(ws, null, 1000, "genesis", {
    owner: "s1", origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: cloudKeys,
    members: [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "s2", email: "b@x.com", role: "member" }],
    devices: [...(withMe ? [{ id: me, sub: "s1", kind: "app", label: "this", sign_key: signer.id }] : []), ...more],
    passkeys: [], stations, gateways: [],
  });
  return { ...e, sig: { key: signer.id, alg: "Ed25519", sig: signer.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } };
}

/// A key of nobody's on this device: the owner's elsewhere.
export function elsewhere() {
  const seed = new Uint8Array(32).fill(9);
  return { id: `ed25519:${hex(ed25519.getPublicKey(seed))}`, signBytes: (b: Uint8Array) => hex(ed25519.sign(b, seed)) };
}

/// A cloud keeping each workspace's chain and its waiting devices, as /v1/workspaces/:ws/lock… answers; and, where
/// `devices` has the workspace's, the devices that asked it for credentials (/v1/workspaces/:ws/devices).
export function lockCloud() {
  const chains = new Map<string, Entry[]>();
  const requests = new Map<string, Record<string, unknown>[]>();
  const devices = new Map<string, Record<string, unknown>[]>();
  const posted: { ws: string; kind: string; id?: string }[] = [];
  const asked: string[] = [];
  // How many of the next posts of entries are kept but their answer lost on the way back (a gateway's 502).
  const lose = { posts: 0 };
  const head = (ws: string) => {
    const c = chains.get(ws) ?? [];
    return c.length === 0 ? null : { seq: c.length - 1, hash: entryHash(c.at(-1)!), genesis: entryHash(c[0]!) };
  };
  const reply = (req: HttpRequest): unknown => {
    const d = /\/v1\/workspaces\/([^/]+)\/devices$/.exec(req.url);
    if (d && req.method === "GET") {
      const list = devices.get(decodeURIComponent(d[1]!));
      return list ? { devices: list } : undefined;
    }
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
    if (lose.posts > 0) {
      lose.posts--;
      return new Status(502, { error: "bad gateway" });
    }
    return { ok: true };
  };
  return { chains, requests, devices, posted, asked, lose, head, reply };
}

/// A core on an app's host reaching `ws` (W) and `w2` (日常), each with its lock in the cloud; `before` changes the host.
/// `station`: the id of `ws`'s station (station-fixture.ts's "st" unless given; one the lock names is an iroh id), or of
/// each of its stations. `seen`: those of them the control plane saw just now (`last_seen` the start's time), the others
/// never seen (`null`). `wire`: how its stations are reached (the host's fetch, HostWire, unless given).
/// `w2`: the stations the account's other workspace (`w2`) lists, none by default. `also`: more of `ws`'s view (its
/// `members`).
export async function rig(locks: (signer: Signer) => Record<string, Entry>, before?: (host: FakeHost) => void, station?: string | string[], seen: readonly string[] = [], wire?: (host: FakeHost) => StationWire, w2: readonly string[] = [], also: Record<string, unknown> = {}) {
  const ids = station === undefined ? [] : typeof station === "string" ? [station] : station;
  const cloud = lockCloud();
  const s = await started(undefined, 0, wire, (x) => {
    x.host.appKeys = true;
    const signer = Effect.runSync(Signer.make(x.host));
    for (const [ws, g] of Object.entries(locks(signer))) cloud.chains.set(ws, [g]);
    x.cloud.also = { name: "W", role: "owner", lock: cloud.head("ws"), lock_requests: 0, ...(ids.length > 0 ? { stations: ids.map((id, i) => ({ id, name: i === 0 ? "studio" : `studio ${i + 1}`, online: true, last_seen: seen.includes(id) ? Math.floor(x.host.nowMs() / 1000) : null })) } : {}), ...also };
    x.cloud.more = [{ id: "w2", name: "日常", emoji: "☀️", role: "owner", lock: cloud.head("w2"), lock_requests: 0, ...(w2.length > 0 ? { stations: w2.map((id, i) => ({ id, name: `daily ${i + 1}`, online: true, last_seen: null })) } : {}) }];
    stationReplies(x.host, cloud.reply);
    before?.(x.host);
  });
  // This device's base key, as its mesh's (the fixture reaches its station another way, with no mesh).
  s.core.inner.mesh = () => withoutMesh(ME);
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
    await s.host.time.passUntil(40_000, () => (take(), done.has(n)));
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

/// The cloud's grant key, as the lock names it, and credentials it signs.
export function grant() {
  const seed = new Uint8Array(32).fill(7);
  const jwk = { kty: "OKP", crv: "Ed25519", kid: "k1", x: toB64url(ed25519.getPublicKey(seed)) };
  const credential = (ws: string, device: string, sub: string, exp = 4102444800, role = "member") => {
    const head = toB64url(utf8(JSON.stringify({ alg: "EdDSA", typ: "stillfail-member+jwt", kid: "k1" })));
    const body = toB64url(utf8(JSON.stringify({ iss: "stillfail-cloud", sub, email: `${sub}@x.com`, name: sub === "s2" ? "李二" : sub, ws, role, device, exp })));
    return `${head}.${body}.${toB64url(ed25519.sign(utf8(`${head}.${body}`), seed))}`;
  };
  return { keys: { keys: [jwk] }, credential };
}

/// Two ends of a stream of lines.
export async function pipe(): Promise<[Duplex, Duplex]> {
  const a = await Effect.runPromise(Queue.unbounded<unknown>());
  const b = await Effect.runPromise(Queue.unbounded<unknown>());
  const end = (mine: Queue.Queue<unknown>, theirs: Queue.Queue<unknown>): Duplex => ({
    send: (m) => Effect.sync(() => void Queue.offerUnsafe(theirs, JSON.parse(JSON.stringify(m)))),
    next: () => Queue.take(mine) as Effect.Effect<any>,
    close: () => void Queue.offerUnsafe(theirs, null),
  });
  return [end(a, b), end(b, a)];
}

/// What a station of a moved workspace gives a device (station/src/mesh/serve.ts `givesDevice`, cloud/state.ts
/// `givenTo`), for a fake station's `/lock/logs` and `/lock/bodies`: only where the state in force made of what it keeps
/// (`chain` its chain, `logs` the person logs, `bodies`) names the device (`base`, its base key), on or off; none while
/// it waits, nor to a device it does not name (that one is refused at its hello, `leftOf`). A chain not moved: true.
export function givesTo(ws: string, chain: readonly Entry[], logs: readonly (readonly Entry[])[], bodies: readonly unknown[], nowMs: number, base: string): boolean {
  const f = stationState(ws, chain, logs, bodies, nowMs);
  return f.said === "chain" || ((f.said === "on" || f.said === "off") && f.f.devices.has(base));
}

/// Whether a station keeping the person logs `logs` takes the body `b` of `ws` (station/src/cloud/lock-bodies.ts: only
/// against an entry kept that commits to it under the workspace's tag).
export function committed(ws: string, logs: readonly (readonly Entry[])[], b: unknown): boolean {
  const h = bodyHash(b);
  if (h === null || (b as { ws?: unknown } | null)?.ws !== ws) return false;
  return logs.some((l) => l.length > 0 && l.some((e) => e.kind === "ws" && (e.body as { t?: unknown; h?: unknown } | null)?.h === h && (e.body as { t?: unknown }).t === wsTag(ws, entryHash(l[0]!))));
}

/// The state in force a fake station keeps (the rules' own, as src/lock-moved.ts `inForce` makes it), not counted as
/// this device's making of it (`made`, which tests of the core's own making read).
export function stationState(ws: string, chain: readonly Entry[], logs: readonly (readonly Entry[])[], bodies: readonly unknown[], nowMs: number): InForce {
  const n = made.count;
  try {
    return inForce(ws, chain, new Map(logs.filter((l) => l.length > 0).map((l) => [entryHash(l[0]!), l])), bodies, nowMs);
  } finally {
    made.count = n;
  }
}

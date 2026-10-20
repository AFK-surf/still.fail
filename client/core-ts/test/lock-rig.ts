// The workspace lock's tests' rig (lock-prompts.test.ts, lock-pair.test.ts): a core on an app's host, its locks at a cloud
// that keeps chains and requests, its device's base key ME.
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
import { apply as applyOps } from "../src/delta.ts";
import type { HttpRequest } from "../src/host.ts";
import { type Entry, Signer, entryHash, next, shortCode } from "../src/lock.ts";
import type { FakeHost } from "../src/testing.ts";
import { hex, utf8 } from "../src/util.ts";
import { call, subscribe } from "./helpers.ts";
import { started, stationReplies } from "./station-fixture.ts";

export const unhex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));
/// The base key of the testing core's device (its mesh's).
export const ME = "ab".repeat(32);
/// A phone of the member s2's, waiting.
export const PHONE = "cd".repeat(32);

/// A workspace's lock: s1 the owner, `signer` (this device's key, when it is in) their app; s2 a member.
export function genesis(ws: string, signer: { id: string; signBytes(b: Uint8Array): string }, withMe: boolean, stations: { key: string; name: string }[] = [], cloudKeys: unknown = {}, me = ME): Entry {
  const e = next(ws, null, 1000, "genesis", {
    owner: "s1", origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: cloudKeys,
    members: [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "s2", email: "b@x.com", role: "member" }],
    devices: withMe ? [{ id: me, sub: "s1", kind: "app", label: "this", sign_key: signer.id }] : [],
    passkeys: [], stations, gateways: [],
  });
  return { ...e, sig: { key: signer.id, alg: "Ed25519", sig: signer.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } };
}

/// A key of nobody's on this device: the owner's elsewhere.
export function elsewhere() {
  const seed = new Uint8Array(32).fill(9);
  return { id: `ed25519:${hex(ed25519.getPublicKey(seed))}`, signBytes: (b: Uint8Array) => hex(ed25519.sign(b, seed)) };
}

/// A cloud keeping each workspace's chain and its waiting devices, as /v1/workspaces/:ws/lock… answers.
export function lockCloud() {
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
export async function rig(locks: (signer: Signer) => Record<string, Entry>, before?: (host: FakeHost) => void) {
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


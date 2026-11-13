// A workspace whose chain moved to its people's own logs (station/test/lock-roster4-model.ts D1, D2, D5), made with
// real keys for the station's own code (lock-bodies.test.ts, lock-moved.test.ts): its old chain (owner alice, bob an
// admin, carol a member; two stations), each person's own log, the statements alice's log (the root) and bob's say as
// `ws {t, h}` entries with their bodies apart, and the chain's `moved {root}`.
import { createHash, generateKeyPairSync, sign as nodeSign, type KeyObject } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type Entry, bodyHash, endpointBytes, entryHash, signedBytes, wsTag } from "../src/cloud/lock.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { lockPartRoute } from "../src/mesh/serve.ts";

export const WS = "01HMOVEDMOVEDMOVEDMOVEDMOV";
export const WS2 = "01HOTHEROTHEROTHEROTHEROTH";

const hexOf = (k: KeyObject) => Buffer.from(k.export({ format: "jwk" }).x as string, "base64url").toString("hex");
export function ed() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const hex = hexOf(publicKey);
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Buffer) => nodeSign(null, bytes, privateKey).toString("hex") };
}
export type Key = ReturnType<typeof ed>;
export const signed = (e: Omit<Entry, "sig">, key: Key): Entry => ({ ...e, sig: { key: key.id, alg: "Ed25519", sig: key.sign(signedBytes(entryHash(e as Entry))) } });

/// A device: its key on its person's log (which signs that log alone), the key it signs a workspace's things with
/// (`signer`: a chain's entries, a vault's versions and certificates; its log says it as `sign_key`) and its base key
/// (its id). Three keys, as a device has: one key for the first two hid that a moved state named a device by the
/// wrong one (2026-11-13).
export type Dev = { key: Key; signer: Key; base: Key };
export const dev = (): Dev => ({ key: ed(), signer: ed(), base: ed() });
let salts = 0;
const salt = () => createHash("sha256").update(`salt ${salts++} ${Math.random()}`).digest("hex").slice(0, 32);

/// A person's own log, as kept by them: entries signed after its head, and the bodies of the statements they made.
export class Log {
  readonly sub: string;
  readonly app: Dev;
  entries: Entry[];
  /// The statements' bodies of each workspace, by their hash, in the order made.
  bodies = new Map<string, any>();
  at = 1000;
  constructor(sub: string, app: Dev = dev()) {
    this.sub = sub;
    this.app = app;
    this.entries = [signed({ v: 1, ws: `person:${sub}`, seq: 0, prev: null, at: this.at, kind: "genesis", body: { sub, device: { key: app.key.id, id: app.base.hex, label: `${sub}'s app`, sign_key: app.signer.id } } }, app.key)];
  }
  get genesis() {
    return entryHash(this.entries[0]!);
  }
  get head() {
    return this.entries.at(-1)!;
  }
  /// One more entry after the head, signed by `by` (the first device by default).
  add(kind: string, body: unknown, by: Key = this.app.key, at = this.at): Entry {
    const e = signed({ v: 1, ws: `person:${this.sub}`, seq: this.head.seq + 1, prev: entryHash(this.head), at, kind, body }, by);
    this.entries.push(e);
    return e;
  }
  /// A statement of workspace `ws` (`kind` and what it says): its body, naming the latest statement of the tag before
  /// it (`prev`), and its commitment after the head. Its body's hash.
  say(kind: string, what: Record<string, unknown>, ws = WS): { body: any; h: string; entry: Entry } {
    const t = wsTag(ws, this.genesis);
    let prev: string | null = null;
    for (let i = this.entries.length - 1; i >= 0; i--) {
      const e = this.entries[i]!;
      if (e.kind === "ws" && e.body.t === t) {
        prev = e.body.h;
        break;
      }
    }
    const body = { ws, kind, ...what, prev, salt: salt() };
    const h = bodyHash(body)!;
    this.bodies.set(h, body);
    return { body, h, entry: this.add("ws", { t, h }) };
  }
}

/// The world: the old chain's people and stations, their logs, and the old chain up to its `moved` (not yet given).
export function world(ws = WS) {
  const alice = new Log("alice"), bob = new Log("bob"), carol = new Log("carol");
  const stations = [ed(), ed(), ed()];
  const body = {
    owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: [["alice", "owner"], ["bob", "admin"], ["carol", "member"]].map(([sub, role]) => ({ sub, email: `${sub}@x`, role })),
    devices: [alice, bob, carol].map((l) => ({ id: l.app.base.hex, sub: l.sub, kind: "app", label: l.sub, sign_key: l.app.signer.id })),
    passkeys: [], stations: stations.slice(0, 2).map((s, i) => ({ key: s.hex, name: `s${i}` })), gateways: [],
  };
  const first = signed({ v: 1, ws, seq: 0, prev: null, at: 1000, kind: "genesis", body }, alice.app.signer);
  const moved = signed({ v: 1, ws, seq: 1, prev: entryHash(first), at: 1000, kind: "moved", body: { root: alice.genesis } }, alice.app.signer);
  const settings = { origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] } };
  return { ws, alice, bob, carol, stations, first, moved, settings };
}
export type World = ReturnType<typeof world>;

/// The statements of a handover: alice opens the workspace (D3), lets bob in as an admin and carol as a member by
/// their logs, and names stations s0 and s1; bob names no one yet.
export function handover(w: World) {
  const open = w.alice.say("open", { ...w.settings, email: "alice@x" }, w.ws);
  const bob = w.alice.say("member", { sub: "bob", email: "bob@x", lock: w.bob.genesis, role: "admin" }, w.ws);
  const carol = w.alice.say("member", { sub: "carol", email: "carol@x", lock: w.carol.genesis, role: "member" }, w.ws);
  const s0 = w.alice.say("station", { key: w.stations[0]!.hex }, w.ws);
  const s1 = w.alice.say("station", { key: w.stations[1]!.hex }, w.ws);
  return { open, bob, carol, s0, s1 };
}

/// Station `i` of the workspace, its old chain pinned (and, when `moved`, the chain's `moved` taken).
export function station(w: World, i = 0, moved = true): Cloud {
  const data = mkdtempSync(join(tmpdir(), "lock-moved-"));
  writeState(data, {
    origin: "https://app.still.fail", station: w.stations[i]!.hex, workspace: w.ws, workspace_name: "Team", name: `s${i}`, relay_url: "", relay_urls: [],
    grant_keys: { keys: [] }, peers: w.stations.map((s, j) => ({ id: s.hex, name: `s${j}` })), revocations: [],
  });
  const c = new Cloud(data, false);
  c.takeLock([w.first]);
  if (moved) c.takeLock([w.first, w.moved], null, true);
  return c;
}

/// What a device brings a station: its person's log and the bodies of its statements, as its app device brings them
/// (POST /lock/person on a connection of that device's in `ws`, mesh/serve.ts `lockPartRoute`: the log taken as its
/// person's, the bodies as the rules take them). Its answer's status and body.
export function bring(c: Cloud, log: Log, bodies = true, ws = WS): [number, unknown] {
  const said = { chain: log.entries, ...(bodies ? { bodies: [...log.bodies.values()].filter((b) => b.ws === ws) } : {}) };
  return lockPartRoute(c, "person", "POST", Buffer.from(JSON.stringify(said)), viewerOf(log.sub, log.app, "member", ws) as never);
}

/// A member's device as a connection of it shows itself: its credential's viewer, its base key's proof of the endpoint.
export const viewerOf = (sub: string, d: { base: Key }, role = "member", workspace = WS) => {
  const endpoint = ed().hex;
  return { sub, email: `${sub}@x`, name: sub, role, workspace, device: endpoint, lockDevice: { base: d.base.hex, proof: d.base.sign(endpointBytes(workspace, endpoint)) } };
};

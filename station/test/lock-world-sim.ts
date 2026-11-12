// The workspace lock across a whole world, tested by its properties (run by lock-world-<n>.test.ts, a part each): the control plane, three
// stations (their own code: cloud.json and lock.json on disk, the presence socket's frames, the mesh's lock sync, what
// they tell devices of their locks, a device's hello) and the members' devices, each step drawn from a seed: an entry
// signed on a device and brought to the stations and the plane, a device connecting, a line cut or back, a station
// stopped or started, the plane holding back or forging, a device that was removed signing all the same. What goes over
// a line is held, reordered (each socket keeps its order) and lost with the line, as the seed says.
//
// The protocol is the one since 2026-11-09 (the root AGENTS.md, The cloud is the account system; client/core-ts
// src/views/lock.ts `Lock.append`): the locks are the stations'. Each device holds a chain of its own, brought up to date
// only as it reads a station (GET /lock, as the stations tell it their lock moved on, or as its line to one opens),
// keeping what each showed it and going by the rules' fork choice among it (since 2026-11-12, client/core-ts
// src/lock-keep.ts; before, it took only a chain that went on from the one it held). It signs after that chain, one
// entry at a time (since step 3b, views/lock.ts `Lock.append`'s turn), brings the whole chain to every station of the
// lock at once, each on its own line, and sends the entry to the plane beside it, waited on only where no station took
// it; taken is by hash. Nothing orders the entries: two devices signing after the same chain may each be taken first by
// another station. An entry of its own that lost its place (refused as not on a station's head, or left aside as it
// reads) it signs again after the head, by the core's rule and limits (`againOf`, AGAIN_MOST); and what it keeps that a
// station it reads lacks, each entry a station showed or took, it carries there with `keep` (views/lock.ts `carry`).
//
// After every step what must always hold is checked: every chain a station, the plane or a device holds checks out,
// nothing a forger made is in any of them or lets anyone in, nobody is let in whom the station's own chain does not
// name. At the end every station starts, the lines come back (the plane still holding back from some stations),
// whatever is on its way lands, and what must come about is checked: every station of the lock keeps the same chain
// (the same head), the plane too once one station reaches it; every device approved on it is let in at every station
// and every removed one at none; no device holds a chain no station keeps; no station keeps a lock turned off; none
// keeps what a removed device signed after a chain from before its removal. A failure is cut down to the fewest steps
// that still fail and says its seed: LOCK_WORLD_SEED=<seed> runs only that one (LOCK_WORLD_RUNS=<n> runs n seeds from
// 1); every failing seed is counted and named with the properties it broke. There are two workspaces, each its own
// lock: every station's home one, and one two of them joined.
//
// Until 2026-11-12 two stations that took different entries at the same place never came back to one chain (E1, E2,
// E5, E6 failed on many seeds). Since the stations keep every entry another keeper took and go by the fork choice
// (cloud/log-keep.ts), E1, E2 and E6 hold on every seed; and since the devices keep what they are shown and go by the
// same fork choice (step 3's reading, 2026-11-12), E3 holds but where a device holds an entry it signed that no station
// kept (it goes with signing again, the rest of step 3). The plane keeps what a station gives it of another branch by
// the same fork choice, as the cloud does (cloud/src/lock.ts `keepLockAt`, the station's presence.ts `planeParted`), so
// where it took the entry that lost first it comes to the stations' chain (2026-11-12). E4, the plane keeping an entry
// no station took, and E3 with it, went once the cloud's taking one no longer counted: what no station took is pending
// on the device that signed it, sent to the plane only once a station took it (step 3b, 2026-11-12). What still fails
// is in `KNOWN_SEEDS` and `KNOWN_TOLD` (`WHY`), and the tests pass when exactly that fails: anything else that fails
// fails them, and so does a known failure that holds now (take it out). The checks of every step stay hard: a wrong chain, a forger's entry or
// someone let in whom the chain does not name fails at once.
import assert from "node:assert/strict";
import { createPrivateKey, createPublicKey, sign as nodeSign } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { keepLockAt, LockAppendRefused } from "../../cloud/src/lock.ts";
import { type Entry, apply, endpointBytes, entryHash, fold, lockChain, signedBytes } from "../src/cloud/lock.ts";
import { keep } from "../src/cloud/log-keep.ts";
import { applyState, planeTeller } from "../src/cloud/presence.ts";
import { Cloud, readLock, writeState } from "../src/cloud/state.ts";
import type { Admitted } from "../src/mesh/credential.ts";
import { tellLocks } from "../src/mesh/lock-events.ts";
import { answerLock, followLock } from "../src/mesh/lock-sync.ts";
import { PersonChains } from "../src/mesh/person-chains.ts";
import { inLockBringing, lockRoute } from "../src/mesh/serve.ts";

const WS = "01HWORLDWORLDWORLDWORLDWOR";
/// The workspace s0 and s1 joined besides their home one.
const WB = "01HWORLDWORLDWORLDWORLDWOB";
const ORIGIN = "https://app.still.fail";
/// When a world starts (unix ms); its clock moves only as its steps say.
const START = Date.UTC(2026, 10, 4, 9, 0, 0);
/// How long a device's call waits for a station to take what it brought before it waits on the plane instead
/// (client/core-ts/src/views/lock.ts TAKEN_MS).
const TAKEN_MS = 15_000;
/// How much of a station's chain its refusal of a device tells (station/src/mesh/serve.ts REFUSAL_ENTRIES_BYTES).
const REFUSAL_ENTRIES_BYTES = 16 * 1024;

/// A seeded random (mulberry32): the same seed, the same draws.
class Rng {
  #s: number;
  constructor(seed: number) {
    this.#s = seed >>> 0;
  }
  next(): number {
    let t = (this.#s += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  int(n: number): number {
    return Math.floor(this.next() * n);
  }
}

/// An Ed25519 key made from `n`, the same every run: a device's base key, an app's signing key, a station's.
function key(n: number) {
  const seed = Buffer.alloc(32);
  seed.writeUInt32BE(n, 28);
  const privateKey = createPrivateKey({ key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]), format: "der", type: "pkcs8" });
  const hex = Buffer.from(createPublicKey(privateKey).export({ format: "jwk" }).x as string, "base64url").toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Buffer) => nodeSign(null, bytes, privateKey).toString("hex") };
}
type Key = ReturnType<typeof key>;

const signed = (e: Omit<Entry, "sig">, by: Key): Entry => ({ ...e, sig: { key: by.id, alg: "Ed25519", sig: by.sign(signedBytes(entryHash(e as Entry))) } });
const after = (chain: Entry[], at: number, kind: string, body: unknown): Omit<Entry, "sig"> => {
  const head = chain.at(-1)!;
  return { v: 1, ws: head.ws, seq: head.seq + 1, prev: entryHash(head), at, kind, body };
};

/// The people: alice the owner, bob an admin, carol a member, each with an app that signs. Devices they may approve:
/// each person's two more (a phone, a laptop), each with a signing key of its own, which signs only once it was taken
/// out again (`stale`). Eve is nobody's: only a forger names her device. Each spare has a device of its person's that
/// only it approves, after it was removed (`mal`).
const PEOPLE = [
  { sub: "alice", role: "owner" },
  { sub: "bob", role: "admin" },
  { sub: "carol", role: "member" },
] as const;
const signers = PEOPLE.map((p, i) => ({ ...p, app: key(100 + i), signer: key(200 + i) }));
const spare = PEOPLE.flatMap((p, i) => [0, 1].map((j) => ({ sub: p.sub as string, base: key(300 + i * 10 + j), signer: key(400 + i * 10 + j), name: `${p.sub}'s ${j === 0 ? "phone" : "laptop"}` })));
const mal = spare.map((d, j) => ({ sub: d.sub, base: key(600 + j), name: `${d.name}'s accomplice` }));
const eve = { sub: "carol", base: key(900) };
const eveKey = key(901);
const stationKeys = [0, 1, 2].map((i) => key(500 + i));
const N = stationKeys.length;

/// Every device a station may be asked to let in, in one order (a step picks by its place).
const everyDevice = [...spare, { ...eve, name: "eve's" }, ...signers.map((s) => ({ sub: s.sub as string, base: s.app, name: `${s.sub}'s app` })), ...mal];

/// Who signed an entry, in words.
const signerName = (e: Entry): string => {
  const k = e.sig?.key;
  return signers.find((s) => s.signer.id === k)?.sub ?? spare.find((d) => d.signer.id === k)?.name ?? (k === eveKey.id ? "a forger" : "someone");
};
const deviceName = (hex: unknown): string => everyDevice.find((d) => d.base.hex === hex)?.name ?? `device ${String(hex).slice(0, 8)}`;
/// One entry in words: its place, who signed it, what it says, its hash's start.
const said = (e: Entry): string => {
  const b = e.body as any;
  const what = e.kind === "device" || e.kind === "device.remove" ? `${e.kind} ${deviceName(b?.id)}` : e.kind === "member" ? `member ${b?.sub} ${b?.role}` : e.kind.startsWith("station") ? `${e.kind} s${stationKeys.findIndex((k) => k.hex === b?.key)}` : e.kind;
  return `${e.seq} ${signerName(e)}: ${what} #${entryHash(e).slice(0, 6)}`;
};
const chainSaid = (c: Entry[]): string => (c.length === 0 ? "no lock" : `#${entryHash(c[0]!).slice(0, 6)} [${c.slice(1).map(said).join("; ")}]`);

const genesisOf = (ws: string, members: number[]) => signed({
  v: 1, ws, seq: 0, prev: null, at: START / 1000, kind: "genesis", body: {
    owner: "alice", origins: [ORIGIN], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: PEOPLE.map((p) => ({ sub: p.sub, email: `${p.sub}@x`, role: p.role })),
    devices: signers.map((s) => ({ id: s.app.hex, sub: s.sub, kind: "app", label: s.sub, sign_key: s.signer.id })),
    passkeys: [], stations: members.map((i) => ({ key: stationKeys[i]!.hex, name: `s${i}` })), gateways: [],
  },
}, signers[0]!.signer);

/// A workspace of the world: its stations, and its lock as the plane keeps it (`plane`), each it kept (`epochs`: turned
/// off and on again, a new one starts). What the world knows of it beside the plane: the geneses the owner signed that a
/// station took, in order (`opened`); those of a lock turned off, as a station or the plane took its `disable` (`off`);
/// what a removed device signed after a chain from before its removal (`stale`).
type Space = { ws: string; name: string; members: number[]; plane: Entry[]; planeAside: Entry[]; epochs: Entry[][]; opened: string[]; off: Set<string>; stale: Set<string> };
const spaces = (): Space[] =>
  ([[WS, "Team", [0, 1, 2]], [WB, "B", [0, 1]]] as const).map(([ws, name, members]) => {
    const g = genesisOf(ws, [...members]);
    return { ws, name, members: [...members], plane: [g], planeAside: [], epochs: [[g]], opened: [entryHash(g)], off: new Set<string>(), stale: new Set<string>() };
  });
/// A station's own name for a workspace: null for its home one.
const keyOf = (sp: Space) => (sp.ws === WS ? null : sp.ws);

/// One step, as drawn: what kind, and three numbers it picks with (each taken modulo what there is to pick from).
type Step = { k: number; a: number; b: number; c: number };
/// What the steps' kinds are, weighted by how often each comes.
const KINDS = ["deliver", "deliver", "deliver", "deliver", "deliver", "sign", "sign", "line", "line", "connect", "station", "forge", "time", "stale"] as const;

function draw(seed: number, n: number): { steps: Step[]; held: boolean[] } {
  const r = new Rng(seed);
  const steps = Array.from({ length: n }, () => ({ k: r.int(KINDS.length), a: r.int(1 << 16), b: r.int(1 << 16), c: r.int(1 << 16) }));
  // At the end, the stations the plane goes on holding back from (cut off from it, or a hostile plane's choice).
  return { steps, held: stationKeys.map(() => r.int(3) === 0) };
}

/// Something on its way over a line: run when it arrives, `lost` when the line goes first. Each `chan` (a socket's one
/// direction, one request's exchange) keeps its order. `what`: what it is, for a world told step by step to pick it.
type Msg = { link: string; chan: string; run: () => void; lost?: () => void; what?: string };

type StationSim = {
  i: number;
  key: Key;
  data: string;
  cloud: Cloud | null;
  stopFollow: (() => void) | null;
  stopTell: (() => void) | null;
  /// Its socket to the plane: its frames' chan down (the way up is chan↑), what it says up it.
  presence: { unlisten: () => void; chan: string; toPlane: (frame: unknown) => void } | null;
};

/// A device of a person that holds the locks (a signer's app, a spare): its chain of each workspace, as it last read it
/// of a station or signed it.
/// `held`: the chain each lock is gone by on the device; `aside`, the entries of it a station showed that are off it.
/// `turn`: of each lock, whether it is signing (one entry at a time, views/lock.ts `Lock.append`) and what waits for it;
/// `handled` its entries that lost their place, signed again or let be; `tries` how many signings again each is;
/// `shown` the entries a station showed it or took from it; `carried` what it carried to which station (`carry`).
type Dev = {
  n: number; name: string; sub: string; base: Key; signer: Key; held: Map<string, Entry[]>; aside: Map<string, Entry[]>;
  turn: Map<string, { busy: boolean; next: (() => void)[] }>; handled: Set<string>; tries: Map<string, number>; shown: Set<string>; carried: Set<string>;
  /// `pending`: of each lock, what it signed that no station took nor refused (client/core-ts/src/lock-pending.ts),
  /// never on its chain, brought as it next reads a station (views/lock.ts `deliver`); `delivering`, the locks whose
  /// pending entries are being brought (one run at a time, as the core's `delivering`: a read meanwhile adds none).
  pending: Map<string, Entry[]>; delivering: Set<string>;
};
const devParts = () => ({ turn: new Map(), handled: new Set<string>(), tries: new Map<string, number>(), shown: new Set<string>(), carried: new Set<string>(), pending: new Map<string, Entry[]>(), delivering: new Set<string>() });

/// The same JSON whatever the order of its keys (an entry's body, compared by what it says).
const sameJson = (v: unknown): string => JSON.stringify(v, (_k, x) => (x !== null && typeof x === "object" && !Array.isArray(x) ? Object.fromEntries(Object.entries(x).sort(([a], [b]) => (a < b ? -1 : 1))) : x));
/// What an entry of a workspace's lock is about (client/core-ts/src/views/lock.ts `subjectOf`).
function subjectOf(e: Entry): string | null {
  const b = (e.body ?? {}) as any;
  if (e.kind === "device" || e.kind === "device.remove") return `device ${b.id}`;
  if (e.kind === "member" || e.kind === "member.remove" || e.kind === "person") return `member ${b.sub}`;
  if (e.kind === "station" || e.kind === "station.remove") return `station ${b.key}`;
  return e.kind === "disable" ? "lock" : null;
}
/// What becomes of an entry that lost its place, by the chain held and what is aside (client/core-ts/src/lock-keep.ts
/// `againOf`, the same rule): done, otherwise, unmoved or sign.
function againOf(chain: Entry[], aside: Entry[], lost: Entry): "done" | "otherwise" | "unmoved" | "sign" {
  const at = new Map(chain.map((e, i) => [entryHash(e), i]));
  if (at.has(entryHash(lost))) return "done";
  const up = new Map(aside.map((e) => [entryHash(e), e]));
  let parent = lost.prev;
  for (let n = 0; parent !== null && !at.has(parent) && n <= aside.length; n++) parent = up.get(parent)?.prev ?? null;
  const i = parent === null ? undefined : at.get(parent);
  if (i === undefined || i === chain.length - 1) return "unmoved";
  const since = chain.slice(i + 1);
  if (since.some((e) => e.kind === lost.kind && sameJson(e.body) === sameJson(lost.body))) return "done";
  const about = subjectOf(lost);
  return about !== null && since.some((e) => subjectOf(e) === about) ? "otherwise" : "sign";
}
/// How many times one entry that lost its place is signed again (client/core-ts/src/lock-keep.ts AGAIN_MOST).
const AGAIN_MOST = 3;

/// A world from its steps; `check` throws what went wrong, naming the step.
class World {
  t = START;
  timers: { at: number; seq: number; f: () => void }[] = [];
  timerSeq = 0;
  queue: Msg[] = [];
  chanSeq = 0;
  /// The workspaces, the home one first.
  sp: Space[] = spaces();
  /// Lines: each station's presence socket, the mesh between two stations, the devices' to the plane, to each station.
  lines = new Map<string, boolean>();
  stations: StationSim[];
  /// The devices that hold the locks: the signers' apps first, then the spares.
  devs: Dev[];
  /// Entries a forger made: none may ever be in a station's chain.
  forged = new Set<string>();
  /// A station's telling of its lock to a device, not yet landed (one is enough: the device reads all there is).
  telling = new Set<string>();
  /// What each station refused of entries brought to it, said once (`station|why`).
  refusals = new Set<string>();
  log: string[] = [];
  rng: Rng;

  constructor(seed: number) {
    this.rng = new Rng(seed ^ 0x5eed);
    const base = mkdtempSync(join(process.env.STILLFAIL_TEST_TMP ?? tmpdir(), "lock-world-"));
    this.stations = stationKeys.map((k, i) => {
      const data = mkdtempSync(join(base, `s${i}-`));
      writeState(data, {
        origin: ORIGIN, station: k.hex, workspace: WS, workspace_name: "Team", name: `s${i}`, relay_url: "", relay_urls: [],
        grant_keys: { keys: [] }, peers: stationKeys.map((s, j) => ({ id: s.hex, name: `s${j}` })), revocations: [],
        ...(this.sp[1]!.members.includes(i) ? { joined: [this.joined(this.sp[1]!, i)] } : {}),
      });
      const c = new Cloud(data, false);
      for (const sp of this.sp) if (sp.members.includes(i)) c.takeLock([sp.plane[0]!], keyOf(sp));
      c.close();
      return { i, key: k, data, cloud: null, stopFollow: null, stopTell: null, presence: null };
    });
    const genesis = new Map(this.sp.map((sp) => [sp.ws, [sp.plane[0]!]]));
    this.devs = [
      ...signers.map((s, n) => ({ n, name: `${s.sub}'s app`, sub: s.sub as string, base: s.app, signer: s.signer, held: new Map(genesis), aside: new Map(), ...devParts() })),
      ...spare.map((d, j) => ({ n: signers.length + j, name: d.name, sub: d.sub, base: d.base, signer: d.signer, held: new Map(genesis), aside: new Map(), ...devParts() })),
    ];
    for (const l of this.allLines()) this.lines.set(l, true);
    for (const s of this.stations) this.start(s);
  }

  /// A joined workspace as the plane says it of station `i`.
  joined(sp: Space, i: number) {
    return { workspace: sp.ws, workspace_name: sp.name, name: `s${i}`, peers: sp.members.map((j) => ({ id: stationKeys[j]!.hex, name: `s${j}` })), revocations: [], locked: true as const };
  }

  space(ws: unknown): Space {
    return this.sp.find((x) => x.ws === ws) ?? this.sp[0]!;
  }

  allLines(): string[] {
    const out = ["dc"];
    for (let i = 0; i < N; i++) out.push(`p${i}`, `d${i}`);
    for (let i = 0; i < N; i++) for (let j = i + 1; j < N; j++) out.push(`m${i}-${j}`);
    return out;
  }

  up(line: string): boolean {
    return this.lines.get(line) === true;
  }

  // ── time and lines ──────────────────────────────────────────────────────────────────────────────────────────────

  /// A timer on the world's clock (the stations' retries, a device's call's deadline).
  after = (ms: number, f: () => void): (() => void) => {
    const timer = { at: this.t + ms, seq: this.timerSeq++, f };
    this.timers.push(timer);
    this.timers.sort((x, y) => x.at - y.at || x.seq - y.seq);
    return () => {
      this.timers = this.timers.filter((x) => x !== timer);
    };
  };

  async pass(ms: number) {
    const until = this.t + ms;
    while (this.timers.length > 0 && this.timers[0]!.at <= until) {
      const timer = this.timers.shift()!;
      this.t = timer.at;
      timer.f();
      await settle();
    }
    this.t = until;
  }

  send(link: string, chan: string, run: () => void, lost?: () => void, what?: string) {
    if (!this.up(link)) {
      lost?.();
      return;
    }
    this.queue.push({ link, chan, run, lost, what });
  }

  /// The messages that may arrive next: each chan's first.
  ready(): Msg[] {
    const seen = new Set<string>();
    return this.queue.filter((m) => !seen.has(m.chan) && (seen.add(m.chan), true));
  }

  async deliver(pick: number): Promise<boolean> {
    const ready = this.ready();
    if (ready.length === 0) return false;
    await this.land(ready[pick % ready.length]!);
    return true;
  }

  /// The first message that may arrive next and is `what`, landed (a world told step by step).
  async deliverWhat(what: string): Promise<void> {
    const m = this.ready().find((x) => x.what === what);
    assert.ok(m !== undefined, `nothing "${what}" on its way`);
    await this.land(m);
  }

  async land(m: Msg) {
    this.queue.splice(this.queue.indexOf(m), 1);
    m.run();
    await settle();
  }

  /// A line cut (what is on it lost) or back. A device's line to a station back: each device reads that station's
  /// locks, as its link opens again.
  async setLine(line: string, on: boolean) {
    if (this.up(line) === on) return;
    this.lines.set(line, on);
    if (!on) {
      const gone = this.queue.filter((m) => m.link === line);
      this.queue = this.queue.filter((m) => m.link !== line);
      for (const m of gone) m.lost?.();
    }
    const p = /^p(\d)$/.exec(line);
    if (p) {
      const s = this.stations[Number(p[1])]!;
      if (on) this.connectPresence(s);
      else this.dropPresence(s);
    }
    const d = /^d(\d)$/.exec(line);
    if (d && on) this.readAll(this.stations[Number(d[1])]!);
    await settle();
  }

  // ── the stations ────────────────────────────────────────────────────────────────────────────────────────────────

  start(s: StationSim) {
    const cloud = new Cloud(s.data, false);
    s.cloud = cloud;
    // What it refuses of entries brought to it (by a device, a station, the plane), said once each in the log.
    const take = cloud.takeLock.bind(cloud);
    cloud.takeLock = (entries: Entry[], ws: string | null = null, fork = false) => {
      try {
        return take(entries, ws, fork);
      } catch (e) {
        const why = `s${s.i}|${ws ?? WS}|${(e as Error).message}|${entries[0]?.seq}`;
        if (!this.refusals.has(why)) {
          this.refusals.add(why);
          this.log.push(`  s${s.i} refuses ${this.space(ws ?? WS).name}'s entries from ${entries[0]?.seq ?? "-"} (${entries.map(said).join("; ")}): ${(e as Error).message}`);
        }
        throw e;
      }
    };
    s.stopFollow = followLock(cloud, (peer, ws, request) => this.meshCall(s, peer, ws, request), this.after);
    // Its event streams to the devices: a lock that moved on is told to each, which reads it (mesh/lock-events.ts).
    s.stopTell = tellLocks(cloud, new PersonChains(null), (event, data) => {
      if (event !== "lock") return;
      const sp = this.space((data as { workspace?: unknown })?.workspace);
      for (const dev of this.devs) this.tell(s, dev, sp);
    });
    this.connectPresence(s);
    this.readAll(s);
  }

  stop(s: StationSim) {
    this.dropPresence(s);
    s.stopFollow?.();
    s.stopTell?.();
    s.cloud?.close();
    s.cloud = null;
    s.stopFollow = null;
    s.stopTell = null;
    // What was on its way to or from it is lost with it.
    const mine = (l: string) => l === `p${s.i}` || l === `d${s.i}` || new RegExp(`^m(${s.i}-\\d|\\d-${s.i})$`).test(l);
    const gone = this.queue.filter((m) => mine(m.link));
    this.queue = this.queue.filter((m) => !mine(m.link));
    for (const m of gone) m.lost?.();
  }

  meshCall(from: StationSim, peer: string, ws: string | null, request: any): Promise<any> {
    const to = this.stations.find((x) => x.key.hex === peer);
    if (!to) return Promise.reject(new Error("no such station"));
    const link = `m${Math.min(from.i, to.i)}-${Math.max(from.i, to.i)}`;
    const chan = `${link}#${this.chanSeq++}`;
    return new Promise((resolve, reject) => {
      const lost = () => reject(new Error("the line to the station went"));
      this.send(link, chan, () => {
        if (to.cloud === null) return lost();
        // The mesh takes a station's requests only from the stations its lock names (its roster, filtered by it).
        if (!(to.cloud.locked(ws)?.state?.stations.has(from.key.hex) ?? false)) return this.send(link, chan, () => reject(new Error("not a station of the lock")), lost);
        let answer: unknown;
        try {
          answer = answerLock(to.cloud, request, ws);
        } catch (e) {
          return this.send(link, chan, () => reject(e), lost);
        }
        this.send(link, chan, () => resolve(answer), lost);
      }, lost);
    });
  }

  // ── the plane ───────────────────────────────────────────────────────────────────────────────────────────────────

  connectPresence(s: StationSim) {
    if (s.cloud === null || !this.up(`p${s.i}`) || s.presence !== null) return;
    const cloud = s.cloud;
    const link = `p${s.i}`;
    const chan = `${link}#${this.chanSeq++}`;
    const open = () => s.presence !== null && s.cloud === cloud && this.up(link);
    const toPlane = (frame: any) => this.send(link, `${chan}↑`, () => this.fromStation(s, frame, `${chan}↓`));
    const { tell } = planeTeller(cloud, toPlane, open);
    s.presence = { unlisten: cloud.listen(tell), chan, toPlane };
    // The plane's first frame on a new socket.
    this.sendState(s, `${chan}↓`, toPlane);
    tell();
  }

  dropPresence(s: StationSim) {
    s.presence?.unlisten();
    s.presence = null;
  }

  head(sp: Space) {
    const last = sp.plane.at(-1)!;
    return { seq: last.seq, hash: entryHash(last), genesis: entryHash(sp.plane[0]!) };
  }

  sendState(s: StationSim, chan: string, toPlane: (f: unknown) => void) {
    const frame = JSON.stringify({
      type: "state", workspace: WS, workspace_name: "Team", name: `s${s.i}`, origin: ORIGIN, relay_urls: [],
      peers: stationKeys.map((k, j) => ({ id: k.hex, name: `s${j}` })), grant_keys: { keys: [] }, revocations: [], lock: this.head(this.sp[0]!),
      workspaces: this.sp.slice(1).filter((sp) => sp.members.includes(s.i)).map((sp) => ({ ...this.joined(sp, s.i), lock: this.head(sp) })),
    });
    this.send(`p${s.i}`, chan, () => s.cloud && applyState(s.cloud, frame, toPlane));
  }

  fromStation(s: StationSim, frame: any, down: string) {
    const sp = this.space(frame?.workspace ?? WS);
    if (!sp.members.includes(s.i)) return;
    if (frame?.type === "lock.get") {
      // Of a chain turned off since, if it names one the plane kept (cloud/src/directory.ts lock_turned_off).
      const off = typeof frame.genesis === "string" ? sp.epochs.slice(0, -1).find((h) => entryHash(h[0]!) === frame.genesis) : undefined;
      const entries = (off ?? sp.plane).filter((e) => e.seq > (frame.after ?? -1));
      const text = JSON.stringify({ type: "lock", entries, ...(sp.ws === WS ? {} : { workspace: sp.ws }) });
      this.send(`p${s.i}`, down, () => s.cloud && applyState(s.cloud, text, (f) => s.presence?.toPlane(f)));
    } else if (frame?.type === "lock.put") this.append(sp, frame.entries, frame.keep === true);
  }

  /// Entries brought to the plane: taken as the cloud takes them (`fork`: a station's, with `keep`, by the fork choice;
  /// cloud/src/lock.ts keepLockAt), every station on a socket told of the new head.
  append(sp: Space, entries: Entry[], fork = false): boolean {
    let plan;
    try {
      plan = keepLockAt({ entries: sp.plane as never, aside: sp.planeAside as never }, entries as never, Math.floor(this.t / 1000), fork);
    } catch (e) {
      if (e instanceof LockAppendRefused) return false;
      throw e;
    }
    if (!plan.changed) return true;
    sp.plane = plan.kept.entries as unknown as Entry[];
    sp.planeAside = plan.kept.aside as unknown as Entry[];
    if (plan.restart) sp.epochs.push(sp.plane);
    else sp.epochs[sp.epochs.length - 1] = sp.plane;
    if (sp.plane.at(-1)!.kind === "disable") sp.off.add(entryHash(sp.plane[0]!));
    for (const s of this.stations) {
      if (s.presence) this.sendState(s, `${s.presence.chan}↓`, s.presence.toPlane);
    }
    return true;
  }

  // ── devices ─────────────────────────────────────────────────────────────────────────────────────────────────────

  /// Station `s` tells `dev` its lock of `sp` moved on (its event stream, over the device's line to it): the device
  /// reads it as it lands.
  tell(s: StationSim, dev: Dev, sp: Space) {
    const k = `${s.i}|${dev.n}|${sp.ws}`;
    if (this.telling.has(k) || !this.up(`d${s.i}`)) return;
    this.telling.add(k);
    const done = () => void this.telling.delete(k);
    this.send(`d${s.i}`, `ev${s.i}-${dev.n}`, () => {
      done();
      this.read(dev, s, sp);
    }, done);
  }

  /// Each device reads each lock of station `s` (its link to it opened).
  readAll(s: StationSim) {
    if (s.cloud === null || !this.up(`d${s.i}`)) return;
    for (const sp of this.sp) if (sp.members.includes(s.i)) for (const dev of this.devs) this.read(dev, s, sp);
  }

  /// A device's GET /lock of station `s` in `sp`, over its line; the chain it answers kept with the one held as it
  /// lands (views/lock.ts readLockOnce, hold). A station whose lock does not name the device refuses it
  /// (`lock_unconfirmed`), telling the last entries of its chain (mesh/serve.ts `refusalOf`), which the device keeps
  /// as a read's where they go on from an entry it holds (views/lock.ts heardTail). A station whose lock does not name the device refuses it
  /// (`lock_unconfirmed`).
  /// `then`: what the device does once the read landed or was lost (a signing turn waiting on it, `lost`). What it
  /// read, it carries to the station where that lacks some of what the device keeps (`carry`).
  read(dev: Dev, s: StationSim, sp: Space, then?: () => void) {
    const chan = `d${s.i}#${this.chanSeq++}`;
    let after = then;
    const done = () => {
      const f = after;
      after = undefined;
      f?.();
    };
    this.send(`d${s.i}`, chan, () => {
      if (s.cloud === null) return done();
      const state = s.cloud.locked(keyOf(sp))?.state;
      if (state && !state.devices.has(dev.base.hex)) {
        const tail: Entry[] = [];
        let bytes = 0;
        for (const entry of s.cloud.lockAfter(-1, keyOf(sp)).reverse()) {
          bytes += JSON.stringify(entry).length;
          if (bytes > REFUSAL_ENTRIES_BYTES) break;
          tail.unshift(entry);
        }
        if (tail.length > 0) this.send(`d${s.i}`, chan, () => (this.heardTail(dev, sp, tail), done()), done);
        else done();
        return;
      }
      const [, answer] = lockRoute(s.cloud, "GET", [], Buffer.alloc(0), viewer(dev.base, dev.sub, "member", sp.ws)) as [number, { head: { genesis: string } | null; entries: Entry[] }];
      const chain = answer.entries;
      const genesis = answer.head?.genesis ?? null;
      this.send(`d${s.i}`, chan, () => {
        for (const e of chain) dev.shown.add(entryHash(e));
        this.take(dev, sp, chain);
        this.carry(dev, s, sp, chain, genesis);
        this.deliverPending(dev, sp);
        done();
      }, done);
    }, done);
  }

  /// What `dev` keeps of `sp`'s lock (its chain, then what is aside), each entry a station showed or took, brought with
  /// `keep` to station `s` it just read, where `s` keeps this lock (`genesis`) and lacks some of it: once each
  /// (views/lock.ts `carry`).
  carry(dev: Dev, s: StationSim, sp: Space, theirs: Entry[], genesis: string | null) {
    const held = dev.held.get(sp.ws) ?? [];
    if (held.length === 0 || genesis !== entryHash(held[0]!) || fold(held, null).disabled) return;
    const kept = [...held, ...(dev.aside.get(sp.ws) ?? [])].filter((e) => dev.shown.has(entryHash(e)));
    const has = new Set(theirs.map(entryHash));
    if (kept.length === 0 || kept.every((e) => has.has(entryHash(e)))) return;
    const what = `${s.i}|${sp.ws}|${kept.map(entryHash).join(",")}`;
    if (dev.carried.has(what)) return;
    dev.carried.add(what);
    this.log.push(`  ${dev.name} carries ${kept.length} entries of ${sp.name} to s${s.i}`);
    this.send(`d${s.i}`, `d${s.i}#${this.chanSeq++}`, () => {
      if (s.cloud === null) return;
      lockRoute(s.cloud, "POST", [], Buffer.from(JSON.stringify({ entries: kept, keep: true })), viewer(dev.base, dev.sub, dev.sub === "alice" ? "owner" : "member", sp.ws));
    });
  }

  /// What `dev` has pending in `sp` brought to its stations, it having read one (views/lock.ts `deliver`), oldest first,
  /// each in its turn: on the chain held, dropped; its parent the head held, brought as it is; else by `againOf`: done,
  /// dropped; sign, signed again after the head (AGAIN_MOST times at most) and brought; else let be (failed, said so).
  deliverPending(dev: Dev, sp: Space) {
    const waiting = dev.pending.get(sp.ws) ?? [];
    if (waiting.length === 0 || dev.delivering.has(sp.ws)) return;
    dev.delivering.add(sp.ws);
    for (const e of [...waiting].sort((x, y) => x.seq - y.seq)) {
      this.turn(dev, sp, () => {
        const left = dev.pending.get(sp.ws) ?? [];
        if (!left.some((x) => entryHash(x) === entryHash(e))) return;
        const drop = () => dev.pending.set(sp.ws, (dev.pending.get(sp.ws) ?? []).filter((x) => entryHash(x) !== entryHash(e)));
        const held = dev.held.get(sp.ws) ?? [];
        if (held.some((x) => entryHash(x) === entryHash(e))) {
          // (a station took it by another's carrying: the plane sent it now, as what a station took is)
          drop();
          return this.send("dc", `dc#${this.chanSeq++}`, () => this.log.push(`  the plane ${this.append(sp, [e]) ? "takes" : "refuses"} ${dev.name}'s ${said(e)}`));
        }
        if (held.length === 0 || fold(held, null).disabled) return drop();
        if (e.seq === held.length && e.prev === entryHash(held.at(-1)!)) {
          this.log.push(`  ${dev.name} brings its pending ${said(e)} in ${sp.name}`);
          return this.bring(dev, sp, held, e, held, dev.tries.get(entryHash(e)) ?? 0);
        }
        const how = againOf(held, dev.aside.get(sp.ws) ?? [], e);
        const tries = dev.tries.get(entryHash(e)) ?? 0;
        drop();
        if (how === "sign" && tries < AGAIN_MOST && this.signAgain(dev, sp, e, tries + 1)) return;
        this.log.push(`  ${dev.name}'s pending ${said(e)} fails (${how})`);
      });
    }
    // (the run over once each was brought and answered, or let be: the turn after the last)
    this.turn(dev, sp, () => void dev.delivering.delete(sp.ws));
  }

  /// `dev`'s turn to sign in `sp` (views/lock.ts `Lock.append`): `f` once no entry of its is being brought there.
  turn(dev: Dev, sp: Space, f: () => void) {
    this.turnOf(dev, sp).next.push(f);
    this.nextTurn(dev, sp);
  }
  turnOf(dev: Dev, sp: Space) {
    let t = dev.turn.get(sp.ws);
    if (t === undefined) dev.turn.set(sp.ws, (t = { busy: false, next: [] }));
    return t;
  }
  nextTurn(dev: Dev, sp: Space) {
    const t = this.turnOf(dev, sp);
    while (!t.busy && t.next.length > 0) t.next.shift()!();
  }
  /// The turn given up (the entry held, refused, or left to the plane): what waits for it goes on.
  giveUp(dev: Dev, sp: Space) {
    this.turnOf(dev, sp).busy = false;
    this.nextTurn(dev, sp);
  }

  /// `lost`, refused by station `s` that keeps the lock and taken by none, in the turn (views/lock.ts `#lost`): `s`
  /// read, then done, let be, or signed again after the head (AGAIN_MOST times at most).
  lost(dev: Dev, sp: Space, lost: Entry, tries: number, s: StationSim) {
    dev.handled.add(entryHash(lost));
    this.read(dev, s, sp, () => {
      const how = againOf(dev.held.get(sp.ws) ?? [], dev.aside.get(sp.ws) ?? [], lost);
      if (how === "sign" && tries < AGAIN_MOST && this.signAgain(dev, sp, lost, tries + 1)) return;
      this.log.push(`  ${dev.name}'s ${said(lost)} is refused (${how})`);
      this.giveUp(dev, sp);
    });
  }

  /// `lost` signed again after the head held, in the turn: whether it was (the rules taking it there).
  signAgain(dev: Dev, sp: Space, lost: Entry, tries: number): boolean {
    const chain = dev.held.get(sp.ws) ?? [];
    if (chain.length === 0) return false;
    const state = fold(chain, null);
    if (state.disabled) return false;
    const at = Math.floor(this.t / 1000);
    const entry = signed(after(chain, at, lost.kind, lost.body), dev.signer);
    try {
      apply(state, entry, at);
    } catch {
      return false;
    }
    dev.tries.set(entryHash(entry), tries);
    this.log.push(`  ${dev.name} signs ${said(entry)} again in ${sp.name}, after ${said(chain.at(-1)!)}`);
    this.bring(dev, sp, chain, entry, chain, tries);
    return true;
  }

  /// The last entries of a station's chain told in its refusal: from the entries held before the first of them, kept as
  /// a read's chain is (views/lock.ts heardTail).
  heardTail(dev: Dev, sp: Space, tail: Entry[]) {
    const was = dev.held.get(sp.ws) ?? [];
    const first = tail[0]!.seq;
    if (was.length === 0 || first > was.length) return;
    for (let i = 0; i < tail.length; i++) {
      const prev = i === 0 ? (first === 0 ? undefined : was[first - 1]) : tail[i - 1];
      if (tail[i]!.seq !== first + i || (prev !== undefined && tail[i]!.prev !== entryHash(prev))) return;
    }
    const chain = [...was.slice(0, first), ...tail];
    for (const e of tail) dev.shown.add(entryHash(e));
    if (entryHash(chain[0]!) === entryHash(was[0]!)) this.take(dev, sp, chain);
  }

  /// A chain read of a station, as the core takes it (views/lock.ts `hold`, client/core-ts/src/lock-keep.ts): of the
  /// lock held and on, one that goes on from its head is held, one behind changes nothing, and one that parts from it
  /// is kept with it and what is aside, the chain held the rules' choice among them (the station's twin of the core's
  /// keeping, the same rules); where the one held is turned off (or none), another lock's chain is taken.
  take(dev: Dev, sp: Space, chain: Entry[]) {
    const was = dev.held.get(sp.ws) ?? [];
    if (chain.length === 0) return;
    const off = was.length === 0 || fold(was, null).disabled;
    if (off) {
      if (was.length === 0 || entryHash(chain[0]!) !== entryHash(was[0]!)) {
        dev.held.set(sp.ws, chain);
        dev.aside.set(sp.ws, []);
      }
      return;
    }
    if (entryHash(chain[0]!) !== entryHash(was[0]!)) return;
    if (chain.length > was.length && entryHash(chain[was.length - 1]!) === entryHash(was.at(-1)!)) return void dev.held.set(sp.ws, chain);
    if (chain.length <= was.length && entryHash(was[chain.length - 1]!) === entryHash(chain.at(-1)!)) return;
    try {
      const genesis = entryHash(was[0]!);
      const t = keep({ entries: was, aside: dev.aside.get(sp.ws) ?? [] }, chain, { chain: (all) => lockChain(all, genesis), pre: (e) => (e.ws !== was[0]!.ws ? "an entry of another lock" : null) });
      if (!t.changed) return;
      if (t.moved) this.log.push(`  ${dev.name} goes by #${entryHash(t.kept.entries.at(-1)!).slice(0, 6)} in ${sp.name}, the rules' choice, keeping ${t.kept.aside.length} aside`);
      dev.held.set(sp.ws, t.kept.entries);
      dev.aside.set(sp.ws, t.kept.aside);
      // Its own entries the chain held went off: each signed again once, in its turn (views/lock.ts `hold`, `again`).
      for (const e of [...t.kept.aside].sort((x, y) => x.seq - y.seq)) {
        if (e.sig?.key !== dev.signer.id || dev.handled.has(entryHash(e))) continue;
        dev.handled.add(entryHash(e));
        this.turn(dev, sp, () => {
          const tries = dev.tries.get(entryHash(e)) ?? 0;
          if (tries < AGAIN_MOST && againOf(dev.held.get(sp.ws) ?? [], dev.aside.get(sp.ws) ?? [], e) === "sign") this.signAgain(dev, sp, e, tries + 1);
        });
      }
    } catch {}
  }

  /// A person's app signs one more entry after the chain it holds and brings it to the stations and the plane
  /// (views/lock.ts `append`, `bring`).
  sign(who: number, what: number, pick: number) {
    const dev = this.devs[who % signers.length]!;
    const sp = this.sp[(what >> 4) % this.sp.length]!;
    // (in its turn: one entry at a time, each after the chain held as the turn begins)
    this.turn(dev, sp, () => this.signNow(dev, sp, what, pick));
  }

  signNow(dev: Dev, sp: Space, what: number, pick: number) {
    const chain = dev.held.get(sp.ws) ?? [];
    if (chain.length === 0) return;
    const state = fold(chain, null);
    const at = Math.floor(this.t / 1000);
    let body: unknown, kind: string;
    const inLock = spare.filter((d) => state.devices.has(d.base.hex));
    const outOfLock = spare.filter((d) => !state.devices.has(d.base.hex));
    // Turned off now and then, and on again once it is off.
    if (state.disabled) return this.reopen(sp, dev);
    switch (what % 4 === 2 && pick % 5 === 0 ? 4 : what % 4) {
      case 4: {
        if (dev.n !== 0) return;
        kind = "disable";
        body = {};
        break;
      }
      case 0: {
        const d = outOfLock[pick % Math.max(1, outOfLock.length)];
        if (!d) return;
        kind = "device";
        body = { id: d.base.hex, sub: d.sub, kind: "app", label: d.name, sign_key: d.signer.id };
        break;
      }
      case 1: {
        const d = inLock[pick % Math.max(1, inLock.length)];
        if (!d) return;
        kind = "device.remove";
        body = { id: d.base.hex };
        break;
      }
      case 3: {
        // A station of the workspace taken out of its lock, or put back; two at least stay in it.
        const at = sp.members[pick % sp.members.length]!;
        const st = stationKeys[at]!;
        if (state.stations.has(st.hex) && state.stations.size <= 2) return;
        kind = state.stations.has(st.hex) ? "station.remove" : "station";
        body = kind === "station" ? { key: st.hex, name: `s${at}` } : { key: st.hex };
        break;
      }
      default: {
        const sub = pick % 2 === 0 ? "bob" : "carol";
        kind = "member";
        body = { sub, email: `${sub}@x`, role: ["viewer", "member", "admin"][pick % 3] };
      }
    }
    const entry = signed(after(chain, at, kind, body), dev.signer);
    // The core checks it as the stations will before it goes (vault/lock-check.ts): one they refuse is not sent.
    try {
      apply(state, entry, at);
    } catch {
      return;
    }
    this.log.push(`  ${dev.name} signs ${said(entry)} in ${sp.name}, after ${chain.length > 1 ? said(chain.at(-1)!) : "the genesis"} as it holds it`);
    this.bring(dev, sp, chain, entry, chain);
  }

  /// The whole chain (`prefix` and `entry`) brought by `dev` to every station of the lock it makes, each on its own line
  /// (views/lock.ts `#firstTaken`): once one took it, the entry goes to the plane too, nothing waiting on it, and the
  /// device holds the chain (where what it holds is still `was`: a call a person waits on, `within`); refused by a
  /// station that keeps this lock and taken by none, nothing more; none answering (all lost, or TAKEN_MS over), it is
  /// pending (client/core-ts/src/lock-pending.ts): not held, not sent to the plane, brought again as the device next
  /// reads a station (`deliverPending`), and held as a station's answer that comes later says it took it. Only a lock that names
  /// no station is the plane's, sent there and waited on, the device holding it as the plane took it (until
  /// 2026-11-12 every entry no station took was).
  bring(dev: Dev, sp: Space, prefix: Entry[], entry: Entry, was: Entry[], tries = 0) {
    this.turnOf(dev, sp).busy = true;
    const whole = [...prefix, entry];
    const genesis = entryHash(whole[0]!);
    const to = this.stations.filter((s) => sp.members.includes(s.i) && fold(whole, null).stations.has(s.key.hex));
    const call = { done: false, left: to.length, refused: null as StationSim | null };
    const hold = () => {
      const h = dev.held.get(sp.ws) ?? [];
      if (h.length === was.length && (h.length === 0 || entryHash(h.at(-1)!) === entryHash(was.at(-1)!))) {
        if (h.length === 0 || entryHash(h[0]!) !== genesis) dev.aside.set(sp.ws, []);
        dev.held.set(sp.ws, whole);
      }
    };
    const toPlane = (waited: boolean) => {
      const chan = `dc#${this.chanSeq++}`;
      this.send("dc", chan, () => {
        const took = this.append(sp, [entry]);
        this.log.push(`  the plane ${took ? "takes" : "refuses"} ${dev.name}'s ${said(entry)}${waited ? " (waited on)" : ""}`);
        if (waited && took) this.send("dc", chan, hold);
      });
    };
    let cancel = () => {};
    const unpend = () => dev.pending.set(sp.ws, (dev.pending.get(sp.ws) ?? []).filter((x) => entryHash(x) !== entryHash(entry)));
    const taken = () => {
      // (held as a station took it, kept with what is held by the rules where that moved on: views/lock.ts `#taken`)
      for (const e of whole) dev.shown.add(entryHash(e));
      this.take(dev, sp, whole);
      unpend();
      toPlane(false);
    };
    const finish = (took: boolean) => {
      if (call.done) {
        // (a station's answer past the wait: one that took it, held as it comes, views/lock.ts `#tookLate`)
        if (took && (dev.pending.get(sp.ws) ?? []).some((x) => entryHash(x) === entryHash(entry))) taken();
        return;
      }
      call.done = true;
      cancel();
      if (took) {
        taken();
        this.giveUp(dev, sp);
      } else if (call.refused === null && (to.length === 0 || entry.kind === "genesis")) {
        // (a lock that names no station, or one turned on (views/lock.ts `open`, which this piece leaves as it was):
        // left to the plane, the turn given up)
        toPlane(true);
        this.giveUp(dev, sp);
      } else if (call.refused === null) {
        // (pending, the turn given up)
        const left = dev.pending.get(sp.ws) ?? [];
        if (!left.some((x) => entryHash(x) === entryHash(entry))) dev.pending.set(sp.ws, [...left, entry]);
        this.log.push(`  ${dev.name}'s ${said(entry)} is pending in ${sp.name}`);
        this.giveUp(dev, sp);
      } else {
        unpend();
        this.lost(dev, sp, entry, tries, call.refused);
      }
    };
    const gone = () => {
      if (--call.left === 0) finish(false);
    };
    for (const s of to) {
      const chan = `d${s.i}#${this.chanSeq++}`;
      this.send(`d${s.i}`, chan, () => {
        if (s.cloud === null) return gone();
        const [status, answer] = lockRoute(s.cloud, "POST", [], Buffer.from(JSON.stringify({ entries: whole })), viewer(dev.base, dev.sub, dev.sub === "alice" ? "owner" : "member", sp.ws)) as [number, any];
        // (taken by hash: the entry on its chain, views/lock.ts `#takenBy`)
        // (a `disable` taken lets the lock go: none kept after it to show it by hash, its answer's `taken` says it,
        // views/lock.ts `letGo`)
        const took = status === 200 && (s.cloud.lockAfter(-1, keyOf(sp)).some((e) => entryHash(e) === entryHash(entry)) || (entry.kind === "disable" && (answer?.taken ?? 0) > 0 && !s.cloud.locked(keyOf(sp))));
        const refused = status === 409 && answer?.head?.genesis === genesis;
        if (took && entry.kind === "disable") sp.off.add(genesis);
        if (took && entry.kind === "genesis" && !sp.opened.includes(genesis)) sp.opened.push(genesis);
        this.log.push(`  s${s.i} ${took ? "takes" : "does not take"} ${dev.name}'s ${said(entry)}${took ? "" : `: ${answer?.error ?? status}`}`);
        this.send(`d${s.i}`, chan, () => {
          if (took) return finish(true);
          // (what becomes of it then is `lost`'s: that station read, in the turn)
          if (refused) call.refused ??= s;
          gone();
        }, gone);
      }, gone, `${dev.name}→s${s.i}`);
    }
    if (to.length === 0) return finish(false);
    // timer: a deadline (TAKEN_MS)
    if (!call.done) cancel = this.after(TAKEN_MS, () => finish(false));
  }

  /// The owner turns the lock on again (views/lock.ts `open`): a new genesis with the people and devices of the one
  /// turned off, and the stations its app reaches that hold no lock (one that still holds the old one is left out, as
  /// the draft lists it `other`), brought to each of them and to the plane.
  reopen(sp: Space, dev: Dev) {
    if (dev.n !== 0) return;
    const was = dev.held.get(sp.ws) ?? [];
    const last = fold(was, null);
    const reached = this.stations.filter((s) => sp.members.includes(s.i) && s.cloud !== null && this.up(`d${s.i}`) && s.cloud.locked(keyOf(sp)) === null);
    if (reached.length < 2) return;
    const at = Math.floor(this.t / 1000);
    const g = signed({
      v: 1, ws: sp.ws, seq: 0, prev: null, at, kind: "genesis", body: {
        owner: "alice", origins: [ORIGIN], rp_id: "app.still.fail", cloud_keys: { keys: [] },
        members: [...last.members.values()], devices: [...last.devices.values()].map(({ by: _, ...d }) => d), passkeys: [],
        stations: reached.map((s) => ({ key: s.key.hex, name: `s${s.i}` })), gateways: [],
      },
    }, signers[0]!.signer);
    this.log.push(`  alice turns ${sp.name}'s lock on again with ${reached.map((s) => `s${s.i}`).join(", ")}`);
    this.bring(dev, sp, [], g, was);
  }

  /// A spare device its own person approved and someone took out again (in the chain of a station now) signs all the
  /// same, after the chain as it was before its removal: it approves a device of its person's, and brings it to one
  /// station it reaches and, now and then, to the plane. What it signs must never stay.
  stale(pick: number, at: number, how: number) {
    const found: { sp: Space; prefix: Entry[]; d: (typeof spare)[number]; j: number }[] = [];
    for (const sp of this.sp) {
      for (const s of this.stations) {
        if (s.cloud === null || !sp.members.includes(s.i)) continue;
        const c = s.cloud.lockAfter(-1, keyOf(sp));
        for (const r of c) {
          if (r.kind !== "device.remove") continue;
          const j = spare.findIndex((d) => d.base.hex === (r.body as { id?: string }).id);
          if (j < 0) continue;
          const prefix = c.slice(0, r.seq);
          const was = fold(prefix, null).devices.get(spare[j]!.base.hex);
          if (was?.own === true && was.sign_key === spare[j]!.signer.id) found.push({ sp, prefix, d: spare[j]!, j });
        }
      }
    }
    const f = found[pick % Math.max(1, found.length)];
    if (!f) return;
    const now = Math.floor(this.t / 1000);
    const entry = signed(after(f.prefix, now, "device", { id: mal[f.j]!.base.hex, sub: f.d.sub, kind: "app", label: mal[f.j]!.name }), f.d.signer);
    try {
      apply(fold(f.prefix, null), entry, now);
    } catch {
      return;
    }
    f.sp.stale.add(entryHash(entry));
    const s = this.stations.filter((x) => f.sp.members.includes(x.i))[at % f.sp.members.length]!;
    const whole = [...f.prefix, entry];
    this.log.push(`  ${f.d.name}, taken out, signs ${said(entry)} in ${f.sp.name} after ${said(f.prefix.at(-1)!)} and brings it to s${s.i}${how % 2 === 0 ? " and the plane" : ""}`);
    this.send(`d${s.i}`, `d${s.i}#${this.chanSeq++}`, () => {
      if (s.cloud === null) return;
      const [status, answer] = lockRoute(s.cloud, "POST", [], Buffer.from(JSON.stringify({ entries: whole })), viewer(f.d.base, f.d.sub, "member", f.sp.ws)) as [number, any];
      this.log.push(`  s${s.i} ${status === 200 && (answer?.head?.seq ?? -1) >= entry.seq ? "takes" : "does not take"} ${f.d.name}'s ${said(entry)}${status === 200 ? "" : `: ${answer?.error ?? status}`}`);
    });
    if (how % 2 === 0) this.send("dc", `dc#${this.chanSeq++}`, () => this.log.push(`  the plane ${this.append(f.sp, [entry]) ? "takes" : "refuses"} ${f.d.name}'s ${said(entry)}`));
  }

  /// A device says hello to a station, bringing the entries from the one that put it in the lock, as it holds them (at
  /// most 64): let in or not, and is that right?
  connect(which: number, at: number, bring = true, inSpace = 0): boolean | null {
    const d = everyDevice[which % everyDevice.length]!;
    const sp = this.sp[inSpace % this.sp.length]!;
    const s = this.stations[at % N]!;
    if (s.cloud === null || !this.up(`d${s.i}`) || !sp.members.includes(s.i)) return null;
    // A joined workspace with no lock pinned: the station takes none of its members (Cloud.leftOut), refused before this.
    if (sp.ws !== WS && s.cloud.locked(sp.ws) === null) return null;
    const mine = this.devs.find((x) => x.base.hex === d.base.hex)?.held.get(sp.ws) ?? [];
    const from = mine.findLastIndex((e) => e.kind === "device" && (e.body as { id?: string }).id === d.base.hex);
    const entries = from < 0 || !bring ? [] : mine.slice(from, from + 64);
    const hello = entries.length > 0 ? { lock: { entries } } : {};
    let inside: boolean;
    try {
      inLockBringing(s.cloud, admitted(d.base, d.sub, sp.ws), "member", d.base.hex, hello);
      inside = true;
    } catch {
      inside = false;
    }
    const state = s.cloud.locked(keyOf(sp))?.state;
    // Let in only as the station's own chain says: the device in it, its member's; with no lock, as the plane says.
    const named = state?.devices.get(d.base.hex);
    assert.equal(inside, state === undefined || (named !== undefined && named.sub === d.sub), `s${s.i} ${inside ? "let in" : "turned away"} in ${sp.name} ${d.name} ${d.base.hex.slice(0, 8)} its chain ${named ? "names" : "does not name"}`);
    // (With no lock, the plane's word is taken as it was before: it signs the credentials.)
    assert.ok(!(inside && d.base.hex === eve.base.hex && state !== undefined), "a device only a forger named is let in");
    return inside;
  }

  /// The plane (or whoever has its place) forges: an entry no member signed, or one in the lock's place of another
  /// workspace, to a station on its socket or in a device's hello; or a head far ahead.
  forge(how: number, at: number) {
    const s = this.stations[at % N]!;
    const sp = this.sp[(how >> 3) % this.sp.length]!;
    if (s.cloud === null || !sp.members.includes(s.i)) return;
    const chain = s.cloud.lockAfter(-1, keyOf(sp));
    if (chain.length === 0) return;
    const fake = (() => {
      switch (how % 3) {
        case 0:
          return signed(after(chain, Math.floor(this.t / 1000), "device", { id: eve.base.hex, sub: eve.sub, kind: "app", label: "eve" }), eveKey);
        case 1:
          // Signed by alice, but changed after.
          return { ...signed(after(chain, Math.floor(this.t / 1000), "station", { key: key(950).hex, name: "x" }), signers[0]!.signer), body: { key: key(951).hex, name: "y" } };
        default:
          return signed({ ...after(chain, Math.floor(this.t / 1000), "device", { id: eve.base.hex, sub: eve.sub, kind: "app", label: "eve" }), prev: "ab".repeat(32) }, signers[2]!.signer);
      }
    })();
    this.forged.add(entryHash(fake));
    this.log.push(`  forged ${fake.kind} at ${fake.seq} in ${sp.name} to s${s.i}`);
    if ((how >> 2) % 2 === 0 && s.presence) {
      const text = JSON.stringify({ type: "lock", entries: [fake], ...(sp.ws === WS ? {} : { workspace: sp.ws }) });
      this.send(`p${s.i}`, `${s.presence.chan}↓`, () => s.cloud && applyState(s.cloud, text));
    } else if (this.up(`d${s.i}`)) {
      try {
        inLockBringing(s.cloud, admitted(eve.base, eve.sub, sp.ws), "member", eve.base.hex, { lock: { entries: [fake] } });
        assert.fail(`s${s.i} let eve in with a forged entry`);
      } catch (e) {
        if ((e as Error).message.includes("let eve in")) throw e;
      }
    }
  }

  // ── properties ──────────────────────────────────────────────────────────────────────────────────────────────────

  /// Each workspace's chains: the plane's first, then each of its stations' (a stopped one's as it left it on disk).
  chains(sp: Space = this.sp[0]!): { who: string; chain: Entry[] }[] {
    const out = [{ who: `the plane's ${sp.name}`, chain: sp.plane }];
    for (const s of this.stations) {
      if (sp.members.includes(s.i)) out.push({ who: `s${s.i}'s ${sp.name}`, chain: this.chainOf(s, sp) });
    }
    return out;
  }

  chainOf(s: StationSim, sp: Space): Entry[] {
    return s.cloud?.lockAfter(-1, keyOf(sp)) ?? readLock(s.data, keyOf(sp))?.entries ?? [];
  }

  /// What must always hold.
  invariants() {
    for (const sp of this.sp) this.holds(sp);
  }

  /// Every chain checks out, is of its workspace and holds nothing a forger made: the plane's, each station's, each
  /// device's. (Gone since the stations keep the locks, 2026-11-09: that each station's chain is one the plane kept, and
  /// that no two chains disagree at any step. A station takes what a device brings it without the plane, and two
  /// stations may each take another entry first at the same place; that they come to one chain is checked in the end,
  /// `converged`.)
  holds(sp: Space) {
    const all = [...this.chains(sp), ...this.devs.map((d) => ({ who: `${d.name}'s ${sp.name}`, chain: d.held.get(sp.ws) ?? [] }))];
    for (const { who, chain } of all) {
      if (chain.length === 0) continue;
      assert.doesNotThrow(() => fold(chain, null), `${who}'s chain does not check out`);
      for (const e of chain) assert.ok(!this.forged.has(entryHash(e)), `${who} took a forged entry at ${e.seq}`);
      assert.ok(chain[0]!.ws === sp.ws, `${who} is another workspace's`);
    }
  }

  async run(steps: Step[], held: boolean[]) {
    for (const [n, st] of steps.entries()) {
      const kind = KINDS[st.k]!;
      this.log.push(`${n}: ${kind} ${st.a % 64} ${st.b % 64} ${st.c % 64}`);
      switch (kind) {
        case "deliver":
          await this.deliver(st.a);
          break;
        case "sign":
          this.sign(st.a, st.b, st.c);
          await settle();
          break;
        case "line": {
          const lines = this.allLines();
          const line = lines[st.a % lines.length]!;
          await this.setLine(line, !this.up(line));
          this.log.push(`  ${line} ${this.up(line) ? "back" : "cut"}`);
          break;
        }
        case "connect":
          this.connect(st.a, st.b, true, st.c);
          break;
        case "station": {
          const s = this.stations[st.a % N]!;
          if (s.cloud) this.stop(s);
          else this.start(s);
          this.log.push(`  s${s.i} ${s.cloud ? "started" : "stopped"}`);
          await settle();
          break;
        }
        case "forge":
          this.forge(st.a, st.b);
          await settle();
          break;
        case "time":
          await this.pass(((st.a % 10) + 1) * 30_000);
          break;
        case "stale":
          this.stale(st.a, st.b, st.c);
          await settle();
          break;
      }
      this.invariants();
    }
    const failed = await this.end(held);
    if (failed.length > 0) throw new EndFailure(failed);
  }

  /// The end: every station up, every line back but the plane's to those it holds back from; whatever is on its way
  /// arrives, and time goes on until nothing is left to happen. The mesh last, once all else settled: what it carries
  /// then is all that may bring a held-back station level. Then what must have come about: each property that does
  /// not, said (`E<n> …: why`).
  async end(held: boolean[]): Promise<string[]> {
    for (const s of this.stations) if (s.cloud === null) this.start(s);
    for (const line of this.allLines()) if (!line.startsWith("m")) await this.setLine(line, !(/^p(\d)$/.test(line) && held[Number(line.slice(1))]));
    await this.drain();
    for (const line of this.allLines()) if (line.startsWith("m")) await this.setLine(line, true);
    this.log.push(`end: the plane holds back from ${held.flatMap((h, i) => (h ? [`s${i}`] : [])).join(", ") || "none"}`);
    await this.drain();
    this.invariants();
    for (const sp of this.sp) {
      for (const s of this.stations) if (sp.members.includes(s.i)) this.log.push(`  s${s.i} keeps ${sp.name}: ${chainSaid(this.chainOf(s, sp))}`);
      this.log.push(`  the plane keeps ${sp.name}: ${chainSaid(sp.plane)}`);
    }
    return this.sp.flatMap((sp) => this.converged(sp, held));
  }

  /// Whatever is on its way arrives, and time goes on (two days at most) until nothing is left to happen.
  async drain() {
    const until = this.t + 48 * 3600_000;
    for (let n = 0; n < 20_000; n++) {
      if (await this.deliver(this.rng.int(1 << 16))) continue;
      if (this.timers.length === 0 || this.timers[0]!.at > until) break;
      await this.pass(Math.max(0, this.timers[0]!.at - this.t));
    }
  }

  /// What must come about once the lines are back and everything in flight landed, each property that does not said.
  converged(sp: Space, held: boolean[]): string[] {
    const out: string[] = [];
    const chain = (i: number) => this.chainOf(this.stations[i]!, sp);
    // E5: none the plane reaches keeps a lock turned off: it hears the rest of that chain, its end with it.
    for (const i of sp.members) {
      const c = chain(i);
      if (!held[i] && c.length > 0 && sp.off.has(entryHash(c[0]!))) out.push(`E5 turned off: s${i} keeps ${sp.name}'s lock #${entryHash(c[0]!).slice(0, 6)}, turned off`);
    }
    // The lock in force: the last the owner turned on that a station took and that is not turned off since.
    const current = [...sp.opened].reverse().find((g) => !sp.off.has(g));
    if (current === undefined) return out;
    const of = sp.members.filter((i) => chain(i).length > 0 && entryHash(chain(i)[0]!) === current);
    if (of.length === 0) return out;
    // The stations of the lock: those every chain of it kept by a station names (one taken out of it in any of them is
    // no longer brought level by the others, nor are they by it).
    const named = sp.members.filter((i) => of.every((j) => fold(chain(j), null).stations.has(stationKeys[i]!.hex)));
    // E1: every station of the lock keeps the same chain, the same head. (None named, every one taken out of it, there
    // is nothing for it to say: seed 29 failed it on no station at all, 2026-11-12.)
    const heads = new Map(named.map((i) => [i, chain(i).length === 0 ? "none" : entryHash(chain(i).at(-1)!)]));
    const one = new Set(heads.values()).size <= 1;
    if (!one) out.push(`E1 one chain: in ${sp.name} ${named.map((i) => `s${i} keeps ${chain(i).length === 0 ? "no lock" : `${chain(i).length - 1} #${heads.get(i)!.slice(0, 6)}`}`).join(", ")}`);
    const common = one && named.length > 0 ? chain(named[0]!) : null;
    // E4: the plane level with it once one station of it reaches the plane (a plane that holds back from all of them is
    // asked nothing).
    if (common !== null && common.length > 0 && named.some((i) => !held[i]) && entryHash(sp.plane.at(-1)!) !== entryHash(common.at(-1)!)) {
      out.push(`E4 the plane: ${sp.name}'s plane keeps ${sp.plane.length - 1} #${entryHash(sp.plane.at(-1)!).slice(0, 6)}, the stations ${common.length - 1} #${entryHash(common.at(-1)!).slice(0, 6)}`);
    }
    // E2: who is let in, the same at every station of the lock, and as the chain they keep says.
    for (let d = 0; d < everyDevice.length; d++) {
      const dev = everyDevice[d]!;
      const answers = named.map((i) => ({ i, inside: this.connect(d, i, false, this.sp.indexOf(sp)) }));
      if (common !== null) {
        const want = fold(common, null).devices.has(dev.base.hex);
        for (const { i, inside } of answers) if (inside !== want) out.push(`E2 let in: ${dev.name} ${want ? "approved but turned away" : "removed but let in"} at s${i} in ${sp.name}`);
      } else if (new Set(answers.map((a) => a.inside)).size > 1) {
        out.push(`E2 let in: ${dev.name} in ${sp.name} let in at ${answers.filter((a) => a.inside).map((a) => `s${a.i}`).join(", ")}, turned away at ${answers.filter((a) => !a.inside).map((a) => `s${a.i}`).join(", ")}`);
      }
    }
    // E3: no device holds a chain no station keeps (one turned off, or of a lock turned off, takes the next as it reads).
    for (const dev of this.devs) {
      const h = dev.held.get(sp.ws) ?? [];
      if (h.length === 0 || fold(h, null).disabled || entryHash(h[0]!) !== current) continue;
      const kept = sp.members.some((i) => {
        const c = chain(i);
        return c.length >= h.length && entryHash(c[h.length - 1]!) === entryHash(h.at(-1)!);
      });
      if (!kept) out.push(`E3 devices: ${dev.name} holds ${sp.name} at ${h.length - 1} #${entryHash(h.at(-1)!).slice(0, 6)}, which no station keeps`);
    }
    // E6: what a removed device signed after a chain from before its removal stays nowhere.
    for (const i of sp.members) {
      for (const e of chain(i)) if (sp.stale.has(entryHash(e))) out.push(`E6 removed: s${i} keeps in ${sp.name} ${said(e)}, signed by a device after it was taken out`);
    }
    return out;
  }

  close() {
    for (const s of this.stations) this.stop(s);
  }
}

/// The properties of the end that did not come about, each a line (`E<n> name: why`).
class EndFailure extends Error {
  readonly failed: string[];
  constructor(failed: string[]) {
    super(`in the end:\n${failed.join("\n")}`);
    this.failed = failed;
  }
}

/// What the station's own code set going, run out (promises, the mesh's answers).
async function settle() {
  for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r));
}

const viewer = (base: Key, sub: string, role: string, ws = WS): Admitted["viewer"] => ({ sub, email: `${sub}@x`, name: sub, role, workspace: ws, device: base.hex, lockDevice: { base: base.hex, proof: base.sign(endpointBytes(ws, base.hex)) } });
const admitted = (base: Key, sub: string, ws = WS): Admitted => ({ viewer: viewer(base, sub, "member", ws), exp: 4102444800, iat: 1000, sid: "sid" });

async function fails(steps: Step[], held: boolean[], seed: number): Promise<{ error: Error; log: string[] } | null> {
  const w = new World(seed);
  try {
    await w.run(steps, held);
    return null;
  } catch (error) {
    return { error: error as Error, log: w.log };
  } finally {
    w.close();
  }
}

/// What the product does not hold (2026-11-12): by seed of the drawn worlds (the default 30, from 1), the end's
/// properties each breaks; by told world, the same. Each is one of these (`WHY`), the stations agreeing in every one
/// (seeds 3, 4, 26 and both told worlds checked from their traces, 2026-11-12). Only shrinks: a world that holds one of these now
/// fails its test until it is taken out.
const WHY: Record<string, string> = {};
// (16 added on 2026-11-12, the one seed ever added, as the model's device changed to read as the core does, and gone
// with 5, 18, 20, 24, 28 and 30 once the plane kept what a station gives it by the fork choice, as the cloud does: in
// those the plane only held the entry that lost. 11 and 26, where it held one no station took, gone with the device
// holding such an entry pending, 2026-11-12. Nothing is to be added.)
const KNOWN_SEEDS: Record<number, (keyof typeof WHY)[]> = {};
const KNOWN_TOLD: Record<string, (keyof typeof WHY)[]> = {};
/// The seeds `KNOWN_SEEDS` says all of (past them, what a world breaks at the end is told, not failed on).
const KNOWN_UPTO = 30;

/// The end's properties a world broke, each by its `E<n>`.
const codes = (failed: string[]): string[] => [...new Set(failed.map((f) => f.split(" ")[0]!))].sort();

/// A told world's end against `KNOWN_TOLD`: what else it breaks fails, and so does a known one that holds now.
function onlyKnown(name: string, failed: string[], log: string[]) {
  const got = codes(failed), known = KNOWN_TOLD[name] ?? [];
  assert.deepEqual(got.filter((c) => !known.includes(c)), [], `breaks what is not known to fail:\n${failed.join("\n")}\n${log.join("\n")}`);
  assert.deepEqual(known.filter((c) => !got.includes(c)), [], `holds now: take it out of KNOWN_TOLD["${name}"]`);
}

/// The fewest steps that still fail as `bad` says: chunks taken out, halving, as long as it still does.
async function shrink(steps: Step[], held: boolean[], seed: number, bad: (f: { error: Error }) => boolean): Promise<Step[]> {
  let now = steps;
  let tries = 0;
  for (let size = Math.floor(now.length / 2); size >= 1; size = Math.floor(size / 2)) {
    for (let at = 0; at + size <= now.length && tries < 400; tries++) {
      const less = [...now.slice(0, at), ...now.slice(at + size)];
      const f = await fails(less, held, seed);
      if (f && bad(f)) now = less;
      else at += size;
    }
  }
  return now;
}

/// The worlds told step by step, in the first part (lock-world-1.test.ts).
export function namedWorlds(): void {
  test("a station the plane holds back from is brought level by the others once the line between them is back, nothing else changing", async () => {
    const w = new World(1);
    try {
      // s1 cut off from the plane, from the devices and from the other stations; alice approves a device meanwhile.
      for (const line of ["p1", "d1", "m0-1", "m1-2"]) await w.setLine(line, false);
      w.sign(0, 0, 0);
      await w.drain();
      const [plane, s0, s1, s2] = w.chains().map((c) => c.chain.length);
      assert.deepEqual([s0, s1, s2], [plane, 1, plane], "s0 and s2 took it, s1 could not");
      // The lines between the stations back, and nothing else: s1 is brought level all the same.
      for (const line of ["m0-1", "m1-2"]) await w.setLine(line, true);
      await w.drain();
      assert.deepEqual(w.chains().map((c) => c.chain.length), [plane, plane, plane, plane]);
      w.invariants();
    } finally {
      w.close();
    }
  });

  test("a station away while the lock was turned off and on again lets the old one go once it is back, by the rest of it the plane kept", async () => {
    const w = new World(2);
    try {
      w.stop(w.stations[2]!);
      // alice turns it off, and on again with the two stations there.
      w.sign(0, 2, 0);
      await w.drain();
      w.sign(0, 0, 0);
      await w.drain();
      assert.equal(w.sp[0]!.epochs.length, 2, "turned on again");
      assert.deepEqual([0, 1].map((i) => w.stations[i]!.cloud!.locked()?.state?.genesis), [0, 1].map(() => entryHash(w.sp[0]!.plane[0]!)));
      // s2 back: it held the first lock, which is off.
      w.start(w.stations[2]!);
      await w.drain();
      assert.equal(w.stations[2]!.cloud!.locked(), null, "the old lock let go");
      w.invariants();
    } finally {
      w.close();
    }
  });

  // The stations come to one chain (E1, E2 hold), the devices and the plane to it (E3, E4).
  test("two devices that sign after the same chain at once, each taken first by another station, leave the stations with one chain in the end", async () => {
    const w = new World(3);
    try {
      // alice approves her phone, bob his laptop, both after the genesis as they hold it.
      w.sign(0, 0, 0);
      w.sign(1, 0, 3);
      // alice's chain reaches s0 first, bob's s1; the rest lands as it will.
      await w.deliverWhat("alice's app→s0");
      await w.deliverWhat("bob's app→s1");
      onlyKnown("two at once", await w.end([false, false, false]), w.log);
    } finally {
      w.close();
    }
  });

  // The stations come to one chain that keeps the removal (E1, E2, E6 hold), and the phone taken out to it, told it as
  // it is refused (E3).
  test("a device taken out that signs after the chain from before, at a station that has not heard of it yet, keeps nothing in the end", async () => {
    const w = new World(4);
    try {
      // alice approves her phone, which signs; every station takes it.
      w.sign(0, 0, 0);
      await w.drain();
      // s2 cut off from everything; alice takes the phone out again, s0 and s1 take that.
      for (const line of ["d2", "p2", "m0-2", "m1-2"]) await w.setLine(line, false);
      w.sign(0, 1, 0);
      await w.drain();
      await w.setLine("d2", true);
      // The phone approves a device of alice's after the chain from before its removal, and brings it to s2.
      w.stale(0, 2, 1);
      await w.drain();
      onlyKnown("a removed device signs", await w.end([false, false, false]), w.log);
    } finally {
      w.close();
    }
  });
}

// What the fork-choice model (lock-fork-choice-model.ts) takes of this world: the same people, keys, entries and draws.
export { Rng, START, WS, after, eve, eveKey, genesisOf, key, mal, said, signed, signers, spare, stationKeys };
export type { Key };

const STEPS = 160;
const RUNS = Number(process.env.LOCK_WORLD_RUNS ?? 30);
const seeds = process.env.LOCK_WORLD_SEED ? [Number(process.env.LOCK_WORLD_SEED)] : Array.from({ length: RUNS }, (_, i) => i + 1);

/// The worlds drawn from the seeds of part `part` of `parts` (every `parts`-th from `part + 1`): the parts are files of
/// their own (lock-world-<n>.test.ts), run beside each other, so the slowest file of the station's tests is a third of
/// what it was. Every seed is run and what it breaks at the end compared with `KNOWN_SEEDS`: the first that breaks
/// anything else (or a check of every step) is cut down to its fewest steps and told whole; a known failure that holds
/// now is named, to be taken out of the table.
export function drawnWorlds(part: number, parts: number): void {
test(`the workspace lock across a world of stations, a plane and devices: never wrong, and one chain once the lines are back but where KNOWN_SEEDS says (part ${part + 1} of ${parts})`, async () => {
  const mine = seeds.filter((s, i) => process.env.LOCK_WORLD_SEED !== undefined ? part === 0 : i % parts === part);
  // A world's failure beyond what is known: a check of every step, or an end's property not in the table for its seed.
  const beyond = (seed: number, error: Error): string[] => {
    if (!(error instanceof EndFailure)) return [`always: ${error.message.split("\n")[0]}`];
    if (seed > KNOWN_UPTO) return [];
    const known = KNOWN_SEEDS[seed] ?? [];
    return codes(error.failed).filter((c) => !known.includes(c));
  };
  const failing: { seed: number; steps: Step[]; held: boolean[]; error: Error; beyond: string[] }[] = [];
  const holdsNow: string[] = [];
  for (const seed of mine) {
    const { steps, held } = draw(seed, STEPS);
    const began = performance.now();
    const failed = await fails(steps, held, seed);
    const got = failed === null ? [] : failed.error instanceof EndFailure ? codes(failed.error.failed) : [];
    const what = failed === null ? "holds" : failed.error instanceof EndFailure ? got.join(", ") : `always: ${failed.error.message.split("\n")[0]}`;
    console.error(`LOCK_WORLD seed ${seed}: ${what}${process.env.LOCK_WORLD_TRACE ? ` in ${Math.round(performance.now() - began)} ms` : ""}`);
    if (failed) {
      const more = beyond(seed, failed.error);
      if (more.length > 0) failing.push({ seed, steps, held, error: failed.error, beyond: more });
    }
    if (seed <= KNOWN_UPTO && (failed === null || failed.error instanceof EndFailure)) {
      const back = (KNOWN_SEEDS[seed] ?? []).filter((c) => !got.includes(c));
      if (back.length > 0) holdsNow.push(`${seed}: ${back.join(", ")}`);
    }
  }
  if (failing.length > 0) {
    const first = failing[0]!;
    const fewest = await shrink(first.steps, first.held, first.seed, (f) => beyond(first.seed, f.error).some((c) => first.beyond.includes(c)));
    const again = (await fails(fewest, first.held, first.seed)) ?? { error: first.error, log: [] };
    const named = failing.map((f) => `${f.seed}: ${f.beyond.join(", ")}`);
    assert.fail(`${failing.length} of ${mine.length} seeds break what KNOWN_SEEDS does not say (${named.join("; ")})\nLOCK_WORLD_SEED=${first.seed}: ${again.error.message}\n${fewest.length} of ${STEPS} steps still do:\n${again.log.join("\n")}`);
  }
  assert.deepEqual(holdsNow, [], "holds now: take it out of KNOWN_SEEDS");
});
}

// The workspace lock across a whole world, tested by its properties (run by lock-world-<n>.test.ts, a part each): the control plane, three
// stations (their own code: cloud.json and lock.json on disk, the presence socket's frames, the mesh's lock sync, a
// device's hello) and the members' devices, each step drawn from a seed: an entry signed on a device and brought to the
// plane and the stations, a device connecting, a line cut or back, a station stopped or started, the plane holding
// back or forging. What goes over a line is held, reordered (each socket keeps its order) and lost with the line, as the
// seed says. After every step what must always hold is checked: no two chains disagree, the plane keeps only what the
// stations take, nothing a forger made is taken or lets anyone in, nobody is let in whom the station's own chain does
// not name. At the end the lines come back (the plane still holding back from some stations) and what must come about
// is checked: every station level with the longest chain, the plane too once one station reaches it, every approved
// device let in everywhere and every removed one nowhere. A failure is cut down to the fewest steps that still fail and
// says its seed: LOCK_WORLD_SEED=<seed> runs only that one (LOCK_WORLD_RUNS=<n> runs n seeds from 1). There are two
// workspaces, each its own lock: every station's home one, and one two of them joined.
import assert from "node:assert/strict";
import { createPrivateKey, createPublicKey, sign as nodeSign } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { extendLock, LockAppendRefused } from "../../cloud/src/lock.ts";
import { type Entry, apply, endpointBytes, entryHash, fold, signedBytes } from "../src/cloud/lock.ts";
import { applyState, planeTeller } from "../src/cloud/presence.ts";
import { Cloud, readLock, writeState } from "../src/cloud/state.ts";
import type { Admitted } from "../src/mesh/credential.ts";
import { answerLock, followLock } from "../src/mesh/lock-sync.ts";
import { inLockBringing, lockRoute } from "../src/mesh/serve.ts";

const WS = "01HWORLDWORLDWORLDWORLDWOR";
/// The workspace s0 and s1 joined besides their home one.
const WB = "01HWORLDWORLDWORLDWORLDWOB";
const ORIGIN = "https://app.still.fail";
/// When a world starts (unix ms); its clock moves only as its steps say.
const START = Date.UTC(2026, 10, 4, 9, 0, 0);

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
/// each person's two more, none signing (a phone, a laptop). Eve is nobody's: only a forger names her device.
const PEOPLE = [
  { sub: "alice", role: "owner" },
  { sub: "bob", role: "admin" },
  { sub: "carol", role: "member" },
] as const;
const signers = PEOPLE.map((p, i) => ({ ...p, app: key(100 + i), signer: key(200 + i) }));
const spare = PEOPLE.flatMap((p, i) => [0, 1].map((j) => ({ sub: p.sub, base: key(300 + i * 10 + j) })));
const eve = { sub: "carol", base: key(900) };
const eveKey = key(901);
const stationKeys = [0, 1, 2].map((i) => key(500 + i));
const N = stationKeys.length;

const genesisOf = (ws: string, members: number[]) => signed({
  v: 1, ws, seq: 0, prev: null, at: START / 1000, kind: "genesis", body: {
    owner: "alice", origins: [ORIGIN], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: PEOPLE.map((p) => ({ sub: p.sub, email: `${p.sub}@x`, role: p.role })),
    devices: signers.map((s) => ({ id: s.app.hex, sub: s.sub, kind: "app", label: s.sub, sign_key: s.signer.id })),
    passkeys: [], stations: members.map((i) => ({ key: stationKeys[i]!.hex, name: `s${i}` })), gateways: [],
  },
}, signers[0]!.signer);

/// A workspace of the world: its stations, and its lock as the plane keeps it (`plane`), each it kept (`epochs`: turned
/// off and on again, a new one starts).
type Space = { ws: string; name: string; members: number[]; plane: Entry[]; epochs: Entry[][] };
const spaces = (): Space[] =>
  ([[WS, "Team", [0, 1, 2]], [WB, "B", [0, 1]]] as const).map(([ws, name, members]) => {
    const g = genesisOf(ws, [...members]);
    return { ws, name, members: [...members], plane: [g], epochs: [[g]] };
  });
/// A station's own name for a workspace: null for its home one.
const keyOf = (sp: Space) => (sp.ws === WS ? null : sp.ws);

/// One step, as drawn: what kind, and three numbers it picks with (each taken modulo what there is to pick from).
type Step = { k: number; a: number; b: number; c: number };
/// What the steps' kinds are, weighted by how often each comes.
const KINDS = ["deliver", "deliver", "deliver", "deliver", "sign", "sign", "line", "line", "connect", "station", "forge", "time"] as const;

function draw(seed: number, n: number): { steps: Step[]; held: boolean[] } {
  const r = new Rng(seed);
  const steps = Array.from({ length: n }, () => ({ k: r.int(KINDS.length), a: r.int(1 << 16), b: r.int(1 << 16), c: r.int(1 << 16) }));
  // At the end, the stations the plane goes on holding back from (cut off from it, or a hostile plane's choice).
  return { steps, held: stationKeys.map(() => r.int(3) === 0) };
}

/// Something on its way over a line: run when it arrives, `lost` when the line goes first. Each `chan` (a socket's one
/// direction, one request's exchange) keeps its order.
type Msg = { link: string; chan: string; run: () => void; lost?: () => void };

type StationSim = {
  i: number;
  key: Key;
  data: string;
  cloud: Cloud | null;
  stopFollow: (() => void) | null;
  /// Its socket to the plane: its frames' chan down (the way up is chan↑), what it says up it.
  presence: { unlisten: () => void; chan: string; toPlane: (frame: unknown) => void } | null;
};

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
  /// Entries a forger made: none may ever be in a station's chain.
  forged = new Set<string>();
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
      return { i, key: k, data, cloud: null, stopFollow: null, presence: null };
    });
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

  /// A timer on the world's clock (the stations' retries).
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

  send(link: string, chan: string, run: () => void, lost?: () => void) {
    if (!this.up(link)) {
      lost?.();
      return;
    }
    this.queue.push({ link, chan, run, lost });
  }

  /// The messages that may arrive next: each chan's first.
  ready(): Msg[] {
    const seen = new Set<string>();
    return this.queue.filter((m) => !seen.has(m.chan) && (seen.add(m.chan), true));
  }

  async deliver(pick: number): Promise<boolean> {
    const ready = this.ready();
    if (ready.length === 0) return false;
    const m = ready[pick % ready.length]!;
    this.queue.splice(this.queue.indexOf(m), 1);
    m.run();
    await settle();
    return true;
  }

  /// A line cut (what is on it lost) or back.
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
    await settle();
  }

  // ── the stations ────────────────────────────────────────────────────────────────────────────────────────────────

  start(s: StationSim) {
    s.cloud = new Cloud(s.data, false);
    s.stopFollow = followLock(s.cloud, (peer, ws, request) => this.meshCall(s, peer, ws, request), this.after);
    this.connectPresence(s);
  }

  stop(s: StationSim) {
    this.dropPresence(s);
    s.stopFollow?.();
    s.cloud?.close();
    s.cloud = null;
    s.stopFollow = null;
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
    } else if (frame?.type === "lock.put") this.append(sp, frame.entries);
  }

  /// Entries brought to the plane: taken as the cloud takes them, every station on a socket told of the new head.
  append(sp: Space, entries: Entry[]): boolean {
    let plan;
    try {
      plan = extendLock(sp.plane as never, entries as never, Math.floor(this.t / 1000));
    } catch (e) {
      if (e instanceof LockAppendRefused) return false;
      throw e;
    }
    if (plan.adding.length === 0) return true;
    sp.plane = plan.restart ? (plan.adding.map((a) => a.e) as Entry[]) : [...sp.plane, ...(plan.adding.map((a) => a.e) as Entry[])];
    if (plan.restart) sp.epochs.push(sp.plane);
    else sp.epochs[sp.epochs.length - 1] = sp.plane;
    for (const s of this.stations) {
      if (s.presence) this.sendState(s, `${s.presence.chan}↓`, s.presence.toPlane);
    }
    return true;
  }

  // ── devices ─────────────────────────────────────────────────────────────────────────────────────────────────────

  /// A person's app signs one more entry after the chain as the plane has it, brings it there, and once it is taken
  /// brings the whole chain to each station it reaches (views/lock.ts `append`). Its request or the answer may be lost.
  sign(who: number, what: number, pick: number) {
    const by = signers[who % signers.length]!;
    const sp = this.sp[(what >> 4) % this.sp.length]!;
    const chan = `dc#${this.chanSeq++}`;
    this.send("dc", chan, () => {
      const chain = [...sp.plane];
      const state = fold(chain, null);
      const at = Math.floor(this.t / 1000);
      let body: unknown, kind: string;
      const inLock = spare.filter((d) => state.devices.has(d.base.hex));
      const outOfLock = spare.filter((d) => !state.devices.has(d.base.hex));
      // Turned off now and then, and on again once it is off.
      if (state.disabled) return this.reopen(sp, by === signers[0] ? 0 : -1);
      switch (what % 4 === 2 && pick % 5 === 0 ? 4 : what % 4) {
        case 4: {
          if (by !== signers[0]) return;
          kind = "disable";
          body = {};
          break;
        }
        case 0: {
          const d = outOfLock[pick % Math.max(1, outOfLock.length)];
          if (!d) return;
          kind = "device";
          body = { id: d.base.hex, sub: d.sub, kind: "app", label: `${d.sub}'s` };
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
      const entry = signed(after(chain, at, kind, body), by.signer);
      // The core checks it as the stations will before it goes (vault/lock-check.ts): one they refuse is not sent.
      try {
        apply(state, entry, at);
      } catch {
        return;
      }
      this.log.push(`  ${by.sub} signs ${kind} ${JSON.stringify(body)} at ${entry.seq} in ${sp.name}`);
      this.send("dc", chan, () => {
        const taken = this.append(sp, [entry]);
        if (!taken) return;
        this.send("dc", chan, () => {
          const whole = [...chain, entry];
          for (const s of this.stations.filter((x) => sp.members.includes(x.i))) {
            this.send(`d${s.i}`, `d${s.i}#${this.chanSeq++}`, () => {
              if (s.cloud) lockRoute(s.cloud, "POST", [], Buffer.from(JSON.stringify({ entries: whole })), viewer(by.app, by.sub, "owner", sp.ws));
            });
          }
        });
      });
    });
  }

  /// The owner turns the lock on again (views/lock.ts `open`): a new genesis with the people and devices of the one
  /// turned off, and the stations its app reaches that hold no lock (one that still holds the old one is left out, as
  /// the draft lists it `other`); to the plane, then
  /// brought to each of them.
  reopen(sp: Space, owner: number) {
    if (owner !== 0) return;
    const last = fold(sp.plane, null);
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
    const chan = `dc#${this.chanSeq++}`;
    this.send("dc", chan, () => {
      if (!this.append(sp, [g])) return;
      this.send("dc", chan, () => {
        for (const s of reached) {
          this.send(`d${s.i}`, `d${s.i}#${this.chanSeq++}`, () => {
            if (s.cloud) lockRoute(s.cloud, "POST", [], Buffer.from(JSON.stringify({ entries: [g] })), viewer(signers[0]!.app, "alice", "owner", sp.ws));
          });
        }
      });
    });
  }

  /// A device says hello to a station, bringing the entries from the one that put it in the lock, as the plane has
  /// them (at most 64): let in or not, and is that right?
  connect(which: number, at: number, bring = true, inSpace = 0): boolean | null {
    const devices = [...spare, eve, ...signers.map((s) => ({ sub: s.sub, base: s.app }))];
    const d = devices[which % devices.length]!;
    const sp = this.sp[inSpace % this.sp.length]!;
    const s = this.stations[at % N]!;
    if (s.cloud === null || !this.up(`d${s.i}`) || !sp.members.includes(s.i)) return null;
    // A joined workspace with no lock pinned: the station takes none of its members (Cloud.leftOut), refused before this.
    if (sp.ws !== WS && s.cloud.locked(sp.ws) === null) return null;
    const from = sp.plane.findLastIndex((e) => e.kind === "device" && (e.body as { id?: string }).id === d.base.hex);
    const entries = from < 0 || !bring || !this.up("dc") ? [] : sp.plane.slice(from, from + 64);
    const hello = entries.length > 0 ? { lock: { entries } } : {};
    let inside: boolean;
    try {
      inLockBringing(s.cloud, admitted(d.base, d.sub, sp.ws), "member", d.base.hex, hello);
      inside = true;
    } catch {
      inside = false;
    }
    const mine = s.cloud.locked(keyOf(sp))?.state;
    // Let in only as the station's own chain says: the device in it, its member's; with no lock, as the plane says.
    const named = mine?.devices.get(d.base.hex);
    assert.equal(inside, mine === undefined || (named !== undefined && named.sub === d.sub), `s${s.i} ${inside ? "let in" : "turned away"} in ${sp.name} ${d.sub}'s device ${d.base.hex.slice(0, 8)} its chain ${named ? "names" : "does not name"}`);
    // (With no lock, the plane's word is taken as it was before: it signs the credentials.)
    assert.ok(!(inside && d === eve && mine !== undefined), "a device only a forger named is let in");
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
      if (sp.members.includes(s.i)) out.push({ who: `s${s.i}'s ${sp.name}`, chain: s.cloud?.lockAfter(-1, keyOf(sp)) ?? readLock(s.data, keyOf(sp))?.entries ?? [] });
    }
    return out;
  }

  /// What must always hold.
  invariants() {
    for (const sp of this.sp) this.holds(sp);
  }

  holds(sp: Space) {
    const all = this.chains(sp);
    for (const { who, chain } of all) {
      if (chain.length === 0) continue;
      assert.doesNotThrow(() => fold(chain, null), `${who}'s chain does not check out`);
      for (const e of chain) assert.ok(!this.forged.has(entryHash(e)), `${who} took a forged entry at ${e.seq}`);
      // Of a lock the plane kept: what it holds, or held before the lock was turned off and on again.
      assert.ok(chain[0]!.ws === sp.ws, `${who} is another workspace's`);
      assert.ok(sp.epochs.some((h) => h.length >= chain.length && entryHash(h[chain.length - 1]!) === entryHash(chain.at(-1)!)), `${who}'s chain is no lock the plane kept`);
    }
    for (const x of all) {
      for (const y of all) {
        if (x.chain.length === 0 || y.chain.length === 0 || entryHash(x.chain[0]!) !== entryHash(y.chain[0]!)) continue;
        const n = Math.min(x.chain.length, y.chain.length);
        for (let i = 0; i < n; i++) assert.equal(entryHash(x.chain[i]!), entryHash(y.chain[i]!), `${x.who} and ${y.who} disagree at ${i}`);
      }
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
      }
      this.invariants();
    }
    // The end: every station up, every line back but the plane's to those it holds back from; whatever is on its way
    // arrives, and time goes on until nothing is left to happen.
    // The mesh last, once all else settled: what it carries then is all that may bring a held-back station level.
    for (const s of this.stations) if (s.cloud === null) this.start(s);
    for (const line of this.allLines()) if (!line.startsWith("m")) await this.setLine(line, !(/^p(\d)$/.test(line) && held[Number(line.slice(1))]));
    await this.drain();
    for (const line of this.allLines()) if (line.startsWith("m")) await this.setLine(line, true);
    this.log.push(`end: the plane holds back from ${held.flatMap((h, i) => (h ? [`s${i}`] : [])).join(", ") || "none"}`);
    await this.drain();
    this.invariants();
    for (const sp of this.sp) this.converged(sp, held);
  }

  /// Whatever is on its way arrives, and time goes on (two days at most) until nothing is left to happen.
  async drain() {
    const until = this.t + 48 * 3600_000;
    for (let n = 0; n < 10_000; n++) {
      if (await this.deliver(this.rng.int(1 << 16))) continue;
      if (this.timers.length === 0 || this.timers[0]!.at > until) break;
      await this.pass(Math.max(0, this.timers[0]!.at - this.t));
    }
  }

  /// What must come about once the lines are back.
  converged(sp: Space, held: boolean[]) {
    const all = this.chains(sp);
    const mine = (i: number) => this.stations[i]!.cloud!.locked(keyOf(sp));
    // The stations the lock names in the end: one taken out of it is no longer brought level by the others. Turned off
    // in the end: each such station the plane reaches holds none.
    const end = fold(sp.plane, null);
    const named = end.stations;
    if (end.disabled) {
      for (const i of sp.members) if (!held[i]) assert.equal(mine(i), null, `s${i} keeps ${sp.name}'s lock turned off`);
      return;
    }
    // None the plane reaches keeps a lock turned off since: it hears the rest of that chain, its end with it.
    for (const i of sp.members) {
      const g = mine(i)?.state?.genesis;
      if (!held[i] && g !== undefined) assert.equal(g, entryHash(sp.plane[0]!), `s${i} keeps ${sp.name}'s lock turned off and on again since`);
    }
    const stations = all.slice(1).filter((_, n) => named.has(stationKeys[sp.members[n]!]!.hex));
    const longest = stations.reduce((x, y) => (y.chain.length > x.chain.length ? y : x));
    for (const s of stations) assert.equal(s.chain.length, longest.chain.length, `${s.who} stays at ${s.chain.length - 1}, ${longest.who} has ${longest.chain.length - 1}`);
    if (held.some((h, i) => !h && sp.members.includes(i) && named.has(stationKeys[i]!.hex))) {
      assert.equal(longest.chain.length, sp.plane.length, `the plane's ${sp.name} is at ${sp.plane.length - 1}, the stations at ${longest.chain.length - 1}`);
    }
    // Who is let in: each device as the final chain says, at every station.
    const state = fold(longest.chain, null);
    for (let d = 0; d < spare.length + 1 + signers.length; d++) {
      for (let i = 0; i < N; i++) {
        if (!sp.members.includes(i) || !named.has(stationKeys[i]!.hex)) continue;
        const devices = [...spare, eve, ...signers.map((s) => ({ sub: s.sub, base: s.app }))];
        const inside = this.connect(d, i, false, this.sp.indexOf(sp));
        const want = state.devices.has(devices[d]!.base.hex);
        assert.equal(inside, want, `${devices[d]!.sub}'s device ${devices[d]!.base.hex.slice(0, 8)} ${want ? "approved but turned away" : "removed but let in"} at s${i} in ${sp.name}`);
      }
    }
  }

  close() {
    for (const s of this.stations) this.stop(s);
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

/// The fewest steps that still fail: chunks taken out, halving, as long as it still fails (with any error).
async function shrink(steps: Step[], held: boolean[], seed: number): Promise<Step[]> {
  let now = steps;
  let tries = 0;
  for (let size = Math.floor(now.length / 2); size >= 1; size = Math.floor(size / 2)) {
    for (let at = 0; at + size <= now.length && tries < 400; tries++) {
      const less = [...now.slice(0, at), ...now.slice(at + size)];
      if (await fails(less, held, seed)) now = less;
      else at += size;
    }
  }
  return now;
}

/// The two worlds told step by step, in the first part (lock-world-1.test.ts).
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
}

const STEPS = 160;
const RUNS = Number(process.env.LOCK_WORLD_RUNS ?? 30);
const seeds = process.env.LOCK_WORLD_SEED ? [Number(process.env.LOCK_WORLD_SEED)] : Array.from({ length: RUNS }, (_, i) => i + 1);

/// The worlds drawn from the seeds of part `part` of `parts` (every `parts`-th from `part + 1`): the parts are files of
/// their own (lock-world-<n>.test.ts), run beside each other, so the slowest file of the station's tests is a third of
/// what it was.
export function drawnWorlds(part: number, parts: number): void {
test(`the workspace lock across a world of stations, a plane and devices: never wrong, and level once the lines are back (part ${part + 1} of ${parts})`, async () => {
  for (const seed of seeds.filter((s, i) => process.env.LOCK_WORLD_SEED !== undefined ? part === 0 : i % parts === part)) {
    const { steps, held } = draw(seed, STEPS);
    const began = performance.now();
    const failed = await fails(steps, held, seed);
    if (process.env.LOCK_WORLD_TRACE) console.error(`seed ${seed}: ${failed ? "fails" : "holds"} in ${Math.round(performance.now() - began)} ms`);
    if (!failed) continue;
    const fewest = await shrink(steps, held, seed);
    const again = (await fails(fewest, held, seed)) ?? failed;
    assert.fail(`LOCK_WORLD_SEED=${seed}: ${again.error.message}\n${fewest.length} of ${STEPS} steps still fail:\n${again.log.join("\n")}`);
  }
});
}

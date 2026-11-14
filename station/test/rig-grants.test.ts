// A rig's own record of who may use it (rig/grants.ts, a station that only runs tasks): only what its person signed with a key on the lock
// the rig pinned counts; a grant lasts as a vault's does (fixed, or until idle, a running task being use); taken
// back or 免批准 turned off, what the chats left without a grant run there stops.
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { type GrantBody, type Kind, type Timeout, latest, signedBytes } from "../../client/core-ts/src/rig-form.ts";
import { type Entry, entryHash, signedBytes as entryBytes } from "../src/cloud/lock.ts";
import { applyState } from "../src/cloud/presence.ts";
import { Cloud, MODE_PENDING_S, readState, rigGrantsPath, writeState } from "../src/cloud/state.ts";
import { Fibers } from "../src/ops/fibers.ts";
import { type Ended, RigGrants } from "../src/rig/grants.ts";
import { testClock } from "./hub-fakes.ts";

const WS = "01WORKSPACE";
const RIG = "aa".repeat(32);
const STATION = "bb".repeat(32);
const OTHER = "cc".repeat(32);
const START = 1_800_000_000_000;
const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest();

function ed() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const hex = (publicKey.export({ format: "der", type: "spki" }) as Buffer).subarray(-32).toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Uint8Array) => nodeSign(null, bytes, privateKey).toString("hex") };
}
type Key = ReturnType<typeof ed>;

/// A person's own lock: its chain as made so far, and a statement signed by one of its keys.
function person(sub: string) {
  const first = ed();
  const chain: Entry[] = [];
  const add = (kind: string, body: unknown, by: Key) => {
    const last = chain[chain.length - 1];
    const e = { v: 1, ws: `person:${sub}`, seq: chain.length, prev: last ? entryHash(last) : null, at: 1000, kind, body } as Omit<Entry, "sig">;
    chain.push({ ...e, sig: { key: by.id, alg: "Ed25519", sig: by.sign(entryBytes(entryHash(e as Entry))) } } as Entry);
  };
  add("genesis", { sub, device: { key: first.id, id: ed().hex, label: "first" } }, first);
  const says = <B>(kind: Kind, body: B, by: Key = first) => ({ body, sig: { key: by.id, sig: by.sign(signedBytes(kind, body, sha256)) } });
  return { sub, first, chain, add, says, genesis: () => entryHash(chain[0]!) };
}

async function world() {
  const dir = mkdtempSync(join(tmpdir(), "rig-grants-"));
  const time = testClock();
  await time.adjust(START);
  const fibers = new Fibers("rig-test", time.clock);
  const owner = person("pat");
  const busy = new Set<string>();
  const stopped: string[] = [];
  const ended: Ended[] = [];
  const cuts: string[] = [];
  let changes = 0;
  const make = () => new RigGrants({
    path: join(dir, "grants.json"),
    self: () => ({ id: RIG, workspace: WS, owner: "pat", person: owner.genesis() }),
    busy: (station, session) => busy.has(`${station}/${session}`),
    stop: (station, session) => void stopped.push(`${station}/${session}`),
    running: () => [...busy].map((k) => ({ station: k.split("/")[0]!, session: k.split("/")[1]! })),
    ended: (e) => void ended.push(e),
    changed: () => void changes++,
    cut: (device, station, session) => void cuts.push(`${device}:${station ?? "*"}/${session ?? "*"}`),
    fibers,
  });
  const now = () => Math.floor(fibers.now() / 1000);
  const grant = (request: string, session: string, timeout: Timeout, more: Partial<GrantBody> = {}, by?: Key) => {
    const at = now();
    return owner.says("grant", { v: 1, sub: "pat", ws: WS, rig: RIG, station: STATION, session, chat: `CHAT/${session}`, request, title: `chat ${session}`, by: "lee@example.com", timeout, at, exp: latest(at, timeout), ...more } as GrantBody, by);
  };
  return {
    owner, make, grant, busy, stopped, ended, cuts, now, changes: () => changes,
    pass: (ms: number) => time.adjust(ms),
    close: async () => {
      await fibers.close();
      rmSync(dir, { recursive: true, force: true });
    },
  };
}

test("only what the rig's person signed with a key on the lock it pinned gives a chat the rig", async () => {
  const w = await world();
  try {
    const rig = w.make();
    assert.match(rig.refusal(WS, STATION, "s1")!, /no grant of this station, which only runs tasks: ask for one with station_use/);
    assert.match(rig.refusal("other", STATION, "s1")!, /another workspace/);
    const signed = w.grant("r1", "s1", { kind: "idle", seconds: 3600 });
    // Its person's lock comes with it; without the lock, the key is not known.
    assert.throws(() => rig.grant(STATION, signed), /not on this rig's person's own lock/);
    // Brought by another station than its chat's, for another rig, by someone else, with a body changed: none counts.
    assert.throws(() => rig.grant(OTHER, signed, w.owner.chain), /brought by its chat's own station/);
    assert.throws(() => rig.grant(STATION, w.grant("r1", "s1", { kind: "idle", seconds: 3600 }, { rig: "dd".repeat(32) }), w.owner.chain), /another rig or workspace/);
    assert.throws(() => rig.grant(STATION, w.grant("r1", "s1", { kind: "idle", seconds: 3600 }, { sub: "mallory" }), w.owner.chain), /not signed by this rig's person/);
    assert.throws(() => rig.grant(STATION, { ...signed, body: { ...signed.body, session: "s2" } }, w.owner.chain), /signature does not hold/);
    const stranger = ed();
    assert.throws(() => rig.grant(STATION, w.grant("r1", "s1", { kind: "idle", seconds: 3600 }, {}, stranger), w.owner.chain), /not on this rig's person's own lock/);
    // Another person's lock is not the one pinned, whatever it says.
    assert.throws(() => rig.grant(STATION, signed, person("pat").chain), /not the one this rig's person pinned/);
    assert.match(rig.refusal(WS, STATION, "s1")!, /no grant/);

    assert.deepEqual(rig.grant(STATION, signed, w.owner.chain), { until: signed.body.exp });
    assert.equal(rig.refusal(WS, STATION, "s1"), null);
    // The chat it names on the station it names, and no other.
    assert.match(rig.refusal(WS, STATION, "s2")!, /no grant/);
    assert.match(rig.refusal(WS, OTHER, "s1")!, /no grant/);
    assert.equal(rig.stationRefusal(WS, STATION), null);
    assert.match(rig.stationRefusal(WS, OTHER)!, /no chat of that station/);
    assert.deepEqual(rig.view()!.grants.map((g) => [g.request, g.station, g.session, g.title, g.by, g.timeout.kind]), [["r1", STATION, "s1", "chat s1", "lee@example.com", "idle"]]);

    // A device added to the person's lock signs from then on; one taken off it signs nothing more, an older chain
    // brought again notwithstanding.
    const second = ed();
    w.owner.add("device", { key: second.id, id: ed().hex, label: "second" }, w.owner.first);
    assert.deepEqual(rig.grant(STATION, w.grant("r2", "s2", { kind: "fixed", seconds: 600 }, {}, second), w.owner.chain), { until: w.now() + 600 });
    const before = [...w.owner.chain];
    w.owner.add("device.remove", { key: second.id }, w.owner.first);
    rig.takeChain(w.owner.chain);
    assert.throws(() => rig.grant(STATION, w.grant("r3", "s3", { kind: "fixed", seconds: 600 }, {}, second), before), /not on this rig's person's own lock/);
  } finally {
    await w.close();
  }
});

test("a grant ends when its time is up or the chat has used the rig for nothing that long; a running task is use", async () => {
  const w = await world();
  try {
    const rig = w.make();
    rig.grant(STATION, w.grant("fixed", "s1", { kind: "fixed", seconds: 600 }), w.owner.chain);
    rig.grant(STATION, w.grant("idle", "s2", { kind: "idle", seconds: 600 }), w.owner.chain);
    // Used at five minutes: the idle one goes on from there, the fixed one does not.
    await w.pass(300_000);
    assert.equal(rig.refusal(WS, STATION, "s1"), null);
    assert.equal(rig.refusal(WS, STATION, "s2"), null);
    await w.pass(300_000);
    assert.deepEqual(w.ended, [{ request: "fixed", station: STATION, session: "s1", why: "expired" }]);
    assert.deepEqual(w.stopped, [`${STATION}/s1`]);
    assert.match(rig.refusal(WS, STATION, "s1")!, /no grant/);
    // A task of the chat's still running at the idle time: the grant holds while it runs.
    w.busy.add(`${STATION}/s2`);
    await w.pass(600_000);
    await w.pass(600_000);
    assert.equal(w.ended.length, 1);
    w.busy.delete(`${STATION}/s2`);
    await w.pass(600_000);
    assert.deepEqual(w.ended.at(-1), { request: "idle", station: STATION, session: "s2", why: "idle" });
    assert.deepEqual(w.stopped, [`${STATION}/s1`, `${STATION}/s2`]);
    assert.deepEqual(rig.view()!.grants, []);
  } finally {
    await w.close();
  }
});

test("a grant is kept across a restart, taken back by its person's word alone, and given back by its own station", async () => {
  const w = await world();
  try {
    let rig = w.make();
    const signed = w.grant("r1", "s1", { kind: "idle", seconds: 3600 });
    rig.grant(STATION, signed, w.owner.chain);
    rig.grant(STATION, w.grant("r2", "s2", { kind: "idle", seconds: 3600 }), w.owner.chain);
    await rig.close();
    rig = w.make();
    assert.equal(rig.refusal(WS, STATION, "s1"), null, "kept with the lock it was checked against");

    // Given back: by its chat's station only.
    assert.equal(rig.release(OTHER, "r2"), false);
    assert.equal(rig.release(STATION, "r2"), true);
    assert.deepEqual(w.ended.at(-1), { request: "r2", station: STATION, session: "s2", why: "released" });

    // Taken back: signed by its person; a stranger's word is none. Brought again after, the grant counts for nothing.
    const revoke = { v: 1 as const, sub: "pat", ws: WS, rig: RIG, request: "r1", at: w.now() };
    assert.throws(() => rig.revoke(w.owner.says("revoke", revoke, ed())), /not on this rig's person's own lock/);
    assert.equal(rig.refusal(WS, STATION, "s1"), null);
    rig.revoke(w.owner.says("revoke", revoke));
    assert.deepEqual(w.ended.at(-1), { request: "r1", station: STATION, session: "s1", why: "revoked" });
    assert.match(rig.refusal(WS, STATION, "s1")!, /no grant/);
    assert.throws(() => rig.grant(STATION, signed, w.owner.chain), /taken back/);
  } finally {
    await w.close();
  }
});

test("免批准: on, every chat of the workspace uses the rig; off again, those with no grant lose what they run", async () => {
  const w = await world();
  try {
    const rig = w.make();
    const settings = (seq: number, open: boolean) => w.owner.says("settings", { v: 1 as const, sub: "pat", ws: WS, rig: RIG, seq, open, at: w.now() });
    assert.equal(rig.open(), false);
    assert.throws(() => rig.settings(w.owner.says("settings", { v: 1 as const, sub: "pat", ws: WS, rig: RIG, seq: 1, open: true, at: w.now() }, ed()), w.owner.chain), /not on this rig's person's own lock/);
    rig.settings(settings(1, true), w.owner.chain);
    assert.equal(rig.open(), true);
    assert.equal(rig.refusal(WS, OTHER, "anyone"), null);
    assert.equal(rig.stationRefusal(WS, OTHER), null);
    assert.match(rig.refusal("other", OTHER, "anyone")!, /another workspace/);
    // One chat holds a grant besides; both run something.
    rig.grant(STATION, w.grant("r1", "s1", { kind: "idle", seconds: 3600 }), w.owner.chain);
    w.busy.add(`${STATION}/s1`);
    w.busy.add(`${OTHER}/free`);
    // Settings from before cannot be brought again.
    rig.settings(settings(2, false));
    assert.equal(rig.open(), false);
    assert.deepEqual(w.stopped, [`${OTHER}/free`], "the chat with a grant goes on");
    assert.throws(() => rig.settings(settings(1, true)), /older than the settings/);
    assert.equal(rig.open(), false);
    assert.match(rig.refusal(WS, OTHER, "free")!, /no grant/);
    assert.equal(rig.refusal(WS, STATION, "s1"), null);
  } finally {
    await w.close();
  }
});

test("whole again: only its person's signature, lately made, is kept for it", async () => {
  const w = await world();
  try {
    const rig = w.make();
    const full = (at: number, by?: Key) => w.owner.says("full", { v: 1 as const, sub: "pat", ws: WS, rig: RIG, at }, by);
    assert.throws(() => rig.full(full(w.now())), /not on this rig's person's own lock/);
    assert.throws(() => rig.full(full(w.now(), ed()), w.owner.chain), /not on this rig's person's own lock/);
    assert.throws(() => rig.full(w.owner.says("full", { v: 1 as const, sub: "mallory", ws: WS, rig: RIG, at: w.now() }), w.owner.chain), /not signed by this rig's person/);
    assert.throws(() => rig.full(full(w.now() - 2 * 3600), w.owner.chain), /signed too long ago/);
    // (a grant's signature is none for it)
    const grant = w.grant("r1", "s1", { kind: "idle", seconds: 3600 });
    assert.throws(() => rig.full({ body: { v: 1, sub: "pat", ws: WS, rig: RIG, at: grant.body.at }, sig: grant.sig }, w.owner.chain), /signature does not hold/);
    assert.equal(rig.full(full(w.now()), w.owner.chain).body.sub, "pat");
  } finally {
    await w.close();
  }
});

test("what a machine is changes only by what was asked of it and the control plane listing it so, never by either alone", () => {
  const data = mkdtempSync(join(tmpdir(), "rig-mode-"));
  const now = Math.floor(Date.now() / 1000);
  const base = { origin: "https://app.still.fail", station: STATION, workspace: WS, workspace_name: "Home", name: "nas", peers: [] };
  const frame = (more: object) => JSON.stringify({ type: "state", workspace: WS, workspace_name: "Home", name: "nas", peers: [{ id: OTHER, name: "willow" }], ...more });
  const pat = { owner: "pat", owner_email: "pat@example.com", owner_name: "Pat", person: "ee".repeat(32) };
  try {
    // A whole station: the plane listing it as someone's rig changes nothing by itself.
    writeState(data, base as any);
    let s = new Cloud(data, false);
    applyState(s, frame({ rig: { owner: "pat" } }));
    assert.equal(readState(data)!.rig, undefined);
    assert.equal(readState(data)!.rig_due, undefined);
    // Asked by a member's device (their own lock to pin), then listed as theirs: due to become one. Listed as
    // another's, or in a second workspace, it is not.
    s.update((st) => void (st.rig_pending = { ...pat, at: now }));
    applyState(s, frame({ rig: { owner: "mallory" } }));
    assert.equal(readState(data)!.rig_due, undefined);
    applyState(s, frame({ rig: { owner: "pat" }, workspaces: [{ workspace: "01OTHER", workspace_name: "Other", name: "nas", peers: [] }] }));
    assert.equal(readState(data)!.rig_due, undefined);
    applyState(s, frame({ rig: { owner: "pat" } }));
    assert.equal(readState(data)!.rig_due, true);
    assert.equal(readState(data)!.rig, undefined, "it stops what it runs as a station first (sessions/agents.ts)");
    // What was asked too long ago is forgotten.
    s.update((st) => {
      delete st.rig_due;
      st.rig_pending = { ...pat, at: now - MODE_PENDING_S - 60 };
    });
    applyState(s, frame({ rig: { owner: "pat" } }));
    assert.deepEqual([readState(data)!.rig_due, readState(data)!.rig_pending], [undefined, undefined]);
    s.close();

    // A rig: the plane listing it as a whole station changes nothing by itself (a plane from before rigs says so of all).
    const { at: _, ...self } = { ...pat, at: 0 };
    writeState(data, { ...base, rig: self } as any);
    mkdirSync(join(data, "rig"), { recursive: true });
    writeFileSync(rigGrantsPath(data), "{}");
    s = new Cloud(data, false);
    applyState(s, frame({}));
    assert.deepEqual(readState(data)!.rig, self);
    // Its person signed it whole (rig.full kept it), and the plane still lists it as theirs: not yet.
    s.update((st) => void (st.full_pending = { at: now }));
    applyState(s, frame({ rig: { owner: "pat" } }));
    assert.deepEqual(readState(data)!.rig, self);
    // Listed as a station: it is one, its person's grants gone with what it was.
    applyState(s, frame({}));
    assert.equal(readState(data)!.rig, undefined);
    assert.equal(readState(data)!.full_pending, undefined);
    assert.equal(existsSync(rigGrantsPath(data)), false);
    s.close();
  } finally {
    rmSync(data, { recursive: true, force: true });
  }
});

test("a device on the rig: attached and taken off only by what its person signed; a chat reaches it by a grant of it or of the rig, or 免批准", async () => {
  const w = await world();
  try {
    const rig = w.make();
    const cam = { id: "0123456789abcdef", name: "cam", kind: "tcp" as const, target: "192.168.1.20:554" };
    const attach = (removed = false, at = w.now()) => w.owner.says("device", { v: 1, sub: "pat", ws: WS, rig: RIG, device: cam, removed, at });
    rig.takeChain(w.owner.chain);
    assert.match(rig.deviceRefusal(WS, STATION, "s1", cam.id)!, /no such device/);
    // Someone else's signature attaches nothing.
    const stranger = person("pat");
    assert.throws(() => rig.device(stranger.says("device", { v: 1, sub: "pat", ws: WS, rig: RIG, device: cam, removed: false, at: w.now() })), /not on this rig's person's own lock/);
    rig.device(attach());
    assert.deepEqual(rig.devices().map((d) => d.name), ["cam"]);
    assert.equal(rig.view()!.devices[0]!.open, false);
    assert.match(rig.deviceRefusal(WS, STATION, "s1", cam.id)!, /no grant of this device: ask for one with device_use/);
    // A grant of the device alone: that device, not the rig's tasks.
    rig.grant(STATION, w.grant("d1", "s1", { kind: "fixed", seconds: 600 }, { device: cam.id }));
    assert.equal(rig.deviceRefusal(WS, STATION, "s1", cam.id), null);
    assert.match(rig.refusal(WS, STATION, "s1")!, /no grant of this station/);
    assert.match(rig.stationRefusal(WS, STATION)!, /no chat of that station has a grant/);
    // A grant of the rig gives its devices too.
    rig.grant(STATION, w.grant("r2", "s2", { kind: "fixed", seconds: 600 }));
    assert.equal(rig.deviceRefusal(WS, STATION, "s2", cam.id), null);
    // A grant of a device the rig does not have is refused.
    assert.throws(() => rig.grant(STATION, w.grant("d9", "s3", { kind: "fixed", seconds: 600 }, { device: "fedcba9876543210" })), /no such device/);
    // 免批准 on the device alone: every chat; off again, those with no grant are looked at again.
    const settings = (seq: number, open: boolean) => w.owner.says("settings", { v: 1, sub: "pat", ws: WS, rig: RIG, seq, open, at: w.now(), device: cam.id });
    rig.settings(settings(1, true));
    assert.equal(rig.deviceRefusal(WS, STATION, "s3", cam.id), null);
    assert.equal(rig.refusal(WS, STATION, "s3") !== null, true);
    rig.settings(settings(2, false));
    assert.deepEqual(w.cuts, [`${cam.id}:*/*`]);
    assert.throws(() => rig.settings(settings(1, true)), /older than the settings this device has/);
    // Its grant over: that chat's connections looked at again.
    await w.pass(601_000);
    rig.view();
    assert.ok(w.cuts.includes(`${cam.id}:${STATION}/s1`));
    // Taken off: the grants of it end, and every connection is looked at again.
    rig.grant(STATION, w.grant("d2", "s4", { kind: "fixed", seconds: 600 }, { device: cam.id }));
    rig.device(attach(true));
    assert.deepEqual(rig.devices(), []);
    assert.ok(w.ended.some((e) => e.request === "d2" && e.why === "removed" && e.device === cam.id));
    // Kept across a restart.
    rig.device(attach(false, w.now() + 1));
    assert.deepEqual(w.make().devices().map((d) => d.id), [cam.id]);
  } finally {
    await w.close();
  }
});

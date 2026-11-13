// A chat's request for a rig (rigs/requests.ts, a station that only runs tasks): asked with a card to the rig's person, approved by what
// their device signed (carried to the rig, not read here), kept while the rig is away, ended as the rig says or as
// its chat is archived; and which rigs a workspace in security mode has (rigs/adds.ts).
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { type GrantBody, type Timeout, latest, signedBytes } from "../../client/core-ts/src/rig-form.ts";
import { type Entry, apply, entryHash, genesis, signedBytes as entryBytes } from "../src/cloud/lock.ts";
import { RigAdds, addRefusal } from "../src/rigs/adds.ts";
import { personChainsOf } from "../src/cloud/state.ts";
import { bring, handover, station as movedStation, world as movedWorld } from "./lock-moved-world.ts";
import { Refused, type RigRequest, RigRequests, said } from "../src/rigs/requests.ts";
import { rigTools } from "../src/rigs/tool.ts";
import { STILLFAIL_SURFACE } from "../src/store/store.ts";

const WS = "work";
const RIG = { id: "aa".repeat(32), name: "build-box", owner: "pat", owner_email: "Pat@Example.com", owner_name: "Pat" };
const SELF = "bb".repeat(32);
const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest();

function ed() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const hex = (publicKey.export({ format: "der", type: "spki" }) as Buffer).subarray(-32).toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Uint8Array) => nodeSign(null, bytes, privateKey).toString("hex") };
}
type Key = ReturnType<typeof ed>;
const says = <B>(kind: "grant" | "revoke" | "settings" | "add", body: B, by: Key) => ({ body, sig: { key: by.id, sig: by.sign(signedBytes(kind, body, sha256)) } });

function world() {
  let now = 1_800_000_000_000;
  const cards: { ts: string; text: string; card: any }[] = [];
  const told: string[] = [];
  const brought: string[] = [];
  const released: { id: string; revoked: boolean }[] = [];
  const heard: RigRequest[] = [];
  const sessions = new Map<string, { archivedAt?: number | null; ws: string | null }>([["s1", { ws: WS }], ["s2", { ws: WS }]]);
  const subscribers: ((c: { type: string; key?: string }) => void)[] = [];
  let n = 0;
  /// How the rig answers a grant brought to it: taken until then, refused, or not reached.
  let rig: { until: number } | { refuses: string } | "away" = "away";
  const hub = {
    store: {
      getSession: (k: string) => sessions.get(k) ?? null,
      starter: () => "lee@example.com",
      latestThread: () => ({ connect: "c", thread: { id: 1, channel: "CHAT", threadTs: "1.0", surface: STILLFAIL_SURFACE } }) as any,
      sessionThreadById: () => ({ connect: "c", thread: { id: 1, channel: "CHAT", threadTs: "1.0", surface: STILLFAIL_SURFACE } }) as any,
      insertMessage: (m: any) => {
        cards.push({ ts: m.ts, text: m.text, card: m.card });
        return [++n];
      },
      pendingCardHeader: (): [{ ts: string }, unknown] | null => (cards.length === 0 ? null : [{ ts: cards.at(-1)!.ts }, cards.at(-1)!.card]),
      withdrawCard: () => true,
      restateCard: (_a: string, _t: number, ts: string, f: (was: any) => any) => {
        const c = cards.find((x) => x.ts === ts)!;
        c.card = f(c.card);
        return true;
      },
      subscribe: (f: (c: { type: string; key?: string }) => void) => void subscribers.push(f),
    },
    chat: () => ({ post: async () => `t${n + 1}` }),
    shared: () => {},
    notify: (_s: string, text: string) => void told.push(text),
  };
  let ids = 0;
  const requests = new RigRequests({
    db: new DatabaseSync(":memory:"), hub, home: () => WS, self: () => SELF, title: (r) => `chat ${r.session}`, now: () => now,
    bring: async (r) => {
      brought.push(r.id);
      if (rig === "away") throw new Error("peer unavailable");
      if ("refuses" in rig) throw new Refused(rig.refuses);
      return rig;
    },
    release: (r, revoke) => void released.push({ id: r.id, revoked: revoke !== null }),
    told: (r) => void heard.push({ ...r }),
    id: () => `r${++ids}`,
  });
  const key = ed();
  const secs = () => Math.floor(now / 1000);
  const grant = (r: RigRequest, timeout: Timeout = r.timeout, more: Partial<GrantBody> = {}) =>
    says("grant", { v: 1, sub: "pat", ws: r.ws, rig: r.rig, station: SELF, session: r.session, chat: r.chat, request: r.id, title: r.title, by: r.by, timeout, at: secs(), exp: latest(secs(), timeout), ...more } as GrantBody, key);
  return {
    requests, cards, told, brought, released, heard, key, grant, secs,
    rigAnswers: (how: typeof rig) => void (rig = how),
    pass: (ms: number) => void (now += ms),
    archive: (s: string) => {
      sessions.set(s, { ...sessions.get(s)!, archivedAt: now });
      for (const f of subscribers) f({ type: "session", key: s });
    },
  };
}

test("asked with a card to the rig's person; what they signed is brought to the rig, and the agent told when it took it", async () => {
  const w = world();
  const r = await w.requests.ask("s1", RIG, WS, "run the GPU benchmark", undefined);
  assert.deepEqual([r.id, r.status, r.rig, r.owner, r.ownerEmail, r.timeout, r.title, r.by], ["r1", "pending", RIG.id, "pat", "pat@example.com", { kind: "idle", seconds: 3600 }, "chat s1", "lee@example.com"]);
  // The card goes to the rig's person, not to whoever started the chat, with what their device signs.
  assert.equal(w.cards[0]!.text, "申请使用 station「build-box」：run the GPU benchmark");
  assert.equal(w.cards[0]!.card.assignee, "pat@example.com");
  assert.deepEqual(w.cards[0]!.card.rig, { request: "r1", rig: RIG.id, name: "build-box", owner: "pat", reason: "run the GPU benchmark", timeout: { kind: "idle", seconds: 3600 }, ws: WS, station: SELF, session: "s1", chat: "CHAT/1.0", title: "chat s1", by: "lee@example.com" });
  assert.match(said(r), /waits for its owner pat@example\.com to approve it on the card/);
  // Asked again while it is open: the same request, no second card.
  assert.equal((await w.requests.ask("s1", RIG, WS, "again", undefined)).id, "r1");
  assert.equal(w.cards.length, 1);

  // Only its person decides, and only for what was asked.
  assert.equal(await w.requests.decide("lee", "r1", WS, w.grant(r), null), "only the rig's owner decides who uses it");
  assert.equal(await w.requests.decide("pat", "r1", "elsewhere", w.grant(r), null), "no such request");
  assert.equal(await w.requests.decide("pat", "r1", WS, w.grant(r, r.timeout, { session: "s2" }), null), "signed for something else than this request");
  assert.equal(await w.requests.decide("pat", "r1", WS, w.grant(r, r.timeout, { exp: w.secs() + 40 * 86400 }), null), "not a rig's grant");
  assert.equal(await w.requests.decide("pat", "r1", WS, { body: {}, sig: {} }, null), "not a rig's grant");
  assert.equal(w.requests.get("r1")!.status, "pending");

  // Approved for two hours fixed (their own choice of time): the rig takes it, the agent is told how to use it.
  w.rigAnswers({ until: w.secs() + 7200 });
  assert.equal(await w.requests.decide("pat", "r1", WS, w.grant(r, { kind: "fixed", seconds: 7200 }), ["the person's lock"]), null);
  const granted = w.requests.get("r1")!;
  assert.deepEqual([granted.status, granted.delivered, granted.until], ["granted", true, w.secs() + 7200]);
  assert.deepEqual(w.brought, ["r1"]);
  assert.match(w.told.at(-1)!, /was granted by pat@example\.com \(for 2 h\): use it as any station, by its name, with station_task/);
  assert.deepEqual(w.cards[0]!.card.rig.outcome, { status: "granted", timeout: { kind: "fixed", seconds: 7200 }, delivered: true, until: w.secs() + 7200 });
  assert.equal(await w.requests.decide("pat", "r1", WS, null, null), "the request is granted already");

  // The rig says it ended (its time up): said in the chat's card and to the agent; the rig is not told what it said.
  w.requests.endedThere("r1", "授权已到期");
  assert.deepEqual([w.requests.get("r1")!.status, w.requests.get("r1")!.why, w.requests.get("r1")!.signed], ["ended", "授权已到期", undefined]);
  assert.match(w.told.at(-1)!, /Your grant r1 of the tasks-only station build-box ended \(授权已到期\)/);
  assert.deepEqual(w.released, []);
  assert.deepEqual(w.cards[0]!.card.rig.outcome, { status: "ended", why: "授权已到期" });
});

test("approved while the rig is away, the grant waits here and is brought when the rig is heard; refused there, it ends refused", async () => {
  const w = world();
  const r = await w.requests.ask("s1", RIG, WS, "a build", { kind: "fixed", seconds: 600 });
  assert.equal(await w.requests.decide("pat", "r1", WS, w.grant(r), null), null);
  let now = w.requests.get("r1")!;
  assert.deepEqual([now.status, now.delivered], ["granted", false]);
  assert.match(w.told.at(-1)!, /was approved by pat@example\.com, but it is not reached now/);
  assert.deepEqual(w.requests.undelivered(WS, RIG.id).map((x) => x.id), ["r1"]);
  // Brought again, still away: the agent is not told a second time.
  const before = w.told.length;
  await w.requests.deliver(w.requests.get("r1")!);
  assert.equal(w.told.length, before);
  // The rig is back.
  w.rigAnswers({ until: w.secs() + 600 });
  await w.requests.deliver(w.requests.get("r1")!);
  now = w.requests.get("r1")!;
  assert.deepEqual([now.status, now.delivered], ["granted", true]);
  assert.match(w.told.at(-1)!, /was granted by pat@example\.com \(for 10 min\)/);
  assert.deepEqual(w.requests.undelivered(WS, RIG.id), []);

  // Another chat's: what was signed does not hold for the rig (a key no longer on its person's lock).
  const second = await w.requests.ask("s2", RIG, WS, "a test run", undefined);
  w.rigAnswers({ refuses: "signed by a key that is not on this rig's person's own lock" });
  assert.equal(await w.requests.decide("pat", second.id, WS, w.grant(second), null), null);
  assert.deepEqual([w.requests.get(second.id)!.status, w.requests.get(second.id)!.why], ["denied", "这台 station 拒绝了这份授权：signed by a key that is not on this rig's person's own lock"]);
  assert.match(w.told.at(-1)!, /was refused \(这台 station 拒绝了这份授权/);
});

test("refused, taken back, handed back, and ended with its chat", async () => {
  const w = world();
  w.rigAnswers({ until: w.secs() + 3600 });
  // Refused: no signature needed.
  const a = await w.requests.ask("s1", RIG, WS, "one", undefined);
  assert.equal(await w.requests.decide("pat", a.id, WS, null, null), null);
  assert.equal(w.requests.get(a.id)!.status, "denied");
  assert.match(w.told.at(-1)!, /was refused\./);

  // Taken back by its person: on what they signed, which goes to the rig.
  const b = await w.requests.ask("s1", RIG, WS, "two", undefined);
  await w.requests.decide("pat", b.id, WS, w.grant(b), null);
  const revoke = (request: string, by = w.key) => says("revoke", { v: 1 as const, sub: "pat", ws: WS, rig: RIG.id, request, at: w.secs() }, by);
  assert.equal(w.requests.revoke("lee", b.id, WS, revoke(b.id), null), "only the rig's owner takes a grant of it back");
  assert.equal(w.requests.revoke("pat", b.id, WS, revoke("other"), null), "signed for something else than this grant");
  assert.equal(w.requests.revoke("pat", b.id, WS, null, null), "not a rig's revoke");
  assert.equal(w.requests.revoke("pat", b.id, WS, revoke(b.id), null), null);
  assert.deepEqual([w.requests.get(b.id)!.status, w.requests.get(b.id)!.why], ["ended", "所有者已收回"]);
  assert.deepEqual(w.released, [{ id: b.id, revoked: true }]);

  // Handed back by its agent (station_use {done: true}): the rig told to let it go; the agent told by the tool's answer.
  const c = await w.requests.ask("s1", RIG, WS, "three", undefined);
  await w.requests.decide("pat", c.id, WS, w.grant(c), null);
  const tools = rigTools({ ask: async () => "", done: (session) => w.requests.release(session, null).map((r) => r.id).join(",") });
  const toldBefore = w.told.length;
  assert.equal(await tools[0]!.run("s1", { done: true }), c.id);
  assert.equal(w.told.length, toldBefore);
  assert.deepEqual(w.released.at(-1), { id: c.id, revoked: false });

  // Its chat archived: a grant is given back, a request still asked is dropped.
  const d = await w.requests.ask("s1", RIG, WS, "four", undefined);
  await w.requests.decide("pat", d.id, WS, w.grant(d), null);
  const e = await w.requests.ask("s2", RIG, WS, "five", undefined);
  w.archive("s1");
  w.archive("s2");
  assert.deepEqual([w.requests.get(d.id)!.status, w.requests.get(d.id)!.why], ["ended", "对话已归档"]);
  assert.deepEqual([w.requests.get(e.id)!.status, w.requests.get(e.id)!.why], ["denied", "对话已归档"]);
  assert.deepEqual(w.released.at(-1), { id: d.id, revoked: false });
  // An archived chat asks for nothing.
  await assert.rejects(w.requests.ask("s2", RIG, WS, "six", undefined), /archived or gone/);
});

test("station_use names its rig, and its timeout is a vault's: idle or fixed, whole minutes, a minute to 30 days", async () => {
  const w = world();
  const tools = rigTools({
    ask: async (session, rig, reason, timeout) => said(await w.requests.ask(session, { ...RIG, name: rig }, WS, reason, timeout)),
    done: () => "",
  });
  await assert.rejects(tools[0]!.run("s1", { reason: "x" }), /station is required/);
  await assert.rejects(tools[0]!.run("s1", { station: "build-box", reason: " " }), /say what you will run/);
  for (const timeout of [{ kind: "idle", seconds: 30 }, { kind: "idle", seconds: 90 }, { kind: "fixed", seconds: 31 * 86400 }, { kind: "always", seconds: 600 }]) {
    await assert.rejects(tools[0]!.run("s1", { station: "build-box", reason: "x", timeout }), /timeout must be idle or fixed/);
  }
  assert.match(await tools[0]!.run("s1", { station: "build-box", reason: "x", timeout: { kind: "fixed", seconds: 86400 } }), /waits for its owner/);
  assert.deepEqual(w.requests.get("r1")!.timeout, { kind: "fixed", seconds: 86400 });
  // Nobody decides for a day: let go as it is next looked at.
  w.pass(86400_000);
  assert.deepEqual(w.requests.of("s1", RIG.id), []);
  assert.deepEqual([w.requests.get("r1")!.status, w.requests.get("r1")!.why], ["denied", "一天内无人处理"]);
});

test("security mode: a rig is the workspace's once its person signed for it with a key the lock knows as theirs", () => {
  const signed = (e: Omit<Entry, "sig">, key: Key): Entry => ({ ...e, sig: { key: key.id, alg: "Ed25519", sig: key.sign(entryBytes(entryHash(e as Entry))) } } as Entry);
  const p = (sub: string) => ({ sub, signer: ed(), base: ed() });
  const alice = p("alice"), pat = p("pat");
  let lock = genesis(signed({ v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body: {
    owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: [{ sub: "alice", email: "a@x", role: "owner" }, { sub: "pat", email: "p@x", role: "member" }],
    devices: [alice, pat].map((d) => ({ id: d.base.hex, sub: d.sub, kind: "app", label: d.sub, sign_key: d.signer.id })),
    passkeys: [], stations: [], gateways: [],
  } }, alice.signer));
  const add = (by: Key, more: Record<string, unknown> = {}) => says("add", { v: 1 as const, sub: "pat", ws: WS, rig: RIG.id, at: 2000, ...more }, by);
  const none = () => new Set<string>();
  assert.equal(addRefusal(add(pat.signer), WS, RIG, lock, none, 3000), null);
  // The owner of the workspace does not sign for another's rig; a stranger's key signs for nothing.
  assert.match(addRefusal(add(alice.signer), WS, RIG, lock, none, 3000)!, /does not know as that member's own/);
  assert.match(addRefusal(add(ed()), WS, RIG, lock, none, 3000)!, /does not know as that member's own/);
  // For this rig, in this workspace, by the person the control plane says it is of.
  assert.match(addRefusal(add(pat.signer, { rig: "cc".repeat(32) }), WS, RIG, lock, none, 3000)!, /another rig or workspace/);
  assert.match(addRefusal(add(pat.signer), "other", RIG, lock, none, 3000)!, /another rig or workspace/);
  assert.match(addRefusal(add(alice.signer, { sub: "alice" }), WS, RIG, lock, none, 3000)!, /not signed by the person this rig is said to be of/);
  assert.match(addRefusal({ ...add(pat.signer), sig: { key: pat.signer.id, sig: "00".repeat(64) } }, WS, RIG, lock, none, 3000)!, /signature does not hold/);
  // A device on their own lock, where they are bound to it, signs as well.
  const personal = ed();
  assert.match(addRefusal(add(personal), WS, RIG, lock, () => new Set([personal.id]), 3000)!, /does not know as that member's own/, "not bound: their own lock is not the workspace's word");
  const chain = signed({ v: 1, ws: "person:pat", seq: 0, prev: null, at: 1000, kind: "genesis", body: { sub: "pat", device: { key: personal.id, id: ed().hex, label: "first" } } }, personal);
  lock = apply(lock, signed({ v: 1, ws: WS, seq: 1, prev: lock.head, at: 2000, kind: "person", body: { sub: "pat", person: entryHash(chain) } }, pat.signer), 2000);
  assert.equal(addRefusal(add(personal), WS, RIG, lock, (g) => (g === entryHash(chain) ? new Set([personal.id]) : new Set()), 3000), null);
  // Out of the workspace, their rigs go with them.
  lock = apply(lock, signed({ v: 1, ws: WS, seq: 2, prev: lock.head, at: 2500, kind: "member.remove", body: { sub: "pat" } }, alice.signer), 2500);
  assert.match(addRefusal(add(pat.signer), WS, RIG, lock, none, 3000)!, /no member who adds rigs here/);
});

test("on a lock moved to its people's logs a rig's add is held by the state in force, made again when a body changes it", () => {
  const mw = movedWorld(WS);
  const said = handover(mw);
  const c = movedStation(mw);
  for (const l of [mw.alice, mw.bob, mw.carol]) bring(c, l, true, WS);
  const rig = { ...RIG, owner: "carol" };
  const adds = new RigAdds({ db: new DatabaseSync(":memory:"), cloud: c, chain: (g) => personChainsOf(c).kept(g), now: () => 3000 });
  assert.equal(adds.take(WS, rig, says("add", { v: 1 as const, sub: "carol", ws: WS, rig: rig.id, at: 2000 }, mw.carol.app.key as unknown as Key)), null);
  assert.equal(adds.holds(WS, rig), true);
  // bob (an admin) takes carol's admit back and admits her again as a viewer, who adds no rigs (a lower role given by
  // a later admit alone changes nothing, rules/src/lock/roster.mbt): bodies of bob's change the state, while the root
  // log's head (a folded chain's word), whose log binds carol and that log's head do not
  const head = c.locked()!.state!.head;
  mw.bob.say("member.remove", { sub: "carol", cancels: [said.carol.h] }, WS);
  mw.bob.say("member", { sub: "carol", email: "carol@x", lock: mw.carol.genesis, role: "viewer" }, WS);
  bring(c, mw.bob, true, WS);
  assert.equal(c.locked()!.state!.head, head);
  assert.equal(c.locked()!.state!.persons.get("carol"), mw.carol.genesis);
  assert.equal(c.locked()!.state!.members.get("carol")?.role, "viewer");
  assert.equal(adds.holds(WS, rig), false, "a viewer's rig is not held");
});

// One station in several workspaces (docs/multi-workspace.md): `stations` keeps the machine, `station_members` each
// workspace it is in. Enrolling moves a station as it always did; joining (/v1/stations/join) adds a workspace. Its
// state says its home (the workspace it joined first) at the top, as before, and the others in `workspaces`.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { exportPKCS8, generateKeyPair } from "jose";
import type { LockEntry } from "../src/lock.ts";
import { harness, type OutboundRequest } from "./harness.ts";
import { signer } from "./lock-signer.ts";

type Harness = Awaited<ReturnType<typeof harness>>;
type As = ReturnType<Harness["as"]>;
const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");

async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}
type Station = Awaited<ReturnType<typeof key>>;

const create = async (owner: As, name: string) => ((await (await owner("POST", "/v1/workspaces", { name })).json()) as any).id as string;
const view = async (who: As, workspace: string) => (await (await who("GET", `/v1/workspaces/${workspace}`)).json()) as any;
const count = async (who: As, workspace: string) => (((await (await who("GET", "/v1/me")).json()) as any).workspaces as any[]).find((w) => w.id === workspace)?.stations;

/** An enrollment token for `workspace`, made by one of its owners. */
async function token(owner: As, workspace: string, name: string): Promise<string> {
  const response = await owner("POST", `/v1/workspaces/${workspace}/enrollments`, { name });
  assert.equal(response.status, 200, `a token for ${workspace}`);
  return ((await response.json()) as any).token;
}

/** The station redeems a token, enrolling (moving) or joining, signed as stations sign it; with `body`, more in it. */
async function enroll(h: Harness, station: Station, token: string, join = false, body: Record<string, unknown> = {}): Promise<{ status: number; body: any }> {
  const signature = await station.sign(`stillfail-station-enroll-v1:${h.origin}:${token}:${station.id}`);
  const response = await h.fetch(join ? "/v1/stations/join" : "/v1/stations/enroll", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token, station: station.id, signature, version: "0.5.0", ...body }),
  });
  return { status: response.status, body: await response.json() };
}

/** A station opens its presence socket, signed as stations sign it. */
async function dial(h: Harness, station: Station) {
  const ts = h.now();
  return h.fetch("/v1/stations/connect", {
    headers: { upgrade: "websocket", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await station.sign(`stillfail-station-connect-v1:${h.origin}:${station.id}:${ts}`) },
  });
}

/** A station's presence socket: what it was told, and how it closed. */
async function connect(h: Harness, station: Station) {
  const response = await dial(h, station);
  assert.equal(response.status, 101);
  const ws = response.webSocket!;
  const frames: any[] = [];
  let pong: (() => void) | null = null;
  const closed = new Promise<number>((resolve) => ws.addEventListener("close", (event) => resolve(event.code), { once: true }));
  ws.addEventListener("message", (event) => (event.data === "pong" ? pong?.() : frames.push(JSON.parse(event.data as string))));
  ws.accept();
  /** Everything it was told since the last time (a pong comes after everything sent before it). */
  const told = async () => {
    await new Promise<void>((resolve) => {
      pong = resolve;
      ws.send("ping");
    });
    return frames.splice(0);
  };
  /** The last state it was told since the last time. */
  const state = async () => (await told()).filter((f) => f.type === "state").at(-1);
  const revokes = async () => (await told()).filter((f) => f.type === "revoke").map((f) => [f.workspace, f.kind, f.id]);
  return { ws, closed, told, state, revokes };
}

const directory = async (h: Harness) => {
  const directories: any = await h.mf.getDurableObjectNamespace("DIRECTORY", "api");
  return directories.get(directories.idFromName("primary")) as { unsplitStations(marks?: boolean): Promise<string[]> };
};

test("stations kept one row each, as before, are split into the machine and its workspace, once", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const home = await create(alice, "Home");
    const x = await key(), y = await key();
    assert.equal((await enroll(h, x, await token(alice, home, "studio"))).status, 200);
    assert.equal((await enroll(h, y, await token(alice, home, "nas"))).status, 200);
    assert.equal((await alice("PATCH", `/v1/workspaces/${home}/stations/${x.id}`, { emoji: "🚀", icon: "glyph:rocket" })).status, 200);
    const before = await view(alice, home);
    const admin = h.as(await h.login("alice"), "admin");
    const listed = async () => (((await (await admin("GET", "/v1/admin/workspaces")).json()) as any).workspaces as any[]).find((w) => w.id === home).stations;
    const listedBefore = await listed();

    // The table as it was, split again (twice: the second finds it split): the same stations, named and marked the same.
    assert.deepEqual(await (await directory(h)).unsplitStations(), ["id", "last_seen", "version"]);
    assert.deepEqual(await view(alice, home), before);
    assert.deepEqual(await listed(), listedBefore);
    assert.equal(await count(alice, home), 2);
    const sx = await connect(h, x);
    const state = await sx.state();
    assert.deepEqual([state.workspace, state.workspace_name, state.name, state.workspaces], [home, "Home", "studio", []]);
    assert.deepEqual(state.peers.map((p: any) => [p.id, p.name, p.version]), [[x.id, "studio", "0.5.0"], [y.id, "nas", "0.5.0"]]);

    // Older still: a table from before emojis and icons.
    assert.deepEqual(await (await directory(h)).unsplitStations(false), ["id", "last_seen", "version"]);
    assert.deepEqual((await view(alice, home)).stations.map((s: any) => [s.id, s.name, s.emoji, s.icon]), [[x.id, "studio", null, null], [y.id, "nas", null, null]]);
    // And it goes on as any: removed, it is let go.
    assert.equal((await alice("DELETE", `/v1/workspaces/${home}/stations/${x.id}`)).status, 200);
    assert.equal(await sx.closed, 4004);
  } finally {
    await h.close();
  }
});

test("a station joins a second workspace: named there; its home's at the top of its state, the other in `workspaces`", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const bobTokens = await h.login("bob");
    const bob = h.as(bobTokens);
    const home = await create(alice, "Home");
    const lab = await create(bob, "Lab");
    assert.equal((await alice("PUT", `/v1/workspaces/${home}/relays`, { relays: ["https://relay-a.example"] })).status, 200);
    assert.equal((await bob("PUT", `/v1/workspaces/${lab}/relays`, { relays: ["https://relay-b.example", "https://relay-a.example/"] })).status, 200);
    assert.equal((await alice("POST", `/v1/workspaces/${home}/members`, { role: "member", emails: ["bob@example.test"] })).status, 200);

    // Enrolled as stations always were: in one workspace, its home.
    const x = await key(), y = await key();
    const first = await enroll(h, x, await token(alice, home, "studio"));
    assert.equal(first.status, 200);
    assert.deepEqual([first.body.workspace, first.body.workspace_name, first.body.name, first.body.home], [home, "Home", "studio", home]);
    assert.equal((await enroll(h, y, await token(alice, home, "nas"))).status, 200);
    const sx = await connect(h, x);
    const sy = await connect(h, y);
    const alone = await sx.state();
    assert.deepEqual([alone.workspace, alone.workspace_name, alone.name, alone.workspaces], [home, "Home", "studio", []], "`workspaces` always, empty in one");
    assert.deepEqual(alone.relay_urls, [h.origin, "https://relay-a.example"]);

    // Joins the lab: in both now, named there as the lab named it; its home stays.
    const joined = await enroll(h, x, await token(bob, lab, "lab box"), true);
    assert.equal(joined.status, 200);
    assert.deepEqual([joined.body.workspace, joined.body.workspace_name, joined.body.name, joined.body.home], [lab, "Lab", "lab box", home]);
    const both = await sx.state();
    assert.deepEqual([both.workspace, both.workspace_name, both.name, both.lock], [home, "Home", "studio", null], "the home's at the top, as before");
    assert.deepEqual(both.peers.map((p: any) => p.id), [x.id, y.id]);
    assert.deepEqual(both.workspaces, [{ workspace: lab, workspace_name: "Lab", name: "lab box", peers: [{ id: x.id, name: "lab box", version: "0.5.0" }], revocations: [], lock: null }]);
    assert.deepEqual(both.relay_urls, [h.origin, "https://relay-a.example", "https://relay-b.example"], "every workspace's relays, each once");
    assert.equal((await sy.state())?.workspaces.length ?? 0, 0, "the home's other station hears nothing of the lab");

    // Each workspace lists it under its own name; the lab's says it is joined there.
    assert.deepEqual((await view(alice, home)).stations.map((s: any) => [s.id, s.name, s.joined]), [[x.id, "studio", undefined], [y.id, "nas", undefined]]);
    assert.deepEqual((await view(bob, lab)).stations.map((s: any) => [s.id, s.name, s.joined]), [[x.id, "lab box", true]]);
    assert.deepEqual([await count(bob, home), await count(bob, lab)], [2, 1]);
    // Renamed and marked in one, it stays as it is in the other.
    assert.equal((await bob("PATCH", `/v1/workspaces/${lab}/stations/${x.id}`, { name: "bench", emoji: "🔬" })).status, 200);
    const renamed = await sx.state();
    assert.deepEqual([renamed.name, renamed.workspaces[0].name], ["studio", "bench"]);
    assert.equal((await view(alice, home)).stations[0].emoji, null);
    // Joining where it is already: only the name.
    const again = await enroll(h, x, await token(bob, lab, "bench 2"), true);
    assert.deepEqual([again.status, again.body.name, again.body.home], [200, "bench 2", home]);
    assert.deepEqual((await view(bob, lab)).stations.map((s: any) => [s.name, s.emoji]), [["bench 2", "🔬"]]);

    // A revocation is its workspace's: told, saying which, to every station in it.
    await sx.told();
    await sy.told();
    const bobSub = (await view(alice, home)).members.find((m: any) => m.email === "bob@example.test").sub;
    assert.equal((await alice("DELETE", `/v1/workspaces/${home}/members/${bobSub}`)).status, 200);
    assert.deepEqual(await sx.revokes(), [[home, "sub", bobSub]]);
    assert.deepEqual(await sy.revokes(), [[home, "sub", bobSub]]);
    // Bob signs out everywhere: his credentials in the lab go, which only the station in the lab hears.
    assert.equal((await h.fetch("/v1/auth/logout", { method: "POST", headers: { authorization: `Bearer ${bobTokens.refresh_token}`, "content-type": "application/json" }, body: '{"all":true}' })).status, 200);
    assert.deepEqual(await sx.revokes(), [[lab, "sub", bobSub]]);
    assert.deepEqual(await sy.revokes(), []);
    // Connecting again, it hears each workspace's with that workspace.
    const later = await (await connect(h, x)).state();
    assert.deepEqual([later.revocations.map((r: any) => r.id), later.workspaces[0].revocations.map((r: any) => r.id)], [[bobSub], [bobSub]]);
  } finally {
    await h.close();
  }
});

test("joining a free workspace has no station limit; an explicit limit is the joined workspace's", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const bob = h.as(await h.login("bob"));
    const home = await create(alice, "Home");
    // Bob's is on the free plan.
    const lab = await create(bob, "Lab");
    const x = await key(), y = await key(), z = await key(), extra = await key();
    assert.equal((await enroll(h, x, await token(alice, home, "studio"))).status, 200);
    assert.equal((await enroll(h, y, await token(alice, home, "nas"))).status, 200);
    const late = await token(bob, lab, "late");
    const extraToken = await token(bob, lab, "extra");
    assert.equal((await enroll(h, x, await token(bob, lab, "x in lab"), true)).status, 200);
    assert.equal((await enroll(h, z, await token(bob, lab, "z"))).status, 200);
    assert.equal((await enroll(h, y, late, true)).status, 200, "a third station can join the free workspace");
    const admin = h.as(await h.login("alice"), "admin");
    assert.equal((await admin("POST", `/v1/admin/workspaces/${lab}/limits`, { members: 1, stations: 3 })).status, 200);
    // An explicit workspace limit still applies when a token is redeemed and when one is requested.
    assert.deepEqual(Object.values(await enroll(h, extra, extraToken, true)), [429, { error: "too_many_stations" }]);
    assert.equal((await bob("POST", `/v1/workspaces/${lab}/enrollments`, { name: "more" })).status, 429);
    assert.deepEqual([await count(alice, home), await count(bob, lab)], [2, 3]);

    // Taken out of its home, it stays in the lab, its home now (at the top of its state, no longer `joined` there).
    const sx = await connect(h, x);
    await sx.told();
    assert.equal((await alice("DELETE", `/v1/workspaces/${home}/stations/${x.id}`)).status, 200);
    const after = await sx.state();
    assert.deepEqual([after.workspace, after.workspace_name, after.name, after.workspaces], [lab, "Lab", "x in lab", []]);
    assert.deepEqual((await view(bob, lab)).stations.map((s: any) => [s.id, s.joined]), [[x.id, undefined], [z.id, undefined], [y.id, true]]);
    assert.deepEqual((await view(alice, home)).stations.map((s: any) => s.id), [y.id]);
    // Taken out of its last, it is let go, as before.
    assert.equal((await bob("DELETE", `/v1/workspaces/${lab}/stations/${x.id}`)).status, 200);
    assert.equal(await sx.closed, 4004);
    assert.equal((await dial(h, x)).status, 404);

    // Enrolling moves, as it always did, out of every other workspace (`join` in its body is not read).
    assert.equal((await enroll(h, y, await token(bob, lab, "y in lab"), true)).status, 200);
    const other = await create(alice, "Other");
    const moved = await enroll(h, y, await token(alice, other, "nas"), false, { join: true });
    assert.deepEqual([moved.status, moved.body.workspace, moved.body.home], [200, other, other]);
    assert.deepEqual([await count(alice, home), await count(bob, lab), await count(alice, other)], [0, 1, 1]);

    // A workspace deleted: its stations leave it, a home taken over by the next; those in no other are let go.
    assert.equal((await enroll(h, y, await token(alice, home, "nas again"), true)).status, 200);
    const sy = await connect(h, y);
    await sy.told();
    assert.equal((await alice("DELETE", `/v1/workspaces/${other}`)).status, 200);
    const left = await sy.state();
    assert.deepEqual([left.workspace, left.name, left.workspaces], [home, "nas again", []]);
    assert.equal((await alice("DELETE", `/v1/workspaces/${home}`)).status, 200);
    assert.equal(await sy.closed, 4004);
  } finally {
    await h.close();
  }
});

test("a station whose home is locked joins locked workspaces only; each one's lock is said and carried for it", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const [a, b, c] = [await create(alice, "A"), await create(alice, "B"), await create(alice, "C")];
    const p = await key(), q = await key();
    assert.equal((await enroll(h, p, await token(alice, a, "p"))).status, 200);
    const genesis = await signer("alice").genesis(b);
    assert.equal((await alice("POST", `/v1/workspaces/${b}/lock`, { entries: [genesis] })).status, 200);
    // A station of an unlocked home joins a locked workspace when it pins that lock there (`locks`); one from before
    // would take its members on the cloud's word.
    assert.deepEqual(Object.values(await enroll(h, p, await token(alice, b, "p"), true)), [409, { error: "locked_workspace" }]);
    assert.equal((await enroll(h, p, await token(alice, b, "p"), true, { locks: true })).status, 200);
    // Its home locked, it joins no unlocked workspace; a locked one it does.
    assert.equal((await enroll(h, q, await token(alice, b, "q"))).status, 200);
    assert.deepEqual(Object.values(await enroll(h, q, await token(alice, c, "q"), true)), [409, { error: "locked_workspace" }]);
    assert.equal((await alice("POST", `/v1/workspaces/${a}/lock`, { entries: [await signer("alice").genesis(a)] })).status, 200);
    assert.equal((await enroll(h, q, await token(alice, a, "q"), true, { locks: true })).status, 200);
    // Each workspace's lock head in the state frame; its entries asked by naming it, said back with its name.
    const sq = await connect(h, q);
    const state = await sq.state();
    assert.equal(state.workspace, b);
    assert.equal(state.lock.seq, 0);
    assert.deepEqual(state.workspaces.map((w: { workspace: string; lock: { seq: number } | null }) => [w.workspace, w.lock?.seq]), [[a, 0]]);
    sq.ws.send(JSON.stringify({ type: "lock.get", after: -1, workspace: a }));
    const got = (await sq.told()).filter((f) => f.type === "lock");
    assert.deepEqual(got.map((f) => [f.workspace, f.entries.map((e: LockEntry) => e.ws)]), [[a, [a]]]);
    // A workspace it is not in is no lock of its to ask; none named, its home's.
    sq.ws.send(JSON.stringify({ type: "lock.get", after: -1, workspace: c }));
    sq.ws.send(JSON.stringify({ type: "lock.get", after: -1 }));
    const home = (await sq.told()).filter((f) => f.type === "lock");
    assert.deepEqual(home.map((f) => [f.workspace, f.entries.map((e: LockEntry) => e.ws)]), [[undefined, [b]]]);
    // Its home locked since, p joins no unlocked workspace either.
    assert.deepEqual(Object.values(await enroll(h, p, await token(alice, c, "p"), true, { locks: true })), [409, { error: "locked_workspace" }]);
    assert.deepEqual([await count(alice, a), await count(alice, b), await count(alice, c)], [2, 2, 0]);
  } finally {
    await h.close();
  }
});

/** Signed as a station signs what it sends (notices, reports): over the body's digest, tagged. */
async function signed(h: Harness, station: Station, path: string, tag: string, value: unknown) {
  const body = JSON.stringify(value);
  const ts = h.now();
  const digest = createHash("sha256").update(body).digest("hex");
  const signature = await station.sign(`${tag}:${h.origin}:${station.id}:${ts}:${digest}`);
  return h.fetch(path, { method: "POST", headers: { "content-type": "application/json", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": signature }, body });
}

test("notices and reports are of the workspace the station names, one it is in; of its home when it names none", async () => {
  const { privateKey } = await generateKeyPair("RS256", { extractable: true });
  const account = { type: "service_account", project_id: "stillfail-test", client_email: "push@stillfail-test.iam.gserviceaccount.com", private_key: await exportPKCS8(privateKey), token_uri: "https://oauth.example/token" };
  const sent: { token: string; data: Record<string, string> }[] = [];
  const h = await harness({
    fcm: JSON.stringify(account),
    push: (request: OutboundRequest) => {
      if (request.url === account.token_uri) return { status: 200, body: JSON.stringify({ access_token: "fcm-access", expires_in: 3600, token_type: "Bearer" }) };
      const message = JSON.parse(new TextDecoder().decode(request.body)).message;
      sent.push({ token: message.token, data: message.data });
      return { status: 200, body: JSON.stringify({ name: "projects/stillfail-test/messages/1" }) };
    },
  });
  try {
    const aliceTokens = await h.login("alice");
    const bobTokens = await h.login("bob");
    const alice = h.as(aliceTokens), bob = h.as(bobTokens);
    const home = await create(alice, "Home");
    const lab = await create(bob, "Lab");
    const other = await create(alice, "Other");
    const x = await key();
    assert.equal((await enroll(h, x, await token(alice, home, "studio"))).status, 200);
    assert.equal((await enroll(h, x, await token(bob, lab, "lab box"), true)).status, 200);
    for (const [tokens, device] of [[aliceTokens, "alice-token"], [bobTokens, "bob-token"]] as const) {
      assert.equal((await h.fetch("/v1/push", { method: "POST", headers: { authorization: `Bearer ${tokens.access_token}`, "content-type": "application/json" }, body: JSON.stringify({ kind: "fcm", token: device }) })).status, 204);
    }
    const notice = { to: ["alice@example.test", "bob@example.test"], kind: "done", session: "s1", title: "t", by: "Claude", text: "done", at: 1790000000000 };
    const notify = (workspace?: unknown) => signed(h, x, "/v1/stations/notify", "stillfail-station-notify-v1", { notices: [notice], ...(workspace === undefined ? {} : { workspace }) });

    // Naming none: its home's, as before; Bob is not in it.
    assert.deepEqual(await (await notify()).json(), { sent: 1 });
    assert.deepEqual(sent.splice(0).map((s) => [s.token, s.data.workspace, s.data.tag]), [["alice-token", home, `${home}/${x.id}/s1`]]);
    // The lab's: its members, linked there.
    assert.deepEqual(await (await notify(lab)).json(), { sent: 1 });
    assert.deepEqual(sent.splice(0).map((s) => [s.token, s.data.workspace, s.data.url]), [["bob-token", lab, `/o/${lab}/${x.id}/s1`]]);
    // One it is not in, or not a workspace at all.
    assert.deepEqual([(await notify(other)).status, (await notify("nope")).status], [403, 400]);
    assert.equal(sent.length, 0);

    // Reports likewise: the console says the workspace, and the station's name there.
    const report = (key: string, workspace?: string) => signed(h, x, "/v1/feedback", "stillfail-station-feedback-v1", { key, title: "t", body: "b", ...(workspace ? { workspace } : {}) });
    assert.equal((await report("k1")).status, 201);
    assert.equal((await report("k2", lab)).status, 201);
    assert.equal((await report("k3", other)).status, 403);
    const listed = ((await (await h.as(aliceTokens, "admin")("GET", "/v1/admin/feedback")).json()) as any).feedback;
    assert.deepEqual(listed.map((f: any) => [f.number, f.workspace?.id, f.station?.name]), [[2, lab, "lab box"], [1, home, "studio"]]);
  } finally {
    await h.close();
  }
});

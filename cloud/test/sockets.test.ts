import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";

// Where devices' events sockets and stations' presence sockets are held (directory.ts `sockets`): on their own objects
// (account.ts, station.ts), told by the Directory after each change; the Directory's from before handed over to them at
// a deploy; and the way back (DIRECTORY_SOCKETS=primary) and forward again. Deterministic: h.settled is the barrier
// for what the Directory tells after a change answers, the retries' alarm goes off when a test says (test/worker.ts).

type Harness = Awaited<ReturnType<typeof harness>>;
const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");

async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}
type Key = Awaited<ReturnType<typeof key>>;

/** A socket and what came on it: `take` what arrived since the last take (after the barrier, h.heard), `closed` its code. */
function received(h: Harness, ws: NonNullable<Awaited<ReturnType<Harness["fetch"]>>["webSocket"]>) {
  const got: any[] = [];
  let pong: (() => void) | null = null;
  const closed = new Promise<number>((resolve) => ws.addEventListener("close", (event) => resolve(event.code), { once: true }));
  ws.addEventListener("message", (event) => (event.data === "pong" ? pong?.() : got.push(JSON.parse(event.data as string))));
  ws.accept();
  /** What arrived before a pong to a ping sent now (without the barrier: only what was sent before the last answer). */
  const now = async (): Promise<any[]> => {
    await new Promise<void>((resolve) => {
      pong = resolve;
      ws.send("ping");
    });
    return got.splice(0);
  };
  return {
    closed,
    now,
    async take(): Promise<any[]> {
      await h.heard(ws);
      // (as whom it tells of what: what it says changed taken off, events.test.ts `bare`)
      return got.splice(0).map((e) => {
        if (typeof e !== "object" || e === null) return e;
        const { entry: _e, rev: _r, set: _s, unset: _u, put: _p, gone: _g, ...rest } = e;
        return rest;
      });
    },
  };
}

async function listen(h: Harness, token: string) {
  const response = await h.fetch("/v1/events", { headers: { upgrade: "websocket", "sec-websocket-protocol": `stillfail-events, stillfail-token.${token}` } });
  assert.equal(response.status, 101);
  return received(h, response.webSocket!);
}

async function connect(h: Harness, station: Key) {
  const ts = h.now();
  const response = await h.fetch("/v1/stations/connect", {
    headers: { upgrade: "websocket", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await station.sign(`stillfail-station-connect-v1:${h.origin}:${station.id}:${ts}`), "x-stillfail-version": "0.2.0" },
  });
  assert.equal(response.status, 101);
  return received(h, response.webSocket!);
}

async function enroll(h: Harness, owner: ReturnType<Harness["as"]>, workspace: string, name: string) {
  const enrollment = (await (await owner("POST", `/v1/workspaces/${workspace}/enrollments`, { name })).json()) as any;
  const station = await key();
  const response = await h.fetch("/v1/stations/enroll", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token: enrollment.token, station: station.id, signature: await station.sign(`stillfail-station-enroll-v1:${h.origin}:${enrollment.token}:${station.id}`) }),
  });
  assert.equal(response.status, 200);
  return station;
}

/** Alice's workspace with bob in it and a station, each signed in. */
async function setUp(h: Harness) {
  const tokens = { alice: await h.login("alice"), bob: await h.login("bob") };
  const alice = h.as(tokens.alice);
  const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
  await alice("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["bob@example.test"] });
  const station = await enroll(h, alice, w, "willow");
  return { tokens, alice, w, station, bob: tokens.bob.subject };
}

const directory = (h: Harness) => h.object("DIRECTORY", "primary");
/** Where the sockets open from now on, as a deploy of DIRECTORY_SOCKETS would say (test/worker.ts). */
async function at(h: Harness, where: "objects" | "primary") {
  const answer = await h.fetch("/__test/sockets", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ where }) });
  assert.equal(answer.status, 200);
}
const load = async (h: Harness) => (await directory(h)).adminLoad();

test("sockets are held on their objects, which a change in the Directory reaches; the Directory holds none", async () => {
  const h = await harness();
  try {
    const { tokens, alice, w, station, bob } = await setUp(h);
    const device = await listen(h, tokens.bob.access_token);
    const presence = await connect(h, station);
    assert.equal((await presence.take())[0].type, "state");
    const held = await load(h);
    assert.deepEqual([held.held, held.live], [{ devices: 0, stations: 0 }, { accounts: 1, stations: 1 }]);

    await alice("PATCH", `/v1/workspaces/${w}`, { name: "House" });
    assert.deepEqual(await device.take(), [{ type: "workspaces" }, { type: "workspace", id: w }]);
    assert.equal((await presence.take()).at(-1).workspace_name, "House");
    // A revocation reaches the station before the change answers: no barrier, a pong right after the answer.
    assert.equal((await alice("PATCH", `/v1/workspaces/${w}/members/${bob}`, { role: "admin" })).status, 200);
    assert.ok((await presence.now()).some((f) => f.type === "revoke" && f.id === bob));
  } finally {
    await h.close();
  }
});

test("a delivery that fails is tried again and gets there; the answer of a revocation does not wait on it for ever", async () => {
  const h = await harness();
  try {
    const { tokens, alice, w, station, bob } = await setUp(h);
    const device = await listen(h, tokens.alice.access_token);
    const presence = await connect(h, station);
    await presence.take();
    const dir = await directory(h);
    const alicesSub = tokens.alice.subject;
    await dir.failTo(`station ${station.id}`, `account ${alicesSub}`);

    // Removing bob: the station's revocation fails once, and the change answers all the same.
    assert.equal((await alice("DELETE", `/v1/workspaces/${w}/members/${bob}`)).status, 200);
    assert.deepEqual(await device.take(), [], "not told yet");
    assert.deepEqual(await presence.take(), []);
    const waiting = (await dir.waiting()) as { kind: string; key: string; tries: number }[];
    assert.deepEqual([...new Set(waiting.map((r) => `${r.kind} ${r.key} ${r.tries}`))].sort(), [`account ${alicesSub} 1`, `station ${station.id} 1`]);

    // Still down when tried again: waits longer, nothing lost.
    await dir.retry();
    assert.ok(((await dir.waiting()) as { tries: number }[]).every((r) => r.tries === 2));
    await dir.failTo();
    await dir.retry();
    assert.deepEqual(await dir.waiting(), []);
    assert.deepEqual(await device.take(), [{ type: "workspaces" }, { type: "workspace", id: w }]);
    const frames = await presence.take();
    assert.ok(frames.some((f) => f.type === "revoke" && f.id === bob), "the revocation");
    // Tried again, it reads its whole state too: everything revoked, as it is now.
    assert.ok(frames.some((f) => f.type === "state" && f.revocations.some((r: any) => r.id === bob)));
  } finally {
    await h.close();
  }
});

test("what failed before goes with what is new, in order: an account let in and then not, with the first not heard, is not let in", async () => {
  const h = await harness();
  try {
    const { tokens, bob } = await setUp(h);
    const admin = h.as(tokens.alice, "admin");
    const dir = await directory(h);
    await dir.failTo(`account ${bob}`);
    await admin("POST", `/v1/admin/users/${bob}/beta`, { on: true });
    await h.settled();
    assert.equal(((await dir.waiting()) as unknown[]).length, 1);
    await dir.failTo();
    await admin("POST", `/v1/admin/users/${bob}/beta`, { on: false });
    await h.settled();
    assert.deepEqual(await dir.waiting(), [], "both went, the earlier first");
    await dir.retry();
    assert.equal((await h.as(tokens.bob, "beta")("GET", "/v1/me")).status, 403);
  } finally {
    await h.close();
  }
});

test("a change told while a socket opens, the Directory's answer still on its way, reaches that socket, which is told from then on", async () => {
  const h = await harness();
  try {
    const { tokens, alice, w, station, bob } = await setUp(h);
    const carol = await h.login("carol");
    await alice("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["carol@example.test"] });

    const account = await h.object("ACCOUNTS", bob);
    await account.holdOpening();
    const opening = listen(h, tokens.bob.access_token);
    await account.openingHeld();
    await alice("PATCH", `/v1/workspaces/${w}`, { name: "House" });
    await h.settled();
    await account.letOpen();
    const device = await opening;
    assert.deepEqual(await device.take(), [{ type: "workspaces" }, { type: "workspace", id: w }]);
    await alice("PATCH", `/v1/workspaces/${w}`, { name: "Hut" });
    assert.deepEqual(await device.take(), [{ type: "workspaces" }, { type: "workspace", id: w }], "still counted as holding a socket");

    // A station's: a member removed as it connects is revoked on the socket that opens, and in its state.
    const object = await h.object("STATIONS", station.id);
    await object.holdOpening();
    const connecting = connect(h, station);
    await object.openingHeld();
    assert.equal((await alice("DELETE", `/v1/workspaces/${w}/members/${carol.subject}`)).status, 200);
    await h.settled();
    await object.letOpen();
    const presence = await connecting;
    const frames = await presence.take();
    assert.ok(frames.some((f) => f.type === "revoke" && f.id === carol.subject), "the revocation");
    assert.ok(frames.at(-1).type === "state" && frames.at(-1).revocations.some((r: any) => r.id === carol.subject), "its state as it is now");
    await alice("PATCH", `/v1/workspaces/${w}`, { name: "Home" });
    assert.equal((await presence.take()).at(-1).workspace_name, "Home", "still counted as holding a socket");
  } finally {
    await h.close();
  }
});

test("what an object keeps is told whether or not it holds a socket: a station let go stops being one, a test channel let in", async () => {
  const h = await harness();
  try {
    const { tokens, alice, w, station, bob } = await setUp(h);
    const object = await h.object("STATIONS", station.id);
    assert.equal(await object.isStation(station.id), true);
    // No socket: told all the same, before the removal answers.
    assert.equal((await alice("DELETE", `/v1/workspaces/${w}/stations/${station.id}`)).status, 200);
    assert.equal(await object.isStation(station.id), false);

    const bobBeta = h.as(tokens.bob, "beta");
    assert.equal((await bobBeta("GET", "/v1/me")).status, 403);
    await h.as(tokens.alice, "admin")("POST", `/v1/admin/users/${bob}/beta`, { on: true });
    await h.settled();
    assert.equal((await bobBeta("GET", "/v1/me")).status, 200);
    await h.as(tokens.alice, "admin")("POST", `/v1/admin/users/${bob}/beta`, { on: false });
    await h.settled();
    assert.equal((await bobBeta("GET", "/v1/me")).status, 403);
  } finally {
    await h.close();
  }
});

test("sockets held on the Directory at a deploy are handed over to their objects, and work after reconnecting; an old Worker's is turned away", async () => {
  const h = await harness();
  try {
    await at(h, "primary");
    const { tokens, alice, w, station } = await setUp(h);
    const device = await listen(h, tokens.bob.access_token);
    const presence = await connect(h, station);
    await presence.take();
    assert.deepEqual((await load(h)).held, { devices: 1, stations: 1 }, "as before their objects");

    // The deploy: the new Worker routes them to their objects, and the Directory, started again, lets its own go.
    await at(h, "objects");
    await (await directory(h)).handOffNow();
    assert.equal(await device.closed, 1012);
    assert.equal(await presence.closed, 1012);
    // A socket an old Worker still opens on the Directory as it is replaced: tried again, it lands on its object.
    assert.equal((await (await directory(h)).fetch("https://directory/events", { headers: { upgrade: "websocket", "x-stillfail-sub": "x" } })).status, 503);

    const again = { device: await listen(h, tokens.bob.access_token), presence: await connect(h, station) };
    assert.equal((await again.presence.take())[0].workspace_name, "Home");
    assert.deepEqual((await load(h)).held, { devices: 0, stations: 0 });
    await alice("PATCH", `/v1/workspaces/${w}`, { name: "House" });
    assert.deepEqual(await again.device.take(), [{ type: "workspaces" }, { type: "workspace", id: w }]);
    assert.equal((await again.presence.take()).at(-1).workspace_name, "House");
  } finally {
    await h.close();
  }
});

test("rolled back (DIRECTORY_SOCKETS=primary) the sockets go back to the Directory and work there; forward again, back to their objects", async () => {
  const h = await harness();
  try {
    const { tokens, alice, w, station } = await setUp(h);
    let device = await listen(h, tokens.bob.access_token);
    let presence = await connect(h, station);
    await presence.take();

    // Back: the objects, started again by the deploy, let their sockets go; they reconnect onto the Directory.
    await at(h, "primary");
    await (await h.object("ACCOUNTS", tokens.bob.subject)).handBackNow();
    await (await h.object("STATIONS", station.id)).handBackNow();
    assert.equal(await device.closed, 1012);
    assert.equal(await presence.closed, 1012);
    device = await listen(h, tokens.bob.access_token);
    presence = await connect(h, station);
    await presence.take();
    assert.deepEqual((await load(h)).held, { devices: 1, stations: 1 });
    await alice("PATCH", `/v1/workspaces/${w}`, { name: "House" });
    assert.deepEqual(await device.take(), [{ type: "workspaces" }, { type: "workspace", id: w }]);
    assert.equal((await presence.take()).at(-1).workspace_name, "House");

    // Forward again.
    await at(h, "objects");
    await (await directory(h)).handOffNow();
    assert.equal(await device.closed, 1012);
    assert.equal(await presence.closed, 1012);
    device = await listen(h, tokens.bob.access_token);
    presence = await connect(h, station);
    await presence.take();
    assert.deepEqual((await load(h)).held, { devices: 0, stations: 0 });
    await alice("PATCH", `/v1/workspaces/${w}`, { name: "Hut" });
    assert.deepEqual(await device.take(), [{ type: "workspaces" }, { type: "workspace", id: w }]);
    assert.equal((await presence.take()).at(-1).workspace_name, "Hut");
  } finally {
    await h.close();
  }
});

test("the Directory counts its calls by what they serve, without writing on a read, and the console reads them", async () => {
  const h = await harness();
  try {
    const { tokens, alice, w } = await setUp(h);
    for (let i = 0; i < 3; i++) await alice("GET", `/v1/workspaces/${w}`);
    const relays = (await (await h.as(tokens.alice, "admin")("GET", "/v1/admin/relays")).json()) as any;
    const { calls, held, bytes, waiting } = relays.directory;
    const sum = (family: string) => (calls.families[family] ?? []).reduce((a: number, b: number) => a + b, 0);
    assert.equal(calls.step, 3600);
    assert.equal(calls.families.workspaces.length, 7 * 24);
    // Three reads, the members added and the enrollment made in setUp, each once (what they answer with is not counted again).
    assert.equal(sum("workspaces"), 6);
    assert.ok(sum("signin") >= 4, "two sign-ins");
    assert.ok(sum("admin") >= 1);
    assert.deepEqual(held, { devices: 0, stations: 0 });
    assert.equal(waiting, 0);
    assert.ok(bytes > 0);
  } finally {
    await h.close();
  }
});

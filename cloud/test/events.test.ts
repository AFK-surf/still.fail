import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";
import type { AccountEvent } from "../src/types.ts";

type Harness = Awaited<ReturnType<typeof harness>>;
const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");
const SILENT_MS = 90_000;

async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}

const upgrade = (protocols: string) => ({ upgrade: "websocket", "sec-websocket-protocol": protocols });

/** A device's events socket; `take` returns what arrived since the last take. */
async function listen(h: Harness, token: string) {
  const response = await h.fetch("/v1/events", { headers: upgrade(`stillfail-events, stillfail-token.${token}`) });
  assert.equal(response.status, 101);
  assert.equal(response.headers.get("sec-websocket-protocol"), "stillfail-events");
  const ws = response.webSocket!;
  ws.accept();
  const got: AccountEvent[] = [];
  let pong: (() => void) | null = null;
  ws.addEventListener("message", (event) => (event.data === "pong" ? pong?.() : got.push(JSON.parse(event.data as string))));
  return {
    ws,
    // A pong comes after everything sent before it, so this sees every event of the call before.
    async take(): Promise<string[]> {
      await new Promise<void>((resolve) => {
        pong = resolve;
        ws.send("ping");
      });
      return got.splice(0).map((e) => JSON.stringify(e)).sort();
    },
  };
}

type Listener = Awaited<ReturnType<typeof listen>>;

/** The Directory object (test/worker.ts): its presence sweep, and when a station's socket closing has been handled. */
async function directory(h: Harness): Promise<{ sweepAt(ms: number): Promise<boolean>; left(station: string): Promise<void> }> {
  const directories: any = await h.mf.getDurableObjectNamespace("DIRECTORY", "api");
  return directories.get(directories.idFromName("primary"));
}

/** Each listener got exactly these events (in any order); the rest got none. */
async function expect(listeners: Record<string, Listener>, expected: Record<string, AccountEvent[]>, what: string) {
  for (const [name, listener] of Object.entries(listeners)) {
    assert.deepEqual(await listener.take(), (expected[name] ?? []).map((e) => JSON.stringify(e)).sort(), `${what}: ${name}`);
  }
}

async function connectStation(h: Harness, station: Awaited<ReturnType<typeof key>>, options: { ts?: number; signer?: Awaited<ReturnType<typeof key>> } = {}) {
  const ts = options.ts ?? h.now();
  const signature = await (options.signer ?? station).sign(`stillfail-station-connect-v1:${h.origin}:${station.id}:${ts}`);
  const response = await h.fetch("/v1/stations/connect", {
    headers: { upgrade: "websocket", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": signature, "x-stillfail-version": "0.2.0" },
  });
  if (response.status !== 101) return { status: response.status };
  const ws = response.webSocket!;
  const frames: any[] = [];
  const closed = new Promise<number>((resolve) => ws.addEventListener("close", (event) => resolve(event.code), { once: true }));
  let pong: (() => void) | null = null;
  ws.addEventListener("message", (event) => (event.data === "pong" ? pong?.() : frames.push(JSON.parse(event.data as string))));
  ws.accept();
  const ping = () => new Promise<void>((resolve) => { pong = resolve; ws.send("ping"); });
  return { status: 101, ws, frames, closed, ping };
}

async function enrollStation(h: Harness, owner: ReturnType<Harness["as"]>, workspace: string, name: string) {
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

test("every change reaches exactly the accounts it affects", { timeout: 30000 }, async () => {
  const h = await harness();
  try {
    const tokens = { alice: await h.login("alice"), bob: await h.login("bob"), carol: await h.login("carol"), dave: await h.login("dave") };
    const alice = h.as(tokens.alice), bob = h.as(tokens.bob), carol = h.as(tokens.carol);
    const on: Record<string, Listener> = {};
    for (const [name, t] of Object.entries(tokens)) on[name] = await listen(h, t.access_token);
    const list: AccountEvent = { type: "workspaces" };

    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const ws: AccountEvent = { type: "workspace", id: w };
    await expect(on, { alice: [list] }, "create");

    await alice("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "bob@example.test" });
    await expect(on, { alice: [ws], bob: [list] }, "invite");
    const invitation = ((await (await bob("GET", "/v1/me")).json()) as any).invitations[0].id;
    assert.equal((await bob("POST", `/v1/invitations/${invitation}/accept`)).status, 200);
    await expect(on, { alice: [list, ws], bob: [list, ws] }, "accept");

    await alice("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "carol@example.test" });
    await expect(on, { alice: [ws], bob: [ws], carol: [list] }, "invite carol");
    const carolInvitation = ((await (await carol("GET", "/v1/me")).json()) as any).invitations[0].id;
    await carol("POST", `/v1/invitations/${carolInvitation}/decline`);
    await expect(on, { alice: [ws], bob: [ws], carol: [list] }, "decline");
    const again = (await (await alice("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "carol@example.test" })).json()) as any;
    await expect(on, { alice: [ws], bob: [ws], carol: [list] }, "invite again");
    await alice("DELETE", `/v1/workspaces/${w}/invitations/${again.id}`);
    await expect(on, { alice: [ws], bob: [ws], carol: [list] }, "revoke");

    await alice("PATCH", `/v1/workspaces/${w}`, { name: "House" });
    await expect(on, { alice: [list, ws], bob: [list, ws] }, "rename workspace");

    const view = (await (await alice("GET", `/v1/workspaces/${w}`)).json()) as any;
    const bobSub = view.members.find((m: any) => m.email === "bob@example.test").sub;
    await alice("PATCH", `/v1/workspaces/${w}/members/${bobSub}`, { role: "admin" });
    await expect(on, { alice: [ws], bob: [list, ws] }, "role");

    const station = await enrollStation(h, alice, w, "studio");
    await expect(on, { alice: [list, ws], bob: [list, ws] }, "enroll");

    // A station's socket is what still.fail cloud tells it: whether it is up, devices find out over the mesh, so connecting
    // tells no one.
    const first = await connectStation(h, station);
    assert.equal(first.status, 101);
    await expect(on, {}, "a station connecting tells no one");
    await first.ping!();
    assert.deepEqual(first.frames![0], { type: "state", peers: [{ id: station.id, name: "studio", version: "0.2.0" }], workspace: w, workspace_name: "House", name: "studio", origin: first.frames![0].origin, relay_url: first.frames![0].relay_url, relay_urls: first.frames![0].relay_urls, relay_names: first.frames![0].relay_names, grant_keys: first.frames![0].grant_keys, revocations: first.frames![0].revocations });
    // bob's role changed above: the credentials he held then are refused, as the station hears at once on connecting.
    assert.deepEqual(first.frames![0].revocations.map((r: any) => [r.kind, r.id]), [["sub", bobSub]]);
    let seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.deepEqual([seen.version, "online" in seen], ["0.2.0", false]);

    await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { name: "big studio" });
    await expect(on, { alice: [ws], bob: [ws] }, "rename station");
    await first.ping!();
    assert.equal(first.frames!.at(-1).name, "big studio", "the station learns its new name");

    first.ws!.close(1000);
    await (await directory(h)).left(station.id);
    await expect(on, {}, "nor does leaving");
    seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.equal(seen.last_seen, h.now(), "last here at");

    // A leaver and a removed member hear of it too.
    assert.equal((await bob("DELETE", `/v1/workspaces/${w}/members/${bobSub}`)).status, 200);
    await expect(on, { alice: [list, ws], bob: [list, ws] }, "leave");
    await alice("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "carol@example.test" });
    await expect(on, { alice: [ws], carol: [list] }, "invite carol for real");
    const joined = ((await (await carol("GET", "/v1/me")).json()) as any).invitations[0].id;
    await carol("POST", `/v1/invitations/${joined}/accept`);
    await expect(on, { alice: [list, ws], carol: [list, ws] }, "carol joins");
    const carolSub = ((await (await alice("GET", `/v1/workspaces/${w}`)).json()) as any).members.find((m: any) => m.email === "carol@example.test").sub;
    await alice("DELETE", `/v1/workspaces/${w}/members/${carolSub}`);
    await expect(on, { alice: [list, ws], carol: [list, ws] }, "remove carol");
    const second = await connectStation(h, station);
    await expect(on, {}, "connecting again");

    // Removing a station closes its socket and it cannot come back.
    await alice("DELETE", `/v1/workspaces/${w}/stations/${station.id}`);
    assert.equal(await second.closed, 4004);
    await expect(on, { alice: [list, ws] }, "remove station");
    assert.equal((await connectStation(h, station)).status, 404);

    const other = await enrollStation(h, alice, w, "mini");
    const third = await connectStation(h, other);
    await expect(on, { alice: [list, ws] }, "second station");
    await alice("DELETE", `/v1/workspaces/${w}`);
    assert.equal(await third.closed, 4004);
    await expect(on, { alice: [list, ws] }, "delete workspace");
  } finally {
    await h.close();
  }
});

test("a reconnect replaces the old station socket; a silent one is dropped", { timeout: 20000 }, async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice");
    const alice = h.as(tokens);
    const events = await listen(h, tokens.access_token);
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const station = await enrollStation(h, alice, w, "studio");
    await events.take();

    const first = await connectStation(h, station);
    const second = await connectStation(h, station);
    assert.equal(await first.closed, 4000);
    const objects = await directory(h);
    await objects.left(station.id);
    assert.deepEqual(await events.take(), [], "a station's socket tells no one");

    // The runtime answers a ping itself and notes when, on the machine's clock (as the sockets' times are): after
    // `pinged`, and before the ping's answer is back.
    const pinged = Date.now();
    await second.ping!();
    assert.equal(await objects.sweepAt(pinged + SILENT_MS), true, "answered pings keep it");
    assert.equal(await objects.sweepAt(Date.now() + SILENT_MS + 1), false);
    assert.equal(await second.closed, 4008);
    assert.deepEqual(await events.take(), []);
    assert.equal(((await (await alice("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0].last_seen, h.now());
  } finally {
    await h.close();
  }
});

test("sockets refuse bad credentials", { timeout: 20000 }, async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice");
    const events = (headers: Record<string, string>) => h.fetch("/v1/events", { headers });
    assert.equal((await events({})).status, 426);
    assert.equal((await events(upgrade("stillfail-events"))).status, 401);
    assert.equal((await events(upgrade("stillfail-events, stillfail-token.invalid"))).status, 401);
    assert.equal((await events(upgrade(`stillfail-events, stillfail-token.${tokens.refresh_token}`))).status, 401, "refresh is not access");
    assert.equal((await events(upgrade(`stillfail-token.${tokens.access_token}`))).status, 401, "must ask for stillfail-events");
    assert.equal((await events({ upgrade: "websocket", authorization: `Bearer ${tokens.access_token}` })).status, 401, "the token travels as a subprotocol");
    await h.fetch("/v1/auth/logout", { method: "POST", headers: { authorization: `Bearer ${tokens.refresh_token}`, "content-type": "application/json" }, body: '{"all":true}' });
    assert.equal((await events(upgrade(`stillfail-events, stillfail-token.${tokens.access_token}`))).status, 401, "a revoked session");

    const alice = h.as(await h.login("alice"));
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const station = await enrollStation(h, alice, w, "studio");
    const forged = await key();
    assert.equal((await connectStation(h, station, { signer: forged })).status, 401);
    assert.equal((await connectStation(h, station, { ts: h.now() - 600 })).status, 400);
    assert.equal((await connectStation(h, forged)).status, 404, "not enrolled");
    assert.equal((await h.fetch("/v1/stations/connect")).status, 426);
    assert.equal((await h.fetch("/v1/stations/heartbeat", { method: "POST" })).status, 404, "gone");
  } finally {
    await h.close();
  }
});


test("station rosters stay workspace scoped and update when peers join or leave", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const a = (await (await alice("POST", "/v1/workspaces", { name: "A" })).json()) as any;
    const b = (await (await alice("POST", "/v1/workspaces", { name: "B" })).json()) as any;
    const first = await enrollStation(h, alice, a.id, "first");
    const socket = await connectStation(h, first);
    await socket.ping!();
    const roster = () => socket.frames!.filter(f => f.type === "state").at(-1).peers.map((p: any) => p.id).sort();
    assert.deepEqual(roster(), [first.id]);
    const second = await enrollStation(h, alice, a.id, "second");
    await socket.ping!();
    assert.deepEqual(roster(), [first.id, second.id].sort());
    await enrollStation(h, alice, b.id, "elsewhere");
    await socket.ping!();
    assert.deepEqual(roster(), [first.id, second.id].sort());
    await alice("DELETE", `/v1/workspaces/${a.id}/stations/${second.id}`);
    await socket.ping!();
    assert.deepEqual(roster(), [first.id]);
    socket.ws!.close(1000);
  } finally { await h.close(); }
});

test("a workspace's own relays: set by its managers, told to its stations and members after still.fail's, kept from others", { timeout: 20000 }, async () => {
  const h = await harness();
  try {
    const tokens = { alice: await h.login("alice"), bob: await h.login("bob") };
    const alice = h.as(tokens.alice), bob = h.as(tokens.bob);
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const other = ((await (await alice("POST", "/v1/workspaces", { name: "Lab" })).json()) as any).id as string;
    await alice("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["bob@example.test"] });
    const station = await enrollStation(h, alice, w, "studio");
    const socket = await connectStation(h, station);
    await socket.ping!();
    const ours = socket.frames![0].relay_urls as string[];
    assert.ok(ours.length > 0);
    const on = { alice: await listen(h, tokens.alice.access_token), bob: await listen(h, tokens.bob.access_token) };

    // Members may not; a manager may, the list cleaned (the same twice, still.fail's own, a trailing slash).
    assert.equal((await bob("PUT", `/v1/workspaces/${w}/relays`, { relays: ["https://relay.home.test"] })).status, 403);
    const set = await alice("PUT", `/v1/workspaces/${w}/relays`, { relays: ["https://relay.home.test/", " https://relay.home.test", ours[0], "https://cn.home.test/relay"] });
    assert.equal(set.status, 200);
    assert.deepEqual(((await set.json()) as any).relays, ["https://relay.home.test", "https://cn.home.test/relay"]);
    await expect(on, { alice: [{ type: "workspaces" }, { type: "workspace", id: w }], bob: [{ type: "workspaces" }, { type: "workspace", id: w }] }, "set relays");
    await socket.ping!();
    assert.deepEqual(socket.frames!.at(-1).relay_urls, [...ours, "https://relay.home.test", "https://cn.home.test/relay"], "the station hears them after still.fail's");
    assert.equal(socket.frames!.at(-1).relay_url, ours[0]);
    const me = (await (await bob("GET", "/v1/me")).json()) as any;
    assert.deepEqual(me.relay_urls, ours, "still.fail's alone for the account");
    assert.deepEqual(me.workspaces.find((x: any) => x.id === w).relays, ["https://relay.home.test", "https://cn.home.test/relay"]);
    assert.deepEqual(((await (await alice("GET", "/v1/me")).json()) as any).workspaces.find((x: any) => x.id === other).relays, [], "another workspace has none");
    assert.deepEqual(((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).relays, ["https://relay.home.test", "https://cn.home.test/relay"]);

    // What is no relay URL is refused, as is too many.
    for (const relays of [["ftp://x.test"], ["not a url"], ["https://u:p@x.test"], ["https://x.test/?a=1"], "https://x.test", [1], ["https://1.test", "https://2.test", "https://3.test", "https://4.test", "https://5.test"]]) {
      assert.equal((await alice("PUT", `/v1/workspaces/${w}/relays`, { relays })).status, 400, JSON.stringify(relays));
    }
    // None again: the station back on still.fail's alone.
    assert.deepEqual(((await (await alice("PUT", `/v1/workspaces/${w}/relays`, { relays: [] })).json()) as any).relays, []);
    await socket.ping!();
    assert.deepEqual(socket.frames!.at(-1).relay_urls, ours);
  } finally {
    await h.close();
  }
});

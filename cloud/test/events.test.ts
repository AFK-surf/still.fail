import assert from "node:assert/strict";
import test from "node:test";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { harness } from "./harness.ts";
import type { AccountEvent } from "../src/types.ts";
import { entryHash } from "../src/lock.ts";
import { signer } from "./lock-signer.ts";

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
  ws.addEventListener("message", (event) => void (event.data === "pong" || got.push(JSON.parse(event.data as string))));
  return {
    ws,
    // Every event of the calls before (h.heard).
    async take(): Promise<string[]> {
      await h.heard(ws);
      return got.splice(0).map((e) => JSON.stringify(bare(e))).sort();
    },
  };
}

type Listener = Awaited<ReturnType<typeof listen>>;

/** An event as whom it tells of what: what it says changed (a list's entry, a view's change and versions) taken off,
 * which "what a change tells is what reading again gives" holds. */
function bare(e: AccountEvent): AccountEvent {
  const { entry: _e, rev: _r, set: _s, unset: _u, put: _p, gone: _g, ...rest } = e as AccountEvent & Record<string, unknown>;
  return rest as AccountEvent;
}

/** A station's object (test/worker.ts): its presence sweep, and when its socket closing has been handled. */
async function stationObject(h: Harness, station: string): Promise<{ sweepAt(ms: number): Promise<boolean>; left(): Promise<void> }> {
  return h.object("STATIONS", station);
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
  ws.addEventListener("message", (event) => void (event.data === "pong" || frames.push(JSON.parse(event.data as string))));
  ws.accept();
  const ping = () => h.heard(ws);
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

test("every change reaches exactly the accounts it affects", async () => {
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
    // Its mark, as a station's: an icon of still.fail's or a picture, an emoji; in the lists as in the workspace, "" takes it away.
    await alice("PATCH", `/v1/workspaces/${w}`, { icon: "glyph:rocket:blue", emoji: "🚀" });
    await expect(on, { alice: [list, ws], bob: [list, ws] }, "workspace icon");
    let marked = ((await (await bob("GET", "/v1/me")).json()) as any).workspaces.find((x: any) => x.id === w);
    assert.deepEqual([marked.name, marked.icon, marked.emoji], ["House", "glyph:rocket:blue", "🚀"]);
    assert.equal((await alice("PATCH", `/v1/workspaces/${w}`, { icon: "rocket" })).status, 400);
    assert.equal((await alice("PATCH", `/v1/workspaces/${w}`, {})).status, 400);
    await alice("PATCH", `/v1/workspaces/${w}`, { icon: "", emoji: "" });
    await expect(on, { alice: [list, ws], bob: [list, ws] }, "workspace icon cleared");
    marked = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any);
    assert.deepEqual([marked.name, "icon" in marked, "emoji" in marked], ["House", false, false]);

    const view = (await (await alice("GET", `/v1/workspaces/${w}`)).json()) as any;
    const bobSub = view.members.find((m: any) => m.email === "bob@example.test").sub;
    await alice("PATCH", `/v1/workspaces/${w}/members/${bobSub}`, { role: "admin" });
    await expect(on, { alice: [ws], bob: [list, ws] }, "role");

    // Let into the test channel or out of it: its `/v1/me` changed (user.beta), so its devices read it again.
    const aliceAdmin = h.as(tokens.alice, "admin");
    await aliceAdmin("POST", `/v1/admin/users/${bobSub}/beta`, { on: true });
    await expect(on, { bob: [list] }, "beta on");
    await aliceAdmin("POST", `/v1/admin/users/${bobSub}/beta`, { on: false });
    await expect(on, { bob: [list] }, "beta off");

    const station = await enrollStation(h, alice, w, "willow");
    await expect(on, { alice: [list, ws], bob: [list, ws] }, "enroll");

    // A station's socket is what still.fail cloud tells it: whether it is up, devices find out over the mesh, so connecting
    // tells no one.
    const first = await connectStation(h, station);
    assert.equal(first.status, 101);
    await expect(on, {}, "a station connecting tells no one");
    await first.ping!();
    assert.deepEqual(first.frames![0], { type: "state", peers: [{ id: station.id, name: "willow", version: "0.2.0" }], workspace: w, workspace_name: "House", name: "willow", origin: first.frames![0].origin, relay_url: first.frames![0].relay_url, relay_urls: first.frames![0].relay_urls, relay_names: first.frames![0].relay_names, grant_keys: first.frames![0].grant_keys, revocations: first.frames![0].revocations, lock: null, ways: { relays: [], off: [] }, workspaces: [] });
    // bob's role changed above: the credentials he held then are refused, as the station hears at once on connecting.
    assert.deepEqual(first.frames![0].revocations.map((r: any) => [r.kind, r.id]), [["sub", bobSub]]);
    let seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.deepEqual([seen.version, "online" in seen], ["0.2.0", false]);

    await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { name: "big willow" });
    await expect(on, { alice: [ws], bob: [ws] }, "rename station");
    await first.ping!();
    assert.equal(first.frames!.at(-1).name, "big willow", "the station learns its new name");
    // Its emoji: one, kept with it for everyone; "" takes it away; anything not an emoji is refused.
    await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { emoji: "🍎🍊" });
    await expect(on, { alice: [ws], bob: [ws] }, "station emoji");
    seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.deepEqual([seen.name, seen.emoji], ["big willow", "🍎"]);
    assert.equal((await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { emoji: "ab" })).status, 400);
    await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { emoji: "" });
    await expect(on, { alice: [ws], bob: [ws] }, "station emoji cleared");
    seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.equal(seen.emoji, null);
    // Its icon, beside the emoji: one of still.fail's by name, or a small picture; anything else is refused, "" takes it away.
    await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { icon: "glyph:rocket", emoji: "🚀" });
    await expect(on, { alice: [ws], bob: [ws] }, "station icon");
    seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.deepEqual([seen.icon, seen.emoji], ["glyph:rocket", "🚀"]);
    await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { icon: "glyph:dice-3:blue", emoji: "🎲" });
    await expect(on, { alice: [ws], bob: [ws] }, "station icon in a colour");
    seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.equal(seen.icon, "glyph:dice-3:blue");
    // A picture put up is kept in the bucket, the workspace keeping its address; anyone with it gets it, as it was sent.
    const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { list(o: { prefix: string }): Promise<{ objects: unknown[] }> };
    const gif = Uint8Array.from([..."GIF89a"].map((c) => c.charCodeAt(0)).concat(Array.from({ length: 600_000 }, (_, i) => i & 255)));
    const picture = `data:image/gif;base64,${Buffer.from(gif).toString("base64")}`;
    assert.equal((await h.as(tokens.dave)("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { icon: picture })).status, 404, "one who is not in it");
    assert.equal((await bucket.list({ prefix: "icons/" })).objects.length, 0, "keeps nothing for one who may not");
    assert.equal((await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { icon: picture })).status, 200);
    await expect(on, { alice: [ws], bob: [ws] }, "station picture");
    seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.match(seen.icon, new RegExp(`^${h.origin}/v1/icons/[0-9a-f]{32}\\.gif$`));
    const served = await h.fetch(seen.icon.slice(h.origin.length));
    assert.equal(served.status, 200);
    assert.equal(served.headers.get("content-type"), "image/gif");
    assert.match(served.headers.get("cache-control") ?? "", /immutable/);
    assert.deepEqual(new Uint8Array(await served.arrayBuffer()), gif);
    // Its address may be given again (as a client that sends the icon it has does); one of another is not taken.
    assert.equal((await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { icon: seen.icon })).status, 200);
    await expect(on, { alice: [ws], bob: [ws] }, "station picture again");
    assert.equal((await h.fetch("/v1/icons/0123456789abcdef0123456789abcdef.gif")).status, 404);
    // And the workspace's own.
    await alice("PATCH", `/v1/workspaces/${w}`, { icon: "data:image/png;base64,iVBORw0KGgo=" });
    await expect(on, { alice: [ws, list], bob: [ws, list] }, "workspace picture");
    assert.match(((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).icon, /\/v1\/icons\/[0-9a-f]{32}\.png$/);
    for (const bad of [`data:image/gif;base64,R0lGODlh${"A".repeat(1_500_000)}`, "data:image/png;base64,R0lGODlh", "https://example.com/v1/icons/0123456789abcdef0123456789abcdef.gif", "rocket", "glyph:Rocket!", "glyph:rocket:", "glyph:rocket:blue:red", "data:image/svg+xml;base64,PHN2Zz4="]) {
      assert.equal((await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { icon: bad })).status, 400, bad.slice(0, 30));
    }
    await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { icon: "", emoji: "" });
    await expect(on, { alice: [ws], bob: [ws] }, "station icon cleared");
    seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.deepEqual([seen.icon, seen.emoji], [null, null]);

    first.ws!.close(1000);
    await (await stationObject(h, station.id)).left();
    await expect(on, {}, "nor does leaving");
    seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.equal(seen.last_seen, h.now(), "last here at");

    // A picture of its own put up or taken away (own-picture.test.ts): its `/v1/me` changed, and the members lists it
    // is in.
    await bob("PUT", "/v1/me/picture", { picture: `data:image/jpeg;base64,${Buffer.from([0xff, 0xd8, 0xff, 0xe0]).toString("base64")}` });
    await expect(on, { alice: [ws], bob: [list, ws] }, "own picture");
    await bob("DELETE", "/v1/me/picture");
    await expect(on, { alice: [ws], bob: [list, ws] }, "own picture taken away");

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

test("a reconnect replaces the old station socket; a silent one is dropped", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice");
    const alice = h.as(tokens);
    const events = await listen(h, tokens.access_token);
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const station = await enrollStation(h, alice, w, "willow");
    await events.take();

    const first = await connectStation(h, station);
    const second = await connectStation(h, station);
    assert.equal(await first.closed, 4000);
    const objects = await stationObject(h, station.id);
    await objects.left();
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

test("sockets refuse bad credentials", async () => {
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
    const station = await enrollStation(h, alice, w, "willow");
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

test("a workspace's own relays: set by its managers, told to its stations and members after still.fail's, kept from others", async () => {
  const h = await harness();
  try {
    const tokens = { alice: await h.login("alice"), bob: await h.login("bob") };
    const alice = h.as(tokens.alice), bob = h.as(tokens.bob);
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const other = ((await (await alice("POST", "/v1/workspaces", { name: "Lab" })).json()) as any).id as string;
    await alice("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["bob@example.test"] });
    const station = await enrollStation(h, alice, w, "willow");
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
    assert.deepEqual(socket.frames!.at(-1).ways, { relays: ["https://relay.home.test", "https://cn.home.test/relay"], off: [] }, "and as the workspace's own, for it to take as its first (station/src/mesh/ways.ts)");
    const me = (await (await bob("GET", "/v1/me")).json()) as any;
    assert.deepEqual(me.relay_urls, ours, "still.fail's alone for the account");
    assert.deepEqual(me.workspaces.find((x: any) => x.id === w).relays, ["https://relay.home.test", "https://cn.home.test/relay"]);
    assert.deepEqual(((await (await alice("GET", "/v1/me")).json()) as any).workspaces.find((x: any) => x.id === other).relays, [], "another workspace has none");
    assert.deepEqual(((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).relays, ["https://relay.home.test", "https://cn.home.test/relay"]);

    // What is no relay URL is refused, as is too many.
    for (const relays of [["ftp://x.test"], ["not a url"], ["https://u:p@x.test"], ["https://x.test/?a=1"], "https://x.test", [1], ["https://1.test", "https://2.test", "https://3.test", "https://4.test", "https://5.test"]]) {
      assert.equal((await alice("PUT", `/v1/workspaces/${w}/relays`, { relays })).status, 400, JSON.stringify(relays));
    }
    // Ways turned off: by a manager, every relay and kind of way listed on or off, told to members as ways_off.
    const ways = async (as: typeof alice, way: string, on: boolean) => as("PUT", `/v1/workspaces/${w}/ways`, { way, on });
    assert.equal((await ways(bob, ours[0]!, false)).status, 403);
    for (const [way, on] of [["https://nowhere.test", false], ["lan", "no"]] as const) assert.equal((await alice("PUT", `/v1/workspaces/${w}/ways`, { way, on })).status, 400, way);
    for (const r of ours) assert.equal((await ways(alice, r, false)).status, 200, r);
    const off = (await (await ways(alice, "tailnet", false)).json()) as any;
    assert.deepEqual(off.ways_off, [...ours, "tailnet"]);
    assert.deepEqual(off.ways.map((x: any) => [x.id, x.kind, x.on, x.own ?? false]), [
      ...ours.map((r) => [r, "relay", false, false]),
      ["https://relay.home.test", "relay", true, true],
      ["https://cn.home.test/relay", "relay", true, true],
      ["lan", "lan", true, false],
      ["tailnet", "tailnet", false, false],
      ["direct", "direct", true, false],
    ]);
    assert.deepEqual(((await (await bob("GET", "/v1/me")).json()) as any).workspaces.find((x: any) => x.id === w).ways_off, [...ours, "tailnet"]);
    assert.equal(((await (await alice("GET", "/v1/me")).json()) as any).workspaces.find((x: any) => x.id === other).ways_off, undefined, "another workspace has none off");
    // A relay is left on: the last one is refused.
    assert.equal((await ways(alice, "https://relay.home.test", false)).status, 200);
    assert.equal((await ways(alice, "https://cn.home.test/relay", false)).status, 409);
    // A relay of its own taken away goes from those off; turned on again, a way is no longer off.
    assert.deepEqual(((await (await alice("PUT", `/v1/workspaces/${w}/relays`, { relays: ["https://cn.home.test/relay"] })).json()) as any).ways_off, [...ours, "tailnet"]);
    for (const r of ours) await ways(alice, r, true);
    assert.deepEqual(((await (await ways(alice, "tailnet", true)).json()) as any).ways_off, undefined);

    // None again: the station back on still.fail's alone.
    assert.deepEqual(((await (await alice("PUT", `/v1/workspaces/${w}/relays`, { relays: [] })).json()) as any).relays, []);
    await socket.ping!();
    assert.deepEqual(socket.frames!.at(-1).relay_urls, ours);
  } finally {
    await h.close();
  }
});

test("a release out, as the repository's releasing workflows say, is told to every device; nobody else can say it", async () => {
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const jwk = { ...(await exportJWK(publicKey)), kid: "actions", alg: "RS256", use: "sig" };
  const h = await harness({ statusRepoId: "42", push: () => ({ status: 200, body: JSON.stringify({ keys: [jwk] }) }) });
  try {
    const token = (claims: Record<string, unknown>, audience = h.origin) => new SignJWT({ repository: "o/r", repository_id: "42", workflow_ref: "o/r/.github/workflows/pipeline.yml@refs/heads/main", ...claims })
      .setProtectedHeader({ alg: "RS256", kid: "actions" }).setIssuer("https://token.actions.githubusercontent.com").setAudience(audience).setIssuedAt().setExpirationTime("10 years").sign(privateKey);
    const send = async (bearer: string | null) => (await h.fetch("/v1/releases/out", { method: "POST", headers: bearer ? { authorization: `Bearer ${bearer}` } : {} })).status;
    const on = { alice: await listen(h, (await h.login("alice")).access_token), bob: await listen(h, (await h.login("bob")).access_token) };
    await expect(on, {}, "signed in");
    assert.equal(await send(null), 401);
    assert.equal(await send(await token({ repository: "fork/r", repository_id: "43", workflow_ref: "fork/r/.github/workflows/pipeline.yml@refs/heads/main" })), 401);
    assert.equal(await send(await token({ workflow_ref: "o/r/.github/workflows/status-incidents.yml@refs/heads/main" })), 401);
    assert.equal(await send(await token({ workflow_ref: "o/r/.github/workflows/pipeline.yml@refs/heads/mine" })), 401);
    assert.equal(await send(await token({}, "https://elsewhere.example")), 401);
    await expect(on, {}, "refused");
    assert.equal(await send(await token({})), 200);
    assert.equal(await send(await token({ workflow_ref: "o/r/.github/workflows/stable.yml@refs/heads/main" })), 200);
    // The repository renamed: known by its id, its workflows under the new name.
    assert.equal(await send(await token({ workflow_ref: "elsewhere/r/.github/workflows/pipeline.yml@refs/heads/main" })), 401);
    assert.equal(await send(await token({ repository: "o/renamed", workflow_ref: "o/renamed/.github/workflows/pipeline.yml@refs/heads/main" })), 200);
    await expect(on, { alice: [{ type: "release" }, { type: "release" }, { type: "release" }], bob: [{ type: "release" }, { type: "release" }, { type: "release" }] }, "told");
  } finally {
    await h.close();
  }
});

test("a workspace whose lock alone moved on says so in its event, its head with it: nothing for a device to ask again", async () => {
  const h = await harness();
  try {
    const token = await h.login("alice");
    const alice = h.as(token);
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const on = { alice: await listen(h, token.access_token) };
    const g = await signer("alice").genesis(w);
    assert.equal((await alice("POST", `/v1/workspaces/${w}/lock`, { entries: [g] })).status, 200);
    const hash = await entryHash(g);
    await expect(on, { alice: [{ type: "workspace", id: w, lock: { head: { seq: 0, hash, genesis: hash }, locked: true } }] }, "lock turned on");
    // What else changes is told as before, to be read again.
    await alice("PATCH", `/v1/workspaces/${w}`, { name: "House" });
    await expect(on, { alice: [{ type: "workspaces" }, { type: "workspace", id: w }] }, "rename");
  } finally {
    await h.close();
  }
});

test("a request to be let in asked or dropped says so in its event: nothing a device of today asks for again", async () => {
  const h = await harness();
  try {
    const token = await h.login("alice");
    const alice = h.as(token);
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const on = { alice: await listen(h, token.access_token) };
    const base = "ab".repeat(32);
    assert.equal((await alice("POST", `/v1/workspaces/${w}/lock/requests`, { base, kind: "web", label: "Chrome" })).status, 200);
    await expect(on, { alice: [{ type: "workspace", id: w, requests: true }] }, "asked");
    assert.equal((await alice("DELETE", `/v1/workspaces/${w}/lock/requests/${base}`)).status, 200);
    await expect(on, { alice: [{ type: "workspace", id: w, requests: true }] }, "dropped");
  } finally {
    await h.close();
  }
});

/** A view held made what its event told (as the core does, client/core-ts src/sync/cloud.ts `patched`). */
function patched(held: any, e: any): any {
  const next = { ...held, ...(e.set ?? {}), rev: e.rev[1] };
  for (const k of e.unset ?? []) delete next[k];
  for (const [list, key] of Object.entries({ members: "sub", stations: "id", rigs: "id", invitations: "id", added: "email" })) {
    const put: any[] = e.put?.[list] ?? [];
    const gone = new Set(e.gone?.[list] ?? []);
    if (put.length === 0 && gone.size === 0) continue;
    const fresh = new Map(put.map((x) => [x[key], x]));
    const items = (held[list] ?? []).flatMap((x: any) => {
      if (gone.has(x[key])) return [];
      const p = fresh.get(x[key]);
      if (!p) return [x];
      fresh.delete(x[key]);
      return [{ ...x, ...p }];
    });
    items.push(...fresh.values());
    if (list === "rigs" && items.length === 0) delete next.rigs;
    else next[list] = items;
  }
  return next;
}

// The locks' end to end, 2026-11-15: every device of every member read `/v1/me` and the view whole at each change of a
// workspace's people or stations, 110 of an account's 187 requests in a minute. Each member is told what changed instead.
test("what a change tells is what reading again gives: the view by its versions, a member's entry of their list", async () => {
  const h = await harness();
  try {
    const tokens = { alice: await h.login("alice"), bob: await h.login("bob"), carol: await h.login("carol") };
    const alice = h.as(tokens.alice), bob = h.as(tokens.bob), carol = h.as(tokens.carol);
    const on = { alice: await listen(h, tokens.alice.access_token), bob: await listen(h, tokens.bob.access_token), carol: await listen(h, tokens.carol.access_token) };
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const got: Record<string, any[]> = { alice: [], bob: [], carol: [] };
    for (const [name, l] of Object.entries(on)) l.ws.addEventListener("message", (event) => void (event.data === "pong" || got[name]!.push(JSON.parse(event.data as string))));
    const read = async (who: ReturnType<Harness["as"]>) => (await (await who("GET", `/v1/workspaces/${w}`)).json()) as any;
    const listed = async (who: ReturnType<Harness["as"]>) => ((await (await who("GET", "/v1/me")).json()) as any).workspaces.find((x: any) => x.id === w);
    const held: Record<string, any> = { alice: await read(alice) };
    let patchedOnce = 0;
    // One change made, then each member's events taken as a device would: a list's entry put in place of the one held,
    // a view patched where the version before is held, read again otherwise (a member new to it, one whose role changed).
    const after = async (what: string, change: () => Promise<unknown>, members: Record<string, ReturnType<Harness["as"]>>) => {
      await change();
      for (const l of Object.values(on)) await l.take();
      for (const [name, who] of Object.entries(members)) {
        for (const e of got[name]!.splice(0)) {
          if (e.type === "workspaces" && e.entry) assert.deepEqual(e.entry, await listed(who), `${what}: ${name}'s entry of the list`);
          if (e.type !== "workspace" || e.id !== w) continue;
          if (e.rev && held[name]?.rev === e.rev[0]) {
            held[name] = patched(held[name], e);
            patchedOnce++;
          } else held[name] = await read(who);
        }
        assert.deepEqual(held[name], await read(who), `${what}: ${name}'s view as told`);
      }
      for (const name of Object.keys(got)) got[name]!.splice(0);
    };
    await after("rename", () => alice("PATCH", `/v1/workspaces/${w}`, { name: "House" }), { alice });
    await after("an invitation", () => alice("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "bob@example.test" }), { alice });
    const invitation = ((await (await bob("GET", "/v1/me")).json()) as any).invitations[0].id;
    await after("bob joins", () => bob("POST", `/v1/invitations/${invitation}/accept`), { alice, bob });
    await after("carol added", () => alice("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["carol@example.test"] }), { alice, bob, carol });
    const bobSub = held.alice.members.find((m: any) => m.email === "bob@example.test").sub;
    const carolSub = held.alice.members.find((m: any) => m.email === "carol@example.test").sub;
    await after("bob an admin", () => alice("PATCH", `/v1/workspaces/${w}/members/${bobSub}`, { role: "admin" }), { alice, bob, carol });
    const station = await enrollStation(h, alice, w, "willow");
    await after("a station enrolled", async () => {}, { alice, bob, carol });
    await after("the station renamed", () => alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { name: "big willow", emoji: "🍎" }), { alice, bob, carol });
    await after("an icon", () => alice("PATCH", `/v1/workspaces/${w}`, { icon: "glyph:rocket:blue", emoji: "🚀" }), { alice, bob, carol });
    await after("the icon taken away", () => alice("PATCH", `/v1/workspaces/${w}`, { icon: "", emoji: "" }), { alice, bob, carol });
    await after("added by email, not signed in yet", () => bob("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["erin@example.test"] }), { alice, bob, carol });
    await after("carol out", () => alice("DELETE", `/v1/workspaces/${w}/members/${carolSub}`), { alice, bob });
    await after("the station out", () => alice("DELETE", `/v1/workspaces/${w}/stations/${station.id}`), { alice, bob });
    console.log(`PATCHED ${patchedOnce}`);
    assert.ok(patchedOnce >= 15, `the views told were patched (${patchedOnce}), not read again`);
  } finally {
    await h.close();
  }
});

// What tells a change never fails the request it follows (2026-11-15: a first version of `#told` answered 500 to an
// invitation already made, reading a row it had not written): a view as last told that cannot be read is let go of,
// every member told plainly as before there were versions, and the next change told with versions again.
for (const [what, kept] of [["not JSON", "{not json"], ["a list not a list", JSON.stringify({ id: "x", name: "Home", members: "alice", stations: [] })]] as const) {
  test(`a view as last told that cannot be read (${what}): the change answers, every member told plainly, the next told with versions`, async () => {
    const h = await harness();
    try {
      const tokens = { alice: await h.login("alice"), bob: await h.login("bob") };
      const alice = h.as(tokens.alice), bob = h.as(tokens.bob);
      const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
      await alice("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "bob@example.test" });
      const invitation = ((await (await bob("GET", "/v1/me")).json()) as any).invitations[0].id;
      assert.equal((await bob("POST", `/v1/invitations/${invitation}/accept`)).status, 200);
      const on = { alice: await listen(h, tokens.alice.access_token), bob: await listen(h, tokens.bob.access_token) };
      const got: Record<string, any[]> = { alice: [], bob: [] };
      for (const [name, l] of Object.entries(on)) l.ws.addEventListener("message", (event) => void (event.data === "pong" || got[name]!.push(JSON.parse(event.data as string))));
      const took = async () => {
        for (const l of Object.values(on)) await l.take();
        const all = { alice: got.alice!.splice(0), bob: got.bob!.splice(0) };
        return all;
      };
      const directory = await h.object("DIRECTORY", "primary");
      await alice("PATCH", `/v1/workspaces/${w}`, { name: "House" });
      await took();
      const was = await directory.toldOf(w);
      assert.ok(was, "a view as last told kept");
      await directory.keepTold(w, kept, was.rev);
      const renamed = await alice("PATCH", `/v1/workspaces/${w}`, { name: "Hut" });
      console.log(`CHANGE AFTER ${what}: ${renamed.status}`);
      assert.equal(renamed.status, 200, `the change answered: ${await renamed.clone().text()}`);
      const plain = await took();
      for (const name of ["alice", "bob"] as const) {
        assert.deepEqual(plain[name].map((e) => JSON.stringify(e)).sort(), [JSON.stringify({ type: "workspaces" }), JSON.stringify({ type: "workspace", id: w })].sort(), `${name} told plainly`);
      }
      const after = await directory.toldOf(w);
      assert.ok(after === null || (after.view !== kept && after.rev > was.rev), `the row let go of or begun again above ${was.rev}: ${JSON.stringify(after)}`);
      await alice("PATCH", `/v1/workspaces/${w}`, { name: "Home" });
      const told = await took();
      for (const name of ["alice", "bob"] as const) {
        const event = told[name].find((e) => e.type === "workspace");
        assert.ok(Array.isArray(event?.rev), `${name} told with versions again: ${JSON.stringify(told[name])}`);
        assert.equal(event.set?.name, "Home");
        assert.ok(told[name].find((e) => e.type === "workspaces")?.entry, `${name} told their entry again`);
      }
    } finally {
      await h.close();
    }
  });
}

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

/** Each listener got exactly these events (in any order); the rest got none. */
async function expect(listeners: Record<string, Listener>, expected: Record<string, AccountEvent[]>, what: string) {
  for (const [name, listener] of Object.entries(listeners)) {
    assert.deepEqual(await listener.take(), (expected[name] ?? []).map((e) => JSON.stringify(e)).sort(), `${what}: ${name}`);
  }
}

async function connectStation(h: Harness, station: Awaited<ReturnType<typeof key>>, options: { ts?: number; signer?: Awaited<ReturnType<typeof key>> } = {}) {
  const ts = options.ts ?? Math.floor(Date.now() / 1000);
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
    assert.deepEqual(first.frames![0], { type: "state", workspace: w, workspace_name: "House", name: "studio", origin: first.frames![0].origin, relay_url: first.frames![0].relay_url, relay_urls: first.frames![0].relay_urls, relay_names: first.frames![0].relay_names, grant_keys: first.frames![0].grant_keys, revocations: first.frames![0].revocations });
    // bob's role changed above: the credentials he held then are refused, as the station hears at once on connecting.
    assert.deepEqual(first.frames![0].revocations.map((r: any) => [r.kind, r.id]), [["sub", bobSub]]);
    let seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.deepEqual([seen.version, "online" in seen], ["0.2.0", false]);

    await alice("PATCH", `/v1/workspaces/${w}/stations/${station.id}`, { name: "big studio" });
    await expect(on, { alice: [ws], bob: [ws] }, "rename station");
    await first.ping!();
    assert.equal(first.frames!.at(-1).name, "big studio", "the station learns its new name");

    first.ws!.close(1000);
    await new Promise((resolve) => setTimeout(resolve, 100));
    await expect(on, {}, "nor does leaving");
    seen = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0];
    assert.ok(seen.last_seen >= Math.floor(Date.now() / 1000) - 5, "last here at");

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
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.deepEqual(await events.take(), [], "a station's socket tells no one");

    const directories: any = await h.mf.getDurableObjectNamespace("DIRECTORY", "api");
    const directory = directories.get(directories.idFromName("primary"));
    await second.ping!();
    assert.equal(await directory.sweepAt(Date.now() + SILENT_MS - 5000), true, "answered pings keep it");
    assert.equal(await directory.sweepAt(Date.now() + SILENT_MS + 5000), false);
    assert.equal(await second.closed, 4008);
    assert.deepEqual(await events.take(), []);
    assert.ok(((await (await alice("GET", `/v1/workspaces/${w}`)).json()) as any).stations[0].last_seen >= Math.floor(Date.now() / 1000) - 5);
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
    assert.equal((await connectStation(h, station, { ts: Math.floor(Date.now() / 1000) - 600 })).status, 400);
    assert.equal((await connectStation(h, forged)).status, 404, "not enrolled");
    assert.equal((await h.fetch("/v1/stations/connect")).status, 426);
    assert.equal((await h.fetch("/v1/stations/heartbeat", { method: "POST" })).status, 404, "gone");
  } finally {
    await h.close();
  }
});

// What stations share (directory.ts `stationShare`, docs/station-share.md): only which station hosts what and which
// may use it, changed only by the host (signed with its key), told to the workspace's stations and members.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { harness } from "./harness.ts";

type Harness = Awaited<ReturnType<typeof harness>>;
const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");

async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}
type Station = Awaited<ReturnType<typeof key>>;

async function enroll(h: Harness, owner: ReturnType<Harness["as"]>, workspace: string, name: string): Promise<Station> {
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

/** A request about what `station` shares, signed by `signer` (the station itself by default). */
async function share(h: Harness, station: Station, body: unknown, signer: Station = station) {
  const text = JSON.stringify(body);
  const ts = Math.floor(Date.now() / 1000);
  const digest = createHash("sha256").update(text).digest("hex");
  const headers = { "content-type": "application/json", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await signer.sign(`stillfail-station-shares-v1:${h.origin}:${station.id}:${ts}:${digest}`) };
  return h.fetch("/v1/stations/shares", { method: "POST", headers, body: text });
}

async function connect(h: Harness, station: Station) {
  const ts = Math.floor(Date.now() / 1000);
  const response = await h.fetch("/v1/stations/connect", {
    headers: { upgrade: "websocket", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await station.sign(`stillfail-station-connect-v1:${h.origin}:${station.id}:${ts}`) },
  });
  assert.equal(response.status, 101);
  const ws = response.webSocket!;
  const frames: any[] = [];
  let pong: (() => void) | null = null;
  ws.addEventListener("message", (event) => (event.data === "pong" ? pong?.() : frames.push(JSON.parse(event.data as string))));
  ws.accept();
  const ping = () => new Promise<void>((resolve) => { pong = resolve; ws.send("ping"); });
  return { ws, frames, ping };
}

test("a station shares, changes who may use it, hands it over; only its host may, the others hear it, and it goes with its host", { timeout: 30000 }, async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const studio = await enroll(h, alice, w, "studio");
    const mini = await enroll(h, alice, w, "mini");
    const heard = await connect(h, mini);
    await heard.ping();
    assert.deepEqual(heard.frames.at(-1).shares, [], "an empty list from a cloud that has shares");

    const id = "sh-0123456789abcdef0123";
    const made = await share(h, studio, { op: "put", id, kind: "profile", name: "Claude Max", allow: null });
    assert.equal(made.status, 200);
    await heard.ping();
    assert.deepEqual(heard.frames.at(-1).shares.map((s: any) => [s.id, s.host, s.allow]), [[id, studio.id, null]]);
    // Seen by the workspace's members too.
    const view = (await (await alice("GET", `/v1/workspaces/${w}`)).json()) as any;
    assert.equal(view.shares[0].name, "Claude Max");

    // Not its host: refused; signed by another key: refused.
    assert.equal((await share(h, mini, { op: "put", id, kind: "profile", name: "mine now" })).status, 403);
    assert.equal((await share(h, mini, { op: "delete", id })).status, 403);
    assert.equal((await share(h, studio, { op: "delete", id }, mini)).status, 401);
    assert.equal((await share(h, studio, { op: "put", id: "Bad Id", kind: "profile", name: "x" })).status, 400);
    assert.equal((await share(h, studio, { op: "put", id: "sh-aaaaaaaaaaaa", kind: "car", name: "x" })).status, 400);

    assert.equal((await share(h, studio, { op: "put", id, kind: "profile", name: "Claude Max", allow: [studio.id] })).status, 200);
    await heard.ping();
    assert.deepEqual(heard.frames.at(-1).shares[0].allow, [studio.id]);

    // Handed over to mini: mini is its host from then on.
    assert.equal((await share(h, studio, { op: "move", id, host: "f".repeat(64) })).status, 400, "not a station of the workspace");
    assert.equal((await share(h, studio, { op: "move", id, host: mini.id })).status, 200);
    await heard.ping();
    assert.equal(heard.frames.at(-1).shares[0].host, mini.id);
    assert.equal((await share(h, studio, { op: "delete", id })).status, 403, "no longer studio's");

    // Its host removed from the workspace: what it shared goes with it.
    assert.equal((await alice("DELETE", `/v1/workspaces/${w}/stations/${mini.id}`)).status, 200);
    const after = (await (await alice("GET", `/v1/workspaces/${w}`)).json()) as any;
    assert.deepEqual(after.shares, []);
  } finally {
    await h.close();
  }
});

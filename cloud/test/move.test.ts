import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";

// Moving one cloud's accounts into another (src/move.ts).

const hex = (bytes: ArrayBuffer) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}

test("a cloud's accounts, workspaces, stations and sessions go whole into another that is moving, and only into one", async () => {
  const from = await harness();
  const into = await harness({ moving: true, signingKey: from.signingKey });
  try {
    // Alice's workspace, Bob in it, a station enrolled: what there is to move.
    const aliceTokens = await from.login("alice");
    await from.login("bob");
    const alice = from.as(aliceTokens);
    const id = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as { id: string }).id;
    assert.equal((await alice("POST", `/v1/workspaces/${id}/members`, { role: "member", emails: ["bob@example.test"] })).status, 200);
    const enrollment = (await (await alice("POST", `/v1/workspaces/${id}/enrollments`, { name: "willow" })).json()) as { token: string };
    const station = await key();
    const enrolled = await from.fetch("/v1/stations/enroll", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: enrollment.token, station: station.id, signature: await station.sign(`stillfail-station-enroll-v1:${from.origin}:${enrollment.token}:${station.id}`) }),
    });
    assert.equal(enrolled.status, 200);

    const admin = (h: typeof from, token = h.adminToken) => ({ authorization: `Bearer ${token}` });
    assert.equal((await from.fetch("/v1/admin/move/export", { method: "POST" })).status, 401, "the admin's token only");
    const exported = await (await from.fetch("/v1/admin/move/export", { method: "POST", headers: admin(from) })).json() as { directory: Record<string, Record<string, unknown>[]>; accounts: Record<string, Record<string, unknown>> };
    assert.equal(exported.directory.users!.length, 2);
    assert.equal(exported.directory.workspaces!.length, 1);
    assert.equal(exported.directory.station_members!.length, 1);
    assert.ok(!("outbox" in exported.directory) && !("live" in exported.directory) && !("hits" in exported.directory), "what is the object's own stays");
    assert.equal(Object.keys(exported.accounts).length, 2);
    assert.ok(Object.values(exported.accounts).every((a) => (a.account as { sessions: unknown[] }).sessions.length === 1), "each account's session goes with it");

    // A cloud in use is never written over.
    assert.equal((await from.fetch("/v1/admin/move/import", { method: "POST", headers: { ...admin(from), "content-type": "application/json" }, body: JSON.stringify(exported) })).status, 409);

    // The one moving takes it whole, and gives back the same.
    const written = await into.fetch("/v1/admin/move/import", { method: "POST", headers: { ...admin(into), "content-type": "application/json" }, body: JSON.stringify(exported) });
    assert.equal(written.status, 200);
    assert.equal(((await written.json()) as { accounts: number }).accounts, 2);
    const again = await (await into.fetch("/v1/admin/move/export", { method: "POST", headers: admin(into) })).json();
    assert.deepEqual(again, exported);

    // While moving, everything else waits (503, never a 401 that signs anyone out); installing a station does not.
    const me = await into.fetch("/v1/me", { headers: { authorization: `Bearer ${aliceTokens.access_token}` } });
    assert.equal(me.status, 503);
    assert.equal(((await me.json()) as { error: string }).error, "moving");
    assert.equal((await into.fetch("/install.sh")).status, 200);
  } finally {
    await from.close();
    await into.close();
  }
});

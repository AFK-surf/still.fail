import assert from "node:assert/strict";
import test from "node:test";
import { importJWK, jwtVerify } from "jose";
import { harness } from "./harness.ts";

const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");

/** An iroh-style identity: an Ed25519 key whose public half, in hex, is the endpoint id. */
async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}

test("accounts own workspaces, invite each other, enroll stations and get credentials for them", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const bob = h.as(await h.login("bob"));

    // Each account sees only its own workspaces; one account may create several.
    const home = await (await alice("POST", "/v1/workspaces", { name: "  Home  " })).json() as any;
    assert.equal(home.name, "Home");
    assert.equal(home.role, "owner");
    await alice("POST", "/v1/workspaces", { name: "Lab" });
    const aliceMe = await (await alice("GET", "/v1/me")).json() as any;
    assert.deepEqual(aliceMe.workspaces.map((w: any) => w.name), ["Home", "Lab"]);
    assert.equal(aliceMe.user.name, "Name of alice");
    assert.equal((await bob("GET", `/v1/workspaces/${home.id}`)).status, 404);

    // An invitation bound to bob's email; bob previews and accepts it.
    const invite = await (await alice("POST", `/v1/workspaces/${home.id}/invitations`, { role: "member", email: "bob@example.test" })).json() as any;
    assert.match(invite.url, /\/invite#/);
    const preview = await (await bob("POST", "/v1/invitations/preview", { token: invite.token })).json() as any;
    assert.deepEqual([preview.name, preview.role, preview.inviter], ["Home", "member", "Name of alice"]);
    const carol = h.as(await h.login("carol"));
    assert.equal((await carol("POST", "/v1/invitations/accept", { token: invite.token })).status, 403, "bound to another email");
    assert.equal((await bob("POST", "/v1/invitations/accept", { token: invite.token })).status, 200);
    assert.equal((await bob("POST", "/v1/invitations/accept", { token: invite.token })).status, 404, "one use");
    assert.deepEqual(((await (await bob("GET", "/v1/me")).json()) as any).workspaces.map((w: any) => [w.name, w.role]), [["Home", "member"]]);

    // Members cannot manage; owners decide roles; the last owner stays.
    assert.equal((await bob("POST", `/v1/workspaces/${home.id}/invitations`, {})).status, 403);
    const view = await (await alice("GET", `/v1/workspaces/${home.id}`)).json() as any;
    const bobSub = view.members.find((m: any) => m.email === "bob@example.test").sub;
    const aliceSub = view.members.find((m: any) => m.role === "owner").sub;
    assert.equal((await alice("DELETE", `/v1/workspaces/${home.id}/members/${aliceSub}`)).status, 409);
    assert.equal((await alice("PATCH", `/v1/workspaces/${home.id}/members/${bobSub}`, { role: "admin" })).status, 200);

    // A station enrolls with a one-time token and proves it holds its key.
    const enrollment = await (await bob("POST", `/v1/workspaces/${home.id}/enrollments`, { name: "studio" })).json() as any;
    assert.match(enrollment.command, /^ember station enroll https:\/\/relay\.example [A-Za-z0-9_-]{43}$/);
    const station = await key();
    const forged = await key();
    const enroll = (token: string, id: string, signature: string) =>
      h.fetch("/v1/stations/enroll", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token, station: id, signature, version: "0.1.0" }) });
    const message = (id: string) => `ember-station-enroll-v1:${h.origin}:${enrollment.token}:${id}`;
    assert.equal((await enroll(enrollment.token, station.id, await forged.sign(message(station.id)))).status, 401, "must hold the key");
    const enrolled = await (await enroll(enrollment.token, station.id, await station.sign(message(station.id)))).json() as any;
    assert.deepEqual([enrolled.workspace, enrolled.name, enrolled.relay_url], [home.id, "studio", h.origin]);
    assert.equal((await enroll(enrollment.token, forged.id, await forged.sign(message(forged.id)))).status, 404, "one use");

    const ts = Math.floor(Date.now() / 1000);
    const connect = async () => h.fetch("/v1/stations/connect", {
      headers: { upgrade: "websocket", "x-ember-station": station.id, "x-ember-ts": String(ts), "x-ember-signature": await station.sign(`ember-station-connect-v1:${h.origin}:${station.id}:${ts}`) },
    });
    const presence = await connect();
    assert.equal(presence.status, 101);
    presence.webSocket!.accept();
    const told: any[] = [];
    presence.webSocket!.addEventListener("message", (event) => told.push(JSON.parse(event.data as string)));

    // A member's credential names who, where, with what role, from which device and session; stations verify it
    // offline, for 30 days, whichever of the workspace's stations it is shown to.
    const device = await key();
    const issued = await (await bob("POST", `/v1/workspaces/${home.id}/credential`, { device: device.id })).json() as any;
    const keys = await (await h.fetch("/.well-known/ember-grant-keys")).json() as any;
    assert.equal(keys.keys[0].d, undefined, "no private half");
    const { payload, protectedHeader } = await jwtVerify(issued.credential, await importJWK(keys.keys[0], "EdDSA"), { issuer: "ember-cloud" });
    assert.deepEqual([payload.ws, payload.role, payload.device, payload.email, payload.name], [home.id, "admin", device.id, "bob@example.test", "Name of bob"]);
    assert.deepEqual([protectedHeader.typ, payload.exp! - payload.iat!, typeof payload.sid, issued.expires_at - issued.issued_at], ["ember-member+jwt", 30 * 86400, "string", 30 * 86400]);
    assert.equal((await carol("POST", `/v1/workspaces/${home.id}/credential`, { device: device.id })).status, 404);

    // Removing a member: no new credential, and the stations are told to refuse the ones it holds.
    assert.equal((await alice("DELETE", `/v1/workspaces/${home.id}/members/${bobSub}`)).status, 200);
    assert.equal((await bob("POST", `/v1/workspaces/${home.id}/credential`, { device: device.id })).status, 404);
    await new Promise((resolve) => setTimeout(resolve, 50));
    const revoke = told.find((frame) => frame.type === "revoke");
    assert.deepEqual([revoke?.kind, revoke?.id, typeof revoke?.at], ["sub", bobSub, "number"]);
    // A station connecting later hears it with its state.
    const again = await connect();
    again.webSocket!.accept();
    const later: any[] = [];
    again.webSocket!.addEventListener("message", (event) => later.push(JSON.parse(event.data as string)));
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.deepEqual(later.find((frame) => frame.type === "state")?.revocations.map((r: any) => [r.kind, r.id]), [["sub", bobSub]]);
    assert.equal((await alice("DELETE", `/v1/workspaces/${home.id}/stations/${station.id}`)).status, 200);
    assert.equal((await connect()).status, 404);
  } finally {
    await h.close();
  }
});

test("an invitation waits for its email: signing in with it shows the invitation, which joins without a link", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const bob = h.as(await h.login("bob"));
    const home = await (await alice("POST", "/v1/workspaces", { name: "Home" })).json() as any;
    assert.equal((await alice("POST", `/v1/workspaces/${home.id}/invitations`, { role: "member" })).status, 400, "an email is required");
    assert.equal((await alice("POST", `/v1/workspaces/${home.id}/invitations`, { role: "member", email: "alice@example.test" })).status, 409, "already a member");
    await alice("POST", `/v1/workspaces/${home.id}/invitations`, { role: "member", email: "Bob@Example.test" });
    const me = await (await bob("GET", "/v1/me")).json() as any;
    assert.deepEqual(me.invitations.map((i: any) => [i.name, i.role, i.inviter]), [["Home", "member", "Name of alice"]]);
    const carol = h.as(await h.login("carol"));
    assert.equal((await carol("POST", `/v1/invitations/${me.invitations[0].id}/accept`)).status, 403);
    assert.equal((await bob("POST", `/v1/invitations/${me.invitations[0].id}/accept`)).status, 200);
    const after = await (await bob("GET", "/v1/me")).json() as any;
    assert.deepEqual([after.invitations.length, after.workspaces.map((w: any) => w.name)], [0, ["Home"]]);
  } finally {
    await h.close();
  }
});

test("the web app may use this origin's /auth/callback; other redirects are refused", async () => {
  const h = await harness();
  try {
    const start = (redirect: string) => h.fetch("/v1/auth/google/start?" + new URLSearchParams({
      state: "s".repeat(43), code_challenge: "c".repeat(43), code_challenge_method: "S256", redirect_uri: redirect,
    }), { redirect: "manual" });
    assert.equal((await start(`${h.origin}/auth/callback`)).status, 302);
    assert.equal((await start("https://evil.example/auth/callback")).status, 400);
  } finally {
    await h.close();
  }
});

test("the Android app signs in through ember://auth/callback", async () => {
  const h = await harness();
  try {
    const flow = await h.begin("google-android-user", undefined, "ember://auth/callback");
    const { redirect, code } = await h.complete(flow);
    assert.equal(`${redirect.protocol}//${redirect.host}${redirect.pathname}`, "ember://auth/callback");
    assert.equal(redirect.searchParams.get("state"), flow.state);
    const tokens = await h.exchange(flow, code);
    assert.equal(tokens.status, 200);
    assert.equal(((await tokens.json()) as { subject: string }).subject, "google-android-user");
  } finally {
    await h.close();
  }
});

test("people are added by email: members at once with an account, else from their first sign-in; no invitation to accept", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const bob = h.as(await h.login("bob"));
    const home = await (await alice("POST", "/v1/workspaces", { name: "Home" })).json() as any;
    await alice("POST", `/v1/workspaces/${home.id}/invitations`, { role: "member", email: "dave@example.test" });
    const made = await (await alice("POST", `/v1/workspaces/${home.id}/members`, { role: "member", emails: ["Bob@example.test", "dave@example.test", " alice@example.test "] })).json() as any;
    assert.deepEqual([made.joined, made.added, made.already], [["bob@example.test"], ["dave@example.test"], ["alice@example.test"]]);
    assert.deepEqual(made.view.added.map((a: any) => a.email), ["dave@example.test"]);
    assert.deepEqual(made.view.invitations, [], "being added replaces the invitation");
    assert.equal((await bob("GET", `/v1/workspaces/${home.id}`)).status, 200, "an account is a member at once");
    assert.equal((await bob("POST", `/v1/workspaces/${home.id}/members`, { emails: ["x@example.test"] })).status, 403, "only managers add");
    assert.equal((await alice("POST", `/v1/workspaces/${home.id}/members`, { emails: ["not an email"] })).status, 400);
    // dave signs in for the first time: a member already.
    const dave = h.as(await h.login("dave"));
    const me = await (await dave("GET", "/v1/me")).json() as any;
    assert.deepEqual(me.workspaces.map((w: any) => [w.name, w.role]), [["Home", "member"]]);
    const view = await (await alice("GET", `/v1/workspaces/${home.id}`)).json() as any;
    assert.deepEqual([view.members.length, view.added], [3, []]);
    // One added and taken back before signing in never joins.
    await alice("POST", `/v1/workspaces/${home.id}/members`, { emails: ["erin@example.test"] });
    await alice("DELETE", `/v1/workspaces/${home.id}/added/erin@example.test`);
    const erin = h.as(await h.login("erin"));
    assert.deepEqual((await (await erin("GET", "/v1/me")).json() as any).workspaces, []);
  } finally {
    await h.close();
  }
});

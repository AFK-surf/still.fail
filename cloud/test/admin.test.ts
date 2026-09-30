import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";

const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");

// alice is the admin in every harness (ADMIN_EMAIL=alice@example.test).

test("the console answers only the admin, and only on its host; everyone else gets the 404 of a path nobody serves", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const alice = h.as(aliceTokens);
    const aliceAdmin = h.as(aliceTokens, "admin");
    const bob = h.as(await h.login("bob"), "admin");
    const paths: [string, string][] = [["GET", "/v1/admin/me"], ["GET", "/v1/admin/users"], ["GET", "/v1/admin/workspaces"], ["GET", "/v1/admin/invite-codes"], ["POST", "/v1/admin/invite-codes"], ["POST", "/v1/admin/invite-codes/AAAA-BBBB-CCCC/revoke"]];
    const nobody = await (await h.fetch("/v1/nothing-here")).text();
    for (const [method, path] of paths) {
      const body = method === "POST" ? {} : undefined;
      for (const response of [await bob(method, path, body), await h.fetchAdmin(path, { method }), await alice(method, path, body)]) {
        assert.equal(response.status, 404, `${method} ${path}`);
        assert.equal(await response.text(), nobody);
      }
    }
    assert.deepEqual(await (await aliceAdmin("GET", "/v1/admin/me")).json(), { email: "alice@example.test" });
    assert.equal((await aliceAdmin("GET", "/v1/admin/nothing")).status, 404);
    // The scripts' token is no way in, and their routes (on the main host only) still take it.
    assert.equal((await h.fetch("/v1/admin/users", { headers: { authorization: `Bearer ${h.adminToken}` } })).status, 404);
    assert.equal((await h.fetch("/v1/admin/relay/restart", { method: "POST", headers: { authorization: `Bearer ${h.adminToken}` } })).status, 200);
    assert.equal((await h.fetchAdmin("/v1/admin/relay/restart", { method: "POST", headers: { authorization: `Bearer ${h.adminToken}` } })).status, 404);
  } finally {
    await h.close();
  }
});

test("the admin sees every user, workspace and code", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const alice = h.as(aliceTokens);
    const aliceAdmin = h.as(aliceTokens, "admin");
    const bob = h.as(await h.login("bob"));
    const carol = h.as(await h.login("carol"));
    await h.login("dave");

    const home = await (await alice("POST", "/v1/workspaces", { name: "Home" })).json() as any;
    await alice("POST", `/v1/workspaces/${home.id}/invitations`, { role: "member", email: "bob@example.test" });
    const invitation = ((await (await bob("GET", "/v1/me")).json()) as any).invitations[0];
    assert.equal((await bob("POST", `/v1/invitations/${invitation.id}/accept`)).status, 200);
    await alice("POST", `/v1/workspaces/${home.id}/invitations`, { role: "admin", email: "erin@example.test" });

    // A station, enrolled and never connected.
    const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const station = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
    const enrollment = await (await alice("POST", `/v1/workspaces/${home.id}/enrollments`, { name: "studio" })).json() as any;
    const signature = hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(`stillfail-station-enroll-v1:${h.origin}:${enrollment.token}:${station}`)));
    assert.equal((await h.fetch("/v1/stations/enroll", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token: enrollment.token, station, signature, version: "0.3.1" }) })).status, 200);

    const made = await (await aliceAdmin("POST", "/v1/admin/invite-codes", { note: "  for   carol " })).json() as any;
    assert.match(made.code, /^[A-HJKMNP-TV-Z2-9]{4}-[A-HJKMNP-TV-Z2-9]{4}-[A-HJKMNP-TV-Z2-9]{4}$/);
    assert.equal(made.url, `${h.origin}/?invite=${made.code}`);
    assert.equal(made.note, "for carol");
    assert.equal(made.expires_at - made.created_at, 14 * 24 * 60 * 60, "two weeks unless said otherwise");
    const lab = await (await carol("POST", "/v1/workspaces", { name: "Lab", invite_code: made.code })).json() as any;
    const spare = await (await aliceAdmin("POST", "/v1/admin/invite-codes", { days: 3 })).json() as any;
    assert.equal(spare.expires_at - spare.created_at, 3 * 24 * 60 * 60);
    assert.equal((await aliceAdmin("POST", "/v1/admin/invite-codes", { days: 0 })).status, 400);
    assert.equal((await aliceAdmin("POST", "/v1/admin/invite-codes", { note: "x".repeat(201) })).status, 400);

    const { users } = await (await aliceAdmin("GET", "/v1/admin/users")).json() as any;
    const by = (email: string) => users.find((u: any) => u.email === email);
    assert.deepEqual(users.map((u: any) => u.email).sort(), ["alice", "bob", "carol", "dave"].map((n) => `${n}@example.test`));
    assert.deepEqual([by("alice@example.test").admission, by("bob@example.test").admission, by("carol@example.test").admission, by("dave@example.test").admission], ["admin", "invitation", "code", null]);
    assert.deepEqual(by("bob@example.test").workspaces, [{ id: home.id, name: "Home", role: "member" }]);
    assert.deepEqual(by("carol@example.test").workspaces, [{ id: lab.id, name: "Lab", role: "owner" }]);
    assert.deepEqual(by("dave@example.test").workspaces, []);
    assert.equal(by("dave@example.test").name, "Name of dave");
    assert.ok(by("dave@example.test").last_seen >= by("dave@example.test").created_at, "signing in is being seen");

    const { workspaces } = await (await aliceAdmin("GET", "/v1/admin/workspaces")).json() as any;
    assert.deepEqual(workspaces.map((w: any) => w.name).sort(), ["Home", "Lab"]);
    const seen = workspaces.find((w: any) => w.id === home.id);
    assert.equal(seen.created_by.email, "alice@example.test");
    assert.deepEqual(seen.members.map((m: any) => [m.email, m.role]), [["alice@example.test", "owner"], ["bob@example.test", "member"]]);
    assert.deepEqual(seen.stations.map((s: any) => [s.id, s.name, s.version]), [[station, "studio", "0.3.1"]]);
    assert.deepEqual(seen.invitations.map((i: any) => [i.email, i.role, i.inviter]), [["erin@example.test", "admin", "Name of alice"]]);

    const { codes } = await (await aliceAdmin("GET", "/v1/admin/invite-codes")).json() as any;
    const used = codes.find((c: any) => c.code === made.code);
    assert.deepEqual([used.used_by.email, used.workspace, used.revoked_at], ["carol@example.test", { id: lab.id, name: "Lab" }, null]);
    assert.ok(used.used_at >= used.created_at);
    assert.equal(used.url, `${h.origin}/?invite=${made.code}`, "the sign-up link is the web app's, not the console's");
    const open = codes.find((c: any) => c.code === spare.code);
    assert.deepEqual([open.used_by, open.used_at, open.workspace, open.revoked_at, open.note], [null, null, null, null, ""]);

    // Revoking: an unused code stops working (and says so in the list); a used one stays used.
    assert.equal((await aliceAdmin("POST", `/v1/admin/invite-codes/${spare.code}/revoke`)).status, 200);
    assert.equal((await aliceAdmin("POST", `/v1/admin/invite-codes/${made.code}/revoke`)).status, 409);
    assert.equal((await aliceAdmin("POST", "/v1/admin/invite-codes/AAAA-BBBB-CCCC/revoke")).status, 404);
    const after = ((await (await aliceAdmin("GET", "/v1/admin/invite-codes")).json()) as any).codes;
    assert.ok(after.find((c: any) => c.code === spare.code).revoked_at > 0);
    assert.equal(after.find((c: any) => c.code === made.code).revoked_at, null);
  } finally {
    await h.close();
  }
});

test("creating a workspace takes the admin, an account with a code (or from before codes), and no one only invited", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const alice = h.as(aliceTokens);
    const aliceAdmin = h.as(aliceTokens, "admin");
    const bob = h.as(await h.login("bob"));
    const carol = h.as(await h.login("carol"));
    const dave = h.as(await h.login("dave"));
    const create = async (as: typeof alice, body: Record<string, unknown>) => {
      const response = await as("POST", "/v1/workspaces", { name: "W", ...body });
      return response.ok ? response.status : [response.status, ((await response.json()) as any).error];
    };
    const code = async (days?: number) => ((await (await aliceAdmin("POST", "/v1/admin/invite-codes", days ? { days } : {})).json()) as any).code as string;

    assert.equal(await create(alice, {}), 200, "the admin needs no code");
    assert.deepEqual(await create(dave, {}), [403, "invite_code_required"]);
    assert.deepEqual(await create(dave, { invite_code: "   " }), [403, "invite_code_required"]);
    assert.deepEqual(await create(dave, { invite_code: "not a code" }), [404, "invite_code_invalid"]);
    assert.deepEqual(await create(dave, { invite_code: "AAAA-BBBB-CCCC" }), [404, "invite_code_invalid"]);

    const revoked = await code();
    await aliceAdmin("POST", `/v1/admin/invite-codes/${revoked}/revoke`);
    assert.deepEqual(await create(dave, { invite_code: revoked }), [404, "invite_code_invalid"]);

    const expired = await code();
    const directories: any = await h.mf.getDurableObjectNamespace("DIRECTORY", "api");
    const directory = directories.get(directories.idFromName("primary"));
    await directory.expireInviteCode(expired);
    assert.deepEqual(await create(dave, { invite_code: expired }), [410, "invite_code_expired"]);

    // A code as typed by hand: any case, spaces for dashes.
    const good = await code();
    assert.equal(await create(dave, { invite_code: ` ${good.toLowerCase().replaceAll("-", " ")} ` }), 200);
    assert.deepEqual(await create(carol, { invite_code: good }), [409, "invite_code_used"]);
    assert.equal(await create(dave, { invite_code: "whatever" }), 200, "once in, a code is not needed (nor looked at) again");
    const codes = ((await (await aliceAdmin("GET", "/v1/admin/invite-codes")).json()) as any).codes;
    assert.equal(codes.filter((c: any) => c.used_by).length, 1, "one code, one workspace");

    // Invited into a workspace: in there only; making one of their own takes a code, and then the account may again.
    const home = await (await alice("POST", "/v1/workspaces", { name: "Home" })).json() as any;
    const invite = await (await alice("POST", `/v1/workspaces/${home.id}/invitations`, { role: "member", email: "bob@example.test" })).json() as any;
    assert.equal((await bob("POST", "/v1/invitations/accept", { token: invite.token })).status, 200);
    assert.deepEqual(await create(bob, {}), [403, "invite_code_required"]);
    assert.equal(await create(bob, { invite_code: await code() }), 200);
    const bobSub = ((await (await bob("GET", "/v1/me")).json()) as any).user.sub;
    assert.equal((await bob("DELETE", `/v1/workspaces/${home.id}/members/${bobSub}`)).status, 200);
    assert.equal(await create(bob, {}), 200);
    const admitted = ((await (await aliceAdmin("GET", "/v1/admin/users")).json()) as any).users;
    assert.equal(admitted.find((u: any) => u.sub === bobSub).admission, "code");

    // A member from before codes existed has no admission on record; being in a workspace is enough.
    const carolSub = ((await (await carol("GET", "/v1/me")).json()) as any).user.sub;
    await alice("POST", `/v1/workspaces/${home.id}/invitations`, { role: "member", email: "carol@example.test" });
    const pending = ((await (await carol("GET", "/v1/me")).json()) as any).invitations[0];
    await carol("POST", `/v1/invitations/${pending.id}/accept`);
    await directory.forgetAdmission(carolSub);
    assert.equal(await create(carol, {}), 200);
    const users = ((await (await aliceAdmin("GET", "/v1/admin/users")).json()) as any).users;
    assert.equal(users.find((u: any) => u.sub === carolSub).admission, "early");
  } finally {
    await h.close();
  }
});

test("two creations racing on one code: exactly one gets it", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const alice = h.as(aliceTokens);
    const aliceAdmin = h.as(aliceTokens, "admin");
    const racers = await Promise.all(["bob", "carol", "dave", "erin"].map(async (name) => h.as(await h.login(name))));
    const { code } = await (await aliceAdmin("POST", "/v1/admin/invite-codes", {})).json() as any;
    const results = await Promise.all(racers.map((as, i) => as("POST", "/v1/workspaces", { name: `W${i}`, invite_code: code })));
    const statuses = results.map((r) => r.status).sort();
    assert.deepEqual(statuses, [200, 409, 409, 409]);
    const { workspaces } = await (await aliceAdmin("GET", "/v1/admin/workspaces")).json() as any;
    assert.equal(workspaces.length, 1);
  } finally {
    await h.close();
  }
});

test("an account creates up to five workspaces, and a workspace lets in up to five people", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const aliceAdmin = h.as(aliceTokens, "admin");
    const bob = h.as(await h.login("bob"));
    const carol = h.as(await h.login("carol"));
    const { code } = await (await aliceAdmin("POST", "/v1/admin/invite-codes", {})).json() as any;
    const made: any[] = [];
    for (let i = 0; i < 5; i++) {
      const response = await bob("POST", "/v1/workspaces", { name: `W${i}`, ...(i === 0 ? { invite_code: code } : {}) });
      assert.equal(response.status, 200);
      made.push(await response.json());
    }
    const sixth = await bob("POST", "/v1/workspaces", { name: "W5" });
    assert.deepEqual([sixth.status, ((await sixth.json()) as any).error], [429, "too_many_workspaces"]);
    // Being made owner of someone else's does not count against it; deleting one of its own frees one.
    assert.equal((await bob("DELETE", `/v1/workspaces/${made[4].id}`)).status, 200);
    assert.equal((await bob("POST", "/v1/workspaces", { name: "W5" })).status, 200);

    // Five people: members, emails added, and open invitations all hold a seat.
    const w = made[0].id;
    const added = await bob("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["p1@example.test", "p2@example.test", "p3@example.test"] });
    assert.equal(added.status, 200);
    assert.equal((await bob("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "carol@example.test" })).status, 200);
    // A newer invitation to the same email takes the older one's seat.
    const again = await (await bob("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "carol@example.test" })).json() as any;
    assert.equal((await bob("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["p4@example.test"] })).status, 200);
    const full = await bob("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "p5@example.test" });
    assert.deepEqual([full.status, ((await full.json()) as any).error], [429, "too_many_members"]);
    const over = await bob("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["p5@example.test"] });
    assert.deepEqual([over.status, ((await over.json()) as any).error], [429, "too_many_members"]);
    // Adding someone already added, or invited, takes no new seat.
    assert.equal((await bob("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["p1@example.test"] })).status, 200);
    assert.equal((await carol("POST", "/v1/invitations/accept", { token: again.token })).status, 200);
    const view = await (await bob("GET", `/v1/workspaces/${w}`)).json() as any;
    assert.equal(view.members.length + view.added.length, 6);
  } finally {
    await h.close();
  }
});

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

test("anyone creates one workspace free; more take the admin, a code (or being from before codes)", async () => {
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
    // A code given while a free one is left is still looked at: it is what the person asked for.
    assert.deepEqual(await create(dave, { invite_code: "not a code" }), [404, "invite_code_invalid"]);
    assert.equal(await create(dave, {}), 200, "the free plan's one");
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
    assert.equal(await create(dave, { invite_code: "whatever" }), 200, "once standard, a code is not needed (nor looked at) again");
    const codes = ((await (await aliceAdmin("GET", "/v1/admin/invite-codes")).json()) as any).codes;
    assert.equal(codes.filter((c: any) => c.used_by).length, 1, "one code, one workspace");

    // Invited into a workspace, an account still has its free one; past it, a code, and then the account may again.
    const home = await (await alice("POST", "/v1/workspaces", { name: "Home" })).json() as any;
    const invite = await (await alice("POST", `/v1/workspaces/${home.id}/invitations`, { role: "member", email: "bob@example.test" })).json() as any;
    assert.equal((await bob("POST", "/v1/invitations/accept", { token: invite.token })).status, 200);
    assert.equal(await create(bob, {}), 200);
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

test("free and standard workspaces both hold up to 64 stations", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const aliceAdmin = h.as(aliceTokens, "admin");
    const bobTokens = await h.login("bob");
    const bob = h.as(bobTokens);
    const w = (await (await bob("POST", "/v1/workspaces", { name: "Free" })).json() as any).id;
    const invited = await bob("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "carol@example.test" });
    assert.deepEqual([invited.status, ((await invited.json()) as any).error], [429, "too_many_members"]);
    const added = await bob("POST", `/v1/workspaces/${w}/members`, { role: "member", emails: ["carol@example.test"] });
    assert.deepEqual([added.status, ((await added.json()) as any).error], [429, "too_many_members"]);

    const enroll = async (join = false, issued?: string) => {
      const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
      const station = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
      let token = issued;
      if (!token) {
        const made = await bob("POST", `/v1/workspaces/${w}/enrollments`, { name: "s" });
        if (!made.ok) return [made.status, ((await made.json()) as any).error];
        token = ((await made.json()) as any).token;
      }
      const signature = hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(`stillfail-station-enroll-v1:${h.origin}:${token}:${station}`)));
      const response = await h.fetch(join ? "/v1/stations/join" : "/v1/stations/enroll", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token, station, signature, version: "0.3.1" }) });
      return response.ok ? response.status : [response.status, ((await response.json()) as any).error];
    };
    assert.equal(await enroll(), 200);
    assert.equal(await enroll(), 200);
    assert.equal(await enroll(), 200);
    const plans = async () => ((await (await aliceAdmin("GET", "/v1/admin/workspaces")).json()) as any).workspaces.map((x: any) => [x.plan, x.seats, x.station_seats, x.stations_unlimited]);
    assert.deepEqual(await plans(), [["free", 1, 64, undefined]]);

    await aliceAdmin("POST", `/v1/admin/users/${bobTokens.subject}/may-create`, { on: true });
    assert.deepEqual(await plans(), [["standard", 6, 64, undefined]]);
    assert.equal((await bob("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "carol@example.test" })).status, 200);
    assert.equal(await enroll(), 200);
    await aliceAdmin("POST", `/v1/admin/users/${bobTokens.subject}/may-create`, { on: false });
    const issued = async () => ((await (await bob("POST", `/v1/workspaces/${w}/enrollments`, { name: "late" })).json()) as any).token as string;
    const lateEnroll = await issued(), lateJoin = await issued();
    for (let n = 4; n < 64; n++) assert.equal(await enroll(), 200, `station ${n + 1}`);
    assert.deepEqual(await enroll(), [429, "too_many_stations"], "free stops at 64");
    assert.deepEqual(await enroll(false, lateEnroll), [429, "too_many_stations"], "a previously issued token does not bypass the cap");
    assert.deepEqual(await plans(), [["free", 1, 64, undefined]]);
    await aliceAdmin("POST", `/v1/admin/users/${bobTokens.subject}/may-create`, { on: true });
    assert.deepEqual(await enroll(), [429, "too_many_stations"], "standard stops at the same limit");
    assert.deepEqual(await enroll(true, lateJoin), [429, "too_many_stations"], "joining also stops at the limit");
    await aliceAdmin("POST", `/v1/admin/users/${bobTokens.subject}/may-create`, { on: false });
    assert.equal(((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations.length, 64, "existing stations stay when the plan changes");
    const namespace: any = await h.mf.getDurableObjectNamespace("DIRECTORY", "api");
    const directory = namespace.get(namespace.idFromName("primary")) as { previouslyEnrolledStation(workspace: string, station: string, by: string): Promise<void>; legacyStationLimit(workspace: string, limit: number): Promise<void> };
    const earlier = "f".repeat(64);
    await directory.previouslyEnrolledStation(w, earlier, bobTokens.subject);
    const retained = ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).stations;
    assert.equal(retained.length, 65, "stations already above the cap remain");
    assert.ok(retained.some((s: any) => s.id === earlier));
    assert.deepEqual(await enroll(), [429, "too_many_stations"]);
    assert.equal((await bob("DELETE", `/v1/workspaces/${w}/stations/${earlier}`)).status, 200);
    assert.deepEqual(await (await aliceAdmin("POST", `/v1/admin/workspaces/${w}/limits`, { members: 1, stations: 256 })).json(), { members: 1, stations: 64 });
    await directory.legacyStationLimit(w, 256);
    assert.deepEqual(await plans(), [["enterprise", 1, 64, undefined]], "an older custom cap does not change the shared limit");
    assert.deepEqual(await enroll(), [429, "too_many_stations"]);
  } finally {
    await h.close();
  }
});

test("those who created a workspace before the free plan keep creating, as the admin's say", async () => {
  const h = await harness();
  try {
    const aliceAdmin = h.as(await h.login("alice"), "admin");
    const bobTokens = await h.login("bob");
    const bob = h.as(bobTokens);
    assert.equal((await bob("POST", "/v1/workspaces", { name: "Old" })).status, 200);
    const directories: any = await h.mf.getDurableObjectNamespace("DIRECTORY", "api");
    const directory = directories.get(directories.idFromName("primary"));
    // As it was: let in by an invitation, then made one when making one was the right to make more; the object starts again.
    await directory.beforeFreePlan(bobTokens.subject, "invitation");
    const user = (((await (await aliceAdmin("GET", "/v1/admin/users")).json()) as any).users as any[]).find((u) => u.sub === bobTokens.subject);
    assert.deepEqual([user.admission, user.plan], ["granted", "standard"]);
    assert.equal((await bob("POST", "/v1/workspaces", { name: "New" })).status, 200);
  } finally {
    await h.close();
  }
});

test("the admin gives an account the right to create workspaces, or takes it back; blocks it; deletes a workspace", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const alice = h.as(aliceTokens);
    const aliceAdmin = h.as(aliceTokens, "admin");
    const bobTokens = await h.login("bob");
    const bob = h.as(bobTokens);
    const carol = h.as(await h.login("carol"));
    const userOf = async (email: string) => (((await (await aliceAdmin("GET", "/v1/admin/users")).json()) as any).users as any[]).find((u) => u.email === email);
    const bobSub = (await userOf("bob@example.test")).sub;
    const carolSub = (await userOf("carol@example.test")).sub;

    // Bob, on the free plan, makes his one and no more; put on the standard plan, he may, with no code; it shows in the list.
    assert.deepEqual([(await userOf("bob@example.test")).may_create, (await userOf("bob@example.test")).plan, (await userOf("bob@example.test")).admission], [false, "free", null]);
    const made = await (await bob("POST", "/v1/workspaces", { name: "Bob's" })).json() as any;
    assert.ok(made.id);
    assert.equal((await userOf("bob@example.test")).admission, "free");
    assert.equal((await bob("POST", "/v1/workspaces", { name: "Nope" })).status, 403);
    assert.deepEqual(await (await aliceAdmin("POST", `/v1/admin/users/${bobSub}/may-create`, { on: true })).json(), { sub: bobSub, may_create: true });
    assert.deepEqual([(await userOf("bob@example.test")).may_create, (await userOf("bob@example.test")).plan, (await userOf("bob@example.test")).admission], [true, "standard", "granted"]);
    assert.equal((await bob("POST", "/v1/workspaces", { name: "Second" })).status, 200);
    // Taken back, having made some does not keep it: he is on the free plan again.
    assert.equal(((await (await aliceAdmin("POST", `/v1/admin/users/${bobSub}/may-create`, { on: false })).json()) as any).may_create, false);
    assert.deepEqual([(await userOf("bob@example.test")).creator, (await userOf("bob@example.test")).admission], [false, "free"]);
    assert.equal((await bob("POST", "/v1/workspaces", { name: "Nope" })).status, 403);

    // Carol, given it and having it taken back before making any, is on the free plan.
    await aliceAdmin("POST", `/v1/admin/users/${carolSub}/may-create`, { on: true });
    assert.equal(((await (await aliceAdmin("POST", `/v1/admin/users/${carolSub}/may-create`, { on: false })).json()) as any).may_create, false);
    assert.equal((await userOf("carol@example.test")).admission, null);
    assert.equal((await carol("POST", "/v1/workspaces", { name: "Free" })).status, 200);
    assert.equal((await aliceAdmin("POST", "/v1/admin/users/nobody/may-create", { on: true })).status, 404);
    assert.equal((await aliceAdmin("POST", `/v1/admin/users/${carolSub}/may-create`, {})).status, 400);

    // Blocked, bob is signed out and the list says so; let back, he signs in again. The admin cannot block herself.
    assert.equal((await aliceAdmin("POST", `/v1/admin/users/${bobSub}/block`, { on: true })).status, 200);
    assert.equal((await bob("GET", "/v1/me")).status, 401);
    assert.equal((await userOf("bob@example.test")).blocked, true);
    assert.equal((await aliceAdmin("POST", `/v1/admin/users/${bobSub}/block`, { on: false })).status, 200);
    assert.equal((await userOf("bob@example.test")).blocked, false);
    assert.equal((await h.as(await h.login("bob"))("GET", "/v1/me")).status, 200);
    const aliceSub = (await userOf("alice@example.test")).sub;
    assert.equal((await aliceAdmin("POST", `/v1/admin/users/${aliceSub}/block`, { on: true })).status, 403);

    // The admin deletes bob's workspace; it is gone from his list and the console's.
    assert.equal((await aliceAdmin("POST", `/v1/admin/workspaces/${made.id}/delete`)).status, 200);
    const { workspaces } = await (await aliceAdmin("GET", "/v1/admin/workspaces")).json() as any;
    assert.ok(!workspaces.some((w: any) => w.id === made.id));
    assert.equal((await aliceAdmin("POST", `/v1/admin/workspaces/${made.id}/delete`)).status, 404);
    // Members carry when they last came, and each workspace how many it may hold.
    const home = await (await alice("POST", "/v1/workspaces", { name: "Home" })).json() as any;
    const listed = ((await (await aliceAdmin("GET", "/v1/admin/workspaces")).json()) as any).workspaces.find((w: any) => w.id === home.id);
    assert.ok(listed.members[0].last_seen > 0);
    assert.equal(listed.seats, 200, "the admin's own hold more");
    void bobTokens;
  } finally {
    await h.close();
  }
});

test("the admin gives an email the test channel and the standard plan before anyone signs in with it; the first to does", async () => {
  const h = await harness();
  try {
    const aliceAdmin = h.as(await h.login("alice"), "admin");
    const list = async () => (await (await aliceAdmin("GET", "/v1/admin/users")).json()) as any;

    // Dave has never signed in: his email is given both, in any case and with spaces; it is listed as pending, not as a user.
    const given = await aliceAdmin("POST", "/v1/admin/pending", { email: "  Dave@Example.test ", beta: true, may_create: true });
    assert.equal(given.status, 200);
    assert.deepEqual(await given.json(), { email: "dave@example.test", sub: null });
    // One not given stays as it was.
    await aliceAdmin("POST", "/v1/admin/pending", { email: "dave@example.test", beta: false });
    await aliceAdmin("POST", "/v1/admin/pending", { email: "dave@example.test", beta: true });
    assert.deepEqual((await list()).pending.map((p: any) => [p.email, p.beta, p.may_create]), [["dave@example.test", true, true]]);
    assert.equal((await list()).users.some((u: any) => u.email === "dave@example.test"), false);

    // He signs in: his account has both, and the email is no longer pending.
    const dave = h.as(await h.login("dave"));
    assert.equal(((await (await dave("GET", "/v1/me")).json()) as any).user.beta, true);
    const user = (await list()).users.find((u: any) => u.email === "dave@example.test");
    assert.deepEqual([user.beta, user.may_create, user.admission], [true, true, "granted"]);
    assert.deepEqual((await list()).pending, []);
    assert.equal((await dave("POST", "/v1/workspaces", { name: "Dave's" })).status, 200);
    assert.equal((await dave("POST", "/v1/workspaces", { name: "Second" })).status, 200);

    // An email someone has signed in with: theirs at once, and its account said.
    const bobTokens = await h.login("bob");
    assert.deepEqual(await (await aliceAdmin("POST", "/v1/admin/pending", { email: "bob@example.test", beta: true })).json(), { email: "bob@example.test", sub: bobTokens.subject });
    assert.equal(((await (await h.as(bobTokens)("GET", "/v1/me")).json()) as any).user.beta, true);
    assert.deepEqual((await list()).pending, []);

    // Taken back before anyone signs in: the account that does has none of it.
    await aliceAdmin("POST", "/v1/admin/pending", { email: "erin@example.test", beta: true });
    assert.equal((await aliceAdmin("POST", "/v1/admin/pending/remove", { email: "Erin@example.test" })).status, 200);
    assert.deepEqual((await list()).pending, []);
    assert.equal("beta" in ((await (await h.as(await h.login("erin"))("GET", "/v1/me")).json()) as any).user, false);

    assert.equal((await aliceAdmin("POST", "/v1/admin/pending", { email: "nope", beta: true })).status, 400);
    assert.equal((await aliceAdmin("POST", "/v1/admin/pending", { email: "x@example.test", beta: "yes" })).status, 400);
    // Only the admin, only on the console's host.
    assert.equal((await dave("POST", "/v1/admin/pending", { email: "x@example.test", beta: true })).status, 404);
  } finally {
    await h.close();
  }
});

test("an invite code made with the test channel lets whoever redeems it in too; one without does not", async () => {
  const h = await harness();
  try {
    const aliceAdmin = h.as(await h.login("alice"), "admin");
    const beta = await (await aliceAdmin("POST", "/v1/admin/invite-codes", { beta: true })).json() as any;
    const plain = await (await aliceAdmin("POST", "/v1/admin/invite-codes", {})).json() as any;
    assert.deepEqual([beta.beta, plain.beta], [true, false]);
    assert.equal((await aliceAdmin("POST", "/v1/admin/invite-codes", { beta: "yes" })).status, 400);

    const dave = h.as(await h.login("dave"));
    const erin = h.as(await h.login("erin"));
    const me = async (as: typeof dave) => ((await (await as("GET", "/v1/me")).json()) as any).user;
    assert.equal((await dave("POST", "/v1/workspaces", { name: "D", invite_code: beta.code })).status, 200);
    assert.equal((await erin("POST", "/v1/workspaces", { name: "E", invite_code: plain.code })).status, 200);
    assert.equal((await me(dave)).beta, true);
    assert.equal("beta" in (await me(erin)), false);
    const { codes } = await (await aliceAdmin("GET", "/v1/admin/invite-codes")).json() as any;
    assert.equal(codes.find((c: any) => c.code === beta.code).beta, true);
  } finally {
    await h.close();
  }
});

test("the admin makes a workspace for a company: its owners by email, limits of its own, stations put in without being in it", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const alice = h.as(aliceTokens);
    const aliceAdmin = h.as(aliceTokens, "admin");
    const bob = h.as(await h.login("bob"));
    const bobAdmin = h.as(await h.login("bob"), "admin");
    const listed = async (id: string) => ((await (await aliceAdmin("GET", "/v1/admin/workspaces")).json()) as any).workspaces.find((w: any) => w.id === id);
    const station = async () => {
      const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
      return { pair, id: hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer) };
    };
    const enroll = async (token: string) => {
      const { pair, id } = await station();
      const signature = hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(`stillfail-station-enroll-v1:${h.origin}:${token}:${id}`)));
      return h.fetch("/v1/stations/enroll", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token, station: id, signature, version: "0.3.1" }) });
    };

    // Only the admin, on the console's host; with a name, owners and whole limits.
    const acme = { name: "Acme", owners: ["Boss@example.test", " boss@example.test"], members: 3, stations: 1 };
    assert.equal((await bobAdmin("POST", "/v1/admin/workspaces", acme)).status, 404);
    assert.equal((await alice("POST", "/v1/admin/workspaces", acme)).status, 404);
    for (const wrong of [{ name: "" }, { owners: [] }, { owners: ["nobody"] }, { members: 0 }, { members: 1001 }, { members: "3" }, { stations: 257 }, { stations: 1.5 }, { owners: ["a@example.test", "b@example.test", "c@example.test", "d@example.test"] }]) {
      assert.ok([400, 429].includes((await aliceAdmin("POST", "/v1/admin/workspaces", { ...acme, ...wrong })).status), JSON.stringify(wrong));
    }
    const made = await (await aliceAdmin("POST", "/v1/admin/workspaces", acme)).json() as any;
    assert.deepEqual([made.joined, made.added], [[], ["boss@example.test"]], "the owner has not signed in yet");
    let w = await listed(made.id);
    assert.deepEqual([w.plan, w.seats, w.station_seats, w.members, w.added.map((a: any) => [a.email, a.role]), w.enrollable], ["enterprise", 3, 64, [], [["boss@example.test", "owner"]], true]);
    assert.equal(w.created_by.email, "alice@example.test");
    // The admin made it, but is not in it.
    assert.ok(!((await (await alice("GET", "/v1/me")).json()) as any).workspaces.some((x: any) => x.id === made.id));
    assert.equal((await alice("GET", `/v1/workspaces/${made.id}`)).status, 404);

    // Stations put in by the admin follow the same fixed limit, regardless of an older requested cap.
    assert.equal((await aliceAdmin("POST", "/v1/admin/workspaces/nope/enrollments", { name: "Mac mini" })).status, 404);
    // Not one that is not a company's: its owners put their stations in.
    const own = await (await bob("POST", "/v1/workspaces", { name: "Bob's" })).json() as any;
    assert.equal((await aliceAdmin("POST", `/v1/admin/workspaces/${own.id}/enrollments`, { name: "Mac mini" })).status, 409);
    assert.equal((await listed(own.id)).enrollable, false);
    assert.equal((await bobAdmin("POST", `/v1/admin/workspaces/${made.id}/enrollments`, { name: "Mac mini" })).status, 404);
    assert.equal((await aliceAdmin("POST", `/v1/admin/workspaces/${made.id}/enrollments`, { name: "" })).status, 400);
    const first = await (await aliceAdmin("POST", `/v1/admin/workspaces/${made.id}/enrollments`, { name: "Mac mini" })).json() as any;
    assert.equal(first.install, `curl -fsSL ${h.origin}/install.sh | sh -s -- ${first.token}`, "the stable channel's installer");
    assert.equal(first.command, `stillfail station enroll ${h.origin} ${first.token}`);
    assert.equal((await enroll(first.token)).status, 200);
    w = await listed(made.id);
    assert.deepEqual(w.stations.map((s: any) => s.name), ["Mac mini"]);
    for (const wrong of [{ members: 3 }, { members: 3, stations: 0 }]) assert.equal((await aliceAdmin("POST", `/v1/admin/workspaces/${made.id}/limits`, wrong)).status, 400);
    assert.equal((await aliceAdmin("POST", "/v1/admin/workspaces/nope/limits", { members: 3, stations: 2 })).status, 404);
    assert.deepEqual(await (await aliceAdmin("POST", `/v1/admin/workspaces/${made.id}/limits`, { members: 3, stations: 2 })).json(), { members: 3, stations: 64 });
    const second = await (await aliceAdmin("POST", `/v1/admin/workspaces/${made.id}/enrollments`, { name: "Second" })).json() as any;
    assert.equal((await enroll(second.token)).status, 200);

    // The owner signs in: an owner of it, who adds people up to its limit (the creator's plan has nothing to do with it).
    const boss = h.as(await h.login("boss"));
    const theirs = ((await (await boss("GET", "/v1/me")).json()) as any).workspaces.find((x: any) => x.id === made.id);
    assert.equal(theirs.role, "owner");
    // From now on its stations are theirs to put in, not the admin's.
    assert.equal((await aliceAdmin("POST", `/v1/admin/workspaces/${made.id}/limits`, { members: 3, stations: 3 })).status, 200);
    assert.equal((await aliceAdmin("POST", `/v1/admin/workspaces/${made.id}/enrollments`, { name: "Third" })).status, 409);
    assert.equal((await listed(made.id)).enrollable, false);
    assert.equal((await boss("POST", `/v1/workspaces/${made.id}/enrollments`, { name: "Third" })).status, 200);
    assert.equal((await boss("POST", `/v1/workspaces/${made.id}/members`, { role: "member", emails: ["bob@example.test", "carol@example.test"] })).status, 200);
    assert.equal((await boss("POST", `/v1/workspaces/${made.id}/members`, { role: "member", emails: ["dave@example.test"] })).status, 429);
    assert.ok(((await (await bob("GET", "/v1/me")).json()) as any).workspaces.some((x: any) => x.id === made.id));
    w = await listed(made.id);
    assert.deepEqual([w.members.length, w.added.map((a: any) => a.email)], [2, ["carol@example.test"]]);

    // One whose owner never signed in is deleted all the same.
    const other = await (await aliceAdmin("POST", "/v1/admin/workspaces", { name: "Other", owners: ["nobody-yet@example.test"], members: 5, stations: 1 })).json() as any;
    assert.equal((await aliceAdmin("POST", `/v1/admin/workspaces/${other.id}/delete`)).status, 200);
    assert.equal(await listed(other.id), undefined);
    // Signing in later, the email finds nothing waiting for it.
    const late = h.as(await h.login("nobody-yet"));
    assert.deepEqual(((await (await late("GET", "/v1/me")).json()) as any).workspaces, []);
  } finally {
    await h.close();
  }
});

test("workspaces the admin made for companies do not count against the admin's own", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const alice = h.as(aliceTokens);
    const aliceAdmin = h.as(aliceTokens, "admin");
    for (let i = 0; i < 32; i++) assert.equal((await aliceAdmin("POST", "/v1/admin/workspaces", { name: `Company ${i}`, owners: [`owner${i}@example.test`], members: 2, stations: 1 })).status, 200);
    assert.equal((await alice("POST", "/v1/workspaces", { name: "Mine" })).status, 200);
  } finally {
    await h.close();
  }
});

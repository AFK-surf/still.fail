// Deleting one's account (DELETE /v1/me; the privacy policy's right to it): the workspaces only it is in go, it leaves
// the others, its sessions end, and signing in again starts a new account. The only owner of a workspace others are in
// is refused until someone else owns it.
import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";

test("an account deletes itself, its own workspaces with it; the last owner of a shared one is refused", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const alice = h.as(aliceTokens);
    const operator = h.as(aliceTokens, "admin");
    const names = async () => (((await (await operator("GET", "/v1/admin/workspaces")).json()) as any).workspaces as any[]).map((w) => w.name).sort();
    const bob = h.as(await h.login("bob"));
    const home = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    await alice("POST", `/v1/workspaces/${home}/invitations`, { role: "member", email: "bob@example.test" });
    const invitation = ((await (await bob("GET", "/v1/me")).json()) as any).invitations[0];
    assert.equal((await bob("POST", `/v1/invitations/${invitation.id}/accept`)).status, 200);
    const solo = ((await (await bob("POST", "/v1/workspaces", { name: "Solo" })).json()) as any).id as string;
    await bob("POST", "/v1/feedback", { key: "k1", title: "broken", body: "it broke" });

    // alice is Home's only owner, and bob is in it.
    const refused = await alice("DELETE", "/v1/me");
    assert.equal(refused.status, 409);
    assert.equal(((await refused.json()) as any).error, "sole_owner");
    assert.equal((await alice("GET", "/v1/me")).status, 200, "and alice is still there");

    assert.deepEqual(await (await bob("DELETE", "/v1/me")).json(), { deleted: true });
    assert.equal((await bob("GET", "/v1/me")).status, 401, "bob's session ended");
    assert.deepEqual(await names(), ["Home"], `bob's own workspace (${solo}) went with him`);
    const members = ((await (await alice("GET", `/v1/workspaces/${home}`)).json()) as any).members as any[];
    assert.deepEqual(members.map((m) => m.email), ["alice@example.test"], "bob left Home");

    // Signing in again is a new account: no workspaces, nothing kept.
    const again = h.as(await h.login("bob"));
    const me = (await (await again("GET", "/v1/me")).json()) as any;
    assert.deepEqual(me.workspaces, []);
    assert.deepEqual(me.invitations, []);

    // Alone in Home now, alice may go, and Home with her.
    assert.equal((await alice("DELETE", "/v1/me")).status, 200);
    assert.equal((await again("GET", `/v1/workspaces/${home}`)).status, 404);
  } finally {
    await h.close();
  }
});

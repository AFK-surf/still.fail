// A picture an account puts up for itself (PUT /v1/me/picture): kept in the bucket as icons are (icons.ts), shown in
// the place of its sign-in's in `/v1/me` and its workspaces' members lists, left as it is by signing in again, taken
// away by DELETE (its sign-in's shown again). Who hears of it: events.test.ts.
import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";

/** What the harness's Google says is everyone's picture. */
const GOOGLE = "https://example.test/p.png";
const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, ...Array.from({ length: 2000 }, (_, i) => i & 255)]);
const picture = `data:image/jpeg;base64,${Buffer.from(jpeg).toString("base64")}`;

test("an account's own picture is shown in place of its sign-in's until it takes it away; signing in again keeps it", async () => {
  const h = await harness();
  try {
    const tokens = { alice: await h.login("alice"), bob: await h.login("bob") };
    const alice = h.as(tokens.alice), bob = h.as(tokens.bob);
    const me = async (who: typeof alice) => ((await (await who("GET", "/v1/me")).json()) as any).user;
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    await alice("POST", `/v1/workspaces/${w}/invitations`, { role: "member", email: "bob@example.test" });
    const invitation = ((await (await bob("GET", "/v1/me")).json()) as any).invitations[0].id;
    assert.equal((await bob("POST", `/v1/invitations/${invitation}/accept`)).status, 200);
    const alicesFace = async () => ((await (await bob("GET", `/v1/workspaces/${w}`)).json()) as any).members.find((m: any) => m.email === "alice@example.test").picture;

    // Before: its sign-in's, and no word of its own.
    assert.deepEqual([(await me(alice)).picture, "own_picture" in (await me(alice))], [GOOGLE, false]);

    // Put up: kept in the bucket, by its address; shown to it and to the members of its workspaces.
    const put = await alice("PUT", "/v1/me/picture", { picture });
    assert.equal(put.status, 200);
    const own = ((await put.json()) as any).picture as string;
    assert.match(own, new RegExp(`^${h.origin}/v1/icons/[0-9a-f]{32}\\.jpeg$`));
    const served = await h.fetch(own.slice(h.origin.length));
    assert.deepEqual([served.status, served.headers.get("content-type")], [200, "image/jpeg"]);
    assert.deepEqual(new Uint8Array(await served.arrayBuffer()), jpeg);
    assert.deepEqual([(await me(alice)).picture, (await me(alice)).own_picture], [own, true]);
    assert.equal(await alicesFace(), own);
    // Nobody else's changes.
    assert.deepEqual([(await me(bob)).picture, "own_picture" in (await me(bob))], [GOOGLE, false]);

    // Signing in again (Google says its picture as ever) leaves it.
    await h.login("alice");
    assert.deepEqual([(await me(alice)).picture, (await me(alice)).own_picture], [own, true]);
    assert.equal(await alicesFace(), own);

    // Its address may be given again; anything not a picture kept here, or not a picture, is refused, and changes nothing.
    assert.equal((await alice("PUT", "/v1/me/picture", { picture: own })).status, 200);
    for (const bad of ["data:image/svg+xml;base64,PHN2Zz4=", "data:image/png;base64,R0lGODlh", `data:image/jpeg;base64,/9j/${"A".repeat(1_500_000)}`, GOOGLE, "glyph:rocket", ""]) {
      assert.equal((await alice("PUT", "/v1/me/picture", { picture: bad })).status, 400, bad.slice(0, 30));
    }
    assert.equal((await alice("PUT", "/v1/me/picture", {})).status, 400, "none");
    assert.equal((await me(alice)).picture, own);
    assert.equal((await h.fetch("/v1/me/picture", { method: "PUT", headers: { "content-type": "application/json" }, body: JSON.stringify({ picture }) })).status, 401, "signed out");

    // Taken away: its sign-in's again, everywhere.
    const removed = await alice("DELETE", "/v1/me/picture");
    assert.equal(removed.status, 200);
    assert.equal(((await removed.json()) as any).picture, GOOGLE);
    assert.deepEqual([(await me(alice)).picture, "own_picture" in (await me(alice))], [GOOGLE, false]);
    assert.equal(await alicesFace(), GOOGLE);
  } finally {
    await h.close();
  }
});

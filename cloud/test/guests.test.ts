import assert from "node:assert/strict";
import test from "node:test";
import { harness, type OutboundRequest } from "./harness.ts";

// One cloud answering as the other product too (src/guests.ts): still.fail's accounts in monoid's cloud, still.fail's
// hosts forwarding to it.
const SECRET = "s".repeat(40);
const GUEST = "https://app.still.fail";
const GUEST_BETA = "https://app.youdid.wtf";
const guests = [{ origin: GUEST, beta: GUEST_BETA, google_client_id: "still-fail-google-client", google_client_secret: "still-fail-google-secret" }];
/** Headers as still.fail's Worker forwards a request made on `origin` from `ip`. */
const forwarded = (origin = GUEST, secret = SECRET, ip = "203.0.113.7") => ({ "x-stillfail-forwarded-origin": origin, "x-stillfail-forward-secret": secret, "x-stillfail-forwarded-for": ip });

test("a request a guest forwarded is answered as made on its origin; a wrong secret or an origin not listed is this cloud's own", async () => {
  const h = await harness({ origin: "https://app.monoid.build", guests, forwardSecret: SECRET });
  try {
    const script = async (headers: Record<string, string>) => (await h.fetch("/install.sh", { headers })).text();
    assert.match(await script(forwarded()), /app\.still\.fail/, "the guest's installer joins the guest's origin");
    assert.doesNotMatch(await script(forwarded()), /app\.monoid\.build/);
    assert.match(await script({}), /app\.monoid\.build/);
    assert.match(await script(forwarded(GUEST, "x".repeat(40))), /app\.monoid\.build/, "a wrong secret: as made here");
    assert.match(await script(forwarded("https://elsewhere.example")), /app\.monoid\.build/, "an origin not a guest's: as made here");
    // The test channel's host of the guest: its installer gives the test channel's release.
    assert.match(await script(forwarded(GUEST_BETA)), /STILLFAIL_CHANNEL:-beta/);
  } finally {
    await h.close();
  }
});

test("signing in on a guest's origin goes by its Google client and calls back there, and its tokens are good on this cloud's", async () => {
  const h = await harness({ origin: "https://app.monoid.build", guests, forwardSecret: SECRET });
  try {
    const start = new URLSearchParams({ state: "s".repeat(43), redirect_uri: "http://127.0.0.1:32145/oauth/callback", code_challenge: "c".repeat(43), code_challenge_method: "S256" });
    const asGuest = await h.fetch(`/v1/auth/google/start?${start}`, { redirect: "manual", headers: forwarded() });
    assert.equal(asGuest.status, 302, "no move to this cloud's own origin");
    const google = new URL(asGuest.headers.get("location")!);
    assert.equal(google.searchParams.get("client_id"), "still-fail-google-client");
    assert.equal(google.searchParams.get("redirect_uri"), `${GUEST}/v1/auth/google/callback`);
    const own = new URL((await h.fetch(`/v1/auth/google/start?${new URLSearchParams({ ...Object.fromEntries(start), state: "t".repeat(43) })}`, { redirect: "manual" })).headers.get("location")!);
    assert.equal(own.searchParams.get("client_id"), "test-google-client");
    assert.equal(own.searchParams.get("redirect_uri"), "https://app.monoid.build/v1/auth/google/callback");

    // A device's sign-in started on the guest's origin is finished on it.
    const device = await h.fetch("/v1/auth/device", { method: "POST", headers: { "content-type": "application/json", ...forwarded() }, body: JSON.stringify({ id: "d".repeat(43), code_challenge: "e".repeat(43), name: "a laptop" }) });
    assert.equal(((await device.json()) as { verification_uri: string }).verification_uri, `${GUEST}/v1/auth/device/${"d".repeat(43)}`);

    // Signed in here, the account's token is good with the guest's origin too (one cloud's accounts).
    const tokens = await h.login();
    const me = await h.fetch("/v1/me", { headers: { authorization: `Bearer ${tokens.access_token}`, ...forwarded() } });
    assert.equal(me.status, 200);
  } finally {
    await h.close();
  }
});

test("a cloud that moved forwards what reaches it, saying its origin and client, but keeps answering its releases", async () => {
  const got: OutboundRequest[] = [];
  const h = await harness({
    forwardTo: "https://app.monoid.build",
    forwardSecret: SECRET,
    push: (request) => {
      got.push(request);
      return { status: 200, body: JSON.stringify({ there: true }) };
    },
  });
  try {
    const answer = await h.fetch("/v1/me?x=1", { headers: { authorization: "Bearer abc", "cf-connecting-ip": "198.51.100.4" } });
    assert.deepEqual(await answer.json(), { there: true });
    assert.equal(got.length, 1);
    assert.equal(got[0]!.url, "https://app.monoid.build/v1/me?x=1");
    assert.equal(got[0]!.headers["x-stillfail-forwarded-origin"], h.origin);
    assert.equal(got[0]!.headers["x-stillfail-forward-secret"], SECRET);
    assert.equal(got[0]!.headers["x-stillfail-forwarded-for"], "198.51.100.4");
    assert.equal(got[0]!.headers.authorization, "Bearer abc");
    // Its releases are its own bucket's: asked here, not there.
    assert.equal((await h.fetch("/releases/android/latest.json")).status, 404);
    assert.equal(got.length, 1);
  } finally {
    await h.close();
  }
});

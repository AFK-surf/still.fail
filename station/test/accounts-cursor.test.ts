// A Cursor profile signed in to the person's Cursor account (accounts/cursor.ts): the browser login with no code, the key
// minted for the station without an end, the profile's check by Cursor's API, against a stand-in Cursor at a local
// address.
import assert from "node:assert/strict";
import { test } from "node:test";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { readCursor, type CursorUrls } from "../src/accounts/cursor.ts";
import { LoginManager, type LoginState } from "../src/accounts/login.ts";
import { accessKinds, checkProfile, URLS } from "../src/accounts/profiles.ts";
import { cursorKey } from "../src/agents/cursor.ts";
import { type Asked, provider, temp, upon } from "./accounts-fakes.ts";

/// Cursor: the login confirmed once `confirm` is called (its poll answers 404 until then), a key minted for its session
/// token, and the API that knows the keys minted.
async function cursor() {
  const s = { confirmed: false, keys: [] as string[], revoked: new Set<string>() };
  const basic = (a: Asked) => Buffer.from(String(a.headers.authorization ?? "").replace(/^Basic /, ""), "base64").toString().replace(/:$/, "");
  const p = await provider((a: Asked) => {
    if (a.url === "/backend/auth/poll") return s.confirmed ? { status: 200, body: { accessToken: "session-token", refreshToken: "refresh" } } : { status: 404, body: "Not found" };
    if (a.url === "/backend/aiserver.v1.DashboardService/CreateUserApiKey") {
      if (a.headers.authorization !== "Bearer session-token") return { status: 401, body: { code: "unauthenticated", message: "no session" } };
      const key = `crsr_${s.keys.length + 1}`;
      s.keys.push(key);
      return { status: 200, body: { apiKey: key } };
    }
    if (a.url === "/backend/aiserver.v1.DashboardService/GetMe") return { status: 200, body: { email: "cu@example.com" } };
    const key = basic(a);
    const known = s.keys.includes(key) && !s.revoked.has(key);
    if (a.url === "/api/v1/me") return known ? { status: 200, body: { apiKeyName: "still.fail · m1", userEmail: "cu@example.com", createdAt: "2026-10-20T00:00:00Z" } } : { status: 401, body: { code: "error", message: "Invalid User API Key" } };
    if (a.url === "/api/v1/models") return known ? { status: 200, body: { items: [{ id: "default", displayName: "Auto" }, { id: "composer-2.5", displayName: "Composer 2.5" }] } } : { status: 401, body: {} };
    return { status: 404, body: {} };
  });
  const urls: CursorUrls = { website: `${p.base}/site`, backend: `${p.base}/backend`, api: `${p.base}/api` };
  return { ...p, s, urls };
}

test("a Cursor sign-in has a page to confirm and no code, then the key minted for the station, without an end, kept in the home", async () => {
  const c = await cursor();
  const dir = temp("cursor-login");
  const logins = new LoginManager(dir, undefined, undefined, undefined, undefined, c.urls, () => "still.fail · m1");
  const wait = (state: LoginState) => upon((wake) => logins.changes(wake), () => (logins.get("cu")?.state === state ? logins.get("cu") : undefined), state);
  try {
    const home = join(dir, "homes", "cu");
    const started = await logins.startCursor({ id: "cu", home }, "zh");
    assert.equal(started.state, "needs_approval");
    assert.equal(started.userCode, null, "nothing to type: the page is confirmed");
    assert.equal(started.runtime, "cursor");
    const page = new URL(started.url!);
    assert.equal(`${page.origin}${page.pathname}`, `${c.base}/site/loginDeepControl`);
    assert.equal(page.searchParams.get("mode"), "login");
    // Still waiting while the page is not confirmed.
    while (!c.asked.some((a) => a.url === "/backend/auth/poll")) await new Promise((r) => setTimeout(r, 20));
    assert.equal(logins.get("cu")!.state, "needs_approval");
    c.s.confirmed = true;
    await wait("done");
    // The poll carried what redeems it (whose hash the page was given) in its body, never in its address.
    const poll = c.asked.find((a) => a.url === "/backend/auth/poll")!;
    assert.equal(poll.method, "POST");
    assert.equal(poll.body.uuid, page.searchParams.get("uuid"));
    assert.equal(createHash("sha256").update(poll.body.verifier).digest("base64url"), page.searchParams.get("challenge"));
    // The key minted for the station by its name, with no end; the session token dropped.
    const mint = c.asked.find((a) => a.url.endsWith("/CreateUserApiKey"))!;
    assert.deepEqual(mint.body, { name: "still.fail · m1" });
    const kept = readCursor(home)!;
    assert.deepEqual({ ...kept, createdAt: 0 }, { apiKey: "crsr_1", email: "cu@example.com", keyName: "still.fail · m1", createdAt: 0 });
    assert.equal(cursorKey(home), "crsr_1");

    // Cancelled while waiting: cancelled it stays, whatever Cursor says next.
    c.s.confirmed = false;
    await logins.startCursor({ id: "cu", home }, "zh");
    logins.cancel("cu");
    c.s.confirmed = true;
    assert.equal(logins.get("cu")!.state, "cancelled");
  } finally {
    await logins.close();
    await c.close();
  }
});

test("a Cursor profile is checked by its key: signed in with its models, asked to sign in again once the key is revoked", async () => {
  assert.deepEqual(accessKinds("cursor"), ["subscription", "env"]);
  const c = await cursor();
  const dir = temp("cursor-check");
  const logins = new LoginManager(dir, undefined, undefined, undefined, undefined, c.urls, () => "still.fail · m1");
  try {
    const home = join(dir, "homes", "cu");
    const urls = { ...URLS, cursor: c.urls };
    const check = () => checkProfile({ runtime: "cursor", kind: "subscription", key: "", via: {}, home, env: {}, machine: false, urls, lang: "en" });
    assert.equal((await check()).state, "login", "not signed in yet");
    await logins.startCursor({ id: "cu", home }, "en");
    c.s.confirmed = true;
    await upon((wake) => logins.changes(wake), () => (logins.get("cu")?.state === "done" ? true : undefined), "done");
    const ok = await check();
    assert.deepEqual([ok.state, ok.detail, ok.models], ["ok", "Signed in, cu@example.com", ["default", "composer-2.5"]]);
    c.s.revoked.add("crsr_1");
    const again = await check();
    assert.equal(again.state, "login");
  } finally {
    await logins.close();
    await c.close();
  }
});

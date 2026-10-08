import assert from "node:assert/strict";
import test from "node:test";
import { ulid } from "ulid";
import type { Tokens } from "../src/auth.ts";
import { harness } from "./harness.ts";

const REVIEW = JSON.stringify([{ email: "Review@Example.test", password: "correct horse battery", name: "App Review" }]);
const json = { "content-type": "application/json" };

test("a review account signs in with its password and gets a session like any other", { timeout: 20000 }, async () => {
  const h = await harness({ reviewAccounts: REVIEW });
  try {
    const signIn = (email: string, password: string) => h.fetch("/v1/auth/password", { method: "POST", headers: json, body: JSON.stringify({ email, password, name: "iPhone" }) });
    assert.equal((await signIn("review@example.test", "correct horse batter")).status, 401, "a wrong password");
    assert.equal((await signIn("someone@example.test", "correct horse battery")).status, 401, "an email not set up");
    const answer = await signIn(" review@EXAMPLE.test ", "correct horse battery");
    assert.equal(answer.status, 200);
    const tokens = (await answer.json()) as Tokens;
    assert.equal(tokens.email, "review@example.test");
    assert.equal(tokens.name, "App Review");
    assert.match(tokens.subject, /^pw-[A-Za-z0-9_-]{32}$/);
    const again = (await (await signIn("review@example.test", "correct horse battery")).json()) as Tokens;
    assert.equal(again.subject, tokens.subject, "the same account each time");
    const sessions = await h.fetch("/v1/auth/sessions", { headers: { authorization: "Bearer " + tokens.access_token } });
    assert.equal(((await sessions.json()) as { sessions: unknown[] }).sessions.length, 2);
    const refreshed = await h.fetch("/v1/auth/refresh", { method: "POST", headers: { ...json, authorization: "Bearer " + tokens.refresh_token }, body: JSON.stringify({ request_id: ulid() }) });
    assert.equal(refreshed.status, 200);
  } finally {
    await h.close();
  }
});

test("without review accounts nobody signs in with a password", { timeout: 20000 }, async () => {
  const h = await harness();
  try {
    const answer = await h.fetch("/v1/auth/password", { method: "POST", headers: json, body: JSON.stringify({ email: "review@example.test", password: "correct horse battery" }) });
    assert.equal(answer.status, 401);
    assert.equal((await h.fetch("/v1/auth/password", { method: "POST", headers: json, body: "{}" })).status, 400);
  } finally {
    await h.close();
  }
});

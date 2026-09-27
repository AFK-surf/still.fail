import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { claudeUsage, codexUsage } from "../src/quota.ts";

test("an account its provider refuses is blocked; a sign-in no longer good is not", async (t) => {
  let answer = new Response("{}");
  t.mock.method(globalThis, "fetch", async () => answer);
  answer = new Response(JSON.stringify({ error: { message: "This organization has been disabled." } }), { status: 403 });
  const blocked = await claudeUsage("t");
  assert.equal(blocked.state, "blocked");
  assert.match(blocked.detail!, /This organization has been disabled/);
  answer = new Response(JSON.stringify({ error: { message: "OAuth token has expired" } }), { status: 401 });
  assert.deepEqual([(await claudeUsage("t")).state, (await claudeUsage("t")).detail], ["unavailable", "登录过期或失效了"]);
  answer = new Response(JSON.stringify({ detail: "Your account has been deactivated" }), { status: 401 });
  assert.equal((await claudeUsage("t")).state, "blocked");
});

test("a Codex login's allowance is read with its auth.json's tokens", async (t) => {
  const file = join(mkdtempSync(join(tmpdir(), "ember-codex-")), "auth.json");
  writeFileSync(file, JSON.stringify({ tokens: { access_token: "at", account_id: "acc" } }));
  const asked: Headers[] = [];
  t.mock.method(globalThis, "fetch", async (_url: string, init: RequestInit) => {
    asked.push(new Headers(init.headers));
    return new Response(JSON.stringify({ rate_limit: {
      primary_window: { used_percent: 30, limit_window_seconds: 18_000, reset_at: 1_900_000_000 },
      secondary_window: { used_percent: 80, limit_window_seconds: 604_800, reset_at: 1_900_500_000 },
    } }));
  });
  const quota = await codexUsage(file);
  assert.deepEqual(quota?.windows, [
    { label: "5 小时", usedPercent: 30, resetsAt: 1_900_000_000_000 },
    { label: "每周", usedPercent: 80, resetsAt: 1_900_500_000_000 },
  ]);
  assert.equal(asked[0]!.get("authorization"), "Bearer at");
  assert.equal(asked[0]!.get("chatgpt-account-id"), "acc");
  // No file (the keychain keeps it): nothing to read.
  assert.equal(await codexUsage(join(tmpdir(), "none", "auth.json")), null);
});

// client/core/src/asks.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Accounts } from "../src/accounts.ts";
import { Asks, buddies, devCloud, linkTarget } from "../src/asks.ts";
import { parseAsk } from "../src/asks-parse.ts";
import { HostError } from "../src/error.ts";
import { holdLanguage } from "../src/i18n.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { run } from "./run.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

test("still_fail_links_open_in_the_app_and_others_do_not", () => {
  const cloud = "https://app.still.fail";
  assert.deepEqual(linkTarget("https://app.still.fail/invite#abc", cloud), { opens: "invite", token: "abc" });
  assert.equal(linkTarget("https://app.still.fail/invite", cloud), null);
  assert.deepEqual(linkTarget("https://ember.3720.org/w/ws1/s/st1/chats/k%3A1", cloud), { opens: "chat", workspace: "ws1", station: "st1", chat: "k:1" });
  assert.deepEqual(linkTarget("https://app.still.fail/o/ws1/st1/ds:C1:1.0?service=web", cloud), { opens: "item", workspace: "ws1", station: "st1", session: "ds:C1:1.0", service: "web" });
  assert.equal(linkTarget("https://app.still.fail/o/ws1/st1/k/", cloud).service, null);
  assert.deepEqual(linkTarget("https://app.still.fail/w/ws1/s/st1/adb", cloud), { opens: "adbShare", workspace: "ws1", station: "st1" });
  assert.equal(linkTarget("https://example.com/o/ws1/st1/k", cloud), null);
  assert.equal(linkTarget("https://app.still.fail:8443/o/ws1/st1/k", cloud), null);
  assert.equal(linkTarget("http://app.still.fail/o/ws1/st1/k", cloud), null);
  assert.equal(linkTarget("https://app.still.fail/o/ws1/st1", cloud), null);
  assert.equal(linkTarget("mailto:a@b.c", cloud), null);
  const dev = "http://10.0.2.2:8877";
  assert.equal(linkTarget("http://10.0.2.2:8877/o/w/s/k", dev).opens, "item");
  assert.equal(linkTarget("https://app.still.fail/o/w/s/k", dev), null);
  assert.ok(devCloud(dev) && devCloud("http://localhost:1") && !devCloud(cloud) && !devCloud("http://10.0.2.2"));
});

test("a_newer_app_is_asked_for_at_most_hourly_and_a_picture_once", async () => {
  const host = new FakeHost();
  host.onFetch((req) => {
    if (req.url === "https://stillfail.test/releases/android/latest.json") return jsonResponse(200, { versionCode: 1200, versionName: "0.1.1200", file: "android/stillfail-1200.apk", sha256: "ab", size: 9, extra: 1 });
    if (req.url === "https://p.test/a.png") return { status: 200, headers: [["content-type", "image/png"]], body: new Uint8Array([1, 2, 3]) };
    return jsonResponse(404, {});
  });
  const asks = new Asks(host);
  const asked = () => host.requests.filter((r) => r.url.endsWith("latest.json")).length;
  const newer = await run(asks.update("android", 1100, false, false));
  assert.deepEqual([newer.versionCode, newer.file, newer.extra], [1200, "android/stillfail-1200.apk", undefined]);
  assert.equal((await run(asks.update("android", 1100, false, false))).versionCode, 1200);
  assert.equal(await run(asks.update("android", 1200, false, false)), null);
  assert.equal(asked(), 1);
  await run(asks.update("android", 1100, true, false));
  assert.equal(asked(), 2);
  const [a, b] = await run(Effect.all([asks.picture("https://p.test/a.png"), asks.picture("https://p.test/a.png")], { concurrency: "unbounded" }));
  assert.deepEqual([a[0], [...a[1]]], ["image/png", [1, 2, 3]]);
  assert.deepEqual([...b[1]], [1, 2, 3]);
  await run(asks.picture("https://p.test/a.png"));
  assert.equal(host.requests.filter((r) => r.url === "https://p.test/a.png").length, 1);
  await assert.rejects(run(asks.picture("https://p.test/gone.png")));
  await assert.rejects(run(asks.picture("https://p.test/gone.png")));
  assert.equal(host.requests.filter((r) => r.url.endsWith("gone.png")).length, 2);
  await assert.rejects(run(asks.picture("file:///etc/passwd")));
});

test("an_explicit_update_gets_the_newest_build_or_fails_instead_of_using_the_cached_one", async () => {
  const host = new FakeHost();
  let served = 1200;
  host.onFetch(() => {
    if (served === 0) throw new HostError("offline");
    if (served === 1) return jsonResponse(503, {});
    if (served === 2) return jsonResponse(200, { invalid: true });
    return jsonResponse(200, { versionCode: served, versionName: `0.1.${served}`, file: `android/stillfail-${served}.apk`, sha256: "ab", size: 9 });
  });
  const asks = new Asks(host);
  assert.equal((await run(asks.update("android", 1100, false, false))).versionCode, 1200);
  served = 1300;
  assert.equal((await run(asks.update("android", 1100, false, false))).versionCode, 1200);
  const latest = await run(asks.update("android", 1100, true, false));
  assert.equal(latest.versionCode, 1300);
  assert.equal(latest.file, "android/stillfail-1300.apk");
  for (const failure of [0, 1, 2]) {
    served = failure;
    await assert.rejects(run(asks.update("android", 1100, true, false)));
  }
  served = 1100;
  assert.equal(await run(asks.update("android", 1100, true, false)), null);
});

test("a_beta_app_takes_its_builds_from_the_beta_feed", async () => {
  const release = (code: number) => ({ versionCode: code, versionName: `0.1.${code}`, file: `android/stillfail-${code}.apk`, sha256: "ab", size: 9 });
  const feeds = (req: { url: string }) =>
    req.url === "https://stillfail.test/releases/android/latest.json"
      ? jsonResponse(200, release(1200))
      : req.url === "https://stillfail.test/releases/android/beta/latest.json"
        ? jsonResponse(200, release(1250))
        : jsonResponse(404, {});
  let host = new FakeHost();
  host.onFetch(feeds);
  let asks = new Asks(host);
  let accounts = await run(Accounts.load(host));
  assert.equal(((await run(asks.run({ kind: "appUpdate", platform: "android", version: 1100, now: false }, accounts))) as J).versionCode, 1200);
  assert.ok(host.requests.every((r) => !r.url.includes("/beta/")));
  host = new FakeHost();
  host.isBeta = true;
  host.onFetch(feeds);
  asks = new Asks(host);
  accounts = await run(Accounts.load(host));
  const newer = (await run(asks.run({ kind: "appUpdate", platform: "android", version: 1100, now: false }, accounts))) as J;
  assert.deepEqual([newer.versionCode, newer.file], [1250, "android/stillfail-1250.apk"]);
  assert.equal(await run(asks.run({ kind: "appUpdate", platform: "android", version: 1250, now: true }, accounts)), null);
  assert.ok(host.requests.every((r) => r.url.endsWith("/android/beta/latest.json")));
  assert.equal(host.requests.length, 2);
});

test("the_calls_are_known_by_name", () => {
  assert.deepEqual(parseAsk("link.parse", { url: "https://x" }), { kind: "linkParse", url: "https://x" });
  assert.deepEqual(parseAsk("app.update", { platform: "android", versionCode: 3 }), { kind: "appUpdate", platform: "android", version: 3, now: false });
  assert.throws(() => parseAsk("app.update", { platform: "android" }));
  assert.deepEqual(parseAsk("buddies", {}), { kind: "buddies" });
  assert.equal(parseAsk("session.stop", {}), null);
});

test("the_buddies_are_the_web_s_list", () => {
  const all = buddies();
  assert.ok(Array.isArray(all) && all.length > 5);
  assert.ok(typeof all[0].id === "string" && typeof all[0].label === "string" && typeof all[0].bg === "string");
});

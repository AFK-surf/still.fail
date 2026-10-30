// The Rust core's asks.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
import { Accounts } from "../src/accounts.ts";
import { keyIdOf } from "../src/app-release.ts";
import { Asks, PICTURE_RETRY_MS, PICTURES_KEPT, buddies, devCloud, linkTarget } from "../src/asks.ts";
import { parseAsk } from "../src/asks-parse.ts";
import { setOwnApp, setTestChannel } from "../src/brand.ts";
import { HostError } from "../src/error.ts";
import { holdLanguage } from "../src/i18n.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { base64, toJsonBytes, utf8 } from "../src/util.ts";
import { run } from "./run.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
// A changelog that says nothing of any build.
const nothing = () => Effect.succeed([] as string[]);

test("still_fail_links_open_in_the_app_and_others_do_not", () => {
  const cloud = "https://app.still.fail";
  assert.deepEqual(linkTarget("https://app.still.fail/invite#abc", cloud), { opens: "invite", token: "abc" });
  assert.equal(linkTarget("https://app.still.fail/invite", cloud), null);
  assert.deepEqual(linkTarget("https://ember.3720.org/w/ws1/s/st1/chats/k%3A1", cloud), { opens: "chat", workspace: "ws1", station: "st1", chat: "k:1" });
  assert.deepEqual(linkTarget("https://app.still.fail/o/ws1/st1/ds:C1:1.0?service=web", cloud), { opens: "item", workspace: "ws1", station: "st1", session: "ds:C1:1.0", service: "web" });
  assert.deepEqual(linkTarget("https://app.youdid.wtf/w/ws1/s/st1/chats/k", cloud), { opens: "chat", workspace: "ws1", station: "st1", chat: "k" });
  assert.deepEqual(linkTarget("https://app.still.fail/o/ws1/st1/k", "https://app.youdid.wtf"), { opens: "item", workspace: "ws1", station: "st1", session: "k", service: null });
  assert.equal(linkTarget("https://app.still.fail/o/ws1/st1/k/", cloud).service, null);
  assert.deepEqual(linkTarget("https://app.still.fail/w/ws1/s/st1/adb", cloud), { opens: "adbShare", workspace: "ws1", station: "st1" });
  assert.deepEqual(linkTarget("https://app.still.fail/w/ws1/s/st1/login/l-3", cloud), { opens: "login", workspace: "ws1", station: "st1", login: "l-3" });
  assert.equal(linkTarget("https://app.still.fail/w/ws1/s/st1/login/", cloud), null);
  assert.deepEqual(linkTarget("https://app.still.fail/o/ws1/st1/k?history=k%3A2&entry=12", cloud), { opens: "item", workspace: "ws1", station: "st1", session: "k", service: null, history: "k:2", entry: 12 });
  assert.deepEqual(linkTarget("https://app.still.fail/w/ws1/s/st1/chats/c?history=k", cloud), { opens: "chat", workspace: "ws1", station: "st1", chat: "c", history: "k" });
  assert.deepEqual(linkTarget("?history=k&entry=3", cloud), { opens: "history", history: "k", entry: 3 });
  assert.deepEqual(linkTarget("?history=k&entry=x", cloud), { opens: "history", history: "k" });
  assert.equal(linkTarget("?service=web", cloud), null);
  assert.equal(linkTarget("https://example.com/o/ws1/st1/k", cloud), null);
  assert.equal(linkTarget("https://app.still.fail:8443/o/ws1/st1/k", cloud), null);
  assert.equal(linkTarget("http://app.still.fail/o/ws1/st1/k", cloud), null);
  assert.equal(linkTarget("https://app.still.fail/o/ws1/st1", cloud), null);
  assert.equal(linkTarget("mailto:a@b.c", cloud), null);
  // A path alone is the cloud's own, as the cards for such links take it.
  assert.deepEqual(linkTarget("/w/ws1/s/st1/adb", cloud), { opens: "adbShare", workspace: "ws1", station: "st1" });
  assert.deepEqual(linkTarget("/o/ws1/st1/k", cloud), { opens: "item", workspace: "ws1", station: "st1", session: "k", service: null });
  assert.equal(linkTarget("//example.com/o/ws1/st1/k", cloud), null);
  const dev = "http://10.0.2.2:8877";
  assert.equal(linkTarget("http://10.0.2.2:8877/o/w/s/k", dev).opens, "item");
  assert.equal(linkTarget("https://app.still.fail/o/w/s/k", dev), null);
  assert.ok(devCloud(dev) && devCloud("http://localhost:1") && !devCloud(cloud) && !devCloud("http://10.0.2.2"));
});

test("message links keep their exact destination and reject invalid sequence numbers", () => {
  const cloud = "https://app.still.fail";
  for (const path of ["/o/ws1/st1/ember%3Ac-1", "/w/ws1/s/st1/chats/c-1"]) {
    assert.equal(linkTarget(`${cloud}${path}?message=11`, cloud).message, 11);
    for (const value of ["0", "-1", "1.5", "x", "9007199254740992"]) {
      assert.equal(linkTarget(`${cloud}${path}?message=${value}`, cloud).message, undefined);
    }
  }
  assert.equal(linkTarget(`${cloud}/o/ws1/st1/ember%3Ac-1?message=11`, cloud).session, "ember:c-1");
});

test("a_newer_app_is_asked_for_at_most_hourly_and_a_picture_once", async () => {
  const host = new FakeHost();
  host.onFetch((req) => {
    if (req.url === "https://stillfail.test/releases/android/latest.json") return jsonResponse(200, { versionCode: 1200, versionName: "0.1.1200", file: "android/stillfail-1200.apk", sha256: "ab", size: 9, extra: 1 });
    if (req.url === "https://p.test/a.png") return { status: 200, headers: [["content-type", "image/png"]], body: new Uint8Array([1, 2, 3]) };
    return jsonResponse(404, {});
  });
  const asks = new Asks(host, nothing);
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
  // One that could not be fetched (a Google account's where Google cannot be reached) is not asked again a while.
  await assert.rejects(run(asks.picture("https://p.test/gone.png")));
  await assert.rejects(run(asks.picture("https://p.test/gone.png")));
  assert.equal(host.requests.filter((r) => r.url.endsWith("gone.png")).length, 1);
  host.advance(PICTURE_RETRY_MS);
  await assert.rejects(run(asks.picture("https://p.test/gone.png")));
  assert.equal(host.requests.filter((r) => r.url.endsWith("gone.png")).length, 2);
  await assert.rejects(run(asks.picture("file:///etc/passwd")));
});

test("a_picture_had_is_kept_on_the_device_and_answered_from_it_when_the_network_is_gone", async () => {
  const host = new FakeHost();
  let online = true;
  host.onFetch((req) => {
    if (!online) throw new HostError("offline");
    return { status: 200, headers: [["content-type", "image/png"]], body: new Uint8Array([req.url.length, 7]) };
  });
  const first = new Asks(host, nothing);
  await run(first.picture("https://p.test/a.png"));
  await run(first.picture("https://p.test/0.png"));
  // The app again, the network gone: the one had is there at once, never fetched again.
  online = false;
  const asks = new Asks(host, nothing);
  const [kind, bytes] = await run(asks.picture("https://p.test/a.png"));
  assert.deepEqual([kind, [...bytes]], ["image/png", [20, 7]]);
  assert.equal(host.requests.filter((r) => r.url === "https://p.test/a.png").length, 1);
  await assert.rejects(run(asks.picture("https://p.test/b.png")));
  // Past the bound the least lately had go: the one had again since stays.
  online = true;
  for (let i = 1; i < PICTURES_KEPT; i++) await run(asks.picture(`https://p.test/${i}.png`));
  online = false;
  const later = new Asks(host, nothing);
  await run(later.picture("https://p.test/a.png"));
  await assert.rejects(run(later.picture("https://p.test/0.png")));
  await run(later.picture(`https://p.test/${PICTURES_KEPT - 1}.png`));
  assert.equal([...host.storage.keys()].filter((k) => k.startsWith("picture-")).length, PICTURES_KEPT);
});

test("an_account_whose_picture_changed_shows_its_last_one_until_the_new_one_is_had", async () => {
  const host = new FakeHost();
  let reached = new Set(["https://g.test/old"]);
  host.onFetch((req) => {
    if (!reached.has(req.url)) throw new HostError("unreachable");
    return { status: 200, headers: [["content-type", "image/jpeg"]], body: new Uint8Array([req.url.endsWith("old") ? 1 : 2]) };
  });
  const account = { sub: "u1", email: "u@x.test", name: "U", picture: "https://g.test/old", access: "a", refresh: "r", access_expires: 9e9 };
  host.storage.set("accounts", toJsonBytes([account]));
  let accounts = await run(Accounts.load(host));
  let asks = new Asks(host, nothing);
  asks.follow(accounts);
  await run(asks.picture("https://g.test/old"));
  await run(accounts.profile("u1", { user: { name: "U", picture: "https://g.test/new" } }));
  assert.deepEqual([...(await run(asks.picture("https://g.test/new")))[1]], [1]);
  // Across the app's start too, and changed again before the new one was ever had.
  accounts = await run(Accounts.load(host));
  asks = new Asks(host, nothing);
  asks.follow(accounts);
  await run(accounts.profile("u1", { user: { picture: "https://g.test/newer" } }));
  assert.deepEqual([...(await run(asks.picture("https://g.test/newer")))[1]], [1]);
  // Once reached, the new one.
  reached = new Set(["https://g.test/newer"]);
  host.advance(PICTURE_RETRY_MS);
  assert.deepEqual([...(await run(new Asks(host, nothing).picture("https://g.test/newer")))[1]], [2]);
  // Nothing stands in for a picture no account had.
  await assert.rejects(run(new Asks(host, nothing).picture("https://g.test/other")));
});

test("a_newer_build_comes_with_what_it_brings_the_app", async () => {
  const host = new FakeHost();
  host.onFetch(() => jsonResponse(200, { versionCode: 1200, versionName: "0.1.1200", file: "android/stillfail-1200.apk", sha256: "ab", size: 9 }));
  const asked: [number, number][] = [];
  const asks = new Asks(host, (from, to) => Effect.sync(() => (asked.push([from, to]), from < 1150 ? ["修复：一件事"] : [])));
  assert.deepEqual((await run(asks.update("android", 1100, false, false))).news, ["修复：一件事"]);
  assert.deepEqual((await run(asks.update("android", 1150, false, false))).news, []);
  assert.equal(await run(asks.update("android", 1200, false, false)), null);
  assert.deepEqual(asked, [[1100, 1200], [1150, 1200]]);
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
  const asks = new Asks(host, nothing);
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

test("a_windows_build_is_offered_only_as_its_signed_words_say_it", async () => {
  // (taken where they verify: app-release.test.ts; one the feed says alone, or signed by another key, is not)
  const host = new FakeHost();
  let signed: J = undefined;
  host.onFetch((req) => {
    if (req.url !== "https://stillfail.test/releases/win/latest.json") return jsonResponse(404, {});
    return jsonResponse(200, { versionCode: 1200, versionName: "0.1.1200", file: "desktop/stillfail-0.1.1200-x64-win.exe", sha256: "ab", size: 9, signed });
  });
  const asks = new Asks(host, nothing);
  assert.equal(await run(asks.update("win", 1100, false, false)), null);
  await assert.rejects(run(asks.update("win", 1100, true, false)), /签名校验/);
  signed = { release: "e30=", signature: "AA==", key: "0000000000000000" };
  await assert.rejects(run(asks.update("win", 1100, true, false)), /签名校验/);
  assert.equal(await run(asks.update("android", 1100, true, false).pipe(Effect.orElseSucceed(() => null))), null);
});

test("a_windows_build_signed_by_a_key_the_app_adds_is_offered_and_parsed_from_the_ask", async () => {
  // (the app's environment's STILLFAIL_RELEASE_KEYS, as the station's and the desktop app's: a test's own releases)
  const secret = ed25519.utils.randomSecretKey();
  const key = base64(ed25519.getPublicKey(secret));
  const sha = "a".repeat(64);
  const words = utf8(JSON.stringify({ kind: "stillfail-desktop-win", version: "0.1.1200", build: 1200, file: "stillfail-0.1.1200-x64-win.exe", sha256: sha, size: 9 }));
  const signed = { release: base64(words), signature: base64(ed25519.sign(words, secret)), key: keyIdOf(ed25519.getPublicKey(secret)) };
  const host = new FakeHost();
  host.onFetch((req) =>
    req.url === "https://stillfail.test/releases/win/latest.json"
      ? jsonResponse(200, { versionCode: 1200, versionName: "0.1.1200", file: "desktop/stillfail-0.1.1200-x64-win.exe", sha256: sha, size: 9, signed })
      : jsonResponse(404, {}),
  );
  await assert.rejects(run(new Asks(host, nothing).update("win", 1100, true, false)), /签名校验/);
  const ask = parseAsk("app.update", { platform: "win", versionCode: 1100, now: true, keys: [key, 3, ""] });
  assert.deepEqual(ask, { kind: "appUpdate", platform: "win", version: 1100, now: true, keys: [key] });
  const accounts = await run(Accounts.load(host));
  assert.equal(((await run(new Asks(host, nothing).run(ask!, accounts))) as J).versionCode, 1200);
  assert.deepEqual(parseAsk("app.update", { platform: "win", versionCode: 1100 }), { kind: "appUpdate", platform: "win", version: 1100, now: false, keys: [] });
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
  let asks = new Asks(host, nothing);
  let accounts = await run(Accounts.load(host));
  assert.equal(((await run(asks.run({ kind: "appUpdate", platform: "android", version: 1100, now: false, keys: [] }, accounts))) as J).versionCode, 1200);
  assert.ok(host.requests.every((r) => !r.url.includes("/beta/")));
  // (youdid.wtf: still.fail's own app on the test channel, as the core says it from its host at the start)
  setTestChannel(true);
  host = new FakeHost();
  host.isBeta = true;
  host.onFetch(feeds);
  asks = new Asks(host, nothing);
  accounts = await run(Accounts.load(host));
  const newer = (await run(asks.run({ kind: "appUpdate", platform: "android", version: 1100, now: false, keys: [] }, accounts))) as J;
  assert.deepEqual([newer.versionCode, newer.file], [1250, "android/stillfail-1250.apk"]);
  assert.equal(await run(asks.run({ kind: "appUpdate", platform: "android", version: 1250, now: true, keys: [] }, accounts)), null);
  assert.ok(host.requests.every((r) => r.url.endsWith("/android/beta/latest.json")));
  assert.equal(host.requests.length, 2);
  // An app of its own on the test channel (still.fail mbui): its feed as it names it.
  setOwnApp(false);
  host = new FakeHost();
  host.isBeta = true;
  host.onFetch((req) => (req.url === "https://stillfail.test/releases/android/mbui/latest.json" ? jsonResponse(200, { ...release(1260), file: "android/mbui/stillfail-1260.apk" }) : jsonResponse(404, {})));
  asks = new Asks(host, nothing);
  accounts = await run(Accounts.load(host));
  assert.equal(((await run(asks.run({ kind: "appUpdate", platform: "android/mbui", version: 1100, now: false, keys: [] }, accounts))) as J).versionCode, 1260);
  assert.ok(host.requests.every((r) => r.url.endsWith("/android/mbui/latest.json")));
  setOwnApp(true);
  setTestChannel(false);
});

test("the_calls_are_known_by_name", () => {
  assert.deepEqual(parseAsk("link.parse", { url: "https://x" }), { kind: "linkParse", url: "https://x" });
  assert.deepEqual(parseAsk("app.update", { platform: "android", versionCode: 3 }), { kind: "appUpdate", platform: "android", version: 3, now: false, keys: [] });
  assert.throws(() => parseAsk("app.update", { platform: "android" }));
  assert.deepEqual(parseAsk("buddies", {}), { kind: "buddies" });
  assert.equal(parseAsk("session.stop", {}), null);
});

test("the_buddies_are_the_web_s_list", () => {
  const all = buddies();
  assert.ok(Array.isArray(all) && all.length > 5);
  assert.ok(typeof all[0].id === "string" && typeof all[0].label === "string" && typeof all[0].bg === "string");
});

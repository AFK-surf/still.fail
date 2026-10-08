// The Rust core's accounts.rs tests, ported.
import { Effect } from "effect";
import { run } from "./run.ts";
import assert from "node:assert/strict";
import { test } from "node:test";
import { Accounts, LOGIN_KEY, STORAGE_KEY, challenge, decodeComponent, encodeComponent, parseQuery, view, type StoredAccount } from "../src/accounts.ts";
import { HostError } from "../src/error.ts";
import { holdLanguage } from "../src/i18n.ts";
import { Runner } from "../src/runtime.ts";
import { FakeHost, flush, jsonResponse } from "../src/testing.ts";
import { Tracer } from "../src/trace.ts";
import { parseJson } from "../src/util.ts";
import type { HttpRequest } from "../src/host.ts";

holdLanguage();

const tokens = (access: string, refresh: string, expires_at: number) => ({ access_token: access, refresh_token: refresh, subject: "sub1", email: "a@x.com", name: "阿一", expires_at });
/// The core's time (its host's clock), in seconds: what a stored credential's expiry is counted from.
const now = (host: FakeHost) => host.nowMs() / 1000;
const account = (sub: string, access_expires: number): StoredAccount => ({ sub, email: `${sub}@x.com`, name: "旧名", picture: "p.png", access: "old-access", refresh: "old-refresh", access_expires });
const body = (r: HttpRequest) => parseJson(r.body!) as Record<string, unknown>;
const header = (r: HttpRequest, name: string) => r.headers.find(([k]) => k === name)?.[1];
async function withStored(host: FakeHost, list: StoredAccount[]) {
  host.store(STORAGE_KEY, list);
  return run(Accounts.load(host));
}
const queryOf = (url: string) => Object.fromEntries(parseQuery(url.split("?")[1]));
const stored = (host: FakeHost, key: string) => parseJson(host.stored(key)) as never;

test("pkce_challenge_is_base64url_sha256", () => {
  assert.equal(challenge("abc"), "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0");
});

test("query_encoding_round_trips", () => {
  const text = "still.fail 网页版 · Chrome & co=1/2+3%";
  const encoded = encodeComponent(text);
  assert.ok(/^[A-Za-z0-9\-_.~%]*$/.test(encoded));
  assert.equal(decodeComponent(encoded), text);
  assert.deepEqual(parseQuery("?a=1+2&b=%E4%BD%A0&c"), [["a", "1 2"], ["b", "你"], ["c", ""]]);
});

test("begin_sign_in_stores_pkce_and_builds_url", async () => {
  const host = new FakeHost();
  const accounts = await run(Accounts.load(host));
  const url = await run(accounts.beginSignIn("https://stillfail.test/auth/callback", "/w/ws1", "still.fail 网页版 · Chrome"));
  assert.ok(url.startsWith("https://stillfail.test/v1/auth/google/start?state="));
  const pending = stored(host, LOGIN_KEY) as { verifier: string; state: string; return_to: string };
  assert.equal(pending.verifier.length, 43);
  assert.notEqual(pending.verifier, pending.state);
  assert.equal(pending.return_to, "/w/ws1");
  const q = queryOf(url);
  assert.equal(q.state, pending.state);
  assert.equal(q.code_challenge, challenge(pending.verifier));
  assert.equal(q.code_challenge_method, "S256");
  assert.equal(q.redirect_uri, "https://stillfail.test/auth/callback");
  assert.equal(q.name, "still.fail 网页版 · Chrome");
});

test("password_sign_in_keeps_the_account_or_says_the_password_is_wrong", async () => {
  const host = new FakeHost();
  const expires = now(host) + 3600;
  host.onFetch((req) => {
    if (req.url === "https://stillfail.test/v1/auth/password") return body(req).password === "right" ? jsonResponse(200, tokens("acc", "ref", expires)) : jsonResponse(401, { error: "invalid_credentials" });
    if (req.url === "https://stillfail.test/v1/me") return jsonResponse(200, { user: {} });
    throw new Error(`unexpected ${req.url}`);
  });
  const accounts = await run(Accounts.load(host));
  const wrong = await Effect.runPromise(Effect.flip(accounts.passwordSignIn("a@x.com", "wrong", "iPhone")));
  assert.equal(wrong.code, "login_wrong_password");
  assert.deepEqual(accounts.list(), []);
  const v = await run(accounts.passwordSignIn("a@x.com", "right", "iPhone"));
  assert.deepEqual(v, { sub: "sub1", email: "a@x.com", name: "阿一", picture: "" });
  assert.deepEqual(body(host.requests[1]), { email: "a@x.com", password: "right", name: "iPhone" });
  assert.deepEqual(accounts.list(), [v]);
  assert.equal((stored(host, STORAGE_KEY) as StoredAccount[])[0].refresh, "ref");
});

test("sign_in_happy_path", async () => {
  const host = new FakeHost();
  const expires = now(host) + 3600;
  host.onFetch((req) => {
    if (req.url === "https://stillfail.test/v1/auth/token") return jsonResponse(200, tokens("acc", "ref", expires));
    if (req.url === "https://stillfail.test/v1/me") return jsonResponse(200, { user: { picture: "https://pic/1" } });
    throw new Error(`unexpected ${req.url}`);
  });
  const accounts = await run(Accounts.load(host));
  let changes = 0;
  accounts.onChange(() => changes++);
  const url = await run(accounts.beginSignIn("https://stillfail.test/auth/callback", "/w/ws1", "dev"));
  const state = queryOf(url).state;
  const pending = stored(host, LOGIN_KEY) as { verifier: string };
  const [v, returnTo] = await run(accounts.completeSignIn(`?code=id.secret&state=${state}`));
  assert.deepEqual(v, { sub: "sub1", email: "a@x.com", name: "阿一", picture: "https://pic/1" });
  assert.equal(returnTo, "/w/ws1");
  assert.equal(host.stored(LOGIN_KEY), undefined);
  assert.ok(changes >= 1);
  assert.equal(host.requests[0].method, "POST");
  assert.deepEqual(body(host.requests[0]), { code: "id.secret", code_verifier: pending.verifier, redirect_uri: "https://stillfail.test/auth/callback" });
  assert.equal(header(host.requests[1], "authorization"), "Bearer acc");
  const list = stored(host, STORAGE_KEY) as StoredAccount[];
  assert.equal(list.length, 1);
  assert.equal(list[0].refresh, "ref");
  assert.equal(await run(accounts.accessToken("sub1")), "acc");
  assert.equal(host.requests.length, 2);
});

test("sign_in_survives_a_failed_profile_and_sanitises_return_to", async () => {
  for (const [returnTo, expected] of [["/auth/callback", "/"], ["", "/"]]) {
    const host = new FakeHost();
    const expires = now(host) + 3600;
    host.onFetch((req) => {
      if (req.url.endsWith("/v1/me")) throw new HostError("offline");
      return jsonResponse(200, tokens("acc", "ref", expires));
    });
    const accounts = await run(Accounts.load(host));
    const url = await run(accounts.beginSignIn("https://stillfail.test/auth/callback", returnTo, "dev"));
    const [v, to] = await run(accounts.completeSignIn(`code=c&state=${queryOf(url).state}`));
    assert.equal(v.picture, "");
    assert.equal(to, expected);
  }
});

test("sign_in_failures", async () => {
  const host = new FakeHost();
  host.onFetch(() => jsonResponse(400, { error: "invalid_grant" }));
  const accounts = await run(Accounts.load(host));
  const begin = () => run(accounts.beginSignIn("https://stillfail.test/auth/callback", "/", "dev"));
  const fails = async (p: Promise<unknown>) => {
    try {
      await p;
    } catch (e) {
      return e as { message: string; status?: number };
    }
    throw new Error("succeeded");
  };
  await begin();
  assert.equal((await fails(run(accounts.completeSignIn("error=login_cancelled")))).message, "登录已取消");
  assert.equal(host.stored(LOGIN_KEY), undefined, "a failed login is not retried");
  await begin();
  assert.equal((await fails(run(accounts.completeSignIn("error=access_denied")))).message, "Google 登录没有成功");
  await begin();
  assert.equal((await fails(run(accounts.completeSignIn("code=c&state=wrong")))).message, "登录状态不匹配，请重新登录");
  assert.equal((await fails(run(accounts.completeSignIn("code=c&state=wrong")))).message, "登录状态不匹配，请重新登录");
  const state = queryOf(await begin()).state;
  const e = await fails(run(accounts.completeSignIn(`code=c&state=${state}`)));
  assert.equal(e.message, "登录凭证已失效，请重新登录");
  assert.equal(e.status, 400);
  assert.deepEqual(accounts.list(), []);
});

test("refresh_is_single_flight", async () => {
  const host = new FakeHost();
  let refreshes = 0;
  const expires = now(host) + 3600;
  host.onFetch(async (req) => {
    assert.ok(req.url.endsWith("/v1/auth/refresh"));
    refreshes++;
    // Slow: the second caller comes while the first waits.
    await flush(3);
    return jsonResponse(200, { access_token: "new-access", refresh_token: "new-refresh", subject: "s", email: "s@x.com", expires_at: expires });
  });
  host.store(STORAGE_KEY, [account("s", now(host) + 30)]);
  const accounts = await run(Accounts.load(host));
  const [a, b] = await Promise.all([run(accounts.accessToken("s")), run(accounts.accessToken("s"))]);
  assert.equal(a, "new-access");
  assert.equal(b, "new-access");
  assert.equal(refreshes, 1);
  assert.equal(accounts.refreshing(), 0);
  const request = host.requests[0];
  assert.equal(header(request, "authorization"), "Bearer old-refresh");
  const id = body(request).request_id as string;
  assert.equal(id.length, 26);
  assert.ok([...id].every((c) => "0123456789ABCDEFGHJKMNPQRSTVWXYZ".includes(c)));
  const list = stored(host, STORAGE_KEY) as StoredAccount[];
  assert.deepEqual([list[0].refresh, list[0].name], ["new-refresh", "旧名"]);
  assert.equal(await run(accounts.accessToken("s")), "new-access");
  assert.equal(refreshes, 1);
});

test("another_core_on_the_same_storage_refreshed_first_so_its_credentials_are_taken", async () => {
  const host = new FakeHost();
  host.onFetch((req) => {
    throw new Error(`no refresh expected, got ${req.url}`);
  });
  host.store(STORAGE_KEY, [account("s", now(host) + 30)]);
  const accounts = await run(Accounts.load(host));
  const theirs = { ...account("s", 0), access: "their-access", refresh: "their-refresh", access_expires: now(host) + 3600 };
  host.store(STORAGE_KEY, [theirs]);
  assert.equal(await run(accounts.accessToken("s")), "their-access");
  assert.equal(accounts.stored("s")!.refresh, "their-refresh");
});

test("refused_refresh_forgets_the_account", async () => {
  const host = new FakeHost();
  host.onFetch(() => jsonResponse(401, { error: "invalid_session" }));
  const accounts = await withStored(host, [account("s", 0), account("t", now(host) + 3600)]);
  await assert.rejects(run(accounts.accessToken("s")), (e: { code: string; message: string }) => e.code === "signed_out" && e.message === "s@x.com 的登录已过期，请重新登录");
  assert.deepEqual(accounts.list().map((a) => a.sub), ["t"]);
  assert.equal((stored(host, STORAGE_KEY) as StoredAccount[]).length, 1);
  await assert.rejects(run(accounts.accessToken("s")), (e: { message: string }) => e.message === "这个账号已退出");
});

test("refreshes_are_traced_with_why_they_failed", async () => {
  const host = new FakeHost();
  let calls = 0;
  const parents: string[] = [];
  host.onFetch((req) => {
    parents.push(header(req, "traceparent") ?? "");
    calls++;
    if (calls === 1) throw new HostError("offline");
    return jsonResponse(401, { error: "refresh_reused" });
  });
  const accounts = await withStored(host, [account("s", 0)]);
  const tracer = new Tracer(host, new Runner(host.time.clock), 0);
  const bodies: unknown[] = [];
  tracer.setExport((b) => Effect.sync(() => void bodies.push(parseJson(b))));
  accounts.setTracer(tracer);
  await assert.rejects(run(accounts.accessToken("s")));
  await assert.rejects(run(accounts.accessToken("s")), (e: { code: string }) => e.code === "signed_out");
  tracer.flush();
  await flush();
  assert.equal(parents.length, 2);
  assert.ok(parents.every((p) => p.startsWith("00-") && p.endsWith("-01")));
  const spans = bodies.flatMap((b) => (b as { resourceSpans: { scopeSpans: { spans: Record<string, unknown>[] }[] }[] }).resourceSpans[0].scopeSpans[0].spans);
  assert.equal(spans.length, 2);
  const attribute = (span: Record<string, unknown>, key: string) => (span.attributes as { key: string; value: Record<string, unknown> }[]).find((a) => a.key === key)?.value;
  assert.ok(spans.every((s) => s.name === "auth.refresh" && (s.status as { code: number }).code === 2));
  assert.ok(attribute(spans[0], "error.type") !== undefined);
  assert.equal(attribute(spans[0], "stillfail.auth.unanswered_ago_ms"), undefined);
  assert.equal(attribute(spans[1], "error.type")!.stringValue, "refresh_reused");
  assert.ok(attribute(spans[1], "stillfail.auth.unanswered_ago_ms") !== undefined);
});

test("failed_refresh_keeps_the_account", async () => {
  const host = new FakeHost();
  host.onFetch(() => jsonResponse(503, {}));
  const accounts = await withStored(host, [account("s", 0)]);
  await assert.rejects(run(accounts.accessToken("s")), (e: { message: string }) => e.message === "刷新登录失败（503）");
  assert.equal(accounts.list().length, 1);
  assert.equal(accounts.refreshing(), 0);
});

test("persistence_round_trips", async () => {
  const host = new FakeHost();
  const list = [account("s", now(host) + 3600), account("t", now(host) + 3600)];
  const accounts = await withStored(host, list);
  assert.deepEqual(accounts.list(), list.map(view));
  await run(accounts.signOut("s")).catch(() => undefined);
  const again = await run(Accounts.load(host));
  assert.deepEqual(again.list(), [view(list[1])]);
  assert.equal(await run(again.accessToken("t")), "old-access");
});

test("sign_out_posts_logout_and_forgets_even_offline", async () => {
  const host = new FakeHost();
  host.onFetch(() => {
    throw new HostError("offline");
  });
  const accounts = await withStored(host, [account("s", now(host) + 3600)]);
  let changes = 0;
  accounts.onChange(() => changes++);
  await run(accounts.signOut("s"));
  assert.deepEqual(accounts.list(), []);
  assert.equal(changes, 1);
  const request = host.requests[0];
  assert.equal(request.url, "https://stillfail.test/v1/auth/logout");
  assert.equal(header(request, "authorization"), "Bearer old-refresh");
  assert.deepEqual(body(request), { all: false });
});

test("migrate_merges_the_old_list", async () => {
  const host = new FakeHost();
  const accounts = await withStored(host, [account("s", 2000)]);
  const old = [
    { sub: "s", email: "s@x.com", name: "", picture: "", access: "stale", refresh: "stale", accessExpires: 1000 },
    { sub: "u", email: "u@x.com", name: "乌", picture: "", access: "ua", refresh: "ur", accessExpires: 3000 },
    { nonsense: true },
  ];
  await run(accounts.migrate(JSON.stringify(old)));
  const again = await run(Accounts.load(host));
  const list = [again.stored("s")!, again.stored("u")!];
  assert.equal(again.list().length, 2);
  assert.equal(list[0].access, "old-access", "the newer session here wins");
  assert.deepEqual([list[1].sub, list[1].refresh, list[1].access_expires], ["u", "ur", 3000]);
  await run(accounts.migrate([{ sub: "s", email: "s@x.com", access: "fresh", refresh: "fresh", accessExpires: 5000 }]));
  assert.equal(accounts.stored("s")!.refresh, "fresh");
  await assert.rejects(run(accounts.migrate({ sub: "s" })));
});

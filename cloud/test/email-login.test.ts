import assert from "node:assert/strict";
import test from "node:test";
import { digest, randomSecret, type Tokens } from "../src/auth.ts";
import { harness } from "./harness.ts";

type H = Awaited<ReturnType<typeof harness>>;
type Answer = Awaited<ReturnType<H["fetch"]>>;

/** A browser signing in on the cloud's page: from an address of its own (the login rate limit is per address), with the attempt's cookie. */
async function browser(h: H, address: string, callback = "http://127.0.0.1:32145/oauth/callback") {
  const verifier = randomSecret(),
    state = randomSecret();
  const query = new URLSearchParams({ state, redirect_uri: callback, code_challenge: await digest(verifier), code_challenge_method: "S256", name: "Pixel" });
  const start = await h.fetch("/v1/auth/google/start?" + query, { redirect: "manual", headers: { "cf-connecting-ip": address } });
  assert.equal(start.status, 200, "the page that asks how");
  const page = await start.text();
  const id = /action="\/v1\/auth\/login\/([A-Za-z0-9_-]{43})"/.exec(page)![1]!;
  const cookie = start.headers.get("set-cookie")!.split(";")[0]!;
  const csrf = cookie.split("=")[1]!;
  /** Sends a form of the page, as the browser does: `fields` with the csrf, its cookie, the page's origin. */
  const post = (fields: Record<string, string>, more: { cookie?: string; origin?: string; csrf?: string } = {}) =>
    h.fetch(`/v1/auth/login/${id}`, {
      method: "POST",
      redirect: "manual",
      headers: { "content-type": "application/x-www-form-urlencoded", origin: more.origin ?? h.origin, cookie: more.cookie ?? cookie, "cf-connecting-ip": address },
      body: new URLSearchParams({ csrf: more.csrf ?? csrf, ...fields }).toString(),
    });
  /** The code given back to the client's callback traded for its tokens. */
  const exchange = async (finished: Answer) => {
    assert.equal(finished.status, 302);
    const location = new URL(finished.headers.get("location")!);
    assert.equal(finished.headers.get("location")!.split("?")[0], callback);
    assert.equal(location.searchParams.get("state"), state);
    const answer = await h.fetch("/v1/auth/token", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ code: location.searchParams.get("code"), code_verifier: verifier, redirect_uri: callback }) });
    assert.equal(answer.status, 200);
    return (await answer.json()) as Tokens;
  };
  return { page, post, exchange };
}

/** The code in the last mail sent to `to`. */
function codeFor(h: H, to: string): string {
  const mail = h.mails.filter((m) => m.to === to).at(-1);
  assert.ok(mail, `a mail to ${to}`);
  return /\b(\d{6})\b/.exec(mail.text)![1]!;
}

/** A sign-in with an email from start to tokens. */
async function emailLogin(h: H, address: string, email: string): Promise<Tokens> {
  const b = await browser(h, address);
  assert.equal((await b.post({ via: "email", email })).status, 200);
  return b.exchange(await b.post({ via: "code", code: codeFor(h, email.trim().toLowerCase()) }));
}

/** A sign-in with Google, chosen on the page, as `sub` (whose email is sub@example.test: harness.ts). */
async function googleLogin(h: H, address: string, sub: string): Promise<Tokens> {
  const b = await browser(h, address);
  const gone = await b.post({ via: "google" });
  assert.equal(gone.status, 302);
  const google = new URL(gone.headers.get("location")!);
  assert.equal(google.origin, "https://accounts.google.com");
  const code = randomSecret();
  h.codes.set(code, { nonce: google.searchParams.get("nonce")!, challenge: google.searchParams.get("code_challenge")!, sub });
  const callback = await h.fetch("/v1/auth/google/callback?" + new URLSearchParams({ state: google.searchParams.get("state")!, code }), { headers: { cookie: gone.headers.get("set-cookie")!.split(";")[0]! }, redirect: "manual" });
  return b.exchange(callback);
}

test("an email signs up with a code sent to it, and signs in to the same account again", { timeout: 30000 }, async () => {
  const h = await harness({ mail: true });
  try {
    const b = await browser(h, "10.1.0.1");
    assert.match(b.page, /name="via" value="google"/, "Google is still there");
    assert.match(b.page, /type="email"/);
    assert.match(b.page, /href="https:\/\/still\.fail\/(en\/)?terms"/, "signing in agrees to the terms, linked");
    assert.match(b.page, /href="https:\/\/still\.fail\/(en\/)?privacy"/);
    const sent = await b.post({ via: "email", email: " New.Person@Example.TEST " });
    assert.equal(sent.status, 200);
    assert.match(await sent.text(), /new\.person@example\.test/, "the code page says where it went");
    assert.match(sent.headers.get("content-security-policy")!, /form-action [^;]* http:\/\/127\.0\.0\.1:32145(;| )/, "its form may send the browser back to the client");
    assert.equal(h.mails.length, 1);
    assert.equal(h.mails[0]!.to, "new.person@example.test");
    assert.doesNotMatch(h.mails[0]!.subject, /\d{6}/, "the code is not in the subject: lock screens show it");
    const code = codeFor(h, "new.person@example.test");
    const wrong = await b.post({ via: "code", code: code === "000000" ? "111111" : "000000" });
    assert.equal(wrong.status, 200);
    assert.match(await wrong.text(), /4/, "how many tries are left");
    const tokens = await b.exchange(await b.post({ via: "code", code: code.slice(0, 3) + " " + code.slice(3) }));
    assert.equal(tokens.email, "new.person@example.test");
    assert.match(tokens.subject, /^em-[A-Za-z0-9_-]{32}$/);
    const me = await h.as(tokens)("GET", "/v1/me");
    assert.equal(me.status, 200, "an account like any other");
    const again = await emailLogin(h, "10.1.0.2", "new.person@example.test");
    assert.equal(again.subject, tokens.subject);
  } finally {
    await h.close();
  }
});

test("an app signs in with an email's code: the code page lets its form send the browser back to the app", { timeout: 30000 }, async () => {
  const h = await harness({ mail: true });
  try {
    const b = await browser(h, "10.7.0.1", "stillfail://auth/callback");
    const sent = await b.post({ via: "email", email: "app@example.test" });
    assert.equal(sent.status, 200);
    // Browsers hold a form's redirect to form-action: without the app's scheme, the right code goes nowhere.
    assert.match(sent.headers.get("content-security-policy")!, /form-action 'self' https:\/\/accounts\.google\.com stillfail:;/);
    const tokens = await b.exchange(await b.post({ via: "code", code: codeFor(h, "app@example.test") }));
    assert.equal(tokens.email, "app@example.test");
  } finally {
    await h.close();
  }
});

test("an email and Google with the same address are one account, whichever came first", { timeout: 30000 }, async () => {
  const h = await harness({ mail: true });
  try {
    const google = await googleLogin(h, "10.2.0.1", "carol");
    assert.equal(google.subject, "carol");
    const byEmail = await emailLogin(h, "10.2.0.2", "Carol@example.test");
    assert.equal(byEmail.subject, "carol", "the code to carol's email signs in to her Google account");
    assert.equal(byEmail.name, "Name of carol", "with its name");
    const first = await emailLogin(h, "10.2.0.3", "dave@example.test");
    assert.match(first.subject, /^em-/);
    const later = await googleLogin(h, "10.2.0.4", "dave");
    assert.equal(later.subject, first.subject, "Google with the email signed up with is that account");
    assert.equal(later.name, "Name of dave");
    assert.equal((await emailLogin(h, "10.2.0.5", "dave@example.test")).subject, first.subject);
  } finally {
    await h.close();
  }
});

test("five wrong codes end a sign-in, an email gets five codes an hour, and only the browser that asked can use them", { timeout: 30000 }, async () => {
  const h = await harness({ mail: true });
  try {
    const b = await browser(h, "10.3.0.1");
    await b.post({ via: "email", email: "eve@example.test" });
    const code = codeFor(h, "eve@example.test");
    // Another browser (no cookie, another csrf) or another site's form gets nowhere.
    assert.equal((await b.post({ via: "code", code }, { cookie: "" })).status, 400);
    assert.equal((await b.post({ via: "code", code }, { csrf: randomSecret() })).status, 400);
    assert.equal((await b.post({ via: "code", code }, { origin: "https://evil.example" })).status, 400);
    const other = code === "999999" ? "888888" : "999999";
    for (let i = 0; i < 4; i++) assert.match(await (await b.post({ via: "code", code: other })).text(), /name="code"/);
    const ended = await (await b.post({ via: "code", code: other })).text();
    assert.doesNotMatch(ended, /name="code"/, "the fifth wrong one ends it");
    assert.equal((await b.post({ via: "code", code })).status, 200);
    assert.doesNotMatch(await (await b.post({ via: "code", code })).text(), /name="code"/, "the right one too, after");

    // Sent again, the code before it no longer works; five codes an hour to one email, from wherever they are asked.
    const c = await browser(h, "10.3.0.2");
    await c.post({ via: "email", email: "frank@example.test" });
    const old = codeFor(h, "frank@example.test");
    await c.post({ via: "resend" });
    assert.equal(h.mails.filter((m) => m.to === "frank@example.test").length, 2);
    if (old !== codeFor(h, "frank@example.test")) assert.match(await (await c.post({ via: "code", code: old })).text(), /name="code"/);
    for (let i = 0; i < 3; i++) await c.post({ via: "resend" });
    const d = await browser(h, "10.3.0.3");
    const limited = await (await d.post({ via: "email", email: "frank@example.test" })).text();
    assert.equal(h.mails.filter((m) => m.to === "frank@example.test").length, 5, "the sixth is not sent");
    assert.match(limited, /class="error"/);
    assert.match(limited, /type="email"/, "and the page still asks");
    // Not an email: asked again, nothing sent.
    const before = h.mails.length;
    assert.match(await (await d.post({ via: "email", email: "not an email" })).text(), /class="error"/);
    assert.match(await (await d.post({ via: "email", email: "a@b" })).text(), /class="error"/);
    assert.equal(h.mails.length, before);
    // Another email instead: back to the first page.
    const e = await browser(h, "10.3.0.4");
    await e.post({ via: "email", email: "gina@example.test" });
    assert.match(await (await e.post({ via: "back" })).text(), /type="email"/);
    assert.equal((await e.post({ via: "code", code: codeFor(h, "gina@example.test") })).status, 200, "the code page is gone with it");
  } finally {
    await h.close();
  }
});

test("a code that cannot be sent says so and leaves Google", { timeout: 30000 }, async () => {
  const h = await harness({ mail: () => "E_SENDER_NOT_VERIFIED" });
  try {
    const b = await browser(h, "10.4.0.1");
    const page = await (await b.post({ via: "email", email: "hank@example.test" })).text();
    assert.match(page, /class="error"/);
    assert.match(page, /name="via" value="google"/);
    assert.equal((await b.post({ via: "google" })).status, 302);
  } finally {
    await h.close();
  }
});

test("a device signs in with an email's code: the mail names it", { timeout: 30000 }, async () => {
  const h = await harness({ mail: true });
  try {
    const id = randomSecret(),
      verifier = randomSecret();
    const started = await h.fetch("/v1/auth/device", { method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "10.5.0.1" }, body: JSON.stringify({ id, code_challenge: await digest(verifier), name: "build-box" }) });
    assert.equal(started.status, 200);
    const { verification_uri } = (await started.json()) as { verification_uri: string };
    const page = await h.fetch(new URL(verification_uri).pathname, { headers: { "cf-connecting-ip": "10.5.0.1" } });
    const html = await page.text();
    assert.match(html, /build-box/);
    assert.match(html, /type="email"/);
    const cookie = page.headers.get("set-cookie")!.split(";")[0]!;
    const post = (fields: Record<string, string>) =>
      h.fetch(`/v1/auth/login/${id}`, { method: "POST", redirect: "manual", headers: { "content-type": "application/x-www-form-urlencoded", origin: h.origin, cookie, "cf-connecting-ip": "10.5.0.1" }, body: new URLSearchParams({ csrf: cookie.split("=")[1]!, ...fields }).toString() });
    const poll = () => h.fetch("/v1/auth/device/token", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ id, code_verifier: verifier }) });
    await post({ via: "email", email: "ivy@example.test" });
    assert.match(h.mails[0]!.text, /build-box/, "whoever reads the mail sees what it signs in");
    assert.equal((await poll()).status, 202);
    const done = await post({ via: "code", code: codeFor(h, "ivy@example.test") });
    assert.equal(done.status, 302);
    assert.equal(new URL(done.headers.get("location")!).pathname, "/v1/auth/device/complete");
    const tokens = (await (await poll()).json()) as Tokens;
    assert.equal(tokens.email, "ivy@example.test");
  } finally {
    await h.close();
  }
});

test("an app's browser sign-in ends on a page saying it is signed in, an Android app's with a link back to it", { timeout: 30000 }, async () => {
  const h = await harness();
  try {
    const page = await h.fetch("/v1/auth/done", { headers: { "accept-language": "zh-CN" } });
    assert.equal(page.status, 200);
    const text = await page.text();
    assert.match(text, /<h1>已登录<\/h1>/);
    assert.doesNotMatch(text, /intent:/, "no app named, no link");
    const android = await (await h.fetch("/v1/auth/done?app=fail.still.android", { headers: { "accept-language": "en" } })).text();
    assert.match(android, /<h1>Signed in<\/h1>/);
    assert.match(android, /href="intent:\/\/back#Intent;scheme=fail\.still\.android;package=fail\.still\.android;end"/);
    const odd = await (await h.fetch("/v1/auth/done?app=" + encodeURIComponent('x"><script>'))).text();
    assert.doesNotMatch(odd, /intent:|<script>/, "not a package: no link");
  } finally {
    await h.close();
  }
});

test("the sign-in page signs an account set up for it in with its password, a wrong one said so on the page", { timeout: 30000 }, async () => {
  const h = await harness({ mail: true, reviewAccounts: JSON.stringify([{ email: "Review@Example.test", password: "correct horse battery", name: "App Review" }]) });
  try {
    const b = await browser(h, "10.9.0.1");
    assert.match(b.page, /name="via" value="password-page"/, "a link to the page that asks for a password");
    const asked = await (await b.post({ via: "password-page" })).text();
    assert.match(asked, /name="via" value="password"/);
    assert.match(asked, /type="password"/);
    const wrong = await b.post({ via: "password", email: "review@example.test", password: "correct horse batter" });
    assert.equal(wrong.status, 200);
    const page = await wrong.text();
    assert.match(page, /邮箱或密码错误|Wrong email or password/);
    assert.match(page, /name="email" value="review@example.test"/, "what was typed kept");
    assert.match(await (await b.post({ via: "password", email: "someone@example.test", password: "correct horse battery" })).text(), /邮箱或密码错误|Wrong email or password/, "an email not set up");
    const right = await b.post({ via: "password", email: " Review@EXAMPLE.test ", password: "correct horse battery" });
    const tokens = await b.exchange(right);
    assert.equal(tokens.email, "review@example.test");
    assert.match(tokens.subject, /^pw-[A-Za-z0-9_-]{32}$/, "the account /v1/auth/password signs in");
  } finally {
    await h.close();
  }
});

test("without a way to send mail, signing in goes straight to Google as before", { timeout: 30000 }, async () => {
  const h = await harness();
  try {
    const flow = await h.begin("jill");
    assert.equal(flow.google.origin, "https://accounts.google.com");
    const id = randomSecret();
    const posted = await h.fetch(`/v1/auth/login/${id}`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded", origin: h.origin }, body: "via=email&email=jill%40example.test" });
    assert.doesNotMatch(await posted.text(), /name="code"/);
    assert.equal(h.mails.length, 0);
  } finally {
    await h.close();
  }
});

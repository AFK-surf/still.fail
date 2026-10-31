import { devicePage, escape } from "./page";
import { requestLang, tr, type Lang } from "./i18n.ts";
import { mailConfigured, sendCode } from "./mail";
export { devicePage } from "./page";

/** An Android app's package (its intent's scheme and package): letters, digits and underscores, dotted. */
const PACKAGE = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/;

/** The page an app's browser sign-in ends on (the browser come back to the app): signed in, close it; with `app` (an
 * Android app's package) a link that brings that app back, should it not have come forward by itself. */
export function signedInPage(lang: Lang, app: string | null): Response {
  const back = app && PACKAGE.test(app) ? `<p class="links"><a class="button" href="intent://back#Intent;scheme=${app};package=${app};end">${tr(lang, "cloud.login.done.back")}</a></p>` : "";
  return devicePage(lang, tr(lang, "cloud.login.done.title"), `<p>${tr(lang, "cloud.login.done.body")}</p>${back}`);
}
import { DurableObject } from "cloudflare:workers";
import { ulid } from "ulid";
import type { Env } from "./env";
import { CODE_TTL_SEC, LOGIN_TTL_SEC, REFRESH_RETRY_SEC, digest, googleIdentity, limited, nowSeconds, randomSecret, readText, reply, seal, unseal, validRedirect, validSecret, type Identity, type Tokens } from "./auth";

type Attempt = {
  redirect: string;
  state: string;
  challenge: string;
  name: string;
  browserHash: string;
  nonce: string;
  googleVerifier: string;
  expires: number;
  /** waiting: a device's, its page not used yet; choosing: the page asks Google or an email; code: a code was sent to
   * `email`; started: gone to Google. */
  phase: "waiting" | "choosing" | "code" | "started" | "callback" | "complete" | "used" | "cancelled";
  device?: boolean;
  nextPoll?: number;
  receipt?: string;
  identity?: Identity;
  codeHash?: string;
  sessionId?: string;
  /** Signing in with an email: where the code went, the code's hash (with the attempt's id), until when it holds and how
   * many wrong ones were typed. */
  email?: string;
  mailCode?: string;
  mailExpires?: number;
  tries?: number;
};

/** Google's "G", in its own colours, before 使用 Google 账号继续 (as Google's sign-in buttons have it). */
const GOOGLE_MARK =
  '<svg width="18" height="18" viewBox="0 0 48 48" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>';

/** Wrong codes a code takes before the sign-in ends. */
const CODE_TRIES = 5;
const EMAIL = /^[^\s@]{1,64}@[^\s@.][^\s@]{0,189}$/;

/** Six digits, each as likely. */
function newMailCode(): string {
  for (;;) {
    const n = crypto.getRandomValues(new Uint32Array(1))[0]!;
    // 4 294 000 000 is a multiple of a million: the rest would make the low codes likelier.
    if (n < 4_294_000_000) return String(n % 1_000_000).padStart(6, "0");
  }
}

function cookieName(origin: string, id: string) {
  return `${origin.startsWith("https:") ? "__Host-" : ""}zork_login_${id}`;
}
function cookie(origin: string, id: string, value: string, age: number) {
  return `${cookieName(origin, id)}=${value}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${age}${origin.startsWith("https:") ? "; Secure" : ""}`;
}
function cookieOf(request: Request, origin: string, id: string): string {
  return (
    (request.headers.get("cookie") ?? "")
      .split(";")
      .map((v) => v.trim())
      .find((v) => v.startsWith(cookieName(origin, id) + "="))
      ?.split("=")[1] ?? ""
  );
}
/** What a page's form-action lists for a login's return (auth.ts validRedirect): an app's scheme, else the origin. */
export function returnSource(redirect: string): string | undefined {
  try {
    const url = new URL(redirect);
    return url.protocol === "http:" || url.protocol === "https:" ? url.origin : url.protocol;
  } catch {
    return undefined;
  }
}

function redirect(location: string, cookies: string): Response {
  return new Response(null, {
    status: 302,
    headers: {
      location,
      "set-cookie": cookies,
      "cache-control": "no-store",
      "referrer-policy": "no-referrer",
    },
  });
}
/** A link to one of the legal pages on still.fail's site (web/public/terms.html, privacy.html; en/ the English), opened beside the sign-in. */
function legalLink(lang: Lang, page: "terms" | "privacy"): string {
  return `<a href="https://still.fail/${lang === "zh" ? "" : "en/"}${page}" target="_blank" rel="noopener">${tr(lang, `cloud.login.choose.${page}`)}</a>`;
}

/** One login attempt, single-use callback and PKCE code, removed on its alarm. */
export class LoginAttempt extends DurableObject<Env> {
  private async google(id: string, attempt: Attempt, browser: string): Promise<Response> {
    const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
    for (const [key, value] of Object.entries({
      client_id: this.env.GOOGLE_CLIENT_ID,
      redirect_uri: `${this.env.PUBLIC_ORIGIN}/v1/auth/google/callback`,
      response_type: "code",
      scope: "openid email profile",
      state: id,
      prompt: "select_account",
      nonce: attempt.nonce,
      code_challenge_method: "S256",
      code_challenge: await digest(attempt.googleVerifier),
    }))
      url.searchParams.set(key, value);
    return redirect(url.toString(), cookie(this.env.PUBLIC_ORIGIN, id, browser, LOGIN_TTL_SEC));
  }
  async startDevice(id: string, challenge: string, name: string): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      if (this.ctx.storage.kv.get("attempt")) return reply({ error: "login_exists" }, 409);
      if (!validSecret(id) || !validSecret(challenge) || !name.trim() || name.length > 80) return reply({ error: "invalid_login" }, 400);
      const attempt: Attempt = {
        redirect: "",
        state: id,
        challenge,
        name,
        browserHash: "",
        nonce: randomSecret(),
        googleVerifier: randomSecret(),
        expires: nowSeconds() + LOGIN_TTL_SEC,
        phase: "waiting",
        device: true,
      };
      this.ctx.storage.kv.put("attempt", attempt);
      await this.ctx.storage.setAlarm(attempt.expires * 1000);
      return reply({
        verification_uri: `${this.env.PUBLIC_ORIGIN}/v1/auth/device/${id}`,
        expires_at: attempt.expires,
        interval: 3,
      });
    });
  }
  async authorizeDevice(id: string, request: Request): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const attempt = this.ctx.storage.kv.get<Attempt>("attempt");
      const lang = requestLang(request);
      if (!attempt?.device || attempt.expires <= nowSeconds() || attempt.phase !== "waiting") return devicePage(lang, tr(lang, "cloud.login.ended.title"), `<p>${tr(lang, "cloud.login.ended.body")}</p>`);
      if (request.method === "GET") {
        const browser = randomSecret();
        attempt.browserHash = await digest(browser);
        this.ctx.storage.kv.put("attempt", attempt);
        if (mailConfigured(this.env)) return this.choosePage(lang, id, attempt, browser);
        return devicePage(
          lang,
          tr(lang, "cloud.login.device.title"),
          `<p>${tr(lang, "cloud.login.device.signingIn", { name: `<strong>${escape(attempt.name)}</strong>` })}</p><p>${tr(lang, "cloud.login.device.reach")}</p><form method="post"><input type="hidden" name="csrf" value="${browser}"><button class="secondary">${GOOGLE_MARK}${tr(lang, "cloud.login.device.continue")}</button></form>`,
          cookie(this.env.PUBLIC_ORIGIN, id, browser, LOGIN_TTL_SEC),
        );
      }
      const browser = cookieOf(request, this.env.PUBLIC_ORIGIN, id);
      try {
        if (request.headers.get("origin") !== this.env.PUBLIC_ORIGIN || request.headers.get("content-type")?.split(";")[0] !== "application/x-www-form-urlencoded") return reply({ error: "invalid_login_state" }, 400);
        const csrf = new URLSearchParams(await readText(request, 1024)).get("csrf");
        if (!validSecret(browser) || csrf !== browser || (await digest(browser)) !== attempt.browserHash) return reply({ error: "invalid_login_state" }, 400);
      } catch {
        return reply({ error: "invalid_login_state" }, 400);
      }
      attempt.phase = "started";
      this.ctx.storage.kv.put("attempt", attempt);
      return this.google(id, attempt, browser);
    });
  }
  async cancelDevice(verifier: string): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const attempt = this.ctx.storage.kv.get<Attempt>("attempt");
      if (!attempt?.device || !validSecret(verifier) || (await digest(verifier)) !== attempt.challenge) return reply({ error: "invalid_grant" }, 401);
      if (attempt.receipt && attempt.identity) {
        const tokens = (await unseal(this.env, attempt.receipt)) as { refresh_token: string };
        const result = await this.env.ACCOUNTS.getByName(attempt.identity.sub).logout(tokens.refresh_token, false);
        if (!result.ok) return result;
      }
      attempt.phase = "cancelled";
      delete attempt.receipt;
      this.ctx.storage.kv.put("attempt", attempt);
      return reply({ cancelled: true });
    });
  }
  async pollDevice(verifier: string): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const attempt = this.ctx.storage.kv.get<Attempt>("attempt");
      if (!attempt?.device || attempt.expires <= nowSeconds() || !validSecret(verifier) || (await digest(verifier)) !== attempt.challenge) return reply({ error: "invalid_grant" }, 401);
      if (attempt.phase === "cancelled") return reply({ error: "login_cancelled" }, 403);
      if (attempt.phase === "used") return attempt.receipt ? reply(await unseal(this.env, attempt.receipt)) : reply({ error: "invalid_grant" }, 401);
      if (attempt.phase !== "complete") {
        if ((attempt.nextPoll ?? 0) > nowSeconds()) return limited(3);
        attempt.nextPoll = nowSeconds() + 3;
        this.ctx.storage.kv.put("attempt", attempt);
        return reply({ pending: true }, 202);
      }
      if (!attempt.identity || !attempt.sessionId) return reply({ error: "invalid_grant" }, 401);
      const result = await this.env.ACCOUNTS.getByName(attempt.identity.sub).create(attempt.identity, attempt.sessionId, attempt.name);
      if (result.ok) {
        const tokens = (await result.json()) as Tokens;
        attempt.receipt = await seal(this.env, tokens, nowSeconds() + REFRESH_RETRY_SEC);
        attempt.phase = "used";
        attempt.expires = nowSeconds() + CODE_TTL_SEC;
        this.ctx.storage.kv.put("attempt", attempt);
        await this.ctx.storage.setAlarm(attempt.expires * 1000);
        return reply(tokens);
      }
      return result;
    });
  }
  async start(id: string, params: { redirect: string; state: string; challenge: string; name: string }, request: Request): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      if (this.ctx.storage.kv.get("attempt")) return reply({ error: "login_exists" }, 409);
      if (!validSecret(id) || !validRedirect(this.env, params.redirect) || !validSecret(params.state) || !validSecret(params.challenge) || params.name.length > 80) return reply({ error: "invalid_login" }, 400);
      const browser = randomSecret();
      const choosing = mailConfigured(this.env);
      const attempt: Attempt = {
        ...params,
        browserHash: await digest(browser),
        nonce: randomSecret(),
        googleVerifier: randomSecret(),
        expires: nowSeconds() + LOGIN_TTL_SEC,
        phase: choosing ? "choosing" : "started",
      };
      this.ctx.storage.kv.put("attempt", attempt);
      await this.ctx.storage.setAlarm(attempt.expires * 1000);
      // Without a way to send codes, straight to Google, as before there was another way.
      return choosing ? this.choosePage(requestLang(request), id, attempt, browser) : this.google(id, attempt, browser);
    });
  }

  async callback(id: string, request: Request): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const attempt = this.ctx.storage.kv.get<Attempt>("attempt");
      const value = cookieOf(request, this.env.PUBLIC_ORIGIN, id);
      if (!attempt || attempt.expires <= nowSeconds() || attempt.phase !== "started" || !validSecret(value) || (await digest(value)) !== attempt.browserHash) return reply({ error: "invalid_login_state" }, 400);
      // Consume before any external I/O; a repeated callback cannot replay Google.
      attempt.phase = "callback";
      this.ctx.storage.kv.put("attempt", attempt);
      const url = new URL(request.url);
      let finish = this.finish(attempt);
      let done = false;
      const code = url.searchParams.get("code");
      if (url.searchParams.has("error") || !code || code.length > 4096) {
        finish.searchParams.set("error", "login_cancelled");
      } else {
        try {
          const identity = await googleIdentity(this.env, code, attempt.googleVerifier, attempt.nonce, url.origin);
          // An account that signed up with this email (a code sent to it) is this one too.
          const account = await this.env.DIRECTORY.getByName("primary").accountFor(identity.sub, identity.email);
          finish = await this.complete(id, attempt, { ...identity, sub: account?.sub ?? identity.sub });
          done = true;
        } catch {
          finish.searchParams.set("error", "google_login_failed");
        }
      }
      if (attempt.device) {
        if (!done) {
          attempt.phase = "cancelled";
          this.ctx.storage.kv.put("attempt", attempt);
        }
        finish.searchParams.delete("state");
      }
      return redirect(finish.toString(), cookie(this.env.PUBLIC_ORIGIN, id, "", 0));
    });
  }

  /** Where the browser goes once the sign-in is done: the client's callback with its state, or the device's page. */
  private finish(attempt: Attempt): URL {
    const finish = new URL(attempt.device ? `${this.env.PUBLIC_ORIGIN}/v1/auth/device/complete` : attempt.redirect);
    finish.searchParams.set("state", attempt.state);
    return finish;
  }

  /** The attempt has proved it is `identity` (Google said so, or the email's code was right): its code is made, and where the browser goes with it. */
  private async complete(id: string, attempt: Attempt, identity: Identity): Promise<URL> {
    const finish = this.finish(attempt);
    attempt.identity = identity;
    const secret = randomSecret();
    if (!attempt.device) attempt.codeHash = await digest(secret);
    attempt.phase = "complete";
    attempt.expires = nowSeconds() + CODE_TTL_SEC;
    attempt.sessionId = ulid();
    // Code is a locator and an independent random capability; no credentials
    // or Google tokens are returned through the browser's URL/history.
    if (!attempt.device) finish.searchParams.set("code", `${id}.${secret}`);
    this.ctx.storage.kv.put("attempt", attempt);
    await this.ctx.storage.setAlarm(attempt.expires * 1000);
    return finish;
  }

  /** The page that asks how to sign in: Google, or a code sent to an email (`email` typed, `error` with it). */
  private choosePage(lang: Lang, id: string, attempt: Attempt, browser: string, email = "", error?: string): Response {
    const csrf = `<input type="hidden" name="csrf" value="${browser}">`;
    const action = `/v1/auth/login/${id}`;
    const device = attempt.device ? `<p>${tr(lang, "cloud.login.device.signingIn", { name: `<strong>${escape(attempt.name)}</strong>` })}</p><p>${tr(lang, "cloud.login.device.reach")}</p>` : "";
    return devicePage(
      lang,
      tr(lang, attempt.device ? "cloud.login.device.title" : "cloud.login.choose.title"),
      `${device}<form class="wide" method="post" action="${action}">${csrf}<input type="hidden" name="via" value="google"><button class="secondary">${GOOGLE_MARK}${tr(lang, "cloud.login.device.continue")}</button></form>` +
        `<p class="or">${tr(lang, "cloud.login.choose.or")}</p>` +
        `<form class="wide" method="post" action="${action}">${csrf}<input type="hidden" name="via" value="email"><input type="email" name="email" value="${escape(email)}" placeholder="${tr(lang, "cloud.login.email.placeholder")}" autocomplete="email" required maxlength="254"><button>${tr(lang, "cloud.login.email.send")}</button></form>` +
        (error ? `<p class="error">${escape(error)}</p>` : "") +
        `<p class="legal">${tr(lang, "cloud.login.choose.agree", { terms: legalLink(lang, "terms"), privacy: legalLink(lang, "privacy") })}</p>`,
      cookie(this.env.PUBLIC_ORIGIN, id, browser, LOGIN_TTL_SEC),
    );
  }

  /** The page that asks for the code sent to the attempt's email. */
  private codePage(lang: Lang, id: string, attempt: Attempt, browser: string, error?: string): Response {
    const csrf = `<input type="hidden" name="csrf" value="${browser}">`;
    const action = `/v1/auth/login/${id}`;
    return devicePage(
      lang,
      tr(lang, "cloud.login.code.title"),
      `<p>${tr(lang, "cloud.login.code.sent", { email: `<strong>${escape(attempt.email ?? "")}</strong>` })}</p>` +
        `<form class="wide" method="post" action="${action}">${csrf}<input type="hidden" name="via" value="code"><input class="code" name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9 ]{6,7}" maxlength="7" placeholder="${tr(lang, "cloud.login.code.placeholder")}" aria-label="${tr(lang, "cloud.login.code.placeholder")}" required autofocus><button>${tr(lang, "cloud.login.code.submit")}</button></form>` +
        (error ? `<p class="error">${escape(error)}</p>` : "") +
        `<p class="links"><button form="resend" class="link">${tr(lang, "cloud.login.code.resend")}</button><button form="back" class="link">${tr(lang, "cloud.login.code.other")}</button></p>` +
        `<form id="resend" method="post" action="${action}">${csrf}<input type="hidden" name="via" value="resend"></form><form id="back" method="post" action="${action}">${csrf}<input type="hidden" name="via" value="back"></form>`,
      cookie(this.env.PUBLIC_ORIGIN, id, browser, LOGIN_TTL_SEC),
      // The right code sends the browser back where the attempt returns (choose's redirect): a device's ends here.
      attempt.device ? undefined : returnSource(attempt.redirect),
    );
  }

  /** The account a code sent to `email` signs in to: the one with that email (a Google one too), else a new one of its own. */
  private async emailIdentity(email: string): Promise<Identity> {
    const own = `em-${(await digest(email)).slice(0, 32)}`;
    const account = await this.env.DIRECTORY.getByName("primary").accountFor(own, email);
    return { sub: account?.sub ?? own, email, name: account?.name ?? "", picture: account?.picture ?? "" };
  }

  /**
   * POST /v1/auth/login/:id, from the page that asks how to sign in (choosePage, codePage), in the browser that started
   * the attempt (its cookie and the form's csrf): `via` google (on to Google), email (a code to `email`), resend, back
   * (another email) or code (the `code` typed).
   */
  async choose(id: string, request: Request): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const attempt = this.ctx.storage.kv.get<Attempt>("attempt");
      const lang = requestLang(request);
      const ended = (title = "cloud.login.ended.title") => devicePage(lang, tr(lang, title), `<p>${tr(lang, "cloud.login.ended.body")}</p>`, cookie(this.env.PUBLIC_ORIGIN, id, "", 0));
      if (!attempt || attempt.expires <= nowSeconds() || !(attempt.phase === "choosing" || attempt.phase === "code" || (attempt.phase === "waiting" && attempt.device)) || !mailConfigured(this.env)) return ended();
      const browser = cookieOf(request, this.env.PUBLIC_ORIGIN, id);
      let form: URLSearchParams;
      try {
        if (request.headers.get("origin") !== this.env.PUBLIC_ORIGIN || request.headers.get("content-type")?.split(";")[0] !== "application/x-www-form-urlencoded") return reply({ error: "invalid_login_state" }, 400);
        form = new URLSearchParams(await readText(request, 2048));
        if (!validSecret(browser) || form.get("csrf") !== browser || (await digest(browser)) !== attempt.browserHash) return reply({ error: "invalid_login_state" }, 400);
      } catch {
        return reply({ error: "invalid_login_state" }, 400);
      }
      const save = async () => {
        this.ctx.storage.kv.put("attempt", attempt);
        await this.ctx.storage.setAlarm(attempt.expires * 1000);
      };
      const send = async (email: string): Promise<Response> => {
        // Per address, as starting one is, and per email: nobody fills someone's inbox.
        if (!(await consumeLoginRate(this.env, request)) || !(await this.env.LOGIN_LIMITS.getByName(await digest(`${this.env.AUTH_SIGNING_KEY}:email:${email}`)).consumeMail()))
          return this.choosePage(lang, id, attempt, browser, email, tr(lang, "cloud.login.email.limited"));
        const code = newMailCode();
        try {
          // A device's sign-in names the device in the mail: someone asked to read a code out for another's device can tell.
          await sendCode(this.env, lang, email, code, attempt.device ? attempt.name : "");
        } catch (error) {
          console.error("login: no code sent", (error as { code?: string }).code ?? String(error));
          return this.choosePage(lang, id, attempt, browser, email, tr(lang, "cloud.login.email.failed"));
        }
        attempt.phase = "code";
        attempt.email = email;
        attempt.mailCode = await digest(`${id}:${code}`);
        attempt.mailExpires = nowSeconds() + LOGIN_TTL_SEC;
        attempt.tries = 0;
        attempt.expires = Math.max(attempt.expires, attempt.mailExpires);
        await save();
        return this.codePage(lang, id, attempt, browser);
      };
      const via = form.get("via");
      if (via === "google") {
        attempt.phase = "started";
        this.ctx.storage.kv.put("attempt", attempt);
        return this.google(id, attempt, browser);
      }
      if (via === "email") {
        const email = (form.get("email") ?? "").trim().toLowerCase();
        if (!EMAIL.test(email) || !email.split("@")[1]!.includes(".")) return this.choosePage(lang, id, attempt, browser, email, tr(lang, "cloud.login.email.invalid"));
        return send(email);
      }
      if (via === "resend" && attempt.phase === "code" && attempt.email) return send(attempt.email);
      if (via === "back") {
        attempt.phase = "choosing";
        delete attempt.email;
        delete attempt.mailCode;
        await save();
        return this.choosePage(lang, id, attempt, browser, "");
      }
      if (via === "code" && attempt.phase === "code" && attempt.email && attempt.mailCode) {
        const code = (form.get("code") ?? "").replace(/\s/g, "");
        if ((attempt.mailExpires ?? 0) <= nowSeconds()) return this.codePage(lang, id, attempt, browser, tr(lang, "cloud.login.code.expired"));
        if (!/^\d{6}$/.test(code) || (await digest(`${id}:${code}`)) !== attempt.mailCode) {
          attempt.tries = (attempt.tries ?? 0) + 1;
          if (attempt.tries >= CODE_TRIES) {
            attempt.phase = "cancelled";
            await save();
            return ended("cloud.login.code.tooMany");
          }
          await save();
          return this.codePage(lang, id, attempt, browser, tr(lang, "cloud.login.code.wrong", { n: CODE_TRIES - attempt.tries }));
        }
        const finish = await this.complete(id, attempt, await this.emailIdentity(attempt.email));
        if (attempt.device) finish.searchParams.delete("state");
        return redirect(finish.toString(), cookie(this.env.PUBLIC_ORIGIN, id, "", 0));
      }
      return attempt.phase === "code" ? this.codePage(lang, id, attempt, browser) : this.choosePage(lang, id, attempt, browser);
    });
  }

  async exchange(secret: string, verifier: string, redirectUri: string): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const attempt = this.ctx.storage.kv.get<Attempt>("attempt");
      if (
        !attempt ||
        attempt.device ||
        attempt.phase !== "complete" ||
        attempt.expires <= nowSeconds() ||
        !attempt.identity ||
        !attempt.sessionId ||
        !validSecret(secret) ||
        !validSecret(verifier) ||
        (await digest(secret)) !== attempt.codeHash ||
        (await digest(verifier)) !== attempt.challenge ||
        redirectUri !== attempt.redirect
      )
        return reply({ error: "invalid_grant" }, 401);
      attempt.phase = "used";
      this.ctx.storage.kv.put("attempt", attempt);
      return this.env.ACCOUNTS.getByName(attempt.identity.sub).create(attempt.identity, attempt.sessionId, attempt.name);
    });
  }

  async alarm() {
    await this.ctx.storage.deleteAll();
  }
}

/** Only login creation reaches this object, keyed by a salted address hash. */
export class LoginLimiter extends DurableObject<Env> {
  async consume(): Promise<boolean> {
    const now = nowSeconds();
    const minute = Math.floor(now / 60);
    const day = Math.floor(now / 86400);
    const old = this.ctx.storage.kv.get<{
      minute: number;
      short: number;
      day: number;
      daily: number;
    }>("limits");
    const next = {
      minute,
      day,
      short: old?.minute === minute ? old.short : 0,
      daily: old?.day === day ? old.daily : 0,
    };
    if (next.short >= 10 || next.daily >= 100) return false;
    next.short++;
    next.daily++;
    this.ctx.storage.kv.put("limits", next);
    await this.ctx.storage.setAlarm((day + 1) * 86400 * 1000);
    return true;
  }
  /** One code sent to an email, this object keyed by its salted hash: 5 an hour, 10 a day. */
  async consumeMail(): Promise<boolean> {
    const now = nowSeconds();
    const hour = Math.floor(now / 3600);
    const day = Math.floor(now / 86400);
    const old = this.ctx.storage.kv.get<{ hour: number; hourly: number; day: number; daily: number }>("mail");
    const next = { hour, day, hourly: old?.hour === hour ? old.hourly : 0, daily: old?.day === day ? old.daily : 0 };
    if (next.hourly >= 5 || next.daily >= 10) return false;
    next.hourly++;
    next.daily++;
    this.ctx.storage.kv.put("mail", next);
    await this.ctx.storage.setAlarm((day + 1) * 86400 * 1000);
    return true;
  }
  async alarm() {
    await this.ctx.storage.deleteAll();
  }
}

export async function googleStart(env: Env, request: Request): Promise<Response> {
  const url = new URL(request.url);
  const state = url.searchParams.get("state") ?? "";
  const challenge = url.searchParams.get("code_challenge") ?? "";
  const callback = url.searchParams.get("redirect_uri") ?? "";
  if (!validRedirect(env, callback) || !validSecret(state) || !validSecret(challenge) || url.searchParams.get("code_challenge_method") !== "S256") return reply({ error: "invalid_login" }, 400);
  if (!(await consumeLoginRate(env, request))) return limited();
  const id = randomSecret();
  const name = (url.searchParams.get("name") ?? "still.fail").slice(0, 80);
  return env.LOGINS.getByName(id).start(id, { redirect: callback, state, challenge, name }, request);
}

export async function consumeLoginRate(env: Env, request: Request): Promise<boolean> {
  const ip = request.headers.get("cf-connecting-ip") ?? "local";
  return env.LOGIN_LIMITS.getByName(await digest(`${env.AUTH_SIGNING_KEY}:${ip}`)).consume();
}

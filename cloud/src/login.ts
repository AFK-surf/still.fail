import { devicePage, escape } from "./page";
import { requestLang, tr } from "./i18n.ts";
export { devicePage } from "./page";
import { DurableObject } from "cloudflare:workers";
import { ulid } from "ulid";
import type { Env } from "./env";
import { CODE_TTL_SEC, LOGIN_TTL_SEC, REFRESH_RETRY_SEC, digest, googleIdentity, limited, nowSeconds, randomSecret, readText, reply, seal, unseal, validRedirect, validSecret, type Identity, type Tokens } from "./auth";
import { appleAuthorizeUrl, appleBundleIds, appleIdentity, appleName, verifyAppleToken } from "./apple";

type Attempt = {
  redirect: string;
  state: string;
  challenge: string;
  name: string;
  browserHash: string;
  nonce: string;
  googleVerifier: string;
  expires: number;
  phase: "waiting" | "started" | "posted" | "callback" | "complete" | "used" | "cancelled";
  device?: boolean;
  /** Signing in with Apple (apple.ts) rather than Google: in the browser, or `native`ly in the iOS app. */
  provider?: "apple";
  native?: boolean;
  /** What Apple posted back, kept for the callback's GET: its code (none when it said no) and the name it gave. */
  posted?: { code?: string; name: string };
  nextPoll?: number;
  receipt?: string;
  identity?: Identity;
  codeHash?: string;
  sessionId?: string;
};

function cookieName(origin: string, id: string) {
  return `${origin.startsWith("https:") ? "__Host-" : ""}zork_login_${id}`;
}
function cookie(origin: string, id: string, value: string, age: number) {
  return `${cookieName(origin, id)}=${value}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${age}${origin.startsWith("https:") ? "; Secure" : ""}`;
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
  private apple(id: string, attempt: Attempt, browser: string): Response {
    return redirect(appleAuthorizeUrl(this.env, id, attempt.nonce), cookie(this.env.PUBLIC_ORIGIN, id, browser, LOGIN_TTL_SEC));
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
        return devicePage(
          lang,
          tr(lang, "cloud.login.device.title"),
          `<p>${tr(lang, "cloud.login.device.signingIn", { name: `<strong>${escape(attempt.name)}</strong>` })}</p><p>${tr(lang, "cloud.login.device.reach")}</p><form method="post"><input type="hidden" name="csrf" value="${browser}"><button>${tr(lang, "cloud.login.device.continue")}</button></form>`,
          cookie(this.env.PUBLIC_ORIGIN, id, browser, LOGIN_TTL_SEC),
        );
      }
      const browser =
        (request.headers.get("cookie") ?? "")
          .split(";")
          .map((v) => v.trim())
          .find((v) => v.startsWith(cookieName(this.env.PUBLIC_ORIGIN, id) + "="))
          ?.split("=")[1] ?? "";
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
  async start(id: string, params: { redirect: string; state: string; challenge: string; name: string }, provider?: "apple"): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      if (this.ctx.storage.kv.get("attempt")) return reply({ error: "login_exists" }, 409);
      if (!validSecret(id) || !validRedirect(this.env, params.redirect) || !validSecret(params.state) || !validSecret(params.challenge) || params.name.length > 80) return reply({ error: "invalid_login" }, 400);
      const browser = randomSecret();
      const attempt: Attempt = {
        ...params,
        browserHash: await digest(browser),
        nonce: randomSecret(),
        googleVerifier: randomSecret(),
        expires: nowSeconds() + LOGIN_TTL_SEC,
        phase: "started",
        ...(provider ? { provider } : {}),
      };
      this.ctx.storage.kv.put("attempt", attempt);
      await this.ctx.storage.setAlarm(attempt.expires * 1000);
      return provider === "apple" ? this.apple(id, attempt, browser) : this.google(id, attempt, browser);
    });
  }

  /**
   * Apple's answer, posted cross-site (without the login's cookie): kept, and the browser sent on to the callback's
   * GET, which has the cookie and finishes as Google's does. The first post is the one kept.
   */
  async applePosted(id: string, form: { code: string | null; error: boolean; user: string | null }): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const attempt = this.ctx.storage.kv.get<Attempt>("attempt");
      if (!attempt || attempt.provider !== "apple" || attempt.native || attempt.expires <= nowSeconds() || attempt.phase !== "started") return reply({ error: "invalid_login_state" }, 400);
      const { code } = form;
      let user: unknown;
      try {
        user = JSON.parse(form.user ?? "null");
      } catch {}
      attempt.posted = { ...(code && code.length <= 4096 && !form.error ? { code } : {}), name: appleName(user) };
      attempt.phase = "posted";
      this.ctx.storage.kv.put("attempt", attempt);
      return new Response(null, {
        status: 303,
        headers: { location: `${this.env.PUBLIC_ORIGIN}/v1/auth/apple/callback?state=${id}`, "cache-control": "no-store", "referrer-policy": "no-referrer" },
      });
    });
  }

  /** The iOS app's sign-in: a nonce for it to give Apple (as its SHA-256, hex), good for one identity token. */
  async startNative(id: string, name: string): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      if (this.ctx.storage.kv.get("attempt")) return reply({ error: "login_exists" }, 409);
      if (!validSecret(id) || !name.trim() || name.length > 80) return reply({ error: "invalid_login" }, 400);
      const attempt: Attempt = {
        redirect: "",
        state: id,
        challenge: "",
        name,
        browserHash: "",
        nonce: randomSecret(),
        googleVerifier: "",
        expires: nowSeconds() + LOGIN_TTL_SEC,
        phase: "started",
        provider: "apple",
        native: true,
      };
      this.ctx.storage.kv.put("attempt", attempt);
      await this.ctx.storage.setAlarm(attempt.expires * 1000);
      return reply({ id, nonce: attempt.nonce, expires_at: attempt.expires });
    });
  }

  /** The identity token the iOS app got for the nonce: a session, once. `user` is the name Apple gave the app, if any. */
  async completeNative(token: string, user: unknown): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const attempt = this.ctx.storage.kv.get<Attempt>("attempt");
      if (!attempt?.native || attempt.expires <= nowSeconds() || attempt.phase !== "started") return reply({ error: "invalid_grant" }, 401);
      // Consumed before Apple's keys are fetched: a token is tried once.
      attempt.phase = "used";
      this.ctx.storage.kv.put("attempt", attempt);
      let identity: Identity;
      try {
        identity = await verifyAppleToken(token, appleBundleIds(this.env), await sha256Hex(attempt.nonce), appleName(user));
      } catch {
        return reply({ error: "apple_login_failed" }, 401);
      }
      return this.env.ACCOUNTS.getByName(identity.sub).create(identity, ulid(), attempt.name);
    });
  }

  async callback(id: string, request: Request): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const attempt = this.ctx.storage.kv.get<Attempt>("attempt");
      const cookies = (request.headers.get("cookie") ?? "").split(";").map((value) => value.trim());
      const value = cookies.find((value) => value.startsWith(cookieName(this.env.PUBLIC_ORIGIN, id) + "="))?.split("=")[1] ?? "";
      const apple = attempt?.provider === "apple";
      if (!attempt || attempt.native || attempt.expires <= nowSeconds() || attempt.phase !== (apple ? "posted" : "started") || !validSecret(value) || (await digest(value)) !== attempt.browserHash) return reply({ error: "invalid_login_state" }, 400);
      // Consume before any external I/O; a repeated callback cannot replay Google (or Apple).
      attempt.phase = "callback";
      this.ctx.storage.kv.put("attempt", attempt);
      const url = new URL(request.url);
      const finish = new URL(attempt.device ? `${this.env.PUBLIC_ORIGIN}/v1/auth/device/complete` : attempt.redirect);
      finish.searchParams.set("state", attempt.state);
      const code = apple ? attempt.posted?.code : url.searchParams.get("code");
      if ((!apple && url.searchParams.has("error")) || !code || code.length > 4096) {
        finish.searchParams.set("error", "login_cancelled");
      } else {
        try {
          attempt.identity = apple
            ? await appleIdentity(this.env, code, attempt.nonce, attempt.posted?.name ?? "")
            : await googleIdentity(this.env, code, attempt.googleVerifier, attempt.nonce, url.origin);
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
        } catch {
          finish.searchParams.set("error", apple ? "apple_login_failed" : "google_login_failed");
        }
      }
      if (attempt.device) {
        if (attempt.phase !== "complete") {
          attempt.phase = "cancelled";
          this.ctx.storage.kv.put("attempt", attempt);
        }
        finish.searchParams.delete("state");
      }
      return redirect(finish.toString(), cookie(this.env.PUBLIC_ORIGIN, id, "", 0));
    });
  }

  async exchange(secret: string, verifier: string, redirectUri: string): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const attempt = this.ctx.storage.kv.get<Attempt>("attempt");
      if (
        !attempt ||
        attempt.device ||
        attempt.native ||
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
  async alarm() {
    await this.ctx.storage.deleteAll();
  }
}

/** A browser's sign-in, with Google or (`provider`) Apple: both take the same parameters and come back the same way. */
export async function googleStart(env: Env, request: Request, provider?: "apple"): Promise<Response> {
  const url = new URL(request.url);
  const state = url.searchParams.get("state") ?? "";
  const challenge = url.searchParams.get("code_challenge") ?? "";
  const callback = url.searchParams.get("redirect_uri") ?? "";
  if (!validRedirect(env, callback) || !validSecret(state) || !validSecret(challenge) || url.searchParams.get("code_challenge_method") !== "S256") return reply({ error: "invalid_login" }, 400);
  if (!(await consumeLoginRate(env, request))) return limited();
  const id = randomSecret();
  const name = (url.searchParams.get("name") ?? "still.fail").slice(0, 80);
  return env.LOGINS.getByName(id).start(id, { redirect: callback, state, challenge, name }, provider);
}

async function sha256Hex(value: string): Promise<string> {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return [...hash].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function consumeLoginRate(env: Env, request: Request): Promise<boolean> {
  const ip = request.headers.get("cf-connecting-ip") ?? "local";
  return env.LOGIN_LIMITS.getByName(await digest(`${env.AUTH_SIGNING_KEY}:${ip}`)).consume();
}

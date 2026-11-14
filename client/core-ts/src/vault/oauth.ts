// A service's sign-in as its person, kept as an item of their vault (the user, 2026-11-14: 「类似别的 app 的 slack oauth
// 绑定」, 「用的是用户的身份」, 「放到密钥库里支持」): the person presses 添加 → Slack 账号, signs in on the service's own
// page, and their user token is written into their vault as a token an agent asks for and is given through the proxy,
// to the service's hosts alone, as any token the person kept by hand.
//
// OAuth 2 with PKCE as a public client (RFC 7636; Slack's since 2026-03): no client secret anywhere, the code changed
// for the token here, on the device that began it, which alone holds the verifier. Nothing passes through still.fail
// cloud or a station: the browser comes back to the web's page `/vault/oauth` (an https address, so the service gives a
// token that does not expire: Slack gives one that rotates to an app's own scheme or a loopback address), which only
// hands the query on to where the sign-in began (`back` in its state):
//   web                                 this page itself: its core completes it (the web's tabs share one database)
//   <scheme>                            the app's browser session (ASWebAuthenticationSession, a Custom Tab), at
//                                       `<scheme>://auth/vault?<query>`
//   http://127.0.0.1:<port>/<path>      the app's browser login (macOS, Windows, Linux), `<that>?<query>`
// The state is base64url of `{"n": nonce, "w": workspace, "b": back}` (web/src/pages/vault-oauth.tsx reads it the
// same way): the nonce finds what began it here, the rest is only where to go. What began is kept on the device
// (`prefs` `vaultOauth`) an hour at most, so an app the system stopped while the browser was up finishes it as it is
// started again.
import { Effect } from "effect";
import { sha256 } from "@noble/hashes/sha2.js";
import type { Inner } from "../core.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { encodeComponent, parseQuery } from "../accounts.ts";
import { base64url, fromBase64, fromUtf8, isObject, utf8 } from "../util.ts";

/// A service a person signs in to as themselves.
export type Provider = {
  id: string;
  /// Its name, as the item's begins.
  name: string;
  authorize: string;
  token: string;
  /// Its public client's id (no secret: PKCE); "" while it has none, the provider then not offered.
  clientId: string;
  /// Asked of the person, as the service's page lists them.
  scopes: string[];
  /// Where its token is sent (the proxy's hosts).
  hosts: string[];
};

/// Slack's app for people's own tokens (made from the manifest in its AGENTS.md entry: user scopes only, PKCE on,
/// token rotation off, distributed publicly), not any connect's bot.
export const SLACK: Provider = {
  id: "slack",
  name: "Slack",
  authorize: "https://slack.com/oauth/v2/authorize",
  token: "https://slack.com/api/oauth.v2.access",
  clientId: "9697294749841.12598696506197",
  scopes: [
    "search:read",
    "channels:history",
    "groups:history",
    "im:history",
    "mpim:history",
    "channels:read",
    "groups:read",
    "im:read",
    "mpim:read",
    "users:read",
    "users:read.email",
    "chat:write",
    "reactions:read",
    "reactions:write",
    "files:read",
  ],
  hosts: ["slack.com"],
};

export const PROVIDERS: Provider[] = [SLACK];

/// The web's page the services send the browser back to.
export const OAUTH_PATH = "/vault/oauth";
/// How long what began waits for the browser to come back.
export const OAUTH_WAIT_MS = 60 * 60 * 1000;
/// At most so many begun at once (the oldest let go).
const PENDING_MOST = 8;

/// What began here: into which vault, or for which agent's request to keep it (secret_save `oauth`: its card), by the
/// verifier its challenge was made of.
type Pending = { ws: string; vault: string; request?: string; provider: string; verifier: string; state: string; at: number };

export const providerOf = (id: string): Provider | undefined => PROVIDERS.find((p) => p.id === id && p.clientId !== "");

/// Where the browser is to be handed on to, said as `back`: "web", an app's scheme, or a loopback address. Anything else
/// is refused, so that no state sends a code elsewhere.
export function backOk(back: string): boolean {
  if (back === "web") return true;
  if (/^http:\/\/127\.0\.0\.1:\d{1,5}\/[\w/.-]*$/.test(back)) return true;
  return /^[a-z][a-z0-9.+-]*$/.test(back) && !["http", "https", "javascript", "data", "file", "blob", "about"].includes(back);
}

export function stateText(nonce: string, ws: string, back: string): string {
  return base64url(utf8(JSON.stringify({ n: nonce, w: ws, b: back })));
}

export function stateOf(state: string): { n: string; w: string; b: string } | null {
  try {
    const padded = state.replace(/-/g, "+").replace(/_/g, "/");
    const bytes = fromBase64(padded + "=".repeat((4 - (padded.length % 4)) % 4));
    if (bytes === null) return null;
    const v: unknown = JSON.parse(fromUtf8(bytes));
    if (!isObject(v) || typeof v.n !== "string" || typeof v.w !== "string" || typeof v.b !== "string" || !backOk(v.b)) return null;
    return { n: v.n, w: v.w, b: v.b };
  } catch {
    return null;
  }
}

/// Where a browser that came back with `query` is handed on to (`back` not "web"); null for the web's own.
export function handedTo(back: string, query: string): string | null {
  if (back === "web" || !backOk(back)) return null;
  return back.startsWith("http://") ? `${back}?${query}` : `${back}://auth/vault?${query}`;
}

function pendingAll(inner: Inner): Record<string, Pending> {
  const v = inner.data.device.get("prefs", "vaultOauth");
  return isObject(v) ? (v as Record<string, Pending>) : {};
}

function keepPending(inner: Inner, all: Record<string, Pending>): void {
  const now = inner.host.nowMs();
  const kept = Object.entries(all)
    .filter(([, p]) => now - p.at < OAUTH_WAIT_MS)
    .sort((a, b) => b[1].at - a[1].at)
    .slice(0, PENDING_MOST);
  inner.data.device.put("prefs", "vaultOauth", Object.fromEntries(kept));
}

/// An application/x-www-form-urlencoded text (by hand: Hermes has no URLSearchParams).
const form = (fields: Record<string, string>) =>
  Object.entries(fields)
    .map(([k, v]) => `${encodeComponent(k)}=${encodeComponent(v)}`)
    .join("&");

const fail = (code: string, message: string) => Effect.fail(new CoreError(code, message));

/// The service's sign-in page for the person to sign in on, into `vault` (or the plain library), or for an agent's
/// request to keep one (`request`: its card, approved with the token as typed in), coming back to `back`.
export function begin(inner: Inner, ws: string, vault: string, provider: string, back: string, request = ""): Effect.Effect<{ url: string }, CoreError> {
  return Effect.gen(function* () {
    const p = providerOf(provider);
    if (!p) return yield* fail("vault_oauth_unknown", t("core-misc.vault.oauth.unknown"));
    if (!backOk(back)) return yield* Effect.fail(CoreError.invalid("back: web, an app's scheme or a loopback address"));
    const random = (n: number) => {
      const b = new Uint8Array(n);
      inner.host.randomBytes(b);
      return base64url(b);
    };
    const nonce = random(16);
    const verifier = random(32);
    const state = stateText(nonce, ws, back);
    const query = form({
      client_id: p.clientId,
      user_scope: p.scopes.join(","),
      redirect_uri: inner.host.cloudOrigin() + OAUTH_PATH,
      state,
      code_challenge: base64url(sha256(utf8(verifier))),
      code_challenge_method: "S256",
    });
    keepPending(inner, { ...pendingAll(inner), [nonce]: { ws, vault, ...(request ? { request } : {}), provider: p.id, verifier, state, at: inner.host.nowMs() } });
    return { url: `${p.authorize}?${query}` };
  });
}

/// What the browser came back with (its query): the code changed for the person's token, kept by `write` as the
/// vault's editor keeps a token, given to agents through the proxy to the service's hosts alone; or, begun for an
/// agent's request, its card approved with it (`approve`: the request's name, hosts and grant, as one typed in).
export function complete(
  inner: Inner,
  ws: string,
  query: string,
  write: (vault: string, plain: unknown, listing: unknown) => Effect.Effect<unknown, CoreError>,
  approve: (request: string, token: string) => Effect.Effect<unknown, CoreError>,
): Effect.Effect<{ name: string }, CoreError> {
  return Effect.gen(function* () {
    const pairs = parseQuery(query);
    const q = { get: (name: string) => pairs.find(([k]) => k === name)?.[1] ?? null };
    const state = q.get("state") ?? "";
    const said = stateOf(state);
    const all = pendingAll(inner);
    const began = said ? all[said.n] : undefined;
    if (q.get("error") === "access_denied") {
      if (said) keepPending(inner, Object.fromEntries(Object.entries(all).filter(([n]) => n !== said.n)));
      return yield* fail("cancelled", t("core-misc.vault.oauth.denied"));
    }
    if (!said || !began || began.state !== state || began.ws !== ws || inner.host.nowMs() - began.at >= OAUTH_WAIT_MS) return yield* fail("vault_oauth_stale", t("core-misc.vault.oauth.stale"));
    // (used once, whatever comes of it)
    keepPending(inner, Object.fromEntries(Object.entries(all).filter(([n]) => n !== said.n)));
    const p = providerOf(began.provider);
    const code = q.get("code") ?? "";
    if (!p || code === "") return yield* fail("vault_oauth_failed", t("core-misc.vault.oauth.failed", { why: q.get("error") ?? "" }));
    const body = form({ client_id: p.clientId, code, code_verifier: began.verifier, redirect_uri: inner.host.cloudOrigin() + OAUTH_PATH });
    const res = yield* Effect.mapError(
      inner.host.fetch({ method: "POST", url: p.token, headers: [["content-type", "application/x-www-form-urlencoded"]], body: utf8(body) }),
      (e) => new CoreError("vault_oauth_failed", t("core-misc.vault.oauth.failed", { why: e.message })),
    );
    const answer = yield* Effect.try({ try: () => JSON.parse(fromUtf8(res.body)) as unknown, catch: () => new CoreError("vault_oauth_failed", t("core-misc.vault.oauth.failed", { why: `HTTP ${res.status}` })) });
    const got = slackAnswer(answer);
    if (typeof got === "string") return yield* fail("vault_oauth_failed", t("core-misc.vault.oauth.failed", { why: got }));
    const who = yield* Effect.orElseSucceed(slackWho(inner, got.token), () => null);
    const name = `${p.name} · ${got.team}${who ? ` · ${who}` : ""}`;
    if (began.request) {
      yield* approve(began.request, got.token);
      return { name };
    }
    const about = t("core-misc.vault.oauth.about", { service: p.name, team: got.team, who: who ?? got.user, hosts: p.hosts.join(", ") });
    yield* write(began.vault, { kind: "token", name, fields: { value: got.token }, notes: about }, { name, about, kind: "token", modes: ["proxy"], hosts: p.hosts });
    return { name };
  });
}

/// Slack's `oauth.v2.access` answer: the person's token, their id and their Slack workspace's name; else why not.
export function slackAnswer(v: unknown): { token: string; user: string; team: string } | string {
  if (!isObject(v)) return "not JSON";
  if (v.ok !== true) return typeof v.error === "string" ? v.error : "not ok";
  const user = isObject(v.authed_user) ? v.authed_user : null;
  const token = user && typeof user.access_token === "string" ? user.access_token : "";
  if (token === "") return "no user token";
  const team = isObject(v.team) && typeof v.team.name === "string" ? v.team.name : "";
  return { token, user: user && typeof user.id === "string" ? user.id : "", team };
}

/// Who the token is of, as Slack names them (`auth.test`'s `user`).
function slackWho(inner: Inner, token: string): Effect.Effect<string | null, unknown> {
  return Effect.map(inner.host.fetch({ method: "POST", url: "https://slack.com/api/auth.test", headers: [["authorization", `Bearer ${token}`]], body: null }), (res) => {
    const v: unknown = JSON.parse(fromUtf8(res.body));
    return isObject(v) && v.ok === true && typeof v.user === "string" ? v.user : null;
  });
}

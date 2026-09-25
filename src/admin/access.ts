// Who may use the admin page. The admin server listens on loopback, so a
// request is either local (trusted) or came through a Cloudflare tunnel, which
// cloudflared also delivers from loopback. Cloudflare's edge always adds
// cf-connecting-ip, and a client cannot strip it; such requests must carry a
// valid Cloudflare Access JWT, verified here against the team's signing keys.
// Without Access configured, tunneled requests are refused: a missing Access
// policy must not leave the admin page open.
import { createPublicKey, verify as verifySignature, type JsonWebKey, type KeyObject } from "node:crypto";
import type { IncomingMessage } from "node:http";

export interface AccessConfig {
  /** e.g. "afk" for afk.cloudflareaccess.com */
  teamDomain: string;
  /** The Access application's AUD tag. */
  aud: string;
}

export type Viewer = { via: "local" } | { via: "access"; email: string };

export class AccessDenied extends Error {}

type FetchJwks = (url: string) => Promise<{ keys: (JsonWebKey & { kid?: string })[] }>;

const defaultFetch: FetchJwks = async (url) => {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`fetching Access keys failed: ${response.status}`);
  return await response.json() as { keys: (JsonWebKey & { kid?: string })[] };
};

function base64url(text: string): Buffer {
  return Buffer.from(text, "base64url");
}

export class AccessGate {
  readonly #config: () => AccessConfig | null;
  readonly #fetch: FetchJwks;
  #keys = new Map<string, KeyObject>();
  #keysFor = "";
  #fetchedAt = 0;

  constructor(config: () => AccessConfig | null, fetchJwks: FetchJwks = defaultFetch) {
    this.#config = config;
    this.#fetch = fetchJwks;
  }

  /** Resolves the viewer or throws AccessDenied. */
  async check(req: IncomingMessage): Promise<Viewer> {
    if (req.headers["cf-connecting-ip"] === undefined && req.headers["cf-ray"] === undefined) return { via: "local" };
    const config = this.#config();
    if (!config) throw new AccessDenied("通过公网访问需要先在 ember 配置 Cloudflare Access（admin.access.teamDomain 和 aud）");
    const token = String(req.headers["cf-access-jwt-assertion"] ?? "");
    if (!token) throw new AccessDenied("缺少 Cloudflare Access 凭证");
    return { via: "access", email: await this.#verify(token, config) };
  }

  async #verify(token: string, config: AccessConfig): Promise<string> {
    const [head, body, signature] = token.split(".");
    if (!head || !body || !signature) throw new AccessDenied("Access 凭证格式不对");
    let header: { alg?: string; kid?: string };
    let claims: { aud?: string | string[]; iss?: string; exp?: number; nbf?: number; email?: string };
    try {
      header = JSON.parse(base64url(head).toString("utf8"));
      claims = JSON.parse(base64url(body).toString("utf8"));
    } catch {
      throw new AccessDenied("Access 凭证无法解析");
    }
    if (header.alg !== "RS256" || !header.kid) throw new AccessDenied("Access 凭证的签名算法不对");
    const key = await this.#key(header.kid, config);
    if (!key || !verifySignature("RSA-SHA256", Buffer.from(`${head}.${body}`), key, base64url(signature))) {
      throw new AccessDenied("Access 凭证签名无效");
    }
    const now = Date.now() / 1000;
    const issuer = `https://${config.teamDomain}.cloudflareaccess.com`;
    const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    if (claims.iss !== issuer) throw new AccessDenied("Access 凭证来自别的团队");
    if (!audiences.includes(config.aud)) throw new AccessDenied("Access 凭证不属于这个应用");
    if (typeof claims.exp !== "number" || claims.exp < now - 30) throw new AccessDenied("Access 凭证已过期");
    if (typeof claims.nbf === "number" && claims.nbf > now + 30) throw new AccessDenied("Access 凭证还未生效");
    if (!claims.email) throw new AccessDenied("Access 凭证里没有邮箱");
    return claims.email;
  }

  /** Signing keys are cached; an unknown kid (key rotation) refetches at most once a minute. */
  async #key(kid: string, config: AccessConfig): Promise<KeyObject | undefined> {
    const url = `https://${config.teamDomain}.cloudflareaccess.com/cdn-cgi/access/certs`;
    const stale = this.#keysFor !== url || (!this.#keys.has(kid) && Date.now() - this.#fetchedAt > 60_000);
    if (stale) {
      const { keys } = await this.#fetch(url);
      this.#keys = new Map(keys.filter((k) => k.kid).map((k) => [k.kid!, createPublicKey({ key: k, format: "jwk" })]));
      this.#keysFor = url;
      this.#fetchedAt = Date.now();
    }
    return this.#keys.get(kid);
  }
}

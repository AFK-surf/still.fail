// Who may use the admin page. The admin server listens on loopback, so a
// request is local (trusted), came through ember-mesh from ember cloud (it
// carries the viewer ember-mesh verified), or came through a Cloudflare tunnel, which
// cloudflared also delivers from loopback. Cloudflare's edge always adds
// cf-connecting-ip, and a client cannot strip it; such requests must carry a
// valid Cloudflare Access JWT, verified here against the team's signing keys.
// Without Access configured, tunneled requests are refused: a missing Access
// policy must not leave the admin page open.
import { createPublicKey, timingSafeEqual, verify as verifySignature, type JsonWebKey, type KeyObject } from "node:crypto";
import type { IncomingMessage } from "node:http";

export interface AccessConfig {
  /** e.g. "afk" for afk.cloudflareaccess.com */
  teamDomain: string;
  /** The Access application's AUD tag. */
  aud: string;
}

/** A person reaching the station through ember cloud; ember-mesh verified their grant. */
export interface MeshViewer { via: "mesh"; sub: string; email: string; name: string; role: string; workspace: string; device: string }

export type Viewer = { via: "local" } | { via: "access"; email: string } | MeshViewer;

/** Who did something, for people: a name, else the email. */
export function viewerName(viewer: Viewer): string {
  return viewer.via === "local" ? "本机管理页" : viewer.via === "mesh" ? viewer.name || viewer.email : viewer.email;
}

/** Who did something, for logs and records: an email, or "local" on the station itself. */
export function viewerId(viewer: Viewer): string {
  return viewer.via === "local" ? "local" : viewer.email;
}

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

  readonly #meshSecret: () => string | null;

  /** `meshSecret` is what ember-mesh sends to prove a request came through it. */
  constructor(config: () => AccessConfig | null, fetchJwks: FetchJwks = defaultFetch, meshSecret: () => string | null = () => null) {
    this.#config = config;
    this.#fetch = fetchJwks;
    this.#meshSecret = meshSecret;
  }

  /** Resolves the viewer or throws AccessDenied. */
  async check(req: IncomingMessage): Promise<Viewer> {
    const mesh = req.headers["x-ember-mesh"];
    if (mesh !== undefined) return this.#mesh(req, String(mesh));
    if (req.headers["cf-connecting-ip"] === undefined && req.headers["cf-ray"] === undefined) return { via: "local" };
    const config = this.#config();
    if (!config) throw new AccessDenied("通过公网访问需要先在 ember 配置 Cloudflare Access（admin.access.teamDomain 和 aud）");
    const token = String(req.headers["cf-access-jwt-assertion"] ?? "");
    if (!token) throw new AccessDenied("缺少 Cloudflare Access 凭证");
    return { via: "access", email: await this.#verify(token, config) };
  }

  #mesh(req: IncomingMessage, supplied: string): MeshViewer {
    const secret = this.#meshSecret();
    const remote = req.socket.remoteAddress ?? "";
    const loopback = remote === "127.0.0.1" || remote === "::1" || remote === "::ffff:127.0.0.1";
    if (!secret || !loopback || supplied.length !== secret.length || !timingSafeEqual(Buffer.from(supplied), Buffer.from(secret))) {
      throw new AccessDenied("mesh 请求无效");
    }
    try {
      const v = JSON.parse(Buffer.from(String(req.headers["x-ember-viewer"] ?? ""), "base64url").toString("utf8")) as Record<string, unknown>;
      const text = (k: string) => (typeof v[k] === "string" ? v[k] as string : "");
      if (!text("email") || !text("sub")) throw new Error("incomplete");
      return { via: "mesh", sub: text("sub"), email: text("email"), name: text("name"), role: text("role"), workspace: text("workspace"), device: text("device") };
    } catch {
      throw new AccessDenied("mesh 请求缺少身份");
    }
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

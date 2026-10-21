// Feishu's OpenAPI over HTTP (docs/feishu.md): one client per app, with its tenant_access_token got from the app's id
// and secret and taken again before it runs out. Feishu (open.feishu.cn) or Lark (open.larksuite.com), or a stand-in
// for tests ($STILLFAIL_FEISHU_API, one address for both).
import { wall } from "../ops/fibers.ts";

type Json = any;

export type Domain = "feishu" | "lark";

export const OPEN: Record<Domain, string> = { feishu: "https://open.feishu.cn", lark: "https://open.larksuite.com" };
/// Where apps are made by a scan (the registration's device flow).
export const ACCOUNTS: Record<Domain, string> = { feishu: "https://accounts.feishu.cn", lark: "https://accounts.larksuite.com" };

export const domainOf = (v: unknown): Domain => (v === "lark" ? "lark" : "feishu");

/// The OpenAPI's address: the stand-in when there is one.
export const openBase = (domain: Domain): string => process.env.STILLFAIL_FEISHU_API || OPEN[domain];
export const accountsBase = (domain: Domain): string => process.env.STILLFAIL_FEISHU_API || ACCOUNTS[domain];

/// Feishu said no: its code and words.
export class FeishuError extends Error {
  readonly code: number;
  constructor(what: string, code: number, msg: string) {
    super(`feishu ${what}: ${code} ${msg}`);
    this.code = code;
  }
}

/// Feishu's codes for too many calls: waited out, like Slack's 429.
const LIMITED = new Set([99991400, 11232, 230020]);
const RETRIES = 4;

/// A file sent with a call (multipart).
export type FilePart = { field: string; bytes: Uint8Array; name: string; mime: string };

export class FeishuClient {
  readonly base: string;
  readonly appId: string;
  private appSecret: string;
  private token: { value: string; until: number } | null = null;
  private fetching: Promise<string> | null = null;

  constructor(appId: string, appSecret: string, domain: Domain = "feishu", base: string = openBase(domain)) {
    this.appId = appId;
    this.appSecret = appSecret;
    this.base = base.replace(/\/+$/, "");
  }

  /// The app's tenant_access_token, taken again ten minutes before it runs out (Feishu gives two hours).
  async tenantToken(): Promise<string> {
    if (this.token && wall.now() < this.token.until) return this.token.value;
    if (this.fetching) return this.fetching;
    this.fetching = (async () => {
      try {
        const body = await this.raw("POST", "/open-apis/auth/v3/tenant_access_token/internal", { app_id: this.appId, app_secret: this.appSecret }, null);
        const value = typeof body?.tenant_access_token === "string" ? body.tenant_access_token : "";
        if (value === "") throw new Error("feishu gave no tenant_access_token");
        const expire = typeof body?.expire === "number" ? body.expire : 7200;
        this.token = { value, until: wall.now() + Math.max(60, expire - 600) * 1000 };
        return value;
      } finally {
        this.fetching = null;
      }
    })();
    return this.fetching;
  }

  /// A call as Feishu answers it: its JSON with code 0, else a FeishuError. `body` is JSON (or multipart with `files`);
  /// `query` goes in the address. Rate limits are waited out.
  private async raw(method: string, path: string, body: Json | null, token: string | null, query?: Record<string, string>, files?: FilePart[]): Promise<Json> {
    const url = new URL(this.base + path);
    for (const [k, v] of Object.entries(query ?? {})) url.searchParams.set(k, v);
    for (let attempt = 0; ; attempt++) {
      const headers: Record<string, string> = token !== null ? { authorization: `Bearer ${token}` } : {};
      let payload: string | FormData | undefined;
      if (files && files.length > 0) {
        const form = new FormData();
        for (const [k, v] of Object.entries(body ?? {})) form.append(k, typeof v === "string" ? v : JSON.stringify(v));
        for (const f of files) form.append(f.field, new Blob([f.bytes as Uint8Array<ArrayBuffer>], { type: f.mime }), f.name);
        payload = form;
      } else if (body !== null && method !== "GET") {
        headers["content-type"] = "application/json; charset=utf-8";
        payload = JSON.stringify(body);
      }
      const response = await fetch(url, { method, headers, body: payload, signal: AbortSignal.timeout(files ? 300_000 : 30_000) });
      const text = await response.text();
      let data: Json = null;
      try {
        data = text === "" ? {} : JSON.parse(text);
      } catch {
        throw new FeishuError(`${method} ${path}`, response.status, text.slice(0, 200));
      }
      const code = typeof data?.code === "number" ? data.code : response.ok ? 0 : response.status;
      if ((response.status === 429 || LIMITED.has(code)) && attempt < RETRIES) {
        const said = Number(response.headers.get("x-ogw-ratelimit-reset") ?? response.headers.get("retry-after") ?? "1");
        await wall.sleep((Number.isFinite(said) && said > 0 ? Math.min(said, 30) : 1) * 1000);
        continue;
      }
      if (code !== 0) throw new FeishuError(`${method} ${path}`, code, typeof data?.msg === "string" ? data.msg : `HTTP ${response.status}`);
      return data;
    }
  }

  /// An OpenAPI call as the app (its tenant token): Feishu's whole answer (`{code, msg, data}`).
  async api(method: string, path: string, body: Json | null = null, query?: Record<string, string>, files?: FilePart[]): Promise<Json> {
    const token = await this.tenantToken();
    try {
      return await this.raw(method, path, body, token, query, files);
    } catch (error) {
      // A token Feishu stopped taking (the secret changed, say): once more with a new one.
      if (error instanceof FeishuError && (error.code === 99991663 || error.code === 99991661)) {
        this.token = null;
        return this.raw(method, path, body, await this.tenantToken(), query, files);
      }
      throw error;
    }
  }

  /// A message's file or image (`GET /im/v1/messages/:id/resources/:key`): its bytes.
  async resource(messageId: string, key: string, type: "image" | "file"): Promise<Uint8Array> {
    const url = new URL(`${this.base}/open-apis/im/v1/messages/${encodeURIComponent(messageId)}/resources/${encodeURIComponent(key)}`);
    url.searchParams.set("type", type);
    const got = await fetch(url, { headers: { authorization: `Bearer ${await this.tenantToken()}` }, signal: AbortSignal.timeout(120_000) });
    if (!got.ok || (got.headers.get("content-type") ?? "").startsWith("application/json")) {
      const said = await got.text().catch(() => "");
      let msg = `HTTP ${got.status}`;
      try {
        const j = JSON.parse(said);
        if (typeof j?.msg === "string") msg = `${j.code} ${j.msg}`;
      } catch {}
      throw new Error(`feishu resource: ${msg}`);
    }
    return new Uint8Array(await got.arrayBuffer());
  }

  /// The long connection's address and its pings' interval (`POST /callback/ws/endpoint`).
  async endpoint(): Promise<{ url: string; pingMs: number }> {
    const data = await this.raw("POST", "/callback/ws/endpoint", { AppID: this.appId, AppSecret: this.appSecret }, null);
    const url = data?.data?.URL;
    if (typeof url !== "string" || url === "") throw new Error("feishu gave no long connection address");
    const ping = data?.data?.ClientConfig?.PingInterval;
    return { url, pingMs: (typeof ping === "number" && ping > 0 ? ping : 120) * 1000 };
  }
}

// X's API v2 over HTTP (docs/x.md): one client per connect, signing each call as its bot's account with OAuth 1.0a
// (the app's consumer key and secret, the account's access token and secret: they do not run out). api.x.com, or a
// stand-in for tests ($STILLFAIL_X_API).
import { createHmac, randomBytes } from "node:crypto";
import { wall } from "../ops/fibers.ts";

type Json = any;

export const API = "https://api.x.com";

/// The API's address: the stand-in when there is one.
export const apiBase = (): string => process.env.STILLFAIL_X_API || API;

/// What a connect signs its calls with.
export type XKeys = { consumerKey: string; consumerSecret: string; accessToken: string; accessSecret: string };

/// X said no: its HTTP status and words.
export class XError extends Error {
  readonly status: number;
  constructor(what: string, status: number, said: string) {
    super(`x ${what}: ${status} ${said}`.trim());
    this.status = status;
  }
}

/// RFC 3986's percent-encoding, as OAuth 1.0a signs (encodeURIComponent leaves !'()* alone).
const enc = (s: string) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

/// The Authorization header of one call (RFC 5849): its query (and none of a JSON or multipart body) signed with HMAC-SHA1.
export function oauthHeader(keys: XKeys, method: string, url: URL, at: { nonce: string; timestamp: number }): string {
  const oauth: Record<string, string> = {
    oauth_consumer_key: keys.consumerKey,
    oauth_nonce: at.nonce,
    oauth_signature_method: "HMAC-SHA1",
    oauth_timestamp: String(at.timestamp),
    oauth_token: keys.accessToken,
    oauth_version: "1.0",
  };
  const pairs: [string, string][] = [...Object.entries(oauth), ...url.searchParams.entries()].map(([k, v]) => [enc(k), enc(v)]);
  pairs.sort(([a, x], [b, y]) => (a < b ? -1 : a > b ? 1 : x < y ? -1 : x > y ? 1 : 0));
  const base = [method.toUpperCase(), enc(`${url.origin}${url.pathname}`), enc(pairs.map(([k, v]) => `${k}=${v}`).join("&"))].join("&");
  const signature = createHmac("sha1", `${enc(keys.consumerSecret)}&${enc(keys.accessSecret)}`).update(base).digest("base64");
  return `OAuth ${Object.entries({ ...oauth, oauth_signature: signature })
    .map(([k, v]) => `${enc(k)}="${enc(v)}"`)
    .join(", ")}`;
}

const RETRIES = 3;

/// A file sent with a call (multipart).
export type FilePart = { field: string; bytes: Uint8Array; name: string; mime: string };

export class XClient {
  readonly base: string;
  private keys: XKeys;

  constructor(keys: XKeys, base: string = apiBase()) {
    this.keys = keys;
    this.base = base.replace(/\/+$/, "");
  }

  /// A call as X answers it: its JSON (whose `errors` may say what it could not give), else an XError. `body` is JSON
  /// (or multipart fields with `files`); `query` goes in the address. Rate limits are waited out, up to a minute.
  async api(method: string, path: string, body: Json | null = null, query?: Record<string, string>, files?: FilePart[]): Promise<Json> {
    const url = new URL(this.base + path);
    for (const [k, v] of Object.entries(query ?? {})) url.searchParams.set(k, v);
    for (let attempt = 0; ; attempt++) {
      const headers: Record<string, string> = { authorization: oauthHeader(this.keys, method, url, { nonce: randomBytes(16).toString("hex"), timestamp: Math.floor(wall.now() / 1000) }) };
      let payload: string | FormData | undefined;
      if (files && files.length > 0) {
        const form = new FormData();
        for (const [k, v] of Object.entries(body ?? {})) form.append(k, typeof v === "string" ? v : JSON.stringify(v));
        for (const f of files) form.append(f.field, new Blob([f.bytes as Uint8Array<ArrayBuffer>], { type: f.mime }), f.name);
        payload = form;
      } else if (body !== null && method !== "GET") {
        headers["content-type"] = "application/json";
        payload = JSON.stringify(body);
      }
      const response = await fetch(url, { method, headers, body: payload, signal: AbortSignal.timeout(files ? 300_000 : 30_000) });
      const text = await response.text();
      let data: Json = null;
      try {
        data = text === "" ? {} : JSON.parse(text);
      } catch {
        throw new XError(`${method} ${path}`, response.status, text.slice(0, 200));
      }
      if (response.status === 429 && attempt < RETRIES) {
        // x-rate-limit-reset: when the window opens again, in epoch seconds.
        const reset = Number(response.headers.get("x-rate-limit-reset") ?? "");
        const wait = Number.isFinite(reset) && reset > 0 ? reset * 1000 - wall.now() : 1000;
        if (wait <= 60_000) {
          await wall.sleep(Math.max(1000, wait));
          continue;
        }
      }
      if (!response.ok) throw new XError(`${method} ${path}`, response.status, saidOf(data) || `HTTP ${response.status}`);
      return data;
    }
  }
}

/// What an X error answer says: its title and detail, or its errors' messages.
export function saidOf(data: Json): string {
  const parts = [data?.title, data?.detail].filter((v) => typeof v === "string" && v !== "");
  if (parts.length > 0) return parts.join(": ");
  const errors = Array.isArray(data?.errors) ? data.errors : [];
  return errors
    .map((e: Json) => (typeof e?.detail === "string" ? e.detail : typeof e?.message === "string" ? e.message : ""))
    .filter((s: string) => s !== "")
    .join("; ");
}

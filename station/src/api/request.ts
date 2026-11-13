// A request to the admin API as the station takes it from the mesh (or another door), and its answer.
import type { Viewer } from "../mesh/credential.ts";
import type { Answer } from "../mesh/wire.ts";
import { type Lang, langOf } from "../ops/i18n.ts";

export type Request = {
  method: string;
  /// After /admin/api, without the query.
  path: string;
  query: [string, string][];
  /// The query as asked (`?…`, or empty): what a preview passes on as it is.
  search?: string;
  headers: Record<string, string>;
  body: Buffer;
  viewer: Viewer;
  lang: Lang;
  /// Read in the background (a part of POST /batch: the history a client brings onto its device): after every other read
  /// waiting, one at a time (read/pool.ts).
  background?: boolean;
  /// The device no longer waits for this request (only reads use it).
  signal?: AbortSignal;
};

/// Its answer, as the mesh's wire writes it (mesh/wire.ts `send`).
export type { Answer };

/// The language a core asks in: its `stillfail-lang`; Chinese for a core from before languages.
export function langOfCore(headers: Record<string, string>): Lang {
  const said = Object.entries(headers).find(([k]) => k.toLowerCase() === "stillfail-lang");
  return said ? langOf(said[1]) : "zh";
}

/// admin/mod.rs `percent_decode`: `%xx` a byte, `+` a space, the rest as it is; then UTF-8, lossily.
export function percentDecode(s: string): string {
  const bytes = Buffer.from(s, "utf8");
  const out: number[] = [];
  for (let i = 0; i < bytes.length; ) {
    const hex = bytes.subarray(i + 1, i + 3).toString("latin1");
    if (bytes[i] === 0x25 && /^[0-9a-fA-F]{2}$/.test(hex)) {
      out.push(parseInt(hex, 16));
      i += 3;
    } else {
      out.push(bytes[i] === 0x2b ? 0x20 : bytes[i]);
      i += 1;
    }
  }
  return new TextDecoder("utf-8").decode(Buffer.from(out));
}

/// admin/mod.rs `query_pairs`.
export const queryPairs = (query: string): [string, string][] =>
  query
    .split("&")
    .filter((p) => p !== "")
    .map((p) => {
      const at = p.indexOf("=");
      return at < 0 ? [percentDecode(p), ""] : [percentDecode(p.slice(0, at)), percentDecode(p.slice(at + 1))];
    });

/// The first value of a name, as `Asked::param` has it.
export const param = (r: Request, name: string) => r.query.find(([k]) => k === name)?.[1];

const JSON_HEADERS = { "content-type": "application/json", "cache-control": "no-store" };

export const json = (status: number, text: string): Answer => ({ status, headers: { ...JSON_HEADERS }, body: Buffer.from(text) });
export const error = (status: number, message: string): Answer => json(status, JSON.stringify({ error: message }));

/// A path segment as the pages send it (a + is a +).
export const segment = (s: string) => percentDecode(s.replace(/\+/g, "%2B"));

/// A value answered as JSON.
export const ok = (value: unknown, status = 200) => json(status, JSON.stringify(value));

/// What a request is refused, and with which status (admin/mod.rs `http_error`): every route's, and the stores'
/// readers' (read/views.ts HttpError).
export class Refused extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

/// A request's JSON object (`read_json`): nothing is `{}`, as is anything not an object; more than a megabyte refused.
export function input(r: Request): Record<string, any> {
  if (r.body.length > 1_000_000) throw new Refused(413, "request too large");
  if (r.body.length === 0) return {};
  let value: unknown;
  try {
    value = JSON.parse(r.body.toString("utf8"));
  } catch {
    throw new Refused(400, "invalid JSON");
  }
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, any>) : {};
}

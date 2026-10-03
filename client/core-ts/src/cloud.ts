// still.fail cloud's account API, called as one of the signed-in accounts (cloud.rs). Errors come back as
// {error: code}; the codes and their words mirror web/src/cloud/api.ts.
import { encodeComponent, type Accounts } from "./accounts.ts";
import * as brand from "./brand.ts";
import { CoreError, asCoreError } from "./error.ts";
import type { Host, HttpResponse } from "./host.ts";
import { t } from "./i18n.ts";
import { CLOUD, cloudWhat, type Status } from "./status.ts";
import { Kind, route, type SpanContext, type Tracer } from "./trace.ts";
import { isObject, parseJson, toJsonBytes } from "./util.ts";

/// A member credential for this device (POST /v1/workspaces/:ws/credential {device}): valid until `expires_at` (s).
export type Credential = { credential: string; issued_at: number; expires_at: number; relay_url: string };

/// still.fail cloud's answer to a beta app used by an account not let into the beta.
export const NOT_BETA = "not_beta";

export function notBetaText(): string {
  return t("core-misc.cloud.not_beta");
}

export class Cloud {
  readonly #host: Host;
  readonly #accounts: Accounts;
  readonly #tracer: Tracer;
  readonly #status: Status;

  constructor(host: Host, accounts: Accounts, tracer: Tracer, status: Status) {
    this.#host = host;
    this.#accounts = accounts;
    this.#tracer = tracer;
    this.#status = status;
  }

  /// One call as `sub`: adds the token (refreshing it), parses JSON, maps errors to CoreError with the cloud's code.
  /// Under a trace (`ctx`) it is a span of it, and says so to still.fail cloud with a `traceparent`.
  async request(sub: string, method: string, path: string, body: unknown, ctx?: SpanContext | null): Promise<unknown> {
    const token = await this.#accounts.accessToken(sub);
    const headers: [string, string][] = [["authorization", `Bearer ${token}`]];
    const channel = channelHeader(this.#host);
    if (channel) headers.push(channel);
    if (body !== undefined && body !== null) headers.push(["content-type", "application/json"]);
    const span = this.#tracer.child(`${method} ${route(path)}`, Kind.Client, ctx);
    if (span) {
      span.set("http.request.method", method);
      span.set("url.path", route(path));
      headers.push(["traceparent", span.context.traceparent()]);
    }
    const waiting = this.#status.begin(CLOUD, cloudWhat(method, path), false);
    let response: HttpResponse;
    try {
      response = await this.#host.fetch({ method, url: `${this.#host.cloudOrigin()}${path}`, headers, body: body === undefined || body === null ? null : toJsonBytes(body) });
      waiting.received(response.body.length);
    } catch (e) {
      waiting.end();
      if (span) {
        span.fail();
        span.end();
      }
      throw asCoreError(e);
    }
    waiting.end();
    if (span) {
      span.set("http.response.status_code", response.status);
      span.set("http.response.body.size", response.body.length);
      if (response.status >= 500) span.fail();
      span.end();
    }
    // Like the web app: an unreadable body counts as {}.
    const parsed = parseJson(response.body);
    const data = parsed === undefined ? {} : parsed;
    if (response.status < 200 || response.status >= 300) {
      const code = isObject(data) && typeof data.error === "string" ? data.error : `http_${response.status}`;
      throw cloudError(code, response.status);
    }
    return data;
  }

  /// POST /v1/telemetry/traces as `sub`: a batch of spans (OTLP JSON).
  async traces(sub: string, body: Uint8Array): Promise<void> {
    const token = await this.#accounts.accessToken(sub);
    const headers: [string, string][] = [
      ["authorization", `Bearer ${token}`],
      ["content-type", "application/json"],
    ];
    const channel = channelHeader(this.#host);
    if (channel) headers.push(channel);
    let response: HttpResponse;
    try {
      response = await this.#host.fetch({ method: "POST", url: `${this.#host.cloudOrigin()}/v1/telemetry/traces`, headers, body });
    } catch (e) {
      throw asCoreError(e);
    }
    if (response.status < 200 || response.status >= 300) throw cloudError(`http_${response.status}`, response.status);
  }

  /// GET /v1/me: {user, workspaces, invitations, relay_url}.
  me(sub: string, ctx?: SpanContext | null): Promise<unknown> {
    return this.request(sub, "GET", "/v1/me", null, ctx);
  }

  async credential(sub: string, workspace: string, device: string): Promise<Credential> {
    const answer = await this.request(sub, "POST", `/v1/workspaces/${encodeComponent(workspace)}/credential`, { device });
    const c = readCredential(answer);
    if (typeof c === "string") throw new CoreError("bad_response", t("core-misc.cloud.bad_response", { brand: brand.name(), error: c }));
    return c;
  }
}

/// A Credential as serde reads it, or serde's words for why not.
export function readCredential(v: unknown): Credential | string {
  if (!isObject(v)) return `invalid type: ${v === null ? "null" : Array.isArray(v) ? "sequence" : typeof v}, expected struct Credential`;
  for (const [k, kind] of [
    ["credential", "string"],
    ["issued_at", "number"],
    ["expires_at", "number"],
    ["relay_url", "string"],
  ] as const) {
    if (!(k in v)) return `missing field \`${k}\``;
    if (typeof v[k] !== kind) return `invalid type: ${JSON.stringify(v[k])}, expected ${kind === "string" ? "a string" : "f64"}`;
  }
  return { credential: v.credential as string, issued_at: v.issued_at as number, expires_at: v.expires_at as number, relay_url: v.relay_url as string };
}

/// A beta app says so on its calls (`x-stillfail-channel: beta`). The released apps send nothing.
export function channelHeader(host: Host): [string, string] | null {
  return host.beta() ? ["x-stillfail-channel", "beta"] : null;
}

/// The error for a cloud error code, with its message in the person's language when there is one.
export function cloudError(code: string, status: number): CoreError {
  const key = message(code);
  const text = code === "invalid_email" ? t("core-misc.cloud.invalid_email", { brand: brand.name() }) : key ? t(key) : code;
  return new CoreError(code, text, status);
}

function message(code: string): string | null {
  const known: Record<string, string> = {
    workspace_not_found: "core-misc.cloud.workspace_not_found",
    member_not_found: "core-misc.cloud.member_not_found",
    station_not_found: "core-misc.cloud.station_not_found",
    invitation_not_found: "core-misc.cloud.invitation_not_found",
    invitation_for_other_email: "core-misc.cloud.invitation_for_other_email",
    forbidden: "core-misc.cloud.forbidden",
    invalid_name: "core-misc.cloud.invalid_name",
    already_member: "core-misc.cloud.already_member",
    last_owner: "core-misc.cloud.last_owner",
    too_many_workspaces: "core-misc.cloud.too_many_workspaces",
    too_many_invitations: "core-misc.cloud.too_many_invitations",
    too_many_members: "core-misc.cloud.too_many_members",
    too_many_stations: "core-misc.cloud.too_many_stations",
    invalid_session: "core-misc.cloud.invalid_session",
    [NOT_BETA]: "core-misc.cloud.not_beta",
  };
  return Object.prototype.hasOwnProperty.call(known, code) ? known[code] : null;
}

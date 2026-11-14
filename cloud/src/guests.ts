// One cloud answering as the other product too (the user, 2026-11-12: still.fail's accounts move into monoid's cloud,
// in the company's Cloudflare account; both apps stay, each its own name). still.fail's hosts stay in still.fail's
// account, where its API Worker forwards what reaches it (FORWARD_TO: `forward`), saying the origin it came to and
// the client's address under FORWARD_SECRET. This cloud takes such a request as one made on that origin (`served`),
// and answers it as that origin's product: its links on that origin and its test channel's, its name in what it says,
// its Google client. GUESTS lists those origins; a forwarded origin not listed, or a wrong secret, is not taken.
// Tokens and station signatures made on any of them are good on all (compat.ts publicOrigins), as one cloud's.
import type { Env } from "./env";

/** One of GUESTS: the product's origin, its test channel's, its Google client (else this cloud's). */
export type Guest = { origin: string; beta?: string; google_client_id?: string; google_client_secret?: string };

const FORWARDED_ORIGIN = "x-stillfail-forwarded-origin";
const FORWARDED_FOR = "x-stillfail-forwarded-for";
const FORWARD_SECRET = "x-stillfail-forward-secret";

/** GUESTS (a JSON list), those with an https origin. */
export function guests(env: Pick<Env, "GUESTS">): Guest[] {
  if (!env.GUESTS) return [];
  try {
    const value = JSON.parse(env.GUESTS) as unknown;
    return (Array.isArray(value) ? value : []).filter((g): g is Guest => typeof g?.origin === "string" && g.origin.startsWith("https://"));
  } catch {
    return [];
  }
}

/** The guest whose origin or test channel's origin `origin` is. */
export function guestOf(env: Pick<Env, "GUESTS">, origin: string): Guest | null {
  return guests(env).find((g) => g.origin === origin || g.beta === origin) ?? null;
}

/** Every guest's origins, theirs and their test channels': answered as this cloud's own (compat.ts publicOrigins). */
export function guestOrigins(env: Pick<Env, "GUESTS">): string[] {
  return guests(env).flatMap((g) => [g.origin, ...(g.beta ? [g.beta] : [])]);
}

/**
 * `env` as it is for a request on `origin`: a guest's, its origins and Google client in this cloud's place (and this
 * cloud's own among the aliases, so what was made on it is still good); another's, as it is.
 */
export function asOrigin(env: Env, origin: string): Env {
  const guest = guestOf(env, origin);
  if (!guest) return env;
  const aliases = [env.PUBLIC_ORIGIN, ...(env.PUBLIC_ORIGIN_ALIASES ?? "").split(",")].map((o) => o.trim()).filter((o) => o && o !== guest.origin);
  const served: Partial<Env> = {
    PUBLIC_ORIGIN: guest.origin,
    PUBLIC_ORIGIN_ALIASES: aliases.join(","),
    BETA_ORIGIN: guest.beta ?? "",
    ...(guest.google_client_id && guest.google_client_secret ? { GOOGLE_CLIENT_ID: guest.google_client_id, GOOGLE_CLIENT_SECRET: guest.google_client_secret } : {}),
  };
  return Object.assign(Object.create(env) as Env, served);
}

/** Whether `a` and `b` are the same secret, in time that does not tell where they differ. */
function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * The request as it was made: one forwarded by a guest's Worker (its secret right, its origin a guest's) on the
 * origin it came to, from the address it came from; any other as it is, the forwarding headers dropped.
 */
export function served(request: Request, env: Env): Request {
  const said = request.headers.get(FORWARDED_ORIGIN);
  if (said === null && request.headers.get(FORWARD_SECRET) === null && request.headers.get(FORWARDED_FOR) === null) return request;
  const secret = request.headers.get(FORWARD_SECRET) ?? "";
  const trusted = said !== null && !!env.FORWARD_SECRET && env.FORWARD_SECRET.length >= 32 && same(secret, env.FORWARD_SECRET) && guestOf(env, said) !== null;
  const url = new URL(request.url);
  const target = trusted ? new URL(`${said}${url.pathname}${url.search}`) : url;
  const headers = new Headers(request.headers);
  const from = headers.get(FORWARDED_FOR);
  for (const name of [FORWARDED_ORIGIN, FORWARDED_FOR, FORWARD_SECRET]) headers.delete(name);
  if (trusted && from) headers.set("cf-connecting-ip", from);
  return new Request(target, { method: request.method, headers, body: request.body, redirect: "manual" });
}

/**
 * What a cloud forwards to the one it moved into (FORWARD_TO, under FORWARD_SECRET): the same request there, saying
 * the origin it came to and the client's address. A WebSocket's upgrade goes through as it is.
 */
export function forward(request: Request, env: Pick<Env, "FORWARD_TO" | "FORWARD_SECRET">): Promise<Response> {
  const url = new URL(request.url);
  const headers = new Headers(request.headers);
  headers.set(FORWARDED_ORIGIN, url.origin);
  headers.set(FORWARD_SECRET, env.FORWARD_SECRET ?? "");
  const from = request.headers.get("cf-connecting-ip");
  if (from) headers.set(FORWARDED_FOR, from);
  else headers.delete(FORWARDED_FOR);
  return fetch(new Request(`${env.FORWARD_TO!.replace(/\/+$/, "")}${url.pathname}${url.search}`, { method: request.method, headers, body: request.body, redirect: "manual" }));
}

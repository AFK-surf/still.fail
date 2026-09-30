// The account-facing API: workspaces, members, invitations, stations and
// grants, each device's event socket and push registration; plus what
// stations do with their own key (enroll, hold their presence socket, send
// traces and notices). `api` returns null for paths it does not own. The
// admin's console has its own, `adminApi`, which only the console's host
// routes to (index.ts).
import { isAdmin } from "./admin";
import { bearerToken, denied, readJson, reply, verifyToken, type Claims } from "./auth";
import { header, publicOrigins, signedMessages } from "./compat";
import { EVENTS_PROTOCOLS, ROLES, type Role } from "./directory";
import type { Env } from "./env";
import { grantKeys, signCredential, validKeyHex, verifyAnySignature } from "./grants";
import { pushKey, registration, stationNotify } from "./push";
import { relays } from "./relays";
import { receiveTraces } from "./tracing";

/** Directory errors travel over RPC as their code; this gives each its status. */
const STATUS: Record<string, number> = {
  workspace_not_found: 404, member_not_found: 404, station_not_found: 404, invitation_not_found: 404, enrollment_not_found: 404,
  forbidden: 403, invitation_for_other_email: 403,
  already_member: 409, invalid_name: 400, invalid_role: 400, invalid_email: 400,
  last_owner: 409,
  too_many_workspaces: 429, too_many_invitations: 429, too_many_members: 429, too_many_stations: 429,
  invite_code_required: 403, invite_code_invalid: 404, invite_code_used: 409, invite_code_expired: 410,
  invalid_note: 400, invalid_expiry: 400,
};

async function directory<T>(run: () => Promise<T> | T): Promise<Response> {
  try {
    const value = await run();
    return reply(value ?? { ok: true });
  } catch (error) {
    const code = error instanceof Error ? error.message : "";
    if (code in STATUS) return reply({ error: code }, STATUS[code]);
    throw error;
  }
}

async function account(token: string | null, env: Env): Promise<Claims | null> {
  const claims = token ? await verifyToken(env, token, "access") : null;
  if (!claims) return null;
  return (await env.ACCOUNTS.getByName(claims.sub).live(claims)) ? claims : null;
}

const isUpgrade = (request: Request) => request.headers.get("upgrade")?.toLowerCase() === "websocket";

/**
 * The access token of an events socket, and the subprotocol the answer
 * selects. Browsers cannot set headers on a WebSocket, so it comes as a second
 * subprotocol, `stillfail-token.<token>`, next to `stillfail-events` (the one
 * the answer selects); clients from before the rename say `ember-token.` and
 * `ember-events`. A header, unlike a query string, stays out of URLs and so
 * out of request logs.
 */
function socketToken(request: Request): { token: string; protocol: string } | null {
  const offered = (request.headers.get("sec-websocket-protocol") ?? "").split(",").map((p) => p.trim());
  const protocol = EVENTS_PROTOCOLS.find((p) => offered.includes(p));
  if (!protocol) return null;
  const match = offered.map((p) => /^(?:stillfail|ember)-token\.([A-Za-z0-9._-]{1,4096})$/.exec(p)).find(Boolean);
  return match?.[1] ? { token: match[1], protocol } : null;
}

async function body(request: Request): Promise<Record<string, unknown>> {
  // Bodiless calls (GET, DELETE, a bare accept or decline) carry no JSON.
  if (request.method === "GET" || request.method === "DELETE" || !request.headers.get("content-type")) return {};
  return readJson(request);
}

export async function api(request: Request, env: Env, url: URL): Promise<Response | null> {
  const path = url.pathname;
  const method = request.method;
  if ((path === "/.well-known/stillfail-grant-keys" || path === "/.well-known/ember-grant-keys") && method === "GET") return reply(grantKeys(env), 200, { "cache-control": "public, max-age=300" });

  // ── stations, authenticated by their own key ────────────────────────────
  if (path === "/v1/stations/enroll" && method === "POST") {
    const input = await readJson(request).catch(() => null);
    if (!input || typeof input.token !== "string" || !validKeyHex(input.station) || typeof input.signature !== "string") return reply({ error: "invalid_request" }, 400);
    const messages = signedMessages("station-enroll-v1", publicOrigins(env), `${input.token}:${input.station}`);
    if (!(await verifyAnySignature(input.station, input.signature, messages))) return reply({ error: "invalid_signature" }, 401);
    const version = typeof input.version === "string" ? input.version.slice(0, 40) : null;
    return directory(async () => ({
      ...(await env.DIRECTORY.getByName("primary").enroll(input.token as string, input.station as string, version)),
      station: input.station,
      ...relays(env),
      grant_keys: grantKeys(env),
    }));
  }
  // The station's presence: a WebSocket it keeps open. Signed at connect in
  // headers: x-stillfail-station (its key), x-stillfail-ts (unix seconds,
  // within 5 minutes), x-stillfail-signature over
  // "stillfail-station-connect-v1:<origin>:<station>:<ts>", and
  // x-stillfail-version. (Stations from before the rename: x-ember-* and
  // "ember-station-connect-v1:…"; the origin is any of the cloud's.)
  if (path === "/v1/stations/connect" && method === "GET") {
    if (!isUpgrade(request)) return reply({ error: "websocket_required" }, 426);
    const station = header(request, "station");
    const signature = header(request, "signature") ?? "";
    const ts = Number(header(request, "ts"));
    if (!validKeyHex(station) || !Number.isSafeInteger(ts) || Math.abs(ts - Date.now() / 1000) > 300) return reply({ error: "invalid_request" }, 400);
    if (!(await verifyAnySignature(station, signature, signedMessages("station-connect-v1", publicOrigins(env), `${station}:${ts}`)))) return reply({ error: "invalid_signature" }, 401);
    const headers = new Headers({ upgrade: "websocket", "x-stillfail-station": station });
    const version = header(request, "version");
    if (version) headers.set("x-stillfail-version", version.slice(0, 40));
    return env.DIRECTORY.getByName("primary").fetch(new Request("https://directory/stations/connect", { headers }));
  }

  // Spans from a signed-in client, or from a station signing them with its key (tracing.ts).
  if (path === "/v1/telemetry/traces" && method === "POST") {
    const token = bearerToken(request);
    const claims = token ? await account(token, env) : null;
    if (token && !claims) return denied();
    return receiveTraces(request, env, claims?.sub ?? null);
  }

  // Notices of a station's chats, signed with its key like its spans, pushed to the people they are for (push.ts).
  if (path === "/v1/stations/notify" && method === "POST") return stationNotify(request, env);
  if (path === "/v1/push/key" && method === "GET") return pushKey(env);
  // This device's push subscription or token, registered with the signed-in account's session, or taken off it.
  if (path === "/v1/push" && (method === "POST" || method === "DELETE")) {
    const claims = await account(bearerToken(request), env);
    if (!claims) return denied();
    return registration(request, env, claims.sub, claims.sid);
  }

  if (path === "/v1/events" && method === "GET") {
    if (!isUpgrade(request)) return reply({ error: "websocket_required" }, 426);
    const socket = socketToken(request);
    const claims = await account(socket?.token ?? null, env);
    if (!claims || !socket) return denied();
    return env.DIRECTORY.getByName("primary").fetch(new Request("https://directory/events", { headers: { upgrade: "websocket", "x-stillfail-sub": claims.sub, "x-stillfail-protocol": socket.protocol } }));
  }

  // ── accounts ────────────────────────────────────────────────────────────
  const isAccountRoute = path === "/v1/me" || path.startsWith("/v1/workspaces") || path.startsWith("/v1/invitations/");
  if (!isAccountRoute) return null;
  const claims = await account(bearerToken(request), env);
  if (!claims) return denied();
  let input: Record<string, unknown>;
  try {
    input = await body(request);
  } catch {
    return reply({ error: "invalid_request" }, 400);
  }
  const dir = env.DIRECTORY.getByName("primary");
  const sub = claims.sub;
  const text = (key: string) => (typeof input[key] === "string" ? (input[key] as string) : "");
  const role = (): Role => (ROLES.includes(input.role as Role) ? (input.role as Role) : "member");

  if (path === "/v1/me" && method === "GET") {
    return directory(async () => ({ ...(await dir.me(sub)), invitations: await dir.invitationsFor(claims.email), ...relays(env) }));
  }
  const byId = /^\/v1\/invitations\/([0-9A-HJKMNP-TV-Z]{26})\/(accept|decline)$/.exec(path);
  if (byId && method === "POST") {
    if (byId[2] === "accept") return directory(() => dir.acceptById(sub, claims.email, byId[1]!));
    return directory(() => dir.declineById(claims.email, byId[1]!));
  }
  if (path === "/v1/workspaces" && method === "POST") return directory(() => dir.createWorkspace(sub, text("name"), isAdmin(env, claims.email), input.invite_code));
  if (path === "/v1/invitations/preview" && method === "POST") return directory(() => dir.previewInvitation(text("token")));
  if (path === "/v1/invitations/accept" && method === "POST") return directory(() => dir.acceptInvitation(sub, claims.email, text("token")));

  const parts = path.split("/").slice(3).map(decodeURIComponent); // after /v1/workspaces/
  const [ws, kind, target, action] = parts;
  if (!ws || !/^[0-9A-HJKMNP-TV-Z]{26}$/.test(ws)) return reply({ error: "not_found" }, 404);
  if (!kind) {
    if (method === "GET") return directory(() => dir.workspace(sub, ws));
    if (method === "PATCH") return directory(() => dir.renameWorkspace(sub, ws, text("name")));
    if (method === "DELETE") return directory(() => dir.deleteWorkspace(sub, ws));
  }
  if (kind === "invitations" && !target && method === "POST") {
    const email = text("email").trim().toLowerCase() || null;
    return directory(async () => {
      const made = await dir.invite(sub, ws, role(), email);
      return { ...made, url: `${env.PUBLIC_ORIGIN}/invite#${made.token}` };
    });
  }
  if (kind === "invitations" && target && method === "DELETE") return directory(() => dir.revokeInvitation(sub, ws, target));
  if (kind === "members" && !target && method === "POST") return directory(() => dir.addMembers(sub, ws, role(), input.emails));
  if (kind === "added" && target && method === "DELETE") return directory(() => dir.removeAdded(sub, ws, target));
  if (kind === "members" && target && method === "PATCH") return directory(() => dir.setRole(sub, ws, target, role()));
  if (kind === "members" && target && method === "DELETE") return directory(() => dir.removeMember(sub, ws, target));
  if (kind === "enrollments" && !target && method === "POST") {
    return directory(async () => {
      const made = await dir.createEnrollment(sub, ws, text("name"));
      // A machine without still.fail installs it and joins at once; one with it joins.
      return { ...made, install: `curl -fsSL ${env.PUBLIC_ORIGIN}/install.sh | sh -s -- ${made.token}`, command: `stillfail station enroll ${env.PUBLIC_ORIGIN} ${made.token}` };
    });
  }
  // A member's credential for this device: what its stations take, offline, for the next 30 days (grants.ts).
  if (kind === "credential" && !target && method === "POST") {
    if (!validKeyHex(input.device)) return reply({ error: "invalid_device" }, 400);
    return directory(async () => {
      const role = await dir.memberRole(sub, ws);
      const signed = await signCredential(env, { sub, email: claims.email, name: claims.name ?? "", ws, role, device: input.device as string, sid: claims.sid });
      return { ...signed, ...relays(env) };
    });
  }
  if (kind === "stations" && target && validKeyHex(target)) {
    if (!action && method === "PATCH") return directory(() => dir.renameStation(sub, ws, target, text("name")));
    if (!action && method === "DELETE") return directory(() => dir.removeStation(sub, ws, target));
  }
  return reply({ error: "not_found" }, 404);
}

/** What any path nobody serves answers; the console's paths answer it to everyone but the admin. */
const notFound = () => new Response("Not found", { status: 404 });

const inviteUrl = (env: Env, code: string) => `${env.PUBLIC_ORIGIN}/?invite=${code}`;

export async function adminApi(request: Request, env: Env, path: string): Promise<Response> {
  const method = request.method;
  const claims = await account(bearerToken(request), env);
  if (!claims || !isAdmin(env, claims.email)) return notFound();
  let input: Record<string, unknown>;
  try {
    input = await body(request);
  } catch {
    return reply({ error: "invalid_request" }, 400);
  }
  const dir = env.DIRECTORY.getByName("primary");
  if (path === "/v1/admin/me" && method === "GET") return reply({ email: claims.email });
  if (path === "/v1/admin/users" && method === "GET") return directory(async () => ({ users: await dir.adminUsers() }));
  if (path === "/v1/admin/workspaces" && method === "GET") return directory(async () => ({ workspaces: await dir.adminWorkspaces() }));
  // Each with its sign-up link: that is the web app's, on the other origin.
  if (path === "/v1/admin/invite-codes" && method === "GET") return directory(async () => ({ codes: (await dir.inviteCodes()).map((c) => ({ ...c, url: inviteUrl(env, c.code) })) }));
  if (path === "/v1/admin/invite-codes" && method === "POST") {
    return directory(async () => {
      const made = await dir.createInviteCode(claims.sub, input.note, input.days);
      return { ...made, url: inviteUrl(env, made.code) };
    });
  }
  const revoke = /^\/v1\/admin\/invite-codes\/([A-Za-z0-9-]{1,32})\/revoke$/.exec(path);
  if (revoke && method === "POST") return directory(() => dir.revokeInviteCode(revoke[1]!));
  return notFound();
}

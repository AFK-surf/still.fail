// The account-facing API: workspaces, members, invitations, stations and
// grants, and each device's event socket; plus the two things stations do
// with their own key (enroll, and hold their presence socket). Returns null
// for paths it does not own.
import { bearerToken, denied, readJson, reply, verifyToken, type Claims } from "./auth";
import { EVENTS_PROTOCOL, ROLES, type Role } from "./directory";
import type { Env } from "./env";
import { grantKeys, signGrant, validKeyHex, verifyKeySignature } from "./grants";

/** Directory errors travel over RPC as their code; this gives each its status. */
const STATUS: Record<string, number> = {
  workspace_not_found: 404, member_not_found: 404, station_not_found: 404, invitation_not_found: 404, enrollment_not_found: 404,
  forbidden: 403, invitation_for_other_email: 403,
  already_member: 409, invalid_name: 400, invalid_role: 400, invalid_email: 400,
  last_owner: 409,
  too_many_workspaces: 429, too_many_invitations: 429, too_many_members: 429, too_many_stations: 429,
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
 * The access token of an events socket. Browsers cannot set headers on a
 * WebSocket, so it comes as a second subprotocol, `ember-token.<token>`, next
 * to `ember-events` (the one the answer selects). A header, unlike a query
 * string, stays out of URLs and so out of request logs.
 */
function socketToken(request: Request): string | null {
  const offered = (request.headers.get("sec-websocket-protocol") ?? "").split(",").map((p) => p.trim());
  if (!offered.includes(EVENTS_PROTOCOL)) return null;
  const match = offered.map((p) => /^ember-token\.([A-Za-z0-9._-]{1,4096})$/.exec(p)).find(Boolean);
  return match?.[1] ?? null;
}

async function body(request: Request): Promise<Record<string, unknown>> {
  // Bodiless calls (GET, DELETE, a bare accept or decline) carry no JSON.
  if (request.method === "GET" || request.method === "DELETE" || !request.headers.get("content-type")) return {};
  return readJson(request);
}

export async function api(request: Request, env: Env, url: URL): Promise<Response | null> {
  const path = url.pathname;
  const method = request.method;
  if (path === "/.well-known/ember-grant-keys" && method === "GET") return reply(grantKeys(env), 200, { "cache-control": "public, max-age=300" });

  // ── stations, authenticated by their own key ────────────────────────────
  if (path === "/v1/stations/enroll" && method === "POST") {
    const input = await readJson(request).catch(() => null);
    if (!input || typeof input.token !== "string" || !validKeyHex(input.station) || typeof input.signature !== "string") return reply({ error: "invalid_request" }, 400);
    const message = `ember-station-enroll-v1:${env.PUBLIC_ORIGIN}:${input.token}:${input.station}`;
    if (!(await verifyKeySignature(input.station, input.signature, message))) return reply({ error: "invalid_signature" }, 401);
    const version = typeof input.version === "string" ? input.version.slice(0, 40) : null;
    return directory(async () => ({
      ...(await env.DIRECTORY.getByName("primary").enroll(input.token as string, input.station as string, version)),
      station: input.station,
      relay_url: env.RELAY_URL || env.PUBLIC_ORIGIN,
      grant_keys: grantKeys(env),
    }));
  }
  // The station's presence: a WebSocket it keeps open. Signed at connect in
  // headers: x-ember-station (its key), x-ember-ts (unix seconds, within 5
  // minutes), x-ember-signature over "ember-station-connect-v1:<origin>:<station>:<ts>",
  // and x-ember-version.
  if (path === "/v1/stations/connect" && method === "GET") {
    if (!isUpgrade(request)) return reply({ error: "websocket_required" }, 426);
    const station = request.headers.get("x-ember-station");
    const signature = request.headers.get("x-ember-signature") ?? "";
    const ts = Number(request.headers.get("x-ember-ts"));
    if (!validKeyHex(station) || !Number.isSafeInteger(ts) || Math.abs(ts - Date.now() / 1000) > 300) return reply({ error: "invalid_request" }, 400);
    if (!(await verifyKeySignature(station, signature, `ember-station-connect-v1:${env.PUBLIC_ORIGIN}:${station}:${ts}`))) return reply({ error: "invalid_signature" }, 401);
    const headers = new Headers({ upgrade: "websocket", "x-ember-station": station });
    const version = request.headers.get("x-ember-version");
    if (version) headers.set("x-ember-version", version.slice(0, 40));
    return env.DIRECTORY.getByName("primary").fetch(new Request("https://directory/stations/connect", { headers }));
  }

  if (path === "/v1/events" && method === "GET") {
    if (!isUpgrade(request)) return reply({ error: "websocket_required" }, 426);
    const claims = await account(socketToken(request), env);
    if (!claims) return denied();
    return env.DIRECTORY.getByName("primary").fetch(new Request("https://directory/events", { headers: { upgrade: "websocket", "x-ember-sub": claims.sub } }));
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
    return directory(async () => ({ ...(await dir.me(sub)), invitations: await dir.invitationsFor(claims.email), relay_url: env.RELAY_URL || env.PUBLIC_ORIGIN }));
  }
  const byId = /^\/v1\/invitations\/([0-9A-HJKMNP-TV-Z]{26})\/(accept|decline)$/.exec(path);
  if (byId && method === "POST") {
    if (byId[2] === "accept") return directory(() => dir.acceptById(sub, claims.email, byId[1]!));
    return directory(() => dir.declineById(claims.email, byId[1]!));
  }
  if (path === "/v1/workspaces" && method === "POST") return directory(() => dir.createWorkspace(sub, text("name")));
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
  if (kind === "members" && target && method === "PATCH") return directory(() => dir.setRole(sub, ws, target, role()));
  if (kind === "members" && target && method === "DELETE") return directory(() => dir.removeMember(sub, ws, target));
  if (kind === "enrollments" && !target && method === "POST") {
    return directory(async () => {
      const made = await dir.createEnrollment(sub, ws, text("name"));
      return { ...made, command: `ember station enroll ${env.PUBLIC_ORIGIN} ${made.token}` };
    });
  }
  if (kind === "stations" && target && validKeyHex(target)) {
    if (!action && method === "PATCH") return directory(() => dir.renameStation(sub, ws, target, text("name")));
    if (!action && method === "DELETE") return directory(() => dir.removeStation(sub, ws, target));
    if (action === "grant" && method === "POST") {
      if (!validKeyHex(input.device)) return reply({ error: "invalid_device" }, 400);
      return directory(async () => {
        const access = await dir.access(sub, ws, target);
        const signed = await signGrant(env, { sub, email: claims.email, name: claims.name ?? "", ws, role: access.role, aud: target, device: input.device as string });
        return { ...signed, station: target, station_name: access.station_name, relay_url: env.RELAY_URL || env.PUBLIC_ORIGIN };
      });
    }
  }
  return reply({ error: "not_found" }, 404);
}

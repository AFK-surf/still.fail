// The account-facing API: workspaces, members, invitations, stations and
// grants; plus the two calls stations make with their own key (enroll and
// heartbeat). Returns null for paths it does not own.
import { bearerToken, denied, readJson, reply, verifyToken, type Claims } from "./auth";
import { ROLES, type Role } from "./directory";
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

async function account(request: Request, env: Env): Promise<Claims | null> {
  const token = bearerToken(request);
  const claims = token ? await verifyToken(env, token, "access") : null;
  if (!claims) return null;
  return (await env.ACCOUNTS.getByName(claims.sub).live(claims)) ? claims : null;
}

async function body(request: Request): Promise<Record<string, unknown>> {
  if (request.method === "GET" || request.method === "DELETE") return {};
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
  if (path === "/v1/stations/heartbeat" && method === "POST") {
    const input = await readJson(request).catch(() => null);
    const ts = Number(input?.ts);
    if (!input || !validKeyHex(input.station) || typeof input.signature !== "string" || !Number.isSafeInteger(ts) || Math.abs(ts - Date.now() / 1000) > 300) return reply({ error: "invalid_request" }, 400);
    if (!(await verifyKeySignature(input.station, input.signature, `ember-station-heartbeat-v1:${env.PUBLIC_ORIGIN}:${input.station}:${ts}`))) return reply({ error: "invalid_signature" }, 401);
    const version = typeof input.version === "string" ? input.version.slice(0, 40) : null;
    const found = await env.DIRECTORY.getByName("primary").heartbeat(input.station, version);
    return found ? reply({ ...found, grant_keys: grantKeys(env) }) : reply({ error: "station_removed" }, 404);
  }

  // ── accounts ────────────────────────────────────────────────────────────
  const isAccountRoute = path === "/v1/me" || path.startsWith("/v1/workspaces") || path.startsWith("/v1/invitations/");
  if (!isAccountRoute) return null;
  const claims = await account(request, env);
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
    return directory(() => (byId[2] === "accept" ? dir.acceptById(sub, claims.email, byId[1]!) : dir.declineById(claims.email, byId[1]!)));
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

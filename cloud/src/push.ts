// Push notifications (docs/notifications.md): devices register where they can be pushed to (a browser's Web Push
// subscription, the Android app's FCM token) with the signed-in account and session; a station sends the notices of
// its chats, signed with its key, naming who they are for by email; still.fail cloud makes each one's text and pushes it
// to the devices of those people who are members of the station's workspace, each device once. A device its push
// service says is gone is dropped (with every account); any other failure is logged and forgotten (the person hears of
// it the next time a client runs).
import { clock, readJson, readText, reply } from "./auth";
import type { PushDevice, PushRegistration } from "./directory";
import type { Env } from "./env";
import { fcmPush, serviceAccount } from "./fcm";
import { langOf, requestLang, type Lang } from "./i18n.ts";
import { line, noticeBody } from "./noticeText";
import { stationSender } from "./tracing";
import { validAuthSecret, validPoint, webPush, type Outcome, type Vapid } from "./webpush";

const MAX_BYTES = 256 * 1024;
/** Notices one request may carry, people one notice may name, and pushes one request may make in all. */
const MAX_NOTICES = 50;
const MAX_TO = 20;
const MAX_PUSHES = 200;

function vapid(env: Env): Vapid | null {
  if (!env.VAPID_PUBLIC_KEY || !env.VAPID_PRIVATE_KEY) return null;
  return { publicKey: env.VAPID_PUBLIC_KEY, privateKey: env.VAPID_PRIVATE_KEY, subject: env.VAPID_SUBJECT || env.PUBLIC_ORIGIN };
}

/** GET /v1/push/key: the VAPID public key a browser subscribes with; 404 without one. */
export function pushKey(env: Env): Response {
  const keys = vapid(env);
  return keys ? reply({ vapid: keys.publicKey }) : reply({ error: "push_not_configured" }, 404);
}

/** A push subscription's endpoint: an https URL of its push service. */
function validEndpoint(value: unknown): value is string {
  if (typeof value !== "string" || value.length > 2048) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password;
  } catch {
    return false;
  }
}
const validToken = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9_:.-]{1,4096}$/.test(value);
/** Browsers give base64url keys, some with padding. */
const unpadded = (value: unknown) => (typeof value === "string" ? value.replace(/=+$/, "") : value);

/** POST /v1/push and DELETE /v1/push, for a signed-in account's session. */
export async function registration(request: Request, env: Env, sub: string, sid: string): Promise<Response> {
  let input: Record<string, unknown>;
  try {
    input = await readJson(request);
  } catch {
    return reply({ error: "invalid_request" }, 400);
  }
  const dir = env.DIRECTORY.getByName("primary");
  if (request.method === "DELETE") {
    if (validEndpoint(input.endpoint)) await dir.unregisterPush(sub, { endpoint: input.endpoint });
    else if (validToken(input.token)) await dir.unregisterPush(sub, { token: input.token });
    else return reply({ error: "invalid_request" }, 400);
    return new Response(null, { status: 204 });
  }
  let device: PushDevice;
  if (input.kind === "web") {
    const keys = (input.keys ?? {}) as Record<string, unknown>;
    const p256dh = unpadded(keys.p256dh), auth = unpadded(keys.auth);
    if (!validEndpoint(input.endpoint) || !validPoint(p256dh) || !validAuthSecret(auth)) return reply({ error: "invalid_request" }, 400);
    if (!vapid(env)) return reply({ error: "push_not_configured" }, 503);
    device = { kind: "web", endpoint: input.endpoint, p256dh, auth };
  } else if (input.kind === "fcm") {
    if (!validToken(input.token)) return reply({ error: "invalid_request" }, 400);
    device = { kind: "fcm", token: input.token };
  } else {
    return reply({ error: "invalid_request" }, 400);
  }
  // The language its notifications are said in: the one the client says, else its request's.
  const lang = typeof input.lang === "string" && input.lang ? langOf(input.lang) : requestLang(request);
  await dir.registerPush(sub, sid, device, lang);
  return new Response(null, { status: 204 });
}

interface Notice {
  to: string[];
  kind: string;
  session: string;
  title: string;
  by?: string;
  text: string;
  at: number;
}

/** A notice as a station sends it, or null for one that is not (it is skipped). Kinds it does not know read as `done`. */
function notice(value: unknown): Notice | null {
  if (!value || typeof value !== "object") return null;
  const n = value as Record<string, unknown>;
  const to = Array.isArray(n.to) ? n.to.filter((e): e is string => typeof e === "string" && e.includes("@") && e.length <= 320).slice(0, MAX_TO) : [];
  if (!to.length || typeof n.kind !== "string" || !/^[a-z_]{1,32}$/.test(n.kind)) return null;
  if (typeof n.session !== "string" || !n.session || n.session.length > 512) return null;
  if (typeof n.text !== "string" || (n.title !== undefined && typeof n.title !== "string") || (n.by !== undefined && n.by !== null && typeof n.by !== "string")) return null;
  const at = typeof n.at === "number" && Number.isFinite(n.at) ? Math.floor(n.at) : clock.now();
  return { to, kind: n.kind, session: n.session, title: (n.title as string | undefined) ?? "", by: (n.by as string | null | undefined) || undefined, text: n.text, at };
}

/** POST /v1/stations/notify: a station's notices, pushed to the members they name → `{ sent }`. */
export async function stationNotify(request: Request, env: Env): Promise<Response> {
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json") return reply({ error: "invalid_request" }, 400);
  let body: string;
  try {
    body = await readText(request, MAX_BYTES);
  } catch {
    return reply({ error: "too_large" }, 413);
  }
  const station = await stationSender(request, env, body, "station-notify-v1");
  if (!station) return reply({ error: "invalid_signature" }, 401);
  let notices: Notice[];
  try {
    const value = JSON.parse(body) as { notices?: unknown };
    if (!Array.isArray(value.notices)) throw new Error("shape");
    notices = value.notices.slice(0, MAX_NOTICES).map(notice).filter((n): n is Notice => n !== null);
  } catch {
    return reply({ error: "invalid_request" }, 400);
  }
  const dir = env.DIRECTORY.getByName("primary");
  const targets = await dir.pushTargets(station, notices.flatMap((n) => n.to));
  if (!targets) return reply({ error: "invalid_signature" }, 401);
  const keys = vapid(env);
  const fcm = serviceAccount(env.FCM_SERVICE_ACCOUNT);
  const pushes: Promise<{ device: PushRegistration; outcome: Outcome }>[] = [];
  for (const n of notices) {
    const base = `${targets.workspace}/${station}`;
    // In each device's language.
    const payload = (lang: Lang): Record<string, string> => ({
      type: "notice",
      kind: n.kind,
      title: line(n.title),
      body: noticeBody(n.kind, n.text, n.by, lang),
      tag: `${base}/${n.session}`,
      url: `/o/${base}/${encodeURIComponent(n.session)}`,
      workspace: targets.workspace,
      station,
      session: n.session,
      at: String(n.at),
    });
    // A device signed in with several of the people named gets it once.
    const devices = new Map<string, PushRegistration>();
    for (const email of n.to) for (const device of targets.devices[email.toLowerCase()] ?? []) devices.set(device.kind === "web" ? `web ${device.endpoint}` : `fcm ${device.token}`, device);
    for (const device of devices.values()) {
      if (pushes.length >= MAX_PUSHES) break;
      const said = payload(device.lang);
      const push = device.kind === "web" ? (keys ? webPush(keys, device, JSON.stringify(said), said.tag!) : null) : fcm ? fcmPush(fcm, device.token, said) : null;
      if (!push) continue;
      pushes.push(push.then((outcome) => ({ device, outcome }), (error) => {
        console.warn(`push: ${error}`);
        return { device, outcome: "failed" as const };
      }));
    }
  }
  const results = await Promise.all(pushes);
  const gone = results.filter((r) => r.outcome === "gone").map((r) => r.device);
  if (gone.length) await dir.dropPush(gone);
  return reply({ sent: results.filter((r) => r.outcome === "sent").length });
}

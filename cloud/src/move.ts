// Moving one cloud's accounts into another (the user, 2026-11-12: still.fail's into monoid's, which then answers as
// still.fail too: guests.ts). Both are deployed with MOVING set first: every other /v1/ call is answered 503 moving
// (clients wait and try again, as for any service unavailable; none is signed out), so nothing changes while it is
// copied. scripts/move-cloud.ts then reads all of the first (export, the icons kept in its bucket) and writes it into
// the second (import), which takes the first's keys (keys.json) so every token, session, credential and sealed value
// stays good; then the first forwards to the second (FORWARD_TO) and MOVING goes from both.
//
//   POST /v1/admin/move/export          the Directory's tables and each account's object (ADMIN_TOKEN)
//   GET  /v1/admin/move/icons           the icons kept in the bucket, by name
//   PUT  /v1/admin/move/icons/<name>    one put in this one's bucket
//   POST /v1/admin/move/import          the export, in place of all this one has
import { bearerToken, denied, digest, reply } from "./auth";
import type { Env } from "./env";

type Moved = { directory: Record<string, Record<string, unknown>[]>; accounts: Record<string, Record<string, unknown>> };

/** Whether this is MOVING's way in, the only one answered while MOVING. */
export const isMoveCall = (path: string) => path.startsWith("/v1/admin/move/");

/** The answer to every other /v1/ call while MOVING: wait and try again. */
export const moving = () => reply({ error: "moving", message: "Moving to a new home: back in a few minutes, nothing is lost. Try again in a minute." }, 503, { "retry-after": "60" });

const ICON_NAME = /^[0-9a-f]{32}\.(png|webp|jpeg|gif)$/;

export async function moveApi(request: Request, env: Env, path: string): Promise<Response> {
  const supplied = bearerToken(request);
  if (!env.ADMIN_TOKEN || env.ADMIN_TOKEN.length < 43 || !supplied || (await digest(supplied)) !== (await digest(env.ADMIN_TOKEN))) return denied();
  const directory = env.DIRECTORY.getByName("primary");
  if (path === "/v1/admin/move/export" && request.method === "POST") {
    const accounts: Moved["accounts"] = {};
    for (const sub of await directory.moveAccounts()) accounts[sub] = await env.ACCOUNTS.getByName(sub).moveExport();
    return reply({ directory: await directory.moveExport(), accounts } satisfies Moved);
  }
  if (path === "/v1/admin/move/import" && request.method === "POST") {
    // Only while MOVING: a cloud in use is never written over.
    if (!env.MOVING) return reply({ error: "not_moving" }, 409);
    let moved: Moved;
    try {
      moved = (await request.json()) as Moved;
      if (typeof moved?.directory !== "object" || typeof moved?.accounts !== "object") throw new Error("shape");
    } catch {
      return reply({ error: "invalid_request" }, 400);
    }
    const tables = await directory.moveImport(moved.directory as never);
    for (const [sub, kept] of Object.entries(moved.accounts)) await env.ACCOUNTS.getByName(sub).moveImport(kept);
    return reply({ tables, accounts: Object.keys(moved.accounts).length });
  }
  const bucket = env.RELEASES;
  if (path === "/v1/admin/move/icons" && request.method === "GET") {
    const names: string[] = [];
    let cursor: string | undefined;
    do {
      const page = bucket ? await bucket.list({ prefix: "icons/", cursor }) : { objects: [], truncated: false as const };
      names.push(...page.objects.map((o) => o.key.slice("icons/".length)).filter((n) => ICON_NAME.test(n)));
      cursor = page.truncated ? page.cursor : undefined;
    } while (cursor);
    return reply({ icons: names });
  }
  const icon = /^\/v1\/admin\/move\/icons\/([^/]+)$/.exec(path)?.[1];
  if (icon && request.method === "PUT" && ICON_NAME.test(icon) && bucket) {
    if (!env.MOVING) return reply({ error: "not_moving" }, 409);
    const type = request.headers.get("content-type") ?? "application/octet-stream";
    await bucket.put(`icons/${icon}`, await request.arrayBuffer(), { httpMetadata: { contentType: type, cacheControl: "public, max-age=31536000, immutable" } });
    return reply({ kept: icon });
  }
  return reply({ error: "not_found" }, 404);
}

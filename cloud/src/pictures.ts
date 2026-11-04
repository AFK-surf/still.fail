// The pictures a browser's page cannot read from where they are (GET /v1/pictures?url=: client/core-ts's
// picture-relay.ts says which): fetched here and answered as this host's own. Slack's people's and bots' pictures,
// whose server says nothing of other pages, so the app in a browser drew their initials instead. Only those: any other
// address is refused, and what comes back is answered only when it is a picture (not SVG, which runs scripts) of up to
// PICTURE_BYTES. Their addresses name each picture for good, so they are kept a day, here and by the browser.
import { reply } from "./auth";
import { relayedPicture } from "../../client/core-ts/src/picture-relay.ts";

/** How large a picture fetched for a page may be. */
export const PICTURE_BYTES = 2 * 1024 * 1024;
const KEPT_SECONDS = 86_400;

/** GET /v1/pictures: the picture at `url`, as `get` (the Worker's fetch) has it. */
export async function servePicture(request: Request, get: (url: string, init: RequestInit) => Promise<Response> = fetch): Promise<Response> {
  const url = new URL(request.url).searchParams.get("url") ?? "";
  if (!relayedPicture(url)) return reply({ error: "not_relayed" }, 400);
  let r: Response;
  try {
    r = await get(url, { redirect: "manual", headers: { "user-agent": "stillfail-cloud" }, cf: { cacheEverything: true, cacheTtl: KEPT_SECONDS } } as RequestInit);
  } catch {
    return reply({ error: "unreachable" }, 502);
  }
  const type = (r.headers.get("content-type") ?? "").split(";")[0]!.trim().toLowerCase();
  if (r.status !== 200 || !type.startsWith("image/") || type.includes("svg")) {
    await r.body?.cancel();
    return reply({ error: "not_found" }, 404);
  }
  if (Number(r.headers.get("content-length") ?? 0) > PICTURE_BYTES) {
    await r.body?.cancel();
    return reply({ error: "too_large" }, 413);
  }
  const body = new Uint8Array(await r.arrayBuffer());
  if (body.length > PICTURE_BYTES) return reply({ error: "too_large" }, 413);
  return new Response(body, {
    headers: {
      "content-type": type,
      "cache-control": `public, max-age=${KEPT_SECONDS}`,
      "x-content-type-options": "nosniff",
      "content-security-policy": "default-src 'none'",
      "referrer-policy": "no-referrer",
    },
  });
}

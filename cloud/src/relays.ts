// The relays stations and devices use. The first is still.fail's own (RELAY_URL, or PUBLIC_ORIGIN's /relay:
// relay-worker.ts), handed out alone as `relay_url` to what came before there were several; RELAY_URLS adds others
// (comma-separated), such as one inside mainland China, where Cloudflare's is slow or out of reach. Each endpoint
// has all of them in its map: a station homes on the nearest, and a device dials it on every one (client/core mesh.rs).
import { originList } from "./compat";

export const relayUrls = (env: { PUBLIC_ORIGIN: string; RELAY_URL?: string; RELAY_URLS?: string }): string[] => originList(env.RELAY_URL || env.PUBLIC_ORIGIN, env.RELAY_URLS);

/** What a station or a device is told about the relays: the one, as before, and all of them. */
export function relays(env: { PUBLIC_ORIGIN: string; RELAY_URL?: string; RELAY_URLS?: string }): { relay_url: string; relay_urls: string[] } {
  const all = relayUrls(env);
  return { relay_url: all[0], relay_urls: all };
}

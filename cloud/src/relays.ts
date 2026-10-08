// The relays stations and devices use. The first is still.fail's own (RELAY_URL, or PUBLIC_ORIGIN's /relay:
// relay-worker.ts), handed out alone as `relay_url` to what came before there were several; RELAY_URLS adds others
// (comma-separated), such as one inside mainland China, where Cloudflare's is slow or out of reach. Each endpoint
// has all of them in its map: a station homes on the nearest, and a device dials it on every one (client/core-ts mesh.ts).
// RELAY_NAMES says what each is called where people see which one a connection goes through (经中继北京).
import { originList } from "./compat";

export const relayUrls = (env: { PUBLIC_ORIGIN: string; RELAY_URL?: string; RELAY_URLS?: string }): string[] => originList(env.RELAY_URL || env.PUBLIC_ORIGIN, env.RELAY_URLS);

type RelayEnv = { PUBLIC_ORIGIN: string; RELAY_URL?: string; RELAY_URLS?: string; RELAY_ENTRIES?: string; RELAY_NAMES?: Record<string, string> };

/** What a station or a device is told about the relays: the one, as before, all of them, and the names of those named.
 * A device (`device`) is told of RELAY_ENTRIES as well, after them: another way into a relay, through a machine its
 * own line reaches well and whose line to that relay is good (Beijing's to Hong Kong's: a phone in the mainland reaches
 * Beijing well, a station in Tokyo Hong Kong; 2026-10-08, bft). A device dials and measures every way it is told of
 * and keeps to the quickest (client/core-ts mesh.ts). A station is not: on the same relay twice under one key, the
 * connection made last takes the other's place there, and through the entry it may be the one on the worse line. */
export function relays(env: RelayEnv, device = false): { relay_url: string; relay_urls: string[]; relay_names: Record<string, string> } {
  const own = relayUrls(env);
  const entries = device ? originList("", env.RELAY_ENTRIES).filter((u) => !own.map(sameUrl).includes(sameUrl(u))) : [];
  const all = [...own, ...entries];
  const names = Object.fromEntries(all.flatMap((url) => (env.RELAY_NAMES?.[url] ? [[url, env.RELAY_NAMES[url]]] : [])));
  return { relay_url: all[0], relay_urls: all, relay_names: names };
}

/** At most this many relays of a workspace's own (directory.ts setRelays). */
export const MAX_RELAYS = 4;

/** A relay's URL as compared: its normal form without a trailing slash. */
export const sameUrl = (url: string): string => (URL.canParse(url) ? new URL(url).href : url).replace(/\/+$/, "");

/** A workspace's own relays as kept (a JSON array, or null for none). */
export function parseRelays(kept: unknown): string[] {
  if (typeof kept !== "string") return [];
  try {
    const list: unknown = JSON.parse(kept);
    return Array.isArray(list) ? list.filter((u): u is string => typeof u === "string") : [];
  } catch {
    return [];
  }
}

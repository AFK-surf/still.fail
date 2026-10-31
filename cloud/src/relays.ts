// The relays stations and devices use. The first is still.fail's own (RELAY_URL, or PUBLIC_ORIGIN's /relay:
// relay-worker.ts), handed out alone as `relay_url` to what came before there were several; RELAY_URLS adds others
// (comma-separated), such as one inside mainland China, where Cloudflare's is slow or out of reach. Each endpoint
// has all of them in its map: a station homes on the nearest, and a device dials it on every one (client/core-ts mesh.ts).
// RELAY_NAMES says what each is called where people see which one a connection goes through (经中继北京).
import { originList } from "./compat";
import type { WayView } from "./types";

export const relayUrls = (env: { PUBLIC_ORIGIN: string; RELAY_URL?: string; RELAY_URLS?: string }): string[] => originList(env.RELAY_URL || env.PUBLIC_ORIGIN, env.RELAY_URLS);

type RelayEnv = { PUBLIC_ORIGIN: string; RELAY_URL?: string; RELAY_URLS?: string; RELAY_ENTRIES?: string; RELAY_ENTRY_TARGETS?: Record<string, string>; RELAY_NAMES?: Record<string, string> };

/** What a station or a device is told about the relays: the one, as before, all of them, and the names of those named.
 * A device (`device`) is told of RELAY_ENTRIES as well, as `relay_entries`: another way into a relay, through a machine
 * its own line reaches well and whose line to that relay is good (Beijing's to Hong Kong's: a phone in the mainland
 * reaches Beijing well, a station in Tokyo Hong Kong; 2026-10-08, bft). `relay_entry_targets` says which relay is on
 * the other side. An entry is not another relay: putting both among `relay_urls` registers the same key twice and the
 * connections displace each other. New clients choose an entrance within the relay connection; older ones dial each
 * entry on an endpoint of its own. A station is not told the entries. */
export function relays(env: RelayEnv, device = false): { relay_url: string; relay_urls: string[]; relay_names: Record<string, string>; relay_entries?: string[]; relay_entry_targets?: Record<string, string> } {
  const own = relayUrls(env);
  const entries = device ? originList("", env.RELAY_ENTRIES).filter((u) => !own.map(sameUrl).includes(sameUrl(u))) : [];
  const names = Object.fromEntries([...own, ...entries].flatMap((url) => (env.RELAY_NAMES?.[url] ? [[url, env.RELAY_NAMES[url]]] : [])));
  const targets = Object.fromEntries(entries.flatMap((entry) => {
    const target = Object.entries(env.RELAY_ENTRY_TARGETS ?? {}).find(([url]) => sameUrl(url) === sameUrl(entry))?.[1];
    const relay = own.find((url) => target !== undefined && sameUrl(url) === sameUrl(target));
    return relay === undefined ? [] : [[entry, relay]];
  }));
  return { relay_url: own[0], relay_urls: own, relay_names: names, ...(device ? { relay_entries: entries, relay_entry_targets: targets } : {}) };
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

/** The ways to a station that are no relay, which a workspace may turn off as it may a relay: straight on its LAN, over
 * Tailscale, and a path iroh punches through (docs/cloud.md, 连接方式). */
export const WAY_KINDS = ["lan", "tailnet", "direct"] as const;

/** Every way a workspace's devices may reach its stations: still.fail's relays, its own, then the kinds that are no
 * relay; each on unless among `off`. */
export function waysOf(env: RelayEnv, own: string[], off: string[]): WayView[] {
  const isOff = (id: string) => off.some((o) => sameUrl(o) === sameUrl(id));
  return [
    ...relayUrls(env).map((url): WayView => ({ id: url, kind: "relay", ...(env.RELAY_NAMES?.[url] ? { name: env.RELAY_NAMES[url] } : {}), on: !isOff(url) })),
    ...own.map((url): WayView => ({ id: url, kind: "relay", own: true, on: !isOff(url) })),
    ...WAY_KINDS.map((kind): WayView => ({ id: kind, kind, on: !off.includes(kind) })),
  ];
}

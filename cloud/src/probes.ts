// still.fail's relays measured from inside the networks devices are on, every half hour (index.ts scheduled): a TCP
// ping to each relay's 443 from the same probes in China's carriers (China Mobile, China Telecom, China Unicom), its
// data centres and Hong Kong, by Globalping (https://globalping.io: free, its probes run by people and hosts who
// volunteer them). How a relay does for a network is seen before a device on it complains, and beside what devices
// report themselves (mesh.speed, docs/telemetry.md): 2026-10-30 Guangzhou's China Telecom reached Hong Kong's relay in
// 139 ms and Shenzhen's in 12. Each probe's result goes to Axiom as a `relay probe` line of that relay (tracing.ts).
// A round trip says nothing of how fast a line carries much: that devices tell (mesh.speed).

const GLOBALPING = "https://api.globalping.io/v1/measurements";

/** How often the relays are probed, in minutes: 4 relays × 20 probes twice an hour is well within Globalping's free 250 an hour. */
export const PROBE_EVERY_MIN = 30;

/** Where the probes are: each of China's carriers, its data centres (where stations run) and Hong Kong. */
export const LOCATIONS = [
  { magic: "China Mobile", limit: 5 },
  { magic: "Chinanet", limit: 5 },
  { magic: "China Unicom", limit: 5 },
  { country: "CN", limit: 3 },
  { country: "HK", limit: 2 },
];

/** How long the probes are given to answer before their results are read (a ping of 16 packets takes a few seconds). */
export const SETTLE_MS = 20_000;

/** What a probe found of a relay, as its `relay probe` line says it. */
export type ProbeLine = {
  probe_country: string;
  probe_region: string;
  probe_city: string;
  probe_asn: number;
  probe_network: string;
  /** Round trips of a TCP handshake to the relay's 443, ms (none when no packet came back). */
  rtt_avg?: number;
  rtt_min?: number;
  rtt_max?: number;
  /** The share of handshakes that got no answer, %. */
  loss?: number;
  status: string;
};

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

/**
 * Probes each relay (its URL) from the same probes and gives what each found, by relay. The first relay's measurement
 * picks the probes; the others' ask for those same ones (Globalping's `locations` given a measurement id), so the
 * relays are compared from the same places. A relay whose measurement could not be made has no lines.
 */
export async function probeRelays(relays: string[], fetch: Fetch, wait: (ms: number) => Promise<void>): Promise<Map<string, ProbeLine[]>> {
  const found = new Map<string, ProbeLine[]>();
  const ids = new Map<string, string>();
  let first: string | null = null;
  for (const relay of relays) {
    const target = URL.canParse(relay) ? new URL(relay).hostname.replace(/^\[|\]$/g, "") : null;
    if (target === null) continue;
    const response: Response | null = await fetch(GLOBALPING, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ type: "ping", target, locations: first ?? LOCATIONS, measurementOptions: { protocol: "TCP", port: 443, packets: 16 } }),
    }).catch(() => null);
    const id: unknown = response?.ok ? ((await response.json().catch(() => null)) as { id?: unknown } | null)?.id : null;
    if (typeof id !== "string") continue;
    first ??= id;
    ids.set(relay, id);
  }
  if (ids.size === 0) return found;
  await wait(SETTLE_MS);
  for (const [relay, id] of ids) {
    const response: Response | null = await fetch(`${GLOBALPING}/${id}`).catch(() => null);
    const value = response?.ok ? ((await response.json().catch(() => null)) as { results?: unknown } | null) : null;
    if (!Array.isArray(value?.results)) continue;
    found.set(relay, value.results.flatMap((r) => lineOf(r)));
  }
  return found;
}

function lineOf(result: unknown): ProbeLine[] {
  if (!result || typeof result !== "object") return [];
  const { probe, result: got } = result as { probe?: Record<string, unknown>; result?: { status?: unknown; stats?: Record<string, unknown> } };
  if (!probe || !got) return [];
  const text = (v: unknown) => (typeof v === "string" ? v.slice(0, 80) : "");
  const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
  const stats = got.stats ?? {};
  const line: ProbeLine = {
    probe_country: text(probe.country),
    probe_region: text(probe.state),
    probe_city: text(probe.city),
    probe_asn: num(probe.asn) ?? 0,
    probe_network: text(probe.network),
    status: text(got.status),
  };
  for (const [key, from] of [["rtt_avg", "avg"], ["rtt_min", "min"], ["rtt_max", "max"], ["loss", "loss"]] as const) {
    const v = num(stats[from]);
    if (v !== undefined) line[key] = v;
  }
  return [line];
}

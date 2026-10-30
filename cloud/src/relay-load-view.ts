// What the console shows of a relay's load (relay-load.ts), worked out from its counters when asked: rates from what
// they grew by. Kept apart from the Durable Object so tests can run it.
import type { Load } from "./relay-metrics";

/** Two samples further apart than this are a gap: no rate is made of them. */
export const GAP = 600;
/** What the console's "now" is made of: the samples of the last few minutes. */
const NOW = 300;

export type Sample = { at: number; load: Load };

/** One range of a relay's chart: buckets of `step` seconds from `start`, null where nothing was sampled. */
export type Series = {
  start: number;
  step: number;
  /** The most bytes a second it sent and received between two samples (about a minute): an average over the whole
   * bucket would hide every burst, and its peak would depend on the range shown. */
  sent: (number | null)[];
  recv: (number | null)[];
  /** The most connections it held. */
  open: (number | null)[];
  /** The share of packets it dropped (0–1). */
  dropped: (number | null)[];
};

export type RelayLoadView = {
  url: string;
  /** When it was last sampled (seconds); null: never. */
  at: number | null;
  /** Over the last few minutes; null when not sampled in them. */
  now: { sent: number; recv: number; dropped: number | null; rx: number | null; tx: number | null } | null;
  open: number | null;
  load1: number | null;
  /** Since midnight UTC, as the budget counts (relay.ts). */
  today: { bytes: number; frames: number };
  day: Series;
  week: Series;
};

/** What a counter grew by from a to b: all of b when it went down (the relay restarted and counts from zero). */
const grew = (a: number | undefined, b: number | undefined) => (a === undefined || b === undefined ? 0 : b >= a ? b - a : b);
const openOf = (load: Load) => Math.max(0, load.accepts - load.disconnects);

function series(samples: Sample[], now: number, step: number, count: number): Series {
  const start = (Math.floor(now / step) - count + 1) * step;
  const sums = Array.from({ length: count }, () => ({ secs: 0, sent: null as number | null, recv: null as number | null, packets: 0, dropped: 0, open: null as number | null }));
  for (let i = 1; i < samples.length; i++) {
    const [a, b] = [samples[i - 1]!, samples[i]!];
    const secs = b.at - a.at;
    const k = Math.floor((b.at - start) / step);
    if (k < 0 || k >= count || secs <= 0 || secs > GAP) continue;
    const s = sums[k]!;
    s.secs += secs;
    s.sent = Math.max(s.sent ?? 0, grew(a.load.sent, b.load.sent) / secs);
    s.recv = Math.max(s.recv ?? 0, grew(a.load.recv, b.load.recv) / secs);
    s.packets += grew(a.load.packets, b.load.packets);
    s.dropped += grew(a.load.dropped, b.load.dropped);
    s.open = Math.max(s.open ?? 0, openOf(b.load));
  }
  const of = (f: (s: (typeof sums)[number]) => number | null) => sums.map((s) => (s.secs > 0 ? f(s) : null));
  return {
    start,
    step,
    sent: of((s) => Math.round(s.sent!)),
    recv: of((s) => Math.round(s.recv!)),
    open: of((s) => s.open),
    dropped: of((s) => (s.packets + s.dropped > 0 ? s.dropped / (s.packets + s.dropped) : null)),
  };
}

/** When a sample was read: the relay's own time when it says it (relay-load.sh: its post can take many seconds to get
 * here, and timed by its arrival a minute's growth would be divided by however much less time it seemed to take). */
const readAt = (s: Sample): Sample => {
  const time = s.load.time;
  return time !== undefined && time <= s.at && time > s.at - GAP ? { at: time, load: s.load } : s;
};

/** What a relay did between two of its samples (about a minute), for Axiom (relay-load.ts): what each counter grew by,
 * the connections it held at the end, its machine's load. None when they are a gap apart or there was none before. */
export type RelayMinute = {
  secs: number;
  open: number;
  accepts: number;
  disconnects: number;
  sent: number;
  recv: number;
  packets: number;
  /** Packets dropped: the destination gone, its queue full, or one that waited there over 200 ms (zzj3720/iroh#1). */
  dropped: number;
  load1?: number;
};

export function relayMinute(before: Sample | null, after: Sample): RelayMinute | null {
  if (before === null) return null;
  const [a, b] = [readAt(before), readAt(after)];
  const secs = b.at - a.at;
  if (secs <= 0 || secs > GAP) return null;
  const by = (key: "accepts" | "disconnects" | "sent" | "recv" | "packets" | "dropped") => grew(a.load[key], b.load[key]);
  return {
    secs,
    open: openOf(b.load),
    accepts: by("accepts"),
    disconnects: by("disconnects"),
    sent: by("sent"),
    recv: by("recv"),
    packets: by("packets"),
    dropped: by("dropped"),
    ...(b.load.load1 !== undefined ? { load1: b.load.load1 } : {}),
  };
}

/** A relay's view from its samples (oldest first) at `now` (seconds). */
export function relayLoadView(url: string, received: Sample[], now: number): RelayLoadView {
  const samples = received.map(readAt).sort((a, b) => a.at - b.at);
  const last = samples.at(-1);
  const recent = samples.filter((s) => s.at >= now - NOW);
  let current: RelayLoadView["now"] = null;
  if (recent.length >= 2) {
    const secs = recent.at(-1)!.at - recent[0]!.at;
    // Step by step: a restart between two of them counts from zero there.
    const sum = (key: keyof Load) => recent.slice(1).reduce((n, b, i) => n + grew(recent[i]!.load[key], b.load[key]), 0);
    const machine = (key: "rx" | "tx") => (recent.every((s) => s.load[key] !== undefined) ? Math.round(sum(key) / secs) : null);
    const packets = sum("packets"), dropped = sum("dropped");
    current = {
      sent: Math.round(sum("sent") / secs),
      recv: Math.round(sum("recv") / secs),
      dropped: packets + dropped > 0 ? dropped / (packets + dropped) : null,
      rx: machine("rx"),
      tx: machine("tx"),
    };
  }
  const midnight = Math.floor(now / 86_400) * 86_400;
  const today = { bytes: 0, frames: 0 };
  for (let i = 1; i < samples.length; i++) {
    const [a, b] = [samples[i - 1]!, samples[i]!];
    if (b.at < midnight) continue;
    // The first sample of the day counts from the last one before it.
    today.bytes += grew(a.load.sent, b.load.sent) + grew(a.load.recv, b.load.recv);
    today.frames += grew(a.load.frames, b.load.frames);
  }
  const fresh = last !== undefined && last.at >= now - NOW;
  return {
    url,
    at: last?.at ?? null,
    now: current,
    open: fresh ? openOf(last.load) : null,
    load1: fresh ? (last.load.load1 ?? null) : null,
    today,
    day: series(samples, now, 300, 288),
    week: series(samples, now, 3600, 168),
  };
}

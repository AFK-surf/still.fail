// The relay process's counters; kept apart from the Durable Object so tests can read them.
/** What the relay process has counted since it started (its Prometheus metrics). */
export type Counters = { bytes: number; frames: number; accepts: number; disconnects: number };

/** Reads iroh-relay's metrics (text exposition) into the counters the budget uses. */
export function relayCounters(text: string): Counters {
  const value = (name: string) => Number(new RegExp(`^relayserver_${name}_total (\\S+)$`, "m").exec(text)?.[1] ?? 0) || 0;
  return {
    bytes: value("bytes_sent") + value("bytes_recv"),
    frames: ["send_packets_sent", "send_packets_recv", "other_packets_sent", "other_packets_recv", "got_ping", "sent_pong"].reduce((sum, name) => sum + value(name), 0),
    accepts: value("accepts"),
    disconnects: value("disconnects"),
  };
}

/**
 * What a relay's load is read from (relay-load.ts): its counters since it started, and, for a relay on a machine of
 * its own, the machine's network card, load average and clock (the lines relay-load.sh adds to the metrics it sends).
 */
export type Load = {
  /** Bytes it sent to clients and received from them. */
  sent: number;
  recv: number;
  frames: number;
  /** Packets it passed on to their destination, and those it dropped (the destination gone, or its queue full). */
  packets: number;
  dropped: number;
  accepts: number;
  disconnects: number;
  /** The machine's network card's bytes in and out, all traffic (TLS, the entries' forwarding, ssh). */
  rx?: number;
  tx?: number;
  /** The machine's load average over a minute. */
  load1?: number;
  /** When the relay's machine read these (seconds). */
  time?: number;
};

export function relayLoad(text: string): Load {
  const value = (name: string) => Number(new RegExp(`^${name} (\\S+)$`, "m").exec(text)?.[1] ?? NaN);
  const counter = (name: string) => value(`relayserver_${name}_total`) || 0;
  const counters = relayCounters(text);
  const load: Load = {
    sent: counter("bytes_sent"),
    recv: counter("bytes_recv"),
    frames: counters.frames,
    packets: counter("send_packets_sent"),
    dropped: counter("send_packets_dropped"),
    accepts: counters.accepts,
    disconnects: counters.disconnects,
  };
  for (const key of ["rx", "tx", "load1", "time"] as const) {
    const v = value(`node_${key}`);
    if (Number.isFinite(v) && v >= 0) load[key] = v;
  }
  return load;
}

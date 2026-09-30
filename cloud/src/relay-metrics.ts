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

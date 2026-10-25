// Shared relay budget; kept apart from the Durable Object so tests can read it.
export const LIMITS = {
  // Every open web page holds one relay connection, and every station one (and a keeper); sized for a few teams. At 64
  // and 120 it was full on 2026-10-08 (429 to bft's keeper and devices) once devices dialled it on a way of its own too.
  connections: 160,
  connectsPerMinute: 300,
  // Per-client rates and frame sizes are the relay process's own (relay-entrypoint.sh); these are all clients together.
  // At 5 GiB and 20M it ran out every day, on 2026-10-25 already at 19:00 in Beijing: everyone on it dropped and refused
  // until 08:00. 15 GiB a day (both ways) is under 450 GB out a month, inside what Containers include outside NA/EU (500 GB).
  bytesPerDay: 15 * 1024 * 1024 * 1024,
  framesPerDay: 60_000_000,
};

/** Trace batches each sender may send a minute (tracing.ts): a client or station sends one every few seconds at most. */
export const TELEMETRY_BATCHES_PER_MINUTE = 60;

// Shared relay budget; kept apart from the Durable Object so tests can read it.
export const LIMITS = {
  // A guard for the one relay process's memory (a lite container), not a share of anything: what costs money is the
  // bytes, below. It was 160, sized for a few teams before every device's and station's endpoint was home on every
  // relay (#2580); on 2026-10-30 the budget refused every new connection from 12:22 in Beijing. Its packets wait in it
  // 200 ms at most (still.fail's iroh-relay), so an idle connection holds little; the relay's minute line in Axiom says
  // how many are open, to raise this further or size the container by.
  connections: 2000,
  // Everyone on it back within a minute after it restarts (a deploy drops them all).
  connectsPerMinute: 3000,
  // Per-client rates and frame sizes are the relay process's own (relay-entrypoint.sh); these are all clients together.
  // At 5 GiB and 20M it ran out every day, on 2026-10-25 already at 19:00 in Beijing: everyone on it dropped and refused
  // until 08:00. 15 GiB a day (both ways) is under 450 GB out a month, inside what Containers include outside NA/EU (500 GB).
  bytesPerDay: 15 * 1024 * 1024 * 1024,
  framesPerDay: 60_000_000,
};

/** Trace batches each sender may send a minute (tracing.ts): a client or station sends one every few seconds at most. */
export const TELEMETRY_BATCHES_PER_MINUTE = 60;

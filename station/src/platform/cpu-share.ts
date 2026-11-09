/// CPU time since boot, all CPUs together: (busy, total).
export type Ticks = [busy: number, total: number];

/// The share between two samples, or null until the total has moved.
export function cpuShare([b0, t0]: Ticks, [b1, t1]: Ticks): number | null {
  return t1 > t0 ? Math.min(Math.max(Math.max(b1 - b0, 0) / (t1 - t0), 0), 1) : null;
}

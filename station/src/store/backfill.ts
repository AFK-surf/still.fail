// Foreground writes announce themselves before SQLite can wait for a lock. All background backfills share one permit,
// and take it only while no foreground write is pending. A write can still wait for the one batch already in progress.
export const BACKFILL_PAUSE_MS = 50;
/// A person waiting for an old page still gets a gap between batches, with foreground writes taking priority.
export const REQUEST_BACKFILL_PAUSE_MS = 5;

export function foreground<T>(priority: Int32Array | null, run: () => T): T {
  if (priority === null) return run();
  Atomics.add(priority, 0, 1);
  try { return run(); }
  finally { Atomics.sub(priority, 0, 1); }
}

/// False means another batch or a foreground write has priority. A missing buffer supports standalone workers/tests.
export function takeBackfill(priority: Int32Array | null, owner: number): boolean {
  if (priority === null) return true;
  if (Atomics.load(priority, 0) !== 0 || Atomics.compareExchange(priority, 1, 0, owner) !== 0) return false;
  if (Atomics.load(priority, 0) === 0) return true;
  giveBackfill(priority, owner);
  return false;
}

export function giveBackfill(priority: Int32Array | null, owner: number): void {
  if (priority !== null) Atomics.compareExchange(priority, 1, owner, 0);
}

/// A terminated worker cannot run its finally block; only release its own permit on exit.
export function releaseStoppedBackfill(buffer: SharedArrayBuffer | undefined, owner: number): void {
  if (buffer !== undefined) giveBackfill(new Int32Array(buffer), owner);
}

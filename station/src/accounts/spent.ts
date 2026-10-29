// How much of a window of a profile's allowance was used over a span (the card shared of a workspace's week: 2026-10-29
// 用户「它只是把每个账号的使用额度算进去，根本不是实际这段时间使用掉的额度」): not how full it reads now, which counts
// what was used before the span in a window begun before it, and nothing of a window that reset in it. Read from how
// full it read along the way (store.ts quota_readings): what it grew by between two readings of one window, and all a
// window read when it began after the one before (it reset, or was reset: an OpenAI subscription's redeemed).

/// A reading of a window: when, how full (percent), when it resets and how long it is (each where the provider says).
export type QuotaReading = { at: number; used: number; ends: number | null; minutes: number | null };

/// How far a window's reset may move between readings and still be the same window's (a provider rounds it anew).
const SAME_WINDOW_MS = 60 * 60_000;

/// What one window used after `since`, in percent of its allowance (a week's past 100 where it reset in it), of its
/// readings in order: from the last one at or before `since` on. With none before it, from its first after, unless
/// that window began after `since` (its whole reading then).
export function spentSince(readings: QuotaReading[], since: number): number {
  let prev: QuotaReading | null = null;
  let spent = 0;
  for (const r of readings) {
    if (r.at > since) {
      if (prev === null) {
        const began = r.ends !== null && r.minutes !== null ? r.ends - r.minutes * 60_000 : null;
        if (began !== null && began >= since) spent += r.used;
      } else if (r.used < prev.used || (r.ends !== null && prev.ends !== null && r.ends > prev.ends + SAME_WINDOW_MS)) {
        spent += r.used;
      } else {
        spent += r.used - prev.used;
      }
    }
    prev = r;
  }
  return Math.round(spent * 10) / 10;
}

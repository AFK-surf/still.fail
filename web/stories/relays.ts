// The admin console's 中继 (web/src/admin/console.tsx RelaysPage), as the core's `adminRelays` view would have it:
// still.fail's three relays and their load over the day (288 buckets of 5 minutes) or the week (168 of an hour), or a
// still.fail cloud from before them (404).
import { CoreError } from "../src/core/client.ts";
import type { DemoExtension } from "../src/demo/mount.tsx";

type Range = "day" | "week";
const RANGES: { id: Range; label: string }[] = [{ id: "day", label: "24 小时" }, { id: "week", label: "7 天" }];

/** The same made-up numbers every time (a story is measured, and drawn again to compare): a small seeded generator. */
function seeded(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 2 ** 32;
  };
}

/** The buckets of a range, ending at 16:00 on 10-20: how many, and each one's hour of the day. */
const BUCKETS: Record<Range, { n: number; hour: (i: number) => number }> = {
  day: { n: 288, hour: (i) => (16 - (287 - i) / 12 + 48) % 24 },
  week: { n: 168, hour: (i) => (16 - (167 - i) + 24 * 7) % 24 },
};

/** Where its times are marked: every six hours over the day, each midnight over the week. */
function ticks(range: Range): { index: number; label: string }[] {
  const { n, hour } = BUCKETS[range];
  const out: { index: number; label: string }[] = [];
  for (let i = 0; i < n; i++) {
    const h = hour(i);
    if (range === "day" && Number.isInteger(h) && h % 6 === 0) out.push({ index: i, label: `${String(h).padStart(2, "0")}:00` });
    if (range === "week" && h === 0) out.push({ index: i, label: `10/${20 - Math.floor((n - 1 - i) / 24)}` });
  }
  return out;
}

/** A day's rhythm: quiet before dawn, busiest in the afternoon and evening (China's time), 0.25–1. */
const rhythm = (h: number) => 0.62 - 0.37 * Math.cos(((h - 3) / 24) * 2 * Math.PI);

/** A series around `base` (its busiest), wandering, none (null) in the buckets of `gaps`. */
function series(range: Range, seed: number, base: number, gaps: [number, number][]): (number | null)[] {
  const { n, hour } = BUCKETS[range];
  const next = seeded(seed);
  let drift = 0;
  return Array.from({ length: n }, (_, i) => {
    drift = drift * 0.85 + (next() - 0.5) * 0.2;
    if (gaps.some(([from, to]) => i >= from && i <= to)) return null;
    return Math.max(0, Math.round(base * rhythm(hour(i)) * (1 + drift + (next() - 0.5) * 0.12) * 10) / 10);
  });
}

const peakOf = (values: (number | null)[][]) => Math.max(...values.flat().filter((v): v is number => v !== null));

type Made = {
  url: string; name: string; state: "online" | "offline" | "error"; seen: string; seed: number; rate: number; conns: number;
  dropped: string; droppedTone?: "amber"; gaps: [number, number][];
  /** A machine of its own (its card's rate and load), or still.fail's own on Cloudflare, held to a budget a day. */
  machine?: { card: string; load: string }; today?: string;
};

function relay(range: Range, r: Made) {
  const sent = series(range, r.seed, r.rate, r.gaps);
  const recv = series(range, r.seed + 1, r.rate * 0.82, r.gaps);
  const conns = series(range, r.seed + 2, r.conns, r.gaps).map((v) => (v === null ? null : Math.round(v)));
  const up = r.state === "online";
  const lastOf = (v: (number | null)[]) => v.findLast((x) => x !== null) ?? 0;
  return {
    url: r.url, name: r.name, state: r.state, seen: r.seen,
    numbers: [
      { label: "发送", value: up ? `${lastOf(sent).toFixed(1)} KB/s` : "–" },
      { label: "接收", value: up ? `${lastOf(recv).toFixed(1)} KB/s` : "–" },
      { label: "在线连接", value: up ? String(lastOf(conns)) : "–" },
      { label: "丢包率", value: r.dropped, ...(r.droppedTone ? { tone: r.droppedTone } : {}) },
      ...(r.machine ? [{ label: "网卡", value: r.machine.card }, { label: "负载", value: r.machine.load }] : []),
      ...(r.today ? [{ label: "今日用量", value: r.today }] : []),
    ],
    charts: [
      { id: "rate", label: "转发速率", peak: `峰值 ${peakOf([sent, recv]).toFixed(1)} KB/s`, series: [{ id: "sent", label: "发送", values: sent }, { id: "recv", label: "接收", values: recv }] },
      { id: "open", label: "在线连接", peak: `峰值 ${peakOf([conns])}`, series: [{ id: "open", label: "在线连接", values: conns }] },
    ],
    ticks: ticks(range),
  };
}

function view(range: Range) {
  const n = BUCKETS[range].n;
  // A gap the length of an hour's outage in either range.
  const hour = range === "day" ? 12 : 1;
  return {
    range, ranges: RANGES,
    relays: [
      relay(range, { url: "https://relay.still.fail", name: "Cloudflare", state: "online", seen: "1 分钟前更新", seed: 11, rate: 86, conns: 52, dropped: "0.1%", today: "1.8 GB / 5.0 GB · 36%", gaps: [[Math.round(n * 0.38), Math.round(n * 0.38) + hour]] }),
      relay(range, { url: "https://bj.relay.still.fail", name: "北京", state: "offline", seen: "42 分钟前更新", seed: 23, rate: 64, conns: 31, dropped: "–", gaps: [[n - (range === "day" ? 9 : 1), n - 1], [Math.round(n * 0.6), Math.round(n * 0.6) + hour * 2]] }),
      relay(range, { url: "https://hk.relay.still.fail", name: "香港", state: "online", seen: "1 分钟前更新", seed: 37, rate: 48, conns: 24, dropped: "6.2%", droppedTone: "amber", machine: { card: "出 61.4 KB/s · 入 58.9 KB/s", load: "0.18" }, gaps: [[Math.round(n * 0.15), Math.round(n * 0.15) + hour]] }),
    ],
  };
}

/** The relays as the core gives them (`normal`), or a cloud from before them answering 404 (`old`). */
export function relaysDemo(kind: "normal" | "old"): DemoExtension {
  return {
    topic: (t) => t.topic !== "adminRelays" ? undefined
      : kind === "old" ? new CoreError({ code: "not_found", message: "Not found", status: 404 })
      : view(t.range ?? "day"),
  };
}

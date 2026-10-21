// The console's 中继 page (`adminRelays`): how loaded still.fail's relays are, from what still.fail cloud worked out of
// their counters (GET /v1/admin/relays, cloud/src/relay-load-view.ts): the numbers now, and a chart over a day or a week.
import * as format from "../format.ts";
import { t } from "../i18n.ts";
import { arr as arrU, get as getU } from "../util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const num = (v: unknown, k: string): number | null => (typeof get(v, k) === "number" && Number.isFinite(get(v, k)) ? get(v, k) : null);
const values = (v: unknown, k: string): (number | null)[] => arr(get(v, k)).map((x) => (typeof x === "number" && Number.isFinite(x) ? x : null));

/** Sampled within this long: shown as up. */
const FRESH = 300;
/** A share of packets dropped from which it is pointed at. */
const DROPPED_AMBER = 0.05;
const DROPPED_RED = 0.2;

export const RANGES = ["day", "week"] as const;
export type Range = (typeof RANGES)[number];

const rate = (bytes: number) => `${format.bytes(bytes)}/s`;
const percent = (share: number) => `${format.fixed1(share * 100)}%`;
const peak = (series: (number | null)[][]) => Math.max(0, ...series.flat().filter((v): v is number => v !== null));

/** Where its x axis is marked: every six hours over a day, every midnight over a week, in local time. */
function ticks(start: number, step: number, count: number, range: Range, offsetMin: number): { index: number; label: string }[] {
  const out: { index: number; label: string }[] = [];
  for (let i = 0; i < count; i++) {
    const ms = (start + i * step) * 1000;
    const [, month, day, , hour, minute] = format.local(ms, offsetMin);
    if (minute !== 0) continue;
    if (range === "day" && hour % 6 === 0) out.push({ index: i, label: format.clock(ms, offsetMin) });
    if (range === "week" && hour === 0) out.push({ index: i, label: `${month}/${day}` });
  }
  return out;
}

function relay(r: J, range: Range, now: number, offsetMin: number) {
  const url = String(get(r, "url") ?? ""), name = String(get(r, "name") ?? get(r, "url") ?? "");
  const at = num(r, "at");
  // Never heard from (its timer not set up yet): nothing to show but that.
  if (at === null) return { url, name, state: "error", seen: t("core-views.admin.relay.never"), numbers: [], charts: [], ticks: [] };
  const state = now - at <= FRESH ? "online" : "offline";
  const seen = t("core-views.admin.relay.seen", { when: format.relativeTime(at * 1000, now * 1000, offsetMin) });
  const current = get(r, "now");
  const numbers: { label: string; value: string; tone?: "amber" | "red" }[] = [];
  const sent = num(current, "sent"), recv = num(current, "recv");
  numbers.push({ label: t("core-views.admin.relay.sent"), value: sent === null ? "–" : rate(sent) });
  numbers.push({ label: t("core-views.admin.relay.recv"), value: recv === null ? "–" : rate(recv) });
  const open = num(r, "open");
  numbers.push({ label: t("core-views.admin.relay.open"), value: open === null ? "–" : String(open) });
  const dropped = num(current, "dropped");
  numbers.push({
    label: t("core-views.admin.relay.dropped"),
    value: dropped === null ? "–" : percent(dropped),
    ...(dropped !== null && dropped >= DROPPED_RED ? { tone: "red" as const } : dropped !== null && dropped >= DROPPED_AMBER ? { tone: "amber" as const } : {}),
  });
  const rx = num(current, "rx"), tx = num(current, "tx");
  if (rx !== null && tx !== null) numbers.push({ label: t("core-views.admin.relay.card"), value: t("core-views.admin.relay.card_value", { out: rate(tx), in: rate(rx) }) });
  const load1 = num(r, "load1");
  if (load1 !== null) numbers.push({ label: t("core-views.admin.relay.load"), value: load1.toFixed(2) });
  // still.fail's own, held to a budget a day (cloud/src/relay.ts).
  const limits = get(r, "limits");
  const bytesLimit = num(limits, "bytes"), framesLimit = num(limits, "frames");
  if (bytesLimit !== null && framesLimit !== null) {
    const bytes = num(get(r, "today"), "bytes") ?? 0, frames = num(get(r, "today"), "frames") ?? 0;
    const used = Math.max(bytes / bytesLimit, frames / framesLimit);
    numbers.push({
      label: t("core-views.admin.relay.today"),
      value: t("core-views.admin.relay.today_value", { used: format.bytes(bytes), limit: format.bytes(bytesLimit), percent: Math.round(used * 100) }),
      ...(used >= 1 ? { tone: "red" as const } : used >= 0.8 ? { tone: "amber" as const } : {}),
    });
  }
  const s = get(r, range);
  const start = num(s, "start") ?? 0, step = num(s, "step") ?? 1;
  const sentSeries = values(s, "sent"), recvSeries = values(s, "recv"), openSeries = values(s, "open");
  return {
    url,
    name,
    state,
    seen,
    numbers,
    charts: [
      {
        id: "rate",
        label: t("core-views.admin.relay.chart_rate"),
        peak: t("core-views.admin.relay.peak", { value: rate(peak([sentSeries, recvSeries])) }),
        series: [
          { id: "sent", label: t("core-views.admin.relay.sent"), values: sentSeries },
          { id: "recv", label: t("core-views.admin.relay.recv"), values: recvSeries },
        ],
      },
      {
        id: "open",
        label: t("core-views.admin.relay.open"),
        peak: t("core-views.admin.relay.peak", { value: String(peak([openSeries])) }),
        series: [{ id: "open", label: t("core-views.admin.relay.open"), values: openSeries }],
      },
    ],
    ticks: ticks(start, step, sentSeries.length, range, offsetMin),
  };
}

/** The page, from what /v1/admin/relays answered; `now` in seconds. */
export function relays(v: J, range: string | null, now: number, offsetMin: number) {
  const shown: Range = range === "week" ? "week" : "day";
  return {
    range: shown,
    ranges: RANGES.map((id) => ({ id, label: t(`core-views.admin.relay.range.${id}`) })),
    relays: arr(get(v, "relays")).map((r) => relay(r, shown, now, offsetMin)),
  };
}

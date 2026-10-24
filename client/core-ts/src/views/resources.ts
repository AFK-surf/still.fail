// What of the stations' machines still.fail uses (the resources page), as Activity Monitor says it: every online
// station's GET /resources put together for a scope. A few totals with the last minutes' line, and what uses them by
// whose (a chat, the agents, the desktop app, the station), each with its processes; the page sorts, filters and
// flattens them. Imports only i18n.ts and what imports nothing: the web's demo draws its made-up station with it.
import { t } from "../i18n.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const get = (v: unknown, k: string): J => (v !== null && typeof v === "object" ? (v as Record<string, unknown>)[k] : undefined);
const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);

const HOUR_MS = 3_600_000;
const HOURS = 24;

/// A station's GET /resources as read (the store's Value: what it answered, or why not), for the view.
export type Source = { address: string; name: string; online: boolean; value: { ok: unknown } | { err: { status?: number | undefined; message: string } } | undefined };
/// What the page says it waits on (looks.ts waitNote).
type Wait = (waiting: string[], failing: { station: string; name: string; message: string }[], empty: boolean) => unknown;

/// CPU as Activity Monitor says it: 100% a whole core. 134% · 12.8% · 0.4% · 0%.
export function cpu(percent: number): string {
  if (percent <= 0) return "0%";
  if (percent >= 100) return `${Math.round(percent)}%`;
  return `${percent.toFixed(1)}%`;
}

/// Memory, in units of 1024 as Activity Monitor says it: 32 GB · 2.78 GB · 412 MB · 3.1 MB.
export function memory(bytes: number): string {
  const gb = bytes / 1024 ** 3;
  const mb = bytes / 1024 ** 2;
  if (gb >= 10) return `${Math.round(gb)} GB`;
  if (gb >= 1) return `${gb.toFixed(2)} GB`;
  if (mb >= 10) return `${Math.round(mb)} MB`;
  return `${mb.toFixed(1)} MB`;
}

/// Watts: 12 W · 4.9 W · 0.42 W · <0.01 W.
export function watts(w: number): string {
  if (w <= 0) return "0 W";
  if (w < 0.01) return "<0.01 W";
  if (w < 1) return `${w.toFixed(2)} W`;
  if (w < 10) return `${w.toFixed(1)} W`;
  return `${Math.round(w)} W`;
}

const wakeups = (n: number) => String(Math.round(n));

type Use = { cpu: number; memory: number; watts: number; wakeups: number };
const useOf = (v: unknown): Use => ({ cpu: num(get(v, "cpu")), memory: num(get(v, "memory")), watts: num(get(v, "watts")), wakeups: num(get(v, "wakeups")) });
const said = (u: Use) => ({ ...u, cpuText: cpu(u.cpu), memoryText: memory(u.memory), wattsText: watts(u.watts), wakeupsText: wakeups(u.wakeups) });
const plus = (a: Use, b: Use): Use => ({ cpu: a.cpu + b.cpu, memory: a.memory + b.memory, watts: a.watts + b.watts, wakeups: a.wakeups + b.wakeups });
const ZERO: Use = { cpu: 0, memory: 0, watts: 0, wakeups: 0 };

function percent(part: number, whole: number): string {
  if (whole <= 0) return "0%";
  const p = (part / whole) * 100;
  return p > 0 && p < 1 ? "<1%" : `${p.toFixed(0)}%`;
}

/// The kinds the page filters by, in its order: a chat's (the agents' with them), the app's, the station's.
const KINDS = ["chats", "app", "station"] as const;
const kindOf = (key: string): (typeof KINDS)[number] => (key === "app" ? "app" : key === "station" ? "station" : "chats");

/// The view at `now`.
export function resourcesView(sources: Source[], now: number, waitNote: Wait): J {
  const several = sources.filter((s) => s.online).length > 1;
  const waiting: string[] = [];
  const failing: { station: string; name: string; message: string }[] = [];
  const notes: string[] = [];
  let counted = false;
  let everyMs = 0;
  let cores = 0;
  let machineMemory = 0;
  let total = ZERO;
  let processes = 0;
  let day = 0;
  // The last minutes' totals, each station's points summed by when (a look of each is some seconds apart).
  const lines: Map<number, Use>[] = [];
  const groups: J[] = [];
  for (const s of sources) {
    if (!s.online) {
      notes.push(t("core-views.resources.note.offline", { name: s.name }));
      continue;
    }
    if (s.value === undefined) {
      waiting.push(s.name);
      continue;
    }
    if ("err" in s.value) {
      const e = s.value.err;
      if (e.status !== 404) failing.push({ station: s.address, name: s.name, message: e.message });
      notes.push(e.status === 404 ? t("core-views.resources.note.outdated", { name: s.name }) : t("core-views.named_error", { name: s.name, error: e.message }));
      continue;
    }
    const v = s.value.ok;
    if (get(v, "counted") !== true) {
      notes.push(t("core-views.resources.note.uncounted", { name: s.name }));
      continue;
    }
    counted = true;
    everyMs = Math.max(everyMs, num(get(v, "everyMs")));
    cores += num(get(get(v, "machine"), "cores"));
    machineMemory += num(get(get(v, "machine"), "memory"));
    total = plus(total, useOf(get(v, "total")));
    lines.push(new Map(arr(get(v, "history")).map((p) => [Math.round(num(get(p, "at")) / 5000), useOf(p)])));
    for (const h of arr(get(v, "hours"))) {
      if (num(get(h, "at")) <= now - HOURS * HOUR_MS) continue;
      for (const j of Object.values(get(h, "joules") ?? {})) day += num(j) / 3600;
    }
    const named = get(v, "chats") ?? {};
    for (const g of arr(get(v, "groups"))) {
      const key = String(get(g, "key") ?? "");
      const session = typeof get(g, "session") === "string" ? (get(g, "session") as string) : null;
      const kind = kindOf(key);
      const c = session !== null ? get(named, session) : undefined;
      const thread = typeof get(c, "thread") === "number" ? get(c, "thread") : null;
      const title =
        key === "app" ? t("core-views.resources.whose.app")
        : key === "station" ? t("core-views.resources.whose.station")
        : key === "agents" || session === null ? t("core-views.resources.whose.agents")
        : typeof get(c, "title") === "string" && get(c, "title") !== "" ? get(c, "title") : t("core-views.resources.whose.chat");
      const procs = arr(get(g, "processes"));
      processes += procs.length;
      groups.push({
        key: `${s.address}\n${key}`,
        kind,
        title,
        // What it is, where its title does not say it already (a chat's: 对话; the app's and the station's say it).
        kindText: [...(several ? [s.name] : []), ...(kind === "chats" ? [t(`core-views.resources.kind.${kind}`)] : [])].join(" · "),
        ...(session !== null && key !== "agents" ? { chat: { station: s.address, ...(thread !== null ? { thread } : { session }) } } : {}),
        use: said(useOf(g)),
        processes: procs.map((p) => ({ key: `${s.address}\n${num(get(p, "pid"))}`, pid: num(get(p, "pid")), name: String(get(p, "name") ?? "?"), use: said(useOf(p)) })),
      });
    }
  }
  const at = [...new Set(lines.flatMap((l) => [...l.keys()]))].sort((a, b) => a - b);
  const line = (k: keyof Use) => at.map((i) => lines.reduce((n, l) => n + (l.get(i)?.[k] ?? 0), 0));
  const tiles = [
    { key: "cpu", label: t("core-views.resources.tile.cpu"), value: cpu(total.cpu), sub: cores > 0 ? t("core-views.resources.tile.cpu_sub", { cores, percent: percent(total.cpu, cores * 100) }) : "", points: line("cpu") },
    { key: "memory", label: t("core-views.resources.tile.memory"), value: memory(total.memory), sub: machineMemory > 0 ? t("core-views.resources.tile.memory_sub", { total: memory(machineMemory), percent: percent(total.memory, machineMemory) }) : "", points: line("memory") },
    { key: "watts", label: t("core-views.resources.tile.watts"), value: watts(total.watts), sub: t("core-views.resources.tile.watts_sub", { wh: watts(day).replace(/ W$/, " Wh") }), points: line("watts") },
    { key: "wakeups", label: t("core-views.resources.tile.wakeups"), value: t("core-views.resources.tile.wakeups_value", { n: wakeups(total.wakeups) }), sub: t("core-views.resources.tile.wakeups_sub", { n: processes }), points: line("wakeups") },
  ];
  return {
    wait: waitNote(waiting, failing, !counted),
    empty: !counted,
    everyMs,
    tiles,
    kinds: KINDS.map((k) => ({ key: k, label: t(`core-views.resources.kind.${k}`) })),
    groups: groups.sort((a, b) => b.use.cpu - a.use.cpu),
    notes,
    basis: t("core-views.resources.basis"),
  };
}

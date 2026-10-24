// What of the stations' machines still.fail uses (a station's 进程), as Activity Monitor says it: every online
// station's GET /resources put together for a scope. A few totals with the last minutes' line, and what uses them by
// whose (a chat, the agents, the desktop app, the station), each with its processes; the page sorts, filters and
// flattens them. Imports only i18n.ts and what imports nothing: the web's demo draws its made-up station with it.
import { t } from "../i18n.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const get = (v: unknown, k: string): J => (v !== null && typeof v === "object" ? (v as Record<string, unknown>)[k] : undefined);
const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);


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

/// Bytes a second, in units of 1024 as Activity Monitor says them: 0 B/s · 812 B/s · 4.2 KB/s · 18 MB/s.
export function rate(bytes: number): string {
  if (bytes < 1) return "0 B/s";
  const units = ["B", "KB", "MB", "GB"];
  let n = bytes;
  let i = 0;
  for (; n >= 1024 && i < units.length - 1; i++) n /= 1024;
  return `${i === 0 || n >= 10 ? Math.round(n) : n.toFixed(1)} ${units[i]}/s`;
}

/// `net`: in and out together, `disk` read and written together: what the page sorts by.
type Use = { cpu: number; memory: number; netIn: number; netOut: number; net: number; diskRead: number; diskWrite: number; disk: number };
const useOf = (v: unknown): Use => {
  const netIn = num(get(v, "netIn"));
  const netOut = num(get(v, "netOut"));
  const diskRead = num(get(v, "diskRead"));
  const diskWrite = num(get(v, "diskWrite"));
  return { cpu: num(get(v, "cpu")), memory: num(get(v, "memory")), netIn, netOut, net: netIn + netOut, diskRead, diskWrite, disk: diskRead + diskWrite };
};
const said = (u: Use) => ({ ...u, cpuText: cpu(u.cpu), memoryText: memory(u.memory), netText: rate(u.net), diskText: rate(u.disk) });
const plus = (a: Use, b: Use): Use => ({
  cpu: a.cpu + b.cpu, memory: a.memory + b.memory, netIn: a.netIn + b.netIn, netOut: a.netOut + b.netOut, net: a.net + b.net,
  diskRead: a.diskRead + b.diskRead, diskWrite: a.diskWrite + b.diskWrite, disk: a.disk + b.disk,
});
const ZERO: Use = { cpu: 0, memory: 0, netIn: 0, netOut: 0, net: 0, diskRead: 0, diskWrite: 0, disk: 0 };

function percent(part: number, whole: number): string {
  if (whole <= 0) return "0%";
  const p = (part / whole) * 100;
  return p > 0 && p < 1 ? "<1%" : `${p.toFixed(0)}%`;
}

/// The kinds the page filters by, in its order: a chat's (the agents' with them), the app's, the station's.
const KINDS = ["chats", "app", "station"] as const;
const kindOf = (key: string): (typeof KINDS)[number] => (key === "app" ? "app" : key === "station" ? "station" : "chats");

/// The view (`_now`: when, for callers from before the hours went).
export function resourcesView(sources: Source[], _now: number, waitNote: Wait): J {
  const several = sources.filter((s) => s.online).length > 1;
  const waiting: string[] = [];
  const failing: { station: string; name: string; message: string }[] = [];
  const notes: string[] = [];
  let counted = false;
  // Some station read the network (one from before does not).
  let net = false;
  let disk = false;
  let everyMs = 0;
  let cores = 0;
  let machineMemory = 0;
  let total = ZERO;
  // The last minutes' totals, each station's points summed by when (a look of each is some seconds apart).
  const lines: Map<number, Use>[] = [];
  const groups: J[] = [];
  const each: J[] = [];
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
    if (get(v, "net") === true) net = true;
    if (get(v, "disk") === true) disk = true;
    everyMs = Math.max(everyMs, num(get(v, "everyMs")));
    cores += num(get(get(v, "machine"), "cores"));
    machineMemory += num(get(get(v, "machine"), "memory"));
    total = plus(total, useOf(get(v, "total")));
    each.push({ station: s.address, net: get(v, "net") === true, use: said(useOf(get(v, "total"))) });
    lines.push(new Map(arr(get(v, "history")).map((p) => [Math.round(num(get(p, "at")) / 5000), useOf(p)])));
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
      groups.push({
        key: `${s.address}\n${key}`,
        kind,
        title,
        // What it is, where its title does not say it already (a chat's: 对话; the app's and the station's say it).
        kindText: [...(several ? [s.name] : []), ...(kind === "chats" ? [t(`core-views.resources.kind.${kind}`)] : [])].join(" · "),
        ...(session !== null && key !== "agents" ? { chat: { station: s.address, ...(thread !== null ? { thread } : { session }) } } : {}),
        station: s.address,
        session: key !== "agents" ? session : null,
        use: said(useOf(g)),
        processes: procs.map((p) => ({ key: `${s.address}\n${num(get(p, "pid"))}`, pid: num(get(p, "pid")), name: String(get(p, "name") ?? "?"), endable: get(p, "endable") === true, use: said(useOf(p)) })),
      });
    }
  }
  const at = [...new Set(lines.flatMap((l) => [...l.keys()]))].sort((a, b) => a - b);
  const line = (k: keyof Use) => at.map((i) => lines.reduce((n, l) => n + (l.get(i)?.[k] ?? 0), 0));
  const tiles = [
    { key: "cpu", label: t("core-views.resources.tile.cpu"), value: cpu(total.cpu), sub: cores > 0 ? t("core-views.resources.tile.cpu_sub", { cores, percent: percent(total.cpu, cores * 100) }) : "", points: line("cpu") },
    { key: "memory", label: t("core-views.resources.tile.memory"), value: memory(total.memory), sub: machineMemory > 0 ? t("core-views.resources.tile.memory_sub", { total: memory(machineMemory), percent: percent(total.memory, machineMemory) }) : "", points: line("memory") },
    ...(disk ? [{ key: "disk", label: t("core-views.resources.tile.disk"), value: `↓ ${rate(total.diskRead)}`, sub: `↑ ${rate(total.diskWrite)}`, points: line("disk") }] : []),
    ...(net ? [{ key: "net", label: t("core-views.resources.tile.net"), value: `↓ ${rate(total.netIn)}`, sub: `↑ ${rate(total.netOut)}`, points: line("net") }] : []),
  ];
  return {
    wait: waitNote(waiting, failing, !counted),
    empty: !counted,
    net,
    disk,
    everyMs,
    tiles,
    kinds: KINDS.map((k) => ({ key: k, label: t(`core-views.resources.kind.${k}`) })),
    groups: groups.sort((a, b) => b.use.cpu - a.use.cpu),
    stations: each,
    notes,
    basis: t("core-views.resources.basis"),
  };
}

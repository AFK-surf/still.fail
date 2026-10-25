// The card shared of a workspace's agents at work (the `fleet` view; 2026-10-26 用户：「来点花哨的设计和更多信息」):
// how many are at work now and where, each station at work with its machine and the makers of its agents, the models
// at work and how many of each, and what they did over the last 7 days (the usage view's days and totals).
import { t } from "../i18n.ts";
import * as present from "../present.ts";
import { arr as arrU, get as getU } from "../util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

/// A station as the card reads it: up or not, how many of its agents are at work as it counts them (its overview's
/// `counts.running`), what its machine is (its host's reading, raw), its chats' rows as listed.
export type FleetStation = { station: string; name: string; emoji?: string | null; icon?: string | null; online: boolean; running: number; host: J; rows: J[] };

/// How many models at most the card names (the rest are left out: the card says how many there are).
const MODELS_MOST = 4;

/// What a machine is in a few words: its chip and its memory (Apple M2 Max · 64 GB), as its card names it.
export function machineOf(host: J): string | null {
  const shown = present.host(host);
  const chip = str(get(host, "cpuModel"));
  const total = get(get(host, "memory"), "totalBytes");
  const memory = typeof total === "number" && total > 0 ? Math.round(total / 1024 ** 3) : 0;
  const parts = [chip, memory > 0 ? `${memory} GB` : null].filter((x): x is string => x !== null);
  return parts.length > 0 ? parts.join(" · ") : (str(get(shown, "identity")) ?? null);
}

/// The card: `stations` as read, the usage view of the last 7 days (null while it is not made yet), and when it is
/// (`at`, in words: 10月26日 04:12).
export function fleetView(stations: FleetStation[], usage: J, at = ""): J {
  const models = new Map<string, { name: string; maker: string | null; count: number }>();
  const shown: J[] = [];
  let running = 0;
  for (const s of stations) {
    if (!s.online || s.running <= 0) continue;
    running += s.running;
    const makers = new Map<string, number>();
    for (const row of s.rows) {
      for (const a of arr(get(row, "agents"))) {
        if (present.markOf(a) !== "run") continue;
        const m = present.session(a);
        const name = str(get(m, "modelName")) ?? str(get(m, "runtimeText")) ?? "";
        const maker = str(get(get(m, "maker"), "id"));
        if (maker !== null) makers.set(maker, (makers.get(maker) ?? 0) + 1);
        if (name === "") continue;
        const was = models.get(name);
        models.set(name, { name, maker, count: (was?.count ?? 0) + 1 });
      }
    }
    shown.push({
      station: s.station,
      name: s.name,
      ...(s.emoji ? { emoji: s.emoji } : {}),
      ...(s.icon ? { icon: s.icon } : {}),
      machine: machineOf(s.host),
      running: s.running,
      makers: [...makers.entries()].sort((a, b) => b[1] - a[1]).map(([id]) => id),
    });
  }
  shown.sort((a, b) => b.running - a.running);
  // (the most first, then by name as it is spelled: no Intl in the core)
  const all = [...models.values()].sort((a, b) => b.count - a.count || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  const where = [t("core-logic.fleet.machines", { n: shown.length })];
  if (all.length > 0) where.push(t("core-logic.fleet.models", { n: all.length }));
  return {
    running,
    unit: t("core-logic.fleet.unit", { n: running }),
    at,
    where: where.join(" · "),
    stations: shown,
    models: all.slice(0, MODELS_MOST).map((m) => ({ name: m.name, ...(m.maker !== null ? { maker: m.maker } : {}), count: m.count, text: `×${m.count}` })),
    ...(week(usage) ?? {}),
  };
}

/// The last 7 days as the usage view has them: its calls, input tokens and cost (its tiles), and each day's calls as a
/// share of the busiest; none while it is read or nothing was spent.
function week(usage: J): J {
  if (usage === null || usage === undefined || get(usage, "empty") === true) return null;
  const tiles = arr(get(usage, "tiles"));
  const days = arr(get(usage, "daily"));
  if (tiles.length < 3 || days.length === 0) return null;
  const most = Math.max(...days.map((d) => (typeof d.calls === "number" ? d.calls : 0)), 0);
  if (most <= 0) return null;
  return {
    week: {
      title: t("core-logic.fleet.week"),
      stats: [tiles[1], tiles[2], tiles[0]].map((x) => ({ label: str(get(x, "label")) ?? "", value: str(get(x, "value")) ?? "" })),
      days: days.map((d) => ({ label: str(d.label) ?? "", share: (typeof d.calls === "number" ? d.calls : 0) / most, today: d.today === true })),
    },
  };
}

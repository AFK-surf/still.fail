// What a station tells the others of its machine and how busy it is (docs/station-peers.md "Load"), for agents choosing
// where a station_task runs: `describe` answers it as `load`, station_list says it. Measured where the station's own
// pages measure it (api/host.ts: GET /host and the events' host samples, the ten-second cache shared), plus what only
// this needs: the CPUs over about a minute (Host.recentBusy), the GPUs (gpu.ts), what runs here and the relay.
import type { Gpu } from "./gpu.ts";

type Json = any;

export type Load = {
  os: string;
  arch: string;
  cpus: number | null;
  cpuModel: string;
  /// How busy the CPUs have been (0–1) over `seconds` (about a minute; null: since the moment before).
  cpuBusy: { share: number; seconds: number | null } | null;
  /// The run queue over 1, 5 and 15 minutes; null where the machine has none (Windows).
  loadAvg: number[] | null;
  memory: { totalBytes: number | null; availableBytes: number | null };
  /// The file system holding the station's data, where remote tasks run (remote/sessions).
  disk: { path: string; totalBytes: number | null; freeBytes: number | null };
  gpus: Gpu[] | null;
  running: { remoteTasks: number; jobs: number; services: number; turns: number };
  /// Its home relay, and how long a ping to one of still.fail's relays took (mesh/relays.ts); null off the mesh.
  relay: { home: string | null; ping: { relay: string; ms: number } | null } | null;
  checkedAt: number | null;
};

export type LoadParts = {
  host: { sample(): Promise<any>; recentBusy(): { busy: number; seconds: number } | null };
  gpus: { read(): Promise<Gpu[] | null> };
  running(): Load["running"];
  relay(): Load["relay"];
};

const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/// The station's load now.
export async function measure(parts: LoadParts): Promise<Load> {
  const [info, gpus] = await Promise.all([parts.host.sample(), parts.gpus.read().catch(() => null)]);
  const recent = parts.host.recentBusy();
  const cpus = num(info?.cpus);
  const total = num(info?.memory?.totalBytes);
  const used = num(info?.memory?.usedBytes);
  const memTotal = total !== null && total > 0 ? total : null;
  const available = info?.memory?.known !== false && memTotal !== null && used !== null && used >= 0 && used <= memTotal ? memTotal - used : null;
  const size = num(info?.disk?.totalBytes);
  const diskTotal = size !== null && size > 0 ? size : null;
  const free = num(info?.disk?.freeBytes);
  return {
    os: String(info?.os ?? ""),
    arch: String(info?.arch ?? ""),
    cpus: cpus !== null && cpus > 0 ? cpus : null,
    cpuModel: String(info?.cpuModel ?? ""),
    cpuBusy: recent !== null ? { share: recent.busy, seconds: recent.seconds } : typeof info?.cpuBusy === "number" ? { share: info.cpuBusy, seconds: null } : null,
    loadAvg: Array.isArray(info?.loadAvg) ? info.loadAvg : null,
    memory: { totalBytes: memTotal, availableBytes: available },
    disk: { path: String(info?.disk?.path ?? ""), totalBytes: diskTotal, freeBytes: diskTotal !== null && free !== null && free >= 0 && free <= diskTotal ? free : null },
    gpus,
    running: parts.running(),
    relay: parts.relay(),
    checkedAt: num(info?.checkedAt),
  };
}

/// The station's relay as its mesh last saw it: where iroh homes, and the last ping (mesh/relays.ts notes it).
export class Net {
  home: () => string | null = () => null;
  private ping: { relay: string; ms: number } | null = null;
  /// Off the mesh again: nothing known.
  private on = false;

  attach(home: () => string | null): () => void {
    this.home = home;
    this.on = true;
    return () => {
      this.home = () => null;
      this.ping = null;
      this.on = false;
    };
  }

  pinged(relay: string, ms: number): void {
    this.ping = { relay, ms: Math.round(ms) };
  }

  seen(): Load["relay"] {
    return this.on ? { home: this.home(), ping: this.ping } : null;
  }
}

/// What an older station's `describe` (no `load`) is said as.
export const OLDER = "unknown (older station)";

const GIB = 1024 ** 3;
function gib(bytes: number): string {
  const g = bytes / GIB;
  return `${g >= 100 ? Math.round(g) : Math.round(g * 10) / 10} GiB`;
}
const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;

/// A GPU in a few words: Apple's chip and its cores (just the cores when the CPU's name already says the chip),
/// NVIDIA's memory and how busy.
function gpuText(gpu: Json, cpuModel: string): string {
  const cores = num(gpu?.cores);
  const name = typeof gpu?.name === "string" ? gpu.name : "GPU";
  const parts: string[] = [];
  if (cores !== null) parts.push(`${cores} cores`);
  const total = num(gpu?.memoryTotalBytes);
  const used = num(gpu?.memoryUsedBytes);
  if (total !== null) parts.push(used !== null ? `${gib(total - used)} of ${gib(total)} free` : gib(total));
  const busy = num(gpu?.busy);
  if (busy !== null) parts.push(`${Math.round(busy * 100)}% busy`);
  if (name === cpuModel && parts.length > 0) return `GPU ${parts.join(", ")}`;
  return parts.length > 0 ? `GPU ${name} (${parts.join(", ")})` : `GPU ${name}`;
}

/// One line saying a station's load (what `describe` answered as `load`), for station_list. Whatever a station leaves
/// out (or a newer one says otherwise) is left out of the line.
export function summary(load: Json): string {
  if (load === null || typeof load !== "object") return OLDER;
  if (typeof load.unavailable === "string") return `unknown (${load.unavailable})`;
  const cpuModel = typeof load.cpuModel === "string" ? load.cpuModel : "";
  const machine: string[] = [];
  const what = [load.arch, load.os].filter((s) => typeof s === "string" && s !== "").join(" ");
  if (what !== "") machine.push(what);
  const cpus = num(load.cpus);
  if (cpus !== null) machine.push(`${cpus} cores${cpuModel !== "" ? ` (${cpuModel})` : ""}`);
  if (Array.isArray(load.gpus)) for (const gpu of load.gpus) machine.push(gpuText(gpu, cpuModel));
  const busy: string[] = [];
  const share = num(load.cpuBusy?.share);
  if (share !== null) {
    const seconds = num(load.cpuBusy?.seconds);
    busy.push(`CPU ${Math.round(share * 100)}% busy ${seconds !== null ? `over the last ${seconds} s` : "just now"}`);
  }
  if (Array.isArray(load.loadAvg) && load.loadAvg.length === 3) busy.push(`load ${load.loadAvg.join(" / ")} (1 / 5 / 15 min)`);
  const room: string[] = [];
  const memTotal = num(load.memory?.totalBytes);
  const memFree = num(load.memory?.availableBytes);
  if (memTotal !== null && memFree !== null && memTotal > 0) room.push(`memory ${gib(memFree)} of ${gib(memTotal)} free`);
  const diskTotal = num(load.disk?.totalBytes);
  const diskFree = num(load.disk?.freeBytes);
  if (diskTotal !== null && diskFree !== null && diskTotal > 0) room.push(`disk ${gib(diskFree)} of ${gib(diskTotal)} free`);
  const r = load.running;
  const running =
    r && typeof r === "object"
      ? `running ${[plural(num(r.remoteTasks) ?? 0, "remote task"), plural(num(r.jobs) ?? 0, "job"), plural(num(r.services) ?? 0, "service"), plural(num(r.turns) ?? 0, "agent turn")].join(", ")}`
      : null;
  const ping = num(load.relay?.ping?.ms);
  const relay = ping !== null ? `relay ping ${ping} ms` : null;
  return [machine.join(", "), busy.join(", "), room.join(", "), running, relay].filter((s) => s !== null && s !== "").join("; ");
}

/// `describe`'s answer for station_list {station}: as it came, its load said in a line too (`summary`), or that an
/// older station says none.
export function detailed(described: Json): Json {
  if (described === null || typeof described !== "object") return described;
  if (!("load" in described)) return { ...described, load: OLDER };
  return { ...described, summary: summary(described.load) };
}

// The machine's state (host.rs `info`), read in a reader and kept here: given again within ten seconds, and the CPU
// ticks last seen kept across reads (readers come and go). GET /host, the events' `host` samples and what other stations
// are told of this one's load (station_list, jobs/load.ts) share it.
import type { Lang } from "../ops/i18n.ts";
import type { Seen, Ticks } from "../read/host.ts";
import type { Readers } from "../read/pool.ts";
import { wall } from "../ops/fibers.ts";
import { platform } from "../platform/index.ts";
import { cpuShare } from "../platform/cpu-share.ts";
import { Gpus } from "../jobs/gpu.ts";

/// How often the CPUs' ticks are noted for their recent average, and over how long that is.
export const CPU_EVERY_MS = 15_000;
export const CPU_SPAN_MS = 60_000;

/// The CPUs' ticks noted every CPU_EVERY_MS for the last CPU_SPAN_MS or so: how busy they have been over about a minute
/// (not a moment's sample), on the main thread (the ticks are os.cpus or /proc/stat, read at once).
export class CpuWindow {
  private seen: { at: number; ticks: Ticks }[] = [];

  note(at: number, ticks: Ticks | null): void {
    if (ticks === null) return;
    this.seen.push({ at, ticks });
    // The oldest kept is the last one at least a span old, so a span is always covered once there has been one.
    while (this.seen.length > 1 && at - this.seen[1]!.at >= CPU_SPAN_MS) this.seen.shift();
  }

  /// The ticks noted last, for a read that would otherwise wait a moment to see them move.
  latest(): Seen {
    return this.seen.at(-1) ?? null;
  }

  /// How busy the CPUs have been since the oldest ticks noted (at most a span and a beat ago) until `ticks` now, and
  /// over how many seconds; null before there is anything to compare with (or the ticks have not moved).
  busy(at: number, ticks: Ticks | null): { busy: number; seconds: number } | null {
    const first = this.seen.find((s) => at - s.at <= CPU_SPAN_MS + CPU_EVERY_MS);
    if (ticks === null || first === undefined || at - first.at < 1000) return null;
    const [b0, t0] = first.ticks;
    const [b1, t1] = ticks;
    if (t1 <= t0) return null;
    return { busy: Math.round(Math.min(Math.max((b1 - b0) / (t1 - t0), 0), 1) * 100) / 100, seconds: Math.round((at - first.at) / 1000) };
  }
}

export class Host {
  private readers: Readers;
  readonly gpus: Pick<Gpus, "read">;
  private cached: { at: number; info: any } | null = null;
  private seen: Seen = null;
  private reading: Promise<any> | null = null;
  private cpu = new CpuWindow();

  constructor(readers: Readers, gpus: Pick<Gpus, "read"> = new Gpus()) {
    this.readers = readers;
    this.gpus = gpus;
  }

  /// Notes the CPUs' ticks now and every CPU_EVERY_MS after, until the returned function is called.
  follow(): () => void {
    const note = () => this.cpu.note(wall.now(), platform.host.cpuTicks());
    note();
    return wall.every(CPU_EVERY_MS, note);
  }

  /// How busy the CPUs have been over about the last minute (follow), null until it has looked twice.
  recentBusy(): { busy: number; seconds: number } | null {
    return this.cpu.busy(wall.now(), platform.host.cpuTicks());
  }

  /// The machine sample and its GPUs. GPU failures do not prevent the other measurements from being shown.
  async sample(lang: Lang = "zh"): Promise<any> {
    const [info, gpus] = await Promise.all([this.info(lang), this.gpus.read().catch(() => null)]);
    return { ...info, gpus };
  }

  /// At most ten seconds old; one read at a time however many ask.
  private info(lang: Lang): Promise<any> {
    if (this.cached !== null && wall.now() - this.cached.at < 10_000) return Promise.resolve(this.cached.info);
    // Ticks the last read saw over a minute ago would make it wait a moment for them to move: those followed are newer.
    const last = this.seen !== null && wall.now() - this.seen.at < 60_000 ? this.seen : (this.cpu.latest() ?? this.seen);
    this.reading ??= this.readers
      .read("host", { seen: last }, lang)
      .then(async (text) => {
        const parsed: { info: any; seen: Seen; needsTicks: boolean } = JSON.parse(text);
        const { info, needsTicks } = parsed;
        let { seen } = parsed;
        if (needsTicks && seen !== null) {
          // macOS can leave ticks unchanged for 500 ms or more. Wait outside the reader, then ask for ticks alone;
          // the reader can serve other requests between samples. As before, give up after two seconds.
          const first = seen.ticks;
          const start = wall.now();
          await wall.sleep(500);
          for (;;) {
            const ticks: Ticks | null = JSON.parse(await this.readers.read("hostTicks", {}, lang));
            if (ticks === null) { seen = last; break; }
            const busy = cpuShare(first, ticks);
            if (busy !== null) {
              info.cpuBusy = Math.round(busy * 100) / 100;
              seen = { at: wall.now(), ticks };
              break;
            }
            if (wall.now() - start >= 2_000) { seen = last; break; }
            await wall.sleep(100);
          }
          info.checkedAt = wall.now();
        }
        this.seen = seen;
        this.cached = { at: info.checkedAt, info };
        return info;
      })
      .finally(() => (this.reading = null));
    return this.reading;
  }
}

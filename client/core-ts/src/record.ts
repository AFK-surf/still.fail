// The device's record of what its connections do, written into the app's performance record while it is on (the iOS
// app's 设置 › 关于 › 诊断 › 性能记录: apps/mbui/docs/perf-record.md, "Connections"), so a weak network's day says what
// the core did: each dial and how far it got, what was waited for and what woke it, the cloud's socket, each way's
// packets. Off (or a host that keeps no record), nothing is formatted: each place asks `recording()` first, one call
// to the host, and builds its line only then. Nothing here changes what the core does.

/// Where the lines go: the host's record (hosts/bridge.ts, over the engine's `__native.recording` / `__native.record`).
export interface Recorder {
  on(): boolean;
  line(text: string): void;
}

/// What keeps the record: the core's host (Host.recorder), none where it keeps none.
export type Recording = { readonly recorder?: Recorder | undefined };

/// Whether lines are kept now: ask before building one.
export function recording(host: Recording): boolean {
  return host.recorder !== undefined && host.recorder.on();
}

/// A line kept, as `<what>: <fields>`, where lines are kept now (the fields worked out only then).
export function record(host: Recording, what: string, fields: () => string): void {
  const r = host.recorder;
  if (r === undefined || !r.on()) return;
  r.line(`${what}: ${fields()}`);
}

/// A station's address or id, as the record names it: its id's first 8 (its workspace's first 6 before it, where it has one).
export function stationTag(addressOrId: string): string {
  const slash = addressOrId.lastIndexOf("/");
  const id = slash >= 0 ? addressOrId.slice(slash + 1) : addressOrId;
  return slash >= 0 ? `${addressOrId.slice(0, Math.min(6, slash))}/${id.slice(0, 8)}` : id.slice(0, 8);
}

/// A failure as the record says it: one line, at most 120 characters.
export function said(message: string): string {
  const one = message.replace(/\s+/g, " ").trim();
  return one.length > 120 ? `${one.slice(0, 117)}…` : one;
}

/// A dial's line (mesh.ts open): where through, how long each stage took from the dial's start (-1: not reached), how
/// it ended.
export function dialLine(d: {
  n: number;
  station: string;
  via: string;
  onto: number;
  credential: number;
  dialled: number;
  openBi: number;
  sent: number;
  total: number;
  outcome: string;
}): string {
  const ms = (x: number) => (x < 0 ? "-" : `${Math.round(x)}ms`);
  return `#${d.n} ${stationTag(d.station)} via=${d.via} onto=${ms(d.onto)} credential=${ms(d.credential)} dialled=${ms(d.dialled)} openBi=${ms(d.openBi)} sent=${ms(d.sent)} total=${ms(d.total)} -> ${d.outcome}`;
}

/// Per host: whether the DHT's lines are being kept, and when they were last taken (`recordDht`).
const dhtTakes = new WeakMap<object, { kept: boolean; at: number }>();

/// The DHT lookup's lines since the last take (the shell's `dht.said`: vendor/n0-mainline's ember), as `dht:` lines
/// each saying how long before it was. While the record is on the shell keeps them however long until the next take
/// (an app back after minutes away says what its socket did then); once off it is told, once, to keep none. `every`:
/// not taken again within that many ms (a station's tick, each station's: one take a tick between them); a dial and a
/// wake take at once. A line names its DHT (`dht#N`) and a lookup the station it is of (its id's first 8): which dial
/// a lookup served is not said, only when.
export function recordDht(
  host: Recording & { nowMs(): number },
  from: { dhtSaid?(keep: boolean): { lines: { at: number; text: string }[]; dropped: number } },
  every = 0,
): void {
  if (from.dhtSaid === undefined) return;
  const was = dhtTakes.get(host) ?? { kept: false, at: -Infinity };
  if (!recording(host)) {
    if (was.kept) {
      dhtTakes.set(host, { kept: false, at: was.at });
      from.dhtSaid(false);
    }
    return;
  }
  const now = host.nowMs();
  if (was.kept && now - was.at < every) return;
  dhtTakes.set(host, { kept: true, at: now });
  const { lines, dropped } = from.dhtSaid(true);
  for (const line of lines) record(host, "dht", () => `${line.text} (${Math.max(0, Math.round(now - line.at))}ms before)`);
  if (dropped > 0) record(host, "dht", () => `${dropped} line(s) dropped for want of room`);
}

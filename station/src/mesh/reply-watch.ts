// What the log says of the ways a connection goes by: all it has now (`pathsOf`), and a large reply that was slow to
// be taken in (`slowly`). Of the connection alone: what was asked is said by who answers it.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Connection, Stream } from "./native.ts";

/// A reply this long or longer whose bytes took more than SLOW_REPLY_MS to be taken in whole is said on the log (slowly).
export const SLOW_REPLY_BYTES = 256 * 1024;
const SLOW_REPLY_MS = 5_000;

/// A large reply's bytes, once the device has taken them all in (acknowledged): said on the log when that took over
/// SLOW_REPLY_MS, with how long it was made in (`made`) and the way it went (a relay or an address, its round trip, the
/// packets sent and lost on it, and how much the station may send on it unacknowledged now and how often that was cut
/// for loss), so a part of a video slow to come is seen here, the station's time apart from the way's. (Its stream told
/// nothing as it was acknowledged until 2026-10-28, which this took for the device having stopped it: nothing was ever
/// said, and a desktop app's images coming at 30 KB/s from a station for an hour left no word of how.) `ways` says every
/// way the connection has, `*` the chosen one, with the packets sent on each while the reply went: a connection has a
/// way through every relay (#2580), and with none chosen noq sends on all of them (2026-10-30: attachments at 11–50
/// KB/s on a way of 70 ms, `way=?` on half of them, the chosen way alone not saying where the bytes went). `route`:
/// what was asked, as the line names it (asked only when the line is said).
export function slowly(stream: Stream, conn: Connection, route: () => string, bytes: number, made: number, from: number) {
  const before = sentOn(conn);
  void stream.stopped().then((code) => {
    const ms = wall.now() - from;
    if (typeof code === "number" || ms < SLOW_REPLY_MS) return;
    const paths = conn.paths?.() ?? [];
    const way = paths.find((p) => p.selected);
    const after = sentOn(conn);
    const ways = paths.map((p, i) => {
      const [key, sent] = after[i]!;
      const was = before.find(([k]) => k === key)?.[1] ?? 0;
      return `${p.selected ? "*" : ""}${key} ${p.rttMs == null ? "?" : `${Math.round(p.rttMs)}ms`} +${sent - was}/${p.lostPackets} cwnd=${p.cwnd ?? "?"}`;
    });
    log.info("mesh", "a reply went slowly", {
      route: route(),
      bytes,
      made,
      ms,
      bytesPerSecond: Math.round((bytes / ms) * 1000),
      device: conn.remoteId(),
      way: way ? (way.relay ?? way.ip ?? "?") : "?",
      rtt: way?.rttMs != null ? Math.round(way.rttMs) : null,
      sent: way?.txPackets ?? null,
      lost: way?.lostPackets ?? null,
      cwnd: way?.cwnd ?? null,
      cuts: way?.congestionEvents ?? null,
      ways: ways.join(", "),
    });
  }, () => {});
}

/// Every way a connection has now, as a reply that went slowly says them: `*` the chosen one, its relay or address, round
/// trip, packets sent and lost.
export function pathsOf(conn: Connection): string {
  return (conn.paths?.() ?? []).map((p) => `${p.selected ? "*" : ""}${p.relay ?? p.ip ?? "?"} ${p.rttMs == null ? "?" : `${Math.round(p.rttMs)}ms`} ${p.txPackets}/${p.lostPackets}`).join(", ");
}

/// The packets sent so far on each of a connection's ways, by a key unique among them (its relay or address, `#n` for
/// its n-th way there).
export function sentOn(conn: Connection): [string, number][] {
  const seen = new Map<string, number>();
  return (conn.paths?.() ?? []).map((p) => {
    const at = p.relay ?? p.ip ?? "?";
    const n = seen.get(at) ?? 0;
    seen.set(at, n + 1);
    return [n ? `${at}#${n}` : at, p.txPackets];
  });
}

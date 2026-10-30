// Connections that only trade packets that carry nothing. 2026-10-19 a phone on ccvm's LAN and the station sent each
// other some 48,000 packets a second for ten minutes and more, no request among them: the phone's of the smallest size
// QUIC has (a PING or an ACK request), the station's ACKs. Neither is held back by congestion control or pacing (noq),
// so once going it went at what the LAN takes, four of the station's threads half busy with it, until the phone's
// Wi-Fi went off. Why the phone kept asking is not known yet.
//
// So each connection is looked at every second (`Connection.stats`, a mesh addon from before it has no packet counts:
// not looked at). One receiving STORM_PACKETS a second or more, hardly any of them carrying data, is a storm: said in
// the log once as it begins (with how many of each kind came and went, and its paths), and once it has gone on
// STORM_SECONDS the connection is closed. Its device connects again (as it does after any connection is lost); what
// it was asking on the old one goes with it.
import type { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Connection, Traffic } from "./native.ts";

/// Packets a second coming on one connection from which it is looked at.
export const STORM_PACKETS = 1000;
/// Of them, at most one in this many carries data (stream, datagram, handshake) for it to be a storm.
const DATA_ONE_IN = 50;
/// Seconds a storm goes on before its connection is closed.
export const STORM_SECONDS = 10;
/// The close code of a connection ended as a storm.
export const STORM_CODE = 5;

type Watched = { conn: Connection; last: Traffic; at: number; since: number | null; seconds: number };

const COUNTS = ["rxPackets", "txPackets", "rxPings", "txPings", "rxAckRequests", "txAckRequests", "rxAcks", "txAcks", "rxData", "txData"] as const;

export class Storms {
  readonly #fibers: Fibers;
  readonly #watched = new Set<Watched>();

  constructor(fibers: Fibers) {
    this.#fibers = fibers;
  }

  /// Looks at every connection each second, until the part closes.
  start(): void {
    this.#fibers.every(1000, () => this.look());
  }

  /// `conn` is looked at from now on, while it is open; not when its addon counts no packets.
  watch(conn: Connection): void {
    const now = conn.stats?.();
    if (now?.rxPackets === undefined) return;
    this.#watched.add({ conn, last: now, at: this.#fibers.now(), since: null, seconds: 0 });
  }

  /// One look at each connection: how much came on it since the last.
  look(): void {
    const at = this.#fibers.now();
    for (const w of this.#watched) {
      if (w.conn.isClosed()) {
        this.#watched.delete(w);
        continue;
      }
      const now = w.conn.stats!();
      const seconds = Math.max(1, (at - w.at) / 1000);
      const rate = Object.fromEntries(COUNTS.map((k) => [k, Math.round(((now[k] ?? 0) - (w.last[k] ?? 0)) / seconds)])) as Record<(typeof COUNTS)[number], number>;
      w.last = now;
      w.at = at;
      const storming = rate.rxPackets >= STORM_PACKETS && (rate.rxData + rate.txData) * DATA_ONE_IN <= rate.rxPackets;
      const device = w.conn.remoteId().slice(0, 12);
      if (!storming) {
        if (w.since !== null) log.info("mesh", "a connection's storm is over", { device, seconds: w.seconds });
        w.since = null;
        w.seconds = 0;
        continue;
      }
      w.seconds += seconds;
      if (w.since === null) {
        w.since = at;
        const paths = (w.conn.paths?.() ?? []).map((p) => `${p.selected ? "*" : ""}${p.ip ?? p.relay ?? "?"} ${p.rttMs == null ? "?" : `${Math.round(p.rttMs)}ms`}`).join("; ");
        log.warn("mesh", "a connection is storming: packets that carry nothing, thousands a second", { device, ...rate, paths });
      }
      if (w.seconds >= STORM_SECONDS) {
        log.warn("mesh", "a storming connection is closed", { device, seconds: Math.round(w.seconds) });
        this.#watched.delete(w);
        w.conn.close(STORM_CODE, "storm");
      }
    }
  }
}

// A device's connections that its own process left behind. A client killed with a connection open (Android's force
// stop, a crash) sends nothing as it goes: the station holds the connection, and whatever is open on it (a screen's view
// driving it, still listed among those on the screen), until QUIC's idle timeout, half a minute on. And iroh keeps one
// chosen path for all the connections of an endpoint id: the dead one's stays chosen while it is held, the new one's
// paths backups.
//
// So when a device's endpoint connects again while it has connections here, each of those is asked whether its other
// end is still there (`Connection.answers`: a datagram it acknowledges at once), and closed if nothing is heard back.
// A connection that answers is left alone: one key may be several live clients at once (Chrome on Android has no
// SharedWorker, so each tab runs a core of its own with the device's key), and none of them is put off by another.
import { log } from "../ops/log.ts";
import type { Connection } from "./native.ts";

/// How long a connection has to answer once a newer one of its endpoint came: a relay's round trip from a phone
/// on a poor network is under a second; asked three times within it.
export const ANSWER_MS = 3_000;
/// The close code of a connection found gone.
export const GONE_CODE = 4;

export class Superseded {
  readonly #open = new Map<string, Set<Connection>>();
  readonly #within: number;

  constructor(within = ANSWER_MS) {
    this.#within = within;
  }

  /// A connection came: those of its endpoint here before it are asked whether they are still there. Resolves once
  /// each has answered or been closed.
  arrived(conn: Connection): Promise<void> {
    const id = conn.remoteId();
    const mine = this.#open.get(id) ?? new Set<Connection>();
    this.#open.set(id, mine);
    const before = [...mine].filter((c) => !c.isClosed());
    mine.add(conn);
    const forget = () => {
      mine.delete(conn);
      if (mine.size === 0 && this.#open.get(id) === mine) this.#open.delete(id);
    };
    conn.closed().then(forget, forget);
    return Promise.all(before.map((old) => this.#ask(old))).then(() => {});
  }

  async #ask(old: Connection): Promise<void> {
    if (old.answers === undefined) return;
    const there = await old.answers(this.#within).catch(() => true);
    if (there || old.isClosed()) return;
    log.info("mesh", "a device's older connection is gone: closed", { device: old.remoteId().slice(0, 12) });
    old.close(GONE_CODE, "gone");
  }
}

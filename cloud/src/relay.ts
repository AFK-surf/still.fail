import { DurableObject } from "cloudflare:workers";
import type { RelayEnv as Env } from "./relay-worker";
import { clock, nowSeconds } from "./auth";

// A bounded shared service budget, never a Mesh membership authority.
import { LIMITS } from "./limits";
export { LIMITS };
import { relayCounters, type Counters } from "./relay-metrics";
export type Quota = {
  minute: number;
  connects: number;
  day: number;
  bytes: number;
  at: number;
  /** Unused since traffic is read from the relay process; kept so budgets written before still read. */
  balance?: number;
  frameBalance?: number;
  frames?: number;
  /** The relay process's own counters when last read (relayCounters): traffic since then is what they grew by. */
  seen?: Counters;
};

/** How often traffic is read from the relay process while connections are open; the daily budget may overshoot by what flows in this time. */
const POLL_MS = 60_000;
/** An admitted connection may take this long to reach the relay process (the Worker's dial timeout plus the handshake). */
const DIAL_MS = 20_000;

/**
 * Admits relay connections; it is not in their path. Frames go straight between the Worker and the relay process,
 * so this object sleeps between connects instead of being held (and billed) by every open socket and every frame.
 * Traffic is counted by the relay process and read here when a connection is admitted and every POLL_MS while any
 * are open; over the daily budget, the process is restarted (every connection drops) and connects are refused.
 */
export class RelayBudget extends DurableObject<Env> {
  protected quota: Quota | undefined;
  /** Connections admitted in the last DIAL_MS, with the relay's accept count then: those not yet accepted still count. */
  private pending: { at: number; accepts: number }[] = [];

  private load(): Quota {
    const now = nowSeconds();
    const q = (this.quota ??= this.ctx.storage.kv.get<Quota>("quota") ?? { minute: Math.floor(now / 60), connects: 0, day: Math.floor(now / 86400), bytes: 0, at: now, frames: 0 });
    const minute = Math.floor(now / 60),
      day = Math.floor(now / 86400);
    if (q.minute !== minute) {
      q.minute = minute;
      q.connects = 0;
    }
    if (q.day !== day) {
      q.day = day;
      q.bytes = 0;
      q.frames = 0;
    }
    q.frames ??= 0;
    q.at = now;
    return q;
  }

  private exhausted(q: Quota): boolean {
    return q.bytes >= LIMITS.bytesPerDay || (q.frames ?? 0) >= LIMITS.framesPerDay;
  }

  /** Reads the relay process's counters and adds what grew since the last read to today's traffic; null while it is not running. */
  private async read(): Promise<Counters | null> {
    let counters: Counters | null = null;
    try {
      const text = await this.env.RELAY.getByName("primary").metrics();
      counters = text === null ? null : relayCounters(text);
    } catch {
      /* not running, or starting: nothing to add */
    }
    const q = this.load();
    if (counters) {
      // A restarted process counts from zero again.
      const seen = q.seen && counters.bytes >= q.seen.bytes && counters.frames >= q.seen.frames ? q.seen : { bytes: 0, frames: 0 };
      q.bytes += counters.bytes - seen.bytes;
      q.frames = (q.frames ?? 0) + counters.frames - seen.frames;
    }
    q.seen = counters ?? undefined;
    return counters;
  }

  /** Whether one more relay connection may be opened now. */
  async admit(): Promise<boolean> {
    const counters = await this.read();
    const q = this.load();
    const now = clock.now();
    this.pending = this.pending.filter((p) => now - p.at < DIAL_MS);
    const accepts = counters?.accepts ?? 0;
    const open = counters ? Math.max(0, counters.accepts - counters.disconnects) : 0;
    const dialing = this.pending.length ? Math.min(this.pending.length, Math.max(0, this.pending.length - (accepts - this.pending[0].accepts))) : 0;
    const admitted = open + dialing < LIMITS.connections && q.connects < LIMITS.connectsPerMinute && !this.exhausted(q);
    if (admitted) {
      q.connects++;
      this.pending.push({ at: now, accepts });
    }
    this.ctx.storage.kv.put("quota", q);
    if (admitted && (await this.ctx.storage.getAlarm()) === null) await this.ctx.storage.setAlarm(Date.now() + POLL_MS);
    return admitted;
  }

  override async alarm(): Promise<void> {
    const counters = await this.read();
    const q = this.load();
    this.ctx.storage.kv.put("quota", q);
    if (this.exhausted(q)) {
      // Dropping every connection keeps reconnects from spending past the budget; admit() refuses them until tomorrow.
      await this.env.RELAY.getByName("primary").destroy();
      return;
    }
    if (counters && counters.accepts > counters.disconnects) await this.ctx.storage.setAlarm(Date.now() + POLL_MS);
  }

  /** For operators: where this object runs, and the round trip from here to the relay process. */
  async where(): Promise<{ colo: string | null; containerMs: number[] }> {
    const trace = await (await fetch("https://www.cloudflare.com/cdn-cgi/trace")).text();
    const colo = /^colo=(.+)$/m.exec(trace)?.[1] ?? null;
    const relay = this.env.RELAY.getByName("primary");
    const containerMs: number[] = [];
    for (let i = 0; i < 5; i++) {
      const start = Date.now();
      await (await relay.fetch(new Request("http://relay/ping"))).arrayBuffer();
      containerMs.push(Date.now() - start);
    }
    return { colo, containerMs };
  }
}

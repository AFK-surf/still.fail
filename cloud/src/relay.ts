import { DurableObject } from "cloudflare:workers";
import type { RelayEnv as Env } from "./relay-worker";
import { clock, nowSeconds } from "./auth";

// A bounded shared service budget, never a Mesh membership authority.
import { LIMITS } from "./limits";
export { LIMITS };
import { relayCounters, type Counters } from "./relay-metrics";
/** What a refused connect was held to (admit). */
export type Refusal = { open: number; dialing: number; connects: number; bytes: number; frames: number; running: boolean };

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
  /** How the day's traffic was counted (COUNTING); a count from before it is not believed. */
  counting?: number;
};

/** Before this (2026-10-25) a failed read forgot `seen`, and the next read added all the process had counted since it
 * started once more: the day's budget ran out hours early. A day counted that way may hold traffic twice and starts over. */
const COUNTING = 2;

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
  /** Connections open at once at most (LIMITS.connections; the tests' fewer, not to open thousands). */
  protected connections = LIMITS.connections;
  /** Connections admitted in the last DIAL_MS, with the relay's accept count then: those not yet accepted still count. */
  private pending: { at: number; accepts: number }[] = [];

  protected load(): Quota {
    const now = nowSeconds();
    const minute = Math.floor(now / 60),
      day = Math.floor(now / 86400);
    const kept = (this.quota ??= this.ctx.storage.kv.get<Quota>("quota"));
    const q = (this.quota = kept?.counting === COUNTING ? kept : { minute, connects: 0, day, bytes: 0, at: now, frames: 0, counting: COUNTING });
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
    // A read that fails keeps `seen`: the process may well go on (busy, not answering in time), and what it counted
    // until then is in today's traffic already.
    if (counters) {
      // A restarted process counts from zero again.
      const seen = q.seen && counters.bytes >= q.seen.bytes && counters.frames >= q.seen.frames ? q.seen : { bytes: 0, frames: 0 };
      q.bytes += counters.bytes - seen.bytes;
      q.frames = (q.frames ?? 0) + counters.frames - seen.frames;
      q.seen = counters;
    }
    return counters;
  }

  /** Whether one more relay connection may be opened now: null if so, else what it was held to (the Worker logs it: a
   * Durable Object's own log is not in `wrangler tail`, and 2026-10-30 it refused every connect from 12:20 in Beijing,
   * the relay's own counters far from every limit, with nothing saying which it was held to). */
  async admit(): Promise<Refusal | null> {
    const counters = await this.read();
    const q = this.load();
    const now = clock.now();
    this.pending = this.pending.filter((p) => now - p.at < DIAL_MS);
    const accepts = counters?.accepts ?? 0;
    const open = counters ? Math.max(0, counters.accepts - counters.disconnects) : 0;
    const dialing = this.pending.length ? Math.min(this.pending.length, Math.max(0, this.pending.length - (accepts - this.pending[0].accepts))) : 0;
    const admitted = open + dialing < this.connections && q.connects < LIMITS.connectsPerMinute && !this.exhausted(q);
    if (admitted) {
      q.connects++;
      this.pending.push({ at: now, accepts });
    }
    this.ctx.storage.kv.put("quota", q);
    if (admitted && (await this.ctx.storage.getAlarm()) === null) await this.ctx.storage.setAlarm(Date.now() + POLL_MS);
    return admitted ? null : { open, dialing, connects: q.connects, bytes: q.bytes, frames: q.frames ?? 0, running: counters !== null };
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

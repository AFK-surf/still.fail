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

/** 4: a count begun anew added all a relay up for days had counted (2026-10-30, `readOnce`); 3 was that, begun anew.
 * 3: reads answered out of order counted traffic again (2026-10-30, `read`): that day's count starts over too.
 * Before 2 (2026-10-25) a failed read forgot `seen`, and the next read added all the process had counted since it
 * started once more: the day's budget ran out hours early. A day counted that way may hold traffic twice and starts over. */
const COUNTING = 4;

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

  /** The read of the relay's counters under way, which those asked meanwhile take the answer of. */
  private reading: Promise<Counters | null> | null = null;

  /** Reads the relay process's counters and adds what grew since the last read to today's traffic; null while it is not
   * running. One at a time: answered in any order, a read older than one counted looked like a process started again
   * (its counters below those last seen), and all it had counted was added once more (2026-10-30: 14.8 GB and 78.5M
   * frames counted by 12:20 in Beijing, some 650 MB carried; every connect refused after). */
  private read(): Promise<Counters | null> {
    this.reading ??= this.readOnce().finally(() => {
      this.reading = null;
    });
    return this.reading;
  }

  private async readOnce(): Promise<Counters | null> {
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
      // A restarted process counts from zero again. Nothing seen yet (the first read, a day counted anew): what the
      // process counted until now is not known to be today's, and is not counted. 2026-10-30, up for days, it had
      // counted 14.8 GB and 78.5M frames in all, every connect refused for the day once a count begun anew added them.
      const seen = !q.seen ? counters : counters.bytes >= q.seen.bytes && counters.frames >= q.seen.frames ? q.seen : { bytes: 0, frames: 0 };
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

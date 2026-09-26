import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { limited, nowSeconds, reply } from "./auth";

// A bounded shared service budget, never a Mesh membership authority.
import { LIMITS } from "./limits";
export { LIMITS };
export type Quota = {
  minute: number;
  connects: number;
  day: number;
  bytes: number;
  at: number;
  balance: number;
  frameBalance?: number;
  frames?: number;
};
type Connection = { close: (code: number, reason: string) => void };

/** How long counted traffic may stay in memory only; a restart forgets at most this much of it. */
const FLUSH_MS = 30_000;

export class RelayBudget extends DurableObject<Env> {
  private connections = new Set<Connection>();
  /** The budget as counted; read once, written when a connection is admitted and within FLUSH_MS of traffic, never per frame. */
  protected quota: Quota | undefined;
  private flushing = false;

  /**
   * Frames are counted in memory: a storage write per frame would hold each
   * frame back until the write is confirmed (the output gate), on every hop.
   */
  private charge(kind: "connect" | "bytes", amount = 0): boolean {
    const now = nowSeconds();
    const minute = Math.floor(now / 60),
      day = Math.floor(now / 86400);
    const q = (this.quota ??= this.ctx.storage.kv.get<Quota>("quota") ?? {
      minute,
      connects: 0,
      day,
      bytes: 0,
      at: now,
      balance: LIMITS.burstBytes,
      frameBalance: LIMITS.burstFrames,
      frames: 0,
    });
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
    q.frameBalance = Math.min(LIMITS.burstFrames, (q.frameBalance ?? LIMITS.burstFrames) + Math.max(0, now - q.at) * LIMITS.framesPerSecond);
    q.balance = Math.min(LIMITS.burstBytes, q.balance + Math.max(0, now - q.at) * LIMITS.bytesPerSecond);
    q.at = now;
    if (kind === "connect") {
      if (q.connects >= LIMITS.connectsPerMinute || q.bytes >= LIMITS.bytesPerDay || q.frames >= LIMITS.framesPerDay) return false;
      q.connects++;
    } else {
      // Tiny/empty frames consume CPU and billable events too.
      if (amount > q.balance || q.bytes + amount > LIMITS.bytesPerDay || q.frameBalance < 1 || q.frames >= LIMITS.framesPerDay) return false;
      q.frameBalance--;
      q.frames++;
      q.bytes += amount;
      q.balance -= amount;
    }
    if (kind === "connect") this.ctx.storage.kv.put("quota", q);
    else if (!this.flushing) {
      this.flushing = true;
      void this.ctx.storage.setAlarm(Date.now() + FLUSH_MS);
    }
    return true;
  }

  override async alarm(): Promise<void> {
    this.flushing = false;
    if (this.quota) this.ctx.storage.kv.put("quota", this.quota);
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

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") return reply({ error: "websocket_required" }, 426);
    if (this.connections.size >= LIMITS.connections || !this.charge("connect")) return limited();
    let server: WebSocket | undefined, upstream: WebSocket | undefined;
    let dialTimer: ReturnType<typeof setTimeout> | undefined;
    let dialAbort: AbortController | undefined;
    let closed = false;
    const connection: Connection = {
      close: (code, reason) => {
        if (closed) return;
        closed = true;
        if (dialTimer !== undefined) clearTimeout(dialTimer);
        dialAbort?.abort();
        for (const socket of [server, upstream]) {
          try {
            socket?.close(code, reason);
          } catch {
            /* already closed */
          }
        }
        this.connections.delete(connection);
      },
    };
    // Reserve before awaiting the container, including in-flight upgrades in
    // the service budget. Cloud account state does not govern transport.
    this.connections.add(connection);
    try {
      const headers = new Headers({ upgrade: "websocket" });
      const protocol = request.headers.get("sec-websocket-protocol");
      if (protocol) headers.set("sec-websocket-protocol", protocol);
      // Fixed routing and a fresh URL prevent credentials/cookies/query values
      // reaching the relay process, its logs, or an arbitrary backend.
      const dial = new AbortController();
      dialAbort = dial;
      dialTimer = setTimeout(() => dial.abort(), 15_000);
      const response = await this.env.RELAY.getByName("primary").fetch(new Request("http://relay/relay", { headers, signal: dial.signal }));
      clearTimeout(dialTimer);
      dialTimer = undefined;
      dialAbort = undefined;
      upstream = response.webSocket ?? undefined;
      if (!upstream || response.status !== 101) {
        connection.close(1011, "relay_unavailable");
        return reply({ error: "relay_unavailable" }, 502);
      }
      upstream.binaryType = "arraybuffer";
      upstream.accept();
      if (closed) {
        upstream.close(1011, "relay_unavailable");
        connection.close(1011, "relay_unavailable");
        return reply({ error: "relay_unavailable" }, 502);
      }
      const pair = new WebSocketPair();
      server = pair[1];
      server.binaryType = "arraybuffer";
      server.accept();
      const forward = (from: WebSocket, to: WebSocket) => {
        from.addEventListener("message", (event) => {
          if (closed) return;
          if (!(event.data instanceof ArrayBuffer) || event.data.byteLength > LIMITS.frameBytes) {
            connection.close(1009, "invalid_frame");
            return;
          }
          if (!this.charge("bytes", event.data.byteLength)) {
            // Closing all sockets prevents reconnecting to bypass
            // a shared byte budget. The persistent budget also gates reconnects.
            for (const c of [...this.connections]) c.close(4008, "relay_quota");
            return;
          }
          try {
            to.send(event.data);
          } catch {
            connection.close(1011, "relay_send_failed");
          }
        });
        from.addEventListener("close", () => connection.close(1000, "relay_closed"));
        from.addEventListener("error", () => connection.close(1011, "relay_error"));
      };
      forward(server, upstream);
      forward(upstream, server);
      const selected = response.headers.get("sec-websocket-protocol");
      return new Response(null, {
        status: 101,
        webSocket: pair[0],
        headers: selected ? { "sec-websocket-protocol": selected } : undefined,
      });
    } catch {
      connection.close(1011, "relay_unavailable");
      return reply({ error: "relay_unavailable" }, 502);
    }
  }
}

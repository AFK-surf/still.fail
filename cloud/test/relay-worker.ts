// Only the test bundler imports this entry: the relay Worker (src/relay-worker.ts) with a stand-in for the relay
// process (an echo, or TEST_RELAY, counting like iroh-relay's metrics) and ways to look into its budget.
import { DurableObject } from "cloudflare:workers";
import worker, { RelayBudget as ProductionRelayBudget } from "../src/relay-worker";
import { clock, nowSeconds } from "../src/auth";
import { LIMITS } from "../src/limits";
import { TEST_CONNECTIONS } from "./relay-limit";
export default worker;

declare const TEST_NOW_MS: number | null;
if (TEST_NOW_MS !== null) clock.now = () => TEST_NOW_MS;

export class RelayBudget extends ProductionRelayBudget {
  protected override connections = TEST_CONNECTIONS;
  exhaustBudget(kind: "bytes" | "frames" = "bytes") {
    // The budget is counted in memory and written now and then: exhausting it means both.
    const q = this.load();
    if (kind === "bytes") q.bytes = LIMITS.bytesPerDay;
    else q.frames = LIMITS.framesPerDay;
    this.ctx.storage.kv.put("quota", q);
  }
  /** A day's budget used up as counted before COUNTING (relay.ts), kept the way it was then. */
  exhaustedBefore() {
    const now = nowSeconds();
    this.quota = undefined;
    this.ctx.storage.kv.put("quota", { minute: Math.floor(now / 60), day: Math.floor(now / 86400), at: now, connects: 0, bytes: LIMITS.bytesPerDay, frames: 0 });
  }
  /** What the alarm does every minute while connections are open. */
  poll() {
    return this.alarm();
  }
  statistics() {
    return this.quota ?? this.ctx.storage.kv.get("quota");
  }
}

export class Relay extends DurableObject<{ TEST_RELAY?: Fetcher }> {
  /** Upgrades held until release(), while a test holds them (hold()); null: none held. */
  private held: (() => void)[] | null = null;
  private arrivals: { n: number; resolve: () => void }[] = [];
  private closings: { n: number; resolve: () => void }[] = [];
  private destroyed = 0;
  private bytes = 0;
  private failing = 0;
  private accepts = 0;
  private disconnects = 0;
  private sockets = new Set<WebSocket>();
  destroy() {
    this.destroyed++;
    // Like the process going away: every connection drops.
    for (const socket of this.sockets) socket.close(1012, "restarted");
    this.disconnects += this.sockets.size;
    this.sockets.clear();
  }
  metrics() {
    if (this.failing > 0) {
      this.failing--;
      throw new Error("the relay process did not answer");
    }
    return `relayserver_bytes_sent_total ${this.bytes}\nrelayserver_accepts_total ${this.accepts}\nrelayserver_disconnects_total ${this.disconnects}\n`;
  }
  /** Traffic through it, as the process counts it. */
  carried(bytes: number) {
    this.bytes += bytes;
  }
  /** The next `n` reads of its counters fail, as while the process is too busy to answer. */
  failReads(n = 1) {
    this.failing = n;
  }
  destroyCount() {
    return this.destroyed;
  }
  /** From now on each upgrade waits here until release(): a test keeps some pending while it does something else. */
  hold() {
    this.held = [];
  }
  /** Resolves once `n` upgrades are waiting here (not on a guess of how long they take to arrive). */
  arrived(n: number) {
    return new Promise<void>((resolve) => {
      this.arrivals.push({ n, resolve });
      this.wake();
    });
  }
  /** Lets every held upgrade go on, and holds no more. */
  release() {
    const held = this.held ?? [];
    this.held = null;
    for (const go of held) go();
  }
  /** Resolves once `n` connections in all have closed here. */
  disconnected(n: number) {
    return new Promise<void>((resolve) => {
      this.closings.push({ n, resolve });
      this.wake();
    });
  }
  private wake() {
    this.closings = this.closings.filter((c) => (c.n <= this.disconnects ? (c.resolve(), false) : true));
    const waiting = this.held?.length ?? 0;
    this.arrivals = this.arrivals.filter((a) => (a.n <= waiting ? (a.resolve(), false) : true));
  }
  async fetch(request: Request): Promise<Response> {
    if (this.held) {
      const held = this.held;
      await new Promise<void>((go) => {
        held.push(go);
        this.wake();
      });
    }
    if (request.headers.has("authorization") || request.headers.has("cookie") || new URL(request.url).search) {
      return new Response("credential leak", { status: 500 });
    }
    if (this.env.TEST_RELAY) {
      return this.env.TEST_RELAY.fetch(request);
    }
    const pair = new WebSocketPair();
    const server = pair[1];
    server.binaryType = "arraybuffer";
    server.accept();
    this.accepts++;
    this.sockets.add(server);
    server.addEventListener("message", (event) => server.send(event.data));
    server.addEventListener("close", () => {
      if (this.sockets.delete(server)) this.disconnects++;
      this.wake();
      server.close(1000, "closed");
    });
    return new Response(null, {
      status: 101,
      webSocket: pair[0],
      headers: {
        "sec-websocket-protocol": request.headers.get("sec-websocket-protocol") ?? "iroh-relay",
      },
    });
  }
}


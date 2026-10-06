// A station for the mesh tests (mesh.test.ts, bridge.test.ts): accepts credentials starting with "ok", echoes requests.
// On localhost over the native addon (station/native/mesh), or on a simulated network (sim-iroh.ts: its `world`).
import { loadAddon } from "../src/hosts/node-iroh.ts";
import { ALPN, FORMER_ALPN } from "../src/mesh.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const addon = loadAddon() as J;

/// Where a station runs: what binds its endpoint, and its time.
export type World = { bind(options: J): Promise<J>; sleep(ms: number): Promise<void> };
/// The machine's own: the addon, real time.
export const REAL: World = { bind: (o) => addon.bind(o), sleep: (ms) => new Promise((r) => setTimeout(r, ms)) };

export class Station {
  endpoint: J;
  grants: string[] = [];
  conns: J[] = [];
  /// Connections before this one answer nothing more.
  deadBelow = 0;
  idempotent = false;
  /// Each request it carried out (read whole, on a way not dead): its head.
  served: J[] = [];
  world: World = REAL;

  static async start(alpns: Uint8Array[] = [ALPN, FORMER_ALPN], world: World = REAL): Promise<Station> {
    return Station.bound({ alpns: alpns.map((a) => Buffer.from(a)), relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" }, world);
  }

  /// One at home on the relay `home`, held on `other` too by a keeper there (station/native/mesh keep.rs).
  static async on(home: string, other: string, world: World = REAL): Promise<Station> {
    const s = await Station.bound({ alpns: [Buffer.from(ALPN), Buffer.from(FORMER_ALPN)], relayUrls: [home], discovery: false, relayOnly: true }, world);
    await s.endpoint.online();
    s.endpoint.keep([other]);
    return s;
  }

  /// `key`: its secret (a random one by default; a simulated network's runs draw theirs from its seed).
  static async bound(options: J, world: World = REAL, key?: Uint8Array): Promise<Station> {
    const s = new Station();
    s.world = world;
    if (!key) {
      const fresh = new Uint8Array(32);
      crypto.getRandomValues(fresh);
      key = fresh;
    }
    s.endpoint = await world.bind({ secretKey: Buffer.from(key), ...options });
    void (async () => {
      for (;;) {
        const conn = await s.endpoint.accept();
        if (conn === null) return;
        const index = s.conns.length;
        s.conns.push(conn);
        void s.#serve(conn, () => index < s.deadBelow).catch(() => {});
      }
    })().catch(() => {});
    return s;
  }

  /// The next `n` connections coming are never answered, not even their handshake (a device whose way here is gone).
  unanswered(n: number): void {
    this.endpoint.holdIncoming(n);
  }

  id(): string {
    return this.endpoint.id();
  }

  addr() {
    const ip = this.endpoint.sockets().find((a: string) => a.startsWith("127.0.0.1"));
    return { id: this.id(), ips: [ip] };
  }

  static async readLine(stream: J, carry: { bytes: Buffer }): Promise<string | null> {
    for (;;) {
      const at = carry.bytes.indexOf(10);
      if (at >= 0) {
        const line = carry.bytes.subarray(0, at).toString();
        carry.bytes = carry.bytes.subarray(at + 1);
        return line;
      }
      const chunk = await stream.read();
      if (chunk === null) return null;
      carry.bytes = Buffer.concat([carry.bytes, chunk]);
    }
  }

  #answer(line: string): J {
    const grant = JSON.parse(line).credential as string;
    this.grants.push(grant);
    return grant.startsWith("ok") ? { ok: true, station: "测试" } : { error: "grant signature invalid" };
  }

  async #serve(conn: J, dead: () => boolean): Promise<void> {
    const control = await conn.acceptBi();
    if (control === null) return;
    const carry = { bytes: Buffer.alloc(0) };
    const first = await Station.readLine(control, carry);
    if (first === null) return;
    const reply = this.#answer(first);
    await control.write(Buffer.from(`${JSON.stringify(reply)}\n`));
    if (reply.error) {
      await control.finish().catch(() => {});
      await this.world.sleep(200);
      conn.close(1, "credential_refused");
      return;
    }
    void (async () => {
      for (;;) {
        const line = await Station.readLine(control, carry).catch(() => null);
        if (line === null) return;
        if (dead()) continue;
        await control.write(Buffer.from(`${JSON.stringify(this.#answer(line))}\n`)).catch(() => {});
      }
    })().catch(() => {});
    for (;;) {
      const stream = await conn.acceptBi();
      if (stream === null) return;
      const once = this.idempotent;
      void (async () => {
        const c = { bytes: Buffer.alloc(0) };
        const head = await Station.readLine(stream, c);
        let body = c.bytes;
        for (;;) {
          const chunk = await stream.read();
          if (chunk === null) break;
          body = Buffer.concat([body, chunk]);
        }
        if (dead()) return;
        const parsed = JSON.parse(head!);
        this.served.push(parsed);
        const headers: J = { "content-type": "text/event-stream", "x-method": parsed.method };
        if (once) headers["stillfail-idempotent"] = "1";
        await stream.write(Buffer.from(`${JSON.stringify({ status: 200, headers })}\n`));
        // A large reply: how fast a way brings one.
        if (parsed.path === "/admin/api/big") {
          await stream.write(Buffer.alloc(1024 * 1024, 7)).catch(() => {});
          await stream.finish().catch(() => {});
          return;
        }
        await stream.write(Buffer.from(`${head}|${body.toString()}`));
        for (const part of ["|one", "|two", "|three"]) {
          await this.world.sleep(100);
          try {
            await stream.write(Buffer.from(part));
          } catch {
            return;
          }
        }
        await stream.finish().catch(() => {});
      })().catch(() => {});
    }
  }

  async close() {
    await this.endpoint.close();
  }
}


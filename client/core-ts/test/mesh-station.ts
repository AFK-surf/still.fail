// A station for the mesh tests (mesh.test.ts, bridge.test.ts): accepts credentials starting with "ok", echoes requests.
// On localhost over the native addon (station/native/mesh), or on a simulated network (sim-iroh.ts: its `world`).
import { loadAddon } from "../src/hosts/node-iroh.ts";
import { ALPN, FORMER_ALPN } from "../src/mesh.ts";
import { configFrame, readClientFrames, stateFrame, videoFrame } from "../src/screen-frames.ts";

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
  /// Each connection's first credential, in the order they came.
  firsts: string[] = [];
  /// Each connection's first line, whole (its credential, protocol, lock, the dial's traceparent).
  hellos: J[] = [];
  conns: J[] = [];
  /// Connections before this one answer nothing more.
  deadBelow = 0;
  idempotent = false;
  /// Each request it carried out (read whole, on a way not dead): its head.
  served: J[] = [];
  /// How long each answer's head waits once its request is read (a station slow to answer: its main thread held).
  lateMs = 0;
  /// The paths of the requests the device let go of before their answers ended (their streams stopped by it).
  letGo: string[] = [];
  /// Screen views (docs/remote-screens.md) as it served them: the head, what the client sent, the most frames it ever
  /// had sent and not acknowledged. A view sends `screenFrames` (a config first), each once fewer than 2 are
  /// unacknowledged, then ends.
  views: { head: J; got: J[]; mostUnacked: number }[] = [];
  screenFrames: { key: boolean; ts: number; data: Uint8Array }[] = [];
  world: World = REAL;
  /// Its LAN addresses, its Tailscale ones, said with the answer to a credential (station/src/mesh/lan.ts).
  lan: string[] = [];
  tailnet: string[] = [];
  /// The phone's adb offers (station/src/mesh/adb.ts), each on the connection it came on, answered 200 and held open:
  /// the latest one's connection is where the station opens its tunnels.
  offers: { conn: J; head: J }[] = [];

  static async start(alpns: Uint8Array[] = [ALPN, FORMER_ALPN], world: World = REAL): Promise<Station> {
    return Station.bound({ alpns: alpns.map((a) => Buffer.from(a)), relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" }, world);
  }

  /// One at home on the relay `home`, held on `other` (one relay or several) too by a keeper there (station/native/mesh
  /// keep.rs).
  static async on(home: string, other: string | string[], world: World = REAL): Promise<Station> {
    const s = await Station.bound({ alpns: [Buffer.from(ALPN), Buffer.from(FORMER_ALPN)], relayUrls: [home], discovery: false, relayOnly: true }, world);
    await s.endpoint.online();
    s.endpoint.keep(Array.isArray(other) ? other : [other]);
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

  /// The next `n` connections coming are refused (an endpoint not taking new connections).
  refused(n: number): void {
    this.endpoint.refuseIncoming(n);
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
    return grant.startsWith("ok") ? { ok: true, station: "测试", ...(this.lan.length > 0 ? { lan: this.lan } : {}), ...(this.tailnet.length > 0 ? { tailnet: this.tailnet } : {}) } : { error: "grant signature invalid" };
  }

  async #serve(conn: J, dead: () => boolean): Promise<void> {
    const control = await conn.acceptBi();
    if (control === null) return;
    const carry = { bytes: Buffer.alloc(0) };
    const first = await Station.readLine(control, carry);
    if (first === null) return;
    this.firsts.push(JSON.parse(first).credential);
    this.hellos.push(JSON.parse(first));
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
        // (stopped by the device before its answer's end: let go of)
        let ended = false;
        if (head !== null) void stream.stopped().then((code: number | null) => code !== null && !ended && this.letGo.push(JSON.parse(head).path), () => {});
        if (head !== null && JSON.parse(head).screen !== undefined) return this.#view(stream, JSON.parse(head), c.bytes);
        if (head !== null && JSON.parse(head).adb?.op === "share") {
          this.offers.push({ conn, head: JSON.parse(head) });
          await stream.write(Buffer.from(`${JSON.stringify({ status: 200, headers: { "content-type": "application/x-ndjson" } })}\n`));
          await stream.write(Buffer.from(`${JSON.stringify({ serial: "127.0.0.1:37001", adb: "connected", message: "" })}\n`));
          return;
        }
        let body = c.bytes;
        for (;;) {
          const chunk = await stream.read();
          if (chunk === null) break;
          body = Buffer.concat([body, chunk]);
        }
        if (dead()) return;
        const parsed = JSON.parse(head!);
        this.served.push(parsed);
        if (this.lateMs > 0) await this.world.sleep(this.lateMs);
        const headers: J = { "content-type": "text/event-stream", "x-method": parsed.method };
        if (once) headers["stillfail-idempotent"] = "1";
        await stream.write(Buffer.from(`${JSON.stringify({ status: 200, headers })}\n`));
        // A large reply: how fast a way brings one, written a piece at a time (as the station's file reads are), so two at
        // once share their way's line.
        if (parsed.path === "/admin/api/big") {
          for (let i = 0; i < 16; i++) await stream.write(Buffer.alloc(64 * 1024, 7)).catch(() => {});
          ended = true;
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
        ended = true;
        await stream.finish().catch(() => {});
      })().catch(() => {});
    }
  }

  /// A screen view: answered 200, then frames as the client acknowledges them (pull-driven, as the station's views are).
  async #view(stream: J, head: J, carry: Buffer): Promise<void> {
    const view = { head, got: [] as J[], mostUnacked: 0 };
    this.views.push(view);
    const frames = [...this.screenFrames];
    const unacked = new Set<number>();
    const waiting: { wake: (() => void) | null } = { wake: null };
    void (async () => {
      let buf: Uint8Array = new Uint8Array(carry);
      for (;;) {
        const chunk = await stream.read().catch(() => null);
        if (chunk === null) return;
        const [got, rest] = readClientFrames(new Uint8Array(Buffer.concat([buf, chunk])));
        buf = rest;
        for (const f of got) {
          view.got.push(f);
          if ("ack" in f) for (const ts of [...unacked]) if (ts <= f.ack) unacked.delete(ts);
        }
        waiting.wake?.();
      }
    })().catch(() => {});
    await stream.write(Buffer.from(`${JSON.stringify({ status: 200, headers: { "content-type": "application/x-stillfail-screen" } })}\n`));
    await stream.write(Buffer.from(configFrame({ codec: "jpeg", width: 640, height: 480 })));
    for (const frame of frames) {
      while (unacked.size >= 2) await new Promise<void>((r) => (waiting.wake = r));
      unacked.add(frame.ts);
      view.mostUnacked = Math.max(view.mostUnacked, unacked.size);
      await stream.write(Buffer.from(videoFrame(frame.key, frame.ts, frame.data)));
    }
    while (unacked.size > 0) await new Promise<void>((r) => (waiting.wake = r));
    await stream.write(Buffer.from(stateFrame({ ended: "done" })));
    await stream.finish().catch(() => {});
  }

  async close() {
    await this.endpoint.close();
  }
}


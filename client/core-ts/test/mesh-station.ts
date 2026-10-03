// A station on localhost over the native addon (station/native/mesh), for the mesh tests (mesh.test.ts,
// bridge.test.ts): accepts credentials starting with "ok", echoes requests.
import { loadAddon } from "../src/hosts/node-iroh.ts";
import { ALPN, FORMER_ALPN } from "../src/mesh.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const addon = loadAddon() as J;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export class Station {
  endpoint: J;
  grants: string[] = [];
  conns: J[] = [];
  /// Connections before this one answer nothing more.
  deadBelow = 0;
  idempotent = false;

  static async start(alpns: Uint8Array[] = [ALPN, FORMER_ALPN]): Promise<Station> {
    const s = new Station();
    const key = new Uint8Array(32);
    crypto.getRandomValues(key);
    s.endpoint = await addon.bind({ secretKey: Buffer.from(key), alpns: alpns.map((a) => Buffer.from(a)), relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
    void (async () => {
      for (;;) {
        const conn = await s.endpoint.accept();
        if (conn === null) return;
        const index = s.conns.length;
        s.conns.push(conn);
        void s.#serve(conn, () => index < s.deadBelow).catch(() => {});
      }
    })();
    return s;
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
      await sleep(200);
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
    })();
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
        const headers: J = { "content-type": "text/event-stream", "x-method": parsed.method };
        if (once) headers["stillfail-idempotent"] = "1";
        await stream.write(Buffer.from(`${JSON.stringify({ status: 200, headers })}\n`));
        await stream.write(Buffer.from(`${head}|${body.toString()}`));
        for (const part of ["|one", "|two", "|three"]) {
          await sleep(100);
          try {
            await stream.write(Buffer.from(part));
          } catch {
            return;
          }
        }
        await stream.finish().catch(() => {});
      })();
    }
  }

  async close() {
    await this.endpoint.close();
  }
}


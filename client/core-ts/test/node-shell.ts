// The bridge's shell in JavaScript (hosts/bridge.ts), over Node and the station's addon: what the Android app's shell
// (apps/android/core: Hermes in C++, its IO in Rust) does, here to test the JS end of the bridge in Node.
import { Effect, Exit, Scope } from "effect";
import { loadAddon } from "../src/hosts/node-iroh.ts";
import { NodeHost } from "../src/hosts/node.ts";
import type { Pull, Sql, TcpConnection } from "../src/host.ts";
import type { Bridge, Native } from "../src/hosts/bridge.ts";

// deno-lint-ignore no-explicit-any
type J = any;
type Done = (json: unknown, bytes?: Uint8Array | null) => void;

export class NodeShell implements Native {
  readonly host: NodeHost;
  bridge!: Bridge;
  readonly #handles = new Map<number, J>();
  #next = 1;
  readonly calls: string[] = [];

  constructor(dataDir: string) {
    this.host = new NodeHost(dataDir, "http://unused", false, () => {});
  }

  #keep(v: J): number {
    const id = this.#next++;
    this.#handles.set(id, v);
    return id;
  }

  /// An Effect that needs a scope: run in one of its own, closed by `close`.
  async #scoped<A>(effect: Effect.Effect<A, unknown, Scope.Scope>): Promise<{ value: A; scope: Scope.Closeable }> {
    const scope = Effect.runSync(Scope.make());
    const value = await Effect.runPromise(Scope.provide(effect, scope));
    return { value, scope };
  }

  call(id: number, op: string, json: string, bytes: Uint8Array | null): void {
    this.calls.push(op);
    const a = JSON.parse(json) as J;
    const done: Done = (out, b = null) => queueMicrotask(() => this.bridge.complete(id, JSON.stringify(out ?? {}), null, b));
    void this.#run(op, a, bytes, done).catch((e) => queueMicrotask(() => this.bridge.complete(id, null, e instanceof Error ? e.message : String(e), null)));
  }

  async #run(op: string, a: J, bytes: Uint8Array | null, done: Done): Promise<void> {
    const h = this.host;
    const run = <A>(e: Effect.Effect<A, unknown>) => Effect.runPromise(e);
    const take = async (pull: Pull<Uint8Array>) => {
      const chunk = await run(pull.take);
      done(chunk === null ? { end: true } : {}, chunk);
    };
    switch (op) {
      case "fetch": {
        const r = await run(h.fetch({ url: a.url, method: a.method, headers: a.headers, body: bytes }));
        return done({ status: r.status, headers: r.headers }, r.body);
      }
      case "stream.open": {
        const { value, scope } = await this.#scoped(h.fetchStream({ url: a.url, method: a.method, headers: a.headers, body: bytes }));
        return done({ status: value.status, headers: value.headers, id: this.#keep({ pull: value.body, scope }) });
      }
      case "stream.read":
      case "tcp.read":
        return take(this.#handles.get(a.id).pull);
      case "stream.close":
      case "ws.close":
      case "tcp.close": {
        const it = this.#handles.get(a.id);
        this.#handles.delete(a.id);
        if (it) await Effect.runPromise(Scope.close(it.scope, Exit.void));
        return done({});
      }
      case "ws.open": {
        const { value, scope } = await this.#scoped(h.websocket(a.url, a.protocols));
        return done({ id: this.#keep({ pull: value, scope }) });
      }
      case "ws.next": {
        const text = await run((this.#handles.get(a.id).pull as Pull<string>).take);
        return done(text === null ? { end: true } : { text });
      }
      case "ws.send":
        return done({});
      case "storage.get": {
        const v = await run(h.storageGet(a.key));
        return done(v === null ? { none: true } : {}, v);
      }
      case "storage.set":
        await run(h.storageSet(a.key, bytes ?? new Uint8Array(0)));
        return done({});
      case "storage.delete":
        await run(h.storageDelete(a.key));
        return done({});
      case "db.read": {
        const rows = await run(h.legacyRead(a));
        const out = new Uint8Array(rows.reduce((n, [, v]) => n + v.length, 0));
        let at = 0;
        for (const [, v] of rows) {
          out.set(v, at);
          at += v.length;
        }
        return done({ keys: rows.map(([k]) => k), sizes: rows.map(([, v]) => v.length) }, out);
      }
      case "tcp.open": {
        const { value, scope } = await this.#scoped(h.tcp(a.port));
        return done({ id: this.#keep({ pull: (value as TcpConnection).read, conn: value, scope }) });
      }
      case "tcp.write":
        await run((this.#handles.get(a.id).conn as TcpConnection).write(bytes ?? new Uint8Array(0)));
        return done({});
      case "tcp.end":
        (this.#handles.get(a.id).conn as TcpConnection).end();
        return done({});
      case "reset":
        return done({});
      case "iroh.bind": {
        const addon = loadAddon() as J;
        const e = await addon.bind({ secretKey: Buffer.from(bytes!), alpns: [], relayUrls: a.relayUrls, discovery: false, lookup: a.lookup, relayOnly: a.relayOnly });
        return done({ id: this.#keep(e) });
      }
      case "iroh.connect": {
        const additional = (a.additional as string[]).map((x) => Buffer.from(x, "hex"));
        const c = await this.#handles.get(a.id).connect(a.addr, Buffer.from(bytes!), additional);
        return done({ id: this.#keep(c) });
      }
      case "iroh.networkChange":
        await this.#handles.get(a.id).networkChange();
        return done({});
      case "iroh.close":
        await this.#handles.get(a.id).close();
        return done({});
      case "conn.openBi":
      case "conn.openUni": {
        const c = this.#handles.get(a.id);
        const s = op === "conn.openBi" ? await c.openBi() : await c.openUni();
        return done({ id: this.#keep(s) });
      }
      case "conn.acceptBi": {
        const s = await this.#handles.get(a.id).acceptBi();
        return done(s === null ? { end: true } : { id: this.#keep(s) });
      }
      case "conn.closed":
        return done(await this.#handles.get(a.id).closedInfo());
      case "conn.close":
        this.#handles.get(a.id).close(a.code, a.reason);
        return done({});
      case "istream.read": {
        const b = await this.#handles.get(a.id).read();
        return done(b === null ? { end: true } : {}, b === null ? null : new Uint8Array(b));
      }
      case "istream.write":
        await this.#handles.get(a.id).write(Buffer.from(bytes!));
        return done({});
      case "istream.finish":
        await this.#handles.get(a.id).finish();
        return done({});
      case "istream.stopped": {
        const code = await this.#handles.get(a.id).stopped();
        return done({ code: typeof code === "number" ? code : null });
      }
      case "istream.reset":
        await this.#handles.get(a.id).reset?.(a.code);
        return done({});
      default:
        throw new Error(`no operation ${op}`);
    }
  }

  /// The accounts' databases (as client/shell's `sql.*`), by id.
  readonly #sqls = new Map<number, Sql>();

  #sql(op: string, a: J): unknown {
    if (op === "sql.open") {
      const sql = a.name === ":memory:" ? this.host.memoryDb() : Effect.runSync(this.host.openDb(a.name));
      const id = this.#next++;
      this.#sqls.set(id, sql);
      return { id };
    }
    if (op === "sql.delete") {
      Effect.runSync(Effect.ignore(this.host.deleteDb(a.name)));
      return null;
    }
    const sql = this.#sqls.get(a.id);
    if (!sql) throw new Error(`no database ${a.id}`);
    switch (op) {
      case "sql.exec":
        sql.exec(a.sql);
        return null;
      case "sql.run":
        return sql.run(a.sql, a.params ?? []);
      case "sql.all":
        return sql.all(a.sql, a.params ?? []);
      case "sql.close":
        this.#sqls.delete(a.id);
        sql.close();
        return null;
    }
    throw new Error(`no operation ${op}`);
  }

  callSync(op: string, json: string): string {
    const a = JSON.parse(json) as J;
    if (op.startsWith("sql.")) {
      try {
        return JSON.stringify({ value: this.#sql(op, a) ?? null });
      } catch (e) {
        return JSON.stringify({ error: e instanceof Error ? e.message : String(e) });
      }
    }
    const it = this.#handles.get(a.id);
    const value = (() => {
      switch (op) {
        case "iroh.endpointId":
          return it.id();
        case "iroh.addAddr":
          return it.addAddr(a.addr) ?? null;
        case "iroh.relayStatus":
          return it.relayStatus();
        case "conn.remoteId":
          return it.remoteId();
        case "conn.closeReason":
          return it.closeReason() ?? null;
        case "conn.paths":
          return it.paths().map((p: J) => ({ selected: p.selected, relay: p.relay ?? null, rttMs: p.rttMs }));
        case "conn.stats":
          return it.stats();
        default:
          return undefined;
      }
    })();
    return JSON.stringify(value === undefined ? { error: `no operation ${op}` } : { value });
  }

  emitted: [number, string][] = [];
  #hearing: (() => void)[] = [];
  emit(client: number, json: string): void {
    this.emitted.push([client, json]);
    for (const wake of this.#hearing.splice(0)) wake();
  }
  /// Once the core emits again.
  heard(): Promise<void> {
    return new Promise((resolve) => this.#hearing.push(resolve));
  }
  now(): number {
    return Date.now();
  }
  monotonic(): number {
    return performance.now();
  }
  utcOffset(atMs: number): number {
    return -new Date(atMs).getTimezoneOffset();
  }
  random(buf: Uint8Array): void {
    crypto.getRandomValues(buf as Uint8Array<ArrayBuffer>);
  }
}

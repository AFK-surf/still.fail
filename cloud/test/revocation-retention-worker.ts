// Isolated test entry only. Never imported by production/configuration; no outbound I/O.
import { DurableObject } from "cloudflare:workers";
import { Directory, REVOCATION_CLEARANCE_TARGET_MS } from "../src/directory";
import type { Env } from "../src/env";

let clock = 4_102_444_800_000; // 2100: persisted alarms cannot fire on wall clock during tests.
Date.now = () => clock;

export class RevocationFixture extends DurableObject<Env> {
  #directory: Directory;
  #pending: Promise<unknown>[] = [];
  #failures = 0;
  #writes: number[] = [];
  #context: DurableObjectState;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // DurableObject's constructor requires the runtime-branded state; a Proxy
    // around that state fails its native type check. Instrument only methods
    // on the real, isolated fixture objects, never the production constructor.
    this.#context = ctx;
    const setAlarm = ctx.storage.setAlarm.bind(ctx.storage);
    Object.defineProperty(ctx.storage, "setAlarm", { configurable: true, value: async (at: number) => {
      this.#writes.push(at);
      if (this.#failures > 0) { this.#failures--; throw new Error("synthetic_alarm_failure"); }
      await setAlarm(at);
    } });
    Object.defineProperty(ctx, "waitUntil", { configurable: true, value: (promise: Promise<unknown>) => {
      this.#pending.push(promise);
    } });
    Object.defineProperty(ctx, "blockConcurrencyWhile", { configurable: true, value: (callback: () => Promise<unknown>) => {
      const promise = callback();
      this.#pending.push(promise);
      return promise;
    } });
    this.#directory = new Directory(this.#context, env);
  }
  // The runtime dispatches alarms and hibernatable socket events to this bound
  // fixture class, so forward them to the real Directory under test.
  async alarm(): Promise<void> { await this.#directory.alarm(); }
  async webSocketMessage(): Promise<void> { await this.#directory.webSocketMessage(); }
  async webSocketClose(ws: WebSocket, code: number): Promise<void> { await this.#directory.webSocketClose(ws, code); }
  async webSocketError(ws: WebSocket): Promise<void> { await this.#directory.webSocketError(ws); }
  async #settle(): Promise<string[]> {
    const errors: string[] = [];
    while (this.#pending.length) {
      for (const result of await Promise.allSettled(this.#pending.splice(0))) {
        if (result.status === "rejected") errors.push(String(result.reason));
      }
    }
    return errors;
  }
  async fetch(request: Request): Promise<Response> {
    await this.#settle();
    const path = new URL(request.url).pathname;
    if (path === "/connect" || path === "/connect-race") {
      const mutation = path === "/connect-race" ? this.#directory.revokeSessions("alice", ["race-session"]) : Promise.resolve();
      const [, response] = await Promise.all([mutation, this.#directory.fetch(new Request("https://fixture.test/stations/connect", { headers: { "x-stillfail-station": "station-a" } }))]);
      return response;
    }
    const body = await request.json() as any;
    if (body.now !== undefined) clock = body.now;
    const errors: string[] = [];
    let mutationRejected = false;
    try {
      if (body.op === "seed") {
        // Synthetic rows and SQL inspection are confined to this fixture.
        this.ctx.storage.sql.exec(`
          INSERT INTO users (sub,email,created_at) VALUES ('alice','alice@example.test',0),('bob','bob@example.test',0);
          INSERT INTO provider_identities VALUES ('apple','synthetic-apple','alice');
          INSERT INTO workspaces (id,name,created_by,created_at) VALUES ('a','A','alice',0),('b','B','bob',0);
          INSERT INTO members VALUES ('a','alice','owner',0),('a','bob','member',0),('b','bob','owner',0);
          INSERT INTO stations (id,workspace,name,enrolled_at,enrolled_by) VALUES ('station-a','a','Station',0,'alice');
        `);
      } else if (body.op === "revoke") await this.#directory.revokeSessions(body.sub ?? "alice", body.sids ?? null, body.cutoff);
      else if (body.op === "role") await this.#directory.setRole("alice", "a", "bob", body.role ?? "member");
      else if (body.op === "remove") await this.#directory.removeMember("alice", "a", "bob");
      else if (body.op === "alarm") await this.#directory.alarm();
      else if (body.op === "legacy") {
        this.ctx.storage.sql.exec("INSERT INTO revocations VALUES (?, ?, ?, ?)", body.workspace ?? "a", body.kind ?? "sid", body.id, body.cutoff);
      } else if (body.op === "restart") {
        await this.ctx.storage.deleteAlarm();
        this.#directory = new Directory(this.#context, this.env);
      } else if (body.op === "fail") this.#failures = body.count ?? 1;
      else if (body.op === "disconnect") {
        for (const ws of this.ctx.getWebSockets("station:station-a")) {
          ws.close(1000);
          await this.#directory.webSocketClose(ws, 1000);
        }
      }
    } catch (error) { mutationRejected = body.op === "revoke" || body.op === "role"; errors.push(String(error)); }
    errors.push(...await this.#settle());
    return Response.json({ errors, mutationRejected, clearanceTarget: REVOCATION_CLEARANCE_TARGET_MS, alarm: await this.ctx.storage.getAlarm(), writes: this.#writes,
      revocations: this.ctx.storage.sql.exec("SELECT * FROM revocations ORDER BY workspace,kind,id").toArray(),
      users: this.ctx.storage.sql.exec("SELECT sub,email FROM users ORDER BY sub").toArray(),
      identities: this.ctx.storage.sql.exec("SELECT * FROM provider_identities").toArray(),
      memberships: this.ctx.storage.sql.exec("SELECT * FROM members ORDER BY workspace,sub").toArray(),
    }, { status: errors.length ? 503 : 200 });
  }
}
export default {
  async fetch(request: Request, env: Env) {
    try {
      return await (env.DIRECTORY as unknown as DurableObjectNamespace<RevocationFixture>).getByName("synthetic").fetch(request);
    } catch (error) {
      // Synthetic fixture only: surface construction/routing errors to the test.
      return Response.json({ fixtureError: String(error), stack: error instanceof Error ? error.stack : undefined }, { status: 500 });
    }
  },
};

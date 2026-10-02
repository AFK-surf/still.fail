// The admin API (mesh/app/src/admin/mod.rs `route`): a table of routes, each a method, a path pattern and what answers
// it, gathered from src/api/routes (one module a part of the API). Reads go to the readers (off the main thread); what
// is not here answers 404 as an unknown route does.
import type { Readers } from "../read/pool.ts";
import { HttpError } from "../read/views.ts";
import { type Answer, type Request, error, json } from "./request.ts";
import { routes as chats } from "./routes/chats.ts";
import { routes as usage } from "./routes/usage.ts";
import { routes as sessions } from "./routes/sessions.ts";
import { routes as events } from "./routes/events.ts";
import type { Events } from "./events.ts";
import { Host } from "./host.ts";

export type Handler = (r: Request, args: string[]) => Promise<Answer>;
export type Route = { method: string; pattern: RegExp; handle: Handler };
/// What a route has to answer with.
export type Tools = {
  /// A read in a reader thread (src/read/ops.ts), answered as JSON; its error as `{error}` with its status.
  read(r: Request, op: string, args: unknown): Promise<Answer>;
  /// The machine's state, shared by GET /host and the events.
  host: Host;
  /// The event streams, once the station's store is open (the write side).
  events?: Events;
  /// Whether that session is there.
  sessionExists(key: string): boolean;
};

/// What the admin API answers with besides the readers: the write side, once there.
export type AdminDeps = { events?: Events; sessionExists?: (key: string) => boolean };

export class Admin {
  private routes: Route[];
  private readers: Readers;

  readonly host: Host;

  constructor(readers: Readers, deps: AdminDeps = {}) {
    this.readers = readers;
    this.host = new Host(readers);
    const tools: Tools = {
      read: async (r, op, args) => {
        try {
          return json(200, await this.readers.read(op, args, r.lang));
        } catch (e) {
          return error(e instanceof HttpError ? e.status : 500, (e as Error).message);
        }
      },
      host: this.host,
      events: deps.events,
      sessionExists: deps.sessionExists ?? (() => false),
    };
    this.routes = [...chats(tools), ...usage(tools), ...sessions(tools), ...events(tools)];
  }

  async handle(r: Request): Promise<Answer> {
    // Who asks is remembered by name, as the cloud's names (`deps.names`): what chats show of people who wrote.
    if (r.viewer.name !== "") this.readers.names.set(r.viewer.email, r.viewer.name);
    for (const route of this.routes) {
      const found = r.method === route.method ? route.pattern.exec(r.path) : null;
      if (found) {
        const answer = await route.handle(r, found.slice(1));
        answer.headers["stillfail-idempotent"] = "1";
        return answer;
      }
    }
    const unknown = error(404, `no route ${r.method} ${r.path}`);
    unknown.headers["stillfail-idempotent"] = "1";
    return unknown;
  }
}

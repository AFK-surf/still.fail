// The admin API (mesh/app/src/admin/mod.rs `route`): a table of routes, each a method, a path pattern and what
// answers it. Reads go to the readers (off the main thread); what is not here yet answers 404 as an unknown route does.
import type { Readers } from "../read/pool.ts";
import { HttpError } from "../read/views.ts";
import { type Answer, type Request, error, json, param } from "./request.ts";

type Handler = (r: Request, args: string[]) => Promise<Answer>;
type Route = { method: string; pattern: RegExp; handle: Handler };

export class Admin {
  private routes: Route[] = [];
  private readers: Readers;

  constructor(readers: Readers) {
    this.readers = readers;
    const read = (op: "chats" | "entries", args: (r: Request, a: string[]) => any): Handler => async (r, a) => {
      try {
        return json(200, await this.readers.read(op, args(r, a), r.lang));
      } catch (e) {
        return error(e instanceof HttpError ? e.status : 500, (e as Error).message);
      }
    };
    this.add("GET", /^\/chats$/, read("chats", (r) => ({ viewer: r.viewer, archived: param(r, "archived") === "1" })));
    this.add("GET", /^\/threads\/([^/]+)\/entries$/, async (r, [id]) => {
      // A thread id is an i64 in the Rust route; one that is no number is no thread.
      if (!/^[+-]?\d+$/.test(id)) return error(404, `unknown thread ${id}`);
      return read("entries", () => ({ viewer: r.viewer, thread: Number(id), params: r.query }))(r, [id]);
    });
  }

  private add(method: string, pattern: RegExp, handle: Handler) {
    this.routes.push({ method, pattern, handle });
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
    return error(404, `no route ${r.method} ${r.path}`);
  }
}

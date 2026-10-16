// The station's logins to command-line tools (docs/remote-login.md, 接口): under /machine-logins (/logins/<id> is a new
// profile's sign-in). Whoever may make things run on the station may start, cancel and finish one, in any workspace it is
// in (a joined workspace's members too: their agents could run `gh auth login` all the same); a read-only member sees
// how they stand only (the admin API refuses their writes; their reads lose the pages, codes and callbacks).
import { type Answer, type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { Logins, Refused, type Login } from "../../logins/index.ts";
import { readOnly } from "../../mesh/credential.ts";

/// A request's JSON object: nothing is `{}`; more than a megabyte refused.
function input(r: Request): Record<string, unknown> {
  if (r.body.length > 1_000_000) throw new Refused(413, "request too large");
  if (r.body.length === 0) return {};
  let value: unknown;
  try {
    value = JSON.parse(r.body.toString("utf8"));
  } catch {
    throw new Refused(400, "invalid JSON");
  }
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

const ok = (value: unknown) => json(200, JSON.stringify(value));

export const routes = (logins: () => Logins | undefined): Route[] => {
  const answer = async (f: (l: Logins) => Promise<Answer> | Answer): Promise<Answer> => {
    const l = logins();
    if (l === undefined) return error(503, "station starting");
    try {
      return await f(l);
    } catch (e) {
      if (e instanceof Refused) return error(e.status, e.message);
      return error(500, (e as Error)?.message ?? String(e));
    }
  };
  /// A login as the viewer may see it.
  const seen = (r: Request, login: Login) => (readOnly(r.viewer) ? Logins.limited(login) : login);
  const id = (s: string) => decodeURIComponent(s);
  return [
    {
      method: "GET",
      pattern: /^\/machine-logins\/*$/,
      handle: (r) =>
        answer(async (l) => {
          return ok({ logins: l.logins().map((x) => seen(r, x)) });
        }),
    },
    {
      method: "POST",
      pattern: /^\/machine-logins\/*$/,
      handle: (r) =>
        answer(async (l) => {
          const body = input(r);
          const command = typeof body.command === "string" || Array.isArray(body.command) ? (body.command as string | string[]) : null;
          if (command === null) throw new Refused(400, "command: the tool's own login command");
          return ok(await l.start(command, { by: { email: r.viewer.email, name: r.viewer.name }, workspace: r.viewer.workspace ?? null }));
        }),
    },
    {
      method: "GET",
      pattern: /^\/machine-logins\/+([^/]+)\/*$/,
      handle: (r, [login]) =>
        answer((l) => {
          const found = l.get(id(login!));
          return found === null ? error(404, "no such login") : ok(seen(r, found));
        }),
    },
    {
      method: "DELETE",
      pattern: /^\/machine-logins\/+([^/]+)\/*$/,
      handle: (_r, [login]) => answer((l) => ok(l.cancel(id(login!)))),
    },
    {
      // The browser's callback, from the client it came back to: `{method, path, headers, body?}` (the body base64) →
      // the command's answer `{status, headers, body}` (base64).
      method: "POST",
      pattern: /^\/machine-logins\/+([^/]+)\/+callback\/*$/,
      handle: (r, [login]) =>
        answer(async (l) => {
          const body = input(r);
          const headers = body.headers && typeof body.headers === "object" && !Array.isArray(body.headers) ? Object.fromEntries(Object.entries(body.headers as Record<string, unknown>).filter((e): e is [string, string] => typeof e[1] === "string")) : {};
          if (typeof body.method !== "string" || typeof body.path !== "string") throw new Refused(400, "method and path");
          return ok(await l.callback(id(login!), { method: body.method, path: body.path, headers, ...(typeof body.body === "string" ? { body: body.body } : {}) }));
        }),
    },
    {
      method: "POST",
      pattern: /^\/machine-logins\/+([^/]+)\/+paste\/*$/,
      handle: (r, [login]) =>
        answer(async (l) => {
          const text = input(r).text;
          if (typeof text !== "string" || text.trim() === "") throw new Refused(400, "text");
          return ok(await l.paste(id(login!), text));
        }),
    },
    {
      method: "POST",
      pattern: /^\/machine-logins\/+([^/]+)\/+input\/*$/,
      handle: (r, [login]) =>
        answer((l) => {
          l.input(id(login!), input(r));
          return ok({ ok: true });
        }),
    },
  ];
};

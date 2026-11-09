// Comma connects through the pages: one made of the line Comma's still.fail plugin shows (`comma <server> <token>`), and
// a Comma connect's part of its config entry (`commaEntry`). Editing, deleting and reconnecting a connect are every
// connect's (routes/connects.ts).
import { type Answer, type Request, error } from "../request.ts";
import type { Route } from "../admin.ts";
import { log } from "../../ops/log.ts";
import { tr } from "../../ops/i18n.ts";
import { commaLine } from "../../comma/index.ts";
import type { EntryEdit } from "../../connects/connections.ts";
import { type ConnectEditDeps, Refused, connectEdits, field, input, isObject, ok, str } from "./connects.ts";

type Json = any;

/// A Comma connect's part of its config entry (`comma`): Comma's address and the connector token, as given (blank ones
/// stay as they were).
export const commaEntry: EntryEdit = (given, had) => {
  if (!isObject(given) && had === null) return null;
  const c: Json = { ...(had ?? {}) };
  for (const key of ["server", "token"]) {
    const [, value] = field(given, key);
    if (value !== null) c[key] = value;
  }
  return c;
};

export const commaRoutes = (deps: Omit<ConnectEditDeps, "entry">): Route[] => {
  const { putConnect, raw, connectsRaw } = connectEdits({ ...deps, entry: (kind) => (kind === "comma" ? commaEntry : undefined) });
  const answer = (f: (r: Request) => Promise<Answer>) => async (r: Request) => {
    try {
      return await f(r);
    } catch (e) {
      if (e instanceof Refused) return error(e.status, e.message);
      log.error("admin", "admin request failed", { path: r.path, error: (e as Error).message });
      return error(500, (e as Error).message);
    }
  };

  /// POST /comma/connects: a connect made of the line Comma shows, its agents' model as `bind` says.
  const create = async (r: Request) => {
    const i = input(r);
    const line = commaLine(str(i.line) ?? "");
    if (line === null) throw new Refused(400, tr(r.lang, "station.comma.badLine"));
    const taken = new Set(connectsRaw(raw()).map((c: Json) => c?.id));
    let id = "comma";
    for (let n = 2; taken.has(id); n++) id = `comma-${n}`;
    return ok({ id, overview: await putConnect(r, id, { bind: i.bind, kind: "comma", mode: "multi-session", comma: line }) });
  };

  return [{ method: "POST", pattern: /^\/comma\/connects$/, handle: answer(create) }];
};

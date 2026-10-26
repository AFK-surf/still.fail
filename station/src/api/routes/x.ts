// X connects through the pages (docs/x.md「管理 API」): an account's keys checked, a connect made of them with its list of
// people, its list changed (handles looked up on X as they are given), and an X connect's part of its config entry
// (`xEntry`). Editing, deleting and reconnecting a connect are every connect's (routes/connects.ts).
import { type Answer, type Request, error, percentDecode } from "../request.ts";
import type { Route } from "../admin.ts";
import { log } from "../../ops/log.ts";
import { type Lang, tr } from "../../ops/i18n.ts";
import type { EntryEdit } from "../../connects/connections.ts";
import type { Allowed } from "../../x/index.ts";
import { userByName, verifyXKeys } from "../../x/surface.ts";
import { XClient, type XKeys } from "../../x/web.ts";
import { type ConnectEditDeps, Refused, connectEdits, connectSlug, field, get, input, isObject, ok, str, type Input } from "./connects.ts";

type Json = any;

export type XRoutesDeps = Omit<ConnectEditDeps, "entry">;

const KEYS = ["consumerKey", "consumerSecret", "accessToken", "accessSecret"] as const;

/// An X connect's part of its config entry (`x`): its keys as given (blank ones stay as they were), whether its posts
/// keep links and how long they may be, its list (as already looked up: ids and handles), and who it is as last seen.
export const xEntry: EntryEdit = (given, had) => {
  if (!isObject(given) && had === null) return null;
  const x: Json = { ...(had ?? {}) };
  for (const key of [...KEYS, "botName", "botImage", "botUserId", "botUsername"]) {
    const [, value] = field(given, key);
    if (value !== null) x[key] = value;
  }
  const links = get(given, "links");
  if (typeof links === "boolean") x.links = links;
  const max = get(given, "maxLength");
  if (typeof max === "number" && Number.isFinite(max)) x.maxLength = Math.min(25_000, Math.max(280, Math.floor(max)));
  const allow = get(given, "allow");
  if (Array.isArray(allow)) {
    const seen = new Set<string>();
    x.allow = allow.flatMap((a: Json) => (isObject(a) && typeof a.id === "string" && /^[0-9]{1,19}$/.test(a.id) && !seen.has(a.id) && (seen.add(a.id), true) ? [{ id: a.id, username: typeof a.username === "string" ? a.username : "" }] : []));
  }
  return x;
};

/// The keys as given.
const keysOf = (v: unknown): XKeys => ({
  consumerKey: (str(get(v, "consumerKey")) ?? "").trim(),
  consumerSecret: (str(get(v, "consumerSecret")) ?? "").trim(),
  accessToken: (str(get(v, "accessToken")) ?? "").trim(),
  accessSecret: (str(get(v, "accessSecret")) ?? "").trim(),
});

/// Handles as given (a list, or one text of them split by spaces and commas), each looked up on X: those found, or a
/// refusal naming those that are not.
async function lookUp(client: XClient, given: unknown, lang: Lang): Promise<Allowed[]> {
  const names = (Array.isArray(given) ? given.filter((g): g is string => typeof g === "string") : typeof given === "string" ? given.split(/[\s,，、]+/) : [])
    .map((n) => n.trim().replace(/^@/, "").replace(/^https?:\/\/(?:www\.)?(?:x|twitter)\.com\//i, "").replace(/[/?].*$/, ""))
    .filter((n) => n !== "");
  const found: Allowed[] = [];
  const missing: string[] = [];
  for (const name of [...new Set(names.map((n) => n.toLowerCase()))]) {
    const user = await userByName(client, name);
    if (user === null) missing.push(`@${name}`);
    else if (!found.some((f) => f.id === user.id)) found.push(user);
  }
  if (missing.length > 0) throw new Refused(400, tr(lang, "station.x.unknownUsers", { users: missing.join(tr(lang, "station.list.separator")) }));
  return found;
}

export const xRoutes = (deps: XRoutesDeps): Route[] => {
  const { putConnect, save, raw, connectsRaw, mine } = connectEdits({ ...deps, entry: (kind) => (kind === "x" ? xEntry : undefined) });
  const answer = (f: (r: Request, args: string[]) => Promise<Answer> | Answer) => async (r: Request, args: string[]) => {
    try {
      return await f(r, args);
    } catch (e) {
      if (e instanceof Refused) return error(e.status, e.message);
      log.error("admin", "admin request failed", { path: r.path, error: (e as Error).message });
      return error(500, (e as Error).message);
    }
  };
  const shownIdentity = (i: Awaited<ReturnType<typeof verifyXKeys>>[0]) => (i === null ? null : { botName: i.botName, botImage: i.botImage, botUserId: i.botUserId, username: i.username });

  /// POST /x/verify: an account's keys as given, checked against X.
  const verify = async (r: Request, i: Input) => {
    const [identity, errors] = await verifyXKeys(keysOf(i), r.lang);
    return ok({ identity: shownIdentity(identity), errors });
  };

  /// POST /x/connects: a connect of the account the keys sign as, named by its handle, with its list of people (their
  /// handles, looked up), checked before it is kept.
  const create = async (r: Request, i: Input) => {
    const keys = keysOf(i.x);
    const [identity, errors] = await verifyXKeys(keys, r.lang);
    if (identity === null || errors.length > 0) throw new Refused(400, errors.join(tr(r.lang, "station.list.semicolon")));
    const allow = await lookUp(new XClient(keys), get(i.x, "allow"), r.lang);
    const taken = new Set(connectsRaw(raw()).map((c: Json) => c?.id));
    const base = connectSlug(identity.username || identity.botName, "x");
    let id = base;
    for (let n = 2; taken.has(id); n++) id = `${base}-${n}`;
    const fields: Json = { ...keys, allow, botName: identity.botName, botUserId: identity.botUserId, botUsername: identity.username };
    if (identity.botImage !== null) fields.botImage = identity.botImage;
    if (typeof get(i.x, "links") === "boolean") fields.links = get(i.x, "links");
    const shown = await putConnect(r, id, { ...i, kind: "x", x: fields });
    return ok({ id, overview: shown });
  };

  /// The keys of an X connect of the viewer's.
  const keysOfConnect = (r: Request, raw: string): [string, XKeys] => {
    const id = mine(r, percentDecode(raw));
    const existing = connectsRaw(deps.config.raw()).find((c: Json) => c?.id === id);
    if (!existing || existing.kind !== "x") throw new Refused(404, `unknown connect ${id}`);
    return [id, keysOf(existing.x)];
  };

  return [
    { method: "POST", pattern: /^\/x\/verify$/, handle: answer((r) => verify(r, input(r))) },
    { method: "POST", pattern: /^\/x\/connects$/, handle: answer((r) => create(r, input(r))) },
    // Its list, as handles: each looked up on X, the whole list replaced.
    {
      method: "PUT",
      pattern: /^\/*x\/+connects\/+([^/]+)\/+allow\/*$/,
      handle: answer(async (r, [at]) => {
        const [id, keys] = keysOfConnect(r, at!);
        const allow = await lookUp(new XClient(keys), input(r).allow, r.lang);
        return ok(await save(r, `x list of ${id}`, (raw) => {
          for (const c of connectsRaw(raw).filter((c: Json) => c?.id === id)) c.x = { ...(isObject(c.x) ? c.x : {}), allow };
        }));
      }),
    },
    // Its keys replaced, checked first: they must sign as the same account (another account is another connect).
    {
      method: "PUT",
      pattern: /^\/*x\/+connects\/+([^/]+)\/+keys\/*$/,
      handle: answer(async (r, [at]) => {
        const [id, had] = keysOfConnect(r, at!);
        const given = keysOf(input(r));
        const keys: XKeys = { consumerKey: given.consumerKey || had.consumerKey, consumerSecret: given.consumerSecret || had.consumerSecret, accessToken: given.accessToken || had.accessToken, accessSecret: given.accessSecret || had.accessSecret };
        const [identity, errors] = await verifyXKeys(keys, r.lang);
        if (identity === null || errors.length > 0) throw new Refused(400, errors.join(tr(r.lang, "station.list.semicolon")));
        const before = connectsRaw(deps.config.raw()).find((c: Json) => c?.id === id)?.x?.botUserId;
        if (typeof before === "string" && before !== "" && before !== identity.botUserId) throw new Refused(400, tr(r.lang, "station.x.otherAccount", { username: `@${identity.username}` }));
        return ok(await save(r, `x keys of ${id}`, (raw) => {
          for (const c of connectsRaw(raw).filter((c: Json) => c?.id === id)) c.x = { ...(isObject(c.x) ? c.x : {}), ...keys };
        }));
      }),
    },
  ];
};

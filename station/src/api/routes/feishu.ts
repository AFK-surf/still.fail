// Feishu connects through the pages (docs/feishu.md「管理 API」): an app made by a scan (its registration begun,
// followed in the overview, dropped), an app's id and secret checked, a connect made of either, and a Feishu connect's
// part of its config entry (`feishuEntry`). Editing, deleting and reconnecting a connect are every connect's
// (routes/connects.ts).
import { type Answer, type Request, error, percentDecode } from "../request.ts";
import type { Route } from "../admin.ts";
import { log } from "../../ops/log.ts";
import { tr } from "../../ops/i18n.ts";
import type { FeishuParts } from "../../feishu/index.ts";
import { verifyFeishuApp } from "../../feishu/surface.ts";
import { domainOf } from "../../feishu/web.ts";
import type { EntryEdit } from "../../connects/connections.ts";
import { type ConnectEditDeps, Refused, connectEdits, connectSlug, field, get, idOf, input, isObject, ok, str, type Input } from "./connects.ts";

type Json = any;

export type FeishuRoutesDeps = Omit<ConnectEditDeps, "entry"> & { feishu: FeishuParts };

/// A Feishu connect's part of its config entry (`feishu`): its app's id and secret as given (blank ones stay as they
/// were), its domain, and who it is as last seen.
export const feishuEntry: EntryEdit = (given, had) => {
  if (!isObject(given) && had === null) return null;
  const f: Json = { ...(had ?? {}) };
  for (const key of ["appId", "appSecret", "botName", "botImage", "botOpenId"]) {
    const [, value] = field(given, key);
    if (value !== null) f[key] = value;
  }
  const domain = str(get(given, "domain"));
  if (domain === "feishu" || domain === "lark") f.domain = domain;
  const tenant = get(given, "tenant");
  if (isObject(tenant) && typeof tenant.key === "string") f.tenant = { key: tenant.key, name: typeof tenant.name === "string" ? tenant.name : "" };
  return f;
};

export const feishuRoutes = (deps: FeishuRoutesDeps): Route[] => {
  const { feishu } = deps;
  const { putConnect, save, raw, connectsRaw, mine } = connectEdits({ ...deps, entry: (kind) => (kind === "feishu" ? feishuEntry : undefined) });
  const answer = (f: (r: Request, args: string[]) => Promise<Answer> | Answer) => async (r: Request, args: string[]) => {
    try {
      return await f(r, args);
    } catch (e) {
      if (e instanceof Refused) return error(e.status, e.message);
      log.error("admin", "admin request failed", { path: r.path, error: (e as Error).message });
      return error(500, (e as Error).message);
    }
  };

  /// POST /feishu/verify: an app's id and secret as given, checked against Feishu.
  const verify = async (r: Request, i: Input) => {
    const appId = (str(i.appId) ?? "").trim();
    const appSecret = (str(i.appSecret) ?? "").trim();
    const [identity, errors] = await verifyFeishuApp(appId, appSecret, domainOf(i.domain), r.lang);
    const shown = identity === null ? null : { botName: identity.botName, botImage: identity.botImage, botOpenId: identity.botUserId, tenant: identity.teamId !== "" ? { key: identity.teamId, name: identity.team } : null };
    return ok({ identity: shown, errors });
  };

  /// POST /feishu/connects: a connect of an app made by a scan (`feishu.registration`) or given by its id and secret,
  /// named as its bot is, checked before it is kept.
  const create = async (r: Request, i: Input) => {
    const f = i.feishu;
    let appId = (str(get(f, "appId")) ?? "").trim();
    let appSecret = (str(get(f, "appSecret")) ?? "").trim();
    let domain = domainOf(get(f, "domain"));
    const registration = str(get(f, "registration"));
    if (registration !== undefined) {
      const made = feishu.registrations.take(registration, idOf(r.viewer));
      if (made === null || made.app === null) throw new Refused(400, tr(r.lang, "station.feishu.notRegistered"));
      [appId, appSecret, domain] = [made.app.appId, made.app.appSecret, made.domain];
    }
    const [identity, errors] = await verifyFeishuApp(appId, appSecret, domain, r.lang);
    // An app just made may take a moment to have its bot: kept all the same, it connects once it does.
    if (registration === undefined && (identity === null || errors.length > 0)) throw new Refused(400, errors.join(tr(r.lang, "station.list.semicolon")));
    const name = identity?.botName || appId;
    const taken = new Set(connectsRaw(raw()).map((c: Json) => c?.id));
    const base = connectSlug(name, "feishu");
    let id = base;
    for (let n = 2; taken.has(id); n++) id = `${base}-${n}`;
    const fields: Json = { appId, appSecret, domain };
    if (identity !== null) {
      fields.botName = identity.botName;
      fields.botOpenId = identity.botUserId;
      if (identity.botImage !== null) fields.botImage = identity.botImage;
      if (identity.teamId !== "") fields.tenant = { key: identity.teamId, name: identity.team };
    }
    const shown = await putConnect(r, id, { ...i, kind: "feishu", feishu: fields });
    return ok({ id, overview: shown });
  };

  return [
    { method: "POST", pattern: /^\/feishu\/verify$/, handle: answer((r) => verify(r, input(r))) },
    { method: "POST", pattern: /^\/feishu\/connects$/, handle: answer((r) => create(r, input(r))) },
    {
      method: "POST",
      pattern: /^\/feishu\/registrations$/,
      handle: answer(async (r) => {
        const i = input(r);
        const name = str(i.name)?.trim() ?? null;
        let made;
        try {
          made = await feishu.registrations.begin(idOf(r.viewer), domainOf(i.domain), name);
        } catch (e) {
          throw new Refused(502, tr(r.lang, "station.feishu.registerFailed", { error: (e as Error).message }));
        }
        return ok({ id: made.id, url: made.url, expiresAt: made.expiresAt, overview: await deps.overview(r.viewer, r.lang) });
      }),
    },
    {
      method: "DELETE",
      pattern: /^\/*feishu\/+registrations\/+([^/]+)\/*$/,
      handle: answer(async (r, [id]) => {
        if (!feishu.registrations.cancel(percentDecode(id!), idOf(r.viewer))) throw new Refused(404, tr(r.lang, "station.feishu.notRegistered"));
        return ok(await deps.overview(r.viewer, r.lang));
      }),
    },
    // An app's secret replaced: as any edit (PUT /connects/:id with `feishu.appSecret`); here too by its own name.
    {
      method: "PUT",
      pattern: /^\/*feishu\/+connects\/+([^/]+)\/+secret\/*$/,
      handle: answer(async (r, [raw]) => {
        const id = mine(r, percentDecode(raw!));
        const i = input(r);
        const secret = (str(i.appSecret) ?? "").trim();
        const existing = connectsRaw(deps.config.raw()).find((c: Json) => c?.id === id);
        if (!existing || existing.kind !== "feishu") throw new Refused(404, `unknown connect ${id}`);
        const f = isObject(existing.feishu) ? existing.feishu : {};
        const [, errors] = await verifyFeishuApp(String(f.appId ?? ""), secret, domainOf(f.domain), r.lang);
        if (errors.length > 0) throw new Refused(400, errors.join(tr(r.lang, "station.list.semicolon")));
        return ok(await save(r, `feishu secret of ${id}`, (raw) => {
          for (const c of connectsRaw(raw).filter((c: Json) => c?.id === id)) c.feishu = { ...(isObject(c.feishu) ? c.feishu : {}), appSecret: secret };
        }));
      }),
    },
  ];
};

// Feishu connects through the pages (「管理 API」): an app made by a scan (its registration begun,
// followed in the overview, dropped), an app's id and secret checked, a connect made of either, and a Feishu connect's
// part of its config entry (`feishuEntry`). Editing, deleting and reconnecting a connect are every connect's
// (routes/connects.ts).
import { type Answer, type Request, error, percentDecode } from "../request.ts";
import type { Route } from "../admin.ts";
import { log } from "../../ops/log.ts";
import { tr } from "../../ops/i18n.ts";
import type { FeishuParts } from "../../feishu/index.ts";
import type { Registration } from "../../feishu/register.ts";
import { verifyFeishuApp } from "../../feishu/surface.ts";
import { domainOf } from "../../feishu/web.ts";
import type { EntryEdit } from "../../connects/connections.ts";
import { type ConnectEditDeps, Refused, connectEdits, connectSlug, field, get, idOf, input, isObject, ok, str, type Input } from "./connects.ts";

type Json = any;

export type FeishuRoutesDeps = Omit<ConnectEditDeps, "entry"> & { feishu: FeishuParts };

/// A Feishu connect's part of its config entry (`feishu`): its app's id and secret as given (blank ones stay as they
/// were), its domain, thread mode, and who it is as last seen.
export const feishuEntry: EntryEdit = (given, had) => {
  if (!isObject(given) && had === null) return null;
  const f: Json = { ...(had ?? {}) };
  for (const key of ["appId", "appSecret", "botName", "botImage", "botOpenId", "registration"]) {
    const [, value] = field(given, key);
    if (value !== null) f[key] = value;
  }
  const domain = str(get(given, "domain"));
  if (domain === "feishu" || domain === "lark") f.domain = domain;
  const threads = get(given, "threads");
  if (typeof threads === "boolean") f.threads = threads;
  const tenant = get(given, "tenant");
  if (isObject(tenant) && typeof tenant.key === "string") f.tenant = { key: tenant.key, name: typeof tenant.name === "string" ? tenant.name : "" };
  return f;
};

export const feishuRoutes = (deps: FeishuRoutesDeps): Route[] => {
  const { feishu } = deps;
  const { putConnect, save, raw, connectsRaw, mine, ofViewer } = connectEdits({ ...deps, entry: (kind) => (kind === "feishu" ? feishuEntry : undefined) });
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

  /// Save an app, or find the result of an earlier save whose response or registration journal write failed.
  const saveApp = async (r: Request, i: Input, made: Registration | null): Promise<{ id: string; overview: unknown }> => {
    const f = i.feishu;
    let appId = (str(get(f, "appId")) ?? "").trim();
    let appSecret = (str(get(f, "appSecret")) ?? "").trim();
    let domain = domainOf(get(f, "domain"));
    const registration = made?.id;
    const saved = () => registration === undefined ? undefined : connectsRaw(raw()).find((c: Json) => c?.kind === "feishu" && c?.feishu?.registration === registration && ofViewer(r, c));
    const existing = saved();
    if (existing !== undefined) return { id: existing.id, overview: null };
    if (made !== null) {
      if (made.app === null) throw new Refused(400, tr(r.lang, "station.feishu.notRegistered"));
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
    const fields: Json = { appId, appSecret, domain, ...(registration !== undefined ? { registration } : {}), ...(get(f, "threads") === true ? { threads: true } : {}) };
    if (identity !== null) {
      fields.botName = identity.botName;
      fields.botOpenId = identity.botUserId;
      if (identity.botImage !== null) fields.botImage = identity.botImage;
      if (identity.teamId !== "") fields.tenant = { key: identity.teamId, name: identity.team };
    }
    try {
      return { id, overview: await putConnect(r, id, { ...i, kind: "feishu", feishu: fields }) };
    } catch (e) {
      // putConnect writes before producing the overview: a failure in the latter must not make a second connect.
      const committed = saved();
      if (committed !== undefined) return { id: committed.id, overview: null };
      throw e;
    }
  };

  /// Both the station's worker and an older client asking to create use the same serialized, idempotent save.
  feishu.registrations.start(async (made) => {
    const context = made.context!;
    const r: Request = { method: "POST", path: "/feishu/connects", query: [], headers: {}, body: Buffer.alloc(0), viewer: context.viewer, lang: context.lang };
    return (await saveApp(r, context.input, made)).id;
  });

  /// POST /feishu/connects: an app given by its id and secret, or a finished scan (including an older client).
  const create = async (r: Request, i: Input) => {
    const registration = str(get(i.feishu, "registration"));
    if (registration === undefined) return ok(await saveApp(r, i, null));
    const id = await feishu.registrations.complete(registration, idOf(r.viewer), r.viewer.workspace, async (made) => (await saveApp(r, i, made)).id);
    if (id === null) throw new Refused(400, tr(r.lang, "station.feishu.notRegistered"));
    return ok({ id, overview: await deps.overview(r.viewer, r.lang) });
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
          const { sub, email, name: viewerName, role, workspace, device, home } = r.viewer;
          const viewer = { sub, email, name: viewerName, role, workspace, device, ...(home === undefined ? {} : { home }) };
          const context = isObject(i.bind) ? { viewer, lang: r.lang, input: { bind: i.bind, mode: i.mode, requireMention: i.requireMention, feishu: { threads: i.threads === true } } } : null;
          made = await feishu.registrations.begin(idOf(r.viewer), domainOf(i.domain), name, context, workspace);
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
        if (!feishu.registrations.cancel(percentDecode(id!), idOf(r.viewer), r.viewer.workspace)) throw new Refused(404, tr(r.lang, "station.feishu.notRegistered"));
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

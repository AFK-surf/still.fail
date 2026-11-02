// Every connect through the pages, whatever its kind (admin/mod.rs `route`, admin/edits.rs `put_connect`/
// `delete_connect`): a connect edited, deleted, pointed at a session, connected again; the config edits every connect's
// routes make (`connectEdits`: Slack's routes/slack.ts and Feishu's routes/feishu.ts add their own connects with them).
// What is a kind's own (its platform's part of a connect: Slack's tokens, Feishu's app) is said by that kind's part
// (connects/connections.ts `ConnectKind`). Config edits go through config.json (ConfigFile.update); what answers with
// the overview is given it (`overview`).
import { type Answer, type Request, error, json, percentDecode } from "../request.ts";
import type { Route } from "../admin.ts";
import type { Viewer } from "../../mesh/credential.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { type Lang, tr } from "../../ops/i18n.ts";
import { log } from "../../ops/log.ts";
import { hubConfig, runs } from "../../sessions/config.ts";
import type { Hub } from "../../sessions/hub.ts";
import { bindSingle } from "../../sessions/lifecycle.ts";
import { runtimeKind, type RuntimeKind } from "../../agents/runtime.ts";
import type { EntryEdit } from "../../connects/connections.ts";

type Json = any;
export type Input = Record<string, unknown>;

/// A path segment as the pages send it (a + is a +).
export const segment = (s: string) => percentDecode(s.replace(/\+/g, "%2B"));
export const ok = (value: unknown) => json(200, JSON.stringify(value));
export class Refused extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

/// A request's JSON object (`read_json`): nothing is `{}`, as is anything not an object; more than a megabyte refused.
export function input(r: Request): Input {
  if (r.body.length > 1_000_000) throw new Refused(413, "request too large");
  if (r.body.length === 0) return {};
  let value: unknown;
  try {
    value = JSON.parse(r.body.toString("utf8"));
  } catch {
    throw new Refused(400, "invalid JSON");
  }
  return isObject(value) ? (value as Input) : {};
}

export const isObject = (v: unknown): v is Record<string, Json> => v !== null && typeof v === "object" && !Array.isArray(v);
/// `Input::str`: a string field, as given.
export const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);
/// `Input::text`: JavaScript's String(x ?? "") as serde writes it.
export const text = (v: unknown): string => (v === undefined || v === null ? "" : typeof v === "string" ? v : JSON.stringify(v));
/// serde's `Value::get`: a field of an object, nothing of anything else.
export const get = (v: unknown, key: string): unknown => (isObject(v) ? v[key] : undefined);

/// Who asks: their id (an email), their name, whether they manage the workspace (access.rs `Viewer`).
export const idOf = (v: Viewer) => v.email;
export const nameOf = (v: Viewer) => (v.name === "" ? v.email : v.name);
export const manages = (v: Viewer) => v.role === "owner" || v.role === "admin";

/// A connect id from its bot's name: lower case, runs of anything else as one dash.
export function connectSlug(name: string, fallback = "slack"): string {
  let out = "";
  for (const c of name.toLowerCase()) {
    if (/^[a-z0-9]$/.test(c)) out += c;
    else if (!out.endsWith("-")) out += "-";
  }
  const slug = [...out.replace(/^-+|-+$/g, "")].slice(0, 32).join("").replace(/-+$/, "");
  return slug === "" ? fallback : slug;
}

/// A field given as a string, trimmed and not empty; null when absent (`given` says whether it was).
export function field(object: unknown, key: string): [boolean, string | null] {
  const v = get(object, key);
  if (v === undefined) return [false, null];
  const t = typeof v === "string" ? v.trim() : "";
  return [true, t === "" ? null : t];
}

export type ConnectEditDeps = {
  config: ConfigFile;
  data: string;
  /// The hub, for pointing a single-session connect at a session and for the efforts a model takes; none while the
  /// station starts.
  hub: () => Hub | undefined;
  /// The overview as the viewer sees it, in their language: what the edits answer with.
  overview: (viewer: Viewer, lang: Lang) => unknown;
  /// Where the station is in still.fail cloud, when it is in a workspace (its home workspace's connects say none).
  place?: () => { origin: string; workspace: string; station: string } | null;
  /// How a kind's part of a connect is edited (none: a kind this station does not know, kept as it was).
  entry: (kind: string) => EntryEdit | undefined;
};

export function connectEdits(deps: ConnectEditDeps) {
  const { config } = deps;
  const overview = async (r: Request) => await deps.overview(r.viewer, r.lang);
  /// Edits the config for the viewer (said in the log as `what`); its refusals are the asker's (400).
  const change = (r: Request, what: string, f: (raw: Json) => void) => {
    try {
      config.update(f);
    } catch (e) {
      throw new Refused(400, (e as Error).message);
    }
    log.info("admin", "config changed from the admin page", { what, by: idOf(r.viewer) });
  };
  /// `save`: an edit, answered with the overview as it is then.
  const save = async (r: Request, what: string, f: (raw: Json) => void) => {
    change(r, what, f);
    return overview(r);
  };
  const raw = () => config.raw();
  const connectsRaw = (raw: Json): Json[] => (Array.isArray(raw.connects) ? raw.connects : (raw.connects = []));
  /// A connect is of the workspace it was added in (docs/multi-workspace.md; none said: the station's home one), and
  /// only that workspace's people see and change it. One of another workspace is no connect of theirs (404).
  const home = () => deps.place?.()?.workspace ?? null;
  const ofViewer = (r: Request, c: Json) => home() === null || ((typeof c?.workspace === "string" && c.workspace !== "" ? c.workspace : home()) === r.viewer.workspace);
  const mine = (r: Request, id: string) => {
    const c = (Array.isArray(raw().connects) ? raw().connects : []).find((c: Json) => c?.id === id);
    if (c !== undefined && !ofViewer(r, c)) throw new Refused(404, `unknown connect ${id}`);
    return id;
  };

  /// A connect added or edited (edits.rs `put_connect`): its kind's part as `deps.entry` makes it, its runtime as it
  /// was made.
  const putConnect = (r: Request, id: string, i: Input) =>
    save(r, `connect ${id}`, (raw) => {
      const lang = r.lang;
      const connects = connectsRaw(raw);
      const existing = connects.find((c) => c?.id === id);
      if (existing !== undefined && !ofViewer(r, existing)) throw new Refused(404, `unknown connect ${id}`);
      const bind = i.bind;
      const oldBind: Json = existing && isObject(existing.bind) ? existing.bind : null;
      const kept = (key: string) => {
        const [given, value] = field(bind, key);
        return given ? value : typeof oldBind?.[key] === "string" ? (oldBind[key] as string) : null;
      };
      const model = kept("model");
      const effort = kept("effort");
      const profile = kept("profile");
      // A connect's runtime is chosen when it is made: its sessions and their history belong to it.
      const given = get(bind, "runtime");
      let runtime: RuntimeKind;
      if (oldBind !== null) runtime = runtimeKind(oldBind.runtime) ?? "claude";
      else if (given !== undefined) {
        const named = runtimeKind(given);
        if (named === undefined) throw new Error(`unknown runtime ${typeof given === "string" ? given : JSON.stringify(given)}`);
        runtime = named;
      } else throw new Error("runtime is required");
      // The profile its sessions keep to (null: the pool's pick), one that runs its runtime and model.
      if (profile !== null) {
        // (as the hub has it: running what its check found too)
        const p = (deps.hub()?.config() ?? hubConfig(raw, deps.data)).profiles.find((p) => p.id === profile);
        if (!p || !p.runtimes.includes(runtime)) throw new Error(tr(lang, "station.profile.cannotRun", { profile, runtime }));
        if (model !== null && !runs(p, model)) throw new Error(tr(lang, "station.profile.modelOff", { profile: p.name, model }));
      }
      if (effort !== null && ["model", "effort", "profile"].some((f) => get(bind, f) !== undefined)) {
        const allowed = deps.hub()?.accounts.modelEfforts(runtime, model, profile);
        if (allowed !== undefined && !allowed.includes(effort)) {
          throw new Error(tr(lang, "station.profile.efforts", { runtime, efforts: allowed.join(tr(lang, "station.list.separator")) }));
        }
      }
      const next: Json = { id };
      const owner = ownerOf(existing?.createdBy ?? null, i.owner, r.viewer, lang);
      next.enabled = typeof i.enabled === "boolean" ? i.enabled : typeof existing?.enabled === "boolean" ? existing.enabled : true;
      next.kind = str(i.kind) ?? (typeof existing?.kind === "string" ? existing.kind : "slack");
      next.mode = i.mode === "multi-session" || i.mode === "single-session" ? i.mode : existing?.mode === "multi-session" || existing?.mode === "single-session" ? existing.mode : "multi-session";
      next.requireMention = typeof i.requireMention === "boolean" ? i.requireMention : typeof existing?.requireMention === "boolean" ? existing.requireMention : true;
      // Its kind's own part (its platform's tokens or app, who it is there): from what was given, and what it had.
      const entry = deps.entry(next.kind);
      if (entry !== undefined) {
        const own = entry(i[next.kind], isObject(existing?.[next.kind]) ? existing[next.kind] : null);
        if (own !== null) next[next.kind] = own;
      }
      if (owner !== null) next.createdBy = owner;
      // Added in a workspace the station joined: that workspace's (one of the home workspace says none, as before).
      if (existing === undefined && home() !== null && r.viewer.workspace !== home()) next.workspace = r.viewer.workspace;
      const b: Json = { runtime };
      if (model !== null) b.model = model;
      if (effort !== null) b.effort = effort;
      if (profile !== null) b.profile = profile;
      next.bind = b;
      // What this station does not know of it is kept (but its kind's part, and the part of a kind it was).
      const known = new Set(["id", "enabled", "kind", "mode", "requireMention", "createdBy", "bind", next.kind, typeof existing?.kind === "string" ? existing.kind : "slack"]);
      for (const [k, v] of Object.entries(existing ?? {})) if (!known.has(k)) next[k] = v;
      const at = connects.findIndex((c) => c?.id === id);
      if (at >= 0) connects[at] = next;
      else connects.push(next);
    });

  return { overview, change, save, raw, connectsRaw, home, ofViewer, mine, putConnect };
}

export type ConnectRoutesDeps = ConnectEditDeps & {
  /// A connect connected again as its kind does it, who its bot is read again.
  reconnect: (kind: string, id: string) => Promise<void>;
};

/// The routes of every connect: PUT and DELETE /connects/:id, POST /connects/:id/session and /reconnect.
export const connectRoutes = (deps: ConnectRoutesDeps): Route[] => {
  const answer = (f: (r: Request, args: string[]) => Promise<Answer> | Answer) => async (r: Request, args: string[]) => {
    try {
      return await f(r, args);
    } catch (e) {
      if (e instanceof Refused) return error(e.status, e.message);
      log.error("admin", "admin request failed", { path: r.path, error: (e as Error).message });
      return error(500, (e as Error).message);
    }
  };
  const { save, raw, connectsRaw, mine, putConnect } = connectEdits(deps);
  const hub = () => {
    const h = deps.hub();
    if (!h) throw new Refused(503, "station starting");
    return h;
  };
  return [
    { method: "PUT", pattern: /^\/*connects\/+([^/]+)\/*$/, handle: answer(async (r, [id]) => ok(await putConnect(r, mine(r, segment(id!)), input(r)))) },
    {
      method: "DELETE",
      pattern: /^\/*connects\/+([^/]+)\/*$/,
      handle: answer(async (r, [raw]) => {
        const id = mine(r, segment(raw!));
        return ok(
          await save(r, `delete connect ${id}`, (raw) => {
            const connects = connectsRaw(raw);
            if (!connects.some((c) => c?.id === id)) throw new Error(`unknown connect ${id}`);
            raw.connects = connects.filter((c) => c?.id !== id);
          }),
        );
      }),
    },
    {
      method: "POST",
      pattern: /^\/*connects\/+([^/]+)\/+session(?:\/.*)?$/,
      handle: answer((r, [raw]) => {
        const id = mine(r, segment(raw!));
        const i = input(r);
        const target = str(i.session);
        const key = bindSingle(hub(), id, target !== undefined && target !== "" ? target : null, str(i.title) ?? null, idOf(r.viewer));
        log.info("admin", "single-session binding changed from the admin page", { connect: id, session: key, by: idOf(r.viewer) });
        return ok({ session: key });
      }),
    },
    {
      method: "POST",
      pattern: /^\/*connects\/+([^/]+)\/+reconnect(?:\/.*)?$/,
      handle: answer(async (r, [at]) => {
        const id = mine(r, segment(at!));
        const kind = (Array.isArray(raw().connects) ? raw().connects : []).find((c: Json) => c?.id === id)?.kind;
        await deps.reconnect(typeof kind === "string" ? kind : "slack", id);
        return ok({ ok: true });
      }),
    },
  ];
};

/// Who a connect belongs to (edits.rs `owner_of`): whoever added it, unless `requested` hands it to someone else. Only
/// a workspace owner or admin, or the current owner, may do that.
function ownerOf(current: Json, requested: unknown, viewer: Viewer, lang: Lang): { id: string; name: string } | null {
  if (requested === undefined) return isObject(current) ? (current as { id: string; name: string }) : { id: idOf(viewer), name: nameOf(viewer) };
  const given = get(requested, "id");
  const id = typeof given === "string" ? given.trim().toLowerCase() : "";
  const at = id.indexOf("@");
  const [a, b] = at >= 0 ? [id.slice(0, at), id.slice(at + 1)] : ["", ""];
  const email = at >= 0 && a !== "" && b !== "" && !/\s/.test(id) && !b.includes("@");
  if (id !== "local" && !email) throw new Error(tr(lang, "station.connect.ownerEmail"));
  if (!manages(viewer) && (!isObject(current) || current.id !== idOf(viewer))) throw new Error(tr(lang, "station.connect.ownerWho"));
  const name = get(requested, "name");
  return { id, name: typeof name === "string" ? [...name].slice(0, 120).join("") : id };
}

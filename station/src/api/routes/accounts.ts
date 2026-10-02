// The accounts' part of the admin API (admin/mod.rs, admin/edits.rs, admin/decision.rs): profiles made, edited,
// checked, signed in and deleted; allowances read and reset; sign-ins for new profiles; the automatic decisions'
// settings. Edits answer with the overview, as the Rust station's do.
import { type Request, type Answer, error, json, percentDecode } from "../request.ts";
import type { Route } from "../admin.ts";
import { type Accounts, Refusal } from "../../accounts/index.ts";

export type AccountsRouteDeps = {
  /// The station's accounts; none while the station starts (503).
  accounts?: Accounts;
  /// GET /overview's answer for the request's viewer, in its language: what edits answer with.
  overview(r: Request): Promise<unknown> | unknown;
};

const segment = (s: string) => percentDecode(s.replace(/\+/g, "%2B"));
const ok = (value: unknown) => json(200, JSON.stringify(value));

/// The key a write is asked under (once.rs KEY), when it has a usable one.
const idempotencyKey = (r: Request): string | undefined => {
  const found = Object.entries(r.headers).find(([k]) => k.toLowerCase() === "idempotency-key")?.[1];
  return found !== undefined && found !== "" && found.length <= 200 ? found : undefined;
};

/// A request's JSON object (`read_json`): nothing is `{}`, as is anything not an object; more than a megabyte refused.
function input(r: Request): Record<string, unknown> {
  if (r.body.length > 1_000_000) throw new Refusal(413, "request too large");
  if (r.body.length === 0) return {};
  let value: unknown;
  try {
    value = JSON.parse(r.body.toString("utf8"));
  } catch {
    throw new Refusal(400, "invalid JSON");
  }
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

export const routes = ({ accounts, overview }: AccountsRouteDeps): Route[] => {
  /// Answered by the accounts, their refusals as `{error}` with their status; 503 while there are none.
  const answer = async (f: (a: Accounts) => Promise<Answer> | Answer): Promise<Answer> => {
    if (accounts === undefined) return error(503, "station starting");
    try {
      return await f(accounts);
    } catch (e) {
      if (e instanceof Refusal) return error(e.status, e.message);
      return error(500, (e as Error)?.message ?? String(e));
    }
  };
  const view = async (r: Request) => overview(r);
  const route = (method: string, pattern: RegExp, handle: (r: Request, args: string[]) => Promise<Answer>): Route => ({ method, pattern, handle });

  return [
    // A profile on the machine's own login.
    route("POST", /^\/profiles\/machine$/, (r) =>
      answer(async (a) => {
        const id = await a.newMachineProfile(input(r), r.viewer, r.lang);
        return ok({ id, overview: await view(r) });
      }),
    ),
    // A keyed profile, made once its key works.
    route("POST", /^\/profiles$/, (r) =>
      answer(async (a) => {
        const id = await a.newKeyedProfile(input(r), r.viewer, r.lang);
        return ok({ id, overview: await view(r) });
      }),
    ),
    // A sign-in that makes a profile once it succeeds.
    route("POST", /^\/logins$/, (r) => answer(async (a) => ok(await a.newLogin(input(r), r.viewer, r.lang)))),
    route("PUT", /^\/*automatic-decisions\/*$/, (r) =>
      answer(async (a) => {
        a.putAutomaticDecisions(input(r), r.viewer);
        return ok(await view(r));
      }),
    ),
    route("POST", /^\/*automatic-decisions\/+refresh\/*$/, (r) =>
      answer(async (a) => {
        await a.refreshDecisionModels(r.viewer, r.lang);
        return ok(await view(r));
      }),
    ),
    route("PUT", /^\/*profiles\/+([^/]+)\/*$/, (r, [id]) =>
      answer(async (a) => {
        const profile = segment(id!);
        a.putProfile(profile, input(r), r.viewer, r.lang);
        const answered = ok(await view(r));
        // Its new state is reported once known.
        void a.check(profile).catch(() => {});
        return answered;
      }),
    ),
    route("DELETE", /^\/*profiles\/+([^/]+)\/*$/, (r, [id]) =>
      answer(async (a) => {
        a.deleteProfile(segment(id!), r.viewer, r.lang);
        return ok(await view(r));
      }),
    ),
    route("POST", /^\/*profiles\/+([^/]+)\/+check(?:\/.*)?$/, (r, [id]) => answer(async (a) => ok(await a.check(segment(id!), r.lang)))),
    route("POST", /^\/*profiles\/+([^/]+)\/+reset-quota(?:\/.*)?$/, (r, [id]) =>
      answer(async (a) => {
        const key = idempotencyKey(r);
        if (key === undefined) throw new Refusal(400, "reset requires an idempotency key");
        return ok(await a.resetQuota(segment(id!), key, r.lang));
      }),
    ),
    route("POST", /^\/*profiles\/+([^/]+)\/+quota(?:\/.*)?$/, (r, [id]) => answer(async (a) => ok(await a.refreshQuota(segment(id!))))),
    route("GET", /^\/*profiles\/+([^/]+)\/+login(?:\/.*)?$/, (r, [id]) =>
      answer((a) => {
        const profile = known(a, segment(id!));
        return ok({ job: a.logins.get(profile) });
      }),
    ),
    route("DELETE", /^\/*profiles\/+([^/]+)\/+login(?:\/.*)?$/, (r, [id]) =>
      answer((a) => {
        const profile = known(a, segment(id!));
        a.logins.cancel(profile);
        return ok({ job: a.logins.get(profile) });
      }),
    ),
    route("POST", /^\/*profiles\/+([^/]+)\/+login(?:\/.*)?$/, (r, [id]) => answer(async (a) => ok({ job: await a.startLogin(segment(id!), r.viewer, r.lang) }))),
    route("POST", /^\/*profiles\/+([^/]+)\/+login-code(?:\/.*)?$/, (r, [id]) =>
      answer(async (a) => {
        const i = input(r);
        const code = i.code === undefined || i.code === null ? "" : typeof i.code === "string" ? i.code : JSON.stringify(i.code);
        try {
          return ok({ job: await a.logins.submitCode(segment(id!), code, r.lang) });
        } catch (e) {
          throw new Refusal(400, (e as Error).message);
        }
      }),
    ),
    // A sign-in for a new profile: dropped, or given its code. Any other id is no route.
    route("DELETE", /^\/*logins\/+([^/]+)\/*$/, (r, [id]) =>
      answer((a) => {
        const login = segment(id!);
        if (!a.hasPending(login)) return noRoute(r);
        a.dropLogin(login);
        return ok({ ok: true });
      }),
    ),
    route("POST", /^\/*logins\/+([^/]+)\/+code(?:\/.*)?$/, (r, [id]) =>
      answer(async (a) => {
        const login = segment(id!);
        if (!a.hasPending(login)) return noRoute(r);
        const i = input(r);
        const code = i.code === undefined || i.code === null ? "" : typeof i.code === "string" ? i.code : JSON.stringify(i.code);
        try {
          return ok({ job: await a.logins.submitCode(login, code, r.lang) });
        } catch (e) {
          throw new Refusal(400, (e as Error).message);
        }
      }),
    ),
  ];
};

/// The profile's id, when there is such a profile (404 when not).
function known(a: Accounts, id: string): string {
  if (!a.profiles().some((p) => p.id === id)) throw new Refusal(404, `unknown profile ${id}`);
  return id;
}

const noRoute = (r: Request) => error(404, `no route ${r.method} ${r.path}`);

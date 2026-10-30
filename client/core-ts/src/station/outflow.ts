// The programs of a station's machine granted its data (docs/data-outflow.md), as the `outflowGrants` topic shows
// them: each with who it is as the system said it, what it said of itself, what it may read (of this station or of
// the whole workspace), who allowed it, when it was granted and what it read lately, the times in words. Revoked with
// `outflow.revoke`. And the requests waiting for an admin, the same way, answered with `outflow.answer`.
import { dayClock } from "../format.ts";
import { t } from "../i18n.ts";
import { get, isObject } from "../util.ts";

type J = any;

const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/// A kind of data in words.
const scopeName = (scope: string) => t(`core-views.outflow.scope.${scope}`);

/// Who a grant's or a request's program is, as the system said it, and what it said of itself.
function programShown(g: J): J {
  const identity = isObject(get(g, "identity")) ? (get(g, "identity") as J) : {};
  const path = str(identity.path) ?? "";
  const signed = identity.valid === true && str(identity.teamId) !== null;
  const said = isObject(get(g, "said")) ? (get(g, "said") as J) : {};
  return {
    id: String(get(g, "id")),
    program: str(identity.app) ?? str(identity.identifier) ?? path.split("/").at(-1) ?? path,
    signed,
    signer: signed ? (str(identity.signer) ?? str(identity.teamId)) : null,
    signedText: signed ? t("core-views.outflow.signedBy", { signer: str(identity.signer) ?? str(identity.teamId) ?? "" }) : t("core-views.outflow.unsigned"),
    teamId: str(identity.teamId),
    identifier: str(identity.identifier),
    path,
    said: [str(said.name), str(said.purpose)].filter((s) => s !== null).join(" — "),
  };
}

const reachOf = (v: unknown): "station" | "workspace" => (v === "workspace" ? "workspace" : "station");

/// One request waiting for an admin, as shown: each kind it asks for with what it gives away, and how far it asks to
/// reach.
export function requestShown(q: J, now: number, offsetMin: number): J {
  const askedAt = num(get(q, "askedAt")) ?? 0;
  const reach = reachOf(get(q, "reach"));
  return {
    ...programShown(q),
    scopes: (Array.isArray(get(q, "scopes")) ? (get(q, "scopes") as unknown[]) : []).map((s) => ({ id: String(s), text: scopeName(String(s)), why: t(`core-views.outflow.scope.${String(s)}Why`) })),
    reach,
    reachText: t(`core-views.outflow.reach.${reach}`),
    askedAt,
    askedText: t("core-views.outflow.askedAt", { when: dayClock(askedAt, now, offsetMin) }),
  };
}

/// One grant as shown.
export function grantShown(g: J, now: number, offsetMin: number): J {
  const grantedAt = num(get(g, "grantedAt")) ?? 0;
  const lastReadAt = num(get(g, "lastReadAt"));
  const reads = (Array.isArray(get(g, "reads")) ? (get(g, "reads") as J[]) : []).filter(isObject).map((r) => ({
    at: num(r.at) ?? 0,
    atText: dayClock(num(r.at) ?? 0, now, offsetMin),
    scope: String(r.scope),
    scopeText: scopeName(String(r.scope)),
    rows: num(r.rows) ?? 0,
  }));
  const reach = reachOf(get(g, "reach"));
  const allowedBy = str(get(g, "allowedBy"));
  return {
    ...programShown(g),
    reach,
    reachText: t(`core-views.outflow.reach.${reach}`),
    allowedBy,
    scopes: (Array.isArray(get(g, "scopes")) ? (get(g, "scopes") as unknown[]) : []).map((s) => ({ id: String(s), text: scopeName(String(s)) })),
    grantedAt,
    grantedText: allowedBy === null ? t("core-views.outflow.grantedAt", { when: dayClock(grantedAt, now, offsetMin) }) : t("core-views.outflow.allowedBy", { when: dayClock(grantedAt, now, offsetMin), who: allowedBy }),
    lastReadAt,
    // Allowed, its program not come for the token yet (a station from before has none such: taken).
    taken: get(g, "taken") !== false,
    lastReadText: get(g, "taken") === false ? t("core-views.outflow.notTaken") : lastReadAt === null ? t("core-views.outflow.neverRead") : t("core-views.outflow.lastRead", { when: dayClock(lastReadAt, now, offsetMin) }),
    // The newest first.
    reads: reads.reverse(),
  };
}

/// What the station said (GET /outflow/grants, `outflow-grants`), as shown: `supported` false for a station from before.
/// Requests the oldest first; none from a station from before them.
export function grantsShown(answer: unknown, now: number, offsetMin: number): J {
  if (get(answer, "unsupported") === true) return { supported: false, grants: [], requests: [] };
  const grants = (Array.isArray(get(answer, "grants")) ? (get(answer, "grants") as J[]) : []).filter(isObject);
  const requests = (Array.isArray(get(answer, "requests")) ? (get(answer, "requests") as J[]) : []).filter(isObject);
  return {
    supported: true,
    grants: grants.map((g) => grantShown(g, now, offsetMin)).sort((a, b) => b.grantedAt - a.grantedAt),
    requests: requests.map((q) => requestShown(q, now, offsetMin)).sort((a, b) => a.askedAt - b.askedAt),
  };
}

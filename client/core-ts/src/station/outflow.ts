// The programs of a station's machine granted its data (docs/data-outflow.md), as the `outflowGrants` topic shows
// them: each with who it is as the system said it, what it said of itself, what it may read, when it was granted and
// what it read lately, the times in words. Revoked with `outflow.revoke`.
import { dayClock } from "../format.ts";
import { t } from "../i18n.ts";
import { get, isObject } from "../util.ts";

type J = any;

const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/// A kind of data in words.
const scopeName = (scope: string) => t(`core-views.outflow.scope.${scope}`);

/// One grant as shown.
export function grantShown(g: J, now: number, offsetMin: number): J {
  const identity = isObject(get(g, "identity")) ? (get(g, "identity") as J) : {};
  const path = str(identity.path) ?? "";
  const signed = identity.valid === true && str(identity.teamId) !== null;
  const program = str(identity.app) ?? str(identity.identifier) ?? path.split("/").at(-1) ?? path;
  const said = isObject(get(g, "said")) ? (get(g, "said") as J) : {};
  const grantedAt = num(get(g, "grantedAt")) ?? 0;
  const lastReadAt = num(get(g, "lastReadAt"));
  const reads = (Array.isArray(get(g, "reads")) ? (get(g, "reads") as J[]) : []).filter(isObject).map((r) => ({
    at: num(r.at) ?? 0,
    atText: dayClock(num(r.at) ?? 0, now, offsetMin),
    scope: String(r.scope),
    scopeText: scopeName(String(r.scope)),
    rows: num(r.rows) ?? 0,
  }));
  return {
    id: String(get(g, "id")),
    program,
    signed,
    signer: signed ? (str(identity.signer) ?? str(identity.teamId)) : null,
    signedText: signed ? t("core-views.outflow.signedBy", { signer: str(identity.signer) ?? str(identity.teamId) ?? "" }) : t("core-views.outflow.unsigned"),
    teamId: str(identity.teamId),
    identifier: str(identity.identifier),
    path,
    said: [str(said.name), str(said.purpose)].filter((s) => s !== null).join(" — "),
    scopes: (Array.isArray(get(g, "scopes")) ? (get(g, "scopes") as unknown[]) : []).map((s) => ({ id: String(s), text: scopeName(String(s)) })),
    grantedAt,
    grantedText: t("core-views.outflow.grantedAt", { when: dayClock(grantedAt, now, offsetMin) }),
    lastReadAt,
    lastReadText: lastReadAt === null ? t("core-views.outflow.neverRead") : t("core-views.outflow.lastRead", { when: dayClock(lastReadAt, now, offsetMin) }),
    // The newest first.
    reads: reads.reverse(),
  };
}

/// What the station said (GET /outflow/grants, `outflow-grants`), as shown: `supported` false for a station from before.
export function grantsShown(answer: unknown, now: number, offsetMin: number): J {
  if (get(answer, "unsupported") === true) return { supported: false, grants: [] };
  const grants = (Array.isArray(get(answer, "grants")) ? (get(answer, "grants") as J[]) : []).filter(isObject);
  return { supported: true, grants: grants.map((g) => grantShown(g, now, offsetMin)).sort((a, b) => b.grantedAt - a.grantedAt) };
}

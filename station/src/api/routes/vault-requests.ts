// What agents asked of the vault (docs/vault.md, agent 用密钥): GET vault/requests, those still waiting that the viewer
// may decide (they are a member of the request's vault); POST vault/grants and vault/denials, the decision as the
// viewer's app signed it. The grant's secret is sealed to the request's box and opened only by the keeper; a refused
// one says why. Only where the station pinned its workspace's lock, as the vault's other routes.
import type { LockState } from "../../cloud/lock.ts";
import type { Deny, Grant } from "../../vault/crypto.ts";
import type { Secrets } from "../../vault/secrets.ts";
import type { Route } from "../admin.ts";
import { type Answer, type Request, json } from "../request.ts";

export type VaultRequestsDeps = {
  secrets: Secrets;
  /// The lock pinned in a workspace this station is in; null when none is.
  lock(workspace: string): LockState | null;
};

const refuse = (status: number, code: string, error: string): Answer => json(status, JSON.stringify({ error, code }));

function body(r: Request): unknown {
  try {
    return JSON.parse(r.body.toString("utf8"));
  } catch {
    return undefined;
  }
}

export const routes = ({ secrets, lock }: VaultRequestsDeps): Route[] => {
  const locked = (r: Request) => lock(r.viewer.workspace);
  const NEEDS_LOCK = () => refuse(409, "vault_needs_lock", "the vault needs the workspace's security mode (its lock) pinned on this station");
  /// A decision: taken, or why not.
  const decide = (r: Request, f: (l: LockState, o: any) => string | null): Answer => {
    const l = locked(r);
    if (l === null) return NEEDS_LOCK();
    const o = body(r);
    if (o === null || typeof o !== "object") return refuse(400, "vault_invalid", "a decision, as JSON");
    const why = f(l, o);
    return why === null ? json(200, JSON.stringify({ ok: true })) : refuse(409, "vault_refused", why);
  };
  return [
    {
      method: "GET",
      pattern: /^\/vault\/requests$/,
      handle: async (r) => {
        const l = locked(r);
        if (l === null) return NEEDS_LOCK();
        return json(200, JSON.stringify({ requests: secrets.pending(l, r.viewer.sub) }));
      },
    },
    { method: "POST", pattern: /^\/vault\/grants$/, handle: async (r) => decide(r, (l, o) => secrets.grant(l, r.viewer.sub, o as Grant)) },
    { method: "POST", pattern: /^\/vault\/denials$/, handle: async (r) => decide(r, (l, o) => secrets.deny(l, r.viewer.sub, o as Deny)) },
  ];
};

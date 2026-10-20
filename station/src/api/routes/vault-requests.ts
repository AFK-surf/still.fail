// What agents asked of the vault (docs/vault.md, agent 用密钥): GET vault/requests, those still waiting that the viewer
// may decide (they are a member of the request's vault, or own the plain library's item); POST vault/grants and
// vault/denials, the decision as the viewer's app signed it. The grant's secret is sealed to the request's box and opened
// only by the keeper; a refused one says why. GET vault/uses: the requests decided, as a vault's uses.
//
// The plain library (vault/plain.ts, docs/vault.md 不加锁的库), a workspace's without security mode: GET vault/plain (the
// viewer's items, without their fields), GET vault/plain/item?id= (one, with them), PUT vault/plain (a version; security
// mode on, only a deletion: the items are moved into the viewer's vault), and POST vault/plain/grants and
// vault/plain/denials (its requests decided by the item's owner, not signed: nothing here is encrypted).
import type { LockState } from "../../cloud/lock.ts";
import type { Deny, Grant } from "../../vault/crypto.ts";
import { type PlainItem, type PlainStore, plainOk, shown } from "../../vault/plain.ts";
import type { Secrets } from "../../vault/secrets.ts";
import type { Route } from "../admin.ts";
import type { Events } from "../events.ts";
import { type Answer, type Request, json, param } from "../request.ts";

export type VaultRequestsDeps = {
  secrets: Secrets;
  plain: PlainStore;
  /// The lock pinned in a workspace this station is in; null when none is.
  lock(workspace: string): LockState | null;
  events?: Events;
};

const refuse = (status: number, code: string, error: string, more: Record<string, unknown> = {}): Answer => json(status, JSON.stringify({ error, code, ...more }));

function body(r: Request): unknown {
  try {
    return JSON.parse(r.body.toString("utf8"));
  } catch {
    return undefined;
  }
}

export const routes = ({ secrets, plain, lock, events }: VaultRequestsDeps): Route[] => {
  const locked = (r: Request) => lock(r.viewer.workspace);
  const NEEDS_LOCK = () => refuse(409, "vault_needs_lock", "the vault needs the workspace's security mode (its lock) pinned on this station");
  /// A decision: taken, or why not.
  const decide = (r: Request, f: (o: any) => string | null): Answer => {
    const o = body(r);
    if (o === null || typeof o !== "object") return refuse(400, "vault_invalid", "a decision, as JSON");
    const why = f(o);
    return why === null ? json(200, JSON.stringify({ ok: true })) : refuse(409, "vault_refused", why);
  };
  const owner = (r: Request) => r.viewer.email.toLowerCase();
  return [
    {
      method: "GET",
      pattern: /^\/vault\/requests$/,
      handle: async (r) => json(200, JSON.stringify({ requests: secrets.pending(r.viewer.workspace, locked(r), r.viewer) })),
    },
    {
      method: "POST",
      pattern: /^\/vault\/grants$/,
      handle: async (r) => {
        const l = locked(r);
        return l === null ? NEEDS_LOCK() : decide(r, (o) => secrets.grant(l, r.viewer.sub, o as Grant));
      },
    },
    {
      method: "POST",
      pattern: /^\/vault\/denials$/,
      handle: async (r) => {
        const l = locked(r);
        return l === null ? NEEDS_LOCK() : decide(r, (o) => secrets.deny(l, r.viewer.sub, o as Deny));
      },
    },
    {
      method: "GET",
      pattern: /^\/vault\/uses$/,
      handle: async (r) => json(200, JSON.stringify({ uses: secrets.uses(r.viewer.workspace, locked(r), param(r, "vault") ?? "", r.viewer) })),
    },
    {
      method: "GET",
      pattern: /^\/vault\/plain$/,
      handle: async (r) => json(200, JSON.stringify({ items: plain.items(r.viewer.workspace, owner(r)).map(shown), locked: locked(r) !== null })),
    },
    {
      method: "GET",
      pattern: /^\/vault\/plain\/item$/,
      handle: async (r) => {
        const i = plain.item(r.viewer.workspace, param(r, "id") ?? "");
        if (i === null || i.owner !== owner(r) || i.deleted) return refuse(404, "vault_unknown", "no such item here, or not yours");
        return json(200, JSON.stringify({ item: i }));
      },
    },
    {
      method: "PUT",
      pattern: /^\/vault\/plain$/,
      handle: async (r) => {
        const ws = r.viewer.workspace;
        const o = body(r) as PlainItem;
        if (o === null || typeof o !== "object") return refuse(400, "vault_invalid", "an item, as JSON");
        const next: PlainItem = { ...o, ws, owner: owner(r) };
        // Security mode on, the plain library only empties: what it held goes into the person's vault, encrypted.
        if (locked(r) !== null && next.deleted !== true) return refuse(409, "vault_locked", "security mode is on: secrets go into the vault, encrypted");
        const prev = plain.item(ws, next.id);
        if (prev !== null && prev.owner !== next.owner) return refuse(404, "vault_unknown", "no such item here, or not yours");
        const follows = prev === null ? 0 : prev.version + 1;
        if (next.version !== follows) return refuse(409, "vault_conflict", `version ${follows} is the one that follows`, { item: prev && shown(prev) });
        const why = plainOk(prev, next, owner(r));
        if (why !== null) return refuse(400, "vault_invalid", why);
        plain.put(next);
        const kept = plain.item(ws, next.id)!;
        events?.tell("vault-plain", shown(kept), `vault-plain\0${kept.id}`, (v) => v.workspace === ws && v.email.toLowerCase() === kept.owner);
        return json(200, JSON.stringify({ item: shown(kept) }));
      },
    },
    { method: "POST", pattern: /^\/vault\/plain\/grants$/, handle: async (r) => decide(r, (o) => secrets.grantPlain(r.viewer.workspace, locked(r), r.viewer.email, o)) },
    { method: "POST", pattern: /^\/vault\/plain\/denials$/, handle: async (r) => decide(r, (o) => secrets.denyPlain(r.viewer.workspace, r.viewer.email, o)) },
  ];
};

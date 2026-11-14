// What agents asked of the vault (agent 用密钥): GET vault/requests, those still waiting that the viewer
// may decide (they are a member of the request's vault, or own the plain library's item); POST vault/grants and
// vault/denials, the decision as the viewer's app signed it. The grant's secret is sealed to the request's box and opened
// only by the keeper; a refused one says why. GET vault/uses: the requests decided, as a vault's uses.
//
// The plain library (vault/plain.ts 不加锁的库), a workspace's without security mode: GET vault/plain (the
// viewer's items, without their fields, and their longest grant), GET vault/plain/item?id= (one, with them), PUT
// vault/plain (a version; security mode on, only a deletion: the items are moved into the viewer's vault), PUT
// vault/plain/lasts ({lasts, at}: the longest grant of the viewer's items that say none), and POST vault/plain/grants and
// vault/plain/denials (its requests decided by the item's owner, not signed: nothing here is encrypted).
//
// A secret an agent asked to keep (secret_save agent 存入), approved: POST vault/saves `{request, vault}`
// once the viewer's app wrote it into their vault (and brought its copy here), POST vault/plain/saves `{request}` to
// write it into their plain library here (`{request, fields}`: one they typed in on its card). Turned down: vault/denials or vault/plain/denials, as any request.
//
// A request to rename an item or say what it is (secret_describe 改名和说明), approved: POST vault/described `{request}`
// once the viewer's app wrote the item's next version saying so (and brought it here), POST vault/plain/described
// `{request}` to write it into the plain library here. It grants nothing (POST vault/grants refuses it).
//
// A request to delete an item (secret_delete 删除), approved: POST vault/removed `{request}` once the viewer's app wrote
// the item's deleted version (and brought it here), POST vault/plain/removed `{request}` to delete it from the plain
// library here. It grants nothing either.
import { admit, type LockState } from "../../cloud/lock.ts";
import { wall } from "../../ops/fibers.ts";
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

/// Preparation is shared; a caller that disconnects stops waiting without cancelling the other callers' work.
async function preparedBeforeCancel(preparing: Promise<void>, signal?: AbortSignal): Promise<boolean> {
  if (signal === undefined) { await preparing; return true; }
  return new Promise<boolean>((resolve, reject) => {
    const abort = () => { signal.removeEventListener("abort", abort); resolve(false); };
    if (signal.aborted) abort();
    else signal.addEventListener("abort", abort, { once: true });
    preparing.then(() => { signal.removeEventListener("abort", abort); resolve(!signal.aborted); }, (error) => {
      signal.removeEventListener("abort", abort);
      reject(error);
    });
  });
}

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
      handle: async (r) => {
        let current = locked(r);
        for (;;) {
          const before = current;
          if (r.signal?.aborted) return refuse(503, "read_cancelled", "read cancelled");
          if (!await preparedBeforeCancel(secrets.preparePending(r.viewer.workspace, before !== null), r.signal)) return refuse(503, "read_cancelled", "read cancelled");
          current = locked(r);
          if (current === before) break;
          if (current === null) return refuse(409, "lock_changed", "the workspace's security mode changed while the requests were prepared; try again");
          const v = r.viewer;
          try {
            admit(current, { sub: v.sub, endpoint: v.device, base: v.lockDevice?.base, proof: v.lockDevice?.proof }, Math.floor(wall.now() / 1000));
          } catch {
            return refuse(403, "lock_unconfirmed", "this device is no longer admitted to the workspace");
          }
        }
        return json(200, JSON.stringify({ requests: secrets.pending(r.viewer.workspace, current, r.viewer) }));
      },
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
      // A secret an agent asked to keep, written into the viewer's vault by their app: `{request, vault}`.
      method: "POST",
      pattern: /^\/vault\/saves$/,
      handle: async (r) => {
        const l = locked(r);
        return l === null ? NEEDS_LOCK() : decide(r, (o) => secrets.saved(l, r.viewer.sub, o));
      },
    },
    {
      // A request to rename an item (secret_describe), approved by the viewer's app once it wrote the item: `{request}`.
      method: "POST",
      pattern: /^\/vault\/described$/,
      handle: async (r) => {
        const l = locked(r);
        return l === null ? NEEDS_LOCK() : decide(r, (o) => secrets.described(l, r.viewer.sub, o));
      },
    },
    {
      // A request to delete an item (secret_delete), approved by the viewer's app once it deleted the item: `{request}`.
      method: "POST",
      pattern: /^\/vault\/removed$/,
      handle: async (r) => {
        const l = locked(r);
        return l === null ? NEEDS_LOCK() : decide(r, (o) => secrets.removed(l, r.viewer.sub, o));
      },
    },
    {
      method: "GET",
      pattern: /^\/vault\/uses$/,
      handle: async (r) => json(200, JSON.stringify({ uses: await secrets.uses(r.viewer.workspace, locked(r), param(r, "vault") ?? "", r.viewer) })),
    },
    {
      method: "GET",
      pattern: /^\/vault\/plain$/,
      handle: async (r) => {
        const lasts = plain.lasts(r.viewer.workspace, owner(r));
        return json(200, JSON.stringify({ items: plain.items(r.viewer.workspace, owner(r)).map(shown), locked: locked(r) !== null, ...(lasts ? { lasts: lasts.lasts, lastsAt: lasts.at } : {}) }));
      },
    },
    {
      method: "PUT",
      pattern: /^\/vault\/plain\/lasts$/,
      handle: async (r) => {
        const o = body(r) as { lasts?: unknown; at?: unknown } | null;
        const why = plain.setLasts(r.viewer.workspace, owner(r), o?.lasts, o?.at);
        return why === null ? json(200, JSON.stringify({ ok: true })) : refuse(400, "vault_invalid", why);
      },
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
        events?.tell("vault-plain", shown(kept), `vault-plain\0${kept.id}`, { workspace: ws, email: kept.owner });
        return json(200, JSON.stringify({ item: shown(kept) }));
      },
    },
    { method: "POST", pattern: /^\/vault\/plain\/grants$/, handle: async (r) => decide(r, (o) => secrets.grantPlain(r.viewer.workspace, locked(r), r.viewer.email, o)) },
    { method: "POST", pattern: /^\/vault\/plain\/denials$/, handle: async (r) => decide(r, (o) => secrets.denyPlain(r.viewer.workspace, r.viewer.email, o)) },
    {
      // A request to rename an item of the plain library, approved by its owner: written here.
      method: "POST",
      pattern: /^\/vault\/plain\/described$/,
      handle: async (r) =>
        decide(r, (o) => {
          const kept = secrets.describedPlain(r.viewer.workspace, locked(r), r.viewer.email, o);
          if (typeof kept === "string") return kept;
          events?.tell("vault-plain", shown(kept), `vault-plain\0${kept.id}`, { workspace: kept.ws, email: kept.owner });
          return null;
        }),
    },
    {
      // A request to delete an item of the plain library, approved by its owner: deleted here (security mode on or not:
      // only deletions are written to it once it is on).
      method: "POST",
      pattern: /^\/vault\/plain\/removed$/,
      handle: async (r) =>
        decide(r, (o) => {
          const kept = secrets.removedPlain(r.viewer.workspace, r.viewer.email, o);
          if (typeof kept === "string") return kept;
          events?.tell("vault-plain", shown(kept), `vault-plain\0${kept.id}`, { workspace: kept.ws, email: kept.owner });
          return null;
        }),
    },
    {
      // A secret an agent asked to keep, approved by whoever it is for: written into their plain library here.
      method: "POST",
      pattern: /^\/vault\/plain\/saves$/,
      handle: async (r) =>
        decide(r, (o) => {
          const kept = secrets.savedPlain(r.viewer.workspace, locked(r), r.viewer.email, o);
          if (typeof kept === "string") return kept;
          events?.tell("vault-plain", shown(kept), `vault-plain\0${kept.id}`, { workspace: kept.ws, email: kept.owner });
          return null;
        }),
    },
  ];
};

// The vaults this station holds (docs/vault.md): GET/PUT vault/vaults, GET/PUT vault/items, GET/PUT vault/boxes. Only
// where the station pinned its workspace's lock (`vault_needs_lock` otherwise): the lock is what says which devices sign
// and whose they are, without it the control plane could add a device of its own and be given the keys. A member sees
// the vaults they are a member of and those vaults' items; each write is checked against the lock and the version it
// follows (vault/crypto.ts), and told to the members' streams as it is kept (`vault`, `vault-item`, `vault-box`; a
// member taken out of a vault is told `vault-gone`; a vault deleted is kept as its last version, `deleted`, its items
// gone). A vault is written on one station (its host) and copied to the
// others by its members' devices (`?copy=1`: a later version than the one held, not necessarily the next; one not later
// is answered with the one held, unchanged), so that agents on any station may ask for its secrets.
import type { LockState } from "../../cloud/lock.ts";
import type { Viewer } from "../../mesh/credential.ts";
import { type BoxCert, type Item, type Vault, certOk, itemOk, vaultOk } from "../../vault/crypto.ts";
import type { VaultStore } from "../../vault/store.ts";
import type { Route } from "../admin.ts";
import type { Events, To } from "../events.ts";
import { type Answer, type Request, json, param } from "../request.ts";

export type VaultDeps = {
  vaults: VaultStore;
  /// The lock pinned in a workspace this station is in; null when none is (or it is broken: nobody is admitted then).
  lock(workspace: string): LockState | null;
  events?: Events;
  /// A device's box certificate taken (a newer one than held): the secrets agents asked to keep for its person are
  /// sealed to it too (vault/secrets.ts `boxed`).
  boxed?(lock: LockState, cert: BoxCert): void;
};

/// A refusal with its code, which the core says as it is.
const refuse = (status: number, code: string, error: string, more: Record<string, unknown> = {}): Answer => json(status, JSON.stringify({ error, code, ...more }));

const NEEDS_LOCK = () => refuse(409, "vault_needs_lock", "the vault needs the workspace's security mode (its lock) pinned on this station");

function body(r: Request): unknown {
  try {
    return JSON.parse(r.body.toString("utf8"));
  } catch {
    return undefined;
  }
}

const sees = (vault: Vault, viewer: Viewer) => vault.ws === viewer.workspace && vault.members.includes(viewer.sub);
/// Whom a vault's changes are told to: its members.
const members = (vault: Vault): To => ({ workspace: vault.ws, subs: vault.members });

export const routes = ({ vaults, lock, events, boxed }: VaultDeps): Route[] => {
  /// The lock of the viewer's workspace, or the refusal.
  const locked = (r: Request): LockState | Answer => lock(r.viewer.workspace) ?? NEEDS_LOCK();
  const isAnswer = (v: LockState | Answer): v is Answer => "status" in v;
  const tell = (event: string, data: unknown, of: string, to: To) => events?.tell(event, data, of, to);
  return [
    {
      method: "GET",
      pattern: /^\/vault\/vaults$/,
      handle: async (r) => {
        const l = locked(r);
        if (isAnswer(l)) return l;
        return json(200, JSON.stringify({ vaults: vaults.vaults(l.ws).filter((v) => sees(v, r.viewer)) }));
      },
    },
    {
      method: "PUT",
      pattern: /^\/vault\/vaults$/,
      handle: async (r) => {
        const l = locked(r);
        if (isAnswer(l)) return l;
        const next = body(r) as Vault;
        if (next === null || typeof next !== "object" || typeof next.id !== "string") return refuse(400, "vault_invalid", "a vault, as JSON");
        if (next.ws !== r.viewer.workspace) return refuse(400, "vault_invalid", "a vault of another workspace");
        const prev = vaults.vault(l.ws, next.id);
        const copy = param(r, "copy") === "1";
        // A copy no later than the one held: nothing to change (it never goes back).
        if (copy && prev !== null && Number.isSafeInteger(next.seq) && next.seq <= prev.seq) return json(200, JSON.stringify({ vault: prev }));
        // Not the version that follows the one held: the device writes on what it was told (it is sent along).
        if (!copy && Number.isSafeInteger(next.seq) && next.seq !== (prev === null ? 0 : prev.seq + 1)) {
          return refuse(409, "vault_conflict", `seq ${prev === null ? 0 : prev.seq + 1} is the one that follows`, { vault: prev });
        }
        const why = vaultOk(l, prev, next, copy);
        if (why !== null) return refuse(400, "vault_invalid", why);
        vaults.putVault(next);
        tell("vault", next, `vault\0${next.id}`, members(next));
        const gone = (prev?.members ?? []).filter((m) => !next.members.includes(m));
        if (gone.length > 0) tell("vault-gone", { id: next.id }, `vault-gone\0${next.id}`, { workspace: next.ws, subs: gone });
        return json(200, JSON.stringify({ vault: next }));
      },
    },
    {
      method: "GET",
      pattern: /^\/vault\/items$/,
      handle: async (r) => {
        const l = locked(r);
        if (isAnswer(l)) return l;
        // One vault's (`vault=`), or those of every vault the member is in.
        const of = param(r, "vault");
        const seen = vaults.vaults(l.ws).filter((v) => sees(v, r.viewer) && (of === undefined || v.id === of));
        if (of !== undefined && seen.length === 0) return refuse(404, "vault_unknown", "no such vault here, or not one of yours");
        return json(200, JSON.stringify({ items: seen.flatMap((v) => vaults.items(l.ws, v.id)) }));
      },
    },
    {
      method: "PUT",
      pattern: /^\/vault\/items$/,
      handle: async (r) => {
        const l = locked(r);
        if (isAnswer(l)) return l;
        const next = body(r) as Item;
        if (next === null || typeof next !== "object" || typeof next.vault !== "string" || typeof next.id !== "string") return refuse(400, "vault_invalid", "an item, as JSON");
        const vault = vaults.vault(l.ws, next.vault);
        if (vault === null || !sees(vault, r.viewer)) return refuse(404, "vault_unknown", "no such vault here, or not one of yours");
        if (vault.deleted) return refuse(404, "vault_unknown", "that vault was deleted");
        const prev = vaults.item(l.ws, vault.id, next.id);
        const copy = param(r, "copy") === "1";
        if (copy && prev !== null && Number.isSafeInteger(next.version) && next.version <= prev.version) return json(200, JSON.stringify({ item: prev }));
        if (!copy && Number.isSafeInteger(next.version) && next.version !== (prev === null ? 0 : prev.version + 1)) {
          return refuse(409, "vault_conflict", `version ${prev === null ? 0 : prev.version + 1} is the one that follows`, { item: prev });
        }
        const why = itemOk(l, vault, prev, next, copy);
        if (why !== null) return refuse(400, "vault_invalid", why);
        vaults.putItem(next);
        tell("vault-item", next, `vault-item\0${vault.id}\0${next.id}`, members(vault));
        return json(200, JSON.stringify({ item: next }));
      },
    },
    {
      method: "GET",
      pattern: /^\/vault\/boxes$/,
      handle: async (r) => {
        const l = locked(r);
        if (isAnswer(l)) return l;
        // Only those of devices still in the lock.
        return json(200, JSON.stringify({ boxes: vaults.boxes(l.ws).filter((c) => certOk(l, c) === null) }));
      },
    },
    {
      method: "PUT",
      pattern: /^\/vault\/boxes$/,
      handle: async (r) => {
        const l = locked(r);
        if (isAnswer(l)) return l;
        const cert = body(r) as BoxCert;
        const why = certOk(l, cert);
        if (why !== null) return refuse(400, "vault_invalid", why);
        const had = vaults.box(l.ws, cert.device);
        // An older one than held changes nothing.
        if (had !== null && had.at > cert.at) return json(200, JSON.stringify({ box: had }));
        vaults.putBox(cert);
        tell("vault-box", cert, `vault-box\0${cert.device}`, { workspace: cert.ws });
        boxed?.(l, cert);
        return json(200, JSON.stringify({ box: cert }));
      },
    },
  ];
};

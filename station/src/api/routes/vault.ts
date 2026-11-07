// The vaults this station holds: GET/PUT vault/vaults, GET/PUT vault/items, GET/PUT vault/boxes. Only
// where the station pinned its workspace's lock (`vault_needs_lock` otherwise): the lock is what says which devices sign
// and whose they are, without it the control plane could add a device of its own and be given the keys. A member sees
// the vaults they are a member of and those vaults' items; each write is checked against the lock and the version it
// follows (vault/crypto.ts), and told to the members' streams as it is kept (`vault`, `vault-item`, `vault-box`; a
// member taken out of a vault is told `vault-gone`; a vault deleted is kept as its last version, `deleted`, its items
// gone). A vault is written on one station (its host) and copied to the
// others by its members' devices (`?copy=1`: a later version than the one held, not necessarily the next; one not later
// is answered with the one held, unchanged), so that agents on any station may ask for its secrets.
import { type LockState, admit } from "../../cloud/lock.ts";
import type { Viewer } from "../../mesh/credential.ts";
import { type BoxCert, type Item, type Vault, TAG, certOk, itemOk, itemSupersedes, signedOk, signerOf, vaultOk, vaultSupersedes } from "../../vault/crypto.ts";
import { isDeletedVaultWrite, type VaultStore } from "../../vault/store.ts";
import type { Route } from "../admin.ts";
import type { Events, To } from "../events.ts";
import { type Answer, type Request, json, param } from "../request.ts";

export type VaultDeps = {
  vaults: VaultStore;
  /// The lock pinned in a workspace this station is in; null when none is (or it is broken: nobody is admitted then).
  lock(workspace: string): LockState | null;
  events?: Events;
  /// Wait for an older station's writes to stop; undefined means the handover is already complete.
  beforeWrite?(): false | Promise<boolean> | undefined;
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

/// The lock device the request comes from, as a connection is admitted (cloud/lock.ts `admit`); null for none. (No
/// clock: only an app device has a box, and an app's approval does not run out.)
function deviceOf(lock: LockState, r: Request): string | null {
  const v = r.viewer;
  try {
    return admit(lock, { sub: v.sub, endpoint: v.device, base: v.lockDevice?.base, proof: v.lockDevice?.proof }, 0).device.id;
  } catch {
    return null;
  }
}

const sees = (vault: Vault, viewer: Viewer) => vault.ws === viewer.workspace && vault.members.includes(viewer.sub);
/// Whom a vault's changes are told to: its members.
const members = (vault: Vault): To => ({ workspace: vault.ws, subs: vault.members });

export const routes = ({ vaults, lock, events, boxed, beforeWrite }: VaultDeps): Route[] => {
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
      // The latest versions of vaults the viewer was a member of, each shown by a version naming them that its owner's
      // device signed (`held`): how a device taken out of a vault (or one that was away as it was) knows it was, rather
      // than taking a station's not listing it for it. Nothing for one the viewer was never shown.
      method: "POST",
      pattern: /^\/vault\/vaults\/latest$/,
      handle: async (r) => {
        const l = locked(r);
        if (isAnswer(l)) return l;
        const held = (body(r) as { held?: unknown } | null)?.held;
        if (!Array.isArray(held) || held.length > 256) return refuse(400, "vault_invalid", "held is a list of vault versions");
        const latest: Vault[] = [];
        for (const h of held as Vault[]) {
          if (h === null || typeof h !== "object" || typeof h.id !== "string" || h.ws !== r.viewer.workspace || !Array.isArray(h.members) || !h.members.includes(r.viewer.sub)) continue;
          if (!signedOk(h, TAG.vault) || signerOf(l, h.sig.key)?.sub !== h.owner) continue;
          const v = vaults.vault(l.ws, h.id);
          if (v !== null && v.owner === h.owner) latest.push(v);
        }
        return json(200, JSON.stringify({ vaults: latest }));
      },
    },
    {
      method: "PUT",
      pattern: /^\/vault\/vaults$/,
      handle: async (r) => {
        const waiting = beforeWrite?.();
        if (waiting === false || (waiting !== undefined && (!await waiting || beforeWrite?.() === false))) return refuse(503, "vault_handover", "the previous station has not finished handing over");
        const l = locked(r);
        if (isAnswer(l)) return l;
        const next = body(r) as Vault;
        if (next === null || typeof next !== "object" || typeof next.id !== "string") return refuse(400, "vault_invalid", "a vault, as JSON");
        if (next.ws !== r.viewer.workspace) return refuse(400, "vault_invalid", "a vault of another workspace");
        const copy = param(r, "copy") === "1";
        for (let attempt = 0; attempt < 3; attempt++) {
          const held = vaults.vaultSnapshot(l.ws, next.id), prev = held?.value ?? null;
          if (attempt > 0 && prev !== null && !sees(prev, r.viewer)) return refuse(404, "vault_unknown", "no such vault here, or not one of yours");
          // A copy of a sibling is kept only if every station chooses it over the one currently held.
          let sibling = false;
          if (copy && prev !== null && Number.isSafeInteger(next.seq) && next.seq <= prev.seq) {
            if (next.seq < prev.seq || !vaultSupersedes(next, prev)) return json(200, JSON.stringify({ vault: prev }));
            sibling = true;
          }
          if (!copy && Number.isSafeInteger(next.seq) && next.seq !== (prev === null ? 0 : prev.seq + 1)) {
            return refuse(409, "vault_conflict", `seq ${prev === null ? 0 : prev.seq + 1} is the one that follows`, { vault: prev });
          }
          const why = sibling ? vaultOk(l, null, next, true) ?? (next.owner !== prev!.owner ? "a vault's owner does not change" : null) : vaultOk(l, prev, next, copy);
          if (why !== null) return refuse(400, "vault_invalid", why);
          try {
            if (!vaults.putVaultIf(next, held?.body ?? null)) continue;
          } catch (error) {
            if (!isDeletedVaultWrite(error)) throw error;
            continue;
          }
          tell("vault", next, `vault\0${next.id}`, members(next));
          const gone = (prev?.members ?? []).filter((m) => !next.members.includes(m));
          if (gone.length > 0) tell("vault-gone", { id: next.id, vault: next }, `vault-gone\0${next.id}`, { workspace: next.ws, subs: gone });
          return json(200, JSON.stringify({ vault: next }));
        }
        const current = vaults.vault(l.ws, next.id);
        if (current === null || !sees(current, r.viewer)) return refuse(404, "vault_unknown", "no such vault here, or not one of yours");
        return refuse(409, "vault_conflict", "the vault changed while it was being written", { vault: current });
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
        const candidates = of === undefined ? vaults.vaults(l.ws) : [vaults.vault(l.ws, of)].filter((v): v is Vault => v !== null);
        const seen = candidates.filter((v) => sees(v, r.viewer) && (of === undefined || v.id === of));
        if (of !== undefined && seen.length === 0) return refuse(404, "vault_unknown", "no such vault here, or not one of yours");
        return json(200, JSON.stringify({ items: seen.flatMap((v) => vaults.items(l.ws, v.id)) }));
      },
    },
    {
      method: "PUT",
      pattern: /^\/vault\/items$/,
      handle: async (r) => {
        const waiting = beforeWrite?.();
        if (waiting === false || (waiting !== undefined && (!await waiting || beforeWrite?.() === false))) return refuse(503, "vault_handover", "the previous station has not finished handing over");
        const l = locked(r);
        if (isAnswer(l)) return l;
        const next = body(r) as Item;
        if (next === null || typeof next !== "object" || typeof next.vault !== "string" || typeof next.id !== "string") return refuse(400, "vault_invalid", "an item, as JSON");
        const copy = param(r, "copy") === "1";
        for (let attempt = 0; attempt < 3; attempt++) {
          const heldVault = vaults.vaultSnapshot(l.ws, next.vault), vault = heldVault?.value ?? null;
          if (vault === null || !sees(vault, r.viewer)) return refuse(404, "vault_unknown", "no such vault here, or not one of yours");
          if (vault.deleted) return refuse(404, "vault_unknown", "that vault was deleted");
          const held = vaults.itemSnapshot(l.ws, vault.id, next.id), prev = held?.value ?? null;
          let sibling = false;
          if (copy && prev !== null && Number.isSafeInteger(next.version) && next.version <= prev.version) {
            if (next.version < prev.version || !itemSupersedes(next, prev)) return json(200, JSON.stringify({ item: prev }));
            sibling = true;
          }
          if (!copy && Number.isSafeInteger(next.version) && next.version !== (prev === null ? 0 : prev.version + 1)) {
            return refuse(409, "vault_conflict", `version ${prev === null ? 0 : prev.version + 1} is the one that follows`, { item: prev });
          }
          const why = itemOk(l, vault, sibling ? null : prev, next, copy);
          if (why !== null) return refuse(400, "vault_invalid", why);
          try {
            if (!vaults.putItemIf(next, heldVault!.body, held?.body ?? null)) continue;
          } catch (error) {
            if (!isDeletedVaultWrite(error)) throw error;
            continue;
          }
          tell("vault-item", next, `vault-item\0${vault.id}\0${next.id}`, members(vault));
          return json(200, JSON.stringify({ item: next }));
        }
        return refuse(409, "vault_conflict", "the vault or item changed while it was being written");
      },
    },
    {
      method: "GET",
      pattern: /^\/vault\/boxes$/,
      handle: async (r) => {
        const l = locked(r);
        if (isAnswer(l)) return l;
        // Only those of devices still in the lock.
        // A small lock can address its devices by the existing primary key, leaving removed devices' certificates
        // unread. For a larger lock the certificate table may be smaller than the device list, so scan it as before.
        const boxes = l.devices.size <= 32 ? vaults.boxesFor(l.ws, [...l.devices.keys()]) : vaults.boxes(l.ws);
        return json(200, JSON.stringify({ boxes: boxes.filter((c) => certOk(l, c) === null) }));
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
        // Published by the device itself, as the lock admits it: a signing key alone (an admin's, who put a device in
        // under someone's name) does not publish a box that the person's secrets would be sealed to.
        if (deviceOf(l, r) !== cert.device) return refuse(403, "vault_not_device", "a device publishes its own box certificate");
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

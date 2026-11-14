// Which rigs a workspace in security mode has (a station that only runs tasks, 2026-11-10). There the control plane's word that a machine is
// one of the workspace's rigs counts for nothing (it could name its own machine, to be sent the workspace's code and
// secrets as tasks): a rig is taken once its person, who compared its code, signed for it (rig-form.ts `AddBody`),
// with a key the workspace's lock knows as that member's own: a device of theirs that signs in the lock, or a device
// on their own lock where they are bound to it. No entry of the workspace's lock says it, so a station or an app from
// before rigs reads the lock as it did. The rig keeps what was signed and shows it to a station that asks
// (`rig.proof`); each station checks it against the lock it pinned.
import type { DatabaseSync } from "node:sqlite";
import { type AddBody, type Signed, wellFormed } from "../../../client/core-ts/src/rig-form.ts";
import { type Entry, type LockState, entryHash, personFold, rank, signer, stateWord } from "../cloud/lock.ts";
import type { Cloud, Rig } from "../cloud/state.ts";
import { signatureHolds } from "../rig/grants.ts";

const SCHEMA = `CREATE TABLE IF NOT EXISTS rig_adds (
  ws TEXT NOT NULL,
  rig TEXT NOT NULL,
  body TEXT NOT NULL,
  PRIMARY KEY (ws, rig)
);`;

/// Why what was signed does not take `rig` into the workspace whose lock is `lock`, or null. `personKeys`: the keys on
/// a person's own lock, by its genesis, as this station has heard it.
export function addRefusal(signed: unknown, ws: string, rig: Rig, lock: LockState, personKeys: (genesis: string, sub: string) => Set<string>, now: number): string | null {
  if (!wellFormed("add", signed)) return "not a rig's add";
  const s = signed as Signed<AddBody>;
  if (s.body.ws !== ws || s.body.rig !== rig.id) return "signed for another rig or workspace";
  if (s.body.sub !== rig.owner) return "not signed by the person this rig is said to be of";
  const member = lock.members.get(s.body.sub);
  if (member === undefined || rank(member.role) < rank("member")) return "its person is no member who adds rigs here";
  const by = signer(lock, { key: s.sig.key }, now);
  const own = by !== null && by.sub === s.body.sub && by.own && !by.passkey;
  const bound = lock.persons.get(s.body.sub);
  if (!own && !(bound !== undefined && personKeys(bound, s.body.sub).has(s.sig.key))) return "signed by a key the workspace's lock does not know as that member's own";
  return signatureHolds("add", s) ? null : "the signature does not hold";
}

export class RigAdds {
  readonly #db: DatabaseSync;
  readonly #cloud: Cloud;
  readonly #chain: (genesis: string) => unknown[] | null;
  readonly #now: () => number;
  /// What was last made of each one kept, by the lock it was checked against (its head).
  readonly #checked = new Map<string, { head: string; holds: boolean }>();

  /// `chain`: a person's own lock as this station has heard it, by its genesis (mesh/person-chains.ts). `now`: seconds.
  constructor(o: { db: DatabaseSync; cloud: Cloud; chain: (genesis: string) => unknown[] | null; now: () => number }) {
    this.#db = o.db;
    this.#cloud = o.cloud;
    this.#chain = o.chain;
    this.#now = o.now;
    this.#db.exec(SCHEMA);
  }

  #keys(genesis: string, sub: string): Set<string> {
    const chain = this.#chain(genesis);
    if (chain === null) return new Set();
    try {
      return new Set(personFold(chain, sub).devices.map((d) => d.key));
    } catch {
      return new Set();
    }
  }

  get(ws: string, rig: string): Signed<AddBody> | null {
    const row = this.#db.prepare("SELECT body FROM rig_adds WHERE ws = ? AND rig = ?").get(ws, rig) as { body: string } | undefined;
    if (row === undefined) return null;
    try {
      return JSON.parse(row.body);
    } catch {
      return null;
    }
  }

  /// Why `signed` is not taken for `rig` in `ws` now, or null: kept, the rig one of the workspace's from now on.
  take(ws: string, rig: Rig, signed: unknown): string | null {
    const lock = this.#cloud.locked(ws === this.#cloud.home() ? null : ws)?.state ?? null;
    if (lock === null) return "this workspace is not in security mode here: its rigs are the control plane's to say";
    const why = addRefusal(signed, ws, rig, lock, (genesis, sub) => this.#keys(genesis, sub), this.#now());
    if (why !== null) return why;
    this.#db.prepare("INSERT INTO rig_adds (ws, rig, body) VALUES (?, ?, ?) ON CONFLICT (ws, rig) DO UPDATE SET body = excluded.body").run(ws, rig.id, JSON.stringify(signed));
    this.#checked.delete(`${ws}\0${rig.id}`);
    this.#cloud.rigsChanged?.();
    return null;
  }

  /// Whether `rig` is one of `ws`'s by what its person signed, as the lock stands now (a member taken out of the lock,
  /// or their device, takes their rigs with them).
  holds(ws: string, rig: Rig): boolean {
    const lock = this.#cloud.locked(ws === this.#cloud.home() ? null : ws)?.state ?? null;
    if (lock === null) return false;
    // (a station the lock's owners signed in, made one that only runs tasks since: the workspace's as it was)
    if (lock.stations.has(rig.id)) return true;
    const key = `${ws}\0${rig.id}`;
    const was = this.#checked.get(key);
    // (a person's own lock moving on is heard as the workspace's does: bound there, its head is what admits them; a state
    // in force where the chain moved says its word, cloud/lock.ts `stateWord`)
    // (its head's hash: the chain gone by moves to another branch of the same length too, cloud/log-keep.ts)
    const own = lock.persons.get(rig.owner) === undefined ? null : this.#chain(lock.persons.get(rig.owner)!);
    const head = `${stateWord(lock)}\0${rig.owner}\0${own === null || own.length === 0 ? "" : `${own.length}:${entryHash(own.at(-1) as Entry)}`}`;
    if (was !== undefined && was.head === head) return was.holds;
    const signed = this.get(ws, rig.id);
    const holds = signed !== null && addRefusal(signed, ws, rig, lock, (genesis, sub) => this.#keys(genesis, sub), this.#now()) === null;
    this.#checked.set(key, { head, holds });
    return holds;
  }
}

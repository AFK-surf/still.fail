// What this device signed in a lock (a workspace's, or a person's own) that no station took and none refused by the
// end of the call's wait: pending. Kept on the device beside the lock held, never on its chain, and brought to the
// lock's stations as one of them is next read, oldest first (views/lock.ts `deliver`, personal-lock.ts `#deliver`).
// The cloud's taking one never counts (the root AGENTS.md, The cloud is the account system): only a station's does.
// Pure: what each lock keeps, where, and who is told is the caller's.
import type { Entry } from "./lock.ts";
import { canonical } from "./lock.ts";
import { CoreError } from "./error.ts";
import { t } from "./i18n.ts";

/// The most entries a lock keeps waiting for its stations here: past it a person's call is refused with a sentence
/// (`pastBound`), a background signer's entry is not signed (it is tried again as the lock is next read). As many
/// failed ones are kept, the oldest going past that. A person who made eight changes with none of their stations up
/// waits for one before the ninth: what they did is all still to take effect, and every one more is one more for the
/// stations to refuse once another device changed the lock meanwhile.
export const PENDING_MOST = 8;

/// How long a write to still.fail cloud of a workspace's roster (a member added, taken out or given a role, a station
/// taken out or enrolled) is waited on before the call fails saying the server did not answer and nothing was saved:
/// the shell's client bounds only the connecting (15 s), and a cloud that took the request and never answered held the
/// person's button for good (test/answer-timing.test.ts, 2026-11-12). As long as the lock waits for its stations to take
/// an entry (views/lock.ts TAKEN_MS), the longest of its waits: a write that takes the cloud longer than a station takes
/// to answer is not one to wait on; ASKED_MS (3 s) would fail writes a slow line makes in five. So does what a lock
/// gives the cloud to keep where it names no station (views/lock.ts `#cloudOnly`, `deliver`; personal-lock.ts the
/// same): a call fails then with `cloudSilent`, nothing kept; brought in the background, it is left pending, brought
/// again as the cloud is next heard from.
export const CLOUD_WRITE_MS = 15_000;

/// The cloud did not answer a write a person waits on by CLOUD_WRITE_MS: nothing saved, try again.
export const cloudSilent = (): CoreError => new CoreError("cloud_silent", t("core-misc.lock.pending.cloudSilent"));

/// What a pending entry does, in words (`core-misc.lock.pending.act.*`); null: the core's own, which no one asked for
/// (a person's lock bound, their devices kept to it, an entry of this device's signed again): kept and brought, not
/// shown.
export type Act = "removeDevice" | "renew" | "approve" | "addMember" | "setRole" | "removeMember" | "protectStation" | "removeStation" | "disable";

/// One pending entry. `id`: the hash of the entry as first signed, the same while it is signed again (`entry` the one
/// brought now). `name`: what it is about, as the person knows it then; `role` a role given, in words. `at` when it was
/// signed first (ms). `state`: `waiting` for a station, or `failed`: `what` was changed meanwhile by another device
/// (`core-misc.lock.pending.failed`), or `why` says what else refused it. `tries`: signings again of it. `sent`: the
/// cloud was sent it as it was signed (a station that pins what the lock says of it from the cloud alone).
export type Pending = {
  id: string;
  entry: Entry;
  act: Act | null;
  name: string;
  role?: string;
  at: number;
  state: "waiting" | "failed";
  what?: string;
  why?: string;
  tries?: number;
  sent?: boolean;
};

/// What a lock's topic says of one (the page draws it): its sentence (`text`, made here), its state, the stations it
/// waits for by name, and, failed for another reason than a change meanwhile, why (`why`).
export type PendingRow = { id: string; text: string; state: "waiting" | "failed"; stations: string[]; why?: string; dismissText?: string };

/// The stations an entry waits for, in words: at most three by name, then how many in all.
export function stationsText(names: readonly string[]): string {
  const sep = t("core-misc.lock.listSep");
  if (names.length <= 3) return names.join(sep);
  return t("core-misc.lock.pending.stationsMore", { names: names.slice(0, 3).join(sep), n: names.length });
}

/// What it does, in words.
export function actText(p: Pick<Pending, "act" | "name" | "role">): string {
  if (p.act === null) return "";
  return t(`core-misc.lock.pending.act.${p.act}`, { name: p.name, role: p.role ?? "" });
}

/// Its row in a lock's topic, `stations` the names of the lock's stations it waits for.
export function pendingRow(p: Pending, stations: readonly string[]): PendingRow {
  const action = actText(p);
  if (p.state === "waiting") return { id: p.id, text: t("core-misc.lock.pending.waiting", { action, stations: stationsText(stations) }), state: "waiting", stations: stations.slice(0, 3) };
  const dismissText = t("core-misc.lock.pending.dismiss");
  if (p.why !== undefined) return { id: p.id, text: action, state: "failed", stations: [], why: p.why, dismissText };
  return { id: p.id, text: t("core-misc.lock.pending.failed", { action, what: p.what ?? p.name }), state: "failed", stations: [], dismissText };
}

/// Whether signing `kind` with `body` would only say again what a waiting one says: the same kind and body (a web
/// page's renewal by its device, whatever its new end).
export function repeats(p: Pending, kind: string, body: unknown): boolean {
  if (p.state !== "waiting" || p.entry.kind !== kind) return false;
  const plain = (b: unknown) => {
    if (typeof b !== "object" || b === null || Array.isArray(b)) return canonical(b ?? null);
    const { exp: _exp, ...rest } = b as Record<string, unknown>;
    return canonical(rest);
  };
  return plain(p.entry.body) === plain(body);
}

/// A lock topic's fields of what is pending (`pending`, and `pendingText` its heading while there are any).
export function pendingFields(rows: PendingRow[]): { pending: PendingRow[]; pendingText?: string } {
  return rows.length === 0 ? { pending: rows } : { pending: rows, pendingText: t("core-misc.lock.pending.header") };
}

/// The sentence past the bound: wait for those stations.
export const pastBound = (stations: readonly string[]): string => t("core-misc.lock.pending.past", { stations: stationsText(stations) });

/// `items` kept to the bound: every waiting one, and the latest PENDING_MOST failed ones.
export function bounded(items: readonly Pending[]): Pending[] {
  const failed = items.filter((p) => p.state === "failed");
  const drop = new Set(failed.slice(0, Math.max(0, failed.length - PENDING_MOST)).map((p) => p.id));
  return drop.size === 0 ? [...items] : items.filter((p) => !drop.has(p.id));
}

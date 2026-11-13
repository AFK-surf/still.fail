// The vault on this device: the vaults and items a workspace's stations hold, kept here as they do
// (only ciphertext and signatures), what the pages show of them, and what a person does with them. Keys live in the
// system's secure storage (Host `secureGet`…: an app's; a web page has none and is refused); a vault's key, once
// unsealed, is kept in memory UNLOCK_MS. Nothing a station or the cloud says is trusted for a key: a vault's version
// counts once its owner's device signed it and a box key once its device did, both checked against the workspace's
// lock, itself checked entry by entry here (vault/lock-check.ts).
//
// Every station of the workspace keeps a copy of each vault (its ciphertext and signatures), so that an agent on any of
// them may ask for its secrets: a vault is written on the station it was made on (`at`, its host), and the latest
// version held anywhere is brought to each station that lacks it (`spread`, `?copy=1`), as it is read or written here.
//
// Topics:
//   vaults {workspace}            the vaults this person is in, whether this device is set up, requests to approve
//   vaultItems {workspace, vault} a vault's items: names once it is unlocked (the listed ones' always)
//   vaultUses {workspace, vault, item}  an item's uses by agents (the requests decided), the latest first
//   (`lockPrompts` `asks`, views/lock.ts: members' devices set up that wait on this one for a vault's key, every
//   workspace's, wherever the person is: `vault.addDevice {vault, device}` gives it, `vault.hidePrompt` puts one away
//   until that device asks again; `vaultAsks` here)
//
// Without security mode the library is plain ( 不加锁的库): each station keeps the person's items as they
// are (`vault/plain`), shown as one vault, `plain`; the calls below take it as they take a vault, with nothing to
// encrypt, sign or ask the person for. Security mode on, what is left of it is moved into their vault (`migrate`).
// Calls (vault.<name> {workspace, …}):
//   setup                         this device's box key (made once), its certificate published; the recovery words
//                                 the first time (`{words}`, shown once: never kept); one's own vault made when one
//                                 has none (`{made}`)
//   create {name, station?}       a vault of one's own, keyed for each of one's devices set up
//   delete {vault}                a vault of one's own deleted, its items with it (the person asked when it holds any)
//   addDevice {vault, device?}    the vault's key sealed for members' devices set up since (its owner signs; done by
//                                 itself too whenever the owner's device unseals it, and as their certificates come
//                                 while it is unsealed here)
//   ask                           this device's certificate published anew (set up already): the owner's devices
//                                 prompted for its key (`lockPrompts` `asks`), or given it at once where one holds it
//   hidePrompt {device, at?}      that device's prompt put away (the one shown, its certificate's `at`), until it
//                                 asks again
//   prompts                       the devices waiting on this one for a key (`lockPrompts` `asks`), as a call
//   putItem {vault, id?, plain, listing?}  an item written (a new one without `id`)
//   deleteItem {vault, item}      an item deleted
//   open {item}                   an item's plaintext (asks the person, unless its vault is unlocked)
//   recover {words}               this device keyed into one's vaults by the recovery words
//   approve {request, scope, typed?}  an agent's request granted: the item sealed to it, signed; a request to keep a
//                                 secret (secret_save) approved: written into one's vault (`scope` unused); one the
//                                 person types in, with what they typed (`typed: {secret, username?}`, an object: never
//                                 kept among what is `doing`)
//   setLasts {vault, lasts}       the longest grant of the vault's items that say none (its owner signs; the plain
//                                 library's told to each station keeping it)
//   deny {request}                turned down, signed
//   migrate                       the plain library's items moved into one's own vault, encrypted (security mode on)
//   lock                          the unlocked keys forgotten now
//   state                         the `vaults` topic's value, as a call
import { Effect, Schedule, Semaphore } from "effect";
import type { Inner } from "../core.ts";
import { ulid } from "../accounts.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import type { Owner } from "../core/routing.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { type Entry, Signer } from "../lock.ts";
import { OTHERS_MS, answersOf, askPerson, tookOrRefused, deviceText, held as lockHeld, inForceOf, lockSeen, movedHere, nameOf as workspaceName, signerOf, stateOf } from "./lock.ts";
import { workspaceIds } from "./marks.ts";
import type { Topic } from "../protocol.ts";
import { StationAddr } from "../station/addr.ts";
import { Priority } from "../sync/scheduler.ts";
import type { SpanContext } from "../trace.ts";
import { get, isObject, utf8 } from "../util.ts";
import {
  type BoxCert, type Deny, type Grant, type Item, type Listing, type Plain, type Request, type Save, type Scope, type Vault,
  SCOPES, TAG, allows, boxPublic, decrypt, encryptWith, fromWords, grantContext, itemContext, keyContext, openSeal, recoveryPair, saveContext, rulesCrypto, sealWith, sign, toWords,
} from "../vault/crypto.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../../rules/js/rules.js";
import { type Checked, checkLock } from "../vault/lock-check.ts";
import { ofAddress } from "../workspace.ts";
import { stamp } from "../present.ts";
import type { VaultOutcome } from "./local.ts";
import { aboutText, describeText, fileBytes, howText, itemWords, kindText, modeText, shownFields, statusWords } from "../vault-words.ts";
import { timed } from "../spent.ts";

// deno-lint-ignore no-explicit-any
type J = any;
type Of = Extract<Call, { kind: "vault" }>;

/// How long a vault's key stays unsealed in memory after it was last unsealed.
export const UNLOCK_MS = 5 * 60_000;
/// How long a write by the owner's device waits for its vault to be keyed anew first (`#writable`).
const REKEY_WAIT_MS = 1_500;
/// The secure storage's box key (X25519, asks the person to be read), and its public half where the app keeps the
/// rest (no asking needed to know it).
export const BOX_KEY = "vault-box";
export const BOX_PUB = "vault-box-pub";
/// How long a grant lasts: one use or an hour; a chat's until the chat is archived, which the station ends it at (30
/// days at most).
const GRANT_SECS: Record<Scope, number> = { once: 3600, hour: 3600, chat: 30 * 86400 };

/// What the workspace's stations hold, as held here (the `vault` record of the workspace): the vaults by id and the
/// station each is on, the box certificates by device, the requests waiting and the station each came from, and the
/// stations that hold no vault (a code: `vault_needs_lock`, `http_404` for one from before).
type Held = {
  vaults: Record<string, Vault>; at: Record<string, string>; boxes: Record<string, BoxCert>; requests: Record<string, Request>; asked: Record<string, string>; refused: Record<string, string>;
  /// What each station holds of each vault (by vault, then station): its version and its items' (by id); the stations
  /// that answered what vaults they hold (those a copy may be brought to).
  on: Record<string, Record<string, Holding>>; keeps: string[];
  /// The plain library's items by id (without their fields) and the station each is on; the stations that keep one;
  /// the longest grant of its items that say none, as said last on any of them.
  plain: Record<string, PlainRow>; plainOn: string[]; plainLasts?: { lasts: Scope; at: number };
  /// The uses of each vault's items (`<station>/<vault>`), as the station keeping it said them, the latest first.
  uses: Record<string, Use[]>;
  /// The devices whose prompt for a key was put away here (`vault.hidePrompt`), by device: the certificate's `at` it
  /// was put away at (one published since, asking again, is shown).
  hidden: Record<string, number>;
  /// A later version of a vault a station told than the one held, that the lock as held here does not take yet, by
  /// vault: this device's lock behind the station's (a device let in again, given the key in the version written for it
  /// before it heard it was in the lock). Taken as the lock comes (`vaultCome`); nothing else would tell it again.
  later?: Record<string, Vault>;
  /// The last version held of a vault under each earlier key, by vault, then by epoch: what unseals an earlier key for
  /// this device (its `keys`), and what the lock took then, while items written under that key are left to be written
  /// again under the vault's (`carryOn`: a keying anew stopped half-way). Let go once nothing sits under it
  /// (`settleBefore`).
  before?: Record<string, Record<string, Vault>>;
};

/// A vault's version a station holds, and its items' versions; the signatures of those (`sig`, `sigs`): which of two of
/// one number it holds (written on two stations at once), so the one every station keeps is brought where it is not.
type Holding = { seq: number; items: Record<string, number>; sig?: string; sigs?: Record<string, string> };

/// An item of the plain library as a station lists it (vault/plain.ts `shown`), and where it is.
type PlainRow = { id: string; owner: string; version: number; kind: string; name: string; notes: string; listing?: Listing; at: number; deleted?: true; station: string };
/// A use as a station says it (vault/secrets.ts `Use`).
type Use = { item: string; at: number; session: string; chatTitle: string | null; mode: string; command: string | null; hosts: string[]; denied: boolean };

/// The id the plain library goes by where a vault's would.
export const PLAIN = "plain";

/// This core's unsealed vault keys (by `<vault>/<epoch>`, until when), the lock as checked and the box key's public
/// half once known. The signing key's id is the lock's (`signerOf`), told as it is made, not read here once.
type Mem = {
  keys: Map<string, { key: Uint8Array; until: number }>; checked: Map<string, { at: string; lock: Checked | CoreError }>; box: string | null | undefined;
  /// Each vault's giving under way (one at a time); the version of each a station refused as no vault (not given
  /// again until it moves on).
  giving: Map<string, ReturnType<typeof Semaphore.makeUnsafe>>; refused: Map<string, number>;
  /// By workspace, the devices and members this device took out of its lock in this run at a person's asking
  /// (`tookOut`): a vault waiting to be keyed anew for one of them may read the box key to be keyed anew (`rekeyGone`).
  out: Map<string, Set<string>>;
};
const mems = new WeakMap<Inner, Mem>();
const mem = (inner: Inner): Mem => {
  let m = mems.get(inner);
  if (!m) mems.set(inner, (m = { keys: new Map(), checked: new Map(), box: undefined, giving: new Map(), refused: new Map(), out: new Map() }));
  return m;
};

const EMPTY: Held = { vaults: {}, at: {}, boxes: {}, requests: {}, asked: {}, refused: {}, on: {}, keeps: [], plain: {}, plainOn: [], uses: {}, hidden: {} };
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const nowS = (inner: Inner) => Math.floor(inner.host.nowMs() / 1000);
const fail = (code: string, message: string) => Effect.fail(new CoreError(code, message));

function held(inner: Inner, ws: string): Held {
  const h = inner.data.record("vault", ws);
  return isObject(h) ? { ...EMPTY, ...(h as Partial<Held>) } : EMPTY;
}

/// The held record changed by `change` (on a copy), and what shows it told.
function change(inner: Inner, ws: string, f: (h: Held) => void): void {
  const h = structuredClone(held(inner, ws)) as Held;
  f(h);
  inner.data.put("vault", ws, h);
  keepTook(inner, ws);
  changed(inner, ws);
}

function items(inner: Inner, ws: string, vault: string): Record<string, Item> {
  const v = inner.data.record("vaultItems", `${ws}/${vault}`);
  return isObject(v) ? (v as Record<string, Item>) : {};
}

function changeItems(inner: Inner, ws: string, vault: string, f: (items: Record<string, Item>) => void): void {
  const all = structuredClone(items(inner, ws, vault)) as Record<string, Item>;
  f(all);
  inner.data.put("vaultItems", `${ws}/${vault}`, all);
  changed(inner, ws);
}

function changed(inner: Inner, ws: string): void {
  lockSeen(inner).touch(`vault ${ws}`, "prompts");
  // (the requests' cards in the chats: shown again where how they are answered here changed)
  inner.views?.vaultChanged(ws);
}

const view = (inner: Inner, ws: string): J => inner.data.shared({ topic: "workspace", workspace: ws });
const stationsOf = (inner: Inner, ws: string): { id: string; name: string }[] => arr(get(view(inner, ws), "stations")).filter((s) => typeof s?.id === "string");

/// The workspace's lock as held here, checked (the same while its head does not move); an error says why it is none.
/// Where its chain moved, the state in force (views/lock.ts `inForceOf`, the same object while what it is made of
/// stands), as a station's vaults go by it (station/src/cloud/state.ts `Cloud.locked`): while it waits for the root's
/// log or its `open`, a state that names nobody (no vault shown, no key given, nobody asked), as a station's then.
function lockOf(inner: Inner, ws: string): Checked | CoreError {
  const h = inner.data.record("lock", ws);
  const entries = isObject(h) && Array.isArray(h.entries) ? (h.entries as Entry[]) : [];
  const head = isObject(h) ? str(get(h.head, "hash")) : null;
  if (entries.length === 0 || head === null) return new CoreError("vault_needs_lock", t("core-misc.vault.needsLock"));
  const force = inForceOf(inner, ws);
  // (where the chain moved, off is a statement, not an entry of it: the workspace off, as a chain disabled is)
  if (force.said === "off") return new CoreError("vault_needs_lock", t("core-misc.vault.needsLock"));
  // (moved: the state in force or, made of nothing the rules give, none that checks out; never the chain at the move)
  if (force.said !== "chain") return force.checked ?? new CoreError("vault_lock_invalid", "the workspace's lock does not check out: no state in force");
  const m = mem(inner);
  const at = `${head}/${entries.length}`;
  const had = m.checked.get(ws);
  if (had?.at === at) return had.lock;
  let lock: Checked | CoreError;
  try {
    lock = timed("vault.lock", () => checkLock(entries, nowS(inner)));
    if (lock.disabled) lock = new CoreError("vault_needs_lock", t("core-misc.vault.needsLock"));
  } catch (e) {
    lock = asCoreError(e);
  }
  m.checked.set(ws, { at, lock });
  return lock;
}

/// Whether a certificate is of an app device in the lock that is its person's own (lock-check.ts Device `own`: one an
/// admin put in under their name is given no key, by itself or asked), signed by its own key; whose device it is.
function certOwner(lock: Checked, cert: BoxCert): string | null {
  return rules.cert_ok_js(lock, cert, false, rulesCrypto) === null ? lock.devices.get(cert.device)!.sub : null;
}

/// The app device of the lock that signs with `key`, where it is its person's own (no other's signature counts).
const ownSigner = (lock: Checked, key: unknown) => [...lock.devices.values()].find((x) => x.kind === "app" && x.own && x.sign_key === key);

/// Whether a vault's version is one the stations take (rules/, as station/src/vault/crypto.ts `vaultOk` checks a copy
/// brought from another station): signed by one of its owner's own app devices in the lock, its members in the lock,
/// each of its keys for a member's own device. Found once for each lock and version.
const trust = new WeakMap<Checked, WeakMap<Vault, boolean>>();
function trusted(lock: Checked, v: Vault): boolean {
  let of = trust.get(lock);
  if (!of) trust.set(lock, (of = new WeakMap()));
  let ok = of.get(v);
  if (ok === undefined) of.set(v, (ok = rules.vault_ok_js(lock, null, v, true, rulesCrypto) === null));
  return ok;
}

/// The lock as it stood when it last took vault version `v`: the lock as it is where it takes it, else the longest
/// prefix of the chain held that does (a version keyed for a device or member taken out since), else none. Found once
/// for each chain and version: a lock held is replaced whole as it moves on, never changed in place (a version by its
/// vault, number and signature, as what is held of the vaults is made anew at every change to any of them): the pages
/// ask it on every view of the vaults (`waitingAs`).
const took = new WeakMap<readonly Entry[], Map<string, Checked | null>>();
/// How many prefixes of a lock `tookAs` has checked: a count only, that the tests read (what it finds is kept).
export const waitingChecks = { count: 0 };
function tookAs(inner: Inner, ws: string, v: Vault): Checked | null {
  const lock = lockOf(inner, ws);
  if (!(lock instanceof CoreError) && trusted(lock, v)) return lock;
  // (a moved workspace has no line of prefixes: what this device kept of the state that took it)
  if (movedHere(inner, ws)) return keptFor(inner, ws, v);
  const entries: readonly Entry[] = lockHeld(inner, ws)?.entries ?? [];
  let of = took.get(entries);
  if (!of) took.set(entries, (of = new Map()));
  const at = `${v.id}/${v.seq}/${v.sig?.sig}`;
  if (of.has(at)) return of.get(at)!;
  let was: Checked | null = null;
  for (let n = entries.length - 1; n > 0 && was === null; n--) {
    waitingChecks.count++;
    try {
      const prefix = checkLock(entries.slice(0, n) as Entry[], nowS(inner));
      if (!prefix.disabled && trusted(prefix, v)) was = prefix;
    } catch {
      // (a prefix that does not check out: an earlier one may)
    }
  }
  of.set(at, was);
  return was;
}

/// Where a workspace's chain moved, what of the state in force took each vault's version this device found trusted
/// (`keepTook`), by vault, then by epoch: the vault's members in that state with their roles, their app devices as it
/// named them (sign key, own) and the signing keys each had had in it (`signKeys`). That is all `vault_ok_js`,
/// `cert_ok_js` and `item_ok_js` read of a lock for one vault (rules/src/js/js.mbt `lock_view`: its members, devices
/// and signKeys; of those, a version's members, its keys' devices, its signer, its owner's, and an item's signer, a
/// member's device), so the version and its items are taken by it as they were. Kept for the newest version found
/// trusted of the vault's own epoch, and of an earlier epoch while its last version is kept for items left under it
/// (`before`): bounded by the vaults held, each by its members and their devices.
type TookState = { seq: number; sig: string; members: [string, string][]; devices: [string, TookDevice][]; signKeys: [string, string[]][] };
type TookDevice = { id: string; sub: string; kind: "app"; sign_key?: string; own: boolean };
type Took = Record<string, Record<string, TookState>>;
const tookHeld = (inner: Inner, ws: string): Took => {
  const r = inner.data.record("vaultTook", ws);
  return isObject(r) && isObject(r.took) ? (r.took as Took) : {};
};

/// What of `lock` takes vault version `v` (`TookState`).
function sliceOf(lock: Checked, v: Vault): TookState {
  const subs = new Set([v.owner, ...v.members].filter((m) => lock.members.has(m)));
  const devices = [...lock.devices.values()].filter((d) => d.kind === "app" && subs.has(d.sub)).sort((a, b) => (a.id < b.id ? -1 : 1));
  return {
    seq: v.seq, sig: v.sig?.sig ?? "",
    members: [...subs].sort().map((m) => [m, lock.members.get(m)!]),
    devices: devices.map((d) => [d.id, { id: d.id, sub: d.sub, kind: "app", ...(typeof d.sign_key === "string" ? { sign_key: d.sign_key } : {}), own: d.own }]),
    signKeys: devices.flatMap((d) => (lock.signKeys.has(d.id) ? [[d.id, [...lock.signKeys.get(d.id)!]] as [string, string[]]] : [])),
  };
}

/// The lock a kept state is read as: the same object for the same record (`trusted`'s WeakMap rests on it). It names
/// no passkey, settings or stations, and the rules' own object is not kept for it (nothing asks who signs by it).
const keptLocks = new WeakMap<TookState, Checked>();
function keptLock(ws: string, s: TookState): Checked {
  let c = keptLocks.get(s);
  if (c === undefined) {
    c = { ws, head: "", genesis: "", members: new Map(s.members), devices: new Map(s.devices), passkeys: new Map(), signed: new Set(), signKeys: new Map(s.signKeys), origins: [], rp_id: "", disabled: false, cloudKeys: null };
    keptLocks.set(s, c);
  }
  return c;
}

/// Where the chain moved, the state that took vault version `v` as this device kept it: only for that very version
/// (its number and signature), never a later one a station gives, and only where it takes it; else none (a device
/// begun anew since kept none, and holds no key of it either).
function keptFor(inner: Inner, ws: string, v: Vault): Checked | null {
  const s = tookHeld(inner, ws)[v.id]?.[String(v.epoch)];
  if (s === undefined || s.seq !== v.seq || s.sig !== (v.sig?.sig ?? "")) return null;
  const c = keptLock(ws, s);
  return trusted(c, v) ? c : null;
}

/// What of the state in force took each vault version held, kept (`TookState`) where the chain moved: as a version is
/// first found trusted (the vaults held changed: `change`) and as the state changes while it still is (`vaultCome`,
/// which runs as it is made anew, whatever made it so); never as a topic is answered. A version the state takes no
/// more keeps what was kept of it; a state that waits (naming nobody) or is off changes nothing kept.
function keepTook(inner: Inner, ws: string): void {
  if (!movedHere(inner, ws)) return;
  const lock = lockOf(inner, ws);
  const h = held(inner, ws);
  const was = tookHeld(inner, ws);
  const next: Took = {};
  for (const v of Object.values(h.vaults)) {
    if (v.deleted) continue;
    const keep: Record<string, TookState> = {};
    for (const [e, s] of Object.entries(was[v.id] ?? {})) if (e === String(v.epoch) || h.before?.[v.id]?.[e] !== undefined) keep[e] = s;
    if (!(lock instanceof CoreError) && trusted(lock, v)) {
      const s = sliceOf(lock, v);
      const had = keep[String(v.epoch)];
      keep[String(v.epoch)] = had !== undefined && JSON.stringify(had) === JSON.stringify(s) ? had : s;
    }
    if (Object.keys(keep).length > 0) next[v.id] = keep;
  }
  if (JSON.stringify(next) !== JSON.stringify(was)) inner.data.put("vaultTook", ws, { took: next });
}

/// A vault waiting to be keyed anew: the lock as it stood when it last took version `v` (`tookAs`), where the lock as
/// it is takes it no more only for a device or a member taken out since that holds a key of it or is in it, and its
/// owner is a member still; else null. Until its owner's device keys it anew (`rekeyGone`, written on its own
/// station), the devices left read it as that lock took it, and change nothing in it (`vault_waiting`,
/// `waitingError`): the stations take no version of it till then (rules/, a key for a device not in the lock). The
/// owner's decision, 2026-11-10: with the vault's station off (a laptop closed), a device taken out left the vault
/// gone for everyone, its items 「条目不存在」, until that station was back, though the devices left held its key and
/// its items. It gives the device taken out nothing: that device is out of the lock, so reads nothing of any vault
/// here (`Vaults.#ready`, and the views ask for this device in the lock), and reaches no station; what is carried on
/// as the vault is keyed anew is checked against this same lock (`#carryNow`).
export function waitingAs(inner: Inner, ws: string, lock: Checked, v: Vault): Checked | null {
  if (v.deleted || trusted(lock, v)) return null;
  const gone = v.keys.some((k) => !lock.devices.has(k.cert.device)) || v.members.some((m) => !lock.members.has(m));
  if (!gone || !lock.members.has(v.owner)) return null;
  return tookAs(inner, ws, v);
}

/// The lock vault `v` is read by on this device: the lock as it is, where it takes it; the lock as it stood, where it
/// waits to be keyed anew (`waitingAs`) and this device, in the lock (`self`), holds one of its keys; else null (not
/// there).
function readAs(inner: Inner, ws: string, lock: Checked, v: Vault, self: { device: string } | null): Checked | null {
  if (v.deleted) return null;
  if (trusted(lock, v)) return lock;
  if (self === null || !v.keys.some((k) => k.cert.device === self.device)) return null;
  return waitingAs(inner, ws, lock, v);
}

/// The name of the station vault `v` waits on to be keyed anew (`waitingAs`), the one it lives on: its id's first
/// characters where the workspace names none.
function waitsOn(inner: Inner, ws: string, v: Vault): string {
  const at = hostOf(inner, ws, v.id);
  return str(stationsOf(inner, ws).find((s) => s.id === at)?.name) || at.slice(0, 8);
}

/// Why a change to vault `v`, waiting to be keyed anew, is refused: the station it waits for (`waitsOn`).
function waitingError(inner: Inner, ws: string, v: Vault): CoreError {
  return new CoreError("vault_waiting", t("core-misc.vault.waiting", { name: v.name, station: waitsOn(inner, ws, v) }));
}

/// Which of what a station says the rules take (a vault's version, an item's, a box certificate): what one says is
/// held over what is held only where they take it, or take what is held no more than it. A version a station made up
/// (signed by someone other than its writer, a later number on it) hides none held before it, nor one it gives after
/// (test/vault.test.ts "a station that lies"). No lock checked here: none taken. A vault waiting to be keyed anew
/// (`waitingAs`) is taken as the lock it waits by took it, and its items checked against that lock: else any later
/// version a station made up of it or of an item, taken by none, would be held over it.
type Fits = { vault(v: Vault): boolean; item(i: Item): boolean; cert(c: BoxCert): boolean };
function fits(inner: Inner, ws: string): Fits {
  const lock = lockOf(inner, ws);
  if (lock instanceof CoreError) return { vault: () => false, item: () => false, cert: () => false };
  return {
    vault: (v) => trusted(lock, v) || waitingAs(inner, ws, lock, v) !== null,
    item: (i) => {
      const v = held(inner, ws).vaults[i.vault];
      const as = v === undefined ? null : trusted(lock, v) ? lock : waitingAs(inner, ws, lock, v);
      return v !== undefined && as !== null && rules.item_ok_js(as, v, null, i, true, rulesCrypto) === null;
    },
    cert: (c) => rules.cert_ok_js(lock, c, false, rulesCrypto) === null,
  };
}

/// Whether what is said is held over what is: the rules take it and not what is held, or it is the later (`later`) and
/// they take it or what is held no more.
const over = (ok: boolean, okHad: () => boolean, later: boolean) => (ok && !okHad()) || (later && (ok || !okHad()));

/// This device in the lock: the one whose signing key is this app's, where it is its person's own (one an admin put
/// in under their name signs nothing, so keeps no vault).
function me(lock: Checked, signer: string | null | undefined): { device: string; sub: string } | null {
  if (!signer) return null;
  const d = ownSigner(lock, signer);
  return d ? { device: d.id, sub: d.sub } : null;
}

/// The certificates the lock vouches for, latest by device, each with whose it is (`sub`): those of the members' own
/// devices only. `bare`: the certificate alone, as it was signed (what is sealed to, and what a vault's keys carry: a
/// field more breaks its signature).
type Vouched = BoxCert & { sub: string };
function certs(inner: Inner, ws: string, lock: Checked): Vouched[] {
  return Object.values(held(inner, ws).boxes).flatMap((c) => {
    const sub = certOwner(lock, c);
    return sub === null ? [] : [{ ...c, sub }];
  });
}
const bare = ({ sub: _s, ...c }: Vouched): BoxCert => c;

export function install(inner: Inner): void {
  handlers.vault = (core, call, _progress, _at, ctx) => run(core, call as Of, ctx);
  inner.stations.also.push({ read: (address) => readStation(inner, address), event: (address, name, data) => heard(inner, address, name, data) });
  inner.router.owners.push(owner(inner));
  // What this app keeps (no person asked): its box key's public half.
  inner.runner.fork(
    Effect.gen(function* () {
      const m = mem(inner);
      const pub = yield* Effect.orElseSucceed(inner.host.storageGet(BOX_PUB), () => null);
      m.box = pub ? new TextDecoder().decode(pub) : null;
      lockSeen(inner).touch("self");
      inner.views?.vaultChanged(null);
    }),
  );
}

// ── what the stations hold ──

const ask = (inner: Inner, address: string, method: string, path: string, body: unknown = null, ctx: SpanContext | null = null) =>
  inner.stations.requests.call(StationAddr.parse(address), method, path, body, { quiet: true, ctx });

/// What a station holds of the vault, read again: its vaults (and their items), the box certificates, the requests.
/// One that holds none says why (no lock pinned; a station from before).
function readStation(inner: Inner, address: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    if (!inner.stations.link(address) || !inner.stations.reachable(address)) return;
    const ws = ofAddress(address);
    const station = address.slice(ws.length + 1);
    // The plain library (a station from before keeps none: 404), whether security mode is on or not.
    const plain = yield* Effect.result(ask(inner, address, "GET", "/vault/plain"));
    const plainItems = plain._tag === "Success" ? (arr(get(plain.success, "items")) as PlainRow[]) : null;
    if (plainItems !== null || (plain._tag === "Failure" && plain.failure.status === 404)) {
      change(inner, ws, (h) => {
        for (const [id, row] of Object.entries(h.plain)) if (row.station === station) delete h.plain[id];
        for (const i of plainItems ?? []) if (typeof i?.id === "string") h.plain[i.id] = { ...i, station };
        h.plainOn = h.plainOn.filter((s) => s !== station).concat(plainItems !== null ? [station] : []);
        const lasts = SCOPES.find((s) => s === get(plain._tag === "Success" ? plain.success : null, "lasts"));
        const at = get(plain._tag === "Success" ? plain.success : null, "lastsAt");
        if (lasts && typeof at === "number" && (h.plainLasts === undefined || h.plainLasts.at < at)) h.plainLasts = { lasts, at };
      });
    }
    // The requests are the keeper's (a station without one answers 404: none).
    const requests = yield* Effect.orElseSucceed(Effect.map(ask(inner, address, "GET", "/vault/requests"), (r) => arr(get(r, "requests")) as Request[]), () => [] as Request[]);
    // (what it was held to hold as it was asked: a listing says nothing of a vault written there after it was asked)
    const then = held(inner, ws);
    const vaults = yield* Effect.result(ask(inner, address, "GET", "/vault/vaults"));
    let list: Vault[] | null = null;
    let all: Item[] = [];
    let boxes: BoxCert[] = [];
    if (vaults._tag === "Failure") {
      const e = vaults.failure;
      if (e.status !== undefined && e.status >= 400 && e.status < 500) change(inner, ws, (h) => {
        h.refused[station] = e.code;
        h.keeps = h.keeps.filter((s) => s !== station);
      });
    } else {
      list = arr(get(vaults.success, "vaults")) as Vault[];
      all = arr(get(yield* ask(inner, address, "GET", "/vault/items"), "items")) as Item[];
      boxes = arr(get(yield* ask(inner, address, "GET", "/vault/boxes"), "boxes")) as BoxCert[];
    }
    for (const v of [...(plainItems !== null ? [PLAIN] : []), ...(list ?? []).map((v) => v.id)]) yield* readUses(inner, address, v);
    // (what it says checked against the lock as held here; its items against their vaults as held once it is read)
    const fit = fits(inner, ws);
    const missing: string[] = [];
    // (a station read anew, its lock maybe caught up or itself updated: a version it refused is tried once more)
    for (const v of list ?? []) mem(inner).refused.delete(v.id);
    change(inner, ws, (h) => {
      if (list !== null) {
        delete h.refused[station];
        if (!h.keeps.includes(station)) h.keeps.push(station);
        const ids = new Set(list.map((v) => v.id));
        // Those it held and holds no more (one held from before copies were kept: where it was): held still here, as
        // its not listing one says nothing of why (a station that lies hides none so); asked for below. Only those it
        // was held to hold as it was asked: a vault made or first copied there meanwhile is not in a listing asked
        // before it (the locks' end to end, 2026-11-15: a vault made on the station as it was being read lost its
        // host here, and the write after it went to station "" and was refused `invalid_params`).
        const heldThen = (id: string) => then.on[id]?.[station] !== undefined || (then.on[id] === undefined && then.at[id] === station);
        for (const id of new Set([...Object.keys(h.on), ...Object.keys(h.at)])) {
          if (!ids.has(id) && heldThen(id) && (h.on[id]?.[station] !== undefined || (h.on[id] === undefined && h.at[id] === station))) {
            unheld(h, id, station);
            if (h.vaults[id] !== undefined) missing.push(id);
          }
        }
        for (const v of list) {
          holds(h, v, station, all.filter((i) => i.vault === v.id), fit);
        }
      }
      for (const c of boxes) if (heldOver(h.boxes[c.device], c, fit)) h.boxes[c.device] = c;
      for (const [id, at] of Object.entries(h.asked)) {
        if (at === station) {
          delete h.requests[id];
          delete h.asked[id];
        }
      }
      for (const r of requests) {
        if (r?.status !== "pending") continue;
        h.requests[r.id] = r;
        h.asked[r.id] = station;
      }
    });
    // Each item as the latest version any station holds (a copy behind its host's says nothing newer).
    for (const v of list ?? []) {
      // (gone where the version held says so: one a station made up deletes nothing)
      if (held(inner, ws).vaults[v.id]?.deleted) inner.data.forgetRecord("vaultItems", `${ws}/${v.id}`);
      else changeItems(inner, ws, v.id, (held) => {
        for (const i of all) if (i.vault === v.id && newer(i, held[i.id], fit)) held[i.id] = i;
      });
      settleBefore(inner, ws, v.id);
    }
    // Those it lists no more: the latest versions it holds of them, as the versions held here show this person was in
    // them; one taking them out (or deleting it), checked, lets it go here.
    if (missing.length > 0) yield* askLatest(inner, address, missing);
    if (list !== null) spreadAll(inner, ws);
    // This device's certificate brought to a station that lacks it (one added to the workspace, or away, since this
    // device was set up): what its agents ask to keep is sealed to this device too, and the requests waiting there are
    // sealed again (vault/secrets.ts `boxed`). 2026-11-03: a request a station made without it could be approved on no
    // page of this device (「此申请提出时此设备尚未开启密钥库」).
    if (list !== null) {
      const lock = lockOf(inner, ws);
      const self = lock instanceof CoreError ? null : me(lock, signerOf(inner));
      const mine = self === null ? undefined : held(inner, ws).boxes[self.device];
      if (self !== null && mine !== undefined && mine.box === mem(inner).box && certOwner(lock as Checked, mine) !== null && !boxes.some((c) => c.device === self.device && c.at >= mine.at)) {
        yield* Effect.ignore(ask(inner, address, "PUT", "/vault/boxes", mine), { log: "Unhandled", message: "vault box brought" });
      }
    }
    // (members' devices set up meanwhile: given the keys unsealed here)
    if (boxes.length > 0) giveKept(inner, ws);
    // (items left under an earlier key, a keying anew stopped half-way: written again under the vault's where the keys
    // are unsealed here still)
    if (list !== null) carryKept(inner, ws);
  });
}

/// Whether item `i` is kept over `had` (none: it is): the later version, or of one version the one every station keeps
/// (rules/ `item_supersedes_js`).
const newer = (i: Item, had: Item | undefined, fit: Fits) =>
  had === undefined || over(fit.item(i), () => fit.item(had), i.version > had.version || (i.version === had.version && rules.item_supersedes_js(i, had)));

/// Whether box certificate `c` is held over `had` (the later, as `over` says).
const heldOver = (had: BoxCert | undefined, c: BoxCert, fit: Fits) => had === undefined || over(fit.cert(c), () => fit.cert(had), had.at <= c.at);

/// That `at` (a station's holding) holds item `i` at its version.
function holdsItem(at: Holding, i: Item): void {
  at.items[i.id] = i.version;
  if (typeof i.sig?.sig === "string") (at.sigs ??= {})[i.id] = i.sig.sig;
}

/// `station` holds vault `v` (and these items, when said): the version kept of those held anywhere is the one shown.
function holds(h: Held, v: Vault, station: string, items: Item[] | null, fit: Fits): void {
  const on = (h.on[v.id] ??= {});
  const was = on[station];
  on[station] = { seq: v.seq, items: was?.items ?? {}, sig: v.sig?.sig, ...(was?.sigs ? { sigs: was.sigs } : {}) };
  if (items !== null) {
    on[station] = { seq: v.seq, items: {}, sig: v.sig?.sig };
    for (const i of items) holdsItem(on[station]!, i);
  }
  // Its host the first of the stations holding it by id, the same on every device: what each writes there follows on
  // from the same version (one written to another meanwhile is refused, not a second of its seq).
  h.at[v.id] = Object.keys(on).sort()[0]!;
  take(h, v, fit);
}

/// Where vault `id` is written from this device (`at` as it is written to, `hostOf`): the first by id of the stations
/// holding it that the workspace has now (its list, and the lock's stations where the lock names any), the same on
/// every device that holds the same; `at` where none of them holds it. A station taken out of the workspace stays in
/// `on` (nothing reads it again to say it holds none), and where its id was the first, every write and keying anew of
/// the vault went to it, a station no longer there: the locks' end to end, 2026-11-15, a station enrolled, given the
/// vault's copy, taken out and stopped, then the owner's write refused `vault_waiting` naming it.
function hostOf(inner: Inner, ws: string, id: string): string {
  const h = held(inner, ws);
  const listed = new Set(stationsOf(inner, ws).map((s) => s.id));
  const named = stateOf(inner, ws).stations;
  const there = Object.keys(h.on[id] ?? {}).filter((s) => listed.has(s) && (named.size === 0 || named.has(s))).sort();
  return there[0] ?? h.at[id] ?? "";
}

/// Vault `v` held over the version held where the rules say so (of one seq, written on two stations at once: the one
/// every station and device keeps); a later one the lock does not take yet kept aside (`later`). One under a new key
/// keeps the version it replaces as the last of its key (`before`): its items may be left under it a while.
function take(h: Held, v: Vault, fit: Fits): void {
  const had = h.vaults[v.id];
  const later = had !== undefined && rules.vault_supersedes_js(v, had);
  if (had === undefined || over(fit.vault(v), () => fit.vault(had), later)) {
    h.vaults[v.id] = v;
    // (a vault deleted keeps no items, so nothing under an earlier key either)
    if (v.deleted) delete h.before?.[v.id];
    else if (had !== undefined && v.epoch > had.epoch) {
      const before = (h.before ??= {});
      before[v.id] = { ...before[v.id], [had.epoch]: had };
    }
    if (h.later?.[v.id] !== undefined && !rules.vault_supersedes_js(h.later[v.id], v)) delete h.later[v.id];
  } else if (later && (h.later?.[v.id] === undefined || rules.vault_supersedes_js(v, h.later[v.id]))) (h.later ??= {})[v.id] = v;
}

/// The versions kept of vault `id`'s earlier keys (`before`) let go where no item held of it sits under them any more.
/// As its items are read whole of a station, never as they are carried on here: an item another device wrote under
/// the earlier key as the vault was keyed anew may be told only after this device wrote the ones it held again, and
/// would then have no version to be carried on by.
function settleBefore(inner: Inner, ws: string, id: string): void {
  const of = held(inner, ws).before?.[id];
  if (of === undefined) return;
  const under = new Set(Object.values(items(inner, ws, id)).filter((i) => !i.deleted).map((i) => String(i.epoch)));
  const gone = Object.keys(of).filter((e) => !under.has(e));
  if (gone.length === 0) return;
  change(inner, ws, (h) => {
    const kept = h.before?.[id];
    if (kept === undefined) return;
    for (const e of gone) delete kept[e];
    if (Object.keys(kept).length === 0) delete h.before![id];
  });
}

/// The versions kept aside (`later`) that the lock as it is now takes, held: their items read again of the station
/// holding them (one heard before its vault was taken here was not held either).
function takeLater(inner: Inner, ws: string): void {
  const fit = fits(inner, ws);
  const now = Object.values(held(inner, ws).later ?? {}).filter((v) => fit.vault(v));
  if (now.length === 0) return;
  change(inner, ws, (h) => {
    for (const v of now) {
      delete h.later![v.id];
      take(h, v, fit);
    }
  });
  const h = held(inner, ws);
  for (const v of now) {
    const station = Object.entries(h.on[v.id] ?? {}).find(([, at]) => at.seq === v.seq)?.[0] ?? h.at[v.id];
    if (station !== undefined) inner.scheduler.enqueue(`${ws}/${station}`, `${ws}/${station} vault/${v.id}`, Priority.background, readItems(inner, `${ws}/${station}`, v.id));
  }
}

/// `station` no longer holds vault `id` (the version held kept, whoever holds it): its host another that does.
function unheld(h: Held, id: string, station: string): void {
  const on = h.on[id];
  if (on !== undefined) delete on[station];
  if (on !== undefined && Object.keys(on).length === 0) delete h.on[id];
  if (h.at[id] === station || h.at[id] === undefined) {
    const left = Object.keys(h.on[id] ?? {}).sort();
    if (left.length > 0) h.at[id] = left[0]!;
    else delete h.at[id];
  }
}

/// Whether the version of vault `id` held here takes this person out of it, or deletes it.
function outOf(inner: Inner, ws: string, id: string): boolean {
  const v = held(inner, ws).vaults[id];
  const sub = inner.workspaces.owner(ws);
  return v !== undefined && (v.deleted === true || sub === null || !v.members.includes(sub));
}

/// Vault `id` let go here where the version held says this person is out of it.
function forgetIfOut(inner: Inner, ws: string, id: string, station: string): void {
  if (!outOf(inner, ws, id)) return;
  change(inner, ws, (h) => letGo(h, id, station));
  inner.data.forgetRecord("vaultItems", `${ws}/${id}`);
}

/// The latest versions `address` holds of vaults `ids`, asked by the versions held here (each naming this person, its
/// owner's: station/src/api/routes/vault.ts `vault/vaults/latest`); taken as any it says, checked; those taking this
/// person out let go. A station from before answers 404: nothing taken, nothing let go.
function askLatest(inner: Inner, address: string, ids: string[]): Effect.Effect<void> {
  const ws = ofAddress(address);
  const station = address.slice(ws.length + 1);
  const mine = ids.map((id) => held(inner, ws).vaults[id]).filter((v): v is Vault => v !== undefined);
  return Effect.flatMap(
    Effect.orElseSucceed(Effect.map(ask(inner, address, "POST", "/vault/vaults/latest", { held: mine }), (r) => arr(get(r, "vaults")) as Vault[]), () => [] as Vault[]),
    (latest) => Effect.sync(() => {
      const fit = fits(inner, ws);
      change(inner, ws, (h) => {
        for (const v of latest) if (ids.includes(v.id)) holds(h, v, station, null, fit);
        // (it holds them: the copy of a station that lists one no more for this person; held here no longer as theirs)
        for (const v of latest) unheld(h, v.id, station);
      });
      for (const id of ids) forgetIfOut(inner, ws, id, station);
    }),
  );
}

/// `station` no longer holds vault `id`: gone where no station holds it; its host another that does.
function letGo(h: Held, id: string, station: string): void {
  const on = h.on[id];
  if (on !== undefined) delete on[station];
  if (on === undefined || Object.keys(on).length === 0) {
    delete h.on[id];
    delete h.vaults[id];
    delete h.at[id];
    delete h.before?.[id];
    return;
  }
  if (h.at[id] === station || h.at[id] === undefined) h.at[id] = Object.keys(on).sort()[0]!;
}

/// What `station` lacks of what the vaults' latest versions are: the vaults it holds none or an older version of, and
/// the items it holds none or an older version of (of the vaults it will hold).
function lacks(h: Pick<Held, "vaults" | "on">, items: (vault: string) => Record<string, Item>, station: string): { id: string; vault: Vault | null; items: Item[] }[] {
  return Object.values(h.vaults).flatMap((v) => {
    const have = h.on[v.id]?.[station];
    // (or the other one of its seq, or of an item's version: brought the one kept)
    const other = (held: string | undefined, sig: unknown) => held !== undefined && typeof sig === "string" && held !== sig;
    const behind = have === undefined || have.seq < v.seq || (have.seq === v.seq && other(have.sig, v.sig?.sig));
    const missing = v.deleted ? [] : Object.values(items(v.id)).filter((i) => {
      const at = have?.items[i.id] ?? -1;
      return at < i.version || (at === i.version && other(have?.sigs?.[i.id], i.sig?.sig));
    });
    return behind || missing.length > 0 ? [{ id: v.id, vault: behind ? v : null, items: missing }] : [];
  });
}

/// Every station that keeps vaults brought what it lacks (each in its own lane, once at a time).
function spreadAll(inner: Inner, ws: string): void {
  for (const station of held(inner, ws).keeps) {
    const address = `${ws}/${station}`;
    inner.scheduler.enqueue(address, `${address} vault-spread`, Priority.background, spread(inner, address));
  }
}

/// A station brought the latest version of each vault and item it lacks, as copies (`?copy=1`: a later version than
/// the one it holds, checked as any is). One that will not take it (a station from before, which takes only the next
/// version) is left as it is: its agents see what it holds.
function spread(inner: Inner, address: string): Effect.Effect<void> {
  const ws = ofAddress(address);
  const station = address.slice(ws.length + 1);
  return Effect.gen(function* () {
    if (!inner.stations.link(address) || !inner.stations.reachable(address)) return;
    for (const want of lacks(held(inner, ws), (vault) => items(inner, ws, vault), station)) {
      if (want.vault !== null) {
        const said = yield* Effect.result(ask(inner, address, "PUT", "/vault/vaults?copy=1", want.vault));
        if (said._tag === "Failure") continue;
        const v = (get(said.success, "vault") as Vault | undefined) ?? want.vault;
        change(inner, ws, (h) => holds(h, v, station, null, fits(inner, ws)));
      }
      for (const i of want.items) {
        const said = yield* Effect.result(ask(inner, address, "PUT", "/vault/items?copy=1", i));
        if (said._tag === "Failure") continue;
        const kept = (get(said.success, "item") as Item | undefined) ?? i;
        change(inner, ws, (h) => {
          const at = h.on[want.id]?.[station];
          if (at !== undefined) holdsItem(at, kept);
        });
      }
    }
  });
}

/// A station's event of the vault: a vault, an item, a box certificate or a request as it is now, a vault gone.
function heard(inner: Inner, address: string, name: string, data: unknown): void {
  const ws = ofAddress(address);
  const station = address.slice(ws.length + 1);
  const d = data as J;
  switch (name) {
    case "vault": {
      if (typeof d?.id !== "string") return;
      const known = held(inner, ws).on[d.id]?.[station] !== undefined;
      change(inner, ws, (h) => holds(h, d as Vault, station, null, fits(inner, ws)));
      if (held(inner, ws).vaults[d.id]?.deleted) inner.data.forgetRecord("vaultItems", `${ws}/${d.id}`);
      // One this person was just put in (or this station was just brought): its items are read.
      else if (!known) inner.scheduler.enqueue(address, `${address} vault/${d.id}`, Priority.background, readItems(inner, address, d.id));
      spreadAll(inner, ws);
      return;
    }
    case "vault-gone":
      if (typeof d?.id !== "string") return;
      // Gone here only by the version taking this person out, checked (`vault`, as the station tells it); else held
      // still, the station holding it no more.
      change(inner, ws, (h) => {
        if (isObject(d.vault) && d.vault.id === d.id) holds(h, d.vault as Vault, station, null, fits(inner, ws));
        unheld(h, d.id, station);
      });
      forgetIfOut(inner, ws, d.id, station);
      return;
    case "vault-item":
      if (typeof d?.vault === "string" && typeof d?.id === "string") {
        const fit = fits(inner, ws);
        changeItems(inner, ws, d.vault, (all) => { if (newer(d as Item, all[d.id], fit)) all[d.id] = d; });
        change(inner, ws, (h) => {
          const at = h.on[d.vault]?.[station];
          if (at !== undefined) holdsItem(at, d as Item);
        });
        spreadAll(inner, ws);
      }
      return;
    case "vault-box":
      if (typeof d?.device === "string") {
        change(inner, ws, (h) => {
          if (heldOver(h.boxes[d.device], d as BoxCert, fits(inner, ws))) h.boxes[d.device] = d;
        });
        // A member's device set up (or asking again): given the keys unsealed here, no one asked.
        giveKept(inner, ws);
      }
      return;
    case "vault-plain":
      if (typeof d?.id === "string") change(inner, ws, (h) => void (h.plain[d.id] = { ...d, station }));
      return;
    case "vault-request":
      if (typeof d?.id !== "string") return;
      // Decided: a use of its item, read again as its station says it (with its chat's title).
      if ((d.status === "granted" || d.status === "denied") && typeof d.vault === "string") {
        inner.scheduler.enqueue(address, `${address} vault-uses/${d.vault}`, Priority.background, readUses(inner, address, d.vault));
      }
      change(inner, ws, (h) => {
        if (d.status === "pending") {
          h.requests[d.id] = d;
          h.asked[d.id] = station;
        } else {
          delete h.requests[d.id];
          delete h.asked[d.id];
        }
      });
      return;
  }
}

/// The uses of a vault's items (or the plain library's) a station keeps; one from before keeps none to say.
function readUses(inner: Inner, address: string, vault: string): Effect.Effect<void> {
  const ws = ofAddress(address);
  const station = address.slice(ws.length + 1);
  return Effect.flatMap(
    Effect.orElseSucceed(Effect.map(ask(inner, address, "GET", `/vault/uses?vault=${encodeURIComponent(vault)}`), (r) => arr(get(r, "uses")) as Use[]), () => null),
    (uses) => Effect.sync(() => { if (uses !== null) change(inner, ws, (h) => void (h.uses[`${station}/${vault}`] = uses)); }),
  );
}

function readItems(inner: Inner, address: string, vault: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const ws = ofAddress(address);
    const station = address.slice(ws.length + 1);
    const all = arr(get(yield* ask(inner, address, "GET", `/vault/items?vault=${encodeURIComponent(vault)}`), "items")) as Item[];
    const fit = fits(inner, ws);
    changeItems(inner, ws, vault, (held) => {
      for (const i of all) if (newer(i, held[i.id], fit)) held[i.id] = i;
    });
    settleBefore(inner, ws, vault);
    change(inner, ws, (h) => {
      const at = h.on[vault]?.[station];
      if (at !== undefined) {
        at.items = {};
        delete at.sigs;
        for (const i of all) holdsItem(at, i);
      }
    });
    spreadAll(inner, ws);
  });
}

// ── what the pages show ──

function owner(inner: Inner): Owner {
  return {
    owns: (t: Topic) => t.topic === "vaults" || t.topic === "vaultItems" || t.topic === "vaultUses",
    // Shown: the workspace's stations read again, what is held showing meanwhile.
    start: (t: Topic) => {
      const ws = t.workspace as string;
      for (const s of stationsOf(inner, ws)) {
        const address = `${ws}/${s.id}`;
        inner.scheduler.enqueue(address, `${address} vault`, Priority.shown, readStation(inner, address));
      }
    },
    compute: (t: Topic) => {
      const ws = typeof t.workspace === "string" ? t.workspace : "";
      // (what this core holds of them beside the records: its keys, the lock, the vaults unsealed here)
      const seen = lockSeen(inner);
      seen.read("self");
      seen.read(`lock ${ws}`);
      seen.read(`vault ${ws}`);
      return { ok: t.topic === "vaults" ? vaultsView(inner, ws) : t.topic === "vaultUses" ? usesView(inner, ws, String(t.vault), String(t.item)) : itemsView(inner, ws, String(t.vault)) };
    },
  };
}

const keyOf = (v: Vault) => `${v.id}/${v.epoch}`;
const unlocked = (inner: Inner, v: Vault) => (mem(inner).keys.get(keyOf(v))?.until ?? 0) > inner.host.nowMs();

/// Whether this host keeps keys as an app does, in the system's secure storage.
const able = (inner: Inner) => inner.host.appKeys === true && typeof inner.host.secureGet === "function" && typeof inner.host.secureSet === "function";

/// How an agent's request a card names (`card.vault`; `save`: one to keep a secret) is answered on this device, from the
/// vault as this core holds it: what a chat's card shows at its foot with the message itself (views.ts),
/// never asking for more. `elsewhere`: approved only in an app that keeps keys (the plain library's anywhere); `setUp`:
/// a secret to keep while this device's vault is not on (开启密钥库 first); else `approve`, a use given for `lasts` at the
/// longest (the item's, else its vault's; a request not held yet, as one with none said).
export type AskAnswer = { answer: "approve" | "setUp" | "elsewhere" | "notHere"; lasts?: Scope };

/// Whether a secret an agent asks to keep was sealed by its station to the person's devices set up then, this one not
/// among them (set up since, or its certificate not on that station then): approved on one of those, or here once
/// the station has this device's certificate and seals it again (readStation brings it). The card says so instead of
/// failing as 存入 is pressed (2026-11-03, 「此申请提出时此设备尚未开启密钥库」).
const notHere = (r: Request | undefined, device: string | null, box: string | null): boolean =>
  r?.save !== undefined && r.save.typed !== true && Array.isArray(r.sealed) && device !== null && !r.sealed.some((x) => x.device === device && (box === null || x.box === box));

export function askAnswers(inner: Inner, ws: string, asks: { request: string; save: boolean }[]): AskAnswer[] {
  const lock = lockOf(inner, ws);
  const plain = lock instanceof CoreError;
  if (!able(inner) && !plain) return asks.map(() => ({ answer: "elsewhere" }));
  const h = held(inner, ws);
  const self = lock instanceof CoreError ? null : me(lock, signerOf(inner));
  // (this device's box certificate the lock vouches for, its key the one kept here: as the `vaults` topic's setUp)
  let setUp: boolean | undefined;
  const isSetUp = (): boolean => {
    if (setUp !== undefined) return setUp;
    if (lock instanceof CoreError) return (setUp = false);
    const cert = self !== null ? h.boxes[self.device] : undefined;
    return (setUp = cert !== undefined && certOwner(lock, cert) !== null && cert.box === mem(inner).box);
  };
  return asks.map(({ request, save }): AskAnswer => {
    if (save) return { answer: !plain && !isSetUp() ? "setUp" : notHere(h.requests[request], self?.device ?? null, mem(inner).box ?? null) ? "notHere" : "approve" };
    const r = h.requests[request];
    const lasts =
      r === undefined
        ? "chat"
        : r.vault === PLAIN
          ? (h.plain[r.item]?.listing?.lasts ?? h.plainLasts?.lasts ?? "chat")
          : (items(inner, ws, r.vault)[r.item]?.listing?.lasts ?? h.vaults[r.vault]?.lasts ?? "chat");
    return { answer: "approve", lasts };
  });
}

/// The workspace's lock checked, and this device's certificate in it, as they come (lock.ts, as the lock is read): what
/// a chat's vault cards are answered by is there as the chat opens, not checked then (a chat opens by looking up what
/// it shows: test/chat-open-lookup.test.ts).
export function vaultCome(inner: Inner, ws: string): void {
  // A version told before the lock that takes it came (this device let in again): held now.
  takeLater(inner, ws);
  // (where the chain moved: what of the state took each version, as it is now)
  keepTook(inner, ws);
  timed("vault.come", () => askAnswers(inner, ws, [{ request: "", save: true }]));
  // A device confirmed in the lock whose certificate came first: given the keys unsealed here; the prompts of every
  // workspace follow the lock too.
  giveKept(inner, ws);
  // A device or member taken out who held a key of a vault of this person's own: the vault keyed anew without them.
  if (able(inner)) inner.runner.fork(Effect.ignore(new Vaults(inner, ws, null).rekeyGone(), { log: "Unhandled", message: "vaults keyed anew" }));
  lockSeen(inner).touch("prompts");
}

/// A device (its id) or a member (their sub) this device takes out of workspace `ws`'s lock as a person asked it to, here
/// and now (views/lock.ts `Lock.append`, a call's): keying anew the vaults that held a key for them is part of what they
/// did, so the box key may be read for it once, the person asked (`rekeyGone`). Nothing else keys a vault anew by asking.
export function tookOut(inner: Inner, ws: string, id: string): void {
  const out = mem(inner).out;
  let at = out.get(ws);
  if (at === undefined) out.set(ws, (at = new Set()));
  at.add(id);
}

/// The keys unsealed here given to the members' devices set up that have none (the vaults of this person's own):
/// forked, nothing asked of the person (`Vaults.giveKept`).
function giveKept(inner: Inner, ws: string): void {
  if (!able(inner)) return;
  inner.runner.fork(Effect.ignore(new Vaults(inner, ws, null).giveKept(), { log: "Unhandled", message: "vault keys given" }));
}

/// The items left under an earlier key of each vault that has any written again under its key with the keys
/// unsealed here: forked, nothing asked of the person (`Vaults.carryOn`). As a station is read again (its connection
/// opened), not as each vault or item is told: that would race the device keying a vault anew, item by item.
function carryKept(inner: Inner, ws: string): void {
  if (!able(inner)) return;
  const h = held(inner, ws);
  const ids = Object.values(h.vaults).filter((v) => !v.deleted && h.before?.[v.id] !== undefined && underEarlier(inner, ws, v).length > 0).map((v) => v.id);
  if (ids.length === 0) return;
  const vaults = new Vaults(inner, ws, null);
  inner.runner.fork(Effect.forEach(ids, (id) => Effect.ignore(vaults.carryOn(id, null), { log: "Unhandled", message: "vault items carried on" }), { discard: true }));
}

/// The items of vault `v` held here still under an earlier key than its own (not deleted).
const underEarlier = (inner: Inner, ws: string, v: Vault): Item[] => Object.values(items(inner, ws, v.id)).filter((i) => !i.deleted && i.epoch < v.epoch);

/// The `lockPrompts` topic's `asks` (views/lock.ts promptsView: the topic every page has open, and every recorded
/// run of the app asks; a topic of its own would be asked by none of them): in every workspace of the person's, the
/// members' devices set up (their certificates the lock vouches for) that hold no key to a vault of this person's own
/// that this device holds the key to (so can give it: `vault.addDevice {vault, device}`), the latest asking first; not
/// those put away (`vault.hidePrompt`), until they ask again (`vault.ask`: a certificate published anew). None where
/// this app keeps no keys.
export function vaultAsks(inner: Inner): J[] {
  const asks: J[] = [];
  if (!able(inner)) return asks;
  const now = clockOf(inner);
  for (const ws of workspaceIds(inner.views?.ok({ topic: "workspaces" }))) {
    const lock = lockOf(inner, ws);
    if (lock instanceof CoreError) continue;
    const self = me(lock, signerOf(inner));
    if (self === null) continue;
    const h = held(inner, ws);
    const vouched = certs(inner, ws, lock);
    const mine = vouched.find((c) => c.device === self.device);
    if (mine === undefined) continue;
    const folded = stateOf(inner, ws);
    for (const v of Object.values(h.vaults)) {
      if (v.deleted || !trusted(lock, v) || v.owner !== self.sub) continue;
      const keyed = new Map(v.keys.map((k) => [k.cert.device, k.cert.box]));
      if (keyed.get(self.device) !== mine.box) continue;
      for (const c of vouched) {
        if (!v.members.includes(c.sub) || keyed.get(c.device) === c.box || (h.hidden[c.device] ?? -1) >= c.at) continue;
        const d = folded.devices.get(c.device);
        asks.push({
          workspace: ws, workspaceName: workspaceName(inner, ws), vault: v.id, vaultName: v.name, device: c.device,
          deviceText: deviceText({ kind: str(d?.kind) ?? "app", label: str(d?.label) ?? "" }), at: c.at, atText: str(stamp(c.at * 1000, now).ago) ?? "",
        });
      }
    }
  }
  asks.sort((a, b) => b.at - a.at || (a.device < b.device ? -1 : 1));
  return asks;
}

/// The `vaults` topic.
export function vaultsView(inner: Inner, ws: string): J {
  const h = held(inner, ws);
  const lock = lockOf(inner, ws);
  const m = mem(inner);
  const sub = inner.workspaces.owner(ws);
  const people = new Map<string, J>(arr(get(view(inner, ws), "members")).map((p) => [p.sub, p]));
  const nameOf = (s: string) => str(get(people.get(s), "name")) || str(get(people.get(s), "email")) || s;
  const stationName = new Map(stationsOf(inner, ws).map((s) => [s.id, s.name]));
  const base = { available: able(inner), locked: !(lock instanceof CoreError), canSign: false, setUp: false, vaults: [] as J[], requests: [] as J[], refused: Object.entries(h.refused).map(([id, code]) => ({ station: id, name: stationName.get(id) ?? "", code })) };
  const plainItems = Object.values(h.plain).filter((i) => !i.deleted);
  const requestRow = (r: Request, itemName: string | null, vaultName: string, lasts: Scope) => ({
    id: r.id, vault: r.vault, vaultName, item: r.item, itemName, lasts,
    session: r.session, chat: r.chat, station: h.asked[r.id] ?? null, mode: r.mode, reason: r.reason, command: r.command ?? null, hosts: r.hosts ?? [], at: r.at, ...(r.timeout ? { timeoutKind: r.timeout.kind, timeoutSeconds: r.timeout.seconds } : {}),
    howText: r.describe ? describeText(itemName ?? r.describe.was.name, { name: r.describe.name, about: r.describe.about, wasAbout: r.describe.was.about }) : r.save?.about ? aboutText(r.save.about) : howText(r.mode, r.hosts ?? []),
    // A secret an agent asks to keep: what kind, the account it is for, whether the person types it in.
    ...(r.save ? { save: { kind: r.save.kind, ...(r.save.username ? { username: r.save.username } : {}), ...(r.save.filename ? { filename: r.save.filename } : {}), ...(r.save.typed ? { typed: true } : {}) } } : {}),
    // An item to rename or say what it is: its name and about as they would be (and its about as it was).
    ...(r.describe ? { describe: { name: r.describe.name, about: r.describe.about, wasAbout: r.describe.was.about } } : {}),
  });
  const personal = t("core-misc.vault.personal");
  // No security mode: the plain library, one vault on the station keeping most of its items (or the first keeping one).
  if (lock instanceof CoreError) {
    const count = new Map<string, number>();
    for (const i of plainItems) count.set(i.station, (count.get(i.station) ?? 0) + 1);
    const on = [...h.plainOn].sort((a, b) => (count.get(b) ?? 0) - (count.get(a) ?? 0))[0];
    const row = on === undefined || sub === null ? [] : [{
      id: PLAIN, name: personal, owner: sub, ownerName: nameOf(sub), mine: true, members: [{ sub, name: nameOf(sub) }],
      station: on, stationName: stationName.get(on) ?? "", items: plainItems.length, devices: 0, open: true, keyed: true, missing: 0, recoverable: false, lasts: h.plainLasts?.lasts ?? "chat",
    }];
    const requests = Object.values(h.requests)
      .filter((r) => r.status === "pending" && r.vault === PLAIN)
      .sort((a, b) => a.at - b.at)
      .map((r) => requestRow(r, r.save?.name ?? r.describe?.was.name ?? h.plain[r.item]?.name ?? null, personal, h.plain[r.item]?.listing?.lasts ?? h.plainLasts?.lasts ?? "chat"));
    return { ...base, plain: true, vaults: row, requests, ...statusWords(row, requests) };
  }
  const self = me(lock, signerOf(inner));
  const vouched = certs(inner, ws, lock);
  const mine = self ? vouched.find((c) => c.device === self.device) : undefined;
  const vaults = Object.values(h.vaults)
    // (one waiting to be keyed anew too, where this device holds a key of it: readAs)
    .filter((v) => sub !== null && v.members.includes(sub) && readAs(inner, ws, lock, v, self) !== null)
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1))
    .map((v) => {
      const keyed = new Map(v.keys.map((k) => [k.cert.device, k.cert.box]));
      const all = Object.values(items(inner, ws, v.id)).filter((i) => !i.deleted);
      return {
        id: v.id, name: v.name, owner: v.owner, ownerName: nameOf(v.owner), mine: v.owner === sub,
        members: v.members.map((s) => ({ sub: s, name: nameOf(s) })),
        station: hostOf(inner, ws, v.id), stationName: stationName.get(hostOf(inner, ws, v.id)) ?? "",
        items: all.length, devices: v.keys.length, open: unlocked(inner, v),
        // Whether this device has a key to it; members' devices set up since that have none yet (its owner's device gives
        // them the key as it next has it in hand, or as asked: addDevice).
        keyed: self !== null && mine !== undefined && keyed.get(self.device) === mine.box,
        missing: vouched.filter((c) => v.members.includes(c.sub) && keyed.get(c.device) !== c.box).length,
        recoverable: v.recovery !== undefined, lasts: v.lasts ?? "chat",
        // (said only while it waits to be keyed anew: a row that does not wait is as it was)
        ...(waitingAs(inner, ws, lock, v) !== null ? { waits: waitsOn(inner, ws, v) } : {}),
      };
    });
  // (a secret to keep is told only to whom it is for: it may be meant for no vault yet)
  const requests = Object.values(h.requests)
    .filter((r) => r.status === "pending" && (r.save !== undefined || (h.vaults[r.vault] !== undefined && !h.vaults[r.vault]!.deleted && sub !== null && h.vaults[r.vault]!.members.includes(sub))))
    .sort((a, b) => a.at - b.at)
    .map((r) => {
      const listing = items(inner, ws, r.vault)[r.item]?.listing;
      return { ...requestRow(r, r.save?.name ?? r.describe?.was.name ?? listing?.name ?? null, h.vaults[r.vault]?.name ?? personal, listing?.lasts ?? h.vaults[r.vault]?.lasts ?? "chat"), ...(notHere(r, self?.device ?? null, m.box ?? null) ? { notHere: true } : {}) };
    });
  // What is left of the plain library from before security mode, to be moved into the person's vault.
  return { ...base, canSign: self !== null, setUp: mine !== undefined && mine.box === m.box, vaults, requests, ...statusWords(vaults, requests), ...(plainItems.length > 0 ? { plainLeft: plainItems.length } : {}) };
}

const clockOf = (inner: Inner) => {
  const now = inner.host.nowMs();
  return { now, offsetMin: inner.host.utcOffsetMin(now) };
};

/// A vault's uses (any station's, for the plain library), the latest first, as the pages show them.
function usesOf(inner: Inner, ws: string, vault: string): J[] {
  const h = held(inner, ws);
  const clock = clockOf(inner);
  return Object.entries(h.uses)
    .filter(([k]) => k.slice(k.indexOf("/") + 1) === vault)
    .flatMap(([k, list]) => list.map((u) => ({ ...u, station: k.slice(0, k.indexOf("/")) })))
    .sort((a, b) => b.at - a.at)
    .map((u) => ({
      item: u.item, at: stamp(u.at * 1000, clock), session: u.session, station: u.station, chatTitle: u.chatTitle, mode: u.mode, command: u.command, hosts: u.hosts,
      // how, in a line: the command it ran (and its way), else how it was given
      howText: typeof u.command === "string" && u.command !== "" ? `${u.command} · ${modeText(u.mode)}` : howText(u.mode, u.hosts ?? []),
      ...(u.denied ? { denied: true } : {}),
    }));
}

/// The `vaultUses` topic.
export function usesView(inner: Inner, ws: string, vault: string, item: string): J {
  return { item, uses: usesOf(inner, ws, vault).filter((u) => u.item === item).map(({ item: _, ...u }) => u) };
}

/// The last use of each item of a vault (granted ones only: a refusal is no use).
function lastUses(inner: Inner, ws: string, vault: string): Map<string, J> {
  const last = new Map<string, J>();
  for (const u of usesOf(inner, ws, vault)) if (!u.denied && !last.has(u.item)) last.set(u.item, (({ item: _, ...rest }) => rest)(u));
  return last;
}

/// The plain library's items, as a vault's (their fields only when opened).
function plainItemsView(inner: Inner, ws: string): J {
  const last = lastUses(inner, ws, PLAIN);
  const list = Object.values(held(inner, ws).plain)
    .filter((i) => !i.deleted)
    .map((i) => ({
      id: i.id, version: i.version, at: i.at, name: i.name, kind: i.kind, ...(i.notes ? { about: i.notes } : {}),
      listed: i.listing !== undefined, modes: i.listing?.modes ?? [], hosts: i.listing?.hosts ?? [], env: i.listing?.env ?? null, lasts: i.listing?.lasts ?? null,
      ...(last.has(i.id) ? { lastUse: last.get(i.id) } : {}),
    }))
    .map((r) => ({ ...r, ...itemWords(r, held(inner, ws).plainLasts?.lasts) }))
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1));
  return { vault: PLAIN, name: t("core-misc.vault.personal"), open: true, items: list };
}

/// The `vaultItems` topic: a vault's items, their names once it is unlocked here (else the listing's, if any).
export function itemsView(inner: Inner, ws: string, id: string): J {
  if (id === PLAIN) return plainItemsView(inner, ws);
  const last = lastUses(inner, ws, id);
  const v = held(inner, ws).vaults[id];
  const lock = lockOf(inner, ws);
  // (one waiting to be keyed anew too, where this device holds a key of it: readAs)
  if (!v || lock instanceof CoreError || readAs(inner, ws, lock, v, me(lock, signerOf(inner))) === null) return { vault: id, name: "", open: false, items: [] };
  const key = unlocked(inner, v) ? mem(inner).keys.get(keyOf(v))!.key : null;
  const list = Object.values(items(inner, ws, id))
    .filter((i) => !i.deleted)
    .map((i) => {
      let plain: Plain | null = null;
      if (key && i.epoch === v.epoch) {
        try {
          plain = JSON.parse(new TextDecoder().decode(decrypt(key, i.ct, itemContext(ws, id, i.id, i.version, i.epoch)))) as Plain;
        } catch {
          plain = null;
        }
      }
      return {
        id: i.id, version: i.version, at: i.at,
        name: str(plain?.name) ?? i.listing?.name ?? null, kind: str(plain?.kind) ?? i.listing?.kind ?? null,
        ...((str(plain?.notes) || i.listing?.about) ? { about: str(plain?.notes) || i.listing?.about } : {}),
        listed: i.listing !== undefined, modes: i.listing?.modes ?? [], hosts: i.listing?.hosts ?? [], env: i.listing?.env ?? null, lasts: i.listing?.lasts ?? null,
        ...(last.has(i.id) ? { lastUse: last.get(i.id) } : {}),
      };
    })
    .map((r) => ({ ...r, ...itemWords(r, v.lasts) }))
    .sort((a, b) => ((a.name ?? "") < (b.name ?? "") ? -1 : (a.name ?? "") > (b.name ?? "") ? 1 : a.id < b.id ? -1 : 1));
  return { vault: id, name: v.name, open: key !== null, items: list };
}

// ── security mode turned off ( 一个库) ──

/// What the person's own vaults hold, opened on this device while the lock is still on (the person asked, saying
/// `reason`, unless the vaults are unlocked; `asked` told when they were): none where this device keeps no vault keys
/// or holds none of theirs.
export function unsealOwn(inner: Inner, ws: string, reason?: string, asked?: () => void): Effect.Effect<{ plain: Plain; listing: Listing | null }[], CoreError> {
  return new Vaults(inner, ws, null).unsealOwn(reason, asked);
}

/// Those secrets written into the plain library once the lock is off: tried again a while, as the station may not have
/// heard yet that it is off (`vault_locked`). One that fails stays in the vault, seen again if security mode comes back.
export function writePlain(inner: Inner, ws: string, secrets: { plain: Plain; listing: Listing | null }[]): Effect.Effect<void> {
  const v = new Vaults(inner, ws, null);
  return Effect.forEach(secrets, (s) =>
    Effect.ignore(Effect.retry(v.putPlain(null, s.plain, s.listing), { times: 30, schedule: Schedule.spaced("2 seconds"), while: (e) => e.code === "vault_locked" || e.code === "vault_no_station" }), { log: "Unhandled", message: "vault item put" }),
  { discard: true });
}

// ── what a person does ──

function run(inner: Inner, c: Of, ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
  const v = new Vaults(inner, c.workspace, ctx);
  const p = (k: string) => str(c.params[k]) ?? "";
  switch (c.name) {
    case "state":
      return Effect.succeed(vaultsView(inner, c.workspace));
    case "lock":
      return Effect.sync(() => {
        mem(inner).keys.clear();
        changed(inner, c.workspace);
        return null;
      });
    case "setup":
      return v.setup();
    case "create":
      return v.create(p("name"), str(c.params.station));
    case "delete":
      return v.delete(p("vault"));
    case "addDevice":
      return v.addDevice(p("vault"), str(c.params.device));
    case "ask":
      return v.ask();
    case "hidePrompt":
      return v.hidePrompt(p("device"), typeof c.params.at === "number" ? c.params.at : null);
    case "prompts":
      return Effect.succeed({ asks: vaultAsks(inner) });
    case "putItem":
      return p("vault") === PLAIN ? v.putPlain(str(c.params.id), c.params.plain, c.params.listing) : v.putItem(p("vault"), str(c.params.id), c.params.plain, c.params.listing);
    case "deleteItem":
      return p("vault") === PLAIN ? v.deletePlain(p("item")) : v.deleteItem(p("vault"), p("item"));
    case "open":
      // (with its fields as its page shows them, and its kind in a word)
      return (held(inner, c.workspace).plain[p("item")] ? v.openPlain(p("item")) : v.open(p("item"))).pipe(
        Effect.map((o) => ({ ...(o as J), shown: shownFields(get(o, "plain")), kindText: kindText(get(get(o, "plain"), "kind")) })),
      );
    case "migrate":
      return v.migrate();
    case "recover":
      return v.recover(p("words"));
    case "approve":
      return v.approve(p("request"), (str(c.params.scope) ?? "once") as Scope, c.params.typed, c.params.timeout);
    case "deny":
      return v.deny(p("request"));
    case "setLasts":
      return v.setLasts(p("vault"), p("lasts"));
    default:
      return Effect.fail(CoreError.invalid(`no vault call ${c.name}`));
  }
}

const KINDS = ["token", "ssh_key", "login", "file", "browser"];
/// The most an item's about may be, its characters (the station's ABOUT_MOST).
const ABOUT_MOST = 2000;
const MODES = ["proxy", "ssh", "env", "file", "browser"];
/// The most a file kept may be, its bytes (the station's FILE_MOST): one credential's file, not a store of files.
const FILE_MOST = 64 * 1024;

/// Why a file's fields are not one (its content its bytes in base64, FILE_MOST of them at most; its name a name), or
/// null.
function fileProblem(fields: Record<string, string>): CoreError | null {
  const bytes = fileBytes(fields.content ?? "");
  if (bytes === null || bytes.length === 0) return CoreError.invalid("a file's content is its bytes in base64");
  if (bytes.length > FILE_MOST) return new CoreError("vault_file_too_big", t("core-misc.vault.fileTooBig", { most: "64 KB" }));
  const name = fields.filename;
  if (name !== undefined && (name.length > 200 || /[/\\\0]/.test(name) || name === "." || name === "..")) return CoreError.invalid("a file's name is a name, not a path");
  return null;
}

/// An item's plaintext as a call gives it: its kind and name, its fields as words.
function plainOf(v: unknown): Plain {
  if (!isObject(v) || !KINDS.includes(v.kind as string) || typeof v.name !== "string") throw CoreError.invalid("plain: {kind: token|ssh_key|login|file|browser, name, fields, domains, notes}");
  const fields: Record<string, string> = {};
  for (const [k, x] of Object.entries(isObject(v.fields) ? v.fields : {})) if (typeof x === "string") fields[k] = x;
  const bad = v.kind === "file" ? fileProblem(fields) : null;
  if (bad !== null) throw bad;
  return { kind: v.kind as Plain["kind"], name: v.name, fields, domains: arr(v.domains).filter((d) => typeof d === "string"), notes: typeof v.notes === "string" ? v.notes : "" };
}

function listingOf(v: unknown): Listing | undefined {
  if (v === undefined || v === null) return undefined;
  if (!isObject(v) || typeof v.name !== "string" || !KINDS.includes(v.kind as string)) throw CoreError.invalid("listing: {name, kind, modes, hosts, env?}");
  const modes = arr(v.modes).filter((m) => MODES.includes(m));
  const lasts = SCOPES.find((s) => s === v.lasts);
  const about = typeof v.about === "string" ? v.about.trim() : "";
  if (about.length > ABOUT_MOST) throw new CoreError("vault_about_long", t("core-misc.vault.aboutTooLong", { most: String(ABOUT_MOST) }));
  return { name: v.name, kind: v.kind as Listing["kind"], modes, hosts: arr(v.hosts).filter((x) => typeof x === "string"), ...(typeof v.env === "string" ? { env: v.env } : {}), ...(lasts ? { lasts } : {}), ...(about ? { about } : {}) };
}

/// What the person typed in for a secret an agent asked to keep (`typed: {secret, username?}`; a file picked, `{secret:
/// its bytes in base64, filename}`), as the item's fields: as the vault's editor writes them (a token's trimmed, a
/// private key's ending in its line, a password as typed; a login's account the agent's, else the one typed; a file's
/// name the one the agent gave, else its own); undefined when there is no secret in it, why not where a file is not one.
function typedFields(s: Save, typed: unknown): Record<string, string> | CoreError | undefined {
  const secret = isObject(typed) && typeof typed.secret === "string" ? typed.secret : "";
  if (secret.trim() === "") return undefined;
  if (s.kind === "file") {
    const filename = s.filename ?? (isObject(typed) && typeof typed.filename === "string" ? typed.filename.trim() : "");
    const fields = { content: secret, ...(filename ? { filename } : {}) };
    return fileProblem(fields) ?? fields;
  }
  if (s.kind === "token") return { value: secret.trim() };
  if (s.kind === "ssh_key") return { private_key: secret.trim() + "\n", ...(s.public_key ? { public_key: s.public_key } : {}) };
  const username = s.username ?? (isObject(typed) && typeof typed.username === "string" ? typed.username.trim() : "");
  return { ...(username ? { username } : {}), password: secret };
}

class Vaults {
  readonly #inner: Inner;
  readonly ws: string;
  readonly #ctx: SpanContext | null;

  constructor(inner: Inner, ws: string, ctx: SpanContext | null) {
    this.#inner = inner;
    this.ws = ws;
    this.#ctx = ctx;
  }

  #station(station: string, method: string, path: string, body: unknown) {
    return this.#inner.stations.requests.call(new StationAddr(this.ws, station), method, path, body, { ctx: this.#ctx });
  }

  /// What every vault call needs: an app keeping keys, the workspace's lock (checked), this app's signing key in it.
  #ready(): Effect.Effect<{ lock: Checked; signer: Signer; self: { device: string; sub: string } }, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      if (!able(inner)) return yield* fail("vault_unavailable", t("core-misc.vault.unavailable"));
      const lock = lockOf(inner, self.ws);
      if (lock instanceof CoreError) return yield* Effect.fail(lock);
      const signer = yield* Signer.load(inner.host);
      const who = signer ? me(lock, signer.id) : null;
      // (in the lock, signing with this app's key, but put in under this person's name by someone else)
      if (signer && !who && [...lock.devices.values()].some((d) => d.kind === "app" && d.sign_key === signer.id)) return yield* fail("vault_not_own", t("core-misc.vault.notOwn"));
      if (!signer || !who) return yield* fail("vault_not_signer", t("core-misc.vault.notSigner"));
      return { lock, signer, self: who };
    });
  }

  /// Vault `id` to be changed: one waiting to be keyed anew (`waitingAs`) is refused, saying the station it waits for.
  #vault(lock: Checked, id: string): Effect.Effect<Vault, CoreError> {
    const v = held(this.#inner, this.ws).vaults[id];
    if (!v || v.deleted) return fail("vault_unknown", t("core-misc.vault.unknown"));
    if (trusted(lock, v)) return Effect.succeed(v);
    if (waitingAs(this.#inner, this.ws, lock, v) !== null) return Effect.fail(waitingError(this.#inner, this.ws, v));
    return fail("vault_unknown", t("core-misc.vault.unknown"));
  }

  /// Vault `id` to have an item written in it by this device (`who`): `#vault`, but one waiting to be keyed anew whose
  /// owner this device's person is, its key in hand here, is keyed anew first (`#rekey`, awaited: the key in hand only,
  /// never the box key read for it) and then written in. The lead's decision, 2026-11-14 (the locks' end to end on real
  /// stations: an item opened, so its vault's key in hand and the keying anew set going, then written at once, was
  /// refused `vault_waiting`, telling the owner to wait for their own device). Any other device, or none in hand: as
  /// `#vault` says.
  #writable(lock: Checked, id: string, who: { sub: string; device: string }): Effect.Effect<Vault, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const v = held(inner, self.ws).vaults[id];
      const inHand = v !== undefined && (mem(inner).keys.get(keyOf(v))?.until ?? 0) > inner.host.nowMs();
      if (v !== undefined && !v.deleted && !trusted(lock, v) && v.owner === who.sub && inHand && v.keys.some((k) => k.cert.device === who.device) && waitingAs(inner, self.ws, lock, v) !== null) {
        // (a station that takes no write keys nothing anew: waited for a while, then refused as before, naming it)
        yield* Effect.timeoutOption(self.#rekey(v.id, v.seq), REKEY_WAIT_MS); // timer: a deadline
      }
      return yield* self.#vault(lock, id);
    });
  }

  /// Vault `id` to be read, and the lock it is read by (`readAs`: one waiting to be keyed anew, as the lock took it).
  #readable(lock: Checked, id: string, self: { device: string }): Effect.Effect<{ v: Vault; as: Checked }, CoreError> {
    const v = held(this.#inner, this.ws).vaults[id];
    const as = v === undefined ? null : readAs(this.#inner, this.ws, lock, v, self);
    if (!v || as === null) return fail("vault_unknown", t("core-misc.vault.unknown"));
    return Effect.succeed({ v, as });
  }

  /// This device's box key, read from the secure storage (the person asked, saying `reason`).
  #boxKey(reason: string): Effect.Effect<Uint8Array, CoreError> {
    const inner = this.#inner;
    return Effect.gen(function* () {
      const priv = yield* Effect.mapError(inner.host.secureGet!(BOX_KEY, { user: true, reason }), (e) => CoreError.refused(e, "vault_refused"));
      if (priv === null || priv.length !== 32) return yield* fail("vault_not_set_up", t("core-misc.vault.notSetUp"));
      return priv;
    });
  }

  /// A vault's key: kept unsealed a while, else unsealed with this device's box key (the person asked); `fresh`: asked
  /// even when it is kept (an agent's grant). In hand, it is given on to the members' devices set up since that have
  /// none (`#give`: its owner's device only), unless the call is that giving itself (`give` false).
  #key(v: Vault, self: { device: string }, fresh: boolean, reason: string, give = true, unsealed?: (priv: Uint8Array) => void): Effect.Effect<Uint8Array, CoreError> {
    const inner = this.#inner;
    const ws = this.ws;
    const self_ = this;
    return Effect.tap(
      Effect.gen(function* () {
        const kept = mem(inner).keys.get(keyOf(v));
        if (!fresh && kept && kept.until > inner.host.nowMs()) return kept.key;
        const mine = v.keys.find((k) => k.cert.device === self.device);
        if (!mine) return yield* fail("vault_no_key", t("core-misc.vault.noKey"));
        const priv = yield* self_.#boxKey(reason);
        if (boxPublic(priv) !== mine.cert.box) return yield* fail("vault_no_key", t("core-misc.vault.noKey"));
        const key = yield* Effect.try({ try: () => openSeal(priv, mine.wrapped, keyContext(ws, v.id, v.epoch)), catch: asCoreError });
        unsealed?.(priv);
        self_.#keep(v, key);
        // (in hand for what the person does: a vault of theirs waiting to be keyed anew is keyed anew with it now)
        inner.runner.fork(Effect.ignore(self_.rekeyGone(), { log: "Unhandled", message: "vaults keyed anew" }));
        return key;
      }),
      (key) => Effect.sync(() => void (give && inner.runner.fork(Effect.ignore(self_.#give(v.id, v.epoch, key, null), { log: "Unhandled", message: "vault key given" })))),
    );
  }

  /// What runs on vault `id` one at a time, each after the one before: a giving of its key, a keying anew, its items
  /// carried on to its key.
  #giving(id: string) {
    const giving = mem(this.#inner).giving;
    let one = giving.get(id);
    if (one === undefined) giving.set(id, (one = Semaphore.makeUnsafe(1)));
    return one.withPermits(1);
  }

  /// The members' devices set up (their box certificates the lock vouches for) that vault `v` has no key for (or
  /// `device` alone).
  #missing(lock: Checked, v: Vault, device: string | null): Vouched[] {
    const keyed = new Map(v.keys.map((k) => [k.cert.device, k.cert.box]));
    return certs(this.#inner, this.ws, lock).filter((c) => v.members.includes(c.sub) && keyed.get(c.device) !== c.box && (device === null || c.device === device));
  }

  /// Vault `id`'s key (of `epoch`, unsealed here) sealed for the members' devices set up since it was keyed (or
  /// `device` alone): its next version, which its owner signs (another member's device gives none). How many it gave.
  #give(id: string, epoch: number, key: Uint8Array, device: string | null): Effect.Effect<number, CoreError> {
    const self = this;
    // One giving of a vault at a time (two would write the same seq, the second refused), each after the one before,
    // reading the vault and the certificates anew: a certificate heard while a version is written is given to next,
    // not dropped (review of #3624).
    return this.#giving(id)(
      Effect.gen(function* () {
        const inner = self.#inner;
        const { lock, signer, self: who } = yield* self.#ready();
        // (one waiting to be keyed anew is given to no one till it is: a key unsealed to read it gives nothing; asked
        // for by the person, addDevice says why)
        const was = held(inner, self.ws).vaults[id];
        if (was !== undefined && waitingAs(inner, self.ws, lock, was) !== null) return 0;
        const v = yield* self.#vault(lock, id);
        if (v.owner !== who.sub || v.epoch !== epoch) return 0;
        const add = self.#missing(lock, v, device);
        const { keys: kept, freshened } = self.#freshened(lock, v);
        if (add.length === 0 && !freshened) return 0;
        const devices = new Set(add.map((c) => c.device));
        const context = keyContext(self.ws, v.id, v.epoch);
        const keys = [
          ...kept.filter((k) => !devices.has(k.cert.device)),
          ...add.map((c) => {
            const cert = bare(c);
            const eph = new Uint8Array(32);
            inner.host.randomBytes(eph);
            return { cert, wrapped: sealWith(cert.box, key, context, eph) };
          }),
        ];
        const { sig: _, ...rest } = v;
        // (refused as not a vault, by a station from before this device's checks: not tried again for this version,
        // as the next certificate or read comes, but as the vault moves on)
        yield* Effect.tapError(self.#putVault(sign({ ...rest, seq: v.seq + 1, keys, at: nowS(inner) }, TAG.vault, signer), hostOf(inner, self.ws, v.id)), (e) =>
          Effect.sync(() => void (e.code === "vault_invalid" && mem(inner).refused.set(v.id, v.seq))));
        return add.length;
      }),
    );
  }

  /// The vault's keys with each device's certificate the latest the lock vouches for of the same box key, where it
  /// is signed by another key (the device back in the lock under a new signing key: its old certificate no longer
  /// checks out against the lock, and a station checks every certificate of a version it is given); whether any was
  /// replaced. One published anew under the same key (`vault.ask`) changes nothing. The key wrapped stays: it is
  /// sealed to the box key, which is the same.
  #freshened(lock: Checked, v: Vault): { keys: Vault["keys"]; freshened: boolean } {
    const latest = new Map(certs(this.#inner, this.ws, lock).map((c) => [c.device, bare(c)]));
    let freshened = false;
    const keys = v.keys.map((k) => {
      const c = latest.get(k.cert.device);
      if (c === undefined || c.box !== k.cert.box || c.sig.key === k.cert.sig.key) return k;
      freshened = true;
      return { cert: c, wrapped: k.wrapped };
    });
    return { keys, freshened };
  }

  /// The keys unsealed here (UNLOCK_MS from their last use) given to the members' devices set up that have none, in
  /// the vaults of this person's own: as a device's certificate comes, or the lock names it, nothing asked of the
  /// person (a key in hand is given on, as it is whenever it is unsealed).
  giveKept(): Effect.Effect<void, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const lock = lockOf(inner, self.ws);
      if (lock instanceof CoreError) return;
      const who = me(lock, signerOf(inner));
      if (who === null) return;
      for (const v of Object.values(held(inner, self.ws).vaults)) {
        if (v.deleted || !trusted(lock, v) || v.owner !== who.sub || mem(inner).refused.get(v.id) === v.seq) continue;
        const kept = mem(inner).keys.get(keyOf(v));
        if (!kept || kept.until <= inner.host.nowMs()) continue;
        if (self.#missing(lock, v, null).length === 0 && !self.#freshened(lock, v).freshened) continue;
        yield* Effect.ignore(self.#give(v.id, v.epoch, kept.key, null), { log: "Unhandled", message: "vault key given" });
      }
    });
  }

  /// The vaults of this person's own that a device or member taken out of the lock since holds a key of (so the
  /// stations take no version of them more, rules/src/vault/vault.mbt, a key for a device not in the lock; this core
  /// reads them meanwhile and changes nothing in them: `waitingAs`) written anew: a new key under the next epoch,
  /// sealed to the members' devices the lock still vouches for, and each item written again under it, the one taken
  /// out holding no key to any of it. Only a version the lock took before (a prefix of the chain vouching for it,
  /// `waitingAs`) is so carried on, and only its items that held then. The key unsealed here, or read with this
  /// device's box key, the person asked, only where this device took out who it waits for at their asking (`tookOut`,
  /// once for that: what is done by itself asks no one). Otherwise it waits for the key unsealed here for something the
  /// person does (`#key`, which runs this then). As the lock comes; nothing done when nothing was taken out. (The locks'
  /// end to end, round 7b, the side run of 2026-11-13: a device started anew, doing nothing, read the box key each time
  /// the lock came, the vault's station not taking the write: its person asked seven times.)
  rekeyGone(): Effect.Effect<void, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const lock = lockOf(inner, self.ws);
      if (lock instanceof CoreError) return;
      const who = me(lock, signerOf(inner));
      if (who === null) return;
      // (waiting to be keyed anew: a version the lock took before, a prefix of the chain vouching for it)
      const waiting = Object.values(held(inner, self.ws).vaults).filter((v) => !v.deleted && v.owner === who.sub && !trusted(lock, v) && v.keys.some((k) => k.cert.device === who.device) && waitingAs(inner, self.ws, lock, v) !== null);
      // Those waiting for one this device took out at the person's asking, their keys not in hand: the box key read
      // once for all of them (the person asked once), each one's key unsealed with it and kept, and what they wait
      // for asked for no more (taken from `out` before the prompt, so a second keying anew as the lock comes again
      // does not ask too).
      const out = mem(inner).out.get(self.ws);
      const goneOf = (v: Vault) => [...v.keys.map((k) => k.cert.device).filter((d) => !lock.devices.has(d)), ...v.members.filter((m) => !lock.members.has(m))];
      const inHand = (v: Vault) => (mem(inner).keys.get(keyOf(v))?.until ?? 0) > inner.host.nowMs();
      const asked = out === undefined ? [] : waiting.filter((v) => !inHand(v) && goneOf(v).some((x) => out.has(x)));
      if (asked.length > 0) {
        for (const v of asked) for (const x of goneOf(v)) out!.delete(x);
        const priv = yield* self.#boxKey(t("core-misc.vault.reason.rekey", { name: asked[0]!.name }));
        for (const v of asked) {
          const mine = v.keys.find((k) => k.cert.device === who.device)!;
          const key = yield* Effect.result(Effect.try({ try: () => openSeal(priv, mine.wrapped, keyContext(self.ws, v.id, v.epoch)), catch: asCoreError }));
          if (key._tag === "Success") self.#keep(v, key.success);
        }
      }
      for (const v of waiting) yield* Effect.ignore(self.#rekey(v.id, v.seq), { log: "Unhandled", message: "vault keyed anew" });
    });
  }

  #rekey(id: string, seq: number): Effect.Effect<void, CoreError> {
    const self = this;
    return this.#giving(id)(
      Effect.gen(function* () {
        const inner = self.#inner;
        const { lock, signer, self: who } = yield* self.#ready();
        const v = held(inner, self.ws).vaults[id];
        // (written anew meanwhile, by another of the person's devices: nothing left to do here)
        if (!v || v.seq !== seq || trusted(lock, v)) return;
        // (the key unsealed here only: `rekeyGone` says when the box key is read for it)
        const kept = mem(inner).keys.get(keyOf(v));
        if (!kept || kept.until <= inner.host.nowMs()) return;
        const old = kept.key;
        const members = v.members.filter((m) => lock.members.has(m));
        const to = certs(inner, self.ws, lock).filter((c) => members.includes(c.sub));
        const epoch = v.epoch + 1;
        const key = new Uint8Array(32);
        inner.host.randomBytes(key);
        const context = keyContext(self.ws, v.id, epoch);
        const seal = (pub: string) => {
          const eph = new Uint8Array(32);
          inner.host.randomBytes(eph);
          return sealWith(pub, key, context, eph);
        };
        const recovery = to.find((c) => c.sub === v.owner && c.recovery)?.recovery;
        const { sig: _, recovery: _r, ...rest } = v;
        const next = sign({ ...rest, seq: v.seq + 1, members, epoch, keys: to.map((c) => ({ cert: bare(c), wrapped: seal(c.box) })), ...(recovery ? { recovery: seal(recovery) } : {}), at: nowS(inner) }, TAG.vault, signer);
        const nv = yield* self.#putVault(next, hostOf(inner, self.ws, v.id));
        // The key before kept a while too, not forgotten: an item not written again yet (this device stopped, a write
        // that failed) is carried on with it, nobody asked. The device taken out holds that key anyway: keeping it
        // here a while gives nothing away. (The version it was sealed in is kept as the last of its epoch, `before`.)
        self.#keep(v, old);
        self.#keep(nv, key);
        // Its items, as they held when the lock took the version before, written again under the new key.
        yield* Effect.ignore(self.#carryNow(id, null, new Map([[keyOf(v), old], [keyOf(nv), key]])), { log: "Unhandled", message: "vault items keyed anew" });
        // A device that came back meanwhile (put in the lock again as it was keyed anew) was looked at against the
        // version before, its key given for the epoch going: given the new one now (after this, as it waits its turn).
        inner.runner.fork(Effect.ignore(self.giveKept(), { log: "Unhandled", message: "vault keys given" }));
      }),
    );
  }

  /// Vault `id`'s items left under an earlier key (a keying anew stopped half-way: the device keying it closed, killed
  /// or cut off, a write that failed) written again under its key, as `#rekey` writes them; otherwise nothing would,
  /// and none of them could be opened. Only those that held when the lock took the last version of that key held here
  /// (`before`) are carried on: a version or an item a station made up is not. Any member's device with a key to the
  /// vault does it, as the rules let any member's device write an item's next version: an owner whose only device
  /// stopped half-way leaves a team's vault unreadable to no one. The keys from `known`, else unsealed here still, else
  /// unsealed with this device's box key, read at most once: the person asked, saying `ask` (`how.asked` told when they
  /// are), or read already (`how.priv`); `ask` null and none read, those of a key not to be had are left as they are.
  /// How many it wrote. Within the vault's giving (`carryOn` takes its turn; `#rekey` holds it already).
  #carryNow(id: string, ask: string | null, known?: Map<string, Uint8Array>, how: { asked?: () => void; priv?: Uint8Array } = {}): Effect.Effect<number, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const ws = self.ws;
      const { lock, signer, self: who } = yield* self.#ready();
      const v = held(inner, ws).vaults[id];
      if (!v || v.deleted || !trusted(lock, v) || !v.members.includes(who.sub) || !v.keys.some((k) => k.cert.device === who.device)) return 0;
      const left = underEarlier(inner, ws, v);
      if (left.length === 0) return 0;
      // What may be carried on, by earlier key: the items the lock took then under the last version held of it.
      const before: Record<string, Vault> = held(inner, ws).before?.[id] ?? {};
      const plan: { b: Vault; items: Item[] }[] = [];
      for (const epoch of new Set(left.map((i) => i.epoch))) {
        const b = before[epoch];
        const was = b === undefined ? null : tookAs(inner, ws, b);
        if (b === undefined || was === null) continue;
        const these = left.filter((i) => i.epoch === b.epoch && rules.item_ok_js(was, b, null, i, true, rulesCrypto) === null);
        if (these.length > 0) plan.push({ b, items: these });
      }
      // This device's box key, read once, where the person may be asked (or it was read already).
      let priv: Uint8Array | null = how.priv ?? null;
      const boxKey: Effect.Effect<Uint8Array | null, CoreError> = Effect.suspend((): Effect.Effect<Uint8Array | null, CoreError> => {
        if (priv !== null || ask === null) return Effect.succeed(priv);
        return Effect.map(self.#boxKey(ask), (p) => {
          priv = p;
          how.asked?.();
          return p;
        });
      });
      // A version's key: given, unsealed here still, else unsealed with the box key (then kept, as `#key` keeps it);
      // none where it is not to be had.
      const keyFor = (of: Vault): Effect.Effect<Uint8Array | null, CoreError> =>
        Effect.gen(function* () {
          const given = known?.get(keyOf(of));
          if (given !== undefined) return given;
          const kept = mem(inner).keys.get(keyOf(of));
          if (kept && kept.until > inner.host.nowMs()) return kept.key;
          const sealed = of.keys.find((k) => k.cert.device === who.device);
          if (sealed === undefined) return null;
          const p = yield* boxKey;
          if (p === null || boxPublic(p) !== sealed.cert.box) return null;
          let key: Uint8Array;
          try {
            key = openSeal(p, sealed.wrapped, keyContext(ws, of.id, of.epoch));
          } catch {
            return null;
          }
          self.#keep(of, key);
          return key;
        });
      const key = plan.length === 0 ? null : yield* keyFor(v);
      let wrote = 0;
      for (const { b, items: these } of key === null ? [] : plan) {
        const old = yield* keyFor(b);
        if (old === null) continue;
        for (const i of these) {
          // (one that fails stops none of the rest; one another device wrote meanwhile is read again by `#putItem`)
          yield* Effect.ignore(
            Effect.gen(function* () {
              const plain = yield* Effect.try({ try: () => decrypt(old, i.ct, itemContext(ws, id, i.id, i.version, i.epoch)), catch: asCoreError });
              const nonce = new Uint8Array(12);
              inner.host.randomBytes(nonce);
              const version = i.version + 1;
              const ct = encryptWith(key!, plain, itemContext(ws, id, i.id, version, v.epoch), nonce);
              const item = sign({ v: 1 as const, ws, vault: id, id: i.id, version, epoch: v.epoch, ct, ...(i.listing ? { listing: i.listing } : {}), at: nowS(inner) }, TAG.item, signer);
              yield* self.#putItem(item, v);
              wrote++;
            }),
            { log: "Unhandled", message: "vault item keyed anew" },
          );
        }
      }
      // (the versions kept of the earlier keys are let go as the vault's items are next read of a station, not here:
      // `settleBefore`)
      changed(inner, ws);
      return wrote;
    });
  }

  /// Vault `id`'s items left under an earlier key carried on (`#carryNow`), in its turn after a giving or a keying anew
  /// under way: a read that carries waits for it, not racing it item by item.
  carryOn(id: string, ask: string | null, known?: Map<string, Uint8Array>, how: { asked?: () => void; priv?: Uint8Array } = {}): Effect.Effect<number, CoreError> {
    return this.#giving(id)(this.#carryNow(id, ask, known, how));
  }

  /// A vault's key kept unsealed UNLOCK_MS from now, then forgotten (and the pages told).
  #keep(v: Vault, key: Uint8Array): void {
    const inner = this.#inner;
    const until = inner.host.nowMs() + UNLOCK_MS;
    mem(inner).keys.set(keyOf(v), { key, until });
    changed(inner, this.ws);
    inner.runner.fork(
      Effect.andThen(
        Effect.sleep(UNLOCK_MS),
        Effect.sync(() => {
          const k = mem(inner).keys.get(keyOf(v));
          if (k && k.until <= inner.host.nowMs()) mem(inner).keys.delete(keyOf(v));
          changed(inner, this.ws);
        }),
      ),
    );
  }

  /// A vault's version taken by its station, held here as it is.
  #putVault(next: Vault, station: string): Effect.Effect<Vault, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const said = yield* self.#station(station, "PUT", "/vault/vaults", next);
      const v = (get(said, "vault") as Vault | undefined) ?? next;
      change(self.#inner, self.ws, (h) => holds(h, v, station, null, fits(self.#inner, self.ws)));
      spreadAll(self.#inner, self.ws);
      return v;
    });
  }

  /// This device set up for the vault in this workspace: its box key (made once, in the secure storage), its
  /// certificate signed and published to the workspace's stations. The person's recovery words the first time: one of
  /// their devices that published a recovery key already gives it (none are made then). Their own vault made (`made`)
  /// only when they have none, as the stations hold them now: a device set up after the first is given that one's
  /// key by a device that has it (`#give`), never a second vault.
  setup(): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const { lock, signer, self: who } = yield* self.#ready();
      // The box key made once (its public half kept beside, read without asking the person).
      const had = yield* Effect.orElseSucceed(inner.host.storageGet(BOX_PUB), () => null);
      let pub = had ? new TextDecoder().decode(had) : null;
      if (pub === null) {
        const priv = new Uint8Array(32);
        inner.host.randomBytes(priv);
        pub = boxPublic(priv);
        yield* Effect.mapError(inner.host.secureSet!(BOX_KEY, priv, { user: true }), (e) => CoreError.refused(e, "vault_refused"));
        yield* Effect.mapError(inner.host.storageSet(BOX_PUB, utf8(pub)), asCoreError);
      }
      mem(inner).box = pub;
      const theirs = certs(inner, self.ws, lock).filter((c) => c.sub === who.sub && typeof c.recovery === "string").sort((a, b) => b.at - a.at)[0];
      let words: string | null = null;
      let recovery = theirs?.recovery ?? null;
      if (recovery === null) {
        const entropy = new Uint8Array(32);
        inner.host.randomBytes(entropy);
        words = toWords(entropy);
        recovery = recoveryPair(entropy).pub;
      }
      const stations = yield* self.#publish(sign({ v: 1 as const, ws: self.ws, device: who.device, box: pub, recovery, at: nowS(inner) }, TAG.box, signer));
      for (const s of stations) yield* Effect.ignore(readStation(inner, `${self.ws}/${s}`), { log: "Unhandled", message: "vault station read" });
      // (not made, it is offered on the page as when there is none; one waiting to be keyed anew is one)
      const own = Object.values(held(inner, self.ws).vaults).some((v) => !v.deleted && (trusted(lock, v) || waitingAs(inner, self.ws, lock, v) !== null) && v.owner === who.sub);
      const made = own ? null : yield* Effect.orElseSucceed(Effect.map(self.create(t("core-misc.vault.personal"), null), (m) => (m as { id: string }).id), () => null);
      return { words, device: who.device, stations, made };
    });
  }

  /// This device's certificate published to the workspace's stations (each told: the members' devices hear of it);
  /// the stations that took it (none: refused).
  #publish(cert: BoxCert): Effect.Effect<string[], CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      // (done once one took it: a station gone silent is not waited on, the others still told it; lock.ts answersOf)
      const published = yield* answersOf(inner, stationsOf(inner, self.ws).map((s) => Effect.as(self.#station(s.id, "PUT", "/vault/boxes", cert), s.id)), tookOrRefused);
      const took = published.flatMap((r) => (r._tag === "Success" ? [r.success] : []));
      if (took.length === 0) return yield* fail("vault_no_station", t("core-misc.vault.noStation"));
      change(inner, self.ws, (h) => void (h.boxes[cert.device] = cert));
      return took;
    });
  }

  /// This device asking for the keys it lacks (set up already): its certificate published anew, dated now, so that
  /// the owner's devices hearing of it give it the keys they hold unsealed, or prompt for it again where it was put
  /// away (`lockPrompts` `asks`: what is shown is by the certificate's date). How many stations were told.
  ask(): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const { lock, signer, self: who } = yield* self.#ready();
      const here = certs(inner, self.ws, lock).find((c) => c.device === who.device);
      const had = yield* Effect.orElseSucceed(inner.host.storageGet(BOX_PUB), () => null);
      const pub = had ? new TextDecoder().decode(had) : null;
      if (!here || pub === null || here.box !== pub) return yield* fail("vault_not_set_up", t("core-misc.vault.notSetUp"));
      const { sig: _s, ...rest } = bare(here);
      const stations = yield* self.#publish(sign({ ...rest, at: Math.max(nowS(inner), here.at + 1) }, TAG.box, signer));
      return { asked: stations.length };
    });
  }

  /// A device's prompt for a key put away on this device, until it asks again (a certificate dated later than the
  /// one shown, `at`: not one that came while the prompt was up).
  hidePrompt(device: string, at: number | null): Effect.Effect<unknown, CoreError> {
    const inner = this.#inner;
    const now = held(inner, this.ws).boxes[device]?.at;
    if (now === undefined) return Effect.fail(CoreError.invalid("device"));
    const hid = at !== null && at < now ? at : now;
    change(inner, this.ws, (h) => void (h.hidden[device] = hid));
    return Effect.succeed(null);
  }

  /// A vault of one's own, on `station` (the first of the workspace's that holds vaults, when not said): its key sealed
  /// to each of one's devices set up, and to one's recovery key.
  create(name: string, station: string | null): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      if (name.trim() === "") return yield* Effect.fail(CoreError.invalid("name"));
      const { lock, signer, self: who } = yield* self.#ready();
      const mine = certs(inner, self.ws, lock).filter((c) => c.sub === who.sub);
      const here = mine.find((c) => c.device === who.device);
      if (!here) return yield* fail("vault_not_set_up", t("core-misc.vault.notSetUp"));
      const h = held(inner, self.ws);
      const on = station ?? stationsOf(inner, self.ws).find((s) => h.refused[s.id] === undefined)?.id;
      if (!on) return yield* fail("vault_no_station", t("core-misc.vault.noStation"));
      const id = `v_${ulid(inner.host)}`;
      const key = new Uint8Array(32);
      inner.host.randomBytes(key);
      const context = keyContext(self.ws, id, 0);
      const seal = (pub: string) => {
        const eph = new Uint8Array(32);
        inner.host.randomBytes(eph);
        return sealWith(pub, key, context, eph);
      };
      const recovery = here.recovery ?? mine.find((c) => c.recovery)?.recovery;
      const next = sign(
        { v: 1 as const, ws: self.ws, id, seq: 0, owner: who.sub, name: name.trim(), members: [who.sub], epoch: 0, keys: mine.map((c) => ({ cert: bare(c), wrapped: seal(c.box) })), ...(recovery ? { recovery: seal(recovery) } : {}), at: nowS(inner) },
        TAG.vault,
        signer,
      );
      const v = yield* self.#putVault(next, on);
      self.#keep(v, key);
      return { id, station: on };
    });
  }

  /// A vault of one's own deleted: its last version, which its owner signs, sealed to no one under a new epoch (the
  /// stations let its items go, and bring it to those holding an older one); the person asked first when it holds any
  /// item, which goes with it.
  delete(id: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const { lock, signer, self: who } = yield* self.#ready();
      const v = yield* self.#vault(lock, id);
      if (v.owner !== who.sub) return yield* fail("vault_not_owner", t("core-misc.vault.notOwnerDelete"));
      const n = Object.values(items(inner, self.ws, v.id)).filter((i) => !i.deleted).length;
      if (n > 0) yield* askPerson(inner, t("core-misc.vault.reason.delete", { name: v.name }), "vault_refused");
      const { sig: _, recovery: _r, ...rest } = v;
      yield* self.#putVault(sign({ ...rest, seq: v.seq + 1, epoch: v.epoch + 1, keys: [], deleted: true as const, at: nowS(inner) }, TAG.vault, signer), hostOf(inner, self.ws, v.id));
      mem(inner).keys.delete(keyOf(v));
      inner.data.forgetRecord("vaultItems", `${self.ws}/${v.id}`);
      changed(inner, self.ws);
      return { deleted: v.id };
    });
  }

  /// The longest grant of a vault's items that say none: a new version its owner signs; the plain library's told to
  /// each station keeping it (the latest word kept on each).
  setLasts(id: string, lasts: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const scope = SCOPES.find((s) => s === lasts);
      if (!scope) return yield* Effect.fail(CoreError.invalid("lasts: once, hour or chat"));
      if (id === PLAIN) {
        const at = nowS(inner);
        const told = yield* answersOf(inner, held(inner, self.ws).plainOn.map((s) => self.#station(s, "PUT", "/vault/plain/lasts", { lasts: scope, at })), tookOrRefused);
        if (!told.some((r) => r._tag === "Success")) return yield* fail("vault_no_station", t("core-misc.vault.noStation"));
        change(inner, self.ws, (h) => void (h.plainLasts = { lasts: scope, at }));
        return { lasts: scope };
      }
      const { lock, signer, self: who } = yield* self.#ready();
      const v = yield* self.#vault(lock, id);
      if (v.owner !== who.sub) return yield* fail("vault_not_owner", t("core-misc.vault.notOwnerLasts"));
      const { sig: _, ...rest } = v;
      yield* self.#putVault(sign({ ...rest, seq: v.seq + 1, lasts: scope, at: nowS(inner) }, TAG.vault, signer), hostOf(inner, self.ws, v.id));
      return { lasts: scope };
    });
  }

  /// The vault's key sealed for members' devices set up since it was keyed (or `device` alone): its owner signs. (Done
  /// by itself whenever the owner's device unseals the key: this for when it has not been since.)
  addDevice(id: string, device: string | null): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const { lock, self: who } = yield* self.#ready();
      const v = yield* self.#vault(lock, id);
      if (v.owner !== who.sub) return yield* fail("vault_not_owner", t("core-misc.vault.notOwner"));
      if (self.#missing(lock, v, device).length === 0) return { added: 0 };
      const key = yield* self.#key(v, who, false, t("core-misc.vault.reason.unlock", { name: v.name }), false);
      return { added: yield* self.#give(v.id, v.epoch, key, device) };
    });
  }

  /// An item written: encrypted under the vault's key, the version after the one held (a new one's 0), signed.
  putItem(vault: string, id: string | null, plain: unknown, listing: unknown): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const body = yield* Effect.try({ try: () => ({ plain: plainOf(plain), listing: listingOf(listing) }), catch: asCoreError });
      const { lock, signer, self: who } = yield* self.#ready();
      const v = yield* self.#writable(lock, vault, who);
      if (!v.members.includes(who.sub)) return yield* fail("vault_unknown", t("core-misc.vault.unknown"));
      const key = yield* self.#key(v, who, false, t("core-misc.vault.reason.unlock", { name: v.name }));
      const item = id ?? `i_${ulid(inner.host)}`;
      const prev = items(inner, self.ws, vault)[item];
      const version = prev ? prev.version + 1 : 0;
      const nonce = new Uint8Array(12);
      inner.host.randomBytes(nonce);
      const ct = encryptWith(key, utf8(JSON.stringify(body.plain)), itemContext(self.ws, vault, item, version, v.epoch), nonce);
      const next = sign({ v: 1 as const, ws: self.ws, vault, id: item, version, epoch: v.epoch, ct, ...(body.listing ? { listing: body.listing } : {}), at: nowS(inner) }, TAG.item, signer);
      return yield* self.#putItem(next, v);
    });
  }

  deleteItem(vault: string, id: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const { lock, signer, self: who } = yield* self.#ready();
      const v = yield* self.#writable(lock, vault, who);
      const prev = items(self.#inner, self.ws, vault)[id];
      if (!prev || prev.deleted) return yield* fail("vault_unknown", t("core-misc.vault.unknownItem"));
      const next = sign({ v: 1 as const, ws: self.ws, vault, id, version: prev.version + 1, epoch: v.epoch, deleted: true as const, ct: "", at: nowS(self.#inner) }, TAG.item, signer);
      return yield* self.#putItem(next, v);
    });
  }

  /// An item's version taken by its station; one that was not the next (another device wrote meanwhile) has the vault's
  /// items read again before it fails.
  #putItem(next: Item, v: Vault): Effect.Effect<unknown, CoreError> {
    const self = this;
    const station = hostOf(this.#inner, this.ws, v.id);
    return Effect.gen(function* () {
      const said = yield* Effect.tapError(self.#station(station, "PUT", "/vault/items", next), (e) =>
        e.code === "vault_conflict" ? Effect.ignore(readItems(self.#inner, `${self.ws}/${station}`, v.id), { log: "Unhandled", message: "vault items read" }) : Effect.void,
      );
      const item = (get(said, "item") as Item | undefined) ?? next;
      const fit = fits(self.#inner, self.ws);
      changeItems(self.#inner, self.ws, v.id, (all) => { if (newer(item, all[item.id], fit)) all[item.id] = item; });
      change(self.#inner, self.ws, (h) => {
        const at = h.on[v.id]?.[station];
        if (at !== undefined) holdsItem(at, item);
      });
      spreadAll(self.#inner, self.ws);
      return { id: item.id, version: item.version };
    });
  }

  /// The item, found in its vault, that vault, and the lock it is read by (`readAs`: one waiting to be keyed anew, as
  /// the lock took it).
  #find(lock: Checked, self: { device: string }, id: string): Effect.Effect<{ v: Vault; item: Item; as: Checked }, CoreError> {
    const h = held(this.#inner, this.ws);
    for (const v of Object.values(h.vaults)) {
      const item = items(this.#inner, this.ws, v.id)[id];
      const as = item && !item.deleted ? readAs(this.#inner, this.ws, lock, v, self) : null;
      if (item && as !== null) return Effect.succeed({ v, item, as });
    }
    return fail("vault_unknown", t("core-misc.vault.unknownItem"));
  }

  /// What an item holds: written by a member's own device in the lock, opened with its vault's key.
  #plain(lock: Checked, v: Vault, item: Item, key: Uint8Array): Effect.Effect<Uint8Array, CoreError> {
    // (as the stations take it, rules/ `itemOk`, and written under the key it is opened with)
    if (rules.item_ok_js(lock, v, null, item, true, rulesCrypto) !== null || item.epoch !== v.epoch) return fail("vault_untrusted", t("core-misc.vault.untrusted"));
    return Effect.try({ try: () => decrypt(key, item.ct, itemContext(this.ws, v.id, item.id, item.version, item.epoch)), catch: asCoreError });
  }

  open(id: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      // (a device taken out of the lock opens nothing, of a vault waiting to be keyed anew either: #ready refuses it)
      const { lock, self: who } = yield* self.#ready();
      let { v, item, as } = yield* self.#find(lock, who, id);
      // Written before its vault was keyed anew (`rekeyGone`), as held here: its station read again for the one
      // written since under the new key.
      if (item.epoch < v.epoch) {
        yield* Effect.ignore(readItems(self.#inner, `${self.ws}/${hostOf(self.#inner, self.ws, v.id)}`, v.id), { log: "Unhandled", message: "vault items read" });
        ({ v, item, as } = yield* self.#find(lock, who, id));
      }
      const name = item.listing?.name ?? v.name;
      const reason = t("core-misc.vault.reason.open", { name });
      // Still under the earlier key (its keying anew stopped half-way): carried on to the vault's key here, the person
      // asked for this device's box key where the keys are not unsealed (as opening it would); one not to be carried on
      // stays refused below (nor one of a vault waiting to be keyed anew: nothing is written into it). What fails it is
      // reading the box key, which opening it would fail on the same way: the answer, not asked again.
      if (item.epoch < v.epoch) {
        yield* self.carryOn(v.id, reason);
        ({ v, item, as } = yield* self.#find(lock, who, id));
      }
      const key = yield* self.#key(v, who, false, reason);
      // (an item of a vault waiting to be keyed anew checked against the lock as it took the vault, as what is carried
      // on is)
      const bytes = yield* self.#plain(as, v, item, key);
      return { vault: v.id, id: item.id, version: item.version, plain: JSON.parse(new TextDecoder().decode(bytes)) };
    });
  }

  /// This device keyed into the vaults the recovery words open (its person's own: their owner signs).
  recover(words: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const entropy = yield* Effect.try({ try: () => fromWords(words), catch: asCoreError });
      const { lock, signer, self: who } = yield* self.#ready();
      const here = certs(inner, self.ws, lock).find((c) => c.device === who.device);
      if (!here) return yield* fail("vault_not_set_up", t("core-misc.vault.notSetUp"));
      const { priv } = recoveryPair(entropy);
      let recovered = 0;
      let others = 0;
      // (one waiting to be keyed anew that this device would be keyed into: a version written, refused, said once the
      // others are done)
      let waited: Vault | null = null;
      for (const v of Object.values(held(inner, self.ws).vaults)) {
        const waits = waitingAs(inner, self.ws, lock, v) !== null;
        if ((!waits && !trusted(lock, v)) || !v.recovery || !v.members.includes(who.sub)) continue;
        let key: Uint8Array;
        try {
          key = openSeal(priv, v.recovery, keyContext(self.ws, v.id, v.epoch));
        } catch {
          continue;
        }
        if (v.owner !== who.sub) {
          others++;
          continue;
        }
        self.#keep(v, key);
        if (v.keys.some((k) => k.cert.device === who.device && k.cert.box === here.box)) {
          recovered++;
          continue;
        }
        if (waits) {
          waited ??= v;
          continue;
        }
        const eph = new Uint8Array(32);
        inner.host.randomBytes(eph);
        const cert = bare(here);
        const keys = [...v.keys.filter((k) => k.cert.device !== who.device), { cert, wrapped: sealWith(cert.box, key, keyContext(self.ws, v.id, v.epoch), eph) }];
        const { sig: _s, ...rest } = v;
        yield* self.#putVault(sign({ ...rest, seq: v.seq + 1, keys, at: nowS(inner) }, TAG.vault, signer), hostOf(inner, self.ws, v.id));
        recovered++;
      }
      if (waited !== null) return yield* Effect.fail(waitingError(inner, self.ws, waited));
      return { recovered, others };
    });
  }

  /// The request as held, or read again from the stations when it is not.
  #request(id: string): Effect.Effect<{ r: Request; station: string }, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      if (!held(inner, self.ws).requests[id]) {
        yield* answersOf(inner, stationsOf(inner, self.ws).map((s) => readStation(inner, `${self.ws}/${s.id}`)), () => (held(inner, self.ws).requests[id] !== undefined ? 0 : OTHERS_MS));
      }
      const h = held(inner, self.ws);
      const r = h.requests[id];
      if (!r || r.status !== "pending") return yield* fail("vault_no_request", t("core-misc.vault.noRequest"));
      return { r, station: h.asked[id] ?? "" };
    });
  }

  /// An agent's request granted: the item's plaintext sealed to the keeper's key for this request, signed by this
  /// device (the person asked each time, whether the vault is unlocked or not). One to keep a secret: kept, with what
  /// the person `typed` where it is theirs to type in.
  approve(id: string, scope: Scope, typed?: unknown, timeoutValue?: unknown): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      if (!["once", "hour", "chat"].includes(scope)) return yield* Effect.fail(CoreError.invalid("scope: once, hour or chat"));
      const timeout = timeoutValue as { kind?: unknown; seconds?: unknown } | undefined;
      if (timeout !== undefined && (timeout === null || typeof timeout !== "object" || (timeout.kind !== "idle" && timeout.kind !== "fixed") || !Number.isSafeInteger(timeout.seconds) || (timeout.seconds as number) < 1 || (timeout.seconds as number) > 30 * 86400 || scope === "once" || (timeout.seconds as number) > GRANT_SECS[scope])) return yield* Effect.fail(CoreError.invalid("invalid timeout"));
      // The plain library's: its owner says so, nothing to open or sign (the station holds the value).
      const asked = yield* self.#request(id);
      if (asked.r.save) return yield* self.#keepSaved(asked.r, asked.station, typed);
      if (asked.r.describe) return yield* self.#describe(asked.r, asked.station);
      if (asked.r.timeout && scope !== "once" && !timeout) return yield* Effect.fail(CoreError.invalid("this request needs an approval with its timeout; update the app"));
      if (asked.r.vault === PLAIN) {
        const { r, station } = asked;
        const h = held(inner, self.ws);
        if (!allows(h.plain[r.item]?.listing?.lasts ?? h.plainLasts?.lasts, scope)) return yield* fail("vault_scope", t("core-misc.vault.scopeTooLong"));
        yield* self.#station(station, "POST", "/vault/plain/grants", { request: r.id, scope, ...(timeout ? { timeout } : {}) });
        self.#settled(r.id, { status: "granted", scope, ...(timeout ? { timeout: timeout as { kind: "idle" | "fixed"; seconds: number } } : {}) });
        return { request: r.id, scope };
      }
      const { lock, signer, self: who } = yield* self.#ready();
      const { r, station } = yield* self.#request(id);
      // (a use of an item, read: one of a vault waiting to be keyed anew is given as it is opened, checked against the
      // lock that took the vault; the sign-in's newer cookies are not written into it meanwhile, below)
      const { v, as } = yield* self.#readable(lock, r.vault, who);
      if (!v.members.includes(who.sub)) return yield* fail("vault_unknown", t("core-misc.vault.unknown"));
      const found = items(inner, self.ws, v.id)[r.item];
      if (!found || found.deleted) return yield* fail("vault_unknown", t("core-misc.vault.unknownItem"));
      let item: Item = found;
      if (!allows(item.listing?.lasts ?? v.lasts, scope)) return yield* fail("vault_scope", t("core-misc.vault.scopeTooLong"));
      // (this device's box key, as it was unsealed for it: a sign-in's newer cookies the request carries are opened with it)
      const unsealed: { priv?: Uint8Array } = {};
      const key = yield* self.#key(v, who, true, t("core-misc.vault.reason.approve", { name: item.listing?.name ?? v.name }), true, (p) => (unsealed.priv = p));
      // Still under the earlier key (its keying anew stopped half-way): carried on to the vault's key first, with the
      // box key just read (the person asked once); one not to be carried on stays refused below.
      if (item.epoch < v.epoch) {
        yield* Effect.ignore(self.carryOn(v.id, null, new Map([[keyOf(v), key]]), unsealed.priv ? { priv: unsealed.priv } : {}), { log: "Unhandled", message: "vault items carried on" });
        item = items(inner, self.ws, v.id)[r.item] ?? item;
      }
      let bytes = yield* self.#plain(as, v, item, key);
      // A sign-in's newer cookies ( 登录态 写回): written as its next version, and granted (not into a vault waiting
      // to be keyed anew: the cookies it holds granted).
      const renewal = r.mode === "browser" && as === lock ? r.renewal?.sealed.find((x) => x.device === who.device) : undefined;
      const priv = unsealed.priv;
      if (renewal !== undefined && priv !== undefined) {
        const renewed = yield* Effect.result(Effect.try({
          try: () => {
            const was = JSON.parse(new TextDecoder().decode(bytes)) as Plain;
            const fields = JSON.parse(new TextDecoder().decode(openSeal(priv, renewal.secret, saveContext(self.ws, r.renewal!.id)))) as Record<string, unknown>;
            if (was.kind !== "browser" || typeof fields.cookies !== "string" || fields.cookies === "") throw new Error("no sign-in's cookies");
            return plainOf({ ...was, fields: { ...was.fields, cookies: fields.cookies } });
          },
          catch: asCoreError,
        }));
        if (renewed._tag === "Success") {
          const plain = renewed.success;
          const version = item.version + 1;
          const nonce = new Uint8Array(12);
          inner.host.randomBytes(nonce);
          const ct = encryptWith(key, utf8(JSON.stringify(plain)), itemContext(self.ws, v.id, item.id, version, v.epoch), nonce);
          const next = sign({ v: 1 as const, ws: self.ws, vault: v.id, id: item.id, version, epoch: v.epoch, ct, ...(item.listing ? { listing: item.listing } : {}), at: nowS(inner) }, TAG.item, signer);
          const put = yield* Effect.result(self.#putItem(next, v));
          if (put._tag === "Success") bytes = utf8(JSON.stringify(plain));
        }
      }
      const grantTo = (box: string): Grant => {
        const eph = new Uint8Array(32);
        inner.host.randomBytes(eph);
        const now = nowS(inner);
        return sign(
          { v: 1 as const, ws: self.ws, request: r.id, vault: v.id, item: item.id, mode: r.mode, hosts: r.hosts ?? item.listing?.hosts ?? [], scope, exp: now + (timeout ? timeout.seconds as number : GRANT_SECS[scope]), ...(timeout ? { timeout: timeout as { kind: "idle" | "fixed"; seconds: number } } : {}), secret: sealWith(box, bytes, grantContext(self.ws, r.id), eph), at: now },
          TAG.grant,
          signer,
        );
      };
      let grant = grantTo(r.box);
      // The station restarted since this request was read: it waits on with a new box (told, maybe not heard yet), so
      // it is read again and sealed to that one.
      const sent = yield* Effect.result(self.#station(station, "POST", "/vault/grants", grant));
      if (sent._tag === "Failure") {
        if (sent.failure.code !== "vault_refused") return yield* Effect.fail(sent.failure);
        yield* Effect.ignore(readStation(inner, `${self.ws}/${station}`), { log: "Unhandled", message: "vault station read" });
        const again = held(inner, self.ws).requests[r.id];
        if (again?.status !== "pending" || !again.box || again.box === r.box) return yield* Effect.fail(sent.failure);
        grant = grantTo(again.box);
        yield* self.#station(station, "POST", "/vault/grants", grant);
      }
      self.#settled(r.id, { status: "granted", scope, ...(timeout ? { timeout: timeout as { kind: "idle" | "fixed"; seconds: number } } : {}) });
      return { request: r.id, scope, exp: grant.exp };
    });
  }

  /// A secret an agent asked to keep, approved. The plain library's is written by the station that asked (with what the
  /// person typed in, where it was theirs to). A vault's is opened with this device's box key (that station sealed it to
  /// the person's devices set up), or is what they typed in, written under the request's item id into one of their
  /// vaults this device holds a key to (the one asked for first, their own next; a new one only when they have none of
  /// their own: one this device has no key to yet, refused), its copy brought to that station, which is then told where
  /// it went, with the grant that lets the asking chat use it. Either way the chat that asked may use it at once.
  #keepSaved(r: Request, station: string, typed: unknown): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const s = r.save!;
      const given = s.typed ? typedFields(s, typed) : null;
      if (given === undefined) return yield* fail("vault_typed_empty", t("core-misc.vault.typedEmpty"));
      if (given instanceof CoreError) return yield* Effect.fail(given);
      if (r.vault === PLAIN) {
        yield* self.#station(station, "POST", "/vault/plain/saves", { request: r.id, ...(given ? { fields: given } : {}) });
        self.#settled(r.id, { status: "granted" });
        return { request: r.id, item: r.item };
      }
      const { lock, signer, self: who } = yield* self.#ready();
      // The box key it is kept with: the one the station sealed it to here, or (typed in) this device's the lock vouches.
      const sealed = (r.sealed ?? []).find((x) => x.device === who.device);
      const box = given ? certs(inner, self.ws, lock).find((c) => c.device === who.device)?.box : sealed?.box;
      if (box === undefined) return yield* (given ? fail("vault_not_set_up", t("core-misc.vault.notSetUp")) : fail("vault_no_key", t("core-misc.vault.notSealedHere")));
      const keyedHere = (v: Vault) => trusted(lock, v) && v.members.includes(who.sub) && v.keys.some((k) => k.cert.device === who.device && k.cert.box === box);
      const h = held(inner, self.ws);
      // (a secret is written into no vault waiting to be keyed anew: the one asked for, or their own when it is the one
      // it would go to, refused saying the station it waits for, not put elsewhere nor a second one made)
      const waitsHere = (v: Vault) => v.members.includes(who.sub) && waitingAs(inner, self.ws, lock, v) !== null;
      if (h.vaults[r.vault] !== undefined && waitsHere(h.vaults[r.vault]!)) return yield* Effect.fail(waitingError(inner, self.ws, h.vaults[r.vault]!));
      const theirs = Object.values(h.vaults).filter(keyedHere).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1));
      const chosen = (h.vaults[r.vault] && keyedHere(h.vaults[r.vault]!) ? h.vaults[r.vault] : undefined) ?? theirs.find((x) => x.owner === who.sub) ?? theirs[0];
      const ownWaiting = chosen ? undefined : Object.values(h.vaults).find((v) => v.owner === who.sub && waitsHere(v));
      if (ownWaiting !== undefined) return yield* Effect.fail(waitingError(inner, self.ws, ownWaiting));
      // Their own vault this device has no key to yet: given it by a device that has (not a second one made here).
      if (!chosen && Object.values(h.vaults).some((v) => !v.deleted && trusted(lock, v) && v.owner === who.sub)) return yield* fail("vault_no_key", t("core-misc.vault.noKey"));
      const priv = yield* self.#boxKey(t("core-misc.vault.reason.save", { name: s.name }));
      if (boxPublic(priv) !== box) return yield* fail("vault_no_key", t(given ? "core-misc.vault.noKey" : "core-misc.vault.notSealedHere"));
      const body = yield* Effect.try({
        try: () => {
          const fields = given ?? JSON.parse(new TextDecoder().decode(openSeal(priv, sealed!.secret, saveContext(self.ws, r.id))));
          return {
            plain: plainOf({ kind: s.kind, name: s.name, fields, domains: [], notes: s.about ?? "" }),
            listing: listingOf({ name: s.name, kind: s.kind, modes: s.modes, hosts: s.hosts, ...(s.env ? { env: s.env } : {}), ...(s.about ? { about: s.about } : {}) }),
          };
        },
        catch: asCoreError,
      });
      let v = chosen;
      if (!v) {
        const made = (yield* self.create(t("core-misc.vault.personal"), null)) as { id: string };
        v = held(inner, self.ws).vaults[made.id];
        if (!v) return yield* fail("vault_unknown", t("core-misc.vault.unknown"));
      }
      const vault = v;
      // Its key: kept unsealed a while, else opened with the box key just read (the person is asked once).
      const kept = mem(inner).keys.get(keyOf(vault));
      const wrapped = vault.keys.find((k) => k.cert.device === who.device)!.wrapped;
      const key = kept && kept.until > inner.host.nowMs() ? kept.key : yield* Effect.try({ try: () => openSeal(priv, wrapped, keyContext(self.ws, vault.id, vault.epoch)), catch: asCoreError });
      self.#keep(vault, key);
      inner.runner.fork(Effect.ignore(self.#give(vault.id, vault.epoch, key, null), { log: "Unhandled", message: "vault key given" }));
      // Written once: an approval tried again after the station was not told finds it there.
      const had = items(inner, self.ws, vault.id)[r.item];
      if (had?.deleted) return yield* fail("vault_unknown", t("core-misc.vault.unknownItem"));
      if (had === undefined) {
        const nonce = new Uint8Array(12);
        inner.host.randomBytes(nonce);
        const ct = encryptWith(key, utf8(JSON.stringify(body.plain)), itemContext(self.ws, vault.id, r.item, 0, vault.epoch), nonce);
        const next = sign({ v: 1 as const, ws: self.ws, vault: vault.id, id: r.item, version: 0, epoch: vault.epoch, ct, ...(body.listing ? { listing: body.listing } : {}), at: nowS(inner) }, TAG.item, signer);
        yield* self.#putItem(next, vault);
      }
      // Keeping it lets the chat that asked use it, for as long as the vault's items are given: its grant sealed to the
      // request's box (a station from before boxes none: no grant then).
      const scope: Scope = allows(body.listing?.lasts ?? vault.lasts, "hour") ? "hour" : "once";
      const now = nowS(inner);
      const eph = new Uint8Array(32);
      inner.host.randomBytes(eph);
      const grant: Grant | null = r.box
        ? sign(
            { v: 1 as const, ws: self.ws, request: r.id, vault: vault.id, item: r.item, mode: r.mode, hosts: r.mode === "proxy" || r.mode === "browser" ? (r.hosts ?? s.hosts) : [], scope, exp: now + GRANT_SECS[scope], ...(scope === "hour" ? { timeout: { kind: "idle" as const, seconds: 3600 } } : {}), secret: sealWith(r.box, utf8(JSON.stringify(body.plain)), grantContext(self.ws, r.id), eph), at: now },
            TAG.grant,
            signer,
          )
        : null;
      // The station that asked holds its copy before it is told.
      yield* spread(inner, `${self.ws}/${station}`);
      yield* self.#station(station, "POST", "/vault/saves", { request: r.id, vault: vault.id, ...(grant ? { grant } : {}) });
      self.#settled(r.id, { status: "granted", ...(grant ? { scope } : {}) });
      return { request: r.id, vault: vault.id, item: r.item, ...(grant ? { scope } : {}) };
    });
  }

  /// An agent's request to rename an item or change its about, approved: the plain library's written by its station; a
  /// vault's item opened here and written as its next version saying so (its listing too, what agents read), its copy
  /// brought to the station that asked, which is then told. It grants nothing.
  #describe(r: Request, station: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const d = r.describe!;
      if (typeof d.name !== "string" || d.name.trim() === "" || typeof d.about !== "string") return yield* Effect.fail(CoreError.invalid("describe: {name, about}"));
      if (r.vault === PLAIN) {
        yield* self.#station(station, "POST", "/vault/plain/described", { request: r.id });
        self.#settled(r.id, { status: "granted" });
        return { request: r.id, item: r.item };
      }
      const opened = (yield* self.open(r.item)) as { vault: string; plain: Plain };
      const item = items(inner, self.ws, opened.vault)[r.item];
      if (!item || item.deleted) return yield* fail("vault_unknown", t("core-misc.vault.unknownItem"));
      const { about: _, ...listing } = item.listing ?? { name: d.name, kind: opened.plain.kind, modes: [], hosts: [] };
      // (one agents may not ask for keeps no listing: its name and notes alone change)
      yield* self.putItem(opened.vault, r.item, { ...opened.plain, name: d.name, notes: d.about }, item.listing ? { ...listing, name: d.name, ...(d.about ? { about: d.about } : {}) } : null);
      // The station that asked holds its copy before it is told.
      yield* spread(inner, `${self.ws}/${station}`);
      yield* self.#station(station, "POST", "/vault/described", { request: r.id });
      self.#settled(r.id, { status: "granted" });
      return { request: r.id, item: r.item };
    });
  }

  deny(id: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const asked = yield* self.#request(id);
      if (asked.r.vault === PLAIN) {
        const { r, station } = asked;
        yield* self.#station(station, "POST", "/vault/plain/denials", { request: r.id });
        self.#settled(r.id, { status: "denied" });
        return { request: r.id };
      }
      const { signer } = yield* self.#ready();
      const { r, station } = yield* self.#request(id);
      const deny: Deny = sign({ v: 1 as const, ws: self.ws, request: r.id, at: nowS(self.#inner) }, TAG.deny, signer);
      yield* self.#station(station, "POST", "/vault/denials", deny);
      self.#settled(r.id, { status: "denied" });
      return { request: r.id };
    });
  }

  // ── the plain library ( 不加锁的库) ──

  /// An item of the plain library written on its station (a new one on the station keeping the library), the version
  /// after the one held.
  putPlain(id: string | null, plain: unknown, listing: unknown): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const body = yield* Effect.try({ try: () => ({ plain: plainOf(plain), listing: listingOf(listing) }), catch: asCoreError });
      if (!(lockOf(inner, self.ws) instanceof CoreError)) return yield* fail("vault_locked", t("core-misc.vault.plainLocked"));
      const h = held(inner, self.ws);
      const prev = id ? h.plain[id] : undefined;
      if (id && (!prev || prev.deleted)) return yield* fail("vault_unknown", t("core-misc.vault.unknownItem"));
      const station = prev?.station ?? vaultsView(inner, self.ws).vaults[0]?.station;
      if (!station) return yield* fail("vault_no_station", t("core-misc.vault.noPlainStation"));
      const next = {
        id: id ?? `i_${ulid(inner.host)}`, version: prev ? prev.version + 1 : 0, kind: body.plain.kind, name: body.plain.name, fields: body.plain.fields, notes: body.plain.notes,
        ...(body.listing ? { listing: body.listing } : {}), at: nowS(inner),
      };
      return yield* self.#putPlainRow(station, next);
    });
  }

  deletePlain(id: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const prev = held(self.#inner, self.ws).plain[id];
      if (!prev || prev.deleted) return yield* fail("vault_unknown", t("core-misc.vault.unknownItem"));
      return yield* self.#putPlainRow(prev.station, { id, version: prev.version + 1, kind: prev.kind, name: "", fields: {}, notes: "", at: nowS(self.#inner), deleted: true });
    });
  }

  /// A plain item's version taken by its station, held here as it said it; not the next (written elsewhere meanwhile):
  /// the library read again before it fails.
  #putPlainRow(station: string, next: J): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const said = yield* Effect.tapError(self.#station(station, "PUT", "/vault/plain", next), (e) =>
        e.code === "vault_conflict" ? Effect.ignore(readStation(self.#inner, `${self.ws}/${station}`), { log: "Unhandled", message: "vault station read" }) : Effect.void,
      );
      const item = (get(said, "item") as PlainRow | undefined) ?? (({ fields: _, ...rest }) => rest)(next);
      change(self.#inner, self.ws, (h) => void (h.plain[item.id] = { ...item, station }));
      return { id: item.id, version: item.version };
    });
  }

  /// What a plain item holds, as its station keeps it (nobody asked: nothing is sealed).
  openPlain(id: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const row = held(self.#inner, self.ws).plain[id];
      if (!row || row.deleted) return yield* fail("vault_unknown", t("core-misc.vault.unknownItem"));
      const i = get(yield* self.#station(row.station, "GET", `/vault/plain/item?id=${encodeURIComponent(id)}`, null), "item") as J;
      const fields: Record<string, string> = {};
      for (const [k, x] of Object.entries(isObject(i?.fields) ? (i.fields as Record<string, unknown>) : {})) if (typeof x === "string") fields[k] = x;
      return { vault: PLAIN, id, version: Number(get(i, "version") ?? row.version), plain: { kind: get(i, "kind") ?? row.kind, name: get(i, "name") ?? row.name, fields, domains: [], notes: str(get(i, "notes")) ?? "" } };
    });
  }

  /// The person's own vaults' items opened (their plaintext and listing), for security mode turned off.
  unsealOwn(reason?: string, asked?: () => void): Effect.Effect<{ plain: Plain; listing: Listing | null }[], CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      if (!able(inner) || lockOf(inner, self.ws) instanceof CoreError) return [];
      const ready = yield* Effect.result(self.#ready());
      if (ready._tag === "Failure") return [];
      const { lock, self: who } = ready.success;
      const out: { plain: Plain; listing: Listing | null }[] = [];
      for (const v of Object.values(held(inner, self.ws).vaults)) {
        // (read: one waiting to be keyed anew too, its items checked against the lock that took it)
        const as = readAs(inner, self.ws, lock, v, who);
        if (as === null || v.owner !== who.sub || !v.keys.some((k) => k.cert.device === who.device)) continue;
        const why = reason ?? t("core-misc.vault.reason.unlock", { name: v.name });
        // (those left under an earlier key carried on first: none of them is lost as the lock goes)
        if (underEarlier(inner, self.ws, v).length > 0) yield* self.carryOn(v.id, why, undefined, { asked: () => asked?.() });
        const all = Object.values(items(inner, self.ws, v.id)).filter((i) => !i.deleted && i.epoch === v.epoch);
        if (all.length === 0) continue;
        const key = yield* self.#key(v, who, false, why, true, () => asked?.());
        for (const item of all) {
          const bytes = yield* Effect.result(self.#plain(as, v, item, key));
          if (bytes._tag === "Success") out.push({ plain: plainOf(JSON.parse(new TextDecoder().decode(bytes.success))), listing: item.listing ?? null });
        }
      }
      return out;
    });
  }

  /// Security mode on: each item left in the plain library written into the person's own vault (encrypted, its listing
  /// kept), then deleted where it was; one the vault holds already (written back when security mode was off, and on
  /// again) only deleted. One that fails stays, said in the count.
  migrate(): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const { lock, self: who } = yield* self.#ready();
      // (one this device holds a key to first)
      const owns = Object.values(held(inner, self.ws).vaults).filter((v) => !v.deleted && trusted(lock, v) && v.owner === who.sub);
      const own = owns.find((v) => v.keys.some((k) => k.cert.device === who.device)) ?? owns[0];
      // (their own waiting to be keyed anew: nothing moved into it till it is)
      const waiting = own ? undefined : Object.values(held(inner, self.ws).vaults).find((v) => v.owner === who.sub && waitingAs(inner, self.ws, lock, v) !== null);
      if (waiting !== undefined) return yield* Effect.fail(waitingError(inner, self.ws, waiting));
      if (!own) return yield* fail("vault_not_set_up", t("core-misc.vault.notSetUp"));
      const same = (p: Plain) => JSON.stringify([p.kind, p.name, p.fields]);
      const had = new Set((yield* self.unsealOwn()).map((s) => same(s.plain)));
      let moved = 0;
      let left = 0;
      for (const row of Object.values(held(inner, self.ws).plain)) {
        if (row.deleted) continue;
        const done = yield* Effect.result(Effect.gen(function* () {
          const opened = (yield* self.openPlain(row.id)) as { plain: Plain };
          if (!had.has(same(plainOf(opened.plain)))) yield* self.putItem(own.id, null, opened.plain, row.listing ?? null);
          yield* self.deletePlain(row.id);
        }));
        if (done._tag === "Success") moved++;
        else left++;
      }
      return { moved, left };
    });
  }

  /// A request answered here (how: `outcome`): no longer waiting (the station says so too, as it tells it), with how it
  /// went shown on its card in the chat at once.
  #settled(id: string, outcome: VaultOutcome): void {
    this.#inner.views?.local.vaultDecided(id, outcome);
    change(this.#inner, this.ws, (h) => {
      delete h.requests[id];
      delete h.asked[id];
    });
  }
}

// The vault on this device (docs/vault.md): the vaults and items a workspace's stations hold, kept here as they do
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
//
// Without security mode the library is plain (docs/vault.md 不加锁的库): each station keeps the person's items as they
// are (`vault/plain`), shown as one vault, `plain`; the calls below take it as they take a vault, with nothing to
// encrypt, sign or ask the person for. Security mode on, what is left of it is moved into their vault (`migrate`).
// Calls (vault.<name> {workspace, …}):
//   setup                         this device's box key (made once), its certificate published; the recovery words
//                                 the first time (`{words}`, shown once: never kept); one's own vault made when one
//                                 has none (`{made}`)
//   create {name, station?}       a vault of one's own, keyed for each of one's devices set up
//   delete {vault}                a vault of one's own deleted, its items with it (the person asked when it holds any)
//   addDevice {vault, device?}    the vault's key sealed for members' devices set up since (its owner signs; done by
//                                 itself too whenever the owner's device unseals it)
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
import { Effect, Schedule } from "effect";
import type { Inner } from "../core.ts";
import { ulid } from "../accounts.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import type { Owner } from "../core/routing.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { type Entry, Signer } from "../lock.ts";
import { askPerson, signerOf } from "./lock.ts";
import type { Topic } from "../protocol.ts";
import { StationAddr } from "../station/addr.ts";
import { Priority } from "../sync/scheduler.ts";
import type { SpanContext } from "../trace.ts";
import { get, isObject, utf8 } from "../util.ts";
import {
  type BoxCert, type Deny, type Grant, type Item, type Listing, type Plain, type Request, type Save, type Scope, type Vault,
  SCOPES, TAG, allows, boxPublic, decrypt, encryptWith, fromWords, grantContext, itemContext, keyContext, openSeal, recoveryPair, saveContext, sealWith, sign, signedOk, toWords,
} from "../vault/crypto.ts";
import { type Checked, checkLock } from "../vault/lock-check.ts";
import { ofAddress } from "../workspace.ts";
import { stamp } from "../present.ts";
import type { VaultOutcome } from "./local.ts";
import { fileBytes, howText, itemWords, kindText, modeText, shownFields, statusWords } from "../vault-words.ts";

// deno-lint-ignore no-explicit-any
type J = any;
type Of = Extract<Call, { kind: "vault" }>;

/// How long a vault's key stays unsealed in memory after it was last unsealed.
export const UNLOCK_MS = 5 * 60_000;
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
};

/// A vault's version a station holds, and its items' versions.
type Holding = { seq: number; items: Record<string, number> };

/// An item of the plain library as a station lists it (vault/plain.ts `shown`), and where it is.
type PlainRow = { id: string; owner: string; version: number; kind: string; name: string; notes: string; listing?: Listing; at: number; deleted?: true; station: string };
/// A use as a station says it (vault/secrets.ts `Use`).
type Use = { item: string; at: number; session: string; chatTitle: string | null; mode: string; command: string | null; hosts: string[]; denied: boolean };

/// The id the plain library goes by where a vault's would.
export const PLAIN = "plain";

/// This core's unsealed vault keys (by `<vault>/<epoch>`, until when), the lock as checked and the box key's public
/// half once known. The signing key's id is the lock's (`signerOf`), told as it is made, not read here once.
type Mem = { keys: Map<string, { key: Uint8Array; until: number }>; checked: Map<string, { at: string; lock: Checked | CoreError }>; box: string | null | undefined };
const mems = new WeakMap<Inner, Mem>();
const mem = (inner: Inner): Mem => {
  let m = mems.get(inner);
  if (!m) mems.set(inner, (m = { keys: new Map(), checked: new Map(), box: undefined }));
  return m;
};

const EMPTY: Held = { vaults: {}, at: {}, boxes: {}, requests: {}, asked: {}, refused: {}, on: {}, keeps: [], plain: {}, plainOn: [], uses: {} };
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
  invalidate(inner, ws);
}

function items(inner: Inner, ws: string, vault: string): Record<string, Item> {
  const v = inner.data.record("vaultItems", `${ws}/${vault}`);
  return isObject(v) ? (v as Record<string, Item>) : {};
}

function changeItems(inner: Inner, ws: string, vault: string, f: (items: Record<string, Item>) => void): void {
  const all = structuredClone(items(inner, ws, vault)) as Record<string, Item>;
  f(all);
  inner.data.put("vaultItems", `${ws}/${vault}`, all);
  invalidate(inner, ws);
}

function invalidate(inner: Inner, ws: string): void {
  inner.store.invalidateAll((t) => (t.topic === "vaults" || t.topic === "vaultItems" || t.topic === "vaultUses") && t.workspace === ws);
  // (the requests' cards in the chats and on the 奏 page: shown again where how they are answered here changed)
  inner.views?.vaultChanged(ws);
}

const view = (inner: Inner, ws: string): J => inner.data.shared({ topic: "workspace", workspace: ws });
const stationsOf = (inner: Inner, ws: string): { id: string; name: string }[] => arr(get(view(inner, ws), "stations")).filter((s) => typeof s?.id === "string");

/// The workspace's lock as held here, checked (the same while its head does not move); an error says why it is none.
function lockOf(inner: Inner, ws: string): Checked | CoreError {
  const h = inner.data.record("lock", ws);
  const entries = isObject(h) && Array.isArray(h.entries) ? (h.entries as Entry[]) : [];
  const head = isObject(h) ? str(get(h.head, "hash")) : null;
  if (entries.length === 0 || head === null) return new CoreError("vault_needs_lock", t("core-misc.vault.needsLock"));
  const m = mem(inner);
  const at = `${head}/${entries.length}`;
  const had = m.checked.get(ws);
  if (had?.at === at) return had.lock;
  let lock: Checked | CoreError;
  try {
    lock = checkLock(entries, nowS(inner));
    if (lock.disabled) lock = new CoreError("vault_needs_lock", t("core-misc.vault.needsLock"));
  } catch (e) {
    lock = asCoreError(e);
  }
  m.checked.set(ws, { at, lock });
  return lock;
}

/// Whether a certificate is of an app device in the lock, signed by its own key; whose device it is.
function certOwner(lock: Checked, cert: BoxCert): string | null {
  const d = lock.devices.get(cert?.device);
  if (!d || d.kind !== "app" || !lock.members.has(d.sub) || d.sign_key !== cert.sig?.key || cert.ws !== lock.ws || !signedOk(cert, TAG.box)) return null;
  return d.sub;
}

/// Whether a vault's version is its owner's (signed by one of their app devices in the lock).
function trusted(lock: Checked, v: Vault): boolean {
  if (v?.ws !== lock.ws || !Array.isArray(v.members) || !signedOk(v, TAG.vault)) return false;
  const d = [...lock.devices.values()].find((x) => x.kind === "app" && x.sign_key === v.sig.key);
  return d !== undefined && d.sub === v.owner;
}

/// This device in the lock: the one whose signing key is this app's.
function me(lock: Checked, signer: string | null | undefined): { device: string; sub: string } | null {
  if (!signer) return null;
  const d = [...lock.devices.values()].find((x) => x.kind === "app" && x.sign_key === signer);
  return d ? { device: d.id, sub: d.sub } : null;
}

/// The certificates the lock vouches for, latest by device.
function certs(inner: Inner, ws: string, lock: Checked): (BoxCert & { sub: string })[] {
  return Object.values(held(inner, ws).boxes).flatMap((c) => {
    const sub = certOwner(lock, c);
    return sub === null ? [] : [{ ...c, sub }];
  });
}

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
      inner.store.invalidateAll((t) => t.topic === "vaults" || t.topic === "vaultItems");
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
    // Each item as the latest version any station holds (a copy behind its host's says nothing newer).
    for (const v of list ?? []) {
      if (v.deleted) inner.data.forgetRecord("vaultItems", `${ws}/${v.id}`);
      else changeItems(inner, ws, v.id, (held) => {
        for (const i of all) if (i.vault === v.id && newer(i, held[i.id])) held[i.id] = i;
      });
    }
    change(inner, ws, (h) => {
      if (list !== null) {
        delete h.refused[station];
        if (!h.keeps.includes(station)) h.keeps.push(station);
        const ids = new Set(list.map((v) => v.id));
        // Those it held and holds no more (one held from before copies were kept: where it was).
        for (const id of new Set([...Object.keys(h.on), ...Object.keys(h.at)])) {
          if (!ids.has(id) && (h.on[id]?.[station] !== undefined || (h.on[id] === undefined && h.at[id] === station))) letGo(h, id, station);
        }
        for (const v of list) {
          holds(h, v, station, Object.fromEntries(all.filter((i) => i.vault === v.id).map((i) => [i.id, i.version])));
        }
      }
      for (const c of boxes) if (!h.boxes[c.device] || h.boxes[c.device]!.at <= c.at) h.boxes[c.device] = c;
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
    if (list !== null) spreadAll(inner, ws);
  });
}

/// Whether item `i` is a later version than `had` (none: it is).
const newer = (i: Item, had: Item | undefined) => had === undefined || i.version > had.version;

/// `station` holds vault `v` (and its items at these versions): the latest version held anywhere is the one shown; its
/// host is the station it was on first, until that one no longer holds it.
function holds(h: Held, v: Vault, station: string, items: Record<string, number> | null): void {
  const on = (h.on[v.id] ??= {});
  on[station] = { seq: v.seq, items: items ?? on[station]?.items ?? {} };
  if (h.at[v.id] === undefined || on[h.at[v.id]!] === undefined) h.at[v.id] = station;
  // Two versions of one seq (written on two stations at once): the host's.
  const had = h.vaults[v.id];
  if (had === undefined || v.seq > had.seq || (v.seq === had.seq && station === h.at[v.id])) h.vaults[v.id] = v;
}

/// `station` no longer holds vault `id`: gone where no station holds it; its host another that does.
function letGo(h: Held, id: string, station: string): void {
  const on = h.on[id];
  if (on !== undefined) delete on[station];
  if (on === undefined || Object.keys(on).length === 0) {
    delete h.on[id];
    delete h.vaults[id];
    delete h.at[id];
    return;
  }
  if (h.at[id] === station || h.at[id] === undefined) h.at[id] = Object.keys(on).sort()[0]!;
}

/// What `station` lacks of what the vaults' latest versions are: the vaults it holds none or an older version of, and
/// the items it holds none or an older version of (of the vaults it will hold).
function lacks(h: Pick<Held, "vaults" | "on">, items: (vault: string) => Record<string, Item>, station: string): { id: string; vault: Vault | null; items: Item[] }[] {
  return Object.values(h.vaults).flatMap((v) => {
    const have = h.on[v.id]?.[station];
    const behind = have === undefined || have.seq < v.seq;
    const missing = v.deleted ? [] : Object.values(items(v.id)).filter((i) => (have?.items[i.id] ?? -1) < i.version);
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
        change(inner, ws, (h) => holds(h, v, station, null));
      }
      for (const i of want.items) {
        const said = yield* Effect.result(ask(inner, address, "PUT", "/vault/items?copy=1", i));
        if (said._tag === "Failure") continue;
        const kept = (get(said.success, "item") as Item | undefined) ?? i;
        change(inner, ws, (h) => {
          const at = h.on[want.id]?.[station];
          if (at !== undefined) at.items[kept.id] = kept.version;
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
      change(inner, ws, (h) => holds(h, d as Vault, station, null));
      if (d.deleted) inner.data.forgetRecord("vaultItems", `${ws}/${d.id}`);
      // One this person was just put in (or this station was just brought): its items are read.
      else if (!known) inner.scheduler.enqueue(address, `${address} vault/${d.id}`, Priority.background, readItems(inner, address, d.id));
      spreadAll(inner, ws);
      return;
    }
    case "vault-gone":
      if (typeof d?.id !== "string") return;
      change(inner, ws, (h) => letGo(h, d.id, station));
      if (held(inner, ws).vaults[d.id] === undefined) inner.data.forgetRecord("vaultItems", `${ws}/${d.id}`);
      return;
    case "vault-item":
      if (typeof d?.vault === "string" && typeof d?.id === "string") {
        changeItems(inner, ws, d.vault, (all) => { if (newer(d as Item, all[d.id])) all[d.id] = d; });
        change(inner, ws, (h) => {
          const at = h.on[d.vault]?.[station];
          if (at !== undefined) at.items[d.id] = d.version;
        });
        spreadAll(inner, ws);
      }
      return;
    case "vault-box":
      if (typeof d?.device === "string") change(inner, ws, (h) => {
        if (!h.boxes[d.device] || h.boxes[d.device]!.at <= d.at) h.boxes[d.device] = d;
      });
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
    changeItems(inner, ws, vault, (held) => {
      for (const i of all) if (newer(i, held[i.id])) held[i.id] = i;
    });
    change(inner, ws, (h) => {
      const at = h.on[vault]?.[station];
      if (at !== undefined) at.items = Object.fromEntries(all.map((i) => [i.id, i.version]));
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
      return { ok: t.topic === "vaults" ? vaultsView(inner, ws) : t.topic === "vaultUses" ? usesView(inner, ws, String(t.vault), String(t.item)) : itemsView(inner, ws, String(t.vault)) };
    },
  };
}

const keyOf = (v: Vault) => `${v.id}/${v.epoch}`;
const unlocked = (inner: Inner, v: Vault) => (mem(inner).keys.get(keyOf(v))?.until ?? 0) > inner.host.nowMs();

/// Whether this host keeps keys as an app does, in the system's secure storage.
const able = (inner: Inner) => inner.host.appKeys === true && typeof inner.host.secureGet === "function" && typeof inner.host.secureSet === "function";

/// How an agent's request a card names (`card.vault`; `save`: one to keep a secret) is answered on this device, from the
/// vault as this core holds it: what a chat's card, and the 奏 page's, show at its foot with the message itself (views.ts),
/// never asking for more. `elsewhere`: approved only in an app that keeps keys (the plain library's anywhere); `setUp`:
/// a secret to keep while this device's vault is not on (开启密钥库 first); else `approve`, a use given for `lasts` at the
/// longest (the item's, else its vault's; a request not held yet, as one with none said).
export type AskAnswer = { answer: "approve" | "setUp" | "elsewhere"; lasts?: Scope };

export function askAnswers(inner: Inner, ws: string, asks: { request: string; save: boolean }[]): AskAnswer[] {
  const lock = lockOf(inner, ws);
  const plain = lock instanceof CoreError;
  if (!able(inner) && !plain) return asks.map(() => ({ answer: "elsewhere" }));
  const h = held(inner, ws);
  // (this device's box certificate the lock vouches for, its key the one kept here: as the `vaults` topic's setUp)
  let setUp: boolean | undefined;
  const isSetUp = (): boolean => {
    if (setUp !== undefined) return setUp;
    if (lock instanceof CoreError) return (setUp = false);
    const self = me(lock, signerOf(inner));
    const cert = self !== null ? h.boxes[self.device] : undefined;
    return (setUp = cert !== undefined && certOwner(lock, cert) !== null && cert.box === mem(inner).box);
  };
  return asks.map(({ request, save }): AskAnswer => {
    if (save) return { answer: !plain && !isSetUp() ? "setUp" : "approve" };
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
    session: r.session, chat: r.chat, station: h.asked[r.id] ?? null, mode: r.mode, reason: r.reason, command: r.command ?? null, hosts: r.hosts ?? [], at: r.at,
    howText: howText(r.mode, r.hosts ?? []),
    // A secret an agent asks to keep: what kind, the account it is for, whether the person types it in.
    ...(r.save ? { save: { kind: r.save.kind, ...(r.save.username ? { username: r.save.username } : {}), ...(r.save.filename ? { filename: r.save.filename } : {}), ...(r.save.typed ? { typed: true } : {}) } } : {}),
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
      .map((r) => requestRow(r, r.save?.name ?? h.plain[r.item]?.name ?? null, personal, h.plain[r.item]?.listing?.lasts ?? h.plainLasts?.lasts ?? "chat"));
    return { ...base, plain: true, vaults: row, requests, ...statusWords(row, requests) };
  }
  const self = me(lock, signerOf(inner));
  const vouched = certs(inner, ws, lock);
  const mine = self ? vouched.find((c) => c.device === self.device) : undefined;
  const vaults = Object.values(h.vaults)
    .filter((v) => !v.deleted && trusted(lock, v) && sub !== null && v.members.includes(sub))
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1))
    .map((v) => {
      const keyed = new Map(v.keys.map((k) => [k.cert.device, k.cert.box]));
      const all = Object.values(items(inner, ws, v.id)).filter((i) => !i.deleted);
      return {
        id: v.id, name: v.name, owner: v.owner, ownerName: nameOf(v.owner), mine: v.owner === sub,
        members: v.members.map((s) => ({ sub: s, name: nameOf(s) })),
        station: h.at[v.id] ?? "", stationName: stationName.get(h.at[v.id] ?? "") ?? "",
        items: all.length, devices: v.keys.length, open: unlocked(inner, v),
        // Whether this device has a key to it; members' devices set up since that have none yet (its owner's device gives
        // them the key as it next has it in hand, or as asked: addDevice).
        keyed: self !== null && mine !== undefined && keyed.get(self.device) === mine.box,
        missing: vouched.filter((c) => v.members.includes(c.sub) && keyed.get(c.device) !== c.box).length,
        recoverable: v.recovery !== undefined, lasts: v.lasts ?? "chat",
      };
    });
  // (a secret to keep is told only to whom it is for: it may be meant for no vault yet)
  const requests = Object.values(h.requests)
    .filter((r) => r.status === "pending" && (r.save !== undefined || (h.vaults[r.vault] !== undefined && !h.vaults[r.vault]!.deleted && sub !== null && h.vaults[r.vault]!.members.includes(sub))))
    .sort((a, b) => a.at - b.at)
    .map((r) => {
      const listing = items(inner, ws, r.vault)[r.item]?.listing;
      return requestRow(r, r.save?.name ?? listing?.name ?? null, h.vaults[r.vault]?.name ?? personal, listing?.lasts ?? h.vaults[r.vault]?.lasts ?? "chat");
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
      id: i.id, version: i.version, at: i.at, name: i.name, kind: i.kind,
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
  if (!v || v.deleted || lock instanceof CoreError || !trusted(lock, v)) return { vault: id, name: "", open: false, items: [] };
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
        listed: i.listing !== undefined, modes: i.listing?.modes ?? [], hosts: i.listing?.hosts ?? [], env: i.listing?.env ?? null, lasts: i.listing?.lasts ?? null,
        ...(last.has(i.id) ? { lastUse: last.get(i.id) } : {}),
      };
    })
    .map((r) => ({ ...r, ...itemWords(r, v.lasts) }))
    .sort((a, b) => ((a.name ?? "") < (b.name ?? "") ? -1 : (a.name ?? "") > (b.name ?? "") ? 1 : a.id < b.id ? -1 : 1));
  return { vault: id, name: v.name, open: key !== null, items: list };
}

// ── security mode turned off (docs/vault.md 一个库) ──

/// What the person's own vaults hold, opened on this device while the lock is still on (the person asked, unless the
/// vaults are unlocked): none where this device keeps no vault keys or holds none of theirs.
export function unsealOwn(inner: Inner, ws: string): Effect.Effect<{ plain: Plain; listing: Listing | null }[], CoreError> {
  return new Vaults(inner, ws, null).unsealOwn();
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
        invalidate(inner, c.workspace);
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
      return v.approve(p("request"), (str(c.params.scope) ?? "once") as Scope, c.params.typed);
    case "deny":
      return v.deny(p("request"));
    case "setLasts":
      return v.setLasts(p("vault"), p("lasts"));
    default:
      return Effect.fail(CoreError.invalid(`no vault call ${c.name}`));
  }
}

const KINDS = ["token", "ssh_key", "login", "file"];
const MODES = ["proxy", "ssh", "env", "file"];
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
  if (!isObject(v) || !KINDS.includes(v.kind as string) || typeof v.name !== "string") throw CoreError.invalid("plain: {kind: token|ssh_key|login|file, name, fields, domains, notes}");
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
  return { name: v.name, kind: v.kind as Listing["kind"], modes, hosts: arr(v.hosts).filter((x) => typeof x === "string"), ...(typeof v.env === "string" ? { env: v.env } : {}), ...(lasts ? { lasts } : {}) };
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
      if (!signer || !who) return yield* fail("vault_not_signer", t("core-misc.vault.notSigner"));
      return { lock, signer, self: who };
    });
  }

  #vault(lock: Checked, id: string): Effect.Effect<Vault, CoreError> {
    const v = held(this.#inner, this.ws).vaults[id];
    if (!v || v.deleted || !trusted(lock, v)) return fail("vault_unknown", t("core-misc.vault.unknown"));
    return Effect.succeed(v);
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
  #key(v: Vault, self: { device: string }, fresh: boolean, reason: string, give = true): Effect.Effect<Uint8Array, CoreError> {
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
        self_.#keep(v, key);
        return key;
      }),
      (key) => Effect.sync(() => void (give && inner.runner.fork(Effect.ignore(self_.#give(v.id, v.epoch, key, null), { log: "Unhandled", message: "vault key given" })))),
    );
  }

  /// The members' devices set up (their box certificates the lock vouches for) that vault `v` has no key for (or
  /// `device` alone).
  #missing(lock: Checked, v: Vault, device: string | null): (BoxCert & { sub: string })[] {
    const keyed = new Map(v.keys.map((k) => [k.cert.device, k.cert.box]));
    return certs(this.#inner, this.ws, lock).filter((c) => v.members.includes(c.sub) && keyed.get(c.device) !== c.box && (device === null || c.device === device));
  }

  /// Vault `id`'s key (of `epoch`, unsealed here) sealed for the members' devices set up since it was keyed (or
  /// `device` alone): its next version, which its owner signs (another member's device gives none). How many it gave.
  #give(id: string, epoch: number, key: Uint8Array, device: string | null): Effect.Effect<number, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const { lock, signer, self: who } = yield* self.#ready();
      const v = yield* self.#vault(lock, id);
      if (v.owner !== who.sub || v.epoch !== epoch) return 0;
      const add = self.#missing(lock, v, device);
      if (add.length === 0) return 0;
      const devices = new Set(add.map((c) => c.device));
      const context = keyContext(self.ws, v.id, v.epoch);
      const keys = [
        ...v.keys.filter((k) => !devices.has(k.cert.device)),
        ...add.map(({ sub: _, ...cert }) => {
          const eph = new Uint8Array(32);
          inner.host.randomBytes(eph);
          return { cert, wrapped: sealWith(cert.box, key, context, eph) };
        }),
      ];
      const { sig: _, ...rest } = v;
      yield* self.#putVault(sign({ ...rest, seq: v.seq + 1, keys, at: nowS(inner) }, TAG.vault, signer), held(inner, self.ws).at[v.id] ?? "");
      return add.length;
    });
  }

  /// A vault's key kept unsealed UNLOCK_MS from now, then forgotten (and the pages told).
  #keep(v: Vault, key: Uint8Array): void {
    const inner = this.#inner;
    const until = inner.host.nowMs() + UNLOCK_MS;
    mem(inner).keys.set(keyOf(v), { key, until });
    invalidate(inner, this.ws);
    inner.runner.fork(
      Effect.andThen(
        Effect.sleep(UNLOCK_MS),
        Effect.sync(() => {
          const k = mem(inner).keys.get(keyOf(v));
          if (k && k.until <= inner.host.nowMs()) mem(inner).keys.delete(keyOf(v));
          invalidate(inner, this.ws);
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
      change(self.#inner, self.ws, (h) => {
        holds(h, v, station, null);
        h.at[v.id] = station;
      });
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
      const cert = sign({ v: 1 as const, ws: self.ws, device: who.device, box: pub, recovery, at: nowS(inner) }, TAG.box, signer);
      const published = yield* Effect.forEach(stationsOf(inner, self.ws), (s) => Effect.map(Effect.result(self.#station(s.id, "PUT", "/vault/boxes", cert)), (r) => [s.id, r._tag === "Success"] as const), { concurrency: 4 });
      if (!published.some(([, ok]) => ok)) return yield* fail("vault_no_station", t("core-misc.vault.noStation"));
      change(inner, self.ws, (h) => void (h.boxes[cert.device] = cert));
      const stations = published.filter(([, ok]) => ok).map(([id]) => id);
      for (const s of stations) yield* Effect.ignore(readStation(inner, `${self.ws}/${s}`), { log: "Unhandled", message: "vault station read" });
      // (not made, it is offered on the page as when there is none)
      const own = Object.values(held(inner, self.ws).vaults).some((v) => !v.deleted && trusted(lock, v) && v.owner === who.sub);
      const made = own ? null : yield* Effect.orElseSucceed(Effect.map(self.create(t("core-misc.vault.personal"), null), (m) => (m as { id: string }).id), () => null);
      return { words, device: who.device, stations, made };
    });
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
        { v: 1 as const, ws: self.ws, id, seq: 0, owner: who.sub, name: name.trim(), members: [who.sub], epoch: 0, keys: mine.map(({ sub: _, ...cert }) => ({ cert, wrapped: seal(cert.box) })), ...(recovery ? { recovery: seal(recovery) } : {}), at: nowS(inner) },
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
      yield* self.#putVault(sign({ ...rest, seq: v.seq + 1, epoch: v.epoch + 1, keys: [], deleted: true as const, at: nowS(inner) }, TAG.vault, signer), held(inner, self.ws).at[v.id] ?? "");
      mem(inner).keys.delete(keyOf(v));
      inner.data.forgetRecord("vaultItems", `${self.ws}/${v.id}`);
      invalidate(inner, self.ws);
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
        const told = yield* Effect.forEach(held(inner, self.ws).plainOn, (s) => Effect.map(Effect.result(self.#station(s, "PUT", "/vault/plain/lasts", { lasts: scope, at })), (r) => r._tag === "Success"), { concurrency: 4 });
        if (!told.some((ok) => ok)) return yield* fail("vault_no_station", t("core-misc.vault.noStation"));
        change(inner, self.ws, (h) => void (h.plainLasts = { lasts: scope, at }));
        return { lasts: scope };
      }
      const { lock, signer, self: who } = yield* self.#ready();
      const v = yield* self.#vault(lock, id);
      if (v.owner !== who.sub) return yield* fail("vault_not_owner", t("core-misc.vault.notOwnerLasts"));
      const { sig: _, ...rest } = v;
      yield* self.#putVault(sign({ ...rest, seq: v.seq + 1, lasts: scope, at: nowS(inner) }, TAG.vault, signer), held(inner, self.ws).at[v.id] ?? "");
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
      const v = yield* self.#vault(lock, vault);
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
      const { lock, signer } = yield* self.#ready();
      const v = yield* self.#vault(lock, vault);
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
    const station = held(this.#inner, this.ws).at[v.id] ?? "";
    return Effect.gen(function* () {
      const said = yield* Effect.tapError(self.#station(station, "PUT", "/vault/items", next), (e) =>
        e.code === "vault_conflict" ? Effect.ignore(readItems(self.#inner, `${self.ws}/${station}`, v.id), { log: "Unhandled", message: "vault items read" }) : Effect.void,
      );
      const item = (get(said, "item") as Item | undefined) ?? next;
      changeItems(self.#inner, self.ws, v.id, (all) => void (all[item.id] = item));
      change(self.#inner, self.ws, (h) => {
        const at = h.on[v.id]?.[station];
        if (at !== undefined) at.items[item.id] = item.version;
      });
      spreadAll(self.#inner, self.ws);
      return { id: item.id, version: item.version };
    });
  }

  /// The item, found in its vault, and that vault.
  #find(lock: Checked, id: string): Effect.Effect<{ v: Vault; item: Item }, CoreError> {
    const h = held(this.#inner, this.ws);
    for (const v of Object.values(h.vaults)) {
      const item = items(this.#inner, this.ws, v.id)[id];
      if (item && !item.deleted && trusted(lock, v)) return Effect.succeed({ v, item });
    }
    return fail("vault_unknown", t("core-misc.vault.unknownItem"));
  }

  /// What an item holds: written by a member's device in the lock, opened with its vault's key.
  #plain(lock: Checked, v: Vault, item: Item, key: Uint8Array): Effect.Effect<Uint8Array, CoreError> {
    const by = [...lock.devices.values()].find((d) => d.kind === "app" && d.sign_key === item.sig?.key);
    if (!by || !v.members.includes(by.sub) || item.vault !== v.id || item.epoch !== v.epoch || !signedOk(item, TAG.item)) return fail("vault_untrusted", t("core-misc.vault.untrusted"));
    return Effect.try({ try: () => decrypt(key, item.ct, itemContext(this.ws, v.id, item.id, item.version, item.epoch)), catch: asCoreError });
  }

  open(id: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const { lock, self: who } = yield* self.#ready();
      const { v, item } = yield* self.#find(lock, id);
      const name = item.listing?.name ?? v.name;
      const key = yield* self.#key(v, who, false, t("core-misc.vault.reason.open", { name }));
      const bytes = yield* self.#plain(lock, v, item, key);
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
      for (const v of Object.values(held(inner, self.ws).vaults)) {
        if (!trusted(lock, v) || !v.recovery || !v.members.includes(who.sub)) continue;
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
        const eph = new Uint8Array(32);
        inner.host.randomBytes(eph);
        const { sub: _, ...cert } = here;
        const keys = [...v.keys.filter((k) => k.cert.device !== who.device), { cert, wrapped: sealWith(cert.box, key, keyContext(self.ws, v.id, v.epoch), eph) }];
        const { sig: _s, ...rest } = v;
        yield* self.#putVault(sign({ ...rest, seq: v.seq + 1, keys, at: nowS(inner) }, TAG.vault, signer), held(inner, self.ws).at[v.id] ?? "");
        recovered++;
      }
      return { recovered, others };
    });
  }

  /// The request as held, or read again from the stations when it is not.
  #request(id: string): Effect.Effect<{ r: Request; station: string }, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      if (!held(inner, self.ws).requests[id]) {
        for (const s of stationsOf(inner, self.ws)) yield* Effect.ignore(readStation(inner, `${self.ws}/${s.id}`), { log: "Unhandled", message: "vault station read" });
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
  approve(id: string, scope: Scope, typed?: unknown): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      if (!["once", "hour", "chat"].includes(scope)) return yield* Effect.fail(CoreError.invalid("scope: once, hour or chat"));
      // The plain library's: its owner says so, nothing to open or sign (the station holds the value).
      const asked = yield* self.#request(id);
      if (asked.r.save) return yield* self.#keepSaved(asked.r, asked.station, typed);
      if (asked.r.vault === PLAIN) {
        const { r, station } = asked;
        const h = held(inner, self.ws);
        if (!allows(h.plain[r.item]?.listing?.lasts ?? h.plainLasts?.lasts, scope)) return yield* fail("vault_scope", t("core-misc.vault.scopeTooLong"));
        yield* self.#station(station, "POST", "/vault/plain/grants", { request: r.id, scope });
        self.#settled(r.id, { status: "granted", scope });
        return { request: r.id, scope };
      }
      const { lock, signer, self: who } = yield* self.#ready();
      const { r, station } = yield* self.#request(id);
      const v = yield* self.#vault(lock, r.vault);
      if (!v.members.includes(who.sub)) return yield* fail("vault_unknown", t("core-misc.vault.unknown"));
      const item = items(inner, self.ws, v.id)[r.item];
      if (!item || item.deleted) return yield* fail("vault_unknown", t("core-misc.vault.unknownItem"));
      if (!allows(item.listing?.lasts ?? v.lasts, scope)) return yield* fail("vault_scope", t("core-misc.vault.scopeTooLong"));
      const key = yield* self.#key(v, who, true, t("core-misc.vault.reason.approve", { name: item.listing?.name ?? v.name }));
      const bytes = yield* self.#plain(lock, v, item, key);
      const eph = new Uint8Array(32);
      inner.host.randomBytes(eph);
      const now = nowS(inner);
      const grant: Grant = sign(
        { v: 1 as const, ws: self.ws, request: r.id, vault: v.id, item: item.id, mode: r.mode, hosts: r.hosts ?? item.listing?.hosts ?? [], scope, exp: now + GRANT_SECS[scope], secret: sealWith(r.box, bytes, grantContext(self.ws, r.id), eph), at: now },
        TAG.grant,
        signer,
      );
      yield* self.#station(station, "POST", "/vault/grants", grant);
      self.#settled(r.id, { status: "granted", scope });
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
      const theirs = Object.values(h.vaults).filter(keyedHere).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1));
      const chosen = (h.vaults[r.vault] && keyedHere(h.vaults[r.vault]!) ? h.vaults[r.vault] : undefined) ?? theirs.find((x) => x.owner === who.sub) ?? theirs[0];
      // Their own vault this device has no key to yet: given it by a device that has (not a second one made here).
      if (!chosen && Object.values(h.vaults).some((v) => !v.deleted && trusted(lock, v) && v.owner === who.sub)) return yield* fail("vault_no_key", t("core-misc.vault.noKey"));
      const priv = yield* self.#boxKey(t("core-misc.vault.reason.save", { name: s.name }));
      if (boxPublic(priv) !== box) return yield* fail("vault_no_key", t(given ? "core-misc.vault.noKey" : "core-misc.vault.notSealedHere"));
      const body = yield* Effect.try({
        try: () => {
          const fields = given ?? JSON.parse(new TextDecoder().decode(openSeal(priv, sealed!.secret, saveContext(self.ws, r.id))));
          return {
            plain: plainOf({ kind: s.kind, name: s.name, fields, domains: [], notes: "" }),
            listing: listingOf({ name: s.name, kind: s.kind, modes: s.modes, hosts: s.hosts, ...(s.env ? { env: s.env } : {}) }),
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
      const scope = SCOPES.filter((x) => allows(body.listing?.lasts ?? vault.lasts, x)).at(-1)!;
      const now = nowS(inner);
      const eph = new Uint8Array(32);
      inner.host.randomBytes(eph);
      const grant: Grant | null = r.box
        ? sign(
            { v: 1 as const, ws: self.ws, request: r.id, vault: vault.id, item: r.item, mode: r.mode, hosts: r.mode === "proxy" ? (r.hosts ?? s.hosts) : [], scope, exp: now + GRANT_SECS[scope], secret: sealWith(r.box, utf8(JSON.stringify(body.plain)), grantContext(self.ws, r.id), eph), at: now },
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

  // ── the plain library (docs/vault.md 不加锁的库) ──

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
  unsealOwn(): Effect.Effect<{ plain: Plain; listing: Listing | null }[], CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      if (!able(inner) || lockOf(inner, self.ws) instanceof CoreError) return [];
      const ready = yield* Effect.result(self.#ready());
      if (ready._tag === "Failure") return [];
      const { lock, self: who } = ready.success;
      const out: { plain: Plain; listing: Listing | null }[] = [];
      for (const v of Object.values(held(inner, self.ws).vaults)) {
        if (!trusted(lock, v) || v.owner !== who.sub || !v.keys.some((k) => k.cert.device === who.device)) continue;
        const all = Object.values(items(inner, self.ws, v.id)).filter((i) => !i.deleted && i.epoch === v.epoch);
        if (all.length === 0) continue;
        const key = yield* self.#key(v, who, false, t("core-misc.vault.reason.unlock", { name: v.name }));
        for (const item of all) {
          const bytes = yield* Effect.result(self.#plain(lock, v, item, key));
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

  /// A request answered here (how: `outcome`): no longer waiting (the station says so too, as it tells it), its card off
  /// the 奏 page, how it went on its card in its chat at once.
  #settled(id: string, outcome: VaultOutcome): void {
    this.#inner.views?.local.vaultDecided(id, outcome);
    change(this.#inner, this.ws, (h) => {
      delete h.requests[id];
      delete h.asked[id];
    });
  }
}

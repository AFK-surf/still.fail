// The vault on this device (docs/vault.md): the vaults and items a workspace's stations hold, kept here as they do
// (only ciphertext and signatures), what the pages show of them, and what a person does with them. Keys live in the
// system's secure storage (Host `secureGet`…: an app's; a web page has none and is refused); a vault's key, once
// unsealed, is kept in memory UNLOCK_MS. Nothing a station or the cloud says is trusted for a key: a vault's version
// counts once its owner's device signed it and a box key once its device did, both checked against the workspace's
// lock, itself checked entry by entry here (vault/lock-check.ts).
//
// Topics:
//   vaults {workspace}            the vaults this person is in, whether this device is set up, requests to approve
//   vaultItems {workspace, vault} a vault's items: names once it is unlocked (the listed ones' always)
// Calls (vault.<name> {workspace, …}):
//   setup                         this device's box key (made once), its certificate published; the recovery words
//                                 the first time (`{words}`, shown once: never kept)
//   create {name, station?}       a vault of one's own, keyed for each of one's devices set up
//   addDevice {vault, device?}    the vault's key sealed for members' devices set up since (its owner signs)
//   putItem {vault, id?, plain, listing?}  an item written (a new one without `id`)
//   deleteItem {vault, item}      an item deleted
//   open {item}                   an item's plaintext (asks the person, unless its vault is unlocked)
//   recover {words}               this device keyed into one's vaults by the recovery words
//   approve {request, scope}      an agent's request granted: the item sealed to it, signed
//   deny {request}                turned down, signed
//   lock                          the unlocked keys forgotten now
//   state                         the `vaults` topic's value, as a call
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import { ulid } from "../accounts.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import type { Owner } from "../core/routing.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { type Entry, Signer } from "../lock.ts";
import type { Topic } from "../protocol.ts";
import { StationAddr } from "../station/addr.ts";
import { Priority } from "../sync/scheduler.ts";
import type { SpanContext } from "../trace.ts";
import { get, isObject, utf8 } from "../util.ts";
import {
  type BoxCert, type Deny, type Grant, type Item, type Listing, type Plain, type Request, type Scope, type Vault,
  TAG, boxPublic, decrypt, encryptWith, fromWords, grantContext, itemContext, keyContext, openSeal, recoveryPair, sealWith, sign, signedOk, toWords,
} from "../vault/crypto.ts";
import { type Checked, checkLock } from "../vault/lock-check.ts";
import { ofAddress } from "../workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;
type Of = Extract<Call, { kind: "vault" }>;

/// How long a vault's key stays unsealed in memory after it was last unsealed.
export const UNLOCK_MS = 5 * 60_000;
/// The secure storage's box key (X25519, asks the person to be read), and its public half where the app keeps the
/// rest (no asking needed to know it).
export const BOX_KEY = "vault-box";
export const BOX_PUB = "vault-box-pub";
/// How long a grant lasts: one use or an hour, a chat's for a day.
const GRANT_SECS: Record<Scope, number> = { once: 3600, hour: 3600, chat: 86400 };

/// What the workspace's stations hold, as held here (the `vault` record of the workspace): the vaults by id and the
/// station each is on, the box certificates by device, the requests waiting and the station each came from, and the
/// stations that hold no vault (a code: `vault_needs_lock`, `http_404` for one from before).
type Held = { vaults: Record<string, Vault>; at: Record<string, string>; boxes: Record<string, BoxCert>; requests: Record<string, Request>; asked: Record<string, string>; refused: Record<string, string> };

/// This core's unsealed vault keys (by `<vault>/<epoch>`, until when), the lock as checked, the signer's id and the
/// box key's public half once known.
type Mem = { keys: Map<string, { key: Uint8Array; until: number }>; checked: Map<string, { at: string; lock: Checked | CoreError }>; signer: string | null | undefined; box: string | null | undefined };
const mems = new WeakMap<Inner, Mem>();
const mem = (inner: Inner): Mem => {
  let m = mems.get(inner);
  if (!m) mems.set(inner, (m = { keys: new Map(), checked: new Map(), signer: undefined, box: undefined }));
  return m;
};

const EMPTY: Held = { vaults: {}, at: {}, boxes: {}, requests: {}, asked: {}, refused: {} };
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
  inner.store.invalidateAll((t) => (t.topic === "vaults" || t.topic === "vaultItems") && t.workspace === ws);
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
  // What this app keeps (no person asked): its signing key's id, its box key's public half.
  inner.runner.fork(
    Effect.gen(function* () {
      const m = mem(inner);
      m.signer = (yield* Effect.orElseSucceed(Signer.load(inner.host), () => null))?.id ?? null;
      const pub = yield* Effect.orElseSucceed(inner.host.storageGet(BOX_PUB), () => null);
      m.box = pub ? new TextDecoder().decode(pub) : null;
      inner.store.invalidateAll((t) => t.topic === "vaults" || t.topic === "vaultItems");
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
    const vaults = yield* Effect.result(ask(inner, address, "GET", "/vault/vaults"));
    if (vaults._tag === "Failure") {
      const e = vaults.failure;
      if (e.status !== undefined && e.status >= 400 && e.status < 500) change(inner, ws, (h) => void (h.refused[station] = e.code));
      return;
    }
    const list = arr(get(vaults.success, "vaults")) as Vault[];
    const all = arr(get(yield* ask(inner, address, "GET", "/vault/items"), "items")) as Item[];
    const boxes = arr(get(yield* ask(inner, address, "GET", "/vault/boxes"), "boxes")) as BoxCert[];
    // The requests are the keeper's (a station without one answers 404: none).
    const requests = yield* Effect.orElseSucceed(Effect.map(ask(inner, address, "GET", "/vault/requests"), (r) => arr(get(r, "requests")) as Request[]), () => [] as Request[]);
    const ids = new Set(list.map((v) => v.id));
    for (const v of list) changeItems(inner, ws, v.id, (held) => {
      for (const k of Object.keys(held)) delete held[k];
      for (const i of all) if (i.vault === v.id) held[i.id] = i;
    });
    change(inner, ws, (h) => {
      delete h.refused[station];
      for (const [id, at] of Object.entries(h.at)) {
        if (at === station && !ids.has(id)) {
          delete h.vaults[id];
          delete h.at[id];
        }
      }
      for (const v of list) {
        h.vaults[v.id] = v;
        h.at[v.id] = station;
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
      const known = held(inner, ws).vaults[d.id] !== undefined;
      change(inner, ws, (h) => {
        h.vaults[d.id] = d;
        h.at[d.id] = station;
      });
      // One this person was just put in: its items are read.
      if (!known) inner.scheduler.enqueue(address, `${address} vault/${d.id}`, Priority.background, readItems(inner, address, d.id));
      return;
    }
    case "vault-gone":
      if (typeof d?.id !== "string") return;
      change(inner, ws, (h) => {
        delete h.vaults[d.id];
        delete h.at[d.id];
      });
      inner.data.forgetRecord("vaultItems", `${ws}/${d.id}`);
      return;
    case "vault-item":
      if (typeof d?.vault === "string" && typeof d?.id === "string") changeItems(inner, ws, d.vault, (all) => void (all[d.id] = d));
      return;
    case "vault-box":
      if (typeof d?.device === "string") change(inner, ws, (h) => {
        if (!h.boxes[d.device] || h.boxes[d.device]!.at <= d.at) h.boxes[d.device] = d;
      });
      return;
    case "vault-request":
      if (typeof d?.id !== "string") return;
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

function readItems(inner: Inner, address: string, vault: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const ws = ofAddress(address);
    const all = arr(get(yield* ask(inner, address, "GET", `/vault/items?vault=${encodeURIComponent(vault)}`), "items")) as Item[];
    changeItems(inner, ws, vault, (held) => {
      for (const k of Object.keys(held)) delete held[k];
      for (const i of all) held[i.id] = i;
    });
  });
}

// ── what the pages show ──

function owner(inner: Inner): Owner {
  return {
    owns: (t: Topic) => t.topic === "vaults" || t.topic === "vaultItems",
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
      return { ok: t.topic === "vaults" ? vaultsView(inner, ws) : itemsView(inner, ws, String(t.vault)) };
    },
  };
}

const keyOf = (v: Vault) => `${v.id}/${v.epoch}`;
const unlocked = (inner: Inner, v: Vault) => (mem(inner).keys.get(keyOf(v))?.until ?? 0) > inner.host.nowMs();

/// Whether this host keeps keys as an app does, in the system's secure storage.
const able = (inner: Inner) => inner.host.appKeys === true && typeof inner.host.secureGet === "function" && typeof inner.host.secureSet === "function";

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
  if (lock instanceof CoreError) return base;
  const self = me(lock, m.signer);
  const vouched = certs(inner, ws, lock);
  const mine = self ? vouched.find((c) => c.device === self.device) : undefined;
  const vaults = Object.values(h.vaults)
    .filter((v) => trusted(lock, v) && sub !== null && v.members.includes(sub))
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1))
    .map((v) => {
      const keyed = new Map(v.keys.map((k) => [k.cert.device, k.cert.box]));
      const all = Object.values(items(inner, ws, v.id)).filter((i) => !i.deleted);
      return {
        id: v.id, name: v.name, owner: v.owner, ownerName: nameOf(v.owner), mine: v.owner === sub,
        members: v.members.map((s) => ({ sub: s, name: nameOf(s) })),
        station: h.at[v.id] ?? "", stationName: stationName.get(h.at[v.id] ?? "") ?? "",
        items: all.length, devices: v.keys.length, open: unlocked(inner, v),
        // Whether this device has a key to it; members' devices set up since that have none yet (its owner adds them).
        keyed: self !== null && mine !== undefined && keyed.get(self.device) === mine.box,
        missing: vouched.filter((c) => v.members.includes(c.sub) && keyed.get(c.device) !== c.box).length,
        recoverable: v.recovery !== undefined,
      };
    });
  const requests = Object.values(h.requests)
    .filter((r) => r.status === "pending" && h.vaults[r.vault] !== undefined && sub !== null && h.vaults[r.vault]!.members.includes(sub))
    .sort((a, b) => a.at - b.at)
    .map((r) => {
      const item = items(inner, ws, r.vault)[r.item];
      return {
        id: r.id, vault: r.vault, vaultName: h.vaults[r.vault]!.name, item: r.item, itemName: item?.listing?.name ?? null,
        session: r.session, chat: r.chat, mode: r.mode, reason: r.reason, command: r.command ?? null, hosts: r.hosts ?? [], at: r.at,
      };
    });
  return { ...base, canSign: self !== null, setUp: mine !== undefined && mine.box === m.box, vaults, requests };
}

/// The `vaultItems` topic: a vault's items, their names once it is unlocked here (else the listing's, if any).
export function itemsView(inner: Inner, ws: string, id: string): J {
  const v = held(inner, ws).vaults[id];
  const lock = lockOf(inner, ws);
  if (!v || lock instanceof CoreError || !trusted(lock, v)) return { vault: id, name: "", open: false, items: [] };
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
        listed: i.listing !== undefined, modes: i.listing?.modes ?? [], hosts: i.listing?.hosts ?? [],
      };
    })
    .sort((a, b) => ((a.name ?? "") < (b.name ?? "") ? -1 : (a.name ?? "") > (b.name ?? "") ? 1 : a.id < b.id ? -1 : 1));
  return { vault: id, name: v.name, open: key !== null, items: list };
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
    case "addDevice":
      return v.addDevice(p("vault"), str(c.params.device));
    case "putItem":
      return v.putItem(p("vault"), str(c.params.id), c.params.plain, c.params.listing);
    case "deleteItem":
      return v.deleteItem(p("vault"), p("item"));
    case "open":
      return v.open(p("item"));
    case "recover":
      return v.recover(p("words"));
    case "approve":
      return v.approve(p("request"), (str(c.params.scope) ?? "once") as Scope);
    case "deny":
      return v.deny(p("request"));
    default:
      return Effect.fail(CoreError.invalid(`no vault call ${c.name}`));
  }
}

const KINDS = ["token", "ssh_key", "login"];
const MODES = ["proxy", "ssh", "env"];

/// An item's plaintext as a call gives it: its kind and name, its fields as words.
function plainOf(v: unknown): Plain {
  if (!isObject(v) || !KINDS.includes(v.kind as string) || typeof v.name !== "string") throw CoreError.invalid("plain: {kind: token|ssh_key|login, name, fields, domains, notes}");
  const fields: Record<string, string> = {};
  for (const [k, x] of Object.entries(isObject(v.fields) ? v.fields : {})) if (typeof x === "string") fields[k] = x;
  return { kind: v.kind as Plain["kind"], name: v.name, fields, domains: arr(v.domains).filter((d) => typeof d === "string"), notes: typeof v.notes === "string" ? v.notes : "" };
}

function listingOf(v: unknown): Listing | undefined {
  if (v === undefined || v === null) return undefined;
  if (!isObject(v) || typeof v.name !== "string" || !KINDS.includes(v.kind as string)) throw CoreError.invalid("listing: {name, kind, modes, hosts, env?}");
  const modes = arr(v.modes).filter((m) => MODES.includes(m));
  return { name: v.name, kind: v.kind as Listing["kind"], modes, hosts: arr(v.hosts).filter((x) => typeof x === "string"), ...(typeof v.env === "string" ? { env: v.env } : {}) };
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
      mem(inner).signer = signer.id;
      return { lock, signer, self: who };
    });
  }

  #vault(lock: Checked, id: string): Effect.Effect<Vault, CoreError> {
    const v = held(this.#inner, this.ws).vaults[id];
    if (!v || !trusted(lock, v)) return fail("vault_unknown", t("core-misc.vault.unknown"));
    return Effect.succeed(v);
  }

  /// This device's box key, read from the secure storage (the person asked, saying `reason`).
  #boxKey(reason: string): Effect.Effect<Uint8Array, CoreError> {
    const inner = this.#inner;
    return Effect.gen(function* () {
      const priv = yield* Effect.mapError(inner.host.secureGet!(BOX_KEY, { user: true, reason }), (e) => new CoreError("vault_refused", e.message));
      if (priv === null || priv.length !== 32) return yield* fail("vault_not_set_up", t("core-misc.vault.notSetUp"));
      return priv;
    });
  }

  /// A vault's key: kept unsealed a while, else unsealed with this device's box key (the person asked); `fresh`: asked
  /// even when it is kept (an agent's grant).
  #key(v: Vault, self: { device: string }, fresh: boolean, reason: string): Effect.Effect<Uint8Array, CoreError> {
    const inner = this.#inner;
    const ws = this.ws;
    const self_ = this;
    return Effect.gen(function* () {
      const kept = mem(inner).keys.get(keyOf(v));
      if (!fresh && kept && kept.until > inner.host.nowMs()) return kept.key;
      const mine = v.keys.find((k) => k.cert.device === self.device);
      if (!mine) return yield* fail("vault_no_key", t("core-misc.vault.noKey"));
      const priv = yield* self_.#boxKey(reason);
      if (boxPublic(priv) !== mine.cert.box) return yield* fail("vault_no_key", t("core-misc.vault.noKey"));
      const key = yield* Effect.try({ try: () => openSeal(priv, mine.wrapped, keyContext(ws, v.id, v.epoch)), catch: asCoreError });
      self_.#keep(v, key);
      return key;
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
        h.vaults[v.id] = v;
        h.at[v.id] = station;
      });
      return v;
    });
  }

  /// This device set up for the vault in this workspace: its box key (made once, in the secure storage), its
  /// certificate signed and published to the workspace's stations. The person's recovery words the first time: one of
  /// their devices that published a recovery key already gives it (none are made then).
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
        yield* Effect.mapError(inner.host.secureSet!(BOX_KEY, priv, { user: true }), asCoreError);
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
      return { words, device: who.device, stations: published.filter(([, ok]) => ok).map(([id]) => id) };
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

  /// The vault's key sealed for members' devices set up since it was keyed (or `device` alone): its owner signs.
  addDevice(id: string, device: string | null): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      const { lock, signer, self: who } = yield* self.#ready();
      const v = yield* self.#vault(lock, id);
      if (v.owner !== who.sub) return yield* fail("vault_not_owner", t("core-misc.vault.notOwner"));
      const keyed = new Map(v.keys.map((k) => [k.cert.device, k.cert.box]));
      const add = certs(inner, self.ws, lock).filter((c) => v.members.includes(c.sub) && keyed.get(c.device) !== c.box && (device === null || c.device === device));
      if (add.length === 0) return { added: 0 };
      const key = yield* self.#key(v, who, false, t("core-misc.vault.reason.unlock", { name: v.name }));
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
      return { added: add.length };
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
        e.code === "vault_conflict" ? Effect.ignore(readItems(self.#inner, `${self.ws}/${station}`, v.id)) : Effect.void,
      );
      const item = (get(said, "item") as Item | undefined) ?? next;
      changeItems(self.#inner, self.ws, v.id, (all) => void (all[item.id] = item));
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
        for (const s of stationsOf(inner, self.ws)) yield* Effect.ignore(readStation(inner, `${self.ws}/${s.id}`));
      }
      const h = held(inner, self.ws);
      const r = h.requests[id];
      if (!r || r.status !== "pending") return yield* fail("vault_no_request", t("core-misc.vault.noRequest"));
      return { r, station: h.asked[id] ?? "" };
    });
  }

  /// An agent's request granted: the item's plaintext sealed to the keeper's key for this request, signed by this
  /// device (the person asked each time, whether the vault is unlocked or not).
  approve(id: string, scope: Scope): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const inner = self.#inner;
      if (!["once", "hour", "chat"].includes(scope)) return yield* Effect.fail(CoreError.invalid("scope: once, hour or chat"));
      const { lock, signer, self: who } = yield* self.#ready();
      const { r, station } = yield* self.#request(id);
      const v = yield* self.#vault(lock, r.vault);
      if (!v.members.includes(who.sub)) return yield* fail("vault_unknown", t("core-misc.vault.unknown"));
      const item = items(inner, self.ws, v.id)[r.item];
      if (!item || item.deleted) return yield* fail("vault_unknown", t("core-misc.vault.unknownItem"));
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
      self.#settled(r.id);
      return { request: r.id, scope, exp: grant.exp };
    });
  }

  deny(id: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const { signer } = yield* self.#ready();
      const { r, station } = yield* self.#request(id);
      const deny: Deny = sign({ v: 1 as const, ws: self.ws, request: r.id, at: nowS(self.#inner) }, TAG.deny, signer);
      yield* self.#station(station, "POST", "/vault/denials", deny);
      self.#settled(r.id);
      return { request: r.id };
    });
  }

  /// A request answered here: no longer waiting (the station says so too, as it tells it).
  #settled(id: string): void {
    change(this.#inner, this.ws, (h) => {
      delete h.requests[id];
      delete h.asked[id];
    });
  }
}

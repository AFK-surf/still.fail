// Who may use this rig (a station that only runs tasks, 2026-11-10): its own record, which nothing but its person's signature changes. A rig
// runs what the workspace's stations send it, for the chats its person granted it to (as a vault's secret is granted:
// a chat, for a time) or, with 免批准 on, for every chat of the workspace, as a station does. The stations bring what
// the person signed (a grant, one taken back, the settings: client/core-ts/src/rig-form.ts) with that person's own
// lock; the rig checks each against the lock it pinned as it joined (`enroll --rig <hash>`), so neither a station's
// database, an agent on it, nor the cloud gives a chat this machine.
//
// What it cannot tell: which chat a station's request is really for. The station says, as it says whose a vault's
// grant is; an agent that owns its station can use a grant another chat of that station holds, and no more.
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import {
  type AddBody, type DeviceBody, type Device, type GrantBody, type RevokeBody, type SettingsBody, type Signed, type Kind, TIMEOUT_MAX, signedBytes, wellFormed,
  FULL_FOR, type FullBody,
} from "../../../client/core-ts/src/rig-form.ts";
import { type Entry, entryHash, personFold, signatureOk } from "../cloud/lock.ts";
import { writePrivate } from "../ops/files.ts";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";

const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest();

/// Whether `signed`'s signature is its key's over its body, as a statement of `kind`.
export function signatureHolds(kind: Kind, signed: Signed<unknown>): boolean {
  try {
    return /^([0-9a-f]{2})+$/.test(signed.sig.sig) && signatureOk(signed.sig.key, Buffer.from(signed.sig.sig, "hex"), Buffer.from(signedBytes(kind, signed.body, sha256)));
  } catch {
    return false;
  }
}

/// What this machine is: its key's id, its workspace, whose it is and that person's own lock (cloud.json's `rig`).
export type Self = { id: string; workspace: string; owner: string; person: string };

/// A grant in force: what was signed, and when the chat last used the rig (ms).
export type Live = { signed: Signed<GrantBody>; usedAt: number };
export type Ended = { request: string; station: string; session: string; why: "expired" | "idle" | "revoked" | "released" | "closed" | "removed"; device?: string };

type Kept = {
  /// The person's own lock, the longest chain of it seen (a device taken off it signs nothing from then on).
  chain: Entry[];
  settings: Signed<SettingsBody> | null;
  add: Signed<AddBody> | null;
  grants: Record<string, Live>;
  /// Grants taken back (their request → when they would have ended, unix seconds): one brought again counts for nothing.
  revoked: Record<string, number>;
  /// The devices its person attached to it (rig-form.ts `DeviceBody`), by id, with each one's own settings (免批准).
  devices: Record<string, Signed<DeviceBody>>;
  deviceSettings: Record<string, Signed<SettingsBody>>;
};

export type GrantsDeps = {
  /// Where it is kept (<data>/rig/grants.json).
  path: string;
  self: () => Self | null;
  /// Whether a chat (a station's session) has a task running here: that is use, however long since it last asked.
  busy: (station: string, session: string) => boolean;
  /// A chat lost the rig: what it runs here stops.
  stop: (station: string, session: string) => void | Promise<void>;
  /// The chats (station, session) with something running here, for those left without a grant when 免批准 goes off.
  running: () => { station: string; session: string }[];
  /// A grant ended here: its station is told.
  ended: (ended: Ended) => void;
  /// A chat (or every chat: none named) may have lost a device of this rig: its connections to it are looked at again
  /// (`deviceRefusal` with no use), and those no longer let through cut.
  cut?: (device: string, station: string | null, session: string | null) => void;
  /// Anything a station shows of this rig changed (grants, settings).
  changed: () => void;
  fibers?: Fibers;
};

export class Refusal extends Error {}

export class RigGrants {
  readonly #d: GrantsDeps;
  readonly #fibers: Fibers;
  #kept: Kept = { chain: [], settings: null, add: null, grants: {}, revoked: {}, devices: {}, deviceSettings: {} };
  #armed: (() => void) | null = null;

  constructor(deps: GrantsDeps) {
    this.#d = deps;
    this.#fibers = deps.fibers ?? new Fibers("rig");
    if (existsSync(deps.path)) {
      try {
        const raw = JSON.parse(readFileSync(deps.path, "utf8"));
        this.#kept = {
          chain: Array.isArray(raw?.chain) ? raw.chain : [],
          settings: wellFormed("settings", raw?.settings) ? raw.settings : null,
          add: wellFormed("add", raw?.add) ? raw.add : null,
          grants: Object.fromEntries(Object.entries((raw?.grants ?? {}) as Record<string, Live>).filter(([, g]) => wellFormed("grant", g?.signed) && Number.isSafeInteger(g.usedAt))),
          revoked: Object.fromEntries(Object.entries((raw?.revoked ?? {}) as Record<string, number>).filter(([, exp]) => Number.isSafeInteger(exp))),
          devices: Object.fromEntries(Object.entries((raw?.devices ?? {}) as Record<string, Signed<DeviceBody>>).filter(([id, d]) => wellFormed("device", d) && d.body.device.id === id && !d.body.removed)),
          deviceSettings: Object.fromEntries(Object.entries((raw?.deviceSettings ?? {}) as Record<string, Signed<SettingsBody>>).filter(([id, d]) => wellFormed("settings", d) && d.body.device === id)),
        };
      } catch (error) {
        // Unreadable: nobody is granted anything until the person signs again; 免批准 is off.
        log.warn("rig", "the rig's grants could not be read; none holds until they are signed again", { error: (error as Error).message });
      }
    }
    this.#look();
  }

  #secs(): number {
    return Math.floor(this.#fibers.now() / 1000);
  }

  #save(): void {
    writePrivate(this.#d.path, JSON.stringify(this.#kept));
  }

  #self(): Self {
    const self = this.#d.self();
    if (self === null) throw new Refusal("this machine is no rig of a workspace now");
    return self;
  }

  /// The person's own lock as brought (`chain`, the longest a station has): taken when it is the lock pinned here and
  /// goes on from the one kept. One that does not hold, or is another's, is refused.
  takeChain(chain: unknown): void {
    if (!Array.isArray(chain) || chain.length === 0) return;
    const self = this.#self();
    const kept = this.#kept.chain;
    const brought = chain as Entry[];
    let genesis: string;
    try {
      genesis = entryHash(brought[0]!);
    } catch {
      throw new Refusal("the lock brought is malformed");
    }
    if (genesis !== self.person) throw new Refusal("the lock brought is not the one this rig's person pinned on it");
    if (brought.length <= kept.length) {
      if (!brought.every((e, i) => same(e, kept[i]))) throw new Refusal("the lock brought is at odds with the one this rig has of its person");
      return;
    }
    if (!kept.every((e, i) => same(e, brought[i]))) throw new Refusal("the lock brought is at odds with the one this rig has of its person");
    try {
      personFold(brought, self.owner);
    } catch (error) {
      throw new Refusal(`the lock brought does not hold: ${(error as Error).message}`);
    }
    this.#kept.chain = brought;
    this.#save();
  }

  /// The keys on the person's lock now.
  #keys(): Set<string> {
    const self = this.#d.self();
    if (self === null || this.#kept.chain.length === 0) return new Set();
    try {
      return new Set(personFold(this.#kept.chain, self.owner).devices.map((d) => d.key));
    } catch {
      return new Set();
    }
  }

  /// A statement of `kind` checked: its shape, that it is about this rig in this workspace by its person, and that a
  /// key on the person's lock signed it. Throws why not.
  #checked<B extends { sub: string; ws: string; rig: string }>(kind: Kind, signed: unknown): Signed<B> {
    const self = this.#self();
    if (!wellFormed(kind, signed)) throw new Refusal(`not a rig's ${kind}`);
    const s = signed as Signed<B>;
    if (s.body.rig !== self.id || s.body.ws !== self.workspace) throw new Refusal("signed for another rig or workspace");
    if (s.body.sub !== self.owner) throw new Refusal("not signed by this rig's person");
    if (!this.#keys().has(s.sig.key)) throw new Refusal("signed by a key that is not on this rig's person's own lock");
    if (!signatureHolds(kind, s)) throw new Refusal("the signature does not hold");
    return s;
  }

  /// A grant its station brings: in force from now, until it ends. Until when at the latest (unix seconds).
  grant(peer: string, signed: unknown, chain?: unknown): { until: number } {
    this.takeChain(chain);
    const s = this.#checked<GrantBody>("grant", signed);
    const b = s.body;
    if (b.station !== peer) throw new Refusal("a grant is brought by its chat's own station");
    const now = this.#secs();
    if (b.exp <= now) throw new Refusal("the grant has expired");
    if (b.request in this.#kept.revoked) throw new Refusal("the grant was taken back");
    if (b.device !== undefined && !(b.device in this.#kept.devices)) throw new Refusal("no such device on this rig");
    const was = this.#kept.grants[b.request];
    this.#kept.grants[b.request] = { signed: s, usedAt: was?.usedAt ?? this.#fibers.now() };
    this.#save();
    this.#look();
    this.#d.changed();
    return { until: b.exp };
  }

  /// A grant taken back by the person (signed), brought by any station.
  revoke(signed: unknown, chain?: unknown): void {
    this.takeChain(chain);
    const s = this.#checked<RevokeBody>("revoke", signed);
    const live = this.#kept.grants[s.body.request];
    this.#kept.revoked[s.body.request] = live?.signed.body.exp ?? this.#secs() + TIMEOUT_MAX;
    if (live) this.#end(live, "revoked");
    else this.#save();
  }

  /// A grant given back by its own station (the chat archived, or its agent done with the rig): no signature needed
  /// to have less.
  release(peer: string, request: string): boolean {
    const live = this.#kept.grants[request];
    if (!live || live.signed.body.station !== peer) return false;
    this.#end(live, "released");
    return true;
  }

  /// The settings as signed: taken when newer than those kept. With 免批准 off again, the chats left with no grant
  /// lose what they run here.
  settings(signed: unknown, chain?: unknown): void {
    this.takeChain(chain);
    const s = this.#checked<SettingsBody>("settings", signed);
    if (s.body.device !== undefined) return this.#deviceSettings(s);
    const had = this.#kept.settings;
    if (had !== null && s.body.seq <= had.body.seq) {
      if (s.body.seq === had.body.seq && had.sig.sig === s.sig.sig) return;
      throw new Refusal("older than the settings this rig has");
    }
    this.#kept.settings = s;
    this.#save();
    if (had?.body.open === true && !s.body.open) {
      for (const { station, session } of this.#d.running()) if (this.#grantOf(station, session) === null) void this.#d.stop(station, session);
      for (const id of Object.keys(this.#kept.devices)) if (!this.#deviceOpen(id)) this.#d.cut?.(id, null, null);
    }
    this.#d.changed();
  }

  /// A device's own settings (免批准 on it alone): taken when newer than its kept ones. Off again, the chats with no
  /// grant of it (or of the rig) lose their connections to it.
  #deviceSettings(s: Signed<SettingsBody>): void {
    const id = s.body.device!;
    if (!(id in this.#kept.devices)) throw new Refusal("no such device on this rig");
    const had = this.#kept.deviceSettings[id];
    if (had !== undefined && s.body.seq <= had.body.seq) {
      if (s.body.seq === had.body.seq && had.sig.sig === s.sig.sig) return;
      throw new Refusal("older than the settings this device has");
    }
    this.#kept.deviceSettings[id] = s;
    this.#save();
    if (had?.body.open === true && !s.body.open && !this.open()) this.#d.cut?.(id, null, null);
    this.#d.changed();
  }

  /// A device attached to this rig by its person, or (`removed`) taken off it: the grants of it end with it.
  device(signed: unknown, chain?: unknown): void {
    this.takeChain(chain);
    const s = this.#checked<DeviceBody>("device", signed);
    const id = s.body.device.id;
    const had = this.#kept.devices[id];
    if (had !== undefined && s.body.at < had.body.at) throw new Refusal("older than what this rig has of the device");
    if (s.body.removed) {
      delete this.#kept.devices[id];
      delete this.#kept.deviceSettings[id];
      this.#save();
      for (const live of Object.values(this.#kept.grants)) if (live.signed.body.device === id) this.#end(live, "removed");
      this.#d.cut?.(id, null, null);
    } else {
      this.#kept.devices[id] = s;
      this.#save();
    }
    this.#d.changed();
  }

  /// The devices attached here.
  devices(): Device[] {
    return Object.values(this.#kept.devices).map((d) => d.body.device);
  }

  #deviceOpen(id: string): boolean {
    const s = this.#kept.deviceSettings[id];
    return s !== undefined && s.body.open;
  }

  /// Why a chat may not reach device `id` here now, or null: it may (a grant of the rig, or of the device; 免批准 on
  /// either), and this is use.
  /// `use`: false only to look again at a connection already open (`cut`), which is no use of it.
  deviceRefusal(workspace: string, station: string, session: string, id: string, use = true): string | null {
    const self = this.#d.self();
    if (self === null) return "this machine is no rig of a workspace now";
    if (workspace !== self.workspace) return "this rig is of another workspace";
    if (!(id in this.#kept.devices)) return "no such device on this rig";
    if (this.open() || this.#deviceOpen(id)) return null;
    if (use) this.#look();
    const live = this.#grantOf(station, session) ?? this.#deviceGrantOf(station, session, id);
    if (live === null) return "this chat has no grant of this device: ask for one with device_use (its owner approves it in still.fail)";
    if (use) this.#used(live);
    return null;
  }

  #deviceGrantOf(station: string, session: string, id: string): Live | null {
    for (const live of Object.values(this.#kept.grants)) {
      const b = live.signed.body;
      if (b.station === station && b.session === session && b.device === id) return live;
    }
    return null;
  }

  /// What the person signed taking this rig into a workspace in security mode (rig-form.ts `AddBody`): kept to show the
  /// stations that ask (`proof`). Checked here only for being about this rig; each station checks who signed it
  /// against the workspace's lock, which this rig does not judge.
  added(signed: unknown): void {
    const self = this.#self();
    if (!wellFormed("add", signed)) throw new Refusal("not a rig's add");
    const s = signed as Signed<AddBody>;
    if (s.body.rig !== self.id || s.body.ws !== self.workspace || s.body.sub !== self.owner) throw new Refusal("signed for another rig, workspace or person");
    if (!signatureHolds("add", s)) throw new Refusal("the signature does not hold");
    this.#kept.add = s;
    this.#save();
  }

  /// Its person's word that this machine is to be a whole station again (rig-form.ts `FullBody`), checked as a grant
  /// is and not older than `FULL_FOR`: who signed it.
  full(signed: unknown, chain?: unknown): Signed<FullBody> {
    this.takeChain(chain);
    const s = this.#checked<FullBody>("full", signed);
    const now = this.#secs();
    if (s.body.at > now + 300 || now - s.body.at > FULL_FOR) throw new Refusal("signed too long ago: switch it again");
    return s;
  }

  proof(): Signed<AddBody> | null {
    return this.#kept.add;
  }

  open(): boolean {
    const self = this.#d.self();
    const s = this.#kept.settings;
    return self !== null && s !== null && s.body.open && s.body.rig === self.id && s.body.ws === self.workspace;
  }

  #grantOf(station: string, session: string): Live | null {
    // (a grant of one device alone is not one of the rig)
    for (const live of Object.values(this.#kept.grants)) if (live.signed.body.station === station && live.signed.body.session === session && live.signed.body.device === undefined) return live;
    return null;
  }

  /// Why a chat (`session` of `station`) may not use this rig now, or null: it may, and this is use.
  refusal(workspace: string, station: string, session: string): string | null {
    const self = this.#d.self();
    if (self === null) return "this machine is no rig of a workspace now";
    if (workspace !== self.workspace) return "this rig is of another workspace";
    if (this.open()) return null;
    this.#look();
    const live = this.#grantOf(station, session);
    if (live === null) return "this chat has no grant of this station, which only runs tasks: ask for one with station_use (its owner approves it in still.fail)";
    this.#used(live);
    return null;
  }

  /// A grant used now. Written down a minute apart at most: a rig started again goes on from when it was last used,
  /// not from when it was granted.
  #used(live: Live): void {
    const now = this.#fibers.now();
    const write = now - live.usedAt >= 60_000;
    live.usedAt = now;
    if (write) {
      this.#save();
      this.#look();
    }
  }

  /// Why a station may not reach a service on this rig now, or null: one of its chats holds a grant (or 免批准 is on).
  stationRefusal(workspace: string, station: string): string | null {
    const self = this.#d.self();
    if (self === null || workspace !== self.workspace) return "this rig is of another workspace";
    if (this.open()) return null;
    this.#look();
    const lives = Object.values(this.#kept.grants).filter((g) => g.signed.body.station === station && g.signed.body.device === undefined);
    if (lives.length === 0) return "no chat of that station has a grant of this one";
    for (const live of lives) this.#used(live);
    return null;
  }

  /// What a station is told of this rig (`describe`): whose it is, whether 免批准 is on, and the grants in force.
  view(): {
    owner: string; person: string; open: boolean; settings: number;
    grants: { request: string; station: string; session: string; chat: string; title: string; by: string; timeout: GrantBody["timeout"]; exp: number; until: number; device?: string }[];
    devices: (Device & { open: boolean; settings: number })[];
  } | null {
    const self = this.#d.self();
    if (self === null) return null;
    this.#look();
    return {
      owner: self.owner,
      person: self.person,
      open: this.open(),
      settings: this.#kept.settings?.body.seq ?? 0,
      grants: Object.values(this.#kept.grants).map((g) => {
        const b = g.signed.body;
        return { request: b.request, station: b.station, session: b.session, chat: b.chat, title: b.title, by: b.by, timeout: b.timeout, exp: b.exp, until: this.#until(g), ...(b.device !== undefined ? { device: b.device } : {}) };
      }),
      devices: Object.values(this.#kept.devices).map((d) => ({ ...d.body.device, open: this.#deviceOpen(d.body.device.id), settings: this.#kept.deviceSettings[d.body.device.id]?.body.seq ?? 0 })),
    };
  }

  /// Until when a grant holds if the chat uses the rig no more (unix seconds).
  #until(g: Live): number {
    const b = g.signed.body;
    return b.timeout.kind === "idle" ? Math.min(b.exp, Math.floor(g.usedAt / 1000) + b.timeout.seconds) : b.exp;
  }

  #end(live: Live, why: Ended["why"]): void {
    const b = live.signed.body;
    delete this.#kept.grants[b.request];
    this.#save();
    if (b.device !== undefined) {
      if (this.#grantOf(b.station, b.session) === null && !this.open() && !this.#deviceOpen(b.device)) this.#d.cut?.(b.device, b.station, b.session);
    } else if (this.#grantOf(b.station, b.session) === null && !this.open()) {
      // Another grant of the same chat keeps what it runs; its devices go with the rig's grant, but for one of their own.
      void this.#d.stop(b.station, b.session);
      for (const id of Object.keys(this.#kept.devices)) if (this.#deviceGrantOf(b.station, b.session, id) === null && !this.#deviceOpen(id)) this.#d.cut?.(id, b.station, b.session);
    }
    this.#d.ended({ request: b.request, station: b.station, session: b.session, why, ...(b.device !== undefined ? { device: b.device } : {}) });
    this.#d.changed();
    this.#look();
  }

  /// Ends the grants whose time is up, and arms the wait for the next to be.
  #look(): void {
    this.#armed?.();
    this.#armed = null;
    const now = this.#secs();
    let next = Infinity;
    for (const live of Object.values(this.#kept.grants)) {
      const b = live.signed.body;
      if (b.exp <= now) {
        this.#end(live, "expired");
        return;
      }
      if (b.timeout.kind === "idle") {
        // A task of the chat's still running here is use: an idle grant does not end under a long build.
        if (this.#d.busy(b.station, b.session)) live.usedAt = this.#fibers.now();
        else if (Math.floor(live.usedAt / 1000) + b.timeout.seconds <= now) {
          this.#end(live, "idle");
          return;
        }
      }
      next = Math.min(next, this.#until(live));
    }
    for (const [request, exp] of Object.entries(this.#kept.revoked)) if (exp <= now) delete this.#kept.revoked[request];
    // The deadline of the grant that ends first (a timeout, not a look at anything of another part).
    if (next !== Infinity) this.#armed = this.#fibers.after(Math.max(1, next - now) * 1000, () => this.#look());
  }

  async close(): Promise<void> {
    this.#armed?.();
    if (this.#d.fibers === undefined) await this.#fibers.close();
  }
}

const same = (a: unknown, b: unknown) => {
  try {
    return entryHash(a as Entry) === entryHash(b as Entry);
  } catch {
    return false;
  }
};

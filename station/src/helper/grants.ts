// What macOS lets still.fail Helper do on this Mac (docs/remote-screens.md "Grants"): Screen Recording and
// Accessibility (the desktop seen and driven), and the folders macOS protects (the drive's: Documents, Desktop,
// Downloads, removable and network disks), and whether the station may reach the LAN it is on (macOS's Local Network:
// the station's own, looked at by sending to it, mesh/lan.ts `lanReach`). One look at them (the helper's `status`) is kept for whatever asks: the
// desktop's screen, the station's page (the overview's `permissions`), the agents' `permissions` tool; at most FRESH_MS
// old where it matters (a view opened, a grant asked for), looked at again when the helper says a grant changed or comes
// back, and in the background once a page reads it SHOWN_MS after the last look.
//
// The helper's window asks for a grant on this Mac, once: not again (nor brought forward) while it is up asking for it,
// nor for AGAIN_MS after it was shown for it, so an agent asking again, the drive retrying or a person refreshing never
// puts it up again; whoever asks then is told it was closed a moment ago. A person's own ask (the station's page: a
// client retrying it is answered once, by its key) puts it up again however lately it was shown: 2026-10-20 a person
// closed it, granted nothing, tapped Request again and was told to come back in a few minutes.
import { execFile } from "node:child_process";
import { lstatSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { LOCAL_NETWORK_SETTINGS, lanReach, localNetworkName } from "../mesh/lan.ts";
import { platform } from "../platform/index.ts";
import type { HelperApp } from "./app.ts";

/// The grants, in the order they are shown: the screen's two, the folders', then the LAN's (`localNetwork`: not the
/// helper's but the station's own; `network` is network disks).
export const GRANTS = ["capture", "control", "documents", "desktop", "downloads", "removable", "network", "localNetwork"] as const;
export type GrantId = (typeof GRANTS)[number];
export type GrantState = "granted" | "denied" | "unknown";
export const isGrant = (v: unknown): v is GrantId => typeof v === "string" && (GRANTS as readonly string[]).includes(v);
const SCREEN: readonly GrantId[] = ["capture", "control"];
/// No window of the helper's asks for Local Network: System Settings' list comes up instead.
export { LOCAL_NETWORK_SETTINGS };

/// The window shown for a grant is not shown (nor brought forward) again for that grant this soon after.
export const AGAIN_MS = 3 * 60_000;
/// A look at the grants is this fresh at most where it matters (a list asked for twice at once looks once).
const FRESH_MS = 2_000;
/// How long the window has to come up after the helper answered `permissions.show`, looked at every UP_MS.
const UP_TRIES = 20;
const UP_MS = 100;
/// The station's page reads what was looked at last; looked at again (in the background) once it is this old.
const SHOWN_MS = 30_000;

/// What became of the helper's window for a grant missing: `up` (shown now, or already up asking for it), `closed`
/// (shown a moment ago and closed since: not shown again yet), `none` (it could not be shown).
export type WindowState = "up" | "closed" | "none";

/// What the helper's `status` says.
export type HelperStatus = {
  capture: boolean;
  control: boolean;
  responsible?: { pid: number; path: string; name: string };
  display?: { id: number; width: number; height: number };
  /// What its running process may do (a grant is had once it starts again).
  live?: { capture: boolean; control: boolean };
  /// Whether its window asking for the grants is up, and what it asks for.
  asking?: boolean;
  asked?: string[];
  /// The drive's folder grants (granted, denied, unknown; Full Disk Access as `all`, counted in each).
  files?: Record<string, string>;
};

/// The grants as the station's page and the agents are told them: each with its state, those the window asks for now,
/// and whether the screen can be seen and driven (a person can then grant the rest from wherever they are).
/// `localNetworkName`: what System Settings' Local Network list names the station by, with `localNetwork` among them.
export type GrantsView = { grants: { grant: GrantId; state: GrantState }[]; asking: GrantId[]; screen: boolean; localNetworkName?: string };

/// A grant that cannot be asked for now, and why (`key` of the station's words).
export class GrantRefused extends Error {
  readonly key: string;
  constructor(key: string) {
    super(key);
    this.key = key;
  }
}

export function grantState(s: HelperStatus, grant: GrantId): GrantState {
  if (grant === "capture" || grant === "control") return s[grant] ? "granted" : "unknown";
  const said = s.files?.[grant];
  return said === "granted" || said === "denied" ? said : "unknown";
}

export class HelperGrants {
  readonly helper: HelperApp;
  readonly #folders: boolean;
  readonly #now: () => number;
  #status: HelperStatus | null = null;
  #checked = -Infinity;
  #checking: Promise<void> | null = null;
  readonly #asked = new Map<GrantId, number>();
  readonly #listeners = new Set<() => void>();
  /// Where removable and network disks are mounted (the test's own).
  readonly #volumes: string;
  readonly #mounts: () => string[];
  /// Whether the station may reach its LAN, as last looked at (null: no LAN, or not known).
  #lan: GrantState | null = null;
  readonly #reach: () => Promise<"granted" | "denied" | null>;
  readonly #open: (url: string) => void;

  constructor(options: {
    helper: HelperApp;
    folders?: boolean;
    now?: () => number;
    volumes?: string;
    /// The disks mounted elsewhere than `volumes` (platform `mounts`): OrbStack's NFS in the home.
    mounts?: () => string[];
    reach?: () => Promise<"granted" | "denied" | null>;
    open?: (url: string) => void;
  }) {
    this.helper = options.helper;
    this.#folders = options.folders ?? true;
    this.#now = options.now ?? (() => wall.now());
    this.#volumes = options.volumes ?? "/Volumes";
    this.#mounts = options.mounts ?? (() => platform.mounts());
    this.#reach = options.reach ?? (() => lanReach());
    this.#open = options.open ?? ((url) => void execFile("open", [url], () => undefined));
    // A grant changed (its window saw it), or the helper came back: looked at again.
    options.helper.listen((event) => {
      if (event.event === "grants") void this.refresh(true);
    });
    options.helper.onBack(() => void this.refresh(true));
  }

  /// The last look; null before the first.
  status(): HelperStatus | null {
    return this.#status;
  }

  /// Told when what is known of them changed.
  onChange(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => void this.#listeners.delete(listener);
  }

  /// The grants as macOS has them now (at most FRESH_MS old, unless `force`); the helper started for it.
  refresh(force = false): Promise<void> {
    if (!force && this.#now() - this.#checked < FRESH_MS) return Promise.resolve();
    this.#checking ??= Promise.all([
      this.#reach().then(
        (lan) => this.#learnLan(lan),
        () => undefined,
      ),
      this.helper.request({ op: "status" }).then(
        (status: HelperStatus) => this.#learn(status),
        (error) => log.warn("helper", "still.fail Helper did not answer", { error: (error as Error).message }),
      ),
    ])
      .then(() => undefined)
      .finally(() => (this.#checking = null));
    return this.#checking;
  }

  #learnLan(lan: GrantState | null) {
    if (lan === this.#lan) return;
    this.#lan = lan;
    if (this.#status !== null) for (const f of [...this.#listeners]) f();
  }

  /// A grant's state as last looked at.
  state(grant: GrantId): GrantState {
    if (grant === "localNetwork") return this.#lan ?? "unknown";
    return this.#status === null ? "unknown" : grantState(this.#status, grant);
  }

  #learn(status: HelperStatus) {
    this.#checked = this.#now();
    const before = JSON.stringify(this.#status);
    this.#status = status;
    if (JSON.stringify(status) !== before) for (const f of [...this.#listeners]) f();
  }

  /// What the station's page shows, as last looked at (null before the first look: looked at now, told when known).
  view(): GrantsView | null {
    if (this.#now() - this.#checked >= SHOWN_MS) void this.refresh();
    const s = this.#status;
    if (s === null) return null;
    const grants = GRANTS.filter((g) => (g === "localNetwork" ? this.#lan !== null : this.#folders || SCREEN.includes(g))).map((grant) => ({
      grant,
      state: this.state(grant),
    }));
    const asking = s.asking === true ? (s.asked ?? []).filter(isGrant) : [];
    return { grants, asking, screen: s.capture && s.control, ...(this.#lan !== null ? { localNetworkName: localNetworkName() } : {}) };
  }

  /// The helper's window asking for `grant` on this Mac (in `words`; `paths` a disk's folder for its grant), unless it
  /// is up asking for it or was shown for it within AGAIN_MS (`again`: a person's own ask, shown however lately it was).
  async show(grant: GrantId, words: Record<string, unknown>, paths?: Record<string, string>, again = false): Promise<WindowState> {
    const status: HelperStatus | null = await this.helper.request({ op: "status" }).catch(() => null);
    if (status !== null) this.#learn(status);
    // Up already asking for it: left as it is, not brought forward.
    if (status?.asking === true && Array.isArray(status.asked) && status.asked.includes(grant)) return "up";
    // Shown for it a moment ago: not again (whatever asks again), until AGAIN_MS have gone by.
    const last = this.#asked.get(grant);
    if (!again && last !== undefined && this.#now() - last < AGAIN_MS) return status === null ? "up" : "closed";
    this.#asked.set(grant, this.#now());
    try {
      await this.helper.request({ op: "permissions.show", words, grants: [grant], ...(paths ? { paths } : {}) });
      // The helper puts it up on its main thread after it answers: what it asks for is known (and told) once it says so.
      await this.#upFor(grant);
      return "up";
    } catch (error) {
      log.warn("helper", "still.fail Helper's window did not show", { error: (error as Error).message });
      return "none";
    }
  }

  /// Until the helper says its window asks for `grant` (at most a moment: UP_TRIES looks), learnt either way.
  async #upFor(grant: GrantId) {
    for (let i = 0; i < UP_TRIES; i++) {
      const status: HelperStatus | null = await this.helper.request({ op: "status" }).catch(() => null);
      if (status !== null) this.#learn(status);
      if (status === null || (status.asking === true && status.asked?.includes(grant))) return;
      await wall.sleep(UP_MS);
    }
  }

  /// A person (or an agent) asks for `grant`: the window up for it, unless it is granted already (`granted`); whether
  /// the screen can be seen and driven (the person can then click in the window from wherever they are). A disk's grant
  /// needs a disk of its kind mounted (macOS asks as the app opens one): refused (`GrantRefused`) when none is. `again`:
  /// a person's own ask, shown however lately it was.
  async request(grant: GrantId, words: Record<string, unknown>, again = false): Promise<{ window: WindowState | "granted"; screen: boolean }> {
    if (!this.#folders && !SCREEN.includes(grant) && grant !== "localNetwork") throw new GrantRefused("station.permissions.unknown");
    await this.refresh(true);
    if (grant === "localNetwork") return { window: this.#settings(again), screen: this.#status?.capture === true && this.#status.control === true };
    const s = this.#status;
    if (s === null) throw new GrantRefused("station.permissions.noHelper");
    const screen = () => this.#status?.capture === true && this.#status.control === true;
    if (grantState(s, grant) === "granted") return { window: "granted", screen: screen() };
    let paths: Record<string, string> | undefined;
    if (grant === "removable" || grant === "network") {
      const disk = await this.#disk(grant);
      if (disk === null) throw new GrantRefused(grant === "removable" ? "station.permissions.noDisk" : "station.permissions.noNetworkDisk");
      paths = { [grant]: disk };
    }
    const window = await this.show(grant, words, paths, again);
    return { window, screen: screen() };
  }

  /// The LAN not reached: System Settings' Local Network list up on the Mac for it, once in a while as the helper's
  /// window is (`granted` when it is reached, `closed` within AGAIN_MS of the last time unless a person asks `again`).
  #settings(again: boolean): WindowState | "granted" {
    if (this.#lan === "granted") return "granted";
    const last = this.#asked.get("localNetwork");
    if (!again && last !== undefined && this.#now() - last < AGAIN_MS) return "closed";
    this.#asked.set("localNetwork", this.#now());
    this.#open(LOCAL_NETWORK_SETTINGS);
    return "up";
  }

  /// A disk mounted here whose grant is `grant` (the helper tells removable from network), null when there is none.
  /// Only the entries of the mount point are looked at, never what is on a disk.
  async #disk(grant: GrantId): Promise<string | null> {
    let tops: string[];
    try {
      tops = readdirSync(this.#volumes)
        .map((name) => join(this.#volumes, name))
        // The system's own disk is a link to / there.
        .filter((p) => {
          try {
            return !lstatSync(p).isSymbolicLink();
          } catch {
            return false;
          }
        });
    } catch {
      tops = [];
    }
    tops.push(...this.#mounts().filter((m) => !m.startsWith(`${this.#volumes}/`)));
    if (tops.length === 0) return null;
    const answer = await this.helper.request({ op: "files.access", paths: tops }).catch(() => null);
    const found = (answer?.access ?? []).find((a: any) => a?.grant === grant && typeof a.path === "string");
    return found?.path ?? null;
  }
}

// What build each device a lock here names last ran, as this station saw it ask (`stillfail-build`, api/oldest.ts): by
// the device's id in the lock (a workspace's chain or state in force, a person's own log: one id a device), the highest
// build it said (-1: it said none) and when it was last seen, and since when this station keeps them at all (`since`,
// its first start with this). A device's core reads them of the stations it reaches (GET /lock `builds`, GET
// /lock/person) and hands a workspace's chain over only once every app device it lets in runs a build that takes a
// moved one (client/core-ts src/lock-handover.ts; the user, 2026-11-14: 无感迁移, no date, no switch, nobody told to
// update). Kept in stillfail.db (`device_builds`), written only as a device's build rises or the day of its last
// sight changes: a request writes nothing else, and most write nothing.
import type { Cloud } from "../cloud/state.ts";
import { nowSecs } from "../ops/files.ts";

/// What a device was last seen running: its highest build (-1: none said) and when (unix seconds).
export type Seen = { build: number; at: number };

/// Where they are kept: the store's `device_builds` (mesh.ts gives it), else memory alone (a test's Cloud).
export type BuildsKept = {
  deviceBuilds(): { id: string; build: number; at: number }[];
  putDeviceBuild(id: string, build: number, at: number): void;
  deviceBuildsSince(now: number): number;
};

const DAY = 86400;

export class DeviceBuilds {
  readonly since: number;
  readonly #rows = new Map<string, Seen>();
  readonly #kept: BuildsKept | null;

  constructor(kept: BuildsKept | null, now: number) {
    this.#kept = kept;
    this.since = kept === null ? now : kept.deviceBuildsSince(now);
    for (const r of kept?.deviceBuilds() ?? []) this.#rows.set(r.id, { build: r.build, at: r.at });
  }

  /// Device `id` asked saying `build` (null: none) at `at`: kept where its build rose or it was last seen another day.
  saw(id: string, build: number | null, at: number): void {
    const b = build ?? -1;
    const was = this.#rows.get(id);
    if (was !== undefined && b <= was.build && Math.floor(at / DAY) === Math.floor(was.at / DAY)) return;
    const next = { build: Math.max(b, was?.build ?? -1), at: Math.max(at, was?.at ?? 0) };
    this.#rows.set(id, next);
    this.#kept?.putDeviceBuild(id, next.build, next.at);
  }

  /// What is kept of the devices `ids`, by id (those never seen left out), with `since`.
  of(ids: Iterable<string>): { since: number; devices: Record<string, Seen> } {
    const devices: Record<string, Seen> = {};
    for (const id of ids) {
      const s = this.#rows.get(id);
      if (s !== undefined) devices[id] = s;
    }
    return { since: this.since, devices };
  }
}

/// The devices' builds of each Cloud, made on first use: kept in `kept` where it is given first (mesh.ts, the store),
/// else in memory (a Cloud a test makes).
const builds = new WeakMap<object, DeviceBuilds>();
export function deviceBuildsOf(cloud: Cloud, kept: BuildsKept | null = null): DeviceBuilds {
  let b = builds.get(cloud);
  if (b === undefined) builds.set(cloud, (b = new DeviceBuilds(kept, nowSecs())));
  return b;
}

// How its person likes it on this device, as the core keeps it (its `prefs` topic, `prefs.set`; client/core/src/prefs.rs):
// the lists' filter, the appearance, whose pictures lead a row, times as dates, keys changed, the chat last open, each
// chat's history tabs, an invite code kept through signing in. The page reads them at once, before the core answers,
// from a copy of the core's last value in localStorage (`stillfail.prefs`): the first paint is as it was left (the
// sidebar filtered, the theme set; index.html reads the appearance's own copy before the page's code runs). The core is
// what they are: its value overwrites the copy whenever it comes. A core from before prefs answers the topic with an
// error: the copy is then all there is, written here as before.
import { useSyncExternalStore } from "react";
import { core } from "./core/react.ts";
import type { DeviceView, PrefsView } from "./core/shapes.ts";
import { legacyPrefs } from "./core/migrate.ts";

const COPY = "stillfail.prefs";
/** The appearance's own copy, read by index.html before the first paint (and by pages from before prefs). */
const APPEARANCE = "stillfail.appearance";

/** The prefs with what the core fills in when nothing was chosen (its shape leaves them optional). */
export type Prefs = Required<Omit<PrefsView, "workspace" | "invite" | "device" | "language" | "lang">> & Pick<PrefsView, "workspace" | "invite" | "language" | "lang"> & { device: Required<Omit<DeviceView, "locale">> & Pick<DeviceView, "locale"> };
/** What `prefs.set` takes: a field, or a map's entries (null: gone). */
export type PrefsPatch = { [K in keyof Omit<Prefs, "device">]?: NonNullable<Prefs[K]> extends Record<string, infer V> ? Record<string, V | null> : Prefs[K] | null };

const DEFAULTS: Prefs = {
  onlyMine: false, onlyWatching: false, appearance: "system", rowPicture: "auto", absoluteTime: false, keys: {}, lastChat: {}, openChat: {}, chatTabs: {}, resume: {}, stationUpdatesDismissed: {},
  device: { app: "", phone: false, handoff: false },
};

function storage(): Storage | null {
  try { return typeof localStorage === "undefined" ? null : localStorage; } catch { return null; }
}

function copied(): Prefs {
  try {
    const raw = storage()?.getItem(COPY);
    if (raw) return { ...DEFAULTS, ...(JSON.parse(raw) as Partial<Prefs>) };
  } catch { /* unreadable: the defaults */ }
  const from = storage();
  return { ...DEFAULTS, ...(from ? legacyPrefs(from) : {}), device: DEFAULTS.device };
}

let current: Prefs | null = null;
let listening = false;
/** Changes sent and not answered yet; the core's values meanwhile wait, the latest shown once all are. */
let sending = 0;
let waiting: Prefs | null = null;
const watchers = new Set<() => void>();

function keep(next: Prefs): void {
  current = next;
  const s = storage();
  try {
    s?.setItem(COPY, JSON.stringify(next));
    if (next.appearance === "system") s?.removeItem(APPEARANCE); else s?.setItem(APPEARANCE, next.appearance);
  } catch { /* private mode: not copied */ }
  for (const f of watchers) f();
}

function listen(): void {
  if (listening || typeof window === "undefined") return;
  listening = true;
  core().subscribe({ topic: "prefs" }, (value) => {
    if (!value || typeof value !== "object") return;
    const next = { ...DEFAULTS, ...(value as PrefsView), device: { ...DEFAULTS.device, ...(value as PrefsView).device } } as Prefs;
    if (sending) waiting = next;
    else keep(next);
  }, () => undefined);
}

/** The prefs now: the core's, or its last value copied here until it answers. */
export function prefs(): Prefs {
  current ??= copied();
  listen();
  return current;
}

/** Changes them: shown at once, then as the core has them. */
export function setPrefs(patch: PrefsPatch): void {
  const now = prefs();
  const next = { ...now } as Record<string, unknown>;
  for (const [field, value] of Object.entries(patch)) {
    const before = (now as unknown as Record<string, unknown>)[field];
    if (value !== null && typeof value === "object" && !Array.isArray(value) && before && typeof before === "object") {
      const map = { ...(before as Record<string, unknown>) };
      for (const [k, v] of Object.entries(value)) { if (v === null) delete map[k]; else map[k] = v; }
      next[field] = map;
    } else if (value === null) delete next[field];
    else next[field] = value;
  }
  keep(next as unknown as Prefs);
  sending++;
  // A core from before prefs refuses it: the copy here is what is kept.
  core().call("prefs.set", patch).catch(() => undefined).finally(() => {
    if (--sending || !waiting) return;
    const latest = waiting;
    waiting = null;
    keep(latest);
  });
}

const watch = (f: () => void) => { watchers.add(f); listen(); return () => { watchers.delete(f); }; };

/** Calls `f` whenever the prefs change; returns how to stop. */
export const onPrefs = watch;

/** The prefs, redrawn when they change. */
export function usePrefs(): Prefs {
  return useSyncExternalStore(watch, prefs, () => DEFAULTS);
}

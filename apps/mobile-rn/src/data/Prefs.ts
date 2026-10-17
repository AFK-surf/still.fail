// How its person likes it on this device, as the core keeps it (its `prefs` topic, `prefs.set`; client/core-ts/src/prefs.ts),
// as web/src/prefs.ts has it (data/Prefs.kt): the workspace last open, the appearance, whose pictures lead a row, 只看我的,
// a new connect to go on with. The app kept these in its preferences before; they go into the core once (AppState reads
// the core's, through web/src/prefs.ts). What the app keeps of its own on the device (the Android app's
// SharedPreferences "stillfail") is `devicePrefs` below.
import * as Device from "expo-device";
import type { CoreClient } from "../../../../web/src/core/client.ts";
import type { PrefsView } from "../../../../web/src/core/shapes.ts";
import { deviceLocale } from "../i18n";

/**
 * What the app keeps itself on the device, by name (SharedPreferences): a few flags and lists the core does not keep, the
 * language last said for a push that wakes the app with no core (AppState.ts KeptLang), and what is kept until it moved
 * into the core.
 */
export class DeviceStore {
  // NATIVE: a synchronous key-value store kept on the device (SharedPreferences "stillfail" in the Android app; e.g.
  // react-native-mmkv, not in this app yet). Until then what is put here lasts as long as the process.
  readonly #values = new Map<string, string | boolean>();

  get all(): ReadonlyMap<string, string | boolean> { return this.#values; }
  contains(key: string): boolean { return this.#values.has(key); }
  getBoolean(key: string, fallback: boolean): boolean {
    const v = this.#values.get(key);
    return typeof v === "boolean" ? v : fallback;
  }
  getString(key: string, fallback: string | null): string | null {
    const v = this.#values.get(key);
    return typeof v === "string" ? v : fallback;
  }
  putBoolean(key: string, value: boolean): void { this.#values.set(key, value); }
  putString(key: string, value: string): void { this.#values.set(key, value); }
  remove(key: string): void { this.#values.delete(key); }
}

/** The app's own preferences on this device. */
export const devicePrefs = new DeviceStore();

const RESUME = "newConnect.resume/";

export const Prefs = {
  /** What the app kept itself before the core did: into the core, only what it has not been told, then gone from here. */
  async moveIn(core: CoreClient, prefs: DeviceStore): Promise<void> {
    const resume = [...prefs.all.keys()].filter((k) => k.startsWith(RESUME));
    const old = ["workspace", "theme", "rowPicture", "onlyMine"].filter((k) => prefs.contains(k)).concat(resume);
    if (old.length === 0) return;
    const patch: Record<string, unknown> = { fill: true };
    const workspace = prefs.getString("workspace", null);
    if (workspace !== null) patch.workspace = workspace;
    const theme = prefs.getString("theme", null);
    if (theme !== null && ["system", "light", "dark"].includes(theme)) patch.appearance = theme;
    const rowPicture = prefs.getString("rowPicture", null);
    if (rowPicture !== null && ["auto", "agents", "people"].includes(rowPicture)) patch.rowPicture = rowPicture;
    if (prefs.contains("onlyMine")) patch.onlyMine = prefs.getBoolean("onlyMine", false);
    const made: [string, string][] = [];
    for (const key of resume) {
      const app = prefs.getString(key, null)?.split("\u0000").find((s) => s.length > 0);
      if (app !== undefined) made.push([key.slice(RESUME.length), app]);
    }
    if (made.length > 0) patch.resume = Object.fromEntries(made);
    try {
      await core.call("prefs.set", patch);
      for (const k of old) prefs.remove(k);
    } catch {
      // Tried again on the next start; they stay here until then.
    }
  },

  /**
   * Tells the core what this device is, once at start: it decides what follows (the name it signs in as, the app a
   * message is sent from). (src/core/index.ts says it as the core starts; this is the Kotlin's, for a start that says it here.)
   */
  async tellDevice(core: CoreClient): Promise<void> {
    try {
      await core.call("client.device", { app: "android", build: "rn-0.1", model: `${Device.manufacturer ?? ""} ${Device.modelName ?? ""}`.trim(), locale: deviceLocale() });
    } catch {
      // A core from before it: nothing said.
    }
  },

  /** The core's first value (it is on the device: at once), for the first frame to be as they are. */
  first(core: CoreClient): Promise<PrefsView> {
    return new Promise((resolve) => {
      let off: (() => void) | null = null;
      let done = false;
      const end = (value: PrefsView) => {
        if (done) return;
        done = true;
        resolve(value);
        // Let go once it is said (after subscribe returned, when it answers at once).
        queueMicrotask(() => off?.());
      };
      off = core.subscribe(
        { topic: "prefs" },
        (value) => end(value && typeof value === "object" ? (value as PrefsView) : {}),
        () => end({}),
      );
      if (done) off();
    });
  },
};

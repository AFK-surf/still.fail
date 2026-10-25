// The iOS Simulators booted on this Mac as screen sources (`simulator:<udid>`, docs/remote-screens.md "Simulators"):
// people see and drive one from their app as they do the desktop, agents with the `computer` tool, while they build and
// debug an app on it. still.fail Helper's `simulator.view` (native/helper's SimulatorView.swift, serve-sim's capture and
// HID in vendor/serve-sim) reads the device's framebuffer and posts touches, keys and buttons to it; nothing of macOS's is
// granted for it, and Simulator.app need not run.
//
// Which are booted is `xcrun simctl list`'s, looked at again when CoreSimulator rewrites a device's device.plist (it
// does as the device boots and shuts down) or the list of devices changes, and as the screens are asked for.
import { execFile } from "node:child_process";
import { type FSWatcher, existsSync, readdirSync, watch } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { HelperApp } from "../helper/app.ts";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { HelperView } from "./desktop.ts";
import { ScreenRefused } from "./hub.ts";
import { SimInput } from "./sim-input.ts";
import type { Codec, ScreenSource, ScreenView, Screens, ViewOptions } from "./source.ts";

/// A booted device as simctl lists it.
export type Booted = { udid: string; name: string; runtime: string; type: string };

/// The booted devices of `simctl list -j devices`: each with its runtime's name ("iOS 26.2", from its identifier).
export function bootedOf(listed: unknown): Booted[] {
  const devices = (listed as { devices?: Record<string, unknown> } | null)?.devices;
  if (devices === null || typeof devices !== "object") return [];
  const out: Booted[] = [];
  for (const [runtime, list] of Object.entries(devices)) {
    if (!Array.isArray(list)) continue;
    for (const d of list) {
      if (d?.state !== "Booted" || typeof d.udid !== "string" || !/^[0-9A-F-]{36}$/i.test(d.udid)) continue;
      out.push({ udid: d.udid, name: typeof d.name === "string" ? d.name : d.udid, runtime: runtimeName(runtime), type: typeof d.deviceTypeIdentifier === "string" ? d.deviceTypeIdentifier : "" });
    }
  }
  return out;
}

/// "com.apple.CoreSimulator.SimRuntime.iOS-26-2" → "iOS 26.2".
export function runtimeName(id: string): string {
  const m = /SimRuntime\.([A-Za-z]+)-([\d-]+)$/.exec(id);
  if (m === null) return id;
  const os = m[1] === "xrOS" ? "visionOS" : m[1]!;
  return `${os} ${m[2]!.replaceAll("-", ".")}`;
}

/// A device type's main screen in pixels, as its capabilities.plist says it (0×0 when it does not).
export function screenOf(capabilities: unknown): { width: number; height: number } {
  const d = (capabilities as { capabilities?: { ScreenDimensionsCapability?: Record<string, unknown> } } | null)?.capabilities?.ScreenDimensionsCapability;
  const width = d?.["main-screen-width"], height = d?.["main-screen-height"];
  return typeof width === "number" && typeof height === "number" && width > 0 && height > 0 ? { width, height } : { width: 0, height: 0 };
}

export type Run = (file: string, args: string[]) => Promise<string>;
const run: Run = (file, args) =>
  new Promise((resolve, reject) =>
    execFile(file, args, { timeout: 60_000, maxBuffer: 16 << 20 }, (error, out, err) => (error ? reject(new Error(`${file} ${args.join(" ")}: ${error.signal ?? error.code ?? ""} ${String(err).trim()}`.slice(0, 500))) : resolve(out))),
  );

export type SimulatorsOptions = {
  screens: Screens;
  /// still.fail Helper; none: no simulator is listed.
  helper: HelperApp | null;
  /// Where CoreSimulator keeps the devices (default ~/Library/Developer/CoreSimulator/Devices).
  devices?: string;
  run?: Run;
};

/// The booted simulators, each a source in `screens` while it is booted.
export class Simulators {
  readonly #o: SimulatorsOptions;
  readonly #run: Run;
  readonly #devices: string;
  readonly #listed = new Map<string, { source: Simulator; remove: () => void }>();
  /// A device type's screen in pixels (its capabilities.plist), by its identifier.
  readonly #sizes = new Map<string, { width: number; height: number }>();
  readonly #watchers = new Map<string, FSWatcher>();
  #looking: Promise<void> | null = null;
  #again = false;
  /// Calls off the look armed after a change on disk.
  #soon: (() => void) | null = null;
  #closed = false;
  #said = false;

  constructor(options: SimulatorsOptions) {
    this.#o = options;
    this.#run = options.run ?? run;
    this.#devices = options.devices ?? join(homedir(), "Library/Developer/CoreSimulator/Devices");
  }

  /// Follows the devices' changes (none where there are no simulators), and looks once.
  start(): Promise<void> {
    if (this.#o.helper === null) return Promise.resolve();
    this.#follow();
    return this.refresh();
  }

  /// The booted devices looked at again (one look at a time; one asked meanwhile is made after it).
  refresh(): Promise<void> {
    if (this.#o.helper === null || this.#closed) return Promise.resolve();
    if (this.#looking !== null) {
      this.#again = true;
      return this.#looking;
    }
    this.#looking = this.#look().finally(() => {
      this.#looking = null;
      if (this.#again) {
        this.#again = false;
        void this.refresh();
      }
    });
    return this.#looking;
  }

  async #look() {
    let booted: Booted[];
    try {
      booted = bootedOf(JSON.parse(await this.#run("xcrun", ["simctl", "list", "-j", "devices"])));
    } catch (error) {
      // No Xcode, or CoreSimulator too busy to answer (a device booting on a loaded Mac): what is listed stays, said once.
      if (!this.#said) log.info("screens", "simctl did not list the simulators", { error: (error as Error).message.slice(0, 300) });
      this.#said = true;
      return;
    }
    if (this.#closed) return;
    const now = new Set(booted.map((b) => b.udid));
    for (const [udid, listed] of this.#listed) {
      if (now.has(udid)) continue;
      this.#listed.delete(udid);
      listed.remove();
      listed.source.gone();
    }
    for (const b of booted) {
      if (this.#listed.has(b.udid)) continue;
      const source = new Simulator(b, this.#o.helper!, await this.#size(b.type));
      if (this.#closed || this.#listed.has(b.udid)) continue;
      this.#listed.set(b.udid, { source, remove: this.#o.screens.add(source) });
    }
    this.#follow();
  }

  /// A device type's screen in pixels, from its bundle's capabilities.plist (0×0 when it cannot be read).
  async #size(type: string): Promise<{ width: number; height: number }> {
    const known = this.#sizes.get(type);
    if (known) return known;
    let size = { width: 0, height: 0 };
    try {
      const types = JSON.parse(await this.#run("xcrun", ["simctl", "list", "-j", "devicetypes"])).devicetypes as { identifier?: string; bundlePath?: string }[];
      const bundle = types.find((t) => t.identifier === type)?.bundlePath;
      if (bundle) {
        size = screenOf(JSON.parse(await this.#run("plutil", ["-convert", "json", "-o", "-", join(bundle, "Contents/Resources/capabilities.plist")])));
      }
    } catch {}
    this.#sizes.set(type, size);
    return size;
  }

  /// Watches the devices' folder (a device made or deleted) and each device's (its device.plist rewritten as it boots
  /// or shuts down; not what is below, which a running device writes all the time).
  #follow() {
    if (this.#closed || !existsSync(this.#devices)) return;
    const dirs = new Set([this.#devices]);
    try {
      for (const e of readdirSync(this.#devices, { withFileTypes: true })) if (e.isDirectory() && /^[0-9A-F-]{36}$/i.test(e.name)) dirs.add(join(this.#devices, e.name));
    } catch {}
    for (const [dir, w] of this.#watchers) {
      if (dirs.has(dir)) continue;
      w.close();
      this.#watchers.delete(dir);
    }
    for (const dir of dirs) {
      if (this.#watchers.has(dir)) continue;
      try {
        const w = watch(dir, (_event, name) => {
          if (dir === this.#devices || name === null || String(name).startsWith("device.plist")) this.#changed();
        });
        w.on("error", () => {
          w.close();
          this.#watchers.delete(dir);
        });
        this.#watchers.set(dir, w);
      } catch {}
    }
  }

  /// Something changed on disk: looked at once it settles (a boot rewrites device.plist a few times).
  #changed() {
    // CoreSimulator's own writes, waited on in the machine's time.
    this.#soon?.();
    this.#soon = wall.after(300, () => {
      this.#soon = null;
      void this.refresh();
    });
  }

  /// The station stopping: nothing followed, every source gone.
  close() {
    this.#closed = true;
    this.#soon?.();
    for (const w of this.#watchers.values()) w.close();
    this.#watchers.clear();
    for (const listed of this.#listed.values()) {
      listed.remove();
      listed.source.gone();
    }
    this.#listed.clear();
  }
}

/// One booted simulator: a view is a connection to the helper's `simulator.view`.
export class Simulator implements ScreenSource {
  readonly id: string;
  readonly kind = "simulator" as const;
  /// A preview opens as any view does: nothing to wake.
  readonly peek = true;
  readonly #device: Booted;
  readonly #helper: HelperApp;
  #size: { width: number; height: number };
  readonly #views = new Set<HelperView>();

  constructor(device: Booted, helper: HelperApp, size: { width: number; height: number }) {
    this.id = `simulator:${device.udid}`;
    this.#device = device;
    this.#helper = helper;
    this.#size = size;
  }

  title(): string {
    return `${this.#device.name} · ${this.#device.runtime}`;
  }

  size(): { width: number; height: number } {
    return this.#size;
  }

  async open(options: ViewOptions): Promise<ScreenView> {
    // H.264 (the helper's encoder; H.265 where asked and this Mac has it), else a JPEG a picture (an agent's view).
    const codec: Codec | undefined = (["h265", "h264", "jpeg"] as const).find((c) => options.codecs.includes(c));
    if (codec === undefined) throw new ScreenRefused(415, "station.screen.codec", { codec: "H.264, JPEG" });
    const socket = await this.#helper.connect({ op: "simulator.view", udid: this.#device.udid, codec, maxWidth: options.maxWidth, maxHeight: options.maxHeight, ...(options.bitrate ? { bitrate: Math.round(options.bitrate) } : {}) });
    const view = new HelperView(codec, socket, () => this.#views.delete(view), new SimInput(), "CoreSimulator");
    this.#views.add(view);
    try {
      await view.ready;
      return view;
    } catch (error) {
      view.close();
      log.warn("screens", "a simulator's view did not open", { udid: this.#device.udid, error: (error as Error).message });
      throw new ScreenRefused(503, "station.screen.failed", { said: (error as Error).message });
    }
  }

  /// It shut down (or the station stops): its views end.
  gone() {
    for (const view of [...this.#views]) view.close();
  }
}

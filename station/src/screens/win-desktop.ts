// This Windows machine's display as a screen source (`desktop`, docs/remote-screens.md): stillfail-screen
// (station/native/screen) captures the main display with Windows.Graphics.Capture, encodes H.265 or H.264 with Media
// Foundation (the hardware encoder where there is one), or a JPEG a picture for a view that takes no H.264, and posts
// the input with SendInput. Each view is a process of its own, started with `view` and spoken to on its standard input
// and output in still.fail Helper's messages (desktop.ts `HelperView`); it ends as its input does.
//
// Nothing is granted on Windows: a station runs in its person's session (a scheduled task at logon), where the display
// can be captured and driven. What cannot be is what Windows keeps from any app there: the sign-in and UAC's secure
// desktop, and windows of apps run as administrator (their input).
import { type ChildProcess, spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import { existsSync } from "node:fs";
import { hostname } from "node:os";
import { fileURLToPath } from "node:url";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { type HelperPipe, HelperView } from "./desktop.ts";
import { ScreenRefused } from "./hub.ts";
import type { AudioFrame, Clip, ClipType, Codec, Frame, Region, ScreenAccess, ScreenCursor, ScreenInput, ScreenResolution, ScreenScale, ScreenSource, ScreenVideo, ScreenView, ViewOptions } from "./source.ts";
import { processUi } from "./ui.ts";
import { WinInput } from "./win-input.ts";

export const SCREEN_BINARY = "stillfail-screen.exe";

/// The release's stillfail-screen: STILLFAIL_SCREEN, beside the station's code in a release, or built in the checkout.
export function screenBinary(env: NodeJS.ProcessEnv = process.env): string | null {
  const candidates = [
    env.STILLFAIL_SCREEN,
    fileURLToPath(new URL(`./${SCREEN_BINARY}`, import.meta.url)),
    fileURLToPath(new URL(`../../native/screen/target/release/${SCREEN_BINARY}`, import.meta.url)),
  ];
  return candidates.find((p) => p && existsSync(p)) ?? null;
}

/// What `stillfail-screen status` says: the main display in pixels, and whether Windows can capture it (10 1903 on).
export type ScreenStatus = { display: { width: number; height: number }; capture: boolean };

/// A scale as stillfail-screen says it, checked: null when it is not one.
export function scaleOf(told: any): ScreenScale | null {
  const n = (v: unknown) => typeof v === "number" && Number.isInteger(v) && v >= 100 && v <= 500;
  if (told === null || typeof told !== "object" || !n(told.percent) || !n(told.recommended) || !Array.isArray(told.steps) || !told.steps.every(n)) return null;
  return { percent: told.percent, recommended: told.recommended, steps: [...told.steps] };
}

/// A resolution as stillfail-screen says it, checked: null when it is not one.
export function resolutionOf(told: any): ScreenResolution | null {
  const n = (v: unknown) => typeof v === "number" && Number.isInteger(v) && v > 0 && v <= 16384;
  const size = (v: any) => v !== null && typeof v === "object" && n(v.width) && n(v.height);
  if (!size(told) || !Array.isArray(told.modes) || !told.modes.every(size)) return null;
  return { width: told.width, height: told.height, modes: told.modes.map((m: any) => ({ width: m.width, height: m.height })) };
}

/// How the process is started (a test's fake in tests).
export type Start = (binary: string, args: string[]) => ChildProcess;
const start: Start = (binary, args) => spawn(binary, args, { stdio: ["pipe", "pipe", "ignore"], windowsHide: true });

export type WindowsDesktopOptions = {
  /// stillfail-screen, null when the release has none.
  binary: string | null;
  /// agent-desktop (screens/ui.ts), null when the release has none.
  ui?: string | null;
  /// Told when its size or access changed.
  changed: () => void;
  /// Its title (default: the machine's name).
  title?: () => string;
  start?: Start;
};

/// A status this recent is not asked again (unless forced).
const FRESH_MS = 2_000;

export class WindowsDesktop implements ScreenSource {
  readonly id = "desktop";
  readonly kind = "desktop" as const;
  readonly reveal = true;
  readonly #o: WindowsDesktopOptions;
  readonly #views = new Set<LastingView>();
  #status: ScreenStatus | null = null;
  #looked = 0;
  #looking: Promise<void> | null = null;
  /// The display's scale before a view first changed it, put back once the last view ends; null while unchanged.
  #original: number | null = null;
  /// Scale changes, one after another.
  #scaling: Promise<unknown> = Promise.resolve();
  /// The display's resolution before a view first changed it, put back once the last view ends; null while unchanged.
  #originalSize: { width: number; height: number } | null = null;
  /// Resolution changes, one after another.
  #sizing: Promise<unknown> = Promise.resolve();

  constructor(options: WindowsDesktopOptions) {
    this.#o = options;
  }

  title(): string {
    return this.#o.title?.() ?? hostname();
  }

  size(): { width: number; height: number } {
    return { width: this.#status?.display.width ?? 0, height: this.#status?.display.height ?? 0 };
  }

  clipboard(): ClipType[] {
    return this.#o.binary === null ? [] : ["text", "png"];
  }

  access(): ScreenAccess {
    if (this.#o.binary === null) return { capture: false, control: false, unsupported: "helper" };
    // A Windows without the capture (before 10 1903).
    if (this.#status?.capture === false) return { capture: false, control: false, unsupported: "platform" };
    return { capture: true, control: true };
  }

  /// The display's size as Windows has it now (at most a moment old, unless `force`).
  refresh(force = false): Promise<void> {
    if (this.#o.binary === null) return Promise.resolve();
    if (!force && wall.now() - this.#looked < FRESH_MS) return Promise.resolve();
    this.#looking ??= this.#ask(["status"])
      .then(
        (told) => {
          const status: ScreenStatus = { display: { width: Number(told.display?.width) || 0, height: Number(told.display?.height) || 0 }, capture: told.capture !== false };
          const before = this.#status;
          this.#status = status;
          if (before === null || before.display.width !== status.display.width || before.display.height !== status.display.height || before.capture !== status.capture) this.#o.changed();
        },
        (e) => log.warn("screens", "stillfail-screen did not say the display", { error: (e as Error).message }),
      )
      .finally(() => {
        this.#looked = wall.now();
        this.#looking = null;
      });
    return this.#looking;
  }

  /// What `stillfail-screen <args>` says (its one JSON line); throws what it said wrong.
  #ask(args: string[]): Promise<any> {
    const binary = this.#o.binary;
    if (binary === null) return Promise.reject(new Error("stillfail-screen is not there"));
    return new Promise((resolve, reject) => {
      const child = (this.#o.start ?? start)(binary, args);
      let said = "";
      const unarm = wall.after(10_000, () => child.kill());
      child.stdout!.setEncoding("utf8").on("data", (chunk: string) => (said += chunk));
      let finished = false;
      const done = (error?: Error) => {
        if (finished) return;
        finished = true;
        unarm();
        try {
          if (error) throw error;
          const told = JSON.parse(said);
          if (typeof told?.error === "string") throw new Error(told.error);
          resolve(told);
        } catch (e) {
          reject(e as Error);
        }
      };
      child.on("error", done);
      child.on("close", () => done());
      child.stdin?.end();
    });
  }

  /// As it is once the changes asked before are made.
  scale(): Promise<ScreenScale | null> {
    const read = this.#scaling.then(() => this.#ask(["scale"])).then(scaleOf, (error) => {
      log.info("screens", "the display's scale was not had", { error: (error as Error).message });
      return null;
    });
    this.#scaling = read;
    return read;
  }

  setScale(percent: number): Promise<ScreenScale> {
    const set = this.#scaling.then(async () => {
      if (this.#original === null) {
        const before = scaleOf(await this.#ask(["scale"]));
        if (before === null) throw new Error("the display's scale was not had");
        this.#original = before.percent;
      }
      const now = scaleOf(await this.#ask(["scale", String(Math.round(percent))]));
      if (now === null) throw new Error("the display's scale was not had");
      log.info("screens", "the display's scale set", { percent: now.percent, was: this.#original });
      return now;
    });
    this.#scaling = set.catch(() => {});
    return set;
  }

  /// As it is once the changes asked before are made.
  resolution(): Promise<ScreenResolution | null> {
    const read = this.#sizing.then(() => this.#ask(["resolution"])).then(resolutionOf, (error) => {
      log.info("screens", "the display's resolution was not had", { error: (error as Error).message });
      return null;
    });
    this.#sizing = read;
    return read;
  }

  setResolution(width: number, height: number): Promise<ScreenResolution> {
    const set = this.#sizing.then(async () => {
      if (this.#originalSize === null) {
        const before = resolutionOf(await this.#ask(["resolution"]));
        if (before === null) throw new Error("the display's resolution was not had");
        this.#originalSize = { width: before.width, height: before.height };
      }
      const now = resolutionOf(await this.#ask(["resolution", `${Math.round(width)}x${Math.round(height)}`]));
      if (now === null) throw new Error("the display's resolution was not had");
      log.info("screens", "the display's resolution set", { width: now.width, height: now.height, was: this.#originalSize });
      // (its size another now: listed anew)
      this.#o.changed();
      return now;
    });
    this.#sizing = set.catch(() => {});
    return set;
  }

  /// The last view ended: the display's scale and resolution as they were before a view changed them.
  #putBack() {
    if (this.#views.size > 0) return;
    const size = this.#originalSize;
    if (size !== null) {
      this.#originalSize = null;
      this.#sizing = this.#sizing.then(() =>
        this.#ask(["resolution", `${size.width}x${size.height}`]).then(
          () => (log.info("screens", "the display's resolution put back", size), this.#o.changed()),
          (error) => log.warn("screens", "the display's resolution was not put back", { ...size, error: (error as Error).message }),
        ),
      );
    }
    const original = this.#original;
    if (original === null) return;
    this.#original = null;
    this.#scaling = this.#scaling.then(() =>
      this.#ask(["scale", String(original)]).then(
        () => log.info("screens", "the display's scale put back", { percent: original }),
        (error) => log.warn("screens", "the display's scale was not put back", { percent: original, error: (error as Error).message }),
      ),
    );
  }

  async open(options: ViewOptions): Promise<ScreenView> {
    const binary = this.#o.binary;
    if (binary === null) throw new ScreenRefused(501, "station.screen.noHelper", {}, this.access());
    // H.265 where it is taken (stillfail-screen makes it where the hardware has an encoder of it, else H.264: its info
    // says which), H.264, else a JPEG a picture (an agent's view, a client without either).
    const codec: Codec | undefined = (["h265", "h264", "jpeg"] as const).find((c) => options.codecs.includes(c));
    if (codec === undefined) throw new ScreenRefused(415, "station.screen.codec", { codec: "H.264, JPEG" });
    await this.refresh();
    if (this.#status?.capture === false) throw new ScreenRefused(501, "station.screen.unsupported", {}, this.access());
    const input = new WinInput();
    const ask = { codec, ...(options.audio === true && !options.peek ? { audio: true } : {}), maxWidth: options.maxWidth, maxHeight: options.maxHeight, ...(options.bitrate ? { bitrate: Math.round(options.bitrate) } : {}), ...(options.fps ? { fps: options.fps } : {}) };
    let first: HelperView;
    try {
      first = await this.#start(binary, ask, input);
    } catch (error) {
      throw new ScreenRefused(503, "station.screen.failed", { said: (error as Error).message });
    }
    const view: LastingView = new LastingView(first, () => this.#start(binary, ask, input), () => (this.#views.delete(view), this.#putBack()));
    this.#views.add(view);
    return view;
  }

  /// One process for a view, answering (its info had); fails with what it said.
  async #start(binary: string, ask: { codec: Codec; maxWidth: number; maxHeight: number; bitrate?: number; fps?: number; audio?: boolean }, input: WinInput): Promise<HelperView> {
    const child = (this.#o.start ?? start)(binary, ["view"]);
    child.stdin!.write(`${JSON.stringify(ask)}\n`);
    const view = new HelperView(ask.codec, childPipe(child), () => {}, input, "Windows.Graphics.Capture", ask.audio);
    try {
      await view.ready;
      return view;
    } catch (error) {
      view.close();
      throw error;
    }
  }

  /// Its apps' accessibility trees: agent-desktop started here, in the person's session as the station is.
  ui(args: string[]): Promise<unknown> {
    const binary = this.#o.ui ?? null;
    if (binary === null) return Promise.reject(new Error("this station's release carries no agent-desktop (update the station)"));
    return processUi(binary)(args);
  }

  /// The station stopping: every view ends.
  close(): Promise<void> {
    for (const view of [...this.#views]) view.close();
    return Promise.resolve();
  }
}

/// Started again this many times within RESTARTS_MS, a view ends instead (the display is not to be had).
const RESTARTS = 3;
const RESTARTS_MS = 60_000;

/// A view that outlives its process: one that ended without being asked (the display went or another became the main
/// one, the graphics driver started again, a crash) is started again, and the view goes on from a key frame with its
/// config (a client takes a new config at any frame), the clipboard still watched. Closed, or started again too often,
/// it ends as any view does.
export class LastingView implements ScreenView {
  #view: HelperView;
  readonly #again: () => Promise<HelperView>;
  readonly #gone: () => void;
  #closed = false;
  #restarts: number[] = [];
  /// The process being started again: every pending `next` waits for the one.
  #restarting: Promise<boolean> | null = null;
  #heard: ((clip: Clip) => void) | null = null;
  #unwatch: (() => void) | null = null;
  /// Who hears the pointer, heard again from a process started again.
  #pointer: ((cursor: ScreenCursor) => void) | null = null;
  #unpoint: (() => void) | null = null;
  /// The bit rate and bounds (and part of the display) asked last, asked again of a process started again.
  #rate: number | null = null;
  #bounds: [number, number, Region | null] | null = null;

  constructor(view: HelperView, again: () => Promise<HelperView>, gone: () => void) {
    this.#view = view;
    this.#again = again;
    this.#gone = gone;
  }

  async next(): Promise<Frame | null> {
    for (;;) {
      const view = this.#view;
      const frame = await view.next();
      if (frame !== null || this.#closed) return frame;
      // Another `next` already started it again: this one asks the new process.
      if (this.#view === view && !(await (this.#restarting ??= this.#restart().finally(() => (this.#restarting = null))))) return null;
      if (this.#closed) return null;
    }
  }

  async nextAudio(): Promise<AudioFrame | null> {
    for (;;) {
      const view = this.#view;
      const audio = await view.nextAudio();
      if (audio !== null || this.#closed || !view.hasAudio()) return audio;
      if (this.#view === view && !(await (this.#restarting ??= this.#restart().finally(() => (this.#restarting = null))))) return null;
      if (this.#closed) return null;
    }
  }

  async #restart(): Promise<boolean> {
    const now = wall.now();
    this.#restarts = [...this.#restarts.filter((t) => now - t < RESTARTS_MS), now];
    if (this.#restarts.length > RESTARTS) {
      log.warn("screens", "stillfail-screen keeps ending; the view ends");
      this.close();
      return false;
    }
    try {
      const view = await this.#again();
      if (this.#closed) {
        view.close();
        return false;
      }
      log.info("screens", "stillfail-screen ended by itself; started again");
      this.#view = view;
      if (this.#heard !== null) this.#unwatch = view.watchClipboard(this.#heard);
      if (this.#pointer !== null) this.#unpoint = view.watchCursor(this.#pointer);
      if (this.#rate !== null) view.rate(this.#rate);
      if (this.#bounds !== null) view.bounds(...this.#bounds);
      return true;
    } catch (error) {
      log.warn("screens", "stillfail-screen did not start again", { error: (error as Error).message });
      this.close();
      return false;
    }
  }

  keyframe() {
    this.#view.keyframe();
  }

  video(): ScreenVideo {
    return this.#view.video();
  }

  rate(bitsPerSecond: number) {
    this.#rate = bitsPerSecond;
    this.#view.rate(bitsPerSecond);
  }

  bounds(maxWidth: number, maxHeight: number, region?: Region | null) {
    this.#bounds = [maxWidth, maxHeight, region ?? null];
    this.#view.bounds(maxWidth, maxHeight, region);
  }

  regions(): boolean {
    return this.#view.regions();
  }

  input(event: ScreenInput): Promise<void> {
    return this.#view.input(event);
  }

  setClipboard(clip: Clip, paste: boolean): Promise<void> {
    return this.#view.setClipboard(clip, paste);
  }

  watchClipboard(heard: (clip: Clip) => void): () => void {
    this.#heard = heard;
    this.#unwatch = this.#view.watchClipboard(heard);
    return () => {
      if (this.#heard !== heard) return;
      this.#heard = null;
      this.#unwatch?.();
      this.#unwatch = null;
    };
  }

  reveal(path: string): Promise<void> {
    return this.#view.reveal(path);
  }

  watchCursor(heard: (cursor: ScreenCursor) => void): () => void {
    this.#pointer = heard;
    this.#unpoint = this.#view.watchCursor(heard);
    return () => {
      if (this.#pointer !== heard) return;
      this.#pointer = null;
      this.#unpoint?.();
      this.#unpoint = null;
    };
  }

  close() {
    if (this.#closed) return;
    this.#closed = true;
    this.#view.close();
    this.#gone();
  }
}

/// A view's process as the helper's connection: its output read, its input written; destroyed, its input ends (the
/// process ends with it) and it is ended outright if it has not in a moment.
export function childPipe(child: ChildProcess): HelperPipe {
  const events = new EventEmitter();
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    events.emit("close");
  };
  child.stdout!.on("data", (chunk: Buffer) => events.emit("data", chunk));
  // Its output read to the end first: what it said as it went is had.
  child.on("close", close);
  child.on("error", (error) => {
    log.warn("screens", "stillfail-screen did not start", { error: error.message });
    close();
  });
  // Written to as it ends: nothing to be told.
  child.stdin!.on("error", () => {});
  return {
    write: (data) => child.stdin!.write(data),
    destroy() {
      child.stdin!.end();
      wall.after(2_000, () => {
        if (child.exitCode === null && child.signalCode === null) child.kill();
      });
    },
    on: (event: string, listener: (...args: any[]) => void) => events.on(event, listener),
  };
}

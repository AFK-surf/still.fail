// This Windows machine's display as a screen source (`desktop`, docs/remote-screens.md): stillfail-screen
// (station/native/screen) captures the main display with Windows.Graphics.Capture, encodes H.264 with Media
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
import type { Clip, ClipType, Codec, Frame, ScreenAccess, ScreenInput, ScreenSource, ScreenView, ViewOptions } from "./source.ts";
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

/// How the process is started (a test's fake in tests).
export type Start = (binary: string, args: string[]) => ChildProcess;
const start: Start = (binary, args) => spawn(binary, args, { stdio: ["pipe", "pipe", "ignore"], windowsHide: true });

export type WindowsDesktopOptions = {
  /// stillfail-screen, null when the release has none.
  binary: string | null;
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
    const binary = this.#o.binary;
    if (binary === null) return Promise.resolve();
    if (!force && wall.now() - this.#looked < FRESH_MS) return Promise.resolve();
    this.#looking ??= new Promise<void>((resolve) => {
      const child = (this.#o.start ?? start)(binary, ["status"]);
      let said = "";
      const unarm = wall.after(10_000, () => child.kill());
      child.stdout!.setEncoding("utf8").on("data", (chunk: string) => (said += chunk));
      let finished = false;
      const done = (error?: Error) => {
        if (finished) return;
        finished = true;
        unarm();
        this.#looked = wall.now();
        this.#looking = null;
        try {
          if (error) throw error;
          const told = JSON.parse(said);
          const status: ScreenStatus = { display: { width: Number(told.display?.width) || 0, height: Number(told.display?.height) || 0 }, capture: told.capture !== false };
          const before = this.#status;
          this.#status = status;
          if (before === null || before.display.width !== status.display.width || before.display.height !== status.display.height || before.capture !== status.capture) this.#o.changed();
        } catch (e) {
          log.warn("screens", "stillfail-screen did not say the display", { error: (e as Error).message });
        }
        resolve();
      };
      child.on("error", done);
      child.on("close", () => done());
      child.stdin?.end();
    });
    return this.#looking;
  }

  async open(options: ViewOptions): Promise<ScreenView> {
    const binary = this.#o.binary;
    if (binary === null) throw new ScreenRefused(501, "station.screen.noHelper", {}, this.access());
    // H.264 where it is taken (the hardware's, small); else a JPEG a picture (an agent's view, a client without H.264).
    const codec: Codec | undefined = options.codecs.includes("h264") ? "h264" : options.codecs.includes("jpeg") ? "jpeg" : undefined;
    if (codec === undefined) throw new ScreenRefused(415, "station.screen.codec", { codec: "H.264, JPEG" });
    await this.refresh();
    if (this.#status?.capture === false) throw new ScreenRefused(501, "station.screen.unsupported", {}, this.access());
    const input = new WinInput();
    const ask = { codec, maxWidth: options.maxWidth, maxHeight: options.maxHeight };
    let first: HelperView;
    try {
      first = await this.#start(binary, ask, input);
    } catch (error) {
      throw new ScreenRefused(503, "station.screen.failed", { said: (error as Error).message });
    }
    const view: LastingView = new LastingView(first, () => this.#start(binary, ask, input), () => this.#views.delete(view));
    this.#views.add(view);
    return view;
  }

  /// One process for a view, answering (its info had); fails with what it said.
  async #start(binary: string, ask: { codec: Codec; maxWidth: number; maxHeight: number }, input: WinInput): Promise<HelperView> {
    const child = (this.#o.start ?? start)(binary, ["view"]);
    child.stdin!.write(`${JSON.stringify(ask)}\n`);
    const view = new HelperView(ask.codec, childPipe(child), () => {}, input);
    try {
      await view.ready;
      return view;
    } catch (error) {
      view.close();
      throw error;
    }
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
  /// The bit rate asked last, asked again of a process started again.
  #rate: number | null = null;

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
      if (this.#rate !== null) view.rate(this.#rate);
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

  rate(bitsPerSecond: number) {
    this.#rate = bitsPerSecond;
    this.#view.rate(bitsPerSecond);
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

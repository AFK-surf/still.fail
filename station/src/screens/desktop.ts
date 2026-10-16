// This machine's display as a screen source (`desktop`, docs/remote-screens.md): on macOS, a helper process per view
// (native/screen, `stillfail-screen`) captures the main display with ScreenCaptureKit, encodes H.264 with
// VideoToolbox and posts input with CGEvent; elsewhere it says it is not supported, and opens nothing.
//
// macOS asks whether a process may capture the screen (Screen Recording) and post input (Accessibility) of the process
// responsible for it: under launchd, the station's launcher (`stillfail-station`, mesh/target/release in the release);
// in the desktop app, the app. The helper says which (`status`), and what is missing is told with its name and path.
// The grants are asked of macOS as they are needed (when a view is opened or listed), never followed: a person turns
// one on in System Settings, and the next look sees it.
import { type ChildProcess, execFile, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { hostname } from "node:os";
import { fileURLToPath } from "node:url";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { ScreenRefused } from "./hub.ts";
import { MacInput } from "./mac-input.ts";
import type { Frame, FrameConfig, ScreenAccess, ScreenInput, ScreenSource, ScreenView, ViewOptions } from "./source.ts";

/// Where the helper is: STILLFAIL_SCREEN, beside the station's code in a release, or where `swift build` put it.
export function screenHelper(env: NodeJS.ProcessEnv = process.env): string | null {
  const candidates = [
    env.STILLFAIL_SCREEN,
    fileURLToPath(new URL("./stillfail-screen", import.meta.url)),
    fileURLToPath(new URL("../../native/screen/.build/arm64-apple-macosx/release/stillfail-screen", import.meta.url)),
  ];
  return candidates.find((p) => p && existsSync(p)) ?? null;
}

/// What the helper's `status` says.
export type HelperStatus = {
  capture: boolean;
  control: boolean;
  responsible?: { pid: number; path: string; name: string };
  display?: { id: number; width: number; height: number };
};

/// A look at the grants is this fresh at most (a list asked for twice at once looks once).
const FRESH_MS = 2_000;
/// The helper answers `status` at once; past this it is taken as not there.
const STATUS_MS = 10_000;

export type DesktopOptions = {
  /// Whether this machine's display can be seen at all (platform.hasDesktopScreen).
  supported: boolean;
  /// The helper's path (`screenHelper`), null when it is not there.
  helper: string | null;
  /// Told when its size or access changed.
  changed: () => void;
  /// Its title (default: the machine's name).
  title?: () => string;
  /// The side test's measurement of the encoder and the link where Screen Recording is not granted: made-up pictures,
  /// no capture (the helper's --synthetic). Never set by the station.
  synthetic?: "moving" | "still";
};

export class Desktop implements ScreenSource {
  readonly id = "desktop";
  readonly kind = "desktop" as const;
  readonly #o: DesktopOptions;
  #status: HelperStatus | null = null;
  #checked = -Infinity;
  #checking: Promise<void> | null = null;
  /// macOS's prompts are asked for once a run, as a view is first refused.
  #asked = false;
  readonly #views = new Set<HelperView>();

  constructor(options: DesktopOptions) {
    this.#o = options;
  }

  title(): string {
    return this.#o.title?.() ?? hostname().replace(/\.local$/, "");
  }

  size(): { width: number; height: number } {
    return { width: this.#status?.display?.width ?? 0, height: this.#status?.display?.height ?? 0 };
  }

  access(): ScreenAccess {
    if (!this.#o.supported) return { capture: false, control: false, unsupported: "platform" };
    if (this.#o.helper === null) return { capture: false, control: false, unsupported: "helper" };
    const s = this.#status;
    const who = s?.responsible?.path ? { app: s.responsible.name, path: s.responsible.path } : {};
    return { capture: s?.capture ?? false, control: s?.control ?? false, ...who };
  }

  /// The grants and the display as macOS has them now (at most FRESH_MS old, unless `force`).
  refresh(force = false): Promise<void> {
    const helper = this.#o.helper;
    if (!this.#o.supported || helper === null) return Promise.resolve();
    if (!force && wall.now() - this.#checked < FRESH_MS) return Promise.resolve();
    this.#checking ??= this.#ask(helper, "status").then(
      (status) => {
        this.#checked = wall.now();
        const before = JSON.stringify(this.#status);
        this.#status = status;
        if (JSON.stringify(status) !== before) this.#o.changed();
      },
      (error) => log.warn("screens", "the desktop's helper did not answer", { error: (error as Error).message }),
    ).finally(() => (this.#checking = null));
    return this.#checking;
  }

  #ask(helper: string, what: "status" | "request"): Promise<HelperStatus> {
    return new Promise((resolve, reject) => {
      execFile(helper, [what], { timeout: STATUS_MS, encoding: "utf8" }, (error, stdout) => {
        if (error) return reject(error);
        try {
          resolve(JSON.parse(stdout.trim().split("\n").at(-1) ?? ""));
        } catch (e) {
          reject(e as Error);
        }
      });
    });
  }

  async open(options: ViewOptions): Promise<ScreenView> {
    const helper = this.#o.helper;
    if (!this.#o.supported) throw new ScreenRefused(501, "station.screen.unsupported", {}, this.access());
    if (helper === null) throw new ScreenRefused(501, "station.screen.noHelper", {}, this.access());
    if (!options.codecs.includes("h264")) throw new ScreenRefused(415, "station.screen.codec", { codec: "H.264" });
    await this.refresh(true);
    if (!this.#status?.capture && this.#o.synthetic === undefined) {
      this.#prompt(helper);
      const access = this.access();
      throw new ScreenRefused(503, "station.screen.captureOff", { app: access.app || "stillfail-station", path: access.path || "" }, access);
    }
    if (!this.#status?.control && this.#o.synthetic === undefined) this.#prompt(helper);
    const extra = this.#o.synthetic === undefined ? [] : ["--synthetic", this.#o.synthetic];
    const view = new HelperView(helper, options, this.#status?.display?.id, extra, () => this.#views.delete(view));
    this.#views.add(view);
    try {
      await view.ready;
    } catch (error) {
      view.close();
      if ((error as HelperError).code === "capture") {
        await this.refresh(true);
        const access = this.access();
        throw new ScreenRefused(503, "station.screen.captureOff", { app: access.app || "stillfail-station", path: access.path || "" }, access);
      }
      throw new ScreenRefused(503, "station.screen.failed", { said: (error as Error).message });
    }
    return view;
  }

  /// macOS's prompts for what is missing (on this machine's screen; they also list the process in System Settings, to
  /// be turned on there).
  #prompt(helper: string) {
    if (this.#asked) return;
    this.#asked = true;
    this.#ask(helper, "request").catch((error) => log.warn("screens", "macOS was not asked for the grants", { error: (error as Error).message }));
  }

  /// The station stopping: every view ends.
  close() {
    for (const view of [...this.#views]) view.close();
  }
}

type HelperError = Error & { code?: string };

/// The helper's messages: a kind byte, the payload's length (4 bytes), the payload (native/screen's main.swift).
export function helperMessage(kind: number, payload: Buffer = Buffer.alloc(0)): Buffer {
  const head = Buffer.alloc(5);
  head[0] = kind;
  head.writeUInt32BE(payload.length, 1);
  return Buffer.concat([head, payload]);
}

/// One view: a helper process, asked for each frame.
class HelperView implements ScreenView {
  readonly ready: Promise<{ width: number; height: number }>;
  readonly #proc: ChildProcess;
  readonly #input = new MacInput();
  #carry: Buffer = Buffer.alloc(0);
  #waiting: ((frame: Frame | null) => void)[] = [];
  #config: FrameConfig | undefined;
  #ended = false;
  #settle!: { resolve: (v: { width: number; height: number }) => void; reject: (e: Error) => void };
  readonly #gone: () => void;

  constructor(helper: string, options: ViewOptions, display: number | undefined, extra: string[], gone: () => void) {
    this.#gone = gone;
    this.ready = new Promise((resolve, reject) => (this.#settle = { resolve, reject }));
    const args = ["view", "--max-width", String(options.maxWidth), "--max-height", String(options.maxHeight)];
    if (display !== undefined) args.push("--display", String(display));
    args.push(...extra);
    this.#proc = spawn(helper, args, { stdio: ["pipe", "pipe", "pipe"] });
    this.#proc.stdin!.on("error", () => this.close());
    this.#proc.stdout!.on("data", (chunk: Buffer) => this.#heard(chunk));
    this.#proc.stderr!.on("data", (chunk: Buffer) => log.info("screens", "the desktop's helper said", { text: chunk.toString().trim().slice(0, 500) }));
    this.#proc.on("error", (error) => {
      this.#settle.reject(error);
      this.close();
    });
    this.#proc.on("exit", () => {
      this.#settle.reject(new Error("the desktop's helper ended"));
      this.close();
    });
  }

  #heard(chunk: Buffer) {
    this.#carry = this.#carry.length === 0 ? chunk : Buffer.concat([this.#carry, chunk]);
    while (this.#carry.length >= 5) {
      const length = this.#carry.readUInt32BE(1);
      if (this.#carry.length < 5 + length) return;
      const kind = this.#carry[0]!;
      const payload = this.#carry.subarray(5, 5 + length);
      this.#carry = this.#carry.subarray(5 + length);
      this.#message(kind, payload);
    }
  }

  #message(kind: number, payload: Buffer) {
    switch (kind) {
      case 1: {
        const info = JSON.parse(payload.toString());
        if (typeof info.error === "string") this.#settle.reject(Object.assign(new Error(info.error), { code: info.code }));
        else {
          log.info("screens", "a view of the desktop opened", { width: info.width, height: info.height, encoder: info.encoder });
          this.#settle.resolve({ width: info.width, height: info.height });
        }
        return;
      }
      case 2:
        this.#config = { codec: "h264", width: payload.readUInt32BE(0), height: payload.readUInt32BE(4), description: new Uint8Array(payload.subarray(8)) };
        return;
      case 3: {
        const frame: Frame = { key: (payload[0]! & 1) === 1, ts: Number(payload.readBigUInt64BE(1)), data: new Uint8Array(payload.subarray(9)) };
        if (this.#config !== undefined) {
          frame.config = this.#config;
          this.#config = undefined;
        }
        this.#waiting.shift()?.(frame);
        return;
      }
      case 4:
        log.info("screens", "the desktop's helper", { said: payload.toString() });
        return;
    }
  }

  #send(kind: number, payload?: Buffer) {
    if (this.#ended) return;
    this.#proc.stdin!.write(helperMessage(kind, payload));
  }

  next(): Promise<Frame | null> {
    if (this.#ended) return Promise.resolve(null);
    return new Promise((resolve) => {
      this.#waiting.push(resolve);
      this.#send(1);
    });
  }

  keyframe() {
    this.#send(2);
  }

  async input(event: ScreenInput): Promise<void> {
    for (const op of this.#input.ops(event, wall.now())) this.#send(3, Buffer.from(JSON.stringify(op)));
  }

  close() {
    if (this.#ended) return;
    this.#ended = true;
    this.#proc.stdin!.end();
    this.#proc.kill();
    for (const resolve of this.#waiting.splice(0)) resolve(null);
    this.#gone();
  }
}

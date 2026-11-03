// Linux desktop views made with GStreamer. Wayland uses the session's XDG RemoteDesktop and ScreenCast portals;
// X11 can use this path when ffmpeg and xdotool are unavailable. Each helper sends complete JPEGs.
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync } from "node:fs";
import { hostname } from "node:os";
import { fileURLToPath } from "node:url";
import { wall } from "../ops/fibers.ts";
import { ScreenRefused } from "./hub.ts";
import type { Frame, ScreenAccess, ScreenInput, ScreenSource, ScreenVideo, ScreenView, ViewOptions } from "./source.ts";
import { EVDEV } from "./x11-desktop.ts";

const MAX_FRAME = 16 * 1024 * 1024;
const CONSENT_WAIT = 4_000;
const FRAME_WAIT = 12_000;
type Size = { width: number; height: number };
type Picture = { data: Buffer; ts: number; size: Size };

type PortalOptions = {
  changed: () => void;
  env: NodeJS.ProcessEnv;
  mode?: "wayland" | "x11";
  title?: () => string;
  python?: string;
  helper?: string;
  consentWaitMs?: number;
};

/// Beside the source in development, beside the station's main.js in its release.
function helperPath(mode: PortalOptions["mode"]): string {
  return fileURLToPath(new URL(mode === "x11" ? "./linux-x11.py" : "./linux-portal.py", import.meta.url));
}

export class LinuxGstDesktop implements ScreenSource {
  readonly id = "desktop";
  readonly kind = "desktop" as const;
  readonly #o: PortalOptions;
  readonly #views = new Set<PortalProcess>();
  readonly #running = new Set<PortalProcess>(); // every helper started, until its process has exited
  #pending: PortalProcess | null = null;
  #failed = false;
  #size: Size = { width: 0, height: 0 };
  #closed = false;

  constructor(options: PortalOptions) { this.#o = options; }
  title(): string { return this.#o.title?.() ?? hostname(); }
  size(): Size { return { ...this.#size }; }
  access(): ScreenAccess {
    if (this.#pending && !this.#pending.isReady) return this.#o.mode === "x11"
      ? { capture: false, control: false, reason: "linuxDesktopStarting" }
      : { capture: false, control: false, reason: "linuxPortalConsent", asking: true };
    if (this.#failed) return { capture: false, control: false, reason: this.#o.mode === "x11" ? "linuxX11FallbackUnavailable" : "linuxPortalUnavailable" };
    return { capture: true, control: true };
  }
  async refresh(_force = false): Promise<void> {} // Listing the desktop never opens a permission dialog.

  async open(options: ViewOptions): Promise<ScreenView> {
    if (!options.codecs.includes("jpeg")) throw new ScreenRefused(415, "station.screen.codec", { codec: "JPEG" });
    const failure = this.#o.mode === "x11" ? "linuxX11FallbackUnavailable" : "linuxPortalUnavailable";
    if (this.#closed) throw new ScreenRefused(503, `station.screen.${failure}`);
    if (!this.#pending) {
      this.#failed = false;
      const helper = this.#o.helper ?? helperPath(this.#o.mode);
      if (!existsSync(helper)) throw new ScreenRefused(503, `station.screen.${failure}`, {}, { capture: false, control: false, reason: failure });
      const process = new PortalProcess(this.#o.python ?? "/usr/bin/python3", helper, this.#o.env,
        (size) => { this.#size = size; this.#o.changed(); },
        () => {
          this.#views.delete(process);
          if (this.#pending === process) { this.#pending = null; this.#failed = !process.finishedNormally; }
          if (!this.#closed) this.#o.changed();
        }, this.#o.mode === "x11" ? "X11 / GStreamer" : "XDG Desktop Portal / PipeWire");
      this.#pending = process;
      this.#running.add(process);
      void process.exited.then(() => this.#running.delete(process));
      void process.ready.then(() => this.#o.changed(), () => {});
    }
    const pending = this.#pending;
    try {
      let stop = () => {};
      const ready = await Promise.race([
        pending.ready.then(() => true),
        new Promise<false>((resolve) => { stop = wall.after(this.#o.consentWaitMs ?? CONSENT_WAIT, () => resolve(false)); }),
      ]).finally(() => stop());
      if (!ready) {
        this.#o.changed();
        throw new ScreenRefused(503, `station.screen.${this.#o.mode === "x11" ? "linuxDesktopStarting" : "linuxPortalConsent"}`, {}, this.access());
      }
      // An open consumes the prepared portal session. Concurrent opens prepare their own and ask separately.
      if (this.#pending !== pending) return await this.open(options);
      this.#pending = null;
      this.#views.add(pending);
      await pending.start(options);
      return pending;
    } catch (error) {
      if (error instanceof ScreenRefused) throw error;
      pending.close();
      this.#failed = true;
      this.#o.changed();
      throw new ScreenRefused(503, `station.screen.${failure}`, {}, this.access());
    }
  }

  async close(): Promise<void> {
    this.#closed = true;
    this.#pending?.close();
    for (const view of [...this.#views]) view.close();
    // Closed means no helper is left running: a closed view's helper may still be releasing its keys.
    await Promise.all([...this.#running].map((process) => process.exited));
  }
}

class PortalProcess implements ScreenView {
  readonly ready: Promise<void>;
  readonly exited: Promise<void>;
  readonly #first: Promise<void>;
  readonly #child: ChildProcessWithoutNullStreams;
  readonly #sizeChanged: (size: Size) => void;
  readonly #gone: () => void;
  readonly #capture: string;
  readonly #keys = new Set<number>();
  #resolveReady!: () => void;
  #rejectReady!: (error: Error) => void;
  #resolveFirst!: () => void;
  #rejectFirst!: (error: Error) => void;
  #carry: Buffer = Buffer.alloc(0);
  #picture: Size = { width: 0, height: 0 };
  #latest: Picture | null = null;
  #last: Picture | null = null;
  #shown: Size | null = null;
  #waiting: { resolve: (frame: Frame | null) => void; reject: (error: Error) => void }[] = [];
  #failure: ScreenRefused | null = null;
  #config = true;
  #lastTs = 0;
  #input: Promise<void> = Promise.resolve();
  #opened = false;
  #ready = false;
  #ended = false;
  #normal = false;
  #error = "";

  constructor(python: string, helper: string, env: NodeJS.ProcessEnv, sizeChanged: (size: Size) => void, gone: () => void, capture: string) {
    this.#sizeChanged = sizeChanged;
    this.#gone = gone;
    this.#capture = capture;
    this.ready = new Promise((resolve, reject) => { this.#resolveReady = resolve; this.#rejectReady = reject; });
    this.#first = new Promise((resolve, reject) => { this.#resolveFirst = resolve; this.#rejectFirst = reject; });
    // A process can fail before open() awaits one of its promises.
    void this.ready.catch(() => {});
    void this.#first.catch(() => {});
    this.#child = spawn(python, ["-u", helper], { env, stdio: ["pipe", "pipe", "pipe"] });
    this.#child.stdin.on("error", () => {});
    this.#child.stderr.on("data", (data: Buffer) => { this.#error = (this.#error + data.toString()).slice(-2000); });
    this.#child.stdout.on("data", (data: Buffer) => this.#read(data));
    this.#child.on("error", (error) => this.#end(error));
    this.#child.on("close", () => this.#end(new Error(this.#error.trim() || "desktop portal ended")));
    this.exited = new Promise((resolve) => {
      this.#child.once("close", () => resolve());
      this.#child.once("error", () => { if (this.#child.pid === undefined) resolve(); }); // never started
    });
  }
  get isReady(): boolean { return this.#ready && !this.#ended; }
  get finishedNormally(): boolean { return this.#normal; }

  async start(options: ViewOptions): Promise<void> {
    await this.#send({ op: "start", maxWidth: options.maxWidth, maxHeight: options.maxHeight, fps: options.fps ?? 15 });
    await wall.within(FRAME_WAIT, this.#first, "desktop portal did not produce a frame");
  }

  #send(command: unknown): Promise<void> {
    if (this.#ended) return Promise.reject(new Error("desktop portal closed"));
    return new Promise((resolve, reject) => this.#child.stdin.write(`${JSON.stringify(command)}\n`, (error) => error ? reject(error) : resolve()));
  }

  #read(chunk: Buffer): void {
    if (this.#ended) return;
    this.#carry = this.#carry.length ? Buffer.concat([this.#carry, chunk]) : chunk;
    while (this.#carry.length >= 5) {
      const kind = this.#carry.readUInt8(0), length = this.#carry.readUInt32BE(1);
      if (length > MAX_FRAME) { this.#end(new Error("desktop portal frame is too large")); return; }
      if (this.#carry.length < length + 5) return;
      const body = this.#carry.subarray(5, length + 5);
      this.#carry = this.#carry.subarray(length + 5);
      if (kind === 1) {
        try {
          const message = JSON.parse(body.toString()) as { type?: string; width?: number; height?: number; message?: string; code?: string };
          if (message.type === "ready") {
            this.#ready = true;
            if (message.width && message.height) this.#sizeChanged({ width: message.width, height: message.height });
            this.#resolveReady();
          } else if (message.type === "picture") {
            if (typeof message.width !== "number" || typeof message.height !== "number" || !Number.isInteger(message.width) || !Number.isInteger(message.height) || message.width < 1 || message.height < 1 || message.width > 16384 || message.height > 16384) throw new Error("invalid desktop picture size");
            this.#picture = { width: message.width, height: message.height };
          } else if (message.type === "error") {
            this.#end(new Error(message.message || "desktop portal failed"));
          } else if (message.type === "input_error" && message.code === "textUnsupported") {
            this.#end(new ScreenRefused(422, "station.screen.linuxTextUnsupported"));
          }
        } catch (error) { this.#end(error as Error); }
        if (this.#ended) return;
      } else if (kind === 2) {
        if (!this.#picture.width || !this.#picture.height) { this.#end(new Error("desktop portal sent a picture without its size")); return; }
        const ts = Math.max(this.#lastTs + 1, Number(process.hrtime.bigint() / 1000n));
        this.#lastTs = ts;
        const picture = { data: body, ts, size: this.#picture };
        this.#last = picture;
        const waiting = this.#waiting.shift();
        if (waiting) waiting.resolve(this.#frame(picture)); else this.#latest = picture;
        if (!this.#opened) { this.#opened = true; this.#resolveFirst(); }
      } else { this.#end(new Error("unrecognized desktop portal frame")); return; }
    }
  }
  #frame(picture: Picture): Frame {
    const { data, ts, size } = picture;
    const changed = !this.#shown || this.#shown.width !== size.width || this.#shown.height !== size.height;
    const config = this.#config || changed ? { config: { codec: "jpeg" as const, ...size } } : {};
    this.#config = false;
    this.#shown = size;
    return { ...config, key: true, ts, data };
  }
  next(): Promise<Frame | null> {
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#ended) return Promise.resolve(null);
    if (this.#latest) {
      const picture = this.#latest;
      this.#latest = null;
      return Promise.resolve(this.#frame(picture));
    }
    return new Promise((resolve, reject) => this.#waiting.push({ resolve, reject }));
  }
  keyframe(): void {
    // Like a browser tab's JPEG view, replay the last picture if the desktop has not changed since it was sent.
    if (!this.#last || this.#ended) return;
    this.#config = true;
    const ts = Math.max(this.#lastTs + 1, Number(process.hrtime.bigint() / 1000n));
    this.#lastTs = ts;
    const picture = { ...this.#last, ts };
    const waiting = this.#waiting.shift();
    if (waiting) waiting.resolve(this.#frame(picture)); else this.#latest = picture;
  }
  video(): ScreenVideo { return { capture: this.#capture, encoder: "GStreamer JPEG (software)" }; }

  input(event: ScreenInput): Promise<void> {
    // Consecutive pointer, key and modifier events must reach the portal in the same order they arrived.
    const next = this.#input.then(() => this.#post(event));
    this.#input = next.catch(() => {});
    return next;
  }

  async #post(event: ScreenInput): Promise<void> {
    if (event.t !== "key") return this.#send({ op: "input", event });
    const keycode = EVDEV[event.code];
    if (keycode === undefined) {
      if (event.kind === "down" && Array.from(event.key).length === 1 && (event.mods & 6) === 0) {
        await this.#send({ op: "input", event: { t: "text", text: event.key } });
      }
      return;
    }
    const send = (code: number, kind: "down" | "up") => this.#send({ op: "input", event: { t: "key", keycode: code, kind } });
    if (event.kind === "up") {
      await send(keycode, "up");
      this.#keys.delete(keycode);
      return;
    }
    const mods = [{ bit: 1, codes: [56, 100] }, { bit: 2, codes: [29, 97] }, { bit: 4, codes: [125, 126] }, { bit: 8, codes: [42, 54] }];
    const temporary = mods.filter((mod) => (event.mods & mod.bit) !== 0 && !mod.codes.includes(keycode) && !mod.codes.some((code) => this.#keys.has(code))).map((mod) => mod.codes[0]!);
    for (const mod of temporary) { await send(mod, "down"); this.#keys.add(mod); }
    await send(keycode, "down");
    this.#keys.add(keycode);
    for (const mod of temporary.reverse()) { await send(mod, "up"); this.#keys.delete(mod); }
  }

  #end(error: Error, terminate = true): void {
    if (this.#ended) return;
    this.#ended = true;
    if (error instanceof ScreenRefused) this.#failure = error;
    if (!this.#ready) this.#rejectReady(error);
    if (!this.#opened) this.#rejectFirst(error);
    if (terminate) this.#child.kill();
    const child = this.#child;
    wall.after(2_000, () => { if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL"); });
    this.#latest = null;
    this.#last = null;
    for (const waiting of this.#waiting.splice(0)) {
      if (this.#failure) waiting.reject(this.#failure); else waiting.resolve(null);
    }
    this.#gone();
  }
  close(): void {
    if (this.#ended) return;
    this.#normal = true;
    // A live helper can release its virtual keys and buttons before the portal session closes. An unanswered
    // permission dialog cannot read this command, so #end still bounds the lifetime of the process.
    if (!this.#child.stdin.destroyed && !this.#child.stdin.writableEnded) this.#child.stdin.end('{"op":"close"}\n');
    this.#end(new Error("desktop portal closed"), false);
  }
}

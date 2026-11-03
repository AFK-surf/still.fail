// A Linux desktop shared through the session's XDG RemoteDesktop and ScreenCast portals. The companion Python
// process holds the portal session and PipeWire fd for exactly as long as the view does; it sends only complete JPEGs.
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync } from "node:fs";
import { hostname } from "node:os";
import { fileURLToPath } from "node:url";
import { ScreenRefused } from "./hub.ts";
import type { Frame, ScreenAccess, ScreenInput, ScreenSource, ScreenVideo, ScreenView, ViewOptions } from "./source.ts";
import { EVDEV } from "./x11-desktop.ts";

const MAX_FRAME = 16 * 1024 * 1024;
const CONSENT_WAIT = 4_000;
const FRAME_WAIT = 12_000;
type Size = { width: number; height: number };

type PortalOptions = {
  changed: () => void;
  env: NodeJS.ProcessEnv;
  title?: () => string;
  python?: string;
  helper?: string;
  consentWaitMs?: number;
};

/// Beside the source in development, beside the station's main.js in its release.
function helperPath(): string {
  return fileURLToPath(new URL("./linux-portal.py", import.meta.url));
}

export class WaylandDesktop implements ScreenSource {
  readonly id = "desktop";
  readonly kind = "desktop" as const;
  readonly #o: PortalOptions;
  readonly #views = new Set<PortalProcess>();
  #pending: PortalProcess | null = null;
  #failed = false;
  #size: Size = { width: 0, height: 0 };
  #closed = false;

  constructor(options: PortalOptions) { this.#o = options; }
  title(): string { return this.#o.title?.() ?? hostname(); }
  size(): Size { return { ...this.#size }; }
  access(): ScreenAccess {
    if (this.#pending && !this.#pending.isReady) return { capture: false, control: false, reason: "linuxPortalConsent", asking: true };
    if (this.#failed) return { capture: false, control: false, reason: "linuxPortalUnavailable" };
    return { capture: true, control: true };
  }
  async refresh(_force = false): Promise<void> {} // Listing the desktop never opens a permission dialog.

  async open(options: ViewOptions): Promise<ScreenView> {
    if (!options.codecs.includes("jpeg")) throw new ScreenRefused(415, "station.screen.codec", { codec: "JPEG" });
    if (this.#closed) throw new ScreenRefused(503, "station.screen.linuxPortalUnavailable");
    if (!this.#pending) {
      this.#failed = false;
      const helper = this.#o.helper ?? helperPath();
      if (!existsSync(helper)) throw new ScreenRefused(503, "station.screen.linuxPortalUnavailable");
      const process = new PortalProcess(this.#o.python ?? "/usr/bin/python3", helper, this.#o.env,
        (size) => { this.#size = size; this.#o.changed(); },
        () => {
          this.#views.delete(process);
          if (this.#pending === process) { this.#pending = null; this.#failed = !process.finishedNormally; }
          if (!this.#closed) this.#o.changed();
        });
      this.#pending = process;
      void process.ready.then(() => this.#o.changed(), () => {});
    }
    const pending = this.#pending;
    try {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const ready = await Promise.race([
        pending.ready.then(() => true),
        new Promise<false>((resolve) => { timer = setTimeout(() => resolve(false), this.#o.consentWaitMs ?? CONSENT_WAIT); }),
      ]).finally(() => { if (timer) clearTimeout(timer); });
      if (!ready) {
        this.#o.changed();
        throw new ScreenRefused(503, "station.screen.linuxPortalConsent", {}, this.access());
      }
      // An open consumes the prepared portal session. Another caller waiting on it needs its own session.
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
      throw new ScreenRefused(503, "station.screen.linuxPortalUnavailable", {}, this.access());
    }
  }

  async close(): Promise<void> {
    this.#closed = true;
    this.#pending?.close();
    for (const view of [...this.#views]) view.close();
  }
}

class PortalProcess implements ScreenView {
  readonly ready: Promise<void>;
  readonly #first: Promise<void>;
  readonly #child: ChildProcessWithoutNullStreams;
  readonly #sizeChanged: (size: Size) => void;
  readonly #gone: () => void;
  readonly #keys = new Set<number>();
  #resolveReady!: () => void;
  #rejectReady!: (error: Error) => void;
  #resolveFirst!: () => void;
  #rejectFirst!: (error: Error) => void;
  #carry: Buffer = Buffer.alloc(0);
  #picture: Size = { width: 0, height: 0 };
  #latest: { data: Buffer; ts: number } | null = null;
  #waiting: ((frame: Frame | null) => void)[] = [];
  #config = true;
  #lastTs = 0;
  #opened = false;
  #ready = false;
  #ended = false;
  #normal = false;
  #error = "";

  constructor(python: string, helper: string, env: NodeJS.ProcessEnv, sizeChanged: (size: Size) => void, gone: () => void) {
    this.#sizeChanged = sizeChanged;
    this.#gone = gone;
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
  }
  get isReady(): boolean { return this.#ready && !this.#ended; }
  get finishedNormally(): boolean { return this.#normal; }

  async start(options: ViewOptions): Promise<void> {
    await this.#send({ op: "start", maxWidth: options.maxWidth, maxHeight: options.maxHeight, fps: options.fps ?? 15 });
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([this.#first, new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("desktop portal did not produce a frame")), FRAME_WAIT);
      })]);
    } finally { if (timer) clearTimeout(timer); }
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
          const message = JSON.parse(body.toString()) as { type?: string; width?: number; height?: number; message?: string };
          if (message.type === "ready") {
            this.#ready = true;
            if (message.width && message.height) this.#sizeChanged({ width: message.width, height: message.height });
            this.#resolveReady();
          } else if (message.type === "picture") {
            if (!message.width || !message.height || message.width > 16384 || message.height > 16384) throw new Error("invalid desktop picture size");
            // Do not label an older queued picture with the new size while its first frame is still in the pipe.
            this.#latest = null;
            this.#picture = { width: message.width, height: message.height };
            this.#config = true;
          } else if (message.type === "error") {
            this.#end(new Error(message.message || "desktop portal failed"));
          }
        } catch (error) { this.#end(error as Error); }
      } else if (kind === 2) {
        if (!this.#picture.width || !this.#picture.height) { this.#end(new Error("desktop portal sent a picture without its size")); return; }
        const ts = Math.max(this.#lastTs + 1, Number(process.hrtime.bigint() / 1000n));
        this.#lastTs = ts;
        const waiting = this.#waiting.shift();
        if (waiting) waiting(this.#frame(body, ts)); else this.#latest = { data: body, ts };
        if (!this.#opened) { this.#opened = true; this.#resolveFirst(); }
      } else { this.#end(new Error("unrecognized desktop portal frame")); return; }
    }
  }
  #frame(data: Buffer, ts: number): Frame {
    const config = this.#config ? { config: { codec: "jpeg" as const, ...this.#picture } } : {};
    this.#config = false;
    return { ...config, key: true, ts, data };
  }
  next(): Promise<Frame | null> {
    if (this.#ended) return Promise.resolve(null);
    if (this.#latest) {
      const { data, ts } = this.#latest;
      this.#latest = null;
      return Promise.resolve(this.#frame(data, ts));
    }
    return new Promise((resolve) => this.#waiting.push(resolve));
  }
  keyframe(): void {} // Every JPEG is a key frame.
  video(): ScreenVideo { return { capture: "XDG Desktop Portal / PipeWire", encoder: "GStreamer JPEG (software)" }; }

  async input(event: ScreenInput): Promise<void> {
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

  #end(error: Error, kill = true): void {
    if (this.#ended) return;
    this.#ended = true;
    if (!this.#ready) this.#rejectReady(error);
    if (!this.#opened) this.#rejectFirst(error);
    if (kill) this.#child.kill();
    this.#latest = null;
    for (const waiting of this.#waiting.splice(0)) waiting(null);
    this.#gone();
  }
  close(): void {
    if (this.#ended) return;
    this.#normal = true;
    // Let the helper release its virtual inputs and close the portal. A dialog that never answered cannot read the
    // command yet, so bound the time for which that process may remain alive.
    const timer = setTimeout(() => this.#child.kill("SIGKILL"), 2_000);
    timer.unref();
    this.#child.once("close", () => clearTimeout(timer));
    this.#child.stdin.end('{"op":"close"}\n');
    this.#end(new Error("desktop portal closed"), false);
  }
}

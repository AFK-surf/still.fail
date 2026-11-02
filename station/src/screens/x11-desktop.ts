// The station user's X11 desktop. ffmpeg captures it as JPEG frames and xdotool posts input; both are system tools.
// A view keeps only the newest frame, so a slow client cannot build a queue of old pictures. Wayland needs its own
// portal implementation: an Xwayland DISPLAY alone does not capture the Wayland desktop.
import { execFile, spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { accessSync, constants } from "node:fs";
import { hostname } from "node:os";
import { delimiter, isAbsolute, join } from "node:path";
import { promisify } from "node:util";
import { wall } from "../ops/fibers.ts";
import { ScreenRefused } from "./hub.ts";
import type { Frame, ScreenAccess, ScreenInput, ScreenSource, ScreenVideo, ScreenView, ViewOptions } from "./source.ts";

const run = promisify(execFile);
const MAX_FRAME = 16 * 1024 * 1024;
const OPEN_TIMEOUT = 10_000;
const FRESH_MS = 2_000;
// xdotool temporarily changes the X keymap for characters outside the layout. Give applications time to read it.
const TYPE_DELAY_MS = 20;
type Size = { width: number; height: number };
type Reason = NonNullable<ScreenAccess["reason"]>;

/// Resolve only executables, without invoking a shell or consulting a different user's environment.
function executable(name: string, env: NodeJS.ProcessEnv): string | null {
  const paths = isAbsolute(name) || name.includes("/") ? [name] : (env.PATH ?? "").split(delimiter).filter(Boolean).map((dir) => join(dir, name));
  return paths.find((path) => {
    try { accessSync(path, constants.X_OK); return true; } catch { return false; }
  }) ?? null;
}

export type X11DesktopOptions = {
  changed: () => void;
  title?: () => string;
  /// A test may supply its own desktop environment and binaries.
  env?: NodeJS.ProcessEnv;
  ffmpeg?: string;
  xdotool?: string;
};

export class X11Desktop implements ScreenSource {
  readonly id = "desktop";
  readonly kind = "desktop" as const;
  readonly #o: X11DesktopOptions;
  readonly #views = new Set<X11View>();
  #size: Size = { width: 0, height: 0 };
  #reason: Reason | undefined = "linuxNoDisplay";
  #looked = 0;
  #looking: Promise<void> | null = null;

  constructor(options: X11DesktopOptions) { this.#o = options; }
  title(): string { return this.#o.title?.() ?? hostname(); }
  size(): Size { return { ...this.#size }; }
  access(): ScreenAccess {
    return this.#reason ? { capture: false, control: false, reason: this.#reason } : { capture: true, control: true };
  }

  /// Ask the X server in the station's own session; neither a display name nor a running process implies access.
  refresh(force = false): Promise<void> {
    if (!force && wall.now() - this.#looked < FRESH_MS) return Promise.resolve();
    this.#looking ??= this.#inspect().then(({ size, reason }) => {
      if (size.width !== this.#size.width || size.height !== this.#size.height || reason !== this.#reason) {
        this.#size = size;
        this.#reason = reason;
        this.#o.changed();
      }
    }).finally(() => { this.#looked = wall.now(); this.#looking = null; });
    return this.#looking;
  }

  async #inspect(): Promise<{ size: Size; reason?: Reason }> {
    const env = this.#o.env ?? process.env;
    const empty = { width: 0, height: 0 };
    if (env.XDG_SESSION_TYPE?.toLowerCase() === "wayland" || env.WAYLAND_DISPLAY) return { size: empty, reason: "linuxWayland" };
    if (!env.DISPLAY) return { size: empty, reason: "linuxNoDisplay" };
    const ffmpeg = executable(this.#o.ffmpeg ?? "ffmpeg", env);
    const xdotool = executable(this.#o.xdotool ?? "xdotool", env);
    if (!ffmpeg || !xdotool) return { size: empty, reason: "linuxTools" };
    try {
      const { stdout } = await run(xdotool, ["getdisplaygeometry"], { env, timeout: 3_000 });
      const match = /^(\d+)\s+(\d+)\s*$/.exec(stdout);
      const width = Number(match?.[1]), height = Number(match?.[2]);
      if (!Number.isInteger(width) || !Number.isInteger(height) || width < 2 || height < 2 || width > 16384 || height > 16384) throw new Error("invalid display size");
      return { size: { width, height } };
    } catch {
      return { size: empty, reason: "linuxUnavailable" };
    }
  }

  async open(options: ViewOptions): Promise<ScreenView> {
    if (!options.codecs.includes("jpeg")) throw new ScreenRefused(415, "station.screen.codec", { codec: "JPEG" });
    await this.refresh(true);
    if (this.#reason) throw new ScreenRefused(503, `station.screen.${this.#reason}`, {}, this.access());
    const env = this.#o.env ?? process.env;
    // Both were found by refresh, but may have been removed since.
    const ffmpeg = executable(this.#o.ffmpeg ?? "ffmpeg", env);
    const xdotool = executable(this.#o.xdotool ?? "xdotool", env);
    if (!ffmpeg || !xdotool) throw new ScreenRefused(503, "station.screen.linuxTools", {}, { capture: false, control: false, reason: "linuxTools" });
    const view = new X11View(ffmpeg, xdotool, env, this.#size, options, () => this.#views.delete(view));
    this.#views.add(view);
    try { await view.ready; return view; }
    catch (error) { view.close(); throw new ScreenRefused(503, "station.screen.failed", { said: (error as Error).message }); }
  }

  async close(): Promise<void> { for (const view of [...this.#views]) view.close(); }
}

/// The JPEG encoder needs even dimensions and does not enlarge a screen beyond its native size.
function fitted(size: Size, maxWidth: number, maxHeight: number): Size {
  const scale = Math.min(1, Math.max(2, maxWidth) / size.width, Math.max(2, maxHeight) / size.height);
  return { width: Math.max(2, Math.floor(size.width * scale / 2) * 2), height: Math.max(2, Math.floor(size.height * scale / 2) * 2) };
}

// DOM KeyboardEvent.code is a physical position. Xorg's evdev keycodes are Linux input codes plus 8: sending
// keysyms instead would move the key on a different layout (KeyQ, for example, is 'a' on French AZERTY).
const EVDEV: Record<string, number> = {
  Escape: 1, Digit1: 2, Digit2: 3, Digit3: 4, Digit4: 5, Digit5: 6, Digit6: 7, Digit7: 8, Digit8: 9, Digit9: 10, Digit0: 11,
  Minus: 12, Equal: 13, Backspace: 14, Tab: 15,
  KeyQ: 16, KeyW: 17, KeyE: 18, KeyR: 19, KeyT: 20, KeyY: 21, KeyU: 22, KeyI: 23, KeyO: 24, KeyP: 25,
  BracketLeft: 26, BracketRight: 27, Enter: 28, ControlLeft: 29,
  KeyA: 30, KeyS: 31, KeyD: 32, KeyF: 33, KeyG: 34, KeyH: 35, KeyJ: 36, KeyK: 37, KeyL: 38,
  Semicolon: 39, Quote: 40, Backquote: 41, ShiftLeft: 42, Backslash: 43,
  KeyZ: 44, KeyX: 45, KeyC: 46, KeyV: 47, KeyB: 48, KeyN: 49, KeyM: 50, Comma: 51, Period: 52, Slash: 53,
  ShiftRight: 54, NumpadMultiply: 55, AltLeft: 56, Space: 57, CapsLock: 58,
  F1: 59, F2: 60, F3: 61, F4: 62, F5: 63, F6: 64, F7: 65, F8: 66, F9: 67, F10: 68,
  NumLock: 69, ScrollLock: 70, Numpad7: 71, Numpad8: 72, Numpad9: 73, NumpadSubtract: 74,
  Numpad4: 75, Numpad5: 76, Numpad6: 77, NumpadAdd: 78, Numpad1: 79, Numpad2: 80, Numpad3: 81, Numpad0: 82,
  NumpadDecimal: 83, IntlBackslash: 86, F11: 87, F12: 88, IntlRo: 89, Convert: 92, KanaMode: 93, NonConvert: 94,
  NumpadComma: 95, NumpadEnter: 96, ControlRight: 97, NumpadDivide: 98, PrintScreen: 99, AltRight: 100,
  Home: 102, ArrowUp: 103, PageUp: 104, ArrowLeft: 105, ArrowRight: 106, End: 107, ArrowDown: 108, PageDown: 109,
  Insert: 110, Delete: 111, AudioVolumeMute: 113, AudioVolumeDown: 114, AudioVolumeUp: 115, NumpadEqual: 117,
  Pause: 119, Lang1: 122, Lang2: 123, IntlYen: 124, MetaLeft: 125, MetaRight: 126, OSLeft: 125, OSRight: 126,
  ContextMenu: 127, MediaTrackNext: 163, MediaPlayPause: 164, MediaTrackPrevious: 165, MediaStop: 166,
  F13: 183, F14: 184, F15: 185, F16: 186, F17: 187, F18: 188, F19: 189, F20: 190, F21: 191, F22: 192, F23: 193, F24: 194,
};

/// xdotool accepts a decimal string as a literal X keycode.
function keyOf(code: string): string | null {
  const evdev = EVDEV[code];
  return evdev === undefined ? null : String(evdev + 8);
}

const MODS = [
  { bit: 1, keys: [keyOf("AltLeft")!, keyOf("AltRight")!] }, { bit: 2, keys: [keyOf("ControlLeft")!, keyOf("ControlRight")!] },
  { bit: 4, keys: [keyOf("MetaLeft")!, keyOf("MetaRight")!] }, { bit: 8, keys: [keyOf("ShiftLeft")!, keyOf("ShiftRight")!] },
];
const BUTTONS = [{ bit: 1, button: 1 }, { bit: 2, button: 3 }, { bit: 4, button: 2 }];

class X11View implements ScreenView {
  readonly ready: Promise<void>;
  readonly #child: ChildProcessWithoutNullStreams;
  readonly #xdotool: string;
  readonly #env: NodeJS.ProcessEnv;
  readonly #screen: Size;
  readonly #picture: Size;
  readonly #gone: () => void;
  readonly #keys = new Set<string>();
  readonly #buttons = new Set<number>();
  #input: Promise<void> = Promise.resolve();
  #carry: Buffer = Buffer.alloc(0);
  #latest: { data: Buffer; ts: number } | null = null;
  #waiting: ((frame: Frame | null) => void)[] = [];
  #config = true;
  #lastTs = 0;
  #ended = false;
  #wheel = { x: 0, y: 0 };
  #opened = false;
  #resolve!: () => void;
  #reject!: (error: Error) => void;
  #timer: () => void;
  #stderr = "";

  constructor(ffmpeg: string, xdotool: string, env: NodeJS.ProcessEnv, screen: Size, options: ViewOptions, gone: () => void) {
    this.#xdotool = xdotool;
    this.#env = env;
    this.#screen = { ...screen };
    this.#picture = fitted(screen, options.maxWidth, options.maxHeight);
    this.#gone = gone;
    this.ready = new Promise((resolve, reject) => { this.#resolve = resolve; this.#reject = reject; });
    // Bound this experimental software encoder's CPU use even when a client asks for a higher frame rate.
    const fps = Math.min(15, Math.max(1, Math.round(options.fps ?? 15)));
    const args = ["-nostdin", "-loglevel", "error", "-f", "x11grab", "-draw_mouse", "1", "-framerate", String(fps),
      "-video_size", `${screen.width}x${screen.height}`, "-i", env.DISPLAY!, "-vf", `scale=${this.#picture.width}:${this.#picture.height}:flags=fast_bilinear`,
      "-c:v", "mjpeg", "-q:v", "5", "-threads", "1", "-f", "image2pipe", "pipe:1"];
    this.#child = spawn(ffmpeg, args, { env, stdio: ["pipe", "pipe", "pipe"] });
    this.#child.stdin.end();
    this.#child.stderr.on("data", (data: Buffer) => { this.#stderr = (this.#stderr + data.toString()).slice(-2000); });
    this.#child.stdout.on("data", (data: Buffer) => this.#read(data));
    this.#child.on("error", (error) => this.#end(error));
    this.#child.on("close", () => this.#end(new Error(this.#stderr.trim() || "X11 capture ended")));
    this.#timer = wall.after(OPEN_TIMEOUT, () => this.#end(new Error("X11 capture did not produce a frame")));
  }

  #read(chunk: Buffer) {
    if (this.#ended) return;
    this.#carry = this.#carry.length ? Buffer.concat([this.#carry, chunk]) : chunk;
    while (this.#carry.length) {
      const start = this.#carry.indexOf(Buffer.from([0xff, 0xd8]));
      if (start < 0) { this.#carry = this.#carry.subarray(Math.max(0, this.#carry.length - 1)); return; }
      if (start > 0) this.#carry = this.#carry.subarray(start);
      const end = this.#carry.indexOf(Buffer.from([0xff, 0xd9]), 2);
      if (end < 0) {
        if (this.#carry.length > MAX_FRAME) this.#end(new Error("X11 frame is too large"));
        return;
      }
      if (end + 2 > MAX_FRAME) { this.#end(new Error("X11 frame is too large")); return; }
      const data = this.#carry.subarray(0, end + 2);
      this.#carry = this.#carry.subarray(end + 2);
      const ts = Math.max(this.#lastTs + 1, Number(process.hrtime.bigint() / 1000n));
      this.#lastTs = ts;
      const waiting = this.#waiting.shift();
      if (waiting) waiting(this.#frame(data, ts));
      else this.#latest = { data, ts };
      if (!this.#opened) { this.#opened = true; this.#timer(); this.#resolve(); }
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
  keyframe(): void {} // Each JPEG is a key frame.
  video(): ScreenVideo { return { capture: "X11", encoder: "ffmpeg MJPEG (software)" }; }

  async #command(args: string[], timeout = 3_000): Promise<void> {
    await run(this.#xdotool, args, { env: this.#env, timeout });
  }
  async #type(text: string): Promise<void> {
    await this.#command(["type", "--delay", String(TYPE_DELAY_MS), "--", text], 5_000 + Array.from(text).length * TYPE_DELAY_MS * 3);
  }
  input(event: ScreenInput): Promise<void> {
    const next = this.#input.then(async () => {
      if (this.#ended) return;
      const point = (x: number, y: number) => [String(Math.max(0, Math.min(this.#screen.width - 1, Math.round(x * (this.#screen.width - 1))))), String(Math.max(0, Math.min(this.#screen.height - 1, Math.round(y * (this.#screen.height - 1)))))];
      if (event.t === "pointer") {
        await this.#command(["mousemove", ...point(event.x, event.y)]);
        for (const { bit, button } of BUTTONS) {
          const down = (event.buttons & bit) !== 0, was = this.#buttons.has(button);
          if (down === was) continue;
          await this.#command([down ? "mousedown" : "mouseup", String(button)]);
          if (down) this.#buttons.add(button); else this.#buttons.delete(button);
        }
      } else if (event.t === "wheel") {
        await this.#command(["mousemove", ...point(event.x, event.y)]);
        this.#wheel.x += event.dx / 100;
        this.#wheel.y += event.dy / 100;
        for (const axis of ["x", "y"] as const) {
          const whole = Math.trunc(this.#wheel[axis]);
          if (!whole) continue;
          const count = Math.min(20, Math.abs(whole));
          this.#wheel[axis] -= Math.sign(whole) * count;
          const button = axis === "y" ? (whole > 0 ? 5 : 4) : (whole > 0 ? 7 : 6);
          await this.#command(["click", "--repeat", String(count), "--delay", "0", String(button)]);
        }
      } else if (event.t === "key") {
        const key = keyOf(event.code);
        if (!key) {
          if (event.kind === "down" && Array.from(event.key).length === 1 && (event.mods & 6) === 0) await this.#type(event.key);
          return;
        }
        if (event.kind === "up") {
          await this.#command(["keyup", key]);
          this.#keys.delete(key);
          return;
        }
        const temporary = MODS.filter((m) => (event.mods & m.bit) !== 0 && !m.keys.includes(key) && !m.keys.some((k) => this.#keys.has(k))).map((m) => m.keys[0]!);
        for (const mod of temporary) { await this.#command(["keydown", mod]); this.#keys.add(mod); }
        await this.#command(["keydown", key]);
        this.#keys.add(key);
        for (const mod of temporary.reverse()) { await this.#command(["keyup", mod]); this.#keys.delete(mod); }
      } else if (event.text) {
        await this.#type(event.text);
      }
    });
    this.#input = next.catch(() => {});
    return next;
  }

  #end(error: Error) {
    if (this.#ended) return;
    this.#ended = true;
    this.#timer();
    if (!this.#opened) this.#reject(error);
    this.#child.kill();
    this.#latest = null;
    for (const waiting of this.#waiting.splice(0)) waiting(null);
    // Release anything this view pressed even if its client disappeared while dragging or typing.
    void this.#input.then(async () => {
      for (const key of this.#keys) await this.#command(["keyup", key]).catch(() => {});
      for (const button of this.#buttons) await this.#command(["mouseup", String(button)]).catch(() => {});
      this.#keys.clear();
      this.#buttons.clear();
    });
    this.#gone();
  }
  close(): void { this.#end(new Error("X11 view closed")); }
}

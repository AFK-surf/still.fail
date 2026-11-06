// Android emulators and phones on this machine's adb as screen sources (`android:<id>`, docs/remote-screens.md
// "Android"): a touchscreen as an iOS Simulator is (kind `simulator`), its pictures and input through scrcpy's program
// on the device (./scrcpy-server, its version pinned: its protocol is its own and changes between releases). A phone
// lent to a chat is in that grant's adb server (adb/servers.ts), not here.
import { type ChildProcess, type ChildProcessWithoutNullStreams, execFile, spawn } from "node:child_process";
import { randomInt } from "node:crypto";
import net from "node:net";
import { fileURLToPath } from "node:url";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import { ScreenRefused } from "./hub.ts";
import type { Panel } from "./sim-mask.ts";
import type { Frame, FrameConfig, ScreenInput, ScreenSource, ScreenVideo, ScreenView, Screens, ViewOptions } from "./source.ts";

/// The version of ./scrcpy-server: it refuses to run under any other name.
export const SERVER_VERSION = "5.0.1";
/// scrcpy's server: beside this module in src, and beside main.js (this module bundled into it) in a release.
export const SERVER_FILE = fileURLToPath(new URL("./scrcpy-server", import.meta.url));
/// How long a view's program has to start listening on the device.
const CONNECT_TIMEOUT = 15_000;
/// How long a look at a device is given (a phone over Wi-Fi may be slow, one that has gone never answers).
const ADB_TIMEOUT = 15_000;
/// How long after `adb track-devices` ended it is started again.
const FOLLOW_AGAIN = 5_000;
/// How long after a device could not be looked at it is looked at again (adb has an emulator long before it has booted).
const LOOK_AGAIN = 3_000;
/// How long adb's devices are followed after the screens were last asked for, none of them there: followed from the
/// station's start, adb's server and `track-devices` ran even on machines without a device. One there keeps them followed.
const FOLLOWED_FOR = 10 * 60_000;
/// Encoded frames kept for a view that asks slowly: past this they are dropped up to a new key frame (a delta dropped
/// alone would break every frame after it).
const QUEUE_MOST = 30;
/// What a view is encoded at, by the side scrcpy is asked for (sideOf): its encoder takes no new rate while it runs, so a
/// view cannot start low and climb as the pace asks of a helper's. A phone's UI stays sharp at these where 1.5 Mbit/s
/// (the pace's start, which this took before) left 1280 and up soft; a still screen sends nothing at any of them.
export function bitrateOf(side: number): number {
  return side <= 480 ? 2_000_000 : side <= 720 ? 3_000_000 : side <= 1080 ? 5_000_000 : side <= 1440 ? 7_000_000 : 8_000_000;
}
/// A preview (a link's card): about two pictures a second, small and cheap.
export const PEEK_FPS = 2;
export const PEEK_BITRATE = 300_000;
/// The most previews of this machine's devices running at once, besides the views: each is a run of scrcpy and an
/// encoder on a device, and a video decoder in the client showing its card (a page of cards would use up a phone's
/// hardware decoders). One more is refused (503) and its card asks again later.
export const PEEKS_MOST = 2;
/// What a view opened to drive shows at least, however small the window it opened in: scrcpy cannot change its size
/// without starting over.
const LEAST_SIDE = 1280;
const MOST_SIDE = 2560;
/// How far apart two width-to-height ratios are the one shape (a picture's size is rounded to multiples of 8).
const SAME_SHAPE = 0.02;
const SCROLL_MOST = 16;
/// A page's wheel pixels in one notch of Android's AXIS_SCROLL.
const WHEEL_NOTCH = 100;

// Control messages (scrcpy's ControlMessage.java)
const CONTROL_KEY = 0, CONTROL_TEXT = 1, CONTROL_TOUCH = 2, CONTROL_SCROLL = 3, CONTROL_CLIPBOARD = 9, CONTROL_RESET = 17;
const TOUCH_DOWN = 0, TOUCH_UP = 1, TOUCH_MOVE = 2;
/// scrcpy's POINTER_ID_GENERIC_FINGER: a finger, not its mouse.
const FINGER = -2n;
const TEXT_MOST = 300;
/// The display turned a quarter (out of following the sensor, as a person's own lock does).
const ROTATE = `case "$(wm user-rotation)" in "lock 1") n=2;; "lock 2") n=3;; "lock 3") n=0;; *) n=1;; esac; wm user-rotation lock $n`;

const KEY_HOME = 3, KEY_BACK = 4, KEY_VOLUME_UP = 24, KEY_VOLUME_DOWN = 25, KEY_POWER = 26, KEY_APP_SWITCH = 187;

/// A page's KeyboardEvent.code → Android's KeyEvent keycode. Escape is the device's back, as the emulator's has it.
export const KEYCODES: Record<string, number> = {
  ...Object.fromEntries([..."ABCDEFGHIJKLMNOPQRSTUVWXYZ"].map((c, i) => [`Key${c}`, 29 + i])),
  ...Object.fromEntries([..."0123456789"].map((c, i) => [`Digit${c}`, 7 + i])),
  ...Object.fromEntries(Array.from({ length: 12 }, (_, i) => [`F${i + 1}`, 131 + i])),
  Enter: 66, NumpadEnter: 66, Escape: KEY_BACK, Backspace: 67, Tab: 61, Space: 62, Minus: 69, Equal: 70, BracketLeft: 71,
  BracketRight: 72, Backslash: 73, Semicolon: 74, Quote: 75, Backquote: 68, Comma: 55, Period: 56, Slash: 76, CapsLock: 115,
  Insert: 124, Home: 122, PageUp: 92, Delete: 112, End: 123, PageDown: 93, ArrowRight: 22, ArrowLeft: 21, ArrowDown: 20,
  ArrowUp: 19, ShiftLeft: 59, ShiftRight: 60, ControlLeft: 113, ControlRight: 114, AltLeft: 57, AltRight: 58, MetaLeft: 117,
  MetaRight: 118,
};

/// A ScreenInput's `mods` (bit 0 alt, 1 ctrl, 2 meta, 3 shift) as Android's meta state, each with its left key's bit.
export function metaOf(mods: number): number {
  return ((mods & 1) !== 0 ? 0x12 : 0) | ((mods & 2) !== 0 ? 0x3000 : 0) | ((mods & 4) !== 0 ? 0x30000 : 0) | ((mods & 8) !== 0 ? 0x41 : 0);
}

const clamp = (v: number) => (Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0);

/// A person's input (source.ts `ScreenInput`) as scrcpy's control messages: the left button held is a finger, a wheel
/// the device's scroll, a key its keycode. Simulator.app's shortcuts, which the app's device buttons send, press this
/// device's. Text goes as keys while they are ASCII, else pasted (over what its clipboard held, as an iOS Simulator's).
export class AndroidInput {
  #finger = false;

  messages(e: ScreenInput, size: { width: number; height: number }): Buffer[] {
    switch (e.t) {
      case "pointer": {
        const left = (e.buttons & 1) === 1;
        if (!this.#finger) {
          if (e.kind !== "down" || !left) return [];
          this.#finger = true;
          return [touch(TOUCH_DOWN, e.x, e.y, size)];
        }
        if (left && e.kind !== "up") return [touch(TOUCH_MOVE, e.x, e.y, size)];
        this.#finger = false;
        return [touch(TOUCH_UP, e.x, e.y, size)];
      }
      case "wheel":
        return e.dx === 0 && e.dy === 0 ? [] : [scroll(e.x, e.y, e.dx, e.dy, size)];
      case "key":
        return this.#key(e.kind === "down", e.code, e.mods);
      case "text":
        return textMessages(e.text);
      case "device":
        return e.name === "volume_up" ? press(KEY_VOLUME_UP) : e.name === "volume_down" ? press(KEY_VOLUME_DOWN) : [];
      case "pose":
      case "button":
        return [];
    }
  }

  #key(down: boolean, code: string, mods: number): Buffer[] {
    const meta = (mods & 4) !== 0, shift = (mods & 8) !== 0, ctrl = (mods & 2) !== 0, alt = (mods & 1) !== 0;
    if (meta && !alt) {
      const button = ctrl ? (shift && code === "KeyH" ? KEY_APP_SWITCH : null)
        : shift && code === "KeyH" ? KEY_HOME : !shift && code === "KeyL" ? KEY_POWER : null;
      if (button !== null) return down ? press(button) : [];
      // (its software keyboard shows by itself as a field takes the focus)
      if (!ctrl && !shift && code === "KeyK") return [];
    }
    const keycode = KEYCODES[code];
    return keycode === undefined ? [] : [key(down, keycode, metaOf(mods))];
  }
}

function key(down: boolean, keycode: number, meta: number): Buffer {
  const b = Buffer.alloc(14);
  b[0] = CONTROL_KEY;
  b[1] = down ? 0 : 1;
  b.writeInt32BE(keycode, 2);
  b.writeInt32BE(0, 6);
  b.writeInt32BE(meta, 10);
  return b;
}

const press = (keycode: number): Buffer[] => [key(true, keycode, 0), key(false, keycode, 0)];

function position(b: Buffer, at: number, x: number, y: number, size: { width: number; height: number }) {
  b.writeInt32BE(Math.min(size.width - 1, Math.round(clamp(x) * size.width)), at);
  b.writeInt32BE(Math.min(size.height - 1, Math.round(clamp(y) * size.height)), at + 4);
  b.writeUInt16BE(size.width, at + 8);
  b.writeUInt16BE(size.height, at + 10);
}

function touch(action: number, x: number, y: number, size: { width: number; height: number }): Buffer {
  const b = Buffer.alloc(32);
  b[0] = CONTROL_TOUCH;
  b[1] = action;
  b.writeBigInt64BE(FINGER, 2);
  position(b, 10, x, y, size);
  b.writeUInt16BE(action === TOUCH_UP ? 0 : 0xffff, 22);
  return b;
}

/// A notch's share of [-16, 16] as scrcpy's 16-bit fixed point. A wheel's dy down is the page's content going up: a
/// negative AXIS_VSCROLL.
function scrollAxis(pixels: number): number {
  const notches = Math.max(-SCROLL_MOST, Math.min(SCROLL_MOST, pixels / WHEEL_NOTCH));
  return Math.max(-32768, Math.min(32767, Math.round((notches / SCROLL_MOST) * 32768)));
}

function scroll(x: number, y: number, dx: number, dy: number, size: { width: number; height: number }): Buffer {
  const b = Buffer.alloc(21);
  b[0] = CONTROL_SCROLL;
  position(b, 1, x, y, size);
  b.writeInt16BE(scrollAxis(dx), 13);
  b.writeInt16BE(scrollAxis(-dy), 15);
  return b;
}

function textMessages(text: string): Buffer[] {
  if (text === "") return [];
  const utf8 = Buffer.from(text, "utf8");
  if (utf8.length <= TEXT_MOST && /^[\x20-\x7e]*$/.test(text)) {
    const head = Buffer.alloc(5);
    head[0] = CONTROL_TEXT;
    head.writeUInt32BE(utf8.length, 1);
    return [Buffer.concat([head, utf8])];
  }
  const head = Buffer.alloc(14);
  head[0] = CONTROL_CLIPBOARD;
  head[9] = 1; // paste, after a sequence of 0 (no answer asked)
  head.writeUInt32BE(utf8.length, 10);
  return [Buffer.concat([head, utf8])];
}

/// The NAL units of an Annex B stream, without their start codes.
export function nalsOf(data: Uint8Array): Uint8Array[] {
  const out: Uint8Array[] = [];
  let start = -1;
  for (let i = 0; i + 2 < data.length; i++) {
    if (data[i] !== 0 || data[i + 1] !== 0 || data[i + 2] !== 1) continue;
    if (start >= 0) out.push(data.subarray(start, data[i - 1] === 0 ? i - 1 : i));
    start = i + 3;
    i += 2;
  }
  if (start >= 0) out.push(data.subarray(start));
  return out;
}

/// The avcC of an H.264 stream's SPS and PPS; null without both.
export function avcCOf(nals: Uint8Array[]): Uint8Array | null {
  const sps = nals.find((n) => (n[0]! & 0x1f) === 7);
  const pps = nals.find((n) => (n[0]! & 0x1f) === 8);
  if (sps === undefined || pps === undefined || sps.length < 4) return null;
  const out = Buffer.alloc(11 + sps.length + pps.length);
  out[0] = 1;
  out[1] = sps[1]!;
  out[2] = sps[2]!;
  out[3] = sps[3]!;
  out[4] = 0xff; // lengths in 4 bytes
  out[5] = 0xe1; // one SPS
  out.writeUInt16BE(sps.length, 6);
  out.set(sps, 8);
  out[8 + sps.length] = 1; // one PPS
  out.writeUInt16BE(pps.length, 9 + sps.length);
  out.set(pps, 11 + sps.length);
  return out;
}

/// A frame's NAL units as AVCC, what its config says of itself left out.
export function avccOf(nals: Uint8Array[]): Uint8Array {
  const kept = nals.filter((n) => {
    const type = n[0]! & 0x1f;
    return type !== 7 && type !== 8;
  });
  const out = Buffer.alloc(kept.reduce((sum, n) => sum + 4 + n.length, 0));
  let at = 0;
  for (const n of kept) {
    out.writeUInt32BE(n.length, at);
    out.set(n, at + 4);
    at += 4 + n.length;
  }
  return out;
}

/// What the video socket says, as scrcpy's develop.md has it: a byte (a forward tunnel's), the device's name, the codec,
/// then for each capture a session packet and media packets (the first of each session its config).
export class ScrcpyStream {
  #carry: Buffer = Buffer.alloc(0);
  #stage = 0;
  readonly #session: (size: { width: number; height: number }) => void;
  readonly #packet: (p: { config: boolean; key: boolean; pts: bigint; data: Uint8Array }) => void;

  constructor(session: (size: { width: number; height: number }) => void, packet: (p: { config: boolean; key: boolean; pts: bigint; data: Uint8Array }) => void) {
    this.#session = session;
    this.#packet = packet;
  }

  heard(chunk: Buffer) {
    this.#carry = this.#carry.length === 0 ? chunk : Buffer.concat([this.#carry, chunk]);
    for (;;) {
      const need = [1, 64, 4, 12][this.#stage]!;
      if (this.#carry.length < need) return;
      if (this.#stage < 3) {
        this.#carry = this.#carry.subarray(need);
        this.#stage++;
        continue;
      }
      const flags = this.#carry[0]!;
      if ((flags & 0x80) !== 0) {
        this.#session({ width: this.#carry.readUInt32BE(4), height: this.#carry.readUInt32BE(8) });
        this.#carry = this.#carry.subarray(12);
        continue;
      }
      const length = this.#carry.readUInt32BE(8);
      if (this.#carry.length < 12 + length) return;
      this.#packet({
        config: (flags & 0x40) !== 0,
        key: (flags & 0x20) !== 0,
        pts: this.#carry.readBigUInt64BE(0) & 0x1fffffffffffffffn,
        data: new Uint8Array(this.#carry.subarray(12, 12 + length)),
      });
      this.#carry = this.#carry.subarray(12 + length);
    }
  }
}

/// How adb is run here: a server this starts does not connect by itself to every phone paired with this machine's key
/// it finds on the network, a phone lent to one chat among them (docs/adb-share.md: that chat's server alone has it).
export const adbEnv = (env: NodeJS.ProcessEnv = process.env): NodeJS.ProcessEnv => ({ ...env, ADB_MDNS_AUTO_CONNECT: "0" });

/// adb started: a .cmd (a shim) through what runs it, no window on Windows.
function adbSpawn(path: string, args: string[]): ChildProcessWithoutNullStreams {
  const env = adbEnv();
  const r = platform.runnable(path, args, env);
  return spawn(r.file, r.args, { windowsHide: true, windowsVerbatimArguments: r.windowsVerbatimArguments, env });
}

/// `adb` of one device.
type Adb = {
  run(args: string[]): Promise<string>;
  shell(command: string): ChildProcess;
};

function adbOf(path: string, serial: string): Adb {
  return {
    run: (args) => adbRun(path, ["-s", serial, ...args]),
    shell: (command) => adbSpawn(path, ["-s", serial, "shell", command]),
  };
}

function adbRun(path: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = adbSpawn(path, args);
    let out = "", err = "";
    const stop = wall.after(ADB_TIMEOUT, () => child.kill());
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (err += d));
    child.on("error", (e) => (stop(), reject(e)));
    child.on("close", (code) => {
      stop();
      if (code === 0) resolve(out);
      else reject(new Error(err.trim() || `adb ended with ${code}`));
    });
  });
}

function connect(port: number): Promise<net.Socket> {
  return new Promise((resolve, reject) => {
    const socket = net.connect(port, "127.0.0.1");
    socket.once("connect", () => (socket.off("error", reject), resolve(socket)));
    socket.once("error", reject);
  });
}

/// What a socket says first, the socket paused after it; null when it ends without a word.
function firstOf(socket: net.Socket): Promise<Buffer | null> {
  return new Promise((resolve) => {
    const settled = (first: Buffer | null) => {
      socket.pause();
      socket.off("data", settled);
      socket.off("close", none);
      socket.off("error", none);
      resolve(first);
    };
    const none = () => settled(null);
    socket.on("data", settled);
    socket.on("close", none);
    socket.on("error", none);
  });
}

/// One view: a run of scrcpy's program on the device, with its tunnel. A still screen sends nothing.
export class AndroidView implements ScreenView {
  readonly #adb: Adb;
  readonly #gone: () => void;
  readonly #sized: (size: { width: number; height: number }) => void;
  readonly #input = new AndroidInput();
  #server: ChildProcess | null = null;
  #video: net.Socket | null = null;
  #control: net.Socket | null = null;
  #port = 0;
  #ended = false;
  #size = { width: 0, height: 0 };
  /// The config to go with the next frame, and whether the queue is dropped up to the next key frame.
  #config: FrameConfig | undefined;
  #dropping = false;
  #lastTs = 0;
  readonly #queue: Frame[] = [];
  readonly #waiting: ((frame: Frame | null) => void)[] = [];

  constructor(adb: Adb, gone: () => void, sized: (size: { width: number; height: number }) => void) {
    this.#adb = adb;
    this.#gone = gone;
    this.#sized = sized;
  }

  /// Puts the program on the device, runs it and connects (its file taken off again once it runs).
  async start(file: string, options: { maxSide: number; bitrate: number; fps?: number; wake: boolean }) {
    const scid = randomInt(1, 0x7fffffff).toString(16).padStart(8, "0");
    const jar = `/data/local/tmp/stillfail-scrcpy-${scid}.jar`;
    const name = `localabstract:scrcpy_${scid}`;
    await this.#adb.run(["push", file, jar]);
    this.#port = Number((await this.#adb.run(["forward", "tcp:0", name])).trim());
    if (!Number.isInteger(this.#port) || this.#port <= 0) throw new Error("adb gave no port for the view");
    const args = [
      `scid=${scid}`, "log_level=warn", "audio=false", "control=true", "tunnel_forward=true", "cleanup=false", "video_codec=h264",
      `max_size=${options.maxSide}`, `video_bit_rate=${options.bitrate}`, `max_fps=${options.fps ?? 60}`, `power_on=${options.wake}`,
    ];
    const server = this.#adb.shell(`CLASSPATH=${jar} app_process / com.genymobile.scrcpy.Server ${SERVER_VERSION} ${args.join(" ")}`);
    this.#server = server;
    let said = "";
    server.stdout?.on("data", (d) => (said += d));
    server.stderr?.on("data", (d) => (said += d));
    server.on("close", () => {
      if (!this.#ended) log.warn("screens", "an Android view's program ended", { said: said.slice(0, 500) });
      this.close();
    });
    // (a forward tunnel takes a connection before anything listens: the byte the program sends first says it does)
    const until = wall.now() + CONNECT_TIMEOUT;
    while (this.#video === null) {
      if (this.#ended) throw new Error(said.trim() || "the view's program ended");
      if (wall.now() > until) throw new Error(said.trim() || "the view's program did not start");
      const socket = await connect(this.#port).catch(() => null);
      const first = socket === null ? null : await firstOf(socket);
      if (socket === null || first === null) {
        socket?.destroy();
        await wall.sleep(100);
        continue;
      }
      this.#video = socket;
      const stream = new ScrcpyStream((size) => this.#session(size), (p) => this.#packet(p));
      socket.on("data", (d: Buffer) => stream.heard(d));
      socket.on("error", () => this.close());
      socket.on("close", () => this.close());
      stream.heard(first);
      socket.resume();
    }
    const control = await connect(this.#port);
    // (what it answers, a clipboard's change, nobody here asks)
    control.on("data", () => {});
    control.on("error", () => this.close());
    this.#control = control;
    void this.#adb.run(["shell", `rm -f ${jar}`]).catch(() => {});
  }

  #session(size: { width: number; height: number }) {
    this.#size = size;
    this.#sized(size);
  }

  #packet(p: { config: boolean; key: boolean; pts: bigint; data: Uint8Array }) {
    const nals = nalsOf(p.data);
    if (p.config) {
      const description = avcCOf(nals);
      if (description !== null) this.#config = { codec: "h264", ...this.#size, description };
      return;
    }
    if (this.#dropping && !p.key) return;
    this.#dropping = false;
    // Rising, whatever a new capture's clock starts from.
    const ts = Math.max(this.#lastTs + 1, Number(p.pts));
    this.#lastTs = ts;
    const frame: Frame = { key: p.key, ts, data: avccOf(nals), ...(p.key && this.#config ? { config: this.#config } : {}) };
    if (p.key) this.#config = undefined;
    const waiting = this.#waiting.shift();
    if (waiting) {
      waiting(frame);
      return;
    }
    this.#queue.push(frame);
    if (this.#queue.length > QUEUE_MOST) {
      // (the new capture says its config again)
      this.#queue.length = 0;
      this.#dropping = true;
      this.keyframe();
    }
  }

  next(): Promise<Frame | null> {
    if (this.#ended) return Promise.resolve(null);
    const frame = this.#queue.shift();
    if (frame) return Promise.resolve(frame);
    return new Promise((resolve) => this.#waiting.push(resolve));
  }

  keyframe() {
    this.#control?.write(Buffer.from([CONTROL_RESET]));
  }

  async input(event: ScreenInput) {
    // Turned by the window manager, the picture's new shape following from scrcpy (its own ROTATE_DEVICE does nothing on an
    // Android 16 emulator).
    if (event.t === "device" && event.name === "rotate") {
      await this.#adb.run(["shell", ROTATE]).catch(() => {});
      return;
    }
    if (this.#size.width === 0) return;
    for (const message of this.#input.messages(event, this.#size)) this.#control?.write(message);
  }

  video(): ScreenVideo {
    return { capture: "scrcpy" };
  }

  close() {
    if (this.#ended) return;
    this.#ended = true;
    this.#video?.destroy();
    this.#control?.destroy();
    this.#server?.kill();
    if (this.#port > 0) void this.#adb.run(["forward", "--remove", `tcp:${this.#port}`]).catch(() => {});
    for (const waiting of this.#waiting.splice(0)) waiting(null);
    this.#gone();
  }
}

/// The side a view asks scrcpy for: what it asked, or for one to drive at least what stays sharp as its window grows.
export function sideOf(options: ViewOptions): number {
  const asked = Math.max(options.maxWidth, options.maxHeight);
  // (a multiple of 8, as encoders take)
  return Math.min(MOST_SIDE, options.peek ? asked : Math.max(LEAST_SIDE, asked)) & ~7;
}

/// What scrcpy is run with for a view: its side, its rate by that side (bitrateOf; `ViewOptions.bitrate`, the pace's start
/// for a source that climbs from it, is not taken), its frames a second as asked (none: 60), its screen turned on to
/// drive. A preview: PEEK_FPS and PEEK_BITRATE at the card's size, the screen left as it is.
export function viewArgs(options: ViewOptions): { maxSide: number; bitrate: number; fps?: number; wake: boolean } {
  const maxSide = sideOf(options);
  if (options.peek === true) return { maxSide, bitrate: PEEK_BITRATE, fps: PEEK_FPS, wake: false };
  return { maxSide, bitrate: bitrateOf(maxSide), ...(options.fps ? { fps: options.fps } : {}), wake: true };
}

/// The previews running of a machine's devices, PEEKS_MOST at most.
export class PeekCount {
  #running = 0;
  readonly #most: number;

  constructor(most = PEEKS_MOST) {
    this.#most = most;
  }

  /// One more starts, unless as many as can run already do.
  take(): boolean {
    if (this.#running >= this.#most) return false;
    this.#running++;
    return true;
  }

  free() {
    this.#running = Math.max(0, this.#running - 1);
  }

  get running(): number {
    return this.#running;
  }
}

/// One device on adb.
export class AndroidScreen implements ScreenSource {
  readonly id: string;
  readonly kind = "simulator" as const;
  /// A preview opens as any view does, without turning its screen on.
  readonly peek = true;
  readonly panels: Panel[];
  readonly #title: string;
  readonly #adb: Adb;
  readonly #file: string;
  readonly #changed: () => void;
  readonly #views = new Set<AndroidView>();
  readonly #peeks: PeekCount;
  /// An emulator's start (ms); none: a phone, which costs this machine nothing while nobody uses it.
  readonly #since: number | undefined;
  #size: { width: number; height: number };
  readonly discard?: () => Promise<void>;

  constructor(o: { id: string; title: string; size: { width: number; height: number }; panels: Panel[]; adb: Adb; file: string; changed: () => void; peeks?: PeekCount; emulator?: { since: number } }) {
    this.id = o.id;
    this.#since = o.emulator?.since;
    // An emulator is closed from a person's app (one left running, the core's `longJobs`): it leaves adb, and the list.
    if (o.emulator) this.discard = async () => void (await o.adb.run(["emu", "kill"]));
    this.#peeks = o.peeks ?? new PeekCount();
    this.panels = o.panels;
    this.#title = o.title;
    this.#size = o.size;
    this.#adb = o.adb;
    this.#file = o.file;
    this.#changed = o.changed;
  }

  title(): string {
    return this.#title;
  }

  since(): number | undefined {
    return this.#since;
  }

  size(): { width: number; height: number } {
    return this.#size;
  }

  async open(options: ViewOptions): Promise<ScreenView> {
    if (!options.codecs.includes("h264")) throw new ScreenRefused(415, "station.screen.codec", { codec: "H.264" });
    const peek = options.peek === true;
    if (peek && !this.#peeks.take()) throw new ScreenRefused(503, "station.screen.failed", { said: `at most ${PEEKS_MOST} Android screens are previewed at once` });
    const view: AndroidView = new AndroidView(this.#adb, () => {
      this.#views.delete(view);
      if (peek) this.#peeks.free();
    }, (size) => {
      // Turned or unfolded: its shape as the listing has it.
      if (Math.abs(size.width / size.height - this.#size.width / this.#size.height) < SAME_SHAPE) return;
      this.#size = size;
      this.#changed();
    });
    this.#views.add(view);
    try {
      await view.start(this.#file, viewArgs(options));
      return view;
    } catch (error) {
      view.close();
      log.warn("screens", "an Android view did not open", { id: this.id, error: (error as Error).message });
      throw new ScreenRefused(503, "station.screen.failed", { said: (error as Error).message });
    }
  }

  /// It left adb (or the station stops): its views end.
  gone() {
    for (const view of [...this.#views]) view.close();
  }
}

/// When the emulator of `serial` (`emulator-<port>`) started (ms): its qemu's start, where `ps` says it (macOS, Linux);
/// none elsewhere (Windows) or when it is not found, and the station takes when it listed it.
export async function emulatorStart(serial: string, ps: () => Promise<string> = psStarts): Promise<number | undefined> {
  const port = /^emulator-(\d+)$/.exec(serial)?.[1];
  if (port === undefined || platform.os === "windows") return undefined;
  const lines = await ps().catch(() => "");
  return startOf(lines, port);
}

/// The start of the qemu run with `-port <port>` in `ps -Ao lstart=,args=`'s lines (its start the first five words, a
/// local time: `Fri Nov  6 16:34:52 2026`).
export function startOf(lines: string, port: string): number | undefined {
  for (const line of lines.split("\n")) {
    const words = line.trim().split(/\s+/);
    const args = words.slice(5);
    const at = args.indexOf("-port");
    if (at < 0 || args[at + 1] !== port || !/qemu-system|emulator/.test(args[0] ?? "")) continue;
    const t = Date.parse(words.slice(0, 5).join(" "));
    if (Number.isFinite(t)) return t;
  }
  return undefined;
}

const psStarts = () =>
  new Promise<string>((resolve, reject) => execFile("ps", ["-Ao", "lstart=,args="], { timeout: 10_000, maxBuffer: 16 << 20 }, (error, out) => (error ? reject(error) : resolve(out))));

/// Whether a device on adb is a screen: an emulator, a phone on USB or one someone connected to by its address. Not one
/// adb found on the network by itself (`adb-<serial>._adb-tls-connect._tcp`: any phone paired with this key that is on
/// the same network, which nobody here asked to show), nor one lent through a member link (adb/link.ts `PORTS`).
export function shownDevice(serial: string): boolean {
  return !serial.includes("._adb") && !serial.startsWith("127.0.0.1:");
}

/// What `adb track-devices -l` says each time: `<four hex digits of length><lines>`, each line `serial state …`. The
/// devices ready to use.
export function devicesOf(lines: string): string[] {
  return lines.split("\n").flatMap((line) => {
    const [serial, state] = line.trim().split(/\s+/);
    return serial && state === "device" ? [serial] : [];
  });
}

/// The panels of `dumpsys display`: each display's size and its corners' radii as shares of its width, top left and
/// then round it; one with no rounded corners is left out.
export function panelsOf(dumpsys: string): Panel[] {
  const out = new Map<string, Panel>();
  for (const line of dumpsys.split("\n")) {
    if (!line.includes("mBaseDisplayInfo=")) continue;
    const real = /\breal (\d+) x (\d+)/.exec(line);
    const rounded = /roundedCorners RoundedCorners\{\[(.*?)\]\}/.exec(line);
    if (!real || !rounded) continue;
    const [width, height] = [Number(real[1]), Number(real[2])];
    const radius = (position: string) => Number(new RegExp(`position=${position}, radius=(\\d+)`).exec(rounded[1]!)?.[1] ?? 0) / width;
    const corners: Panel["corners"] = [radius("TopLeft"), radius("TopRight"), radius("BottomRight"), radius("BottomLeft")];
    if (width > 0 && corners.some((c) => c > 0)) out.set(`${width}x${height}`, { width, height, corners });
  }
  return [...out.values()];
}

/// `wm size`'s answer: the size overriding the physical one where there is one.
export function sizeOf(wm: string): { width: number; height: number } {
  const of = (word: string) => new RegExp(`${word} size: (\\d+)x(\\d+)`).exec(wm);
  const m = of("Override") ?? of("Physical");
  return m ? { width: Number(m[1]), height: Number(m[2]) } : { width: 0, height: 0 };
}

/// The devices on this machine's adb, each a screen while it is on it. A machine without adb lists none.
export class AndroidScreens {
  readonly #screens: Screens & { changed(): void };
  readonly #adb: () => string | null;
  readonly #file: string;
  readonly #listed = new Map<string, { id: string; source: AndroidScreen; remove: () => void }>();
  /// The previews running, of all its devices.
  readonly #peeks = new PeekCount();
  #follow: ChildProcess | null = null;
  #again: (() => void) | null = null;
  #closed = false;
  #serials: string[] = [];
  #looking = Promise.resolve();
  #lookAgain: (() => void) | null = null;
  readonly #again_ms: number;
  /// When following stops, nothing listed (`FOLLOWED_FOR` after the screens were last asked for).
  #rest: (() => void) | null = null;
  #resting = false;

  constructor(o: { screens: Screens & { changed(): void }; adb: () => string | null; file?: string; lookAgain?: number }) {
    this.#screens = o.screens;
    this.#adb = o.adb;
    this.#again_ms = o.lookAgain ?? LOOK_AGAIN;
    this.#file = o.file ?? SERVER_FILE;
  }

  start() {
    this.#resting = false;
    if (this.#closed || this.#follow !== null) return;
    const path = this.#adb();
    if (path === null) return;
    const child = adbSpawn(path, ["track-devices", "-l"]);
    this.#follow = child;
    let carry = "";
    child.stdout.on("data", (d) => {
      carry += d;
      for (;;) {
        const length = parseInt(carry.slice(0, 4), 16);
        if (!Number.isInteger(length) || carry.length < 4 + length) return;
        this.#heard(path, devicesOf(carry.slice(4, 4 + length)));
        carry = carry.slice(4 + length);
      }
    });
    child.on("error", () => {});
    child.on("close", () => {
      this.#follow = null;
      if (this.#closed || this.#resting) return;
      this.#again?.();
      this.#again = wall.after(FOLLOW_AGAIN, () => this.start());
    });
  }

  /// As the screens are asked for: adb may have come since (one put on the machine, its follow ended).
  async refresh(): Promise<void> {
    this.start();
    this.#rest?.();
    this.#rest = wall.after(FOLLOWED_FOR, () => this.#stopFollowing());
    await this.#looking;
  }

  /// Not asked for in a while: adb's devices let go of while none is listed (asked for again: followed again).
  #stopFollowing() {
    this.#rest = null;
    if (this.#closed) return;
    if (this.#listed.size > 0) {
      this.#rest = wall.after(FOLLOWED_FOR, () => this.#stopFollowing());
      return;
    }
    this.#resting = true;
    this.#again?.();
    this.#again = null;
    this.#follow?.kill();
  }

  #heard(path: string, serials: string[]) {
    this.#serials = serials;
    this.#looking = this.#looking.then(() => this.#look(path)).catch((error) => log.warn("screens", "looking at adb's devices failed", { error: (error as Error).message }));
  }

  async #look(path: string) {
    const serials = this.#serials.filter(shownDevice);
    for (const [serial, listed] of [...this.#listed]) {
      if (serials.includes(serial)) continue;
      this.#listed.delete(serial);
      listed.remove();
      listed.source.gone();
    }
    let unseen = false;
    for (const serial of serials) {
      if (this.#closed || this.#listed.has(serial)) continue;
      // (a phone both on USB and over Wi-Fi: the one screen)
      const source = await this.#screen(path, serial).catch((error) => {
        unseen = true;
        log.info("screens", "an Android device could not be looked at yet", { serial, error: (error as Error).message });
        return null;
      });
      if (source === null || [...this.#listed.values()].some((l) => l.id === source.id)) continue;
      if (this.#closed || !this.#serials.includes(serial)) continue;
      this.#listed.set(serial, { id: source.id, source, remove: this.#screens.add(source) });
    }
    this.#lookAgain?.();
    this.#lookAgain = unseen && !this.#closed ? wall.after(this.#again_ms, () => this.#heard(path, this.#serials)) : null;
  }

  async #screen(path: string, serial: string): Promise<AndroidScreen> {
    const adb = adbOf(path, serial);
    // (what is asked below is not there until it has booted)
    if ((await adb.run(["shell", "getprop sys.boot_completed"])).trim() !== "1") throw new Error("still booting");
    const emulator = serial.startsWith("emulator-");
    const props = await adb.run(["shell", "getprop ro.serialno; getprop ro.product.model; getprop ro.build.version.release; settings get global device_name"]);
    const [serialno, model, release, named] = props.split("\n").map((l) => l.trim());
    const avd = emulator ? (await adb.run(["emu", "avd", "name"]).catch(() => "")).split("\n")[0]!.trim() : "";
    const name = avd || (named && named !== "null" ? named : model) || serial;
    // (emulators all have one ro.serialno, a phone keeps its own however it is connected)
    const id = `android:${emulator || !serialno ? serial : serialno}`;
    return new AndroidScreen({
      id,
      title: `${name} · Android ${release}`,
      size: sizeOf(await adb.run(["shell", "wm size"])),
      panels: panelsOf(await adb.run(["shell", "dumpsys display"]).catch(() => "")),
      adb,
      file: this.#file,
      changed: () => this.#screens.changed(),
      peeks: this.#peeks,
      ...(emulator ? { emulator: { since: (await emulatorStart(serial)) ?? wall.now() } } : {}),
    });
  }

  /// The station stopping: nothing followed, every source gone.
  close() {
    this.#closed = true;
    this.#rest?.();
    this.#again?.();
    this.#lookAgain?.();
    this.#follow?.kill();
    for (const listed of this.#listed.values()) {
      listed.remove();
      listed.source.gone();
    }
    this.#listed.clear();
  }
}

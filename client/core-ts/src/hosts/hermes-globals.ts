// What the core and Effect take from a JS host that Hermes has not (the Android app's engine, apps/android/core):
// timers on the engine's loop (`__native.setTimer`), TextEncoder/TextDecoder, structuredClone of plain data,
// AbortController, a URL that reads absolute URLs, performance.now, crypto.getRandomValues, console. Each is put in only
// where the engine has none of its own; case conversion always (hermes-case.ts: the engine's needs Java the app has
// not). Imported first by hosts/hermes.ts.

/// What the engine (C++) puts on the global object for the JS (also hosts/hermes.ts's).
export interface HermesNative {
  call(id: number, op: string, json: string, bytes: ArrayBuffer | undefined): void;
  callSync(op: string, json: string): string;
  emit(client: number, json: string): void;
  fatal(reason: string): void;
  now(): number;
  monotonic(): number;
  utcOffset(atMs: number): number;
  random(n: number): ArrayBuffer;
  setTimer(id: number, ms: number): void;
  clearTimer(id: number): void;
  log(level: number, message: string): void;
}

import { lowerCase, upperCase } from "./hermes-case.ts";

// deno-lint-ignore no-explicit-any
const g = globalThis as any;
const native = g.__native as HermesNative;

// ── timers: the engine's loop calls __stillfail_timer(id) when one is due ──

const timers = new Map<number, () => void>();
let nextTimer = 1;
g.__stillfail_timer = (id: number) => {
  const run = timers.get(id);
  if (!run) return;
  timers.delete(id);
  run();
};
if (typeof g.setTimeout !== "function") {
  g.setTimeout = (fn: (...a: unknown[]) => void, ms?: number, ...args: unknown[]) => {
    const id = nextTimer++;
    timers.set(id, () => fn(...args));
    native.setTimer(id, Math.max(0, Number(ms) || 0));
    return id;
  };
  g.clearTimeout = (id: number) => {
    if (timers.delete(id)) native.clearTimer(id);
  };
  g.setInterval = (fn: (...a: unknown[]) => void, ms?: number, ...args: unknown[]) => {
    const id = nextTimer++;
    const every = Math.max(0, Number(ms) || 0);
    const tick = () => {
      timers.set(id, tick);
      native.setTimer(id, every);
      fn(...args);
    };
    timers.set(id, tick);
    native.setTimer(id, every);
    return id;
  };
  g.clearInterval = g.clearTimeout;
}
if (typeof g.setImmediate !== "function") {
  g.setImmediate = (fn: (...a: unknown[]) => void, ...args: unknown[]) => g.setTimeout(fn, 0, ...args);
  g.clearImmediate = (id: number) => g.clearTimeout(id);
}
if (typeof g.queueMicrotask !== "function") {
  g.queueMicrotask = (fn: () => void) => void Promise.resolve().then(fn);
}

// ── text ──

if (typeof g.TextEncoder !== "function") {
  g.TextEncoder = class TextEncoder {
    readonly encoding = "utf-8";
    encode(input = ""): Uint8Array {
      const s = String(input);
      const out: number[] = [];
      for (let i = 0; i < s.length; i++) {
        let c = s.charCodeAt(i);
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
          const d = s.charCodeAt(i + 1);
          if (d >= 0xdc00 && d <= 0xdfff) {
            c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00);
            i++;
          } else c = 0xfffd;
        } else if (c >= 0xd800 && c <= 0xdfff) c = 0xfffd;
        if (c < 0x80) out.push(c);
        else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
        else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
        else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      }
      return new Uint8Array(out);
    }
  };
}
if (typeof g.TextDecoder !== "function") {
  g.TextDecoder = class TextDecoder {
    readonly encoding = "utf-8";
    decode(input?: ArrayBuffer | ArrayBufferView): string {
      if (input === undefined) return "";
      const b = input instanceof ArrayBuffer ? new Uint8Array(input) : new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
      let out = "";
      const chunk: number[] = [];
      const flush = () => {
        out += String.fromCharCode.apply(null, chunk);
        chunk.length = 0;
      };
      for (let i = 0; i < b.length; ) {
        const c = b[i];
        let cp = 0xfffd;
        let n = 1;
        if (c < 0x80) cp = c;
        else if (c >= 0xc2 && c < 0xe0 && i + 1 < b.length && (b[i + 1] & 0xc0) === 0x80) {
          cp = ((c & 31) << 6) | (b[i + 1] & 63);
          n = 2;
        } else if (c >= 0xe0 && c < 0xf0 && i + 2 < b.length && (b[i + 1] & 0xc0) === 0x80 && (b[i + 2] & 0xc0) === 0x80) {
          cp = ((c & 15) << 12) | ((b[i + 1] & 63) << 6) | (b[i + 2] & 63);
          n = 3;
          if (cp < 0x800 || (cp >= 0xd800 && cp <= 0xdfff)) cp = 0xfffd;
        } else if (c >= 0xf0 && c < 0xf5 && i + 3 < b.length && (b[i + 1] & 0xc0) === 0x80 && (b[i + 2] & 0xc0) === 0x80 && (b[i + 3] & 0xc0) === 0x80) {
          cp = ((c & 7) << 18) | ((b[i + 1] & 63) << 12) | ((b[i + 2] & 63) << 6) | (b[i + 3] & 63);
          n = 4;
          if (cp < 0x10000 || cp > 0x10ffff) cp = 0xfffd;
        }
        if (cp >= 0x10000) {
          cp -= 0x10000;
          chunk.push(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
        } else chunk.push(cp);
        if (chunk.length > 8000) flush();
        i += n;
      }
      flush();
      return out;
    }
  };
}

// ── data ──

/// A copy of plain data (what the core clones: JSON values, bytes, Maps, Sets, Dates).
function clone(v: unknown, seen: Map<object, unknown>): unknown {
  if (v === null || typeof v !== "object") return v;
  if (seen.has(v)) return seen.get(v);
  if (ArrayBuffer.isView(v)) {
    const copy = new (v.constructor as new (b: ArrayBuffer) => ArrayBufferView)((v.buffer as ArrayBuffer).slice(v.byteOffset, v.byteOffset + v.byteLength));
    seen.set(v, copy);
    return copy;
  }
  if (v instanceof ArrayBuffer) return v.slice(0);
  if (v instanceof Date) return new Date(v.getTime());
  if (v instanceof Map) {
    const m = new Map();
    seen.set(v, m);
    for (const [k, x] of v) m.set(clone(k, seen), clone(x, seen));
    return m;
  }
  if (v instanceof Set) {
    const s = new Set();
    seen.set(v, s);
    for (const x of v) s.add(clone(x, seen));
    return s;
  }
  if (Array.isArray(v)) {
    const a: unknown[] = [];
    seen.set(v, a);
    for (let i = 0; i < v.length; i++) a.push(clone(v[i], seen));
    return a;
  }
  const o: Record<string, unknown> = {};
  seen.set(v, o);
  for (const k of Object.keys(v)) o[k] = clone((v as Record<string, unknown>)[k], seen);
  return o;
}
if (typeof g.structuredClone !== "function") g.structuredClone = (v: unknown) => clone(v, new Map());

// ── AbortController (Effect gives one to each promise it may interrupt) ──

if (typeof g.AbortController !== "function") {
  class AbortSignal {
    aborted = false;
    reason: unknown = undefined;
    onabort: ((e: unknown) => void) | null = null;
    #listeners: ((e: unknown) => void)[] = [];
    addEventListener(type: string, fn: (e: unknown) => void) {
      if (type === "abort") this.#listeners.push(fn);
    }
    removeEventListener(type: string, fn: (e: unknown) => void) {
      if (type === "abort") this.#listeners = this.#listeners.filter((l) => l !== fn);
    }
    throwIfAborted() {
      if (this.aborted) throw this.reason;
    }
    _abort(reason: unknown) {
      if (this.aborted) return;
      this.aborted = true;
      this.reason = reason ?? new Error("aborted");
      const e = { type: "abort", target: this };
      this.onabort?.(e);
      for (const l of this.#listeners) l(e);
    }
  }
  g.AbortSignal = AbortSignal;
  g.AbortController = class AbortController {
    readonly signal = new AbortSignal();
    abort(reason?: unknown) {
      this.signal._abort(reason);
    }
  };
}

// ── URL: what the core reads of one (an absolute URL's parts) ──

if (typeof g.URL !== "function") {
  g.URL = class URL {
    protocol = "";
    username = "";
    password = "";
    hostname = "";
    port = "";
    pathname = "";
    search = "";
    hash = "";
    constructor(input: string, base?: string) {
      const s = String(input);
      const m = /^([a-zA-Z][a-zA-Z0-9+.-]*:)\/\/(?:([^:@/]*)(?::([^@/]*))?@)?(\[[^\]]*\]|[^:/?#]*)(?::(\d*))?([^?#]*)(\?[^#]*)?(#.*)?$/.exec(s);
      if (!m) {
        if (base !== undefined && !/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(s)) {
          const b = new URL(base);
          const path = s.startsWith("/") ? s : b.pathname.replace(/[^/]*$/, "") + s;
          return new URL(`${b.protocol}//${b.host}${path}`);
        }
        throw new TypeError(`Invalid URL: ${s}`);
      }
      this.protocol = m[1].toLowerCase();
      this.username = m[2] ?? "";
      this.password = m[3] ?? "";
      this.hostname = m[4].toLowerCase();
      const defaults: Record<string, string> = { "http:": "80", "https:": "443", "ws:": "80", "wss:": "443" };
      this.port = m[5] === undefined || m[5] === defaults[this.protocol] ? "" : m[5];
      this.pathname = m[6] === "" ? "/" : m[6];
      this.search = m[7] === "?" ? "" : (m[7] ?? "");
      this.hash = m[8] === "#" ? "" : (m[8] ?? "");
    }
    get host() {
      return this.port === "" ? this.hostname : `${this.hostname}:${this.port}`;
    }
    get origin() {
      return `${this.protocol}//${this.host}`;
    }
    get href() {
      const auth = this.username !== "" ? `${this.username}${this.password !== "" ? `:${this.password}` : ""}@` : "";
      return `${this.protocol}//${auth}${this.host}${this.pathname}${this.search}${this.hash}`;
    }
    get searchParams() {
      const params = new Map<string, string>();
      for (const part of this.search.replace(/^\?/, "").split("&")) {
        if (part === "") continue;
        const [k, v = ""] = part.split("=");
        const d = (x: string) => decodeURIComponent(x.replace(/\+/g, " "));
        if (!params.has(d(k))) params.set(d(k), d(v));
      }
      return { get: (k: string) => params.get(k) ?? null, has: (k: string) => params.has(k) };
    }
    toString() {
      return this.href;
    }
    toJSON() {
      return this.href;
    }
  };
}

// ── clocks, randomness, the console ──

if (typeof g.performance !== "object" || typeof g.performance?.now !== "function") g.performance = { now: () => native.monotonic() };
if (typeof g.crypto !== "object" || typeof g.crypto?.getRandomValues !== "function") {
  g.crypto = {
    getRandomValues<T extends ArrayBufferView>(buf: T): T {
      const bytes = new Uint8Array(native.random(buf.byteLength));
      new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength).set(bytes);
      return buf;
    },
  };
}
if (typeof g.console !== "object") {
  const say = (level: number) => (...a: unknown[]) => native.log(level, a.map((x) => (typeof x === "string" ? x : x instanceof Error ? `${x.message}\n${x.stack ?? ""}` : JSON.stringify(x))).join(" "));
  g.console = { log: say(1), info: say(1), debug: say(0), warn: say(2), error: say(3) };
}

// ── case conversion: all but ASCII would go through Java (hermes-case.ts) ──

{
  const lower = String.prototype.toLowerCase;
  const upper = String.prototype.toUpperCase;
  const proto = String.prototype as unknown as Record<string, unknown>;
  proto.toLowerCase = function (this: unknown) { return lowerCase(String(this), (s) => lower.call(s)); };
  proto.toUpperCase = function (this: unknown) { return upperCase(String(this), (s) => upper.call(s)); };
}

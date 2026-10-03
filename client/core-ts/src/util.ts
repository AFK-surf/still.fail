// Bytes and text the core needs on every host (Node, a browser's worker, Hermes): UTF-8, base64, hex, SHA-256, and
// JSON as the Rust core reads and writes it (objects' keys in order, as serde_json without preserve_order keeps them).

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export function utf8(text: string): Uint8Array {
  return encoder.encode(text);
}

export function fromUtf8(bytes: Uint8Array): string {
  return decoder.decode(bytes);
}

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

function encode64(bytes: Uint8Array, alphabet: string, pad: boolean): string {
  let out = "";
  let i = 0;
  for (; i + 2 < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += alphabet[(n >> 18) & 63] + alphabet[(n >> 12) & 63] + alphabet[(n >> 6) & 63] + alphabet[n & 63];
  }
  const rest = bytes.length - i;
  if (rest === 1) {
    const n = bytes[i] << 16;
    out += alphabet[(n >> 18) & 63] + alphabet[(n >> 12) & 63] + (pad ? "==" : "");
  } else if (rest === 2) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += alphabet[(n >> 18) & 63] + alphabet[(n >> 12) & 63] + alphabet[(n >> 6) & 63] + (pad ? "=" : "");
  }
  return out;
}

export function base64(bytes: Uint8Array): string {
  return encode64(bytes, B64, true);
}

export function base64url(bytes: Uint8Array): string {
  return encode64(bytes, B64URL, false);
}

/// Standard base64 with its padding (the `base64` crate's STANDARD): null when it is not that.
export function fromBase64(text: string): Uint8Array | null {
  if (text.length % 4 !== 0) return null;
  const values: number[] = [];
  let pad = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === "=") {
      if (i < text.length - 2) return null;
      pad++;
      values.push(0);
      continue;
    }
    if (pad > 0) return null;
    const v = B64.indexOf(c);
    if (v < 0) return null;
    values.push(v);
  }
  const out = new Uint8Array((values.length / 4) * 3 - pad);
  let o = 0;
  for (let i = 0; i < values.length; i += 4) {
    const n = (values[i] << 18) | (values[i + 1] << 12) | (values[i + 2] << 6) | values[i + 3];
    if (o < out.length) out[o++] = (n >> 16) & 255;
    if (o < out.length) out[o++] = (n >> 8) & 255;
    if (o < out.length) out[o++] = n & 255;
  }
  // Bits left over in the last character must be zero (the crate refuses the rest).
  if (pad === 1 && (values[values.length - 2] & 3) !== 0) return null;
  if (pad === 2 && (values[values.length - 3] & 15) !== 0) return null;
  return out;
}

export function hex(bytes: Uint8Array): string {
  let out = "";
  for (const b of bytes) out += b.toString(16).padStart(2, "0");
  return out;
}

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);

export function sha256(data: Uint8Array): Uint8Array {
  const h = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
  const length = data.length;
  const padded = new Uint8Array(((length + 9 + 63) >> 6) << 6);
  padded.set(data);
  padded[length] = 0x80;
  const bits = length * 8;
  const view = new DataView(padded.buffer);
  view.setUint32(padded.length - 4, bits >>> 0);
  view.setUint32(padded.length - 8, Math.floor(bits / 2 ** 32));
  const w = new Uint32Array(64);
  for (let off = 0; off < padded.length; off += 64) {
    for (let i = 0; i < 16; i++) w[i] = view.getUint32(off + i * 4);
    for (let i = 16; i < 64; i++) {
      const s0 = ((w[i - 15] >>> 7) | (w[i - 15] << 25)) ^ ((w[i - 15] >>> 18) | (w[i - 15] << 14)) ^ (w[i - 15] >>> 3);
      const s1 = ((w[i - 2] >>> 17) | (w[i - 2] << 15)) ^ ((w[i - 2] >>> 19) | (w[i - 2] << 13)) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, hh] = h;
    for (let i = 0; i < 64; i++) {
      const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
      const ch = (e & f) ^ (~e & g);
      const t1 = (hh + S1 + ch + K[i] + w[i]) >>> 0;
      const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) >>> 0;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }
  const out = new Uint8Array(32);
  const ov = new DataView(out.buffer);
  for (let i = 0; i < 8; i++) ov.setUint32(i * 4, h[i]);
  return out;
}

/// A JSON value (serde_json::Value).
export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type JsonObject = { [key: string]: Json };

export function isObject(v: unknown): v is JsonObject {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

/// serde_json's equality: objects by their keys whatever the order, numbers by value.
export function equal(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return false;
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (!equal(a[i], b[i])) return false;
    return true;
  }
  if (Array.isArray(b)) return false;
  const ak = Object.keys(a);
  const bk = Object.keys(b);
  if (ak.length !== bk.length) return false;
  for (const k of ak) {
    if (!Object.prototype.hasOwnProperty.call(b, k)) return false;
    if (!equal((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k])) return false;
  }
  return true;
}

/// Keys sorted at every level, as serde_json (a BTreeMap) keeps them: what the Rust core writes and sends.
export function sorted(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(sorted);
  if (isObject(v)) {
    const out: Record<string, unknown> = {};
    for (const k of Object.keys(v).sort(compareKeys)) out[k] = sorted(v[k]);
    return out;
  }
  return v;
}

/// Rust's string order: by UTF-8 bytes (code points), not UTF-16 units.
export function compareKeys(a: string, b: string): number {
  if (a === b) return 0;
  const la = a.length;
  const lb = b.length;
  for (let i = 0, j = 0; i < la && j < lb; ) {
    const ca = a.codePointAt(i)!;
    const cb = b.codePointAt(j)!;
    if (ca !== cb) return ca < cb ? -1 : 1;
    i += ca > 0xffff ? 2 : 1;
    j += cb > 0xffff ? 2 : 1;
  }
  return la < lb ? -1 : la > lb ? 1 : 0;
}

/// What went out of the store as it is (output.ts): never changed after, so it is shared and not shaped again.
export const shaped = new WeakSet<object>();

/// JSON text as serde_json writes it: keys sorted.
export function toJson(v: unknown): string {
  return JSON.stringify(sorted(v));
}

export function toJsonBytes(v: unknown): Uint8Array {
  return utf8(toJson(v));
}

/// JSON from bytes; undefined when they are not JSON.
export function parseJson(bytes: Uint8Array | string | null | undefined): Json | undefined {
  if (bytes === null || bytes === undefined) return undefined;
  try {
    return JSON.parse(typeof bytes === "string" ? bytes : fromUtf8(bytes)) as Json;
  } catch {
    return undefined;
  }
}

export function clone<T>(v: T): T {
  return v === undefined ? v : (JSON.parse(JSON.stringify(v)) as T);
}

/// `value.pointer("/a/b")`.
export function pointer(v: unknown, path: string): unknown {
  let at: unknown = v;
  for (const part of path.split("/").slice(1)) {
    if (Array.isArray(at)) at = at[Number(part)];
    else if (isObject(at)) at = at[part];
    else return undefined;
  }
  return at;
}

/// `Value::as_str`, `as_u64`, … : the value when it is of that kind.
export function str(v: unknown): string | undefined {
  return typeof v === "string" ? v : undefined;
}
export function u64(v: unknown): number | undefined {
  return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : undefined;
}
export function i64(v: unknown): number | undefined {
  return typeof v === "number" && Number.isInteger(v) ? v : undefined;
}
export function f64(v: unknown): number | undefined {
  return typeof v === "number" ? v : undefined;
}
export function bool(v: unknown): boolean | undefined {
  return typeof v === "boolean" ? v : undefined;
}
export function arr(v: unknown): unknown[] | undefined {
  return Array.isArray(v) ? v : undefined;
}
export function obj(v: unknown): Record<string, unknown> | undefined {
  return isObject(v) ? (v as Record<string, unknown>) : undefined;
}
/// `v.get(k)` on an object (undefined otherwise).
export function get(v: unknown, k: string | number): unknown {
  if (typeof k === "number") return Array.isArray(v) ? v[k] : undefined;
  return isObject(v) ? v[k] : undefined;
}

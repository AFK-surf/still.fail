// The frames of Feishu's long connection (docs/feishu.md): protobuf's `pbbp2.Frame`, as Feishu's SDKs encode it, by
// hand (its five fields are all the station needs, and its SDK would bring a second HTTP stack and its own reconnects).
//
//   message Header { string key = 1; string value = 2; }
//   message Frame { uint64 SeqID = 1; uint64 LogID = 2; int32 service = 3; int32 method = 4; repeated Header headers = 5;
//                   string payload_encoding = 6; string payload_type = 7; bytes payload = 8; string LogIDNew = 9; }

/// method: a control frame (ping, pong) or a data frame (an event, a callback).
export const CONTROL = 0;
export const DATA = 1;

export type Frame = {
  seqId: bigint;
  logId: bigint;
  service: number;
  method: number;
  headers: [string, string][];
  payloadEncoding?: string;
  payloadType?: string;
  payload?: Uint8Array;
  logIdNew?: string;
};

/// A header's value, or undefined.
export const header = (f: Frame, key: string): string | undefined => f.headers.find(([k]) => k === key)?.[1];

const utf8 = new TextEncoder();
const fromUtf8 = new TextDecoder();

class Writer {
  private parts: number[] = [];
  varint(v: bigint) {
    let n = BigInt.asUintN(64, v);
    while (n >= 0x80n) {
      this.parts.push(Number(n & 0x7fn) | 0x80);
      n >>= 7n;
    }
    this.parts.push(Number(n));
  }
  tag(field: number, wire: number) {
    this.varint(BigInt((field << 3) | wire));
  }
  bytes(field: number, b: Uint8Array) {
    this.tag(field, 2);
    this.varint(BigInt(b.length));
    for (const x of b) this.parts.push(x);
  }
  done(): Uint8Array {
    return Uint8Array.from(this.parts);
  }
}

function headerBytes(key: string, value: string): Uint8Array {
  const w = new Writer();
  w.bytes(1, utf8.encode(key));
  w.bytes(2, utf8.encode(value));
  return w.done();
}

export function encode(f: Frame): Uint8Array {
  const w = new Writer();
  w.tag(1, 0);
  w.varint(f.seqId);
  w.tag(2, 0);
  w.varint(f.logId);
  w.tag(3, 0);
  // int32: negative ones as ten bytes, as protobuf does.
  w.varint(BigInt(f.service));
  w.tag(4, 0);
  w.varint(BigInt(f.method));
  for (const [k, v] of f.headers) w.bytes(5, headerBytes(k, v));
  if (f.payloadEncoding !== undefined) w.bytes(6, utf8.encode(f.payloadEncoding));
  if (f.payloadType !== undefined) w.bytes(7, utf8.encode(f.payloadType));
  if (f.payload !== undefined) w.bytes(8, f.payload);
  if (f.logIdNew !== undefined) w.bytes(9, utf8.encode(f.logIdNew));
  return w.done();
}

class Reader {
  at = 0;
  readonly b: Uint8Array;
  constructor(b: Uint8Array) {
    this.b = b;
  }
  get more() {
    return this.at < this.b.length;
  }
  varint(): bigint {
    let shift = 0n;
    let v = 0n;
    for (;;) {
      if (this.at >= this.b.length) throw new Error("frame: cut short");
      const x = this.b[this.at++]!;
      v |= BigInt(x & 0x7f) << shift;
      if ((x & 0x80) === 0) return v;
      shift += 7n;
      if (shift > 70n) throw new Error("frame: varint too long");
    }
  }
  chunk(): Uint8Array {
    const n = Number(this.varint());
    if (this.at + n > this.b.length) throw new Error("frame: cut short");
    const out = this.b.subarray(this.at, this.at + n);
    this.at += n;
    return out;
  }
  skip(wire: number) {
    if (wire === 0) this.varint();
    else if (wire === 2) this.chunk();
    else if (wire === 1) this.at += 8;
    else if (wire === 5) this.at += 4;
    else throw new Error(`frame: wire type ${wire}`);
  }
}

const int32 = (v: bigint) => Number(BigInt.asIntN(32, v));

export function decode(bytes: Uint8Array): Frame {
  const r = new Reader(bytes);
  const f: Frame = { seqId: 0n, logId: 0n, service: 0, method: 0, headers: [] };
  while (r.more) {
    const tag = Number(r.varint());
    const [field, wire] = [tag >> 3, tag & 7];
    if (field === 1 && wire === 0) f.seqId = r.varint();
    else if (field === 2 && wire === 0) f.logId = r.varint();
    else if (field === 3 && wire === 0) f.service = int32(r.varint());
    else if (field === 4 && wire === 0) f.method = int32(r.varint());
    else if (field === 5 && wire === 2) {
      const h = new Reader(r.chunk());
      let [key, value] = ["", ""];
      while (h.more) {
        const t = Number(h.varint());
        if (t >> 3 === 1 && (t & 7) === 2) key = fromUtf8.decode(h.chunk());
        else if (t >> 3 === 2 && (t & 7) === 2) value = fromUtf8.decode(h.chunk());
        else h.skip(t & 7);
      }
      f.headers.push([key, value]);
    } else if (field === 6 && wire === 2) f.payloadEncoding = fromUtf8.decode(r.chunk());
    else if (field === 7 && wire === 2) f.payloadType = fromUtf8.decode(r.chunk());
    else if (field === 8 && wire === 2) f.payload = r.chunk().slice();
    else if (field === 9 && wire === 2) f.logIdNew = fromUtf8.decode(r.chunk());
    else r.skip(wire);
  }
  return f;
}

/// Data frames too big for one come in parts (`sum` of them, numbered by `seq`, under one `message_id`): put together
/// once all are in. Parts of one never finished are dropped after a while (`drop`).
export class Parts {
  private open = new Map<string, { parts: (Uint8Array | undefined)[]; at: number }>();
  add(f: Frame, now: number): Uint8Array | null {
    const sum = Number(header(f, "sum") ?? "1");
    const payload = f.payload ?? new Uint8Array();
    if (!(sum > 1)) return payload;
    const id = header(f, "message_id") ?? "";
    const seq = Number(header(f, "seq") ?? "0");
    let entry = this.open.get(id);
    if (!entry) this.open.set(id, (entry = { parts: Array(sum).fill(undefined), at: now }));
    if (seq >= 0 && seq < entry.parts.length) entry.parts[seq] = payload;
    if (entry.parts.some((p) => p === undefined)) return null;
    this.open.delete(id);
    const total = entry.parts.reduce((n, p) => n + p!.length, 0);
    const out = new Uint8Array(total);
    let at = 0;
    for (const p of entry.parts) {
      out.set(p!, at);
      at += p!.length;
    }
    return out;
  }
  drop(before: number) {
    for (const [id, e] of this.open) if (e.at < before) this.open.delete(id);
  }
}

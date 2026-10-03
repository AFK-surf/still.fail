// How requests reach a station, and a preview socket's framing (station/wire.rs). The mesh wire (mesh links) is in
// mesh.ts; tests' stations answer over the host's fetch (testing.ts `HostWire`).
import { CoreError } from "../error.ts";
import { Effect } from "effect";
import type { Pull } from "../host.ts";
import { t } from "../i18n.ts";
import type { StationAddr } from "./addr.ts";

/// A request's head as it goes to a station: `path` includes `/admin/api`.
export type RequestHead = { method: string; path: string; headers: [string, string][] };

/// A station's answer: status, headers, and the body as it arrives; how it came (`relay`, `direct`), when known.
export type WireReply = { status: number; headers: [string, string][]; body: Pull<Uint8Array>; via: string | null };

export function replyHeader(reply: { headers: [string, string][] }, name: string): string | undefined {
  return reply.headers.find(([k]) => k.toLowerCase() === name.toLowerCase())?.[1];
}

/// The whole body.
export function replyBytes(reply: WireReply) {
  return Effect.gen(function* () {
    const parts: Uint8Array[] = [];
    for (;;) {
      const chunk = yield* reply.body.take;
      if (chunk === null) break;
      parts.push(chunk);
    }
    return concat(parts);
  });
}

export function concat(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

/// How a link to a station runs (mesh.ts `Link.net`).
export type LinkNet = {
  path: string | null;
  relay: string | null;
  rttMs: number | null;
  measured: { measuring: boolean; relays: [string, number | null][]; moved: string | null } | null;
  today: [number, number] | null;
  rxBytes: number;
  txBytes: number;
  txPackets: number;
  lostPackets: number;
};

/// The client's half of a socket stream.
export interface SocketOut {
  write(bytes: Uint8Array): Promise<void>;
  finish(): void;
  /// Let go: the stream is reset.
  reset(): void;
}

/// A socket stream as it opened: the station's reply (101 once the service took it), and where the client's frames go.
export type WireSocket = { reply: WireReply; send: SocketOut };

/// How requests reach a station. A request for an event stream carries `accept: text/event-stream`.
export interface StationWire {
  request(station: StationAddr, head: RequestHead, body: Uint8Array): Promise<WireReply>;
  /// The way to the station is taken for gone: what is open to it closes.
  reset?(station: StationAddr): void;
  /// Whether the wire itself finds another way to a station when the UI comes back.
  races?(): boolean;
  /// Resolves once the way to the station a request would take now is replaced by another; never for a wire that
  /// does not race. `cancel` lets go of the wait.
  replaced?(station: StationAddr): { done: Promise<void>; cancel(): void };
  /// How the connection to the station runs now; null where there is none of its own.
  net?(station: StationAddr): LinkNet | null;
  /// Measures the ways to the station now.
  measure?(station: StationAddr): Promise<void>;
  /// A preview page's WebSocket. Only the mesh carries one.
  socket?(station: StationAddr, head: RequestHead): Promise<WireSocket>;
}

export function noMeasure(): Promise<void> {
  return Promise.reject(new CoreError("unsupported", t("station.core.oneWay")));
}

export function noSocket(): Promise<WireSocket> {
  return Promise.reject(new CoreError("unsupported", t("station.core.previewNoSocket")));
}

/// A WebSocket message on a socket stream (mesh/app/src/preview.rs): a kind byte (1 text, 2 binary, 8 close), the
/// payload's length (4 bytes, big-endian), the payload; a close's is its code (2 bytes) and reason.
export type Frame = { text: string } | { binary: Uint8Array } | { close: [number, string] };

export function encodeFrame(frame: Frame): Uint8Array {
  let kind: number;
  let payload: Uint8Array;
  if ("text" in frame) {
    kind = 1;
    payload = new TextEncoder().encode(frame.text);
  } else if ("binary" in frame) {
    kind = 2;
    payload = frame.binary;
  } else {
    kind = 8;
    const reason = new TextEncoder().encode(frame.close[1]);
    payload = new Uint8Array(2 + reason.length);
    payload[0] = (frame.close[0] >> 8) & 255;
    payload[1] = frame.close[0] & 255;
    payload.set(reason, 2);
  }
  const out = new Uint8Array(5 + payload.length);
  out[0] = kind;
  new DataView(out.buffer).setUint32(1, payload.length);
  out.set(payload, 5);
  return out;
}

/// The frames whole in `buf`, and what is left (the start of the next).
export function takeFrames(buf: Uint8Array): [Frame[], Uint8Array] {
  const frames: Frame[] = [];
  let at = 0;
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const decoder = new TextDecoder();
  while (buf.length - at >= 5) {
    const len = view.getUint32(at + 1);
    if (buf.length - at - 5 < len) break;
    const payload = buf.subarray(at + 5, at + 5 + len);
    switch (buf[at]) {
      case 1:
        frames.push({ text: decoder.decode(payload) });
        break;
      case 2:
        frames.push({ binary: payload.slice() });
        break;
      case 8: {
        const code = payload.length >= 2 ? (payload[0] << 8) | payload[1] : 1005;
        frames.push({ close: [code, decoder.decode(payload.subarray(Math.min(2, payload.length)))] });
        break;
      }
    }
    at += 5 + len;
  }
  return [frames, buf.slice(at)];
}

/// Whichever of two attempts answers; one that fails leaves it to the other.
export function firstAnswer<T>(a: Promise<T>, b: Promise<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    let failed = 0;
    const fail = (e: unknown) => {
      if (++failed === 2) reject(e);
    };
    a.then(resolve, fail);
    b.then(resolve, fail);
  });
}

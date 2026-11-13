// The framing of a mesh protocol's streams, and nothing of what they carry: one JSON line at a time off a stream, then
// the rest of it; a request, a JSON head line then its body until the stream finishes; its answer, a JSON head line
// `{status, headers}` then the body. Who may open a stream and what a request is answered are not here (door.ts is
// given them; the station's own are mesh/serve.ts's): scripts/mesh-base.ts keeps this file from importing them.
import { wall } from "../ops/fibers.ts";
import type { Stream } from "./endpoint.ts";

export const MAX_HEAD = 16 * 1024;
// Files sent to a session go through here: in parts of 16 MB at most, or whole up to 50 MB (clients before parts).
export const MAX_BODY = 64 * 1024 * 1024;
/// Headers of one hop, not of what is relayed.
export const HOP = ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "host", "content-length"];

/// What a request is answered.
export type Answer = {
  status: number;
  headers: Record<string, string>;
  /// Whole, or as it comes (an event stream).
  body: Buffer | AsyncIterable<Buffer>;
};

/// One JSON line at a time from a stream, then the rest of it.
export class Reader {
  carry: Buffer = Buffer.alloc(0);
  stream: Stream;
  /// How long a line may be: the admin API's heads are small; the device tools' carry their bodies in it.
  private maxLine: number;
  constructor(stream: Stream, maxLine = MAX_HEAD) {
    this.stream = stream;
    this.maxLine = maxLine;
  }

  async line(): Promise<any | null> {
    // A long line (the device tools') comes in many pieces: kept as they come, each looked through once.
    let at = this.carry.indexOf(10);
    if (at < 0) {
      const parts = [this.carry];
      let size = this.carry.length;
      while (at < 0) {
        if (size > this.maxLine) throw new Error("head too large");
        const more = await this.stream.read();
        if (more === null) {
          if (size === 0) return null;
          throw new Error("stream ended mid-line");
        }
        const found = more.indexOf(10);
        if (found >= 0) at = size + found;
        parts.push(more);
        size += more.length;
      }
      this.carry = Buffer.concat(parts, size);
    }
    if (at > this.maxLine) throw new Error("head too large");
    const line = this.carry.subarray(0, at);
    this.carry = this.carry.subarray(at + 1);
    return JSON.parse(line.toString());
  }

  async rest(): Promise<Buffer> {
    const parts = [this.carry];
    let size = this.carry.length;
    for (let more = await this.stream.read(); more; more = await this.stream.read()) {
      parts.push(more);
      size += more.length;
      if (size > MAX_BODY) throw new Error("request body too large");
    }
    return Buffer.concat(parts);
  }

  /// The rest as it comes, however long (a request passed on as it is: a module's).
  async *chunks(): AsyncGenerator<Buffer> {
    if (this.carry.length > 0) {
      const first = this.carry;
      this.carry = Buffer.alloc(0);
      yield first;
    }
    for (let more = await this.stream.read(); more; more = await this.stream.read()) yield more;
  }
}

export const writeLine = (stream: Stream, value: unknown) => stream.write(Buffer.from(JSON.stringify(value) + "\n"));

/// One request as its stream was taken: its head line, the reader that read it (what came with the line still in its
/// `carry`), the stream, and when the stream was accepted (the machine's time, and the process's own clock at it).
export type Asked = { head: any; reader: Reader; stream: Stream; accepted: { wall: number; at: bigint } };

/// One request stream's head read, and `answer` called with it in that same turn (what answers it starts then, and
/// sees to its own failing: nothing here waits for it). A stream that ends with nothing asked is finished.
export async function request(raw: Stream, answer: (asked: Asked) => void) {
  const accepted = { wall: wall.now(), at: process.hrtime.bigint() };
  const reader = new Reader(raw);
  const head = await reader.line();
  if (head === null) {
    await raw.finish().catch(() => {});
    return;
  }
  answer({ head, reader, stream: raw, accepted });
}

/// An answer onto its stream: its head line, then its body. A body that is a stream (GET /events) ends when the caller
/// stops reading or goes, even while nothing is being written to it, and is let go of however the writing ends: one
/// whose head could not be written (the caller gone while its answer was being made) stayed a follower of the events
/// for good, told everything into a queue nobody read. A whole body says its length, unless compressed (compress.ts: a
/// client counts what it has read once decompressed): a chat's picture shows how far it has come by it
/// (pengxiao, 2026-10-28: without it, one under the core's step for an unknown length showed 0 B until it was here).
export async function send(stream: Stream, response: Answer) {
  const head = { status: response.status, headers: response.headers };
  if (Buffer.isBuffer(response.body)) {
    const said = Object.keys(response.headers).some((k) => ["content-length", "content-encoding"].includes(k.toLowerCase()));
    if (!said) head.headers = { ...response.headers, "content-length": String(response.body.length) };
    await writeLine(stream, head);
    await stream.write(response.body);
    return;
  }
  const chunks = response.body[Symbol.asyncIterator]();
  const end = () => void chunks.return?.();
  stream.stopped().then(end, end);
  try {
    await writeLine(stream, head);
    for (;;) {
      const next = await chunks.next();
      if (next.done) break;
      await stream.write(next.value);
    }
  } finally {
    end();
  }
}

// Files over the station transport (mesh/peer.ts): a file goes in one request or one answer, its bytes after the head
// as they are read, at the pace the other end takes them. Before 2026-10-29 the transport carried JSON only, and a file
// went as base64 in chunks of 256 KiB, a round trip each (CHUNK, jobs/remote.ts): stations from before still answer and
// are sent so.
import { constants } from "node:fs";
import { type FileHandle, open } from "node:fs/promises";
import type { Bytes } from "./bus.ts";

/// How much of a file is read at once as it is sent.
const PIECE = 1024 * 1024;

/// The bytes of the file at `path` from `offset` up to `end`, read as they are sent: it is opened when the first are
/// wanted (never, when nothing takes them) and closed after the last or when sending stops. A file that ends before
/// `end` (changed meanwhile) fails them.
export async function* fileBytes(path: string, offset: number, end: number): Bytes {
  if (offset >= end) return;
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    for (let at = offset; at < end; ) {
      const piece = Buffer.allocUnsafe(Math.min(PIECE, end - at));
      const { bytesRead } = await file.read(piece, 0, piece.length, at);
      if (bytesRead === 0) throw new Error("the file got shorter while it was sent");
      at += bytesRead;
      yield piece.subarray(0, bytesRead);
    }
  } finally {
    await file.close();
  }
}

/// `bytes` in one piece: what a request or answer carries that is already in memory.
export async function* oneBytes(bytes: Buffer): Bytes {
  if (bytes.length > 0) yield bytes;
}

/// `bytes` written into `file` from `offset`, all of them; how many. More than `limit` from where the file begins fails.
export async function writeBytes(file: FileHandle, bytes: Bytes, offset: number, limit: number): Promise<number> {
  let at = offset;
  for await (const piece of bytes) {
    if (at + piece.length > limit) throw new Error("more came than the file can be");
    for (let done = 0; done < piece.length; ) done += (await file.write(piece, done, piece.length - done, at + done)).bytesWritten;
    at += piece.length;
  }
  return at - offset;
}

/// `bytes` in memory, all of them; more than `limit` fails.
export async function readBytes(bytes: Bytes, limit: number): Promise<Buffer> {
  const parts: Buffer[] = [];
  let size = 0;
  for await (const piece of bytes) {
    size += piece.length;
    if (size > limit) throw new Error("more came than was asked for");
    parts.push(piece);
  }
  return Buffer.concat(parts, size);
}

/// `bytes` not wanted after all: their sending stopped (an answer's: its stream reset), none read.
export async function stopBytes(bytes: Bytes): Promise<void> {
  await bytes[Symbol.asyncIterator]().return?.();
}

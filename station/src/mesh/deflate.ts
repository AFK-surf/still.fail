// Answers deflated for a client that asks so (`accept-encoding: deflate-raw`, client/core-ts/src/station/requests.ts):
// on a slow link the bytes are the wait, and JSON goes to a fifth or less. Raw deflate; an event stream is flushed after
// each event, so every one comes out whole as it arrives, and is deflated against those before it (an event like the
// last is a few bytes). JSON and text only (pictures and archives are as small as they get), and nothing of a preview: its
// page reads it as the service sent it. A client from before asks nothing, and gets every answer as it was.
import { constants, createDeflateRaw, deflateRaw } from "node:zlib";
import { promisify } from "node:util";
import type { Answer } from "../api/request.ts";

export const DEFLATE = "deflate-raw";
/// A whole answer smaller than this goes as it is: deflated it would hardly be smaller.
const SMALL = 512;
const deflateWhole = promisify(deflateRaw);

const header = (headers: Record<string, string>, name: string) => Object.entries(headers).find(([k]) => k.toLowerCase() === name)?.[1];

/// `answer` as it goes to a client that asked with `headers` for `path` (after /admin/api): deflated where it can be.
export async function deflated(answer: Answer, headers: Record<string, string>, path: string): Promise<Answer> {
  const asked = (header(headers, "accept-encoding") ?? "").split(",").some((e) => e.trim() === DEFLATE);
  if (!asked || path.startsWith("/preview/") || header(answer.headers, "content-encoding") !== undefined) return answer;
  if (!/^(application\/json|text\/)/.test(header(answer.headers, "content-type") ?? "")) return answer;
  // A length said was of what it says, not of what is sent (a file's progress would go by it): none is said.
  const sent = Object.fromEntries(Object.entries(answer.headers).filter(([k]) => k.toLowerCase() !== "content-length"));
  sent["content-encoding"] = DEFLATE;
  if (Buffer.isBuffer(answer.body)) {
    if (answer.body.length < SMALL) return answer;
    return { ...answer, headers: sent, body: await deflateWhole(answer.body) };
  }
  return { ...answer, headers: sent, body: deflatedStream(answer.body) };
}

/// A stream's chunks deflated, each flushed as it goes. Ends as the stream does; let go of (`return`), it lets go of the
/// stream at once (written by hand: an async generator's would wait for the stream's next chunk).
function deflatedStream(body: AsyncIterable<Buffer>): AsyncIterableIterator<Buffer> {
  const source = body[Symbol.asyncIterator]();
  const z = createDeflateRaw({ flush: constants.Z_SYNC_FLUSH });
  // What it gives as it is written (flowing: a big chunk's output is never held back for want of a reader).
  const out: Buffer[] = [];
  z.on("data", (part: Buffer) => out.push(part));
  const deflate = (chunk: Buffer) => new Promise<Buffer>((resolve, reject) => z.write(chunk, (error) => (error ? reject(error) : resolve(Buffer.concat(out.splice(0))))));
  const it: AsyncIterableIterator<Buffer> = {
    [Symbol.asyncIterator]: () => it,
    next: async () => {
      const next = await source.next();
      if (next.done) {
        z.close();
        return { done: true, value: undefined };
      }
      return { done: false, value: await deflate(next.value) };
    },
    return: async () => {
      z.close();
      await source.return?.();
      return { done: true, value: undefined };
    },
  };
  return it;
}

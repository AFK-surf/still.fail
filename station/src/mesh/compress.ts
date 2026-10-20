// Answers compressed for a client that asks so (`accept-encoding: zstd`, client/core-ts/src/station/requests.ts): on a
// slow link the bytes are the wait, and JSON goes to a fifth or less. zstd: a whole answer as small as deflate makes it,
// an event stream far smaller, as each event is compressed against the last megabyte of the stream (what a stream
// tells again, a session's summary, a sidebar row, the overview, is a few bytes the next time; deflate looks back 32 KB
// only, and on a station that is busy the last time is further back than that): of a real station's stream, 7% of it
// rather than 24%. The stream is flushed after each event, so every one comes out whole as it arrives. JSON and text
// only (pictures and archives are as small as they get), and nothing of a preview: its page reads it as the service
// sent it. A client from before asks nothing, and gets every answer as it was.
import { constants, createZstdCompress, zstdCompress } from "node:zlib";
import { promisify } from "node:util";
import type { Answer } from "../api/request.ts";

export const ZSTD = "zstd";
/// A whole answer smaller than this goes as it is: compressed it would hardly be smaller.
const SMALL = 512;
/// zstd's fast level, and how far back a stream's events are compressed against (2^20: a megabyte; each end holds that
/// much for each stream).
const LEVEL = 3;
const WINDOW_LOG = 20;
const params = { [constants.ZSTD_c_compressionLevel]: LEVEL, [constants.ZSTD_c_windowLog]: WINDOW_LOG };
/// Several reads in one (POST /batch, the history a client brings in the background: nobody waits on it) compressed
/// harder. Of a new device's chats on the main station, 8% less than at LEVEL for some 7 ms a batch; level 19 would take
/// 18% off, at some 100 ms a batch of the threads every answer is compressed on.
const BATCH_LEVEL = 9;
const batchParams = { ...params, [constants.ZSTD_c_compressionLevel]: BATCH_LEVEL };
const compressWhole = promisify(zstdCompress);

const header = (headers: Record<string, string>, name: string) => Object.entries(headers).find(([k]) => k.toLowerCase() === name)?.[1];

/// `answer` as it goes to a client that asked with `headers` for `path` (after /admin/api): compressed where it can be.
export async function compressed(answer: Answer, headers: Record<string, string>, path: string): Promise<Answer> {
  const asked = (header(headers, "accept-encoding") ?? "").split(",").some((e) => e.trim() === ZSTD);
  if (!asked || path.startsWith("/preview/") || header(answer.headers, "content-encoding") !== undefined) return answer;
  if (!/^(application\/json|text\/)/.test(header(answer.headers, "content-type") ?? "")) return answer;
  // A length said was of what it says, not of what is sent (a file's progress would go by it): none is said.
  const sent = Object.fromEntries(Object.entries(answer.headers).filter(([k]) => k.toLowerCase() !== "content-length"));
  sent["content-encoding"] = ZSTD;
  if (Buffer.isBuffer(answer.body)) {
    if (answer.body.length < SMALL) return answer;
    return { ...answer, headers: sent, body: await compressWhole(answer.body, { params: path.split("?")[0] === "/batch" ? batchParams : params }) };
  }
  return { ...answer, headers: sent, body: compressedStream(answer.body) };
}

/// A stream's chunks compressed, each flushed as it goes. Ends as the stream does; let go of (`return`), it lets go of the
/// stream at once (written by hand: an async generator's would wait for the stream's next chunk).
function compressedStream(body: AsyncIterable<Buffer>): AsyncIterableIterator<Buffer> {
  const source = body[Symbol.asyncIterator]();
  const z = createZstdCompress({ params });
  // What it gives as it is written and flushed (flowing: a big chunk's output is never held back for want of a reader).
  const out: Buffer[] = [];
  z.on("data", (part: Buffer) => out.push(part));
  const compress = (chunk: Buffer) =>
    new Promise<Buffer>((resolve, reject) => {
      z.write(chunk, (error) => {
        if (error) reject(error);
      });
      z.flush(constants.ZSTD_e_flush, () => resolve(Buffer.concat(out.splice(0))));
    });
  const it: AsyncIterableIterator<Buffer> = {
    [Symbol.asyncIterator]: () => it,
    next: async () => {
      const next = await source.next();
      if (next.done) {
        z.close();
        return { done: true, value: undefined };
      }
      return { done: false, value: await compress(next.value) };
    },
    return: async () => {
      z.close();
      await source.return?.();
      return { done: true, value: undefined };
    },
  };
  return it;
}

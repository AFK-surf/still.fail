// The releases bucket (RELEASES, R2 on Cloudflare) of a self-hosted cloud: a directory on disk (FILES), bound to the API
// as the part of R2Bucket it uses (src/releases.ts ReleaseBucket, src/icons.ts IconBucket): head, get with a range, put.
// What the operator serves (station releases, the apps' feeds, changelog.json) is put in that directory as files under
// the keys scripts/release.sh would put them at; icons the API puts land beside them.
import { WorkerEntrypoint } from "cloudflare:workers";

export type ReleasesEnv = { FILES: Fetcher };

/** A key as the bucket's: segments of letters, digits and ._-, none a dot's alone. */
export const validKey = (key: string) => /^[A-Za-z0-9._-]+(\/[A-Za-z0-9._-]+)*$/.test(key) && !key.split("/").some((s) => /^\.+$/.test(s) || s.startsWith("."));

/** An object's etag: of its size and when it was written (what the disk says of it), quoted as R2's httpEtag is. */
const etagOf = (answer: Response) => `"${Number(answer.headers.get("content-length") ?? 0).toString(16)}-${Date.parse(answer.headers.get("last-modified") ?? "") || 0}"`;

export class Releases extends WorkerEntrypoint<ReleasesEnv> {
  async #ask(key: string, method: "GET" | "HEAD"): Promise<Response | null> {
    if (!validKey(key)) return null;
    const answer = await this.env.FILES.fetch(new Request(`http://files/${key}`, { method }));
    if (!answer.ok || (answer.headers.get("content-type")?.startsWith("application/json") && !key.endsWith(".json"))) {
      await answer.body?.cancel();
      return null;
    }
    return answer;
  }

  async head(key: string): Promise<{ size: number; httpEtag: string } | null> {
    const answer = await this.#ask(key, "HEAD");
    return answer ? { size: Number(answer.headers.get("content-length") ?? 0), httpEtag: etagOf(answer) } : null;
  }

  async get(key: string, options?: { range?: { offset: number; length: number } }): Promise<{ body: ReadableStream<Uint8Array>; size: number; httpEtag: string } | null> {
    const answer = await this.#ask(key, "GET");
    if (!answer?.body) return null;
    const size = Number(answer.headers.get("content-length") ?? 0), httpEtag = etagOf(answer);
    const range = options?.range;
    if (!range) return { body: answer.body, size, httpEtag };
    // (the disk takes no ranges: the bytes before the range are read past, those after not read)
    const start = Math.min(range.offset, size), end = Math.min(start + range.length, size);
    let at = 0;
    const cut = new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, out) {
        const from = Math.max(start - at, 0), to = Math.min(end - at, chunk.length);
        if (from < to) out.enqueue(chunk.subarray(from, to));
        at += chunk.length;
        if (at >= end) out.terminate();
      },
    });
    return { body: answer.body.pipeThrough(cut), size: end - start, httpEtag };
  }

  async put(key: string, value: Uint8Array | ArrayBuffer | string): Promise<{ key: string } | null> {
    if (!validKey(key)) throw new Error("invalid_key");
    const answer = await this.env.FILES.fetch(new Request(`http://files/${key}`, { method: "PUT", body: value }));
    if (!answer.ok) throw new Error(`put ${key}: ${answer.status}`);
    return { key };
  }
}

export default { fetch: () => new Response("Not found", { status: 404 }) } satisfies ExportedHandler<ReleasesEnv>;

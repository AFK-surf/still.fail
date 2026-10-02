// Offline operator tool, run on loopback with Wrangler's remote R2 bindings. Never deployed as a public Worker.
import { createHash } from "node:crypto";
interface Env { SOURCE: R2Bucket; TARGET: R2Bucket; MIGRATION_TOKEN: string }
async function digest(body: ReadableStream<Uint8Array>): Promise<string> {
  const hash = createHash("sha256");
  for await (const bytes of body) hash.update(bytes);
  return hash.digest("hex");
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try { return await migrate(request, env); }
    catch (error) { return Response.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 }); }
  },
};
async function migrate(request: Request, env: Env): Promise<Response> {
    if (!env.MIGRATION_TOKEN || request.headers.get("authorization") !== `Bearer ${env.MIGRATION_TOKEN}`) return new Response("unauthorized", { status: 401 });
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/list") {
      const list = await env.SOURCE.list({ limit: 100, cursor: url.searchParams.get("cursor") ?? undefined });
      return Response.json({ objects: list.objects.map(({ key, etag, size }) => ({ key, etag, size })), cursor: list.truncated ? list.cursor : null });
    }
    if (request.method !== "POST" || url.pathname !== "/copy") return new Response("not found", { status: 404 });
    const input = await request.json() as { key: string; etag: string; verifyOnly?: boolean; reconcile?: boolean; resume?: { sourceEtag: string; targetEtag: string; sha256: string } };
    if (typeof input.key !== "string" || typeof input.etag !== "string") return new Response("invalid input", { status: 400 });
    const source = await env.SOURCE.get(input.key, { onlyIf: { etagMatches: input.etag } });
    if (!source || !("body" in source)) return Response.json({ error: "source_changed", etag: (await env.SOURCE.head(input.key))?.etag ?? null }, { status: 409 });
    const before = await env.TARGET.head(input.key);
    if (!input.verifyOnly && input.resume?.sourceEtag === source.etag && input.resume?.targetEtag === before?.etag && before?.size === source.size) {
      await source.body.cancel();
      return Response.json({ key: input.key, sourceEtag: source.etag, targetEtag: before.etag, size: source.size, sha256: input.resume.sha256 });
    }
    // After cutover, target writes/deletions win. Only replace the exact object
    // verified before cutover, or insert a previously unseen key if still absent.
    if (input.reconcile && (input.resume ? before?.etag !== input.resume.targetEtag : !!before)) {
      await source.body.cancel();
      return Response.json({ key: input.key, size: source.size, preservedTarget: true });
    }
    let sourceHash: string;
    if (input.verifyOnly) sourceHash = await digest(source.body);
    else {
      const hash = createHash("sha256");
      const copied = await env.TARGET.put(input.key, source.body.pipeThrough(new TransformStream<Uint8Array, Uint8Array>({
        transform(bytes, controller) { hash.update(bytes); controller.enqueue(bytes); },
      })).pipeThrough(new FixedLengthStream(source.size)), {
        httpMetadata: source.httpMetadata, customMetadata: source.customMetadata,
        onlyIf: before ? { etagMatches: before.etag } : { etagDoesNotMatch: "*" },
      });
      if (!copied) return new Response("target changed concurrently", { status: 409 });
      sourceHash = hash.digest("hex");
    }
    const target = await env.TARGET.get(input.key);
    if (!target) return new Response("target missing", { status: 409 });
    const targetHash = await digest(target.body);
    const sameMetadata = (a: unknown, b: unknown) => JSON.stringify(Object.entries((a ?? {}) as object).sort()) === JSON.stringify(Object.entries((b ?? {}) as object).sort());
    if (targetHash !== sourceHash || target.size !== source.size || !sameMetadata(target.httpMetadata, source.httpMetadata) || !sameMetadata(target.customMetadata, source.customMetadata)) {
      return new Response("copy verification failed", { status: 409 });
    }
    const latest = await env.SOURCE.head(input.key);
    if (latest?.etag !== input.etag) return Response.json({ error: "source_changed", etag: latest?.etag ?? null }, { status: 409 });
    return Response.json({ key: input.key, sourceEtag: input.etag, targetEtag: target.etag, size: source.size, sha256: sourceHash });
}

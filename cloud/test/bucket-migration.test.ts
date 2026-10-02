import assert from "node:assert/strict";
import test from "node:test";
import { build } from "esbuild";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";

test("bucket migration verifies bytes and metadata, detects source changes, and keeps the source", async () => {
  const script = (await build({ entryPoints: ["migrations/release-bucket.ts"], bundle: true, write: false, format: "esm", platform: "node", external: ["node:*"] })).outputFiles[0].text;
  const mf = new Miniflare(convertV4MiniflareOptions({ modules: true, script, compatibilityDate: "2026-09-08", compatibilityFlags: ["nodejs_compat"], r2Buckets: ["SOURCE", "TARGET"], bindings: { MIGRATION_TOKEN: "test-only" } }));
  try {
    const source = await mf.getR2Bucket("SOURCE") as unknown as R2Bucket, target = await mf.getR2Bucket("TARGET") as unknown as R2Bucket;
    const object = await source.put("private/report.bin", new Uint8Array([0, 255, 3]), { httpMetadata: { contentType: "application/octet-stream", cacheControl: "private" }, customMetadata: { owner: "test" } });
    assert.ok(object);
    const call = (body: unknown) => mf.dispatchFetch("http://localhost/copy", { method: "POST", headers: { authorization: "Bearer test-only", "content-type": "application/json" }, body: JSON.stringify(body) });
    assert.equal((await mf.dispatchFetch("http://localhost/list")).status, 401);
    const listed = await mf.dispatchFetch("http://localhost/list", { headers: { authorization: "Bearer test-only" } });
    assert.equal((await listed.json() as any).objects.length, 1);
    const copy = await call({ key: object.key, etag: object.etag });
    assert.equal(copy.status, 200, await copy.clone().text());
    const proof = await copy.json() as any;
    assert.equal(proof.sha256.length, 64);
    assert.equal((await call({ key: object.key, etag: object.etag, resume: proof })).status, 200);
    await target.put(object.key, 'interrupted or changed target');
    assert.equal((await call({ key: object.key, etag: object.etag, resume: proof })).status, 200, 'changed target must be copied and verified again');
    assert.deepEqual(new Uint8Array(await (await target.get(object.key))!.arrayBuffer()), new Uint8Array([0, 255, 3]));
    assert.equal((await target.head(object.key))!.customMetadata!.owner, "test");
    assert.equal((await source.head(object.key))!.etag, object.etag);
    assert.equal((await call({ key: object.key, etag: object.etag, verifyOnly: true })).status, 200);
    await target.put(object.key, "new production write");
    const preserved = await call({ key: object.key, etag: object.etag, resume: proof, reconcile: true });
    assert.equal((await preserved.json() as any).preservedTarget, true);
    assert.equal(await (await target.get(object.key))!.text(), "new production write");
    await target.delete(object.key);
    assert.equal((await call({ key: object.key, etag: object.etag, resume: proof, reconcile: true })).status, 200);
    assert.equal(await target.head(object.key), null, 'do not resurrect a production deletion');
    await call({ key: object.key, etag: object.etag });
    const late = await source.put("late.bin", "late old uploader");
    assert.ok(late);
    assert.equal((await call({ key: late.key, etag: late.etag, reconcile: true })).status, 200);
    assert.equal(await (await target.get(late.key))!.text(), "late old uploader");
    await target.put(late.key, "production wins without baseline");
    assert.equal((await call({ key: late.key, etag: late.etag, reconcile: true })).status, 200);
    assert.equal(await (await target.get(late.key))!.text(), "production wins without baseline");
    await source.put(object.key, "newer");
    assert.equal((await call({ key: object.key, etag: object.etag })).status, 409);
    assert.deepEqual(new Uint8Array(await (await target.get(object.key))!.arrayBuffer()), new Uint8Array([0, 255, 3]));
  } finally { await mf.dispose(); }
});

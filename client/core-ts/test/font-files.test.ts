// A face's files kept by the core for an app that keeps none (src/font-files.ts, docs/fonts.md): fetched in parts, how
// far said each percent; kept by hash, gzipped as fetched, then as the app unzipped them; only the chosen faces' stay;
// previews fetched once.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { FontFiles } from "../src/font-files.ts";
import * as fonts from "../src/fonts.ts";
import { parseCall } from "../src/core/calls.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Beside } from "../src/protocol.ts";
import type { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { run } from "./run.ts";

holdLanguage();

const ORIGIN = "https://stillfail.test";

function rig(chosen: () => unknown) {
  const host = new FakeHost();
  host.origin = ORIGIN;
  fonts.setOrigin(ORIGIN);
  let changed = 0;
  const store = { invalidate: () => void changed++ } as unknown as Store;
  const files = new FontFiles(host, store, chosen);
  const seen: unknown[] = [];
  const said = () => (files.compute() as { ok: unknown }).ok;
  // each file in parts of a tenth of the face, failing where `refuse` says
  const refuse = new Set<string>();
  host.onFetchStream((req) =>
    Effect.sync(() => {
      const f = ["inter", "lxgw-wenkai"].flatMap((id) => fonts.faceOf(id)!.files).find((x) => x.url === req.url)!;
      if (refuse.has(req.url)) return { status: 503, headers: [] as [string, string][], body: { take: Effect.succeed(null) } };
      const whole = fonts.faceOf(f.url.includes("/inter/") ? "inter" : "lxgw-wenkai")!.bytes;
      const part = Math.ceil(whole / 10);
      let left = f.bytes;
      return {
        status: 200,
        headers: [] as [string, string][],
        body: {
          take: Effect.sync(() => {
            seen.push(said());
            if (left === 0) return null;
            const n = Math.min(part, left);
            left -= n;
            return new Uint8Array(n).fill(7);
          }),
        },
      };
    }),
  );
  return { host, files, seen, said, refuse, changed: () => changed };
}

test("a face's files are fetched once, how far said as they come, kept gzipped until the app keeps them unzipped", async () => {
  const r = rig(() => ({ text: "lxgw-wenkai" }));
  const face = fonts.faceOf("lxgw-wenkai")!;
  assert.equal(face.files.length, 2);
  assert.equal(await run(r.files.fetch("lxgw-wenkai")), null);
  // how far, by what of the face came (its two files one after the other), each percent once
  const far = r.seen.map((s) => (s as { fetching: Record<string, number> }).fetching["lxgw-wenkai"]);
  assert.equal(far[0], 0);
  assert.deepEqual(far, [...far].sort((a, b) => a - b));
  assert.ok(far.some((p) => p > 0.4 && p < 0.6), JSON.stringify(far));
  assert.deepEqual(r.said(), { fetching: {}, failed: {} });
  // kept as fetched
  const first = (await run(r.files.file(face.files[0].sha256))) as Beside;
  assert.deepEqual(first.value, { zipped: true });
  assert.equal(first.bytes.length, face.files[0].bytes);
  // the app's unzipped one kept instead
  assert.equal(await run(r.files.keep(face.files[0].sha256, new Uint8Array([1, 2, 3]))), null);
  const now = (await run(r.files.file(face.files[0].sha256))) as Beside;
  assert.deepEqual([now.value, [...now.bytes]], [{ zipped: false }, [1, 2, 3]]);
  // fetched again: nothing asked for, what is kept is kept
  const asked = r.host.requests.length;
  await run(r.files.fetch("lxgw-wenkai"));
  assert.equal(r.host.requests.length, asked);
  assert.deepEqual((await run(r.files.file(face.files[0].sha256)) as Beside).value, { zipped: false });
  // a file not kept, a face not there
  await assert.rejects(run(r.files.file("00")));
  await assert.rejects(run(r.files.keep("00", new Uint8Array([1]))));
  await assert.rejects(run(r.files.fetch("comic-sans")));
});

test("where a file is kept, on a host that keeps values as files; its bytes still given by the call", async () => {
  const r = rig(() => ({ text: "lxgw-wenkai" }));
  const first = fonts.faceOf("lxgw-wenkai")!.files[0];
  // a host without files: nowhere
  assert.equal(r.files.at(first.sha256), null);
  r.host.storagePath = (key) => (r.host.storage.has(key) ? `/data/${key}` : null);
  assert.equal(r.files.at(first.sha256), null);
  await run(r.files.fetch("lxgw-wenkai"));
  assert.equal(r.files.at(first.sha256), `/data/fonts/file/${first.sha256}`);
  await run(r.files.keep(first.sha256, new Uint8Array([1, 2, 3])));
  const kept = (await run(r.files.file(first.sha256))) as Beside;
  assert.deepEqual([kept.value, [...kept.bytes]], [{ zipped: false }, [1, 2, 3]]);
});

test("a fetch that fails says why until the face is fetched again; only the chosen faces' files stay", async () => {
  let chosen: Record<string, string> = { ui: "inter" };
  const r = rig(() => chosen);
  const inter = fonts.faceOf("inter")!.files[0];
  r.refuse.add(inter.url);
  await assert.rejects(run(r.files.fetch("inter")));
  const failed = (r.said() as { failed: Record<string, string> }).failed;
  assert.match(failed.inter, /503/);
  r.refuse.clear();
  await run(r.files.fetch("inter"));
  assert.deepEqual(r.said(), { fetching: {}, failed: {} });
  // another chosen instead: once it is here, inter's file goes
  chosen = { ui: "lxgw-wenkai" };
  await run(r.files.fetch("lxgw-wenkai"));
  await assert.rejects(run(r.files.file(inter.sha256)));
  assert.equal(r.host.storage.has(`fonts/file/${inter.sha256}`), false);
  for (const f of fonts.faceOf("lxgw-wenkai")!.files) assert.deepEqual(((await run(r.files.file(f.sha256))) as Beside).value, { zipped: true });
  // kept across a core started again: what the host's storage holds
  const again = new FontFiles(r.host, { invalidate: () => {} } as unknown as Store, () => chosen);
  assert.equal(((await run(again.file(fonts.faceOf("lxgw-wenkai")!.files[1].sha256))) as Beside).bytes.length, fonts.faceOf("lxgw-wenkai")!.files[1].bytes);
});

test("a face's preview is fetched once and kept", async () => {
  const r = rig(() => ({}));
  const url = fonts.faceOf("inter")!.preview!;
  r.host.onFetch((req) => (req.url === url ? { status: 200, headers: [], body: new Uint8Array([9, 9]) } : { status: 404, headers: [], body: new Uint8Array() }));
  assert.deepEqual([...((await run(r.files.preview("inter"))) as Beside).bytes], [9, 9]);
  assert.deepEqual([...((await run(r.files.preview("inter"))) as Beside).bytes], [9, 9]);
  assert.equal(r.host.requests.filter((q) => q.url === url).length, 1);
  await assert.rejects(run(r.files.preview("comic-sans")));
});

test("the calls: fonts.fetch, fonts.preview {id}; fonts.file {sha256}; fonts.keep {sha256} with the file beside", () => {
  assert.deepEqual(parseCall("fonts.fetch", { id: "inter" }), { kind: "fonts", call: { kind: "fetch", id: "inter" } });
  assert.deepEqual(parseCall("fonts.preview", { id: "inter" }), { kind: "fonts", call: { kind: "preview", id: "inter" } });
  assert.deepEqual(parseCall("fonts.file", { sha256: "ab" }), { kind: "fonts", call: { kind: "file", sha256: "ab" } });
  assert.deepEqual(parseCall("fonts.keep", { sha256: "ab" }, new Uint8Array([1])), { kind: "fonts", call: { kind: "keep", sha256: "ab", bytes: new Uint8Array([1]) } });
  assert.throws(() => parseCall("fonts.keep", { sha256: "ab" }));
  assert.throws(() => parseCall("fonts.fetch", {}));
});

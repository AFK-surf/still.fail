// A face's files kept by the core for an app that keeps none (src/font-files.ts, docs/fonts.md): fetched in parts, how
// far said each percent; kept by hash, gzipped as fetched, then as the app unzipped them; every face fetched stays;
// previews fetched once.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { Effect } from "effect";
import { FontFiles } from "../src/font-files.ts";
import * as fonts from "../src/fonts.ts";
import { parseCall } from "../src/core/calls.ts";
import { SHARE_LOOKS_FILES } from "../src/share-looks.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Beside } from "../src/protocol.ts";
import type { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { run } from "./run.ts";

holdLanguage();

const ORIGIN = "https://stillfail.test";

function rig() {
  const host = new FakeHost();
  host.origin = ORIGIN;
  fonts.setOrigin(ORIGIN);
  let changed = 0;
  const store = { invalidate: () => void changed++ } as unknown as Store;
  const files = new FontFiles(host, store);
  const seen: unknown[] = [];
  const said = () => (files.compute() as { ok: unknown }).ok;
  // each file in parts of a tenth of the face, failing where `refuse` says
  const refuse = new Set<string>();
  // the share card's looks' files the site answers, in parts of 64 KB: none (a site that has not got them answers its page)
  const site = new Map<string, Uint8Array>();
  host.onFetchStream((req) =>
    Effect.sync(() => {
      if (req.url.startsWith(`${ORIGIN}/share-looks/`)) {
        const file = site.get(req.url.slice(`${ORIGIN}/share-looks/`.length)) ?? new TextEncoder().encode("<!doctype html><title>still.fail</title>");
        let at = 0;
        const parts = {
          take: Effect.sync(() => {
            seen.push(said());
            if (at >= file.length) return null;
            const part = file.slice(at, at + 65536);
            at += part.length;
            return part;
          }),
        };
        return { status: refuse.has(req.url) ? 503 : 200, headers: [] as [string, string][], body: parts };
      }
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
  return { host, files, seen, said, refuse, site, changed: () => changed };
}

test("a face's files are fetched once, how far said as they come, kept gzipped until the app keeps them unzipped", async () => {
  const r = rig();
  const face = fonts.faceOf("lxgw-wenkai")!;
  assert.equal(face.files.length, 2);
  assert.equal(await run(r.files.fetch("lxgw-wenkai")), null);
  // how far, by what of the face came (its two files one after the other), each percent once
  const far = r.seen.map((s) => (s as { fetching: Record<string, number> }).fetching["lxgw-wenkai"]);
  assert.equal(far[0], 0);
  assert.deepEqual(far, [...far].sort((a, b) => a - b));
  assert.ok(far.some((p) => p > 0.4 && p < 0.6), JSON.stringify(far));
  assert.deepEqual(r.said(), { fetching: {}, failed: {}, kept: ["lxgw-wenkai"], share: {}, shareFailed: {} });
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
  const r = rig();
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

test("a fetch that fails says why until the face is fetched again; a face fetched stays when another is chosen", async () => {
  const r = rig();
  const inter = fonts.faceOf("inter")!.files[0];
  r.refuse.add(inter.url);
  await assert.rejects(run(r.files.fetch("inter")));
  const failed = (r.said() as { failed: Record<string, string> }).failed;
  assert.match(failed.inter, /503/);
  r.refuse.clear();
  await run(r.files.fetch("inter"));
  assert.deepEqual(r.said(), { fetching: {}, failed: {}, kept: ["inter"], share: {}, shareFailed: {} });
  // another fetched: inter's file stays, chosen again with nothing asked of the network
  await run(r.files.fetch("lxgw-wenkai"));
  assert.deepEqual((r.said() as { kept: string[] }).kept, ["inter", "lxgw-wenkai"]);
  assert.deepEqual(((await run(r.files.file(inter.sha256))) as Beside).value, { zipped: true });
  const asked = r.host.requests.length;
  await run(r.files.fetch("inter"));
  assert.equal(r.host.requests.length, asked);
  // kept across a core started again: what the host's storage holds, said once it is read
  const again = new FontFiles(r.host, { invalidate: () => {} } as unknown as Store);
  assert.deepEqual((again.compute() as { ok: { kept: string[] } }).ok.kept, []);
  again.start();
  await run(Effect.void);
  assert.deepEqual((again.compute() as { ok: { kept: string[] } }).ok.kept, ["inter", "lxgw-wenkai"]);
  assert.equal(((await run(again.file(fonts.faceOf("lxgw-wenkai")!.files[1].sha256))) as Beside).bytes.length, fonts.faceOf("lxgw-wenkai")!.files[1].bytes);
});

test("a face's preview is fetched once and kept", async () => {
  const r = rig();
  const url = fonts.faceOf("inter")!.preview!;
  r.host.onFetch((req) => (req.url === url ? { status: 200, headers: [], body: new Uint8Array([9, 9]) } : { status: 404, headers: [], body: new Uint8Array() }));
  assert.deepEqual([...((await run(r.files.preview("inter"))) as Beside).bytes], [9, 9]);
  assert.deepEqual([...((await run(r.files.preview("inter"))) as Beside).bytes], [9, 9]);
  assert.equal(r.host.requests.filter((q) => q.url === url).length, 1);
  await assert.rejects(run(r.files.preview("comic-sans")));
});

/// A file of the share card's looks as still.fail's site has it (web/public/share-looks/).
const onSite = (file: string) => new Uint8Array(readFileSync(new URL(`../../../web/public/share-looks/${file}`, import.meta.url)));

test("the share card's looks' table says the site's files as they are (node scripts/share-looks.ts)", async () => {
  const { made } = await import("../../../scripts/share-looks.ts");
  assert.equal(readFileSync(new URL("../src/share-looks.ts", import.meta.url), "utf8"), made());
});

test("a file of the share card's looks is fetched from the site once, how far said as it comes, and kept; nothing else is", async () => {
  const r = rig();
  const file = "1/a1-murasame-adv.webp";
  r.site.set(file, onSite(file));
  const got = (await run(r.files.share(file))) as Beside;
  assert.deepEqual(got.bytes, onSite(file));
  const far = r.seen.map((s) => (s as { share: Record<string, { got: number; bytes: number }> }).share[file]);
  assert.deepEqual(far[0], { got: 0, bytes: SHARE_LOOKS_FILES[file]!.bytes });
  assert.ok(far.some((p) => p !== undefined && p.got > 0 && p.got < p.bytes), JSON.stringify(far));
  assert.deepEqual(r.said(), { fetching: {}, failed: {}, kept: [], share: {}, shareFailed: {} });
  // kept: asked again, nothing fetched
  const asked = r.host.requests.length;
  assert.deepEqual(((await run(r.files.share(file))) as Beside).bytes, onSite(file));
  assert.equal(r.host.requests.length, asked);
  for (const other of ["../avatars/a.gz", "1/nobody.webp", "x/face-400.gz", "https://evil.test/a.gz", "1/../1/face-400.gz"]) await assert.rejects(run(r.files.share(other)));
});

test("what a site without the file answers (its page) is not kept as it: said failed, fetched again once asked again", async () => {
  const r = rig();
  const file = "1/face-400.gz";
  // kept by a core before files were checked: the page, dropped
  r.host.storage.set(`fonts/share/${file}`, new TextEncoder().encode("<!doctype html>"));
  await assert.rejects(run(r.files.share(file)), /下载到的文件不对/);
  assert.deepEqual((r.said() as { shareFailed: Record<string, string> }).shareFailed, { [file]: "下载到的文件不对" });
  assert.equal(r.host.storage.has(`fonts/share/${file}`), false);
  assert.equal(r.host.storage.has(`share-looks/${file}`), false);
  // a site that answers but not 200
  r.site.set(file, onSite(file));
  r.refuse.add(`${ORIGIN}/share-looks/${file}`);
  await assert.rejects(run(r.files.share(file)), /503/);
  // the site has it now: fetched, kept, the failure gone
  r.refuse.clear();
  assert.deepEqual(((await run(r.files.share(file))) as Beside).bytes, onSite(file));
  assert.deepEqual(r.said(), { fetching: {}, failed: {}, kept: [], share: {}, shareFailed: {} });
  // one cut short or longer than said: not the file either
  const short = "1/face-600.gz";
  r.site.set(short, onSite(short).slice(0, 1000));
  await assert.rejects(run(r.files.share(short)), /下载到的文件不对/);
  r.site.set(short, new Uint8Array([...onSite(short), 0]));
  await assert.rejects(run(r.files.share(short)), /下载到的文件不对/);
  assert.equal(r.host.storage.has(`share-looks/${short}`), false);
});

test("still.fail's own app on the test channel has the looks' files from the test channel's site, which main deploys", () => {
  fonts.setOrigin("https://app.still.fail", true);
  assert.equal(fonts.shareLooksFile("1/face-400.gz"), "https://app.youdid.wtf/share-looks/1/face-400.gz");
  fonts.setOrigin("https://app.still.fail");
  assert.equal(fonts.shareLooksFile("1/a1-murasame-adv.webp"), "https://app.still.fail/share-looks/1/a1-murasame-adv.webp");
  // a cloud of its own (a page's, a local one): its own
  fonts.setOrigin("https://app.youdid.wtf/", true);
  assert.equal(fonts.shareLooksFile("1/face-400.gz"), "https://app.youdid.wtf/share-looks/1/face-400.gz");
  fonts.setOrigin("http://localhost:8787", true);
  assert.equal(fonts.shareLooksFile("1/face-400.gz"), "http://localhost:8787/share-looks/1/face-400.gz");
  fonts.setOrigin(ORIGIN);
});

test("the calls: fonts.fetch, fonts.preview {id}; fonts.file {sha256}; fonts.keep {sha256} with the file beside", () => {
  assert.deepEqual(parseCall("fonts.fetch", { id: "inter" }), { kind: "fonts", call: { kind: "fetch", id: "inter" } });
  assert.deepEqual(parseCall("fonts.preview", { id: "inter" }), { kind: "fonts", call: { kind: "preview", id: "inter" } });
  assert.deepEqual(parseCall("fonts.share", { file: "1/face-400.gz" }), { kind: "fonts", call: { kind: "share", file: "1/face-400.gz" } });
  assert.deepEqual(parseCall("fonts.file", { sha256: "ab" }), { kind: "fonts", call: { kind: "file", sha256: "ab" } });
  assert.deepEqual(parseCall("fonts.keep", { sha256: "ab" }, new Uint8Array([1])), { kind: "fonts", call: { kind: "keep", sha256: "ab", bytes: new Uint8Array([1]) } });
  assert.throws(() => parseCall("fonts.keep", { sha256: "ab" }));
  assert.throws(() => parseCall("fonts.fetch", {}));
});

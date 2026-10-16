// The web app the beta desktop app takes without a new app (docs/desktop-web-updates.md): its archive, its signed feed
// (scripts/release-sign.ts desktop-web, verifyDesktopWeb), what the app downloads and serves (web-update.mts), and which
// changes are a web release alone (scripts/desktop-web.ts plan).
import assert from "node:assert/strict";
import { createHash, createPublicKey, generateKeyPairSync, sign } from "node:crypto";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gunzipSync, gzipSync } from "node:zlib";
import { describe, test } from "node:test";
import { readArchive, writeArchive } from "../apps/desktop/src/web-archive.mts";
import { WebUpdates } from "../apps/desktop/src/web-update.mts";
import { Unverified, keyId, verifyDesktopWeb } from "../station/src/updates/signed.ts";
import { SHELL, plan } from "../scripts/desktop-web.ts";

// A release key of the tests' own (station/test/release-fakes.ts's, made here: that one takes the station's packages,
// which this check has not installed), and another the app does not take.
const pair = () => {
  const { privateKey } = generateKeyPairSync("ed25519");
  const raw = Buffer.from(createPublicKey(privateKey).export({ format: "jwk" }).x as string, "base64url").toString("base64");
  return { privateKey, raw, pem: privateKey.export({ format: "pem", type: "pkcs8" }) as string };
};
const KEY = pair();
const OTHER = pair();
const trusted = new Map([[keyId(KEY.raw), KEY.raw]]);
const signed = (words: object, key = KEY) => {
  const bytes = Buffer.from(JSON.stringify(words));
  return { release: bytes.toString("base64"), signature: sign(null, bytes, key.privateKey).toString("base64"), key: keyId(key.raw) };
};
const temp = () => mkdtempSync(join(tmpdir(), "stillfail-web-update-"));
const files = (build: number) => [
  { path: "index.html", bytes: Buffer.from(`<!doctype html><title>${build}</title>`) },
  { path: `assets/index-${build}.js`, bytes: Buffer.from(`console.log(${build})`) },
  { path: "build.json", bytes: Buffer.from(JSON.stringify({ build })) },
];
const sha = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

/** A feed and its archive, as CI puts them: build `build`, for apps from `needs`, signed by `key`. */
function release(build: number, needs: number, key = undefined as typeof OTHER | undefined, bytes = writeArchive(files(build))) {
  const file = `stillfail-beta-web-0.1.${build}.tar.gz`;
  const words = { kind: "stillfail-desktop-web", version: `0.1.${build}`, build, needs, file, sha256: sha(bytes), size: bytes.length };
  return { feed: { version: `0.1.${build}`, build, needs, file, ...(key ? signed(words, key) : signed(words)) }, file, bytes };
}

/** A releases host of its own: what it serves is what `served` holds now; it counts what was asked of it. */
function host(served: { feed?: object; files: Record<string, Uint8Array> }) {
  const asked: string[] = [];
  const fetch = async (url: string) => {
    const name = url.slice(url.lastIndexOf("/") + 1);
    asked.push(name);
    if (name === "stillfail-beta-web.json") return served.feed ? new Response(JSON.stringify(served.feed)) : new Response("", { status: 404 });
    const bytes = served.files[name];
    return bytes ? new Response(Buffer.from(bytes)) : new Response("", { status: 404 });
  };
  return { fetch, asked };
}

function app(dir: string, build: number, fetch: (url: string) => Promise<Response>, now?: () => number) {
  const carried = join(dir, "Resources", "web");
  mkdirSync(join(carried, "assets"), { recursive: true });
  writeFileSync(join(carried, "index.html"), "carried");
  writeFileSync(join(carried, "assets", "old.js"), "carried's");
  return new WebUpdates({ dir: join(dir, "userData", "web"), carried, app: build, feed: "https://app.still.fail/releases/desktop/web/stillfail-beta-web.json", fetch, trusted, ...(now ? { now } : {}) });
}

describe("the desktop app's web app without a new app", () => {
  test("an archive holds plain files under its directory, the same files giving the same bytes", () => {
    const a = writeArchive(files(3000));
    assert.deepEqual(Buffer.from(a), Buffer.from(writeArchive([...files(3000)].reverse())));
    assert.deepEqual(readArchive(a).map((f) => [f.path, Buffer.from(f.bytes).toString()]), files(3000).map((f) => [f.path, f.bytes.toString()]).sort());
    // A long path: ustar's prefix and name.
    const long = `assets/${"a".repeat(90)}/${"b".repeat(90)}.js`;
    assert.equal(readArchive(writeArchive([{ path: long, bytes: Buffer.from("x") }]))[0]!.path, long);
    for (const bad of ["../x", "/etc/passwd", "a/../../x", "a//b", "./a"]) assert.throws(() => writeArchive([{ path: bad, bytes: Buffer.from("") }]), /not a path/);
    // Made by hand: a path leaving the directory, a link, a header changed after its checksum.
    const raw = Buffer.from(gunzipSync(writeArchive([{ path: "index.html", bytes: Buffer.from("x") }])));
    const evil = Buffer.from(raw);
    evil.write("../index.html\0", 0);
    fixSum(evil);
    assert.throws(() => readArchive(gzipSync(evil)), /may not/);
    const link = Buffer.from(raw);
    link[156] = 0x32; // "2": a symbolic link
    fixSum(link);
    assert.throws(() => readArchive(gzipSync(link)), /not a plain file/);
    const changed = Buffer.from(raw);
    changed.write("other.html", 0);
    assert.throws(() => readArchive(gzipSync(changed)), /checksum/);
    assert.throws(() => readArchive(gzipSync(raw.subarray(0, 600))), /cut short|without its end/);
  });

  test("a feed verifies only as signed, for an app as old as this one, newer than what it runs", () => {
    const { feed } = release(3010, 3000);
    assert.equal(verifyDesktopWeb(feed, 3005, 3005, trusted).build, 3010);
    const unverified = (f: () => unknown, why: RegExp) => assert.throws(f, (e: Error) => e instanceof Unverified && why.test(e.message));
    unverified(() => verifyDesktopWeb(feed, 2999, 2999, trusted), /needs the app 0\.1\.3000/);
    unverified(() => verifyDesktopWeb(feed, 3010, 3010, trusted), /not newer/);
    unverified(() => verifyDesktopWeb(release(3010, 3000, OTHER).feed, 3005, 3005, trusted), /does not take/);
    unverified(() => verifyDesktopWeb({ ...feed, version: "0.1.3020" }, 3005, 3005, trusted), /not the signed one/);
    unverified(() => verifyDesktopWeb({ version: "0.1.3010" }, 3005, 3005, trusted), /not signed/);
    const words = JSON.parse(Buffer.from(feed.release, "base64").toString());
    unverified(() => verifyDesktopWeb({ ...feed, ...signed({ ...words, file: "../station.json" }) }, 3005, 3005, trusted), /not well formed/);
    unverified(() => verifyDesktopWeb({ ...feed, ...signed({ ...words, needs: 3011 }) }, 3020, 3005, trusted), /not a desktop web release/);
  });

  test("scripts/release-sign.ts signs a web release as the app verifies it", () => {
    const dir = temp();
    const archive = join(dir, "stillfail-beta-web-0.1.3010.tar.gz");
    writeFileSync(archive, writeArchive(files(3010)));
    const sign = (...more: string[]) => spawnSync(process.execPath, [join(import.meta.dirname, "..", "scripts", "release-sign.ts"), "desktop-web", join(dir, "feed.json"), archive, ...more], {
      env: { PATH: process.env.PATH, RELEASE_SIGNING_KEY: KEY.pem }, encoding: "utf8",
    });
    assert.equal(sign("--build", "3010", "--needs", "3000").status, 0);
    const feed = JSON.parse(readFileSync(join(dir, "feed.json"), "utf8"));
    const r = verifyDesktopWeb(feed, 3000, 2999, trusted);
    assert.deepEqual([r.build, r.needs, r.file, r.sha256], [3010, 3000, "stillfail-beta-web-0.1.3010.tar.gz", sha(readFileSync(archive))]);
    // An app newer than the web app it is for is not a release to sign.
    assert.notEqual(sign("--build", "3010", "--needs", "3011").status, 0);
  });

  test("the app downloads a newer build, serves it when taken, and keeps the files of the one before", async () => {
    const dir = temp();
    const served: { feed?: object; files: Record<string, Uint8Array> } = { files: {} };
    const { fetch, asked } = host(served);
    const web = app(dir, 3000, fetch);
    // No feed yet: nothing.
    assert.equal(await web.check(), null);
    assert.deepEqual(web.roots(), [join(dir, "Resources", "web")]);
    const first = release(3010, 3000);
    served.feed = first.feed;
    served.files[first.file] = first.bytes;
    const ready = await web.check();
    assert.equal(ready?.build, 3010);
    // Downloaded, not served until taken.
    assert.equal(web.current().build, 3000);
    assert.equal(readFileSync(join(ready!.dir, "assets", "index-3010.js"), "utf8"), "console.log(3010)");
    await web.take();
    assert.equal(web.current().build, 3010);
    assert.deepEqual(web.roots(), [ready!.dir, join(dir, "Resources", "web")]);
    // The next: the one before stays a root while the app runs (its pages' chunks).
    const second = release(3020, 3000);
    served.feed = second.feed;
    served.files[second.file] = second.bytes;
    await web.check();
    await web.take();
    assert.deepEqual(web.roots(), [join(dir, "userData", "web", "0.1.3020"), join(dir, "userData", "web", "0.1.3010"), join(dir, "Resources", "web")]);
    // Asked again: nothing newer, nothing downloaded.
    const before = asked.length;
    assert.equal(await web.check(), null);
    assert.deepEqual(asked.slice(before), ["stillfail-beta-web.json"]);
    // The next start serves the newest downloaded at once, and keeps only it.
    const again = app(dir, 3000, fetch);
    assert.equal(again.current().build, 3020);
    await again.settle();
    assert.equal(existsSync(join(dir, "userData", "web", "0.1.3010")), false);
    assert.equal(JSON.parse(readFileSync(join(dir, "userData", "web", "state.json"), "utf8")).served, 3020);
    // An app updated since, carrying a newer web app than the one downloaded, serves its own.
    assert.equal(app(dir, 3030, fetch).current().build, 3030);
  });

  test("an app not asked for a while, or never by this build of it, is stale; a download tells its progress", async () => {
    const dir = temp();
    const served: { feed?: object; files: Record<string, Uint8Array> } = { files: {} };
    const { fetch } = host(served);
    let now = 1_000_000;
    const HOUR = 60 * 60 * 1000;
    const web = app(dir, 3000, fetch, () => now);
    assert.equal(web.stale(HOUR), true);
    // A feed that fails says nothing of what is newest.
    const failing = app(dir, 3000, async () => new Response("", { status: 502 }), () => now);
    await assert.rejects(failing.check(), /502/);
    assert.equal(failing.stale(HOUR), true);
    // Nothing published: asked all the same.
    await web.check();
    assert.equal(web.stale(HOUR), false);
    const r = release(3010, 3000);
    served.feed = r.feed;
    served.files[r.file] = r.bytes;
    const told: number[] = [];
    web.progress = (p) => {
      assert.deepEqual([p.build, p.size], [3010, r.bytes.length]);
      told.push(p.received);
    };
    now += 2 * HOUR;
    assert.equal(web.stale(HOUR), true);
    assert.equal((await web.check())?.build, 3010);
    assert.equal(told[0], 0);
    assert.equal(told.at(-1), r.bytes.length);
    assert.equal(web.stale(HOUR), false);
    // The next start of this app knows when it asked; the app updated since does not (it is offered other builds).
    now += HOUR / 2;
    assert.equal(app(dir, 3000, fetch, () => now).stale(HOUR), false);
    assert.equal(app(dir, 3005, fetch, () => now).stale(HOUR), true);
    // More bytes than signed: not read on.
    web.progress = null;
    const long = release(3020, 3000);
    served.feed = long.feed;
    served.files[long.file] = Buffer.concat([long.bytes, Buffer.from("more")]);
    await assert.rejects(web.check(), /not the one signed: longer/);
  });

  test("a build for a newer app, or not the bytes signed, is not taken; one that did not come up is put away", async () => {
    const dir = temp();
    const served: { feed?: object; files: Record<string, Uint8Array> } = { files: {} };
    const { fetch, asked } = host(served);
    const web = app(dir, 3000, fetch);
    const newer = release(3010, 3005);
    served.feed = newer.feed;
    served.files[newer.file] = newer.bytes;
    assert.equal(await web.check(), null);
    assert.ok(!asked.includes(newer.file));
    const tampered = release(3011, 3000);
    served.feed = tampered.feed;
    served.files[tampered.file] = writeArchive(files(9999));
    await assert.rejects(web.check(), /not the one signed/);
    assert.equal(web.current().build, 3000);
    const good = release(3012, 3000);
    served.feed = good.feed;
    served.files[good.file] = good.bytes;
    await web.check();
    await web.take();
    // A page on another build than the one served says it failed: not this one's to put away.
    assert.equal(await web.back(3011), false);
    assert.equal(web.current().build, 3012);
    assert.equal(await web.back(3012), true);
    assert.equal(web.current().build, 3000);
    // A second window on 3012 says so too: 3000 is served now, and stays.
    assert.equal(await web.back(3012), false);
    // Offered again, it is not downloaded again.
    const count = asked.filter((a) => a === good.file).length;
    assert.equal(await web.check(), null);
    assert.equal(asked.filter((a) => a === good.file).length, count);
  });

  test("a change to the web app alone is a web release; one to the shell, a new app", () => {
    assert.deepEqual(plan(["web/src/App.tsx", "web/src/i18n.ts"]), { desktop: false, desktopWeb: true });
    // The root's packages: the shell's bundles take some of them too.
    assert.deepEqual(plan(["pnpm-lock.yaml"]), { desktop: true, desktopWeb: false });
    assert.deepEqual(plan(["web/src/App.tsx", "client/core-ts/src/core.ts"]), { desktop: true, desktopWeb: true });
    // What the shell's bundles take from web/ is the shell's.
    assert.deepEqual(plan(["web/src/core/delta.ts"]), { desktop: true, desktopWeb: false });
    assert.deepEqual(plan(["docs/x.md", "cloud/src/api.ts"]), { desktop: false, desktopWeb: false });
    assert.ok(SHELL.test("apps/desktop/src/web-update.mts"));
  });
});

/** A ustar header's checksum, made again after it was changed. */
function fixSum(tar: Buffer): void {
  tar.fill(0x20, 148, 156);
  let sum = 0;
  for (let i = 0; i < 512; i++) sum += tar[i]!;
  tar.write(`${sum.toString(8).padStart(6, "0")}\0 `, 148);
}

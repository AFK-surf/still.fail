// Signed releases (scripts/release-sign.ts): what verifies and what does not, the release signed by
// scripts/release-sign.ts as CI signs it, and `stillfail-station update` saying what to run.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { RELEASE_KEYS, Unverified, allowed, expected, keyId, sha256, trustedKeys, verifyFeed, verifySigned } from "../src/updates/signed.ts";
import { gunzipSync } from "node:zlib";
import { storedZip } from "../../scripts/delta.ts";
import { updateCommand } from "../src/updates/command.ts";
import { platform } from "../src/updates/versions.ts";
import { KEY, OTHER, SHA_A, SHA_B, feedOf, nextRelease, programBytes, signed, trusted, withDeltas, words } from "./release-fakes.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const temp = () => realpathSync(mkdtempSync(join(tmpdir(), "stillfail-signed-")));
const unverified = (f: () => unknown, why: RegExp) => assert.throws(f, (e: Error) => e instanceof Unverified && why.test(e.message));

describe("signed releases", () => {
  test("a feed verifies only as signed, by a key the station takes, for the version it says", () => {
    const r = verifyFeed(feedOf(1310), trusted);
    assert.equal(r.version, "0.1.1310");
    assert.deepEqual(expected(r, platform()), { sha256: SHA_A, size: 1, nodeSha256: SHA_B });
    unverified(() => verifyFeed({ version: "0.1.1310", build: 1310 }, trusted), /not signed/);
    unverified(() => verifyFeed(feedOf(1310, {}, OTHER), trusted), /does not take/);
    // The other key's signature under the tests' key's name.
    unverified(() => verifyFeed({ ...feedOf(1310, {}, OTHER), key: keyId(KEY.raw) }, trusted), /does not verify/);
    // A word changed after signing.
    const f = feedOf(1310);
    const w = JSON.parse(Buffer.from(f.release, "base64").toString("utf8"));
    w.build = 1311;
    w.version = "0.1.1311";
    unverified(() => verifyFeed({ ...f, version: "0.1.1311", release: Buffer.from(JSON.stringify(w)).toString("base64") }, trusted), /does not verify/);
    // Signed words of another release, or none, under the feed's version.
    unverified(() => verifyFeed({ ...feedOf(1310), version: "0.1.1320" }, trusted), /not the signed one/);
    unverified(() => verifyFeed({ version: "0.1.1310", ...signed({ ...words(1310), version: "0.1.1" }) }, trusted), /not the signed one/);
    // 0.<m>.<n>: any m (the stable releases before it, only said), n its build.
    assert.equal(verifyFeed({ version: "0.34.1310", ...signed({ ...words(1310), version: "0.34.1310" }) }, trusted).build, 1310);
    unverified(() => verifyFeed({ version: "0.34.1311", ...signed({ ...words(1310), version: "0.34.1311" }) }, trusted), /not the signed one/);
    unverified(() => verifyFeed({ version: "1.34.1310", ...signed({ ...words(1310), version: "1.34.1310" }) }, trusted), /not the signed one/);
    unverified(() => verifyFeed({ version: "0.1.1310", ...signed({ kind: "stillfail-desktop-win", version: "0.1.1310", build: 1310 }) }, trusted), /not a station release/);
    unverified(() => verifyFeed(feedOf(1310, { sha256: "nope" }), trusted), /not well formed/);
    unverified(() => expected(r, "plan9-mips"), /no build for plan9-mips/);
  });

  test("a build may say its raw archive (what a delta makes), both its words well formed or neither", () => {
    const raw = { rawSha256: "c".repeat(64), rawSize: 4096 };
    assert.deepEqual(expected(verifyFeed(feedOf(1310, raw), trusted), platform()), { sha256: SHA_A, size: 1, nodeSha256: SHA_B, ...raw });
    // From before (none said): as it was.
    assert.equal(expected(verifyFeed(feedOf(1310), trusted), platform()).rawSha256, undefined);
    for (const bad of [{ rawSha256: "nope", rawSize: 1 }, { rawSha256: "c".repeat(64) }, { rawSize: 1 }, { rawSha256: "c".repeat(64), rawSize: -1 }, { rawSha256: "c".repeat(64), rawSize: "1" }, { rawSha256: "C".repeat(64), rawSize: 1 }]) {
      unverified(() => verifyFeed(feedOf(1310, bad as object), trusted), /not well formed/);
    }
    // The feed's deltas are not the signed words': whatever they say, the release verifies as it is.
    assert.equal(verifyFeed({ ...feedOf(1310, raw), deltas: { [platform() ?? "darwin-arm64"]: [{ from: 1300, file: "x", sha256: "nope", size: -1 }] } }, trusted).build, 1310);
  });

  test("the station takes only the release keys and those its environment adds; placeholders none", () => {
    assert.deepEqual([...trustedKeys({}).values()], RELEASE_KEYS.filter((k) => !k.startsWith("__")));
    const added = trustedKeys({ STILLFAIL_RELEASE_KEYS: ` ${KEY.raw} , ` });
    assert.equal(added.get(keyId(KEY.raw)), KEY.raw);
    // Every key in the station is a real Ed25519 key (32 bytes), or a placeholder not taken.
    for (const k of RELEASE_KEYS) assert.ok(k.startsWith("__") || Buffer.from(k, "base64").length === 32, k);
  });

  test("an older release only back from the beta to the stable channel", () => {
    const r = verifyFeed(feedOf(1300), trusted);
    assert.ok(allowed(r, 1290, "beta", "beta"));
    assert.ok(allowed(r, 1300, "stable", "stable"), "the same one again");
    assert.ok(!allowed(r, 1310, "stable", "stable"));
    assert.ok(!allowed(r, 1310, "beta", "beta"));
    assert.ok(!allowed(r, 1310, "beta", "stable"));
    assert.ok(allowed(r, 1310, "stable", "beta"));
    assert.ok(allowed(r, null, "stable", "stable"), "a release that says no build");
  });

  test("scripts/release-sign.ts signs a station release as stations verify it, and refuses to sign none in CI", () => {
    const dir = temp();
    // Two platforms' archives, and their Nodes as node-dist.sh keeps them: bin/node in a tarball, node.exe in
    // nodejs.org's zip.
    const node = "24.21.0";
    // The archives as scripts/release.sh packs them: a .tar.gz, and Windows' zip (deflated).
    mkdirSync(join(dir, "r", "stillfail"), { recursive: true });
    writeFileSync(join(dir, "r", "stillfail", "VERSION"), "the release ".repeat(100));
    execFileSync("tar", ["-czf", join(dir, "mac.tar.gz"), "-C", join(dir, "r"), "stillfail"]);
    execFileSync("zip", ["-qr", join(dir, "win.zip"), "stillfail"], { cwd: join(dir, "r") });
    mkdirSync(join(dir, "n", "bin"), { recursive: true });
    writeFileSync(join(dir, "n", "bin", "node"), "a node binary");
    execFileSync("tar", ["-czf", join(dir, "node.tar.gz"), "-C", join(dir, "n"), "bin/node"]);
    mkdirSync(join(dir, "w", `node-v${node}-win-x64`), { recursive: true });
    writeFileSync(join(dir, "w", `node-v${node}-win-x64`, "node.exe"), "a node.exe");
    execFileSync("zip", ["-qr", join(dir, "node.zip"), `node-v${node}-win-x64`], { cwd: join(dir, "w") });
    const sign = (env: Record<string, string>, ...more: string[]) =>
      spawnSync(process.execPath, [join(root, "scripts", "release-sign.ts"), "station", join(dir, "station.json"), "--build", "1310", "--commit", "c".repeat(40), "--node", node,
        `darwin-arm64=${join(dir, "mac.tar.gz")},${join(dir, "node.tar.gz")}`, `win32-x64=${join(dir, "win.zip")},${join(dir, "node.zip")}`, ...more], {
        env: { PATH: process.env.PATH, ...env }, encoding: "utf8",
      });
    const done = sign({ RELEASE_SIGNING_KEY: KEY.pem });
    assert.equal(done.status, 0, done.stderr);
    const feed = JSON.parse(readFileSync(join(dir, "station.json"), "utf8"));
    assert.deepEqual([feed.version, feed.build, feed.key], ["0.1.1310", 1310, keyId(KEY.raw)]);
    const r = verifyFeed(feed, trusted);
    const hex = (s: string) => sha256(Buffer.from(s));
    const [mac, win] = [readFileSync(join(dir, "mac.tar.gz")), readFileSync(join(dir, "win.zip"))];
    // Their raw forms: the tar inside, the zip stored (scripts/delta.ts rawOf).
    const [macRaw, winRaw] = [gunzipSync(mac), storedZip(win)];
    assert.ok(!winRaw.equals(win), "the zip's entries were deflated");
    assert.deepEqual(r.builds, {
      "darwin-arm64": { sha256: sha256(mac), size: mac.length, nodeSha256: hex("a node binary"), rawSha256: sha256(macRaw), rawSize: macRaw.length },
      "win32-x64": { sha256: sha256(win), size: win.length, nodeSha256: hex("a node.exe"), rawSha256: sha256(winRaw), rawSize: winRaw.length },
    });
    assert.equal(r.node, node);
    // Without a key: refused in CI, and outside it unless an unsigned release is asked for (a dev cloud's).
    assert.equal(sign({ CI: "true" }, "--unsigned-ok").status, 1);
    assert.equal(sign({}).status, 1);
    const unsigned = sign({}, "--unsigned-ok");
    assert.equal(unsigned.status, 0, unsigned.stderr);
    assert.match(unsigned.stderr, /not signed/);
    assert.equal(JSON.parse(readFileSync(join(dir, "station.json"), "utf8")).release, undefined);
    // In CI, a key no station takes is refused too.
    const other = sign({ CI: "true", RELEASE_SIGNING_KEY: KEY.pem });
    assert.equal(other.status, 1);
    assert.match(other.stderr, /not one of the keys stations take/);
    // The Windows installer's .sig.
    writeFileSync(join(dir, "x.exe"), "an installer");
    const file = spawnSync(process.execPath, [join(root, "scripts", "release-sign.ts"), "file", join(dir, "x.exe"), "--kind", "stillfail-desktop-win", "--build", "1310"], {
      env: { PATH: process.env.PATH, RELEASE_SIGNING_KEY: KEY.pem }, encoding: "utf8",
    });
    assert.equal(file.status, 0, file.stderr);
    const d = verifySigned(JSON.parse(readFileSync(join(dir, "x.exe.sig"), "utf8")), trusted);
    assert.deepEqual(d, { kind: "stillfail-desktop-win", version: "0.1.1310", build: 1310, file: "x.exe", sha256: sha256(readFileSync(join(dir, "x.exe"))), size: 12 });
  });

  test("`stillfail-station update` sets the channel asked, verifies the latest, and says what to run", async (t) => {
    const asked: string[] = [];
    let feed: object = feedOf(1310);
    const server = createServer((req, res) => {
      asked.push(req.url ?? "");
      if (req.url === "/stations/releases/station-beta.json") return void res.end(JSON.stringify(feed));
      res.writeHead(404).end();
    });
    await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
    t.after(() => server.close());
    const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    const data = temp();
    const app = join(data, "app");
    mkdirSync(join(app, "bin"), { recursive: true });
    mkdirSync(join(data, "mesh"));
    writeFileSync(join(app, "BUILD"), "1300\n");
    // In Comma: its releases under /stations.
    writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin, provider: "comma" }));
    const said: string[] = [];
    const log = console.log;
    const error = console.error;
    console.log = (s: string) => said.push(s);
    console.error = (s: string) => said.push(`! ${s}`);
    try {
      // No installer in the release (one from before they were bundled): refused.
      assert.equal(await updateCommand(["update", "--beta", "--app", app, "--data", data], data, trusted), 1);
      assert.match(said.pop()!, /不含安装脚本/);
      assert.equal(JSON.parse(readFileSync(join(data, "config.json"), "utf8")).updateChannel, "beta");
      writeFileSync(join(app, "bin", `install.zh.${process.platform === "win32" ? "ps1" : "sh"}`), "");
      assert.equal(await updateCommand(["update", "--app", app, "--data", data], data, trusted), 0);
      assert.deepEqual(said.pop()!.split("\n"), [
        `script=${join(app, "bin", `install.zh.${process.platform === "win32" ? "ps1" : "sh"}`)}`,
        `STILLFAIL_ORIGIN=${origin}/stations`,
        "STILLFAIL_CHANNEL=beta",
        `STILLFAIL_RELEASE_SHA256=${SHA_A}`,
        `STILLFAIL_NODE_SHA256=${SHA_B}`,
        "STILLFAIL_INSTALL_LANG=zh",
      ]);
      // Not signed by a key it takes: refused, nothing to run.
      feed = feedOf(1310, {}, OTHER);
      assert.equal(await updateCommand(["update", "--app", app, "--data", data], data, trusted), 1);
      assert.match(said.pop()!, /签名校验失败/);
      feed = feedOf(1290);
      assert.equal(await updateCommand(["update", "--app", app, "--data", data], data, trusted), 1);
      assert.match(said.pop()!, /0\.1\.1290 早于当前的 0\.1\.1300/);
      assert.equal(await updateCommand(["update", "--app", app, "--beta", "--stable", "--data", data], data, trusted), 2);
    } finally {
      console.log = log;
      console.error = error;
    }
    assert.ok(asked.every((a) => a === "/stations/releases/station-beta.json"), asked.join());
  });

  test("`stillfail-station update` takes a delta from the build it runs, and says what it made for the installer", { skip: process.platform === "win32" && "a .tar.gz release" }, async (t) => {
    const data = temp();
    const app = join(data, "app");
    mkdirSync(join(app, "bin"), { recursive: true });
    mkdirSync(join(app, "station"));
    mkdirSync(join(data, "mesh"));
    writeFileSync(join(app, "BUILD"), "1300\n");
    writeFileSync(join(app, "bin", "install.zh.sh"), "");
    writeFileSync(join(app, "station", "main.js"), programBytes(200_000));
    const release = nextRelease(join(data, "release"), app);
    let feed: object = withDeltas(feedOf(1310, release.build), [release.entry(1300)]);
    const server = createServer((req, res) => {
      if (req.url === "/releases/station.json") return void res.end(JSON.stringify(feed));
      if (req.url === "/releases/station/next.delta") return void res.end(release.delta);
      res.writeHead(404).end();
    });
    await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
    t.after(() => server.close());
    const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin }));
    const said: string[] = [];
    const log = console.log;
    console.log = (s: string) => said.push(s);
    t.after(() => (console.log = log));
    assert.equal(await updateCommand(["update", "--app", app, "--data", data], data, trusted), 0);
    const told = Object.fromEntries(said.pop()!.split("\n").map((l) => l.split(/=(.*)/s).slice(0, 2) as [string, string]));
    assert.equal(told.STILLFAIL_RELEASE_SHA256, release.build.rawSha256);
    assert.match(told.STILLFAIL_ARCHIVE!, /[\\/]stillfail-handed\.[0-9a-f]+[\\/]stillfail\.tar\.gz$/);
    assert.ok(readFileSync(told.STILLFAIL_ARCHIVE!).equals(release.raw), "the release's raw archive");
    rmSync(dirname(told.STILLFAIL_ARCHIVE!), { recursive: true, force: true });
    // One whose hash is not the feed's: the installer downloads the release, checked by its own hash.
    feed = withDeltas(feedOf(1310, release.build), [{ ...release.entry(1300), sha256: SHA_A }]);
    assert.equal(await updateCommand(["update", "--app", app, "--data", data], data, trusted), 0);
    const plain = said.pop()!;
    assert.match(plain, new RegExp(`STILLFAIL_RELEASE_SHA256=${release.build.sha256}`));
    assert.doesNotMatch(plain, /STILLFAIL_ARCHIVE/);
    // The applier the running station starts apart from itself: what it makes, or why not (exit 1).
    const out = join(data, "made.tar");
    writeFileSync(join(data, "d"), release.delta);
    assert.equal(await updateCommand(["update", "--apply-delta", "--app", app, "--delta", join(data, "d"), "--out", out], data), 0);
    assert.ok(readFileSync(out).equals(release.raw));
    const errors: string[] = [];
    const error = console.error;
    console.error = (s: string) => errors.push(s);
    try {
      writeFileSync(join(app, "station", "main.js"), "changed since");
      assert.equal(await updateCommand(["update", "--apply-delta", "--app", app, "--delta", join(data, "d"), "--out", out], data), 1);
      assert.match(errors.pop()!, /old/);
      assert.equal(await updateCommand(["update", "--apply-delta", "--app", app], data), 2);
    } finally {
      console.error = error;
    }
  });

  test("`stillfail update` hands the installer the archive a delta made", () => {
    // What `stillfail-station update` says is given to the installer only as these let it through.
    for (const file of ["stillfail", "stillfail.ps1"]) {
      const text = readFileSync(join(root, "bin", file), "utf8");
      assert.ok(text.includes("STILLFAIL_ARCHIVE"), `bin/${file} passes STILLFAIL_ARCHIVE on`);
    }
  });
});

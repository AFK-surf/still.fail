// Signed releases (docs/release-signing.md): what verifies and what does not, the release signed by
// scripts/release-sign.ts as CI signs it, and `stillfail-station update` saying what to run.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { RELEASE_KEYS, Unverified, allowed, expected, keyId, sha256, trustedKeys, verifyDesktop, verifyFeed, verifySigned } from "../src/updates/signed.ts";
import { updateCommand } from "../src/updates/command.ts";
import { platform } from "../src/updates/versions.ts";
import { KEY, OTHER, SHA_A, SHA_B, feedOf, signed, trusted, words } from "./release-fakes.ts";

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
    unverified(() => verifyFeed({ version: "0.1.1310", ...signed({ kind: "stillfail-desktop-win", version: "0.1.1310", build: 1310 }) }, trusted), /not a station release/);
    unverified(() => verifyFeed(feedOf(1310, { sha256: "nope" }), trusted), /not well formed/);
    unverified(() => expected(r, "plan9-mips"), /no build for plan9-mips/);
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

  test("the Windows desktop installer: signed, as offered, newer, these very bytes", () => {
    const bytes = Buffer.from("an installer");
    const sig = (w: object, key = KEY) => signed({ kind: "stillfail-desktop-win", version: "0.1.1310", build: 1310, file: "x.exe", sha256: sha256(bytes), size: bytes.length, ...w }, key);
    assert.equal(verifyDesktop(sig({}), bytes, "0.1.1310", 1300, trusted).build, 1310);
    unverified(() => verifyDesktop(sig({}, OTHER), bytes, "0.1.1310", 1300, trusted), /does not take/);
    unverified(() => verifyDesktop(sig({}), Buffer.from("another"), "0.1.1310", 1300, trusted), /not the one signed/);
    unverified(() => verifyDesktop(sig({}), bytes, "0.1.1320", 1300, trusted), /offered as 0\.1\.1320/);
    unverified(() => verifyDesktop(sig({}), bytes, "0.1.1310", 1310, trusted), /not newer/);
    unverified(() => verifyDesktop(sig({ kind: "stillfail-station-release" }), bytes, "0.1.1310", 1300, trusted), /not a Windows desktop release/);
    unverified(() => verifySigned({ release: "e30=", signature: "", key: keyId(KEY.raw) }, trusted), /does not verify/);
  });

  test("scripts/release-sign.ts signs a station release as stations verify it, and refuses to sign none in CI", () => {
    const dir = temp();
    // Two platforms' archives, and their Nodes as node-dist.sh keeps them: bin/node in a tarball, node.exe in
    // nodejs.org's zip.
    const node = "24.21.0";
    writeFileSync(join(dir, "mac.tar.gz"), "the mac archive");
    writeFileSync(join(dir, "win.zip"), "the windows archive");
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
    assert.deepEqual(r.builds, {
      "darwin-arm64": { sha256: hex("the mac archive"), size: 15, nodeSha256: hex("a node binary") },
      "win32-x64": { sha256: hex("the windows archive"), size: 19, nodeSha256: hex("a node.exe") },
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
    const d = verifyDesktop(JSON.parse(readFileSync(join(dir, "x.exe.sig"), "utf8")), readFileSync(join(dir, "x.exe")), "0.1.1310", 1300, trusted);
    assert.equal(d.file, "x.exe");
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
      assert.match(said.pop()!, /0\.1\.1290 比现在的 0\.1\.1300 旧/);
      assert.equal(await updateCommand(["update", "--app", app, "--beta", "--stable", "--data", data], data, trusted), 2);
    } finally {
      console.log = log;
      console.error = error;
    }
    assert.ok(asked.every((a) => a === "/stations/releases/station-beta.json"), asked.join());
  });
});

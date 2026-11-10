// Signs releases with the key in $RELEASE_SIGNING_KEY (Ed25519, PKCS#8 PEM: CI's
// `production` environment), as the station (station/src/updates/signed.ts) and the apps' core
// (client/core-ts/src/app-release.ts) verify them.
//   release-sign.ts station OUT --build N --commit SHA --node VERSION PLATFORM=ARCHIVE,NODE_DIST …
//       the station's feed (station.json): its version, and the signed words naming each platform's archive, its raw
//       form (rawSha256, rawSize: what a delta to it makes, scripts/delta.ts rawOf: the tar in the .tar.gz, the .zip
//       with every entry stored), and the Node binary in its Node (scripts/node-dist.sh's: bin/node in the tarball,
//       node.exe in nodejs.org's zip). The feed's `deltas` are not signed (what a delta makes is checked against these)
//   release-sign.ts file FILE --kind stillfail-desktop-win --build N [--raw RAW]
//       FILE.sig: the signed words naming FILE (the Windows desktop app's installer) and, given RAW (its raw form:
//       `FILE --raw RAW`, apps/mbui/windows/setup.c), `raw` {sha256, size}: what a delta to it makes, which the apps'
//       core takes from these words alone (client/core-ts src/app-release.ts winReleaseWords; scripts/release-deltas.ts)
//   release-sign.ts keygen PRIVATE_FILE
//       a new key: the private one written to PRIVATE_FILE (PEM), the public one (for RELEASE_KEYS) said
// Without a key: in CI (CI set) an error; elsewhere, with --unsigned-ok, a warning and the feed unsigned (a release for
// a dev cloud: RELEASE_DIR), no .sig. A key the station does not take (not in RELEASE_KEYS) is refused in CI.
// The key is in GitHub's `production` environment and backed up offline; its public half is in signed.ts's
// RELEASE_KEYS beside a recovery key kept offline, which signs a release replacing a lost or leaked key. To change keys,
// release one with both (signed by the old), then swap the secret. Without a key a local RELEASE_DIR release is unsigned
// and stations will not take it; `keygen` makes a test key, which STILLFAIL_RELEASE_KEYS makes a station trust.
import { spawn } from "node:child_process";
import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign } from "node:crypto";
import { createReadStream, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename } from "node:path";
import { createGunzip } from "node:zlib";
import { type Build, RELEASE_KEYS, keyId, verifySigned } from "../station/src/updates/signed.ts";
import { storedZip } from "./delta.ts";

const args = process.argv.slice(2);
const flag = (name: string) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const positional = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1]!.startsWith("--") && args[i - 1] !== "--unsigned-ok"));
const fail = (why: string): never => {
  console.error(`release-sign: ${why}`);
  process.exit(1);
};
const usage = (): never => {
  console.error("usage: release-sign.ts station OUT --build N --commit SHA --node VERSION PLATFORM=ARCHIVE,NODE_DIST… | file FILE --kind KIND --build N [--raw RAW] | keygen PRIVATE_FILE");
  process.exit(2);
};

/// The sha256 of a stream's bytes, and how many there were.
function hashOf(stream: NodeJS.ReadableStream): Promise<{ sha256: string; size: number }> {
  return new Promise((resolve, reject) => {
    const h = createHash("sha256");
    let size = 0;
    stream.on("data", (b: Buffer) => {
      h.update(b);
      size += b.length;
    });
    stream.on("error", reject);
    stream.on("end", () => resolve({ sha256: h.digest("hex"), size }));
  });
}

const hashFile = (path: string) => hashOf(createReadStream(path));

/// The sha256 and size of an archive's raw form (scripts/delta.ts rawOf), the .tar.gz's tar hashed as it is gunzipped.
async function hashRaw(path: string): Promise<{ sha256: string; size: number }> {
  if (path.endsWith(".zip")) {
    const raw = storedZip(readFileSync(path));
    return { sha256: createHash("sha256").update(raw).digest("hex"), size: raw.length };
  }
  if (!/\.(tar\.gz|tgz)$/.test(path)) fail(`${path}: not a .tar.gz nor a .zip, whose raw form is known`);
  return hashOf(createReadStream(path).pipe(createGunzip()));
}

/// The sha256 of what `program args` writes (a file out of an archive).
async function hashOut(program: string, list: string[]): Promise<string> {
  const child = spawn(program, list, { stdio: ["ignore", "pipe", "inherit"] });
  const [hashed, code] = await Promise.all([hashOf(child.stdout), new Promise<number | null>((r) => child.on("close", r))]);
  if (code !== 0 || hashed.size === 0) fail(`${program} ${list.join(" ")} did not give the file (${code})`);
  return hashed.sha256;
}

/// The Node binary in a Node of scripts/node-dist.sh: bin/node in its tarball; node.exe in nodejs.org's zip.
const nodeBinarySha = (dist: string, version: string) =>
  dist.endsWith(".zip") ? hashOut("unzip", ["-p", dist, `node-v${version}-win-x64/node.exe`]) : hashOut("tar", ["-xzOf", dist, "bin/node"]);

/// The key to sign with, and its public half (raw, base64); none when $RELEASE_SIGNING_KEY is not set.
function signingKey(): { key: ReturnType<typeof createPrivateKey>; raw: string } | null {
  const pem = process.env.RELEASE_SIGNING_KEY?.trim();
  if (!pem) return null;
  const key = createPrivateKey(pem);
  if (key.asymmetricKeyType !== "ed25519") fail(`RELEASE_SIGNING_KEY is ${key.asymmetricKeyType}, not Ed25519`);
  const raw = Buffer.from(createPublicKey(key).export({ format: "jwk" }).x as string, "base64url").toString("base64");
  const taken = RELEASE_KEYS.includes(raw);
  if (!taken && process.env.CI) fail(`RELEASE_SIGNING_KEY's public key (${raw}) is not one of the keys stations take (station/src/updates/signed.ts RELEASE_KEYS)`);
  if (!taken) console.error(`release-sign: warning: the key ${raw} is not one of RELEASE_KEYS; only a station given it (STILLFAIL_RELEASE_KEYS) takes these releases`);
  return { key, raw };
}

/// `words` signed: what verifySigned reads.
function signed(words: object, k: { key: ReturnType<typeof createPrivateKey>; raw: string }) {
  const bytes = Buffer.from(JSON.stringify(words));
  const out = { release: bytes.toString("base64"), signature: sign(null, bytes, k.key).toString("base64"), key: keyId(k.raw) };
  // Checked as a station checks it, before anyone is given it.
  verifySigned(out, new Map([[keyId(k.raw), k.raw]]));
  return out;
}

/// The key, or none (and the warning) when that is allowed here.
function keyOrNone() {
  const k = signingKey();
  if (k) return k;
  if (process.env.CI) fail("RELEASE_SIGNING_KEY is not set: CI does not publish unsigned releases (scripts/release-sign.ts)");
  if (!args.includes("--unsigned-ok")) fail("RELEASE_SIGNING_KEY is not set (--unsigned-ok: an unsigned release for a dev cloud)");
  console.error("release-sign: warning: RELEASE_SIGNING_KEY is not set: the release is not signed, and no station updates to it");
  return null;
}

const build = () => {
  const n = Number(flag("--build"));
  return Number.isSafeInteger(n) && n > 0 ? n : usage();
};

switch (positional[0]) {
  case "station": {
    const out = positional[1] ?? usage();
    const n = build();
    const commit = flag("--commit") ?? usage();
    const node = flag("--node") ?? usage();
    const version = `0.1.${n}`;
    const builds: Record<string, Required<Build>> = {};
    for (const given of positional.slice(2)) {
      const m = /^([a-z0-9-]+)=([^,]+),(.+)$/.exec(given) ?? usage();
      const [, platform, archive, dist] = m;
      const [file, raw, nodeSha256] = await Promise.all([hashFile(archive!), hashRaw(archive!), nodeBinarySha(dist!, node)]);
      if (file.size !== statSync(archive!).size) fail(`${archive} changed while it was read`);
      builds[platform!] = { ...file, nodeSha256, rawSha256: raw.sha256, rawSize: raw.size };
    }
    if (Object.keys(builds).length === 0) usage();
    const k = keyOrNone();
    const feed = { version, build: n, commit, ...(k ? signed({ kind: "stillfail-station-release", version, build: n, commit, node, builds }, k) : {}) };
    writeFileSync(out, `${JSON.stringify(feed)}\n`);
    console.error(`release-sign: ${out}: ${version}${k ? `, signed by ${keyId(k.raw)}` : ", NOT signed"} (${Object.keys(builds).join(", ")})`);
    break;
  }
  case "file": {
    const file = positional[1] ?? usage();
    const kind = flag("--kind") ?? usage();
    const n = build();
    const k = keyOrNone();
    if (!k) break;
    const rawFile = flag("--raw");
    const [{ sha256, size }, raw] = await Promise.all([hashFile(file), rawFile === undefined ? null : hashFile(rawFile)]);
    writeFileSync(`${file}.sig`, `${JSON.stringify(signed({ kind, version: `0.1.${n}`, build: n, file: basename(file), sha256, size, ...(raw ? { raw } : {}) }, k))}\n`);
    console.error(`release-sign: ${file}.sig: signed by ${keyId(k.raw)}`);
    break;
  }
  case "keygen": {
    const out = positional[1] ?? usage();
    const { privateKey, publicKey } = generateKeyPairSync("ed25519");
    writeFileSync(out, privateKey.export({ format: "pem", type: "pkcs8" }), { mode: 0o600, flag: "wx" });
    const raw = Buffer.from(publicKey.export({ format: "jwk" }).x as string, "base64url").toString("base64");
    console.log(`${raw}  (id ${keyId(raw)})`);
    break;
  }
  default:
    usage();
}

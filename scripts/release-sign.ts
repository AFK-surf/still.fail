// Signs releases (docs/release-signing.md) with the key in $RELEASE_SIGNING_KEY (Ed25519, PKCS#8 PEM: CI's
// `production` environment), as the station (station/src/updates/signed.ts) and the Windows desktop app verify them.
//   release-sign.ts station OUT --build N --commit SHA --node VERSION PLATFORM=ARCHIVE,NODE_DIST …
//       the station's feed (station.json): its version, and the signed words naming each platform's archive and the
//       Node binary in its Node (scripts/node-dist.sh's: bin/node in the tarball, node.exe in nodejs.org's zip)
//   release-sign.ts file FILE --kind stillfail-desktop-win --build N
//       FILE.sig: the signed words naming FILE (the Windows desktop app's installer)
//   release-sign.ts desktop-web FEED ARCHIVE --build N --needs M
//       the feed of the web app the beta desktop app takes without a new one (docs/desktop-web-updates.md): its
//       version, the oldest app it works in (M) and the signed words naming ARCHIVE
//   release-sign.ts keygen PRIVATE_FILE
//       a new key: the private one written to PRIVATE_FILE (PEM), the public one (for RELEASE_KEYS) said
// Without a key: in CI (CI set) an error; elsewhere, with --unsigned-ok, a warning and the feed unsigned (a release for
// a dev cloud: RELEASE_DIR), no .sig. A key the station does not take (not in RELEASE_KEYS) is refused in CI.
import { spawn } from "node:child_process";
import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign } from "node:crypto";
import { createReadStream, statSync, writeFileSync } from "node:fs";
import { basename } from "node:path";
import { RELEASE_KEYS, keyId, verifySigned } from "../station/src/updates/signed.ts";

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
  console.error("usage: release-sign.ts station OUT --build N --commit SHA --node VERSION PLATFORM=ARCHIVE,NODE_DIST… | file FILE --kind KIND --build N | desktop-web FEED ARCHIVE --build N --needs M | keygen PRIVATE_FILE");
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
  if (process.env.CI) fail("RELEASE_SIGNING_KEY is not set: CI does not publish unsigned releases (docs/release-signing.md)");
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
    const builds: Record<string, { sha256: string; size: number; nodeSha256: string }> = {};
    for (const given of positional.slice(2)) {
      const m = /^([a-z0-9-]+)=([^,]+),(.+)$/.exec(given) ?? usage();
      const [, platform, archive, dist] = m;
      const [file, nodeSha256] = await Promise.all([hashFile(archive!), nodeBinarySha(dist!, node)]);
      if (file.size !== statSync(archive!).size) fail(`${archive} changed while it was read`);
      builds[platform!] = { ...file, nodeSha256 };
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
    const { sha256, size } = await hashFile(file);
    writeFileSync(`${file}.sig`, `${JSON.stringify(signed({ kind, version: `0.1.${n}`, build: n, file: basename(file), sha256, size }, k))}\n`);
    console.error(`release-sign: ${file}.sig: signed by ${keyId(k.raw)}`);
    break;
  }
  case "desktop-web": {
    const out = positional[1] ?? usage();
    const archive = positional[2] ?? usage();
    const n = build();
    const needs = Number(flag("--needs"));
    if (!Number.isSafeInteger(needs) || needs <= 0 || needs > n) usage();
    const k = keyOrNone();
    const version = `0.1.${n}`;
    const { sha256, size } = await hashFile(archive);
    const file = basename(archive);
    const feed = { version, build: n, needs, file, ...(k ? signed({ kind: "stillfail-desktop-web", version, build: n, needs, file, sha256, size }, k) : {}) };
    writeFileSync(out, `${JSON.stringify(feed)}\n`);
    console.error(`release-sign: ${out}: ${version} for apps from 0.1.${needs}${k ? `, signed by ${keyId(k.raw)}` : ", NOT signed"}`);
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

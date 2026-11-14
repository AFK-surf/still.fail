// Signed releases for tests (scripts/release-sign.ts): a key of the tests' own, which only the stations made in tests
// take (given as `trusted`), and feeds signed by it as scripts/release-sign.ts signs them.
import { execFileSync } from "node:child_process";
import { createHash, createPublicKey, generateKeyPairSync, sign } from "node:crypto";
import { appendFileSync, cpSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { gunzipSync } from "node:zlib";
import { makeTree } from "../../scripts/delta.ts";
import { type Build, keyId } from "../src/updates/signed.ts";
import { platform } from "../src/updates/versions.ts";

const pair = () => {
  const { privateKey } = generateKeyPairSync("ed25519");
  const raw = Buffer.from(createPublicKey(privateKey).export({ format: "jwk" }).x as string, "base64url").toString("base64");
  return { privateKey, raw, pem: privateKey.export({ format: "pem", type: "pkcs8" }) as string };
};

/// The tests' release key, and another no station takes.
export const KEY = pair();
export const OTHER = pair();
export const trusted = new Map([[keyId(KEY.raw), KEY.raw]]);

/// `words` signed by `key`, as a feed carries them.
export function signed(words: object, key = KEY): { release: string; signature: string; key: string } {
  const bytes = Buffer.from(JSON.stringify(words));
  return { release: bytes.toString("base64"), signature: sign(null, bytes, key.privateKey).toString("base64"), key: keyId(key.raw) };
}

export const SHA_A = "a".repeat(64);
export const SHA_B = "b".repeat(64);

/// A station release's words: build `build`, this machine's archive hashing to `sha256` (and its Node to `nodeSha256`).
export function words(build: number, b: Partial<Build> = {}) {
  return {
    kind: "stillfail-station-release",
    version: `0.1.${build}`,
    build,
    commit: "0".repeat(40),
    node: "24.21.0",
    builds: { [platform() ?? "darwin-arm64"]: { sha256: SHA_A, size: 1, nodeSha256: SHA_B, ...b } },
  };
}

/// The feed of release `build`, signed (by `key`).
export const feedOf = (build: number, b: Partial<Build> = {}, key = KEY) => ({ version: `0.1.${build}`, build, commit: "0".repeat(40), ...signed(words(build, b), key) });

const sha = (b: Buffer) => createHash("sha256").update(b).digest("hex");

/// Bytes like a program's, the same each time (a delta to a changed copy is small; the archive is not).
export function programBytes(n: number, seed = 1): Buffer {
  const out = Buffer.alloc(n);
  for (let i = 0; i < n; i++) {
    seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
    out[i] = 32 + ((seed >>> 16) % 95);
  }
  return out;
}

/// The release after the one installed in `app` (its files as its archive had them, nothing beside them yet), as
/// scripts/station-bundle.sh lays one out and scripts/release.sh packs it: its tree (BUILD `build`, station/main.js
/// changed, a file of its own) as stillfail-station-<platform>.tar.gz in `dir`, its raw form (the tar inside), and the
/// delta from `app` to that raw form, as scripts/delta.ts makes it. `build` is what its signed words say of it.
export function nextRelease(dir: string, app: string, build = 1310) {
  const next = join(dir, "next", "stillfail");
  mkdirSync(next, { recursive: true });
  cpSync(app, next, { recursive: true });
  writeFileSync(join(next, "BUILD"), `${build}\n`);
  appendFileSync(join(next, "station", "main.js"), "\n// the next build\n");
  writeFileSync(join(next, "station", "new.js"), "a file of the next build only\n");
  const file = join(dir, `stillfail-station-${platform() ?? "darwin-arm64"}.tar.gz`);
  execFileSync("tar", ["-czf", file, "-C", join(dir, "next"), "stillfail"]);
  const archive = readFileSync(file), raw = gunzipSync(archive);
  writeFileSync(join(dir, "next.tar"), raw);
  makeTree(app, join(dir, "next.tar"), join(dir, "next.delta"));
  const delta = readFileSync(join(dir, "next.delta"));
  return {
    raw,
    delta,
    build: { sha256: sha(archive), size: archive.length, rawSha256: sha(raw), rawSize: raw.length } satisfies Partial<Build>,
    /// The feed's entry for the delta from build `from`, named `file` under /releases/.
    entry: (from: number, file = "station/next.delta", body = delta) => ({ from, file, sha256: sha(body), size: body.length }),
  };
}

/// A release's feed with `deltas` beside its signed words (as scripts/release.sh writes it).
export const withDeltas = (feed: object, deltas: object[]) => ({ ...feed, deltas: { [platform() ?? "darwin-arm64"]: deltas } });

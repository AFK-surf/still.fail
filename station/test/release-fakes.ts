// Signed releases for tests (docs/release-signing.md): a key of the tests' own, which only the stations made in tests
// take (given as `trusted`), and feeds signed by it as scripts/release-sign.ts signs them.
import { createPublicKey, generateKeyPairSync, sign } from "node:crypto";
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

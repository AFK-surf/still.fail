// The station's releases are signed (scripts/release-sign.ts): what still.fail cloud serves as releases/station.json
// (station-beta.json) carries, beside the version it always said, `release`: the release's own words (its build, and
// the sha256 and size of each platform's archive and of the Node binary each runs on), and `signature`: Ed25519 over
// those words' bytes, by the key `key` names. The cloud stores and serves them but cannot make them: a station updates
// only to a release whose words verify, and only to a newer build than its own (back to the stable channel from the
// beta excepted, which a person asks for). The installer it runs is the one in its own release, which got here verified
// (cloud/src/install.ts, bin/install.<lang>.sh), told what the archive and Node must hash to. The Windows app's
// installer is signed the same way (its .sig beside it, which the apps' core verifies: client/core-ts/src/app-release.ts),
import { createHash, createPublicKey, verify } from "node:crypto";
import { RELEASE_KEYS } from "./keys.ts";

/// The keys releases are signed with (keys.ts, which the apps' core reads too). A key is named by keyId.
/// STILLFAIL_RELEASE_KEYS (comma-separated) adds keys for a test's own releases (a dev cloud's); it is the station's
/// environment, which only the machine's user sets.
export { RELEASE_KEYS };

/// What a key is named by in what it signed: the first 16 hex digits of the sha256 of its raw bytes.
export const keyId = (raw: string) => createHash("sha256").update(Buffer.from(raw, "base64")).digest("hex").slice(0, 16);

/// The keys this station takes, by id.
export function trustedKeys(env: Record<string, string | undefined> = process.env): Map<string, string> {
  const all = [...RELEASE_KEYS.filter((k) => !k.startsWith("__")), ...(env.STILLFAIL_RELEASE_KEYS ?? "").split(",").map((s) => s.trim()).filter(Boolean)];
  return new Map(all.map((k) => [keyId(k), k]));
}

/// A platform's build: its archive's sha256 and size, its Node binary's sha256, and (from releases signed since deltas)
/// the sha256 and size of the archive's raw form, what a delta to it makes (scripts/delta.ts rawOf: the tar inside the
/// .tar.gz; Windows' zip with every entry stored), which the installer is then handed and checks instead.
export type Build = { sha256: string; size: number; nodeSha256: string; rawSha256?: string; rawSize?: number };

/// A release's signed words, as scripts/release-sign.ts writes them.
export type Release = {
  kind: "stillfail-station-release";
  version: string;
  build: number;
  commit: string;
  node: string;
  builds: Record<string, Build>;
};

export class Unverified extends Error {}

const SHA = /^[0-9a-f]{64}$/;

const publicKey = (raw: string) => createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: Buffer.from(raw, "base64").toString("base64url") }, format: "jwk" });

/// The words `signed` carries (`release`, base64), once its `signature` verifies by the key `key` names, one of
/// `trusted`. Throws Unverified otherwise.
export function verifySigned(signed: any, trusted: Map<string, string> = trustedKeys()): any {
  if (typeof signed?.release !== "string" || typeof signed?.signature !== "string") throw new Unverified("the release is not signed");
  const key = typeof signed.key === "string" ? trusted.get(signed.key) : undefined;
  if (key === undefined) throw new Unverified(`the release is signed by a key this station does not take (${String(signed.key)})`);
  const words = Buffer.from(signed.release, "base64");
  let good = false;
  try {
    good = verify(null, words, publicKey(key), Buffer.from(signed.signature, "base64"));
  } catch {}
  if (!good) throw new Unverified("the release's signature does not verify");
  try {
    return JSON.parse(words.toString("utf8"));
  } catch {
    throw new Unverified("the release's words are not JSON");
  }
}

/// The release a feed says, verified: its signature by one of the keys, its words well formed and the version they say
/// the one the feed says. Throws Unverified otherwise (a feed from before releases were signed included).
export function verifyFeed(feed: any, trusted: Map<string, string> = trustedKeys()): Release {
  const r = verifySigned(feed, trusted);
  if (r?.kind !== "stillfail-station-release" || typeof r.version !== "string" || !Number.isSafeInteger(r.build) || typeof r.builds !== "object" || r.builds === null)
    throw new Unverified("the release's words are not a station release");
  // (0.<m>.<n>: m only said, n the build; 0.1. until m was counted, the user, 2026-11-09)
  if (!new RegExp(`^0\\.\\d+\\.${r.build}$`).test(r.version) || (feed.version !== undefined && feed.version !== r.version)) throw new Unverified("the feed's version is not the signed one");
  for (const [p, b] of Object.entries<any>(r.builds)) {
    if (!SHA.test(b?.sha256 ?? "") || !SHA.test(b?.nodeSha256 ?? "") || !Number.isSafeInteger(b?.size)) throw new Unverified(`the release's ${p} build is not well formed`);
    // The raw form's words, said together or not at all (a release from before says none, and a station from before
    // takes no notice of them).
    if ((b.rawSha256 !== undefined || b.rawSize !== undefined) && (!SHA.test(b.rawSha256 ?? "") || !Number.isSafeInteger(b.rawSize) || b.rawSize < 0))
      throw new Unverified(`the release's ${p} build is not well formed`);
  }
  return r as Release;
}

/// Whether going from the release built `current` (from `installed`'s channel) to `release` on `channel` is allowed: a
/// newer build, the same one again, or an older one only back from the beta to the stable channel (a person's ask: the
/// cloud cannot switch a station's channel). Anything else would let whoever serves the feed put back an older release.
export function allowed(release: Release, current: number | null, channel: string, installed: string | null): boolean {
  if (current === null) return true;
  if (release.build >= current) return true;
  return channel === "stable" && installed === "beta";
}

/// What the installer is told to check, for this machine's build of `release`.
export function expected(release: Release, platform: string | null): Build {
  const b = platform !== null ? release.builds[platform] : undefined;
  if (!b) throw new Unverified(`the release has no build for ${platform ?? "this machine"}`);
  return b;
}

export const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

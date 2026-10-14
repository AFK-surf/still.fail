// The station's releases are signed (docs/release-signing.md): what still.fail cloud serves as releases/station.json
// (station-beta.json) carries, beside the version it always said, `release`: the release's own words (its build, and
// the sha256 and size of each platform's archive and of the Node binary each runs on), and `signature`: Ed25519 over
// those words' bytes, by a key named here. The cloud stores and serves them but cannot make them: a station updates only
// to a release whose words verify, and only to a newer build than its own (back to the stable channel from the beta
// excepted, which a person asks for). The installer it runs is the one in its own release, which got here verified
// (cloud/src/install.ts, bin/install.<lang>.sh), told what the archive and Node must hash to.
import { createHash, createPublicKey, verify } from "node:crypto";

/// The keys releases are signed with: the release key (CI's `production` environment, RELEASE_SIGNING_KEY) and a
/// recovery key kept offline, raw Ed25519 public keys in base64. STILLFAIL_RELEASE_KEYS (comma-separated) adds keys for
/// a test's own releases (a dev cloud's); it is the station's environment, which only the machine's user sets.
export const RELEASE_KEYS: Record<string, string> = {
  "release-1": "__RELEASE_KEY_1__",
};

export type Build = { sha256: string; size: number; nodeSha256: string };

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

function keys(): Map<string, string> {
  const all = new Map(Object.entries(RELEASE_KEYS).filter(([, k]) => !k.startsWith("__")));
  for (const [i, k] of (process.env.STILLFAIL_RELEASE_KEYS ?? "").split(",").map((s) => s.trim()).filter(Boolean).entries()) all.set(`env-${i}`, k);
  return all;
}

const publicKey = (raw: string) => createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: Buffer.from(raw, "base64").toString("base64url") }, format: "jwk" });

/// The release a feed says, verified: its signature by one of the keys, its words well formed and the version they say
/// the one the feed says. Throws Unverified otherwise (a feed from before releases were signed included).
export function verifyFeed(feed: any, trusted = keys()): Release {
  if (typeof feed?.release !== "string" || typeof feed?.signature !== "string") throw new Unverified("the release is not signed");
  const words = Buffer.from(feed.release, "base64");
  const signature = Buffer.from(feed.signature, "base64");
  const named = typeof feed.key === "string" ? trusted.get(feed.key) : undefined;
  const candidates = named !== undefined ? [named] : [...trusted.values()];
  if (!candidates.some((k) => verify(null, words, publicKey(k), signature))) throw new Unverified("the release's signature does not verify");
  let r: any;
  try {
    r = JSON.parse(words.toString("utf8"));
  } catch {
    throw new Unverified("the release's words are not JSON");
  }
  if (r?.kind !== "stillfail-station-release" || typeof r.version !== "string" || !Number.isInteger(r.build) || typeof r.builds !== "object" || r.builds === null)
    throw new Unverified("the release's words are not a station release");
  if (r.version !== `0.1.${r.build}` || (typeof feed.version === "string" && feed.version !== r.version)) throw new Unverified("the feed's version is not the signed one");
  for (const [p, b] of Object.entries<any>(r.builds)) {
    if (!SHA.test(b?.sha256 ?? "") || !SHA.test(b?.nodeSha256 ?? "") || !Number.isInteger(b?.size)) throw new Unverified(`the release's ${p} build is not well formed`);
  }
  return r as Release;
}

/// Whether going from the release built `current` (on `installed`'s channel) to `release` on `channel` is allowed: a
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

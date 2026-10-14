// The station's releases are signed (docs/release-signing.md): what still.fail cloud serves as releases/station.json
// (station-beta.json) carries, beside the version it always said, `release`: the release's own words (its build, and
// the sha256 and size of each platform's archive and of the Node binary each runs on), and `signature`: Ed25519 over
// those words' bytes, by the key `key` names. The cloud stores and serves them but cannot make them: a station updates
// only to a release whose words verify, and only to a newer build than its own (back to the stable channel from the
// beta excepted, which a person asks for). The installer it runs is the one in its own release, which got here verified
// (cloud/src/install.ts, bin/install.<lang>.sh), told what the archive and Node must hash to. The Windows desktop app's
// installer is signed the same way (its .sig beside it: verifyDesktop).
import { createHash, createPublicKey, verify } from "node:crypto";

/// The keys releases are signed with, raw Ed25519 public keys in base64: the release key (CI's `production`
/// environment, RELEASE_SIGNING_KEY) and a recovery key kept offline. A key is named by keyId. STILLFAIL_RELEASE_KEYS
/// (comma-separated) adds keys for a test's own releases (a dev cloud's); it is the station's environment, which only
/// the machine's user sets.
export const RELEASE_KEYS: readonly string[] = [
  // release-1 (id 3c2d0f7ad7f9eca2): CI's RELEASE_SIGNING_KEY; its private key also kept in 1Password.
  "vJeYSXYJW04ANrn49w+I7nzS/8NFsh1MKwRCiJ8PVPI=",
  // recovery (id d3353d225efaaecd): kept offline (1Password) only, never in CI; signs a release that replaces release-1 should it be lost.
  "pvYJzkDfZGPRIPSLQ0jQDTXwhkwfbMsUtXxdVavugxc=",
];

/// What a key is named by in what it signed: the first 16 hex digits of the sha256 of its raw bytes.
export const keyId = (raw: string) => createHash("sha256").update(Buffer.from(raw, "base64")).digest("hex").slice(0, 16);

/// The keys this station takes, by id.
export function trustedKeys(env: Record<string, string | undefined> = process.env): Map<string, string> {
  const all = [...RELEASE_KEYS.filter((k) => !k.startsWith("__")), ...(env.STILLFAIL_RELEASE_KEYS ?? "").split(",").map((s) => s.trim()).filter(Boolean)];
  return new Map(all.map((k) => [keyId(k), k]));
}

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

/// The Windows desktop app's installer's signed words (desktop/<installer>.exe.sig).
export type DesktopRelease = { kind: "stillfail-desktop-win"; version: string; build: number; file: string; sha256: string; size: number };

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
  if (r.version !== `0.1.${r.build}` || (feed.version !== undefined && feed.version !== r.version)) throw new Unverified("the feed's version is not the signed one");
  for (const [p, b] of Object.entries<any>(r.builds)) {
    if (!SHA.test(b?.sha256 ?? "") || !SHA.test(b?.nodeSha256 ?? "") || !Number.isSafeInteger(b?.size)) throw new Unverified(`the release's ${p} build is not well formed`);
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

/// The Windows desktop app's installer `bytes`, as its .sig (`sig`, JSON) says it: signed, for the version the feed
/// offers (`version`), newer than the app's own (`current`, its build), and these very bytes. Throws Unverified
/// otherwise.
export function verifyDesktop(sig: any, bytes: Uint8Array, version: string, current: number, trusted: Map<string, string> = trustedKeys()): DesktopRelease {
  const r = verifySigned(sig, trusted);
  if (r?.kind !== "stillfail-desktop-win" || !Number.isSafeInteger(r.build) || r.version !== `0.1.${r.build}`) throw new Unverified("the words are not a Windows desktop release");
  if (r.version !== version) throw new Unverified(`the installer is signed as ${r.version}, offered as ${version}`);
  if (r.build <= current) throw new Unverified(`the installer is ${r.version}, not newer than this app`);
  if (r.size !== bytes.length || r.sha256 !== sha256(bytes)) throw new Unverified("the installer is not the one signed");
  return r as DesktopRelease;
}

export const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

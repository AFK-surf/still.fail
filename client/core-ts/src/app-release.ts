// A build of the Windows app that its updater takes only once its words verify (scripts/release-sign.ts), as the
// Electron app it took the place of took its installer: the feed's release carries the installer's .sig (`signed`, scripts/release-sign.ts file --kind
// stillfail-desktop-win), whose words say its version and build, its file, its SHA-256 and size; signed by one of the
// release keys (station/src/updates/keys.ts; or one the app's environment adds, STILLFAIL_RELEASE_KEYS, as the station's
// and the desktop app's do: a test's own releases, a dev cloud's), the same build the feed offers, the same file, hash
// and size. The host checks the installer's bytes against that hash as they come (mbui's win_update.h): what the cloud
// serves cannot put another program in the app's place.
//
// A release may offer deltas (scripts/delta.ts): `deltas`, each from one build, making `raw` (the package with its
// contents stored, which the platform's installer is then given as before) or, without it, the release's file itself
// (Android's APK). A delta only spares bytes: one malformed, or not smaller than the package, is not offered, never an
// update refused. On Windows what it makes is checked against the signed words' `raw`, never the feed's own.
import { ed25519 } from "@noble/curves/ed25519.js";
import { RELEASE_KEYS } from "../../../station/src/updates/keys.ts";
import { fromBase64, hex, sha256 } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// What a key is named by in what it signed: the first 16 hex digits of the sha256 of its raw bytes.
export function keyIdOf(raw: Uint8Array): string {
  return hex(sha256(raw)).slice(0, 16);
}

/// Why the feed's Windows release is not to be taken, "" when its signed words are it (`keys`: raw public keys, base64).
export function winReleaseUnverified(release: J, keys: readonly string[] = RELEASE_KEYS): string {
  const words = winReleaseWords(release, keys);
  return "why" in words ? words.why : "";
}

/// The feed's Windows release's signed words where they verify and are it, else why not (winReleaseUnverified's).
export function winReleaseWords(release: J, keys: readonly string[] = RELEASE_KEYS): { words: J } | { why: string } {
  const why = (why: string) => ({ why });
  const signed = release?.signed;
  if (typeof signed?.release !== "string" || typeof signed?.signature !== "string") return why("the release is not signed");
  const raw = keys.map((k) => fromBase64(k)).find((k) => k !== null && keyIdOf(k) === signed.key);
  if (!raw) return why(`the release is signed by a key this app does not take (${String(signed.key)})`);
  const words = fromBase64(signed.release), signature = fromBase64(signed.signature);
  if (!words || !signature) return why("the release's signature is not base64");
  let good = false;
  try {
    good = ed25519.verify(signature, words, raw);
  } catch {}
  if (!good) return why("the release's signature does not verify");
  let r: J;
  try {
    r = JSON.parse(new TextDecoder().decode(words));
  } catch {
    return why("the release's words are not JSON");
  }
  if (r?.kind !== "stillfail-desktop-win" || !Number.isSafeInteger(r.build) || !new RegExp(`^0\\.\\d+\\.${r.build}$`).test(r.version)) return why("the words are not a Windows release");
  if (r.build !== release.versionCode) return why(`the installer is signed as ${r.version}, offered as build ${release.versionCode}`);
  const file = String(release.file ?? "").split("/").pop();
  if (r.file !== file || r.sha256 !== release.sha256 || r.size !== release.size) return why("the feed's installer is not the one signed");
  return { words: r };
}

/// A delta the feed offers: from build `from`, its file under /releases/.
export type FeedDelta = { from: number; file: string; sha256: string; size: number };
/// What a release's deltas make, and which there are (none: the list empty).
export type Deltas = { makesSha256: string; makesSize: number; deltas: readonly FeedDelta[] };
/// The answer's `delta` (AppDelta): the one from the asking build.
export type AppDelta = { file: string; sha256: string; size: number; makesSha256: string; makesSize: number };

const SHA256 = /^[0-9a-f]{64}$/;
const FILE = /^[A-Za-z0-9._/-]+$/;
const positive = (n: unknown): n is number => typeof n === "number" && Number.isSafeInteger(n) && n > 0;
/// `{sha256, size}` as it should be, else null.
function made(v: J): { sha256: string; size: number } | null {
  return typeof v?.sha256 === "string" && SHA256.test(v.sha256) && positive(v.size) ? { sha256: v.sha256, size: v.size } : null;
}

/// The deltas the feed `feed` offers for its release `release` (conformed), each well made and smaller than the package;
/// what they make: `signedRaw` where given (Windows: its signed words' `raw`, null where they have none, and then no
/// delta), else the feed's `raw`, else the release's file itself.
export function feedDeltas(feed: J, release: J, signedRaw?: J): Deltas {
  const makes = signedRaw !== undefined ? made(signedRaw) : feed?.raw !== undefined ? made(feed.raw) : made(release);
  const list: J[] = Array.isArray(feed?.deltas) ? feed.deltas : [];
  if (makes === null || !positive(release?.size)) return { makesSha256: "", makesSize: 0, deltas: [] };
  const deltas: FeedDelta[] = [];
  for (const d of list) {
    const file = d?.file;
    const well = positive(d?.from) && typeof file === "string" && FILE.test(file) && !file.startsWith("/") && !file.split("/").includes("..") && made(d) !== null;
    if (well && d.size < release.size) deltas.push({ from: d.from, file, sha256: d.sha256, size: d.size });
  }
  return { makesSha256: makes.sha256, makesSize: makes.size, deltas };
}

/// The delta from build `version`, none where there is none.
export function deltaFrom(deltas: Deltas | null, version: number): AppDelta | null {
  const d = deltas?.deltas.find((d) => d.from === version);
  return d === undefined ? null : { file: d.file, sha256: d.sha256, size: d.size, makesSha256: deltas!.makesSha256, makesSize: deltas!.makesSize };
}

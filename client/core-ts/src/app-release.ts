// A build of the Windows app that its updater takes only once its words verify (docs/release-signing.md), as still.fail's
// desktop app took its installer (apps/desktop main.ts verifyWindowsUpdates, station/src/updates/signed.ts
// verifyDesktop): the feed's release carries the installer's .sig (`signed`, scripts/release-sign.ts file --kind
// stillfail-desktop-win), whose words say its version and build, its file, its SHA-256 and size; signed by one of the
// release keys (station/src/updates/keys.ts), the same build the feed offers, the same file, hash and size. The host
// checks the installer's bytes against that hash as they come (mbui's win_update.h): what the cloud serves cannot put
// another program in the app's place.
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
  const signed = release?.signed;
  if (typeof signed?.release !== "string" || typeof signed?.signature !== "string") return "the release is not signed";
  const raw = keys.map((k) => fromBase64(k)).find((k) => k !== null && keyIdOf(k) === signed.key);
  if (!raw) return `the release is signed by a key this app does not take (${String(signed.key)})`;
  const words = fromBase64(signed.release), signature = fromBase64(signed.signature);
  if (!words || !signature) return "the release's signature is not base64";
  let good = false;
  try {
    good = ed25519.verify(signature, words, raw);
  } catch {}
  if (!good) return "the release's signature does not verify";
  let r: J;
  try {
    r = JSON.parse(new TextDecoder().decode(words));
  } catch {
    return "the release's words are not JSON";
  }
  if (r?.kind !== "stillfail-desktop-win" || !Number.isSafeInteger(r.build) || r.version !== `0.1.${r.build}`) return "the words are not a Windows release";
  if (r.build !== release.versionCode) return `the installer is signed as ${r.version}, offered as 0.1.${release.versionCode}`;
  const file = String(release.file ?? "").split("/").pop();
  if (r.file !== file || r.sha256 !== release.sha256 || r.size !== release.size) return "the feed's installer is not the one signed";
  return "";
}

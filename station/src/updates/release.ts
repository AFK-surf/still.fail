// What updating the station runs, from the pages (updates.ts) and from `stillfail update` (command.ts) alike
// (scripts/release-sign.ts): the channel's feed read and its release verified (signed.ts), refused when it would put an
// older release back, and the installer this release carries (bin/install.<lang>.<sh|ps1>) told where the release is
// and what it and its Node must hash to.
// A delta: when the verified release says its archive's raw form (rawSha256, rawSize) and the feed lists a delta from the
// build this station runs (`deltas`, not signed: what it makes is checked against the signed hash), the delta is
// downloaded and applied to the installed release, and the installer is handed what it made (STILLFAIL_ARCHIVE, where it
// takes a handed archive from) with the raw form's hash to check instead of the archive's. Anything wrong with it is a
// line in the log, and the installer downloads the whole archive as without one.
import { spawn } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { createReadStream, createWriteStream, existsSync } from "node:fs";
import { mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { type Lang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { platform as machine } from "../platform/index.ts";
import { type Build, type Release, Unverified, allowed, expected, trustedKeys, verifyFeed } from "./signed.ts";
import { type Channel, feed, platform, stationVersion } from "./versions.ts";

const UA = { "user-agent": "stillfail-station" };

/// The feed of `channel` at `base` (where the releases are: the cloud's origin, Comma's /stations), as served.
export async function readFeed(channel: Channel, base: string, ms = 15_000): Promise<any> {
  const url = feed(channel, base);
  const response = await fetch(url, { headers: UA, signal: AbortSignal.timeout(ms) });
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  return response.json();
}

/// The release `said` (a feed as served) names, verified; null when it does not verify (said in the log by the caller:
/// `why`).
export function verifiedOrNull(said: any, trusted = trustedKeys()): { release: Release | null; why: string | null } {
  try {
    return { release: verifyFeed(said, trusted), why: null };
  } catch (e) {
    if (e instanceof Unverified) return { release: null, why: e.message };
    throw e;
  }
}

/// The installer `app` carries for this machine, in `lang`.
export const bundledInstaller = (app: string, lang: Lang) => join(app, "bin", `install.${lang}.${machine.installerExt}`);

/// A delta the feed lists for this machine from the build it runs, with what it must make (the signed raw form).
export type Delta = { from: number; url: string; sha256: string; size: number; rawSha256: string; rawSize: number };

export type Plan = {
  release: Release;
  /// The installer to run (the one this release carries).
  script: string;
  /// What it is told (beside the station's own STILLFAIL_DATA): where the releases are, the channel, what the archive
  /// and Node must hash to, the language it speaks.
  env: Record<string, string>;
  /// The delta to try first (takeDelta), when there is one.
  delta: Delta | null;
};

const SHA = /^[0-9a-f]{64}$/;
/// A file under /releases/: '/'-separated names, none of them "." or "..".
const FILE = /^(?!.*(^|\/)\.\.?(\/|$))[A-Za-z0-9._-]+(\/[A-Za-z0-9._-]+)*$/;

/// The delta `said` (a feed as served) lists for `platform` from build `current`, when `build` (verified) says the raw
/// form it makes; null otherwise, and for one not well formed or no smaller than the archive itself.
export function deltaFor(said: any, build: Build, platform: string | null, current: number | null, base: string): Delta | null {
  if (current === null || platform === null || build.rawSha256 === undefined || build.rawSize === undefined) return null;
  const list = said?.deltas?.[platform];
  if (!Array.isArray(list)) return null;
  const d = list.find((d: any) => d?.from === current);
  if (d === undefined || typeof d.file !== "string" || !FILE.test(d.file) || !SHA.test(d.sha256 ?? "") || !Number.isSafeInteger(d.size) || d.size <= 0) return null;
  if (d.size >= build.size) return null;
  return { from: current, url: `${base}/releases/${d.file}`, sha256: d.sha256, size: d.size, rawSha256: build.rawSha256, rawSize: build.rawSize };
}

/// What updating the station of `app` (from `installed`'s channel) to `channel`'s latest at `base` runs. Refusals are
/// thrown in `lang`: a feed that does not verify, an older release (but back to the stable one from the beta), none
/// for this machine, no installer in this release.
export async function planUpdate(o: { base: string; channel: Channel; app: string; installed: Channel; lang: Lang; trusted?: Map<string, string> }): Promise<Plan> {
  const said = await readFeed(o.channel, o.base);
  const { release, why } = verifiedOrNull(said, o.trusted);
  if (release === null) throw new Error(tr(o.lang, "station.updates.unverified", { why }));
  const version = stationVersion(o.app) ?? null;
  const current = version === null ? null : Number(/^0\.\d+\.(\d+)$/.exec(version)?.[1] ?? NaN);
  if (!allowed(release, current, o.channel, o.installed)) throw new Error(tr(o.lang, "station.updates.older", { version: release.version, current: version }));
  let build;
  try {
    build = expected(release, platform());
  } catch {
    throw new Error(tr(o.lang, "station.updates.noBuild", { version: release.version }));
  }
  const script = bundledInstaller(o.app, o.lang);
  if (!existsSync(script)) throw new Error(tr(o.lang, "station.updates.noInstaller"));
  return {
    release,
    script,
    env: {
      STILLFAIL_ORIGIN: o.base,
      STILLFAIL_CHANNEL: o.channel,
      STILLFAIL_RELEASE_SHA256: build.sha256,
      STILLFAIL_NODE_SHA256: build.nodeSha256,
      STILLFAIL_INSTALL_LANG: o.lang,
    },
    delta: deltaFor(said, build, platform(), Number.isSafeInteger(current) ? current : null, o.base),
  };
}

/// Applies the delta file `delta` to the installed release `app`, writing what it makes to `out`.
export type Applier = (app: string, delta: string, out: string, signal: AbortSignal) => Promise<void>;

/// The applier in a process apart (a station's: reading, hashing and patching tens of MB is not for its thread): the
/// release's own Node running its station's `update --apply-delta` (command.ts), or from a checkout scripts/delta.ts,
/// which applies by the same code (delta.ts). Its last line said is why it failed.
export const applyApart: Applier = (app, delta, out, signal) => {
  // (in the release, every module is main.js: import.meta.url names it)
  const here = import.meta.url;
  const args = here.endsWith(".ts")
    ? [fileURLToPath(new URL("../../../scripts/delta.ts", here)), "apply", "--old", app, "--delta", delta, "--out", out]
    : [fileURLToPath(here), "update", "--apply-delta", "--app", app, "--delta", delta, "--out", out];
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, args, { stdio: ["ignore", "ignore", "pipe"], signal, windowsHide: true });
    let said = "";
    child.stderr!.on("data", (b: Buffer) => (said = (said + b.toString("utf8")).slice(-2000)));
    child.on("error", reject);
    child.on("close", (code, sig) => (code === 0 ? resolve() : reject(new Error(said.trim().split("\n").at(-1) || `the applier ended (${code ?? sig})`))));
  });
};

/// Where the installer takes an archive it is handed from (cloud/src/install.ts, install-windows.ts): a directory of its
/// own in the temporary one, which the installer removes as it takes the archive. The file keeps the archive's name
/// though what a delta makes is its raw form: only an installer of this release or later is handed one (the one this
/// station carries runs first, then the new release's own), and both unpack either form.
function handedArchive(): { dir: string; archive: string } {
  const hex = randomBytes(16).toString("hex");
  return machine.installerExt === "ps1"
    ? { dir: join(tmpdir(), `stillfail-handed-${hex}`), archive: "stillfail.zip" }
    : { dir: join(tmpdir(), `stillfail-handed.${hex}`), archive: "stillfail.tar.gz" };
}

/// The sha256 of a file and its size, read as a stream (a release's archive: tens of MB).
function hashFile(file: string): Promise<{ sha256: string; size: number }> {
  return new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    let size = 0;
    createReadStream(file)
      .on("data", (b) => {
        hash.update(b);
        size += b.length;
      })
      .on("end", () => resolve({ sha256: hash.digest("hex"), size }))
      .on("error", reject);
  });
}

/// Downloads the delta to `to`, refused unless it is the size and sha256 the feed says.
async function download(d: Delta, to: string, signal: AbortSignal, progress: (percent: number) => void) {
  const response = await fetch(d.url, { headers: UA, signal });
  if (!response.ok || !response.body) throw new Error(`${d.url}: ${response.status}`);
  const length = response.headers.get("content-length");
  if (length !== null && Number(length) !== d.size) throw new Error(`the delta is ${length} bytes, the feed says ${d.size}`);
  const hash = createHash("sha256");
  const out = createWriteStream(to);
  let got = 0;
  let said = -1;
  try {
    for await (const chunk of response.body as unknown as AsyncIterable<Uint8Array>) {
      got += chunk.length;
      if (got > d.size) throw new Error(`the delta is more than the ${d.size} bytes the feed says`);
      hash.update(chunk);
      if (!out.write(chunk)) await new Promise<void>((r) => out.once("drain", () => r()));
      const percent = Math.floor((got * 100) / d.size);
      if (percent !== said) progress((said = percent));
    }
  } finally {
    await new Promise<void>((r, j) => out.end((e?: Error | null) => (e ? j(e) : r())));
  }
  if (got !== d.size) throw new Error(`the delta is ${got} bytes, the feed says ${d.size}`);
  if (hash.digest("hex") !== d.sha256) throw new Error("the delta's sha256 is not the feed's");
}

/// What the installer is told beside `plan.env` once the plan's delta made the release's raw archive: where it is
/// (STILLFAIL_ARCHIVE) and what it hashes to (STILLFAIL_RELEASE_SHA256, the signed raw form's). Never fails: a delta
/// not used (none, a download or an applying that failed, what it made not the signed raw form) is a line in the log,
/// what it left removed, and nothing told (the installer downloads the whole archive, checked against its own hash).
/// `signal` ends it (the caller's deadline); `progress` hears how much of the delta is in (0–100).
export async function takeDelta(plan: Plan, o: { app: string; apply: Applier; signal: AbortSignal; progress?: (percent: number) => void }): Promise<Record<string, string>> {
  const d = plan.delta;
  if (d === null) return {};
  const { dir, archive } = handedArchive();
  const made = join(dir, archive);
  try {
    await mkdir(dir, { mode: 0o700 });
    const file = join(dir, "delta");
    await download(d, file, o.signal, o.progress ?? (() => {}));
    await o.apply(o.app, file, made, o.signal);
    await rm(file, { force: true });
    o.signal.throwIfAborted();
    const got = await hashFile(made);
    if (got.size !== d.rawSize || got.sha256 !== d.rawSha256) throw new Error(`what it made (${got.size} bytes) is not the release's signed raw archive`);
    log.info("updates", "the release made from a delta", { from: d.from, delta: d.size, archive: d.rawSize });
    return { STILLFAIL_ARCHIVE: made, STILLFAIL_RELEASE_SHA256: d.rawSha256 };
  } catch (e) {
    await rm(dir, { recursive: true, force: true }).catch(() => {});
    log.warn("updates", "the delta not used: the installer downloads the whole release", { from: d.from, url: d.url, why: (e as Error).message });
    return {};
  }
}

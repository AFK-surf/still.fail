// What updating the station runs, from the pages (updates.ts) and from `stillfail update` (command.ts) alike
// (docs/release-signing.md): the channel's feed read and its release verified (signed.ts), refused when it would put an
// older release back, and the installer this release carries (bin/install.<lang>.<sh|ps1>) told where the release is
// and what it and its Node must hash to.
import { existsSync } from "node:fs";
import { join } from "node:path";
import { type Lang, tr } from "../ops/i18n.ts";
import { platform as machine } from "../platform/index.ts";
import { type Release, Unverified, allowed, expected, trustedKeys, verifyFeed } from "./signed.ts";
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

export type Plan = {
  release: Release;
  /// The installer to run (the one this release carries).
  script: string;
  /// What it is told (beside the station's own STILLFAIL_DATA): where the releases are, the channel, what the archive
  /// and Node must hash to, the language it speaks.
  env: Record<string, string>;
};

/// What updating the station of `app` (from `installed`'s channel) to `channel`'s latest at `base` runs. Refusals are
/// thrown in `lang`: a feed that does not verify, an older release (but back to the stable one from the beta), none
/// for this machine, no installer in this release.
export async function planUpdate(o: { base: string; channel: Channel; app: string; installed: Channel; lang: Lang; trusted?: Map<string, string> }): Promise<Plan> {
  const { release, why } = verifiedOrNull(await readFeed(o.channel, o.base), o.trusted);
  if (release === null) throw new Error(tr(o.lang, "station.updates.unverified", { why }));
  const version = stationVersion(o.app) ?? null;
  const current = version === null ? null : Number(version.slice("0.1.".length));
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
  };
}

import { stat } from "node:fs/promises";

/// Where the Antigravity CLI's own installer (antigravity.google/cli, its install.ps1) reads which build to download:
/// `<build>.json`, `{version, url, sha512}`.
export const AGY_MANIFESTS = "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests";

const UA = { "user-agent": "stillfail-station" };

export type AgyWatch = {
  manifests: string;
  /// The build's name in the manifests here (platform's `agyBuild`).
  build: () => Promise<string | null>;
  /// Where the installer downloads build `url` (platform's `agyStaging`).
  staging: (url: string) => string | null;
  /// Runs `f` after `ms` on the updates' clock; gives what cancels it.
  after: (ms: number, f: () => void) => () => void;
  /// How much of `version`'s build is in, as it is looked at (`total` its size).
  said: (version: string, got: number, total: number) => void;
};

/// Says how much of the Antigravity CLI's build its installer has downloaded: the build its manifest names, its size as
/// its server says it, and the file the installer writes it to, looked at twice a second until that is whole or this is
/// stopped. Gives what stops it.
export function watchAgyDownload(o: AgyWatch): () => void {
  let stopped = false;
  let next: (() => void) | null = null;
  void (async () => {
    let version: string;
    let file: string | null;
    let total: number;
    try {
      const build = await o.build();
      if (build === null) return;
      const m = await fetch(`${o.manifests}/${build}.json`, { headers: UA, signal: AbortSignal.timeout(15_000) });
      if (!m.ok) return;
      const manifest = (await m.json()) as { version?: unknown; url?: unknown };
      if (typeof manifest.version !== "string" || typeof manifest.url !== "string") return;
      version = manifest.version;
      file = o.staging(manifest.url);
      const head = await fetch(manifest.url, { method: "HEAD", headers: UA, signal: AbortSignal.timeout(15_000) });
      total = Number(head.headers.get("content-length"));
      if (!head.ok || file === null || !Number.isFinite(total) || total <= 0) return;
    } catch {
      return;
    }
    const at = file;
    const look = async () => {
      next = null;
      const got = await stat(at).then((s) => s.size, () => null);
      if (stopped) return;
      if (got !== null) o.said(version, got, total);
      if (got !== null && got >= total) return;
      // timer: a sample of this machine (another program, the installer, writing its download says nothing).
      next = o.after(500, () => void look());
    };
    if (!stopped) await look();
  })();
  return () => {
    stopped = true;
    next?.();
  };
}

// Getting a desktop app from before the rename onto the renamed one. Squirrel.Mac (the updater under electron-updater)
// only installs an update whose bundle id is the running app's and whose signature meets the running app's designated
// requirement, which names that id: an ember.app (dev.ember.desktop) cannot update to still.fail (fail.still.desktop).
// So the old feed (latest-mac.yml, which apps from before the rename read) carries this same app built under the old
// id (build.sh BRIDGE=1), and that build, finding itself under the old id, updates differently: it downloads the app
// under the new id from the new feed (stillfail-mac.yml, what the renamed app reads), checks it, and has a script put
// it in place of itself once it has quit, then open it. Its data came over already (main.ts, carryOverUserData).
import { execFile, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { createWriteStream, mkdtempSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { promisify } from "node:util";
import { net } from "electron";

/** The app's bundle id, and the one it had before the rename. */
export const APP_ID = "fail.still.desktop";
export const FORMER_APP_ID = "dev.ember.desktop";
/** The feed of the app under its new id: `<feed>/stillfail-mac.yml` (electron-builder's channel "stillfail"). */
export const CHANNEL = "stillfail";

const run = promisify(execFile);

/** A bundle's id, from its Info.plist; null when it has none to read. */
export function bundleIdOf(app: string): string | null {
  try {
    const plist = readFileSync(join(app, "Contents", "Info.plist"), "utf8");
    return /<key>CFBundleIdentifier<\/key>\s*<string>([^<]+)<\/string>/.exec(plist)?.[1] ?? null;
  } catch {
    return null;
  }
}

/** The running app's bundle (…/ember.app for …/ember.app/Contents/MacOS/<name>). */
export function ownBundle(): string {
  return dirname(dirname(dirname(process.execPath)));
}

/** The team a bundle is signed by; null when it is not signed by one (ad hoc, or not at all). */
async function teamOf(app: string): Promise<string | null> {
  try {
    const { stderr } = await run("codesign", ["-dv", app]);
    const team = /^TeamIdentifier=(.+)$/m.exec(stderr)?.[1]?.trim();
    return team && team !== "not set" ? team : null;
  } catch {
    return null;
  }
}

interface Latest { version: string; path: string; sha512: string }

/** The fields of a latest-mac.yml this needs (electron-builder writes them at the top level). */
export function parseFeed(yml: string): Latest | null {
  const field = (name: string) => new RegExp(`^${name}:\\s*['"]?([^'"\\n]+?)['"]?\\s*$`, "m").exec(yml)?.[1];
  const version = field("version");
  const path = field("path");
  const sha512 = field("sha512");
  return version && path && sha512 ? { version, path, sha512 } : null;
}

export class Bridge {
  #latest: Latest | null = null;

  /** `feed`: where the builds are (…/releases/desktop). */
  constructor(readonly feed: string) {}

  /** The app under its new id that there is, or null. */
  async check(): Promise<string | null> {
    const response = await net.fetch(`${this.feed}/${CHANNEL}-mac.yml`, { cache: "no-store" });
    if (!response.ok) throw new Error(`${CHANNEL}-mac.yml: ${response.status}`);
    this.#latest = parseFeed(await response.text());
    return this.#latest?.version ?? null;
  }

  /**
   * Downloads the app under its new id, checks it (the feed's sha512; its bundle id; signed by the same team as this
   * one, when this one is), and leaves a script waiting for this process to end, which puts it where this bundle is
   * and opens it (or opens this one again if that fails). The caller then quits the app.
   */
  async prepare(progress: (percent: number) => void): Promise<void> {
    const latest = this.#latest ?? (await this.check(), this.#latest);
    if (!latest) throw new Error("没有找到新版本");
    const dir = mkdtempSync(join(tmpdir(), "stillfail-update-"));
    const zip = join(dir, basename(latest.path));
    const response = await net.fetch(`${this.feed}/${encodeURIComponent(latest.path)}`, { cache: "no-store" });
    if (!response.ok || !response.body) throw new Error(`下载失败（${response.status}）`);
    const total = Number(response.headers.get("content-length")) || 0;
    const hash = createHash("sha512");
    const file = createWriteStream(zip);
    let got = 0;
    for await (const chunk of response.body as unknown as AsyncIterable<Uint8Array>) {
      hash.update(chunk);
      if (!file.write(chunk)) await new Promise<void>((resolve) => file.once("drain", () => resolve()));
      got += chunk.length;
      if (total) progress(Math.floor((got / total) * 100));
    }
    await new Promise<void>((resolve, reject) => file.end((error?: Error | null) => (error ? reject(error) : resolve())));
    if (hash.digest("base64") !== latest.sha512) throw new Error("下载的文件校验不对");
    const unpacked = join(dir, "app");
    await run("ditto", ["-x", "-k", zip, unpacked]);
    const found = readdirSync(unpacked).map((name) => join(unpacked, name)).find((path) => path.endsWith(".app") && bundleIdOf(path) === APP_ID);
    if (!found) throw new Error(`下载的包里没有 ${APP_ID}`);
    await run("codesign", ["--verify", "--deep", "--strict", found]).catch(() => { throw new Error("新版本的签名不对"); });
    const team = await teamOf(ownBundle());
    if (team && (await teamOf(found)) !== team) throw new Error("新版本不是同一个开发者签的");

    const current = ownBundle();
    const target = join(dirname(current), basename(found));
    const old = join(dir, "previous.app");
    // Waits for the app to be gone (a minute at most), then swaps the bundles; a failed swap puts this one back.
    const script = `
      for i in $(seq 1 120); do kill -0 ${process.pid} 2>/dev/null || break; sleep 0.5; done
      if mv "$CURRENT" "$OLD"; then
        if [ "$TARGET" != "$CURRENT" ] && [ -e "$TARGET" ]; then mv "$TARGET" "$DIR/replaced.app" || true; fi
        if mv "$FOUND" "$TARGET"; then open "$TARGET"; exit 0; fi
        mv "$OLD" "$CURRENT"
      fi
      open "$CURRENT"
    `;
    spawn("/bin/sh", ["-c", script], {
      detached: true,
      stdio: "ignore",
      env: { PATH: "/usr/bin:/bin:/usr/sbin:/sbin", CURRENT: current, OLD: old, TARGET: target, FOUND: found, DIR: dir },
    }).unref();
  }
}

// The web app the beta desktop app takes without a new app (docs/desktop-web-updates.md). What the app carries is two
// things: the web app (dist/cloud-web) and the rest, its shell (SHELL: its own code, the core, the station, what its
// bundles take from web/ and cloud/). A change to the shell is a new app (CI's desktop job); a change to the web app
// alone is a web release: its files packed (apps/desktop/src/web-archive.mts) and a feed signed saying the oldest app it
// works in, the build of the last commit that changed the shell, as only apps from then carry the shell it was made for.
//   node scripts/desktop-web.ts plan              which of the two the files on stdin change: desktop=…, desktop_web=…
//   node scripts/desktop-web.ts needs [rev]       the oldest app the web app at rev works in (its build)
//   node scripts/desktop-web.ts pack DIR --build N  dist/cloud-web as DIR/desktop/web/stillfail-beta-web-0.1.N.tar.gz
//                                                 and its feed DIR/desktop/web/stillfail-beta-web.json (scripts/release-sign.ts)
//   node scripts/desktop-web.ts check             SHELL holds every file of the repository the shell's bundles take
//                                                 (apps/desktop/build.sh's esbuild runs; apps/desktop's deps installed)
import { execFileSync } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, relative, sep } from "node:path";
import { writeArchive, type ArchivedFile } from "../apps/desktop/src/web-archive.mts";

const root = join(import.meta.dirname, "..");

/**
 * The shell: what the desktop app carries besides the web app. The app's code, the core (client/: its utility
 * process's client/core-ts, the words), the station and its native parts, the release scripts and installers, and the
 * files of web/ and cloud/ its bundles take (`check` says when one is missing).
 */
export const SHELL = new RegExp([
  "^apps/desktop/", "^client/", "^station/(src|native)/", "^station/(package\\.json|pnpm-lock\\.yaml)$", "^vendor/", "^bin/",
  "^scripts/(release|station-bundle)\\.sh$", "^\\.github/release-desktop\\.py$", "^scripts/(posthog-key|native|installers|release-sign)\\.ts$",
  "^cloud/src/(install|install-windows|i18n|previewSocket)\\.ts$",
  "^web/src/core/delta\\.ts$", "^web/src/annotate/frame\\.ts$", "^web/public/avatars/index\\.json$",
].join("|"));

/** The web app the app carries: dist/cloud-web, built from web/ with the root's packages. */
export const WEB = /^(web\/|package\.json$|pnpm-lock\.yaml$)/;

/** What the files change: the shell (a new app), or the web app alone (a web release). */
export function plan(files: string[]): { desktop: boolean; desktopWeb: boolean } {
  const desktop = files.some((f) => SHELL.test(f));
  return { desktop, desktopWeb: files.some((f) => WEB.test(f) && !SHELL.test(f)) };
}

const git = (...args: string[]) => execFileSync("git", args, { cwd: root, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });

/** The build of the newest commit on rev's first-parent line that changed the shell: the oldest app rev's web app works in. */
export function needs(rev = "HEAD"): number {
  const log = git("log", "--first-parent", "--diff-merges=first-parent", "--name-only", "--format=%x1e%H", rev);
  for (const record of log.split("\x1e").slice(1)) {
    const [commit, ...files] = record.split("\n").filter(Boolean);
    if (files.some((f) => SHELL.test(f))) return Number(git("rev-list", "--count", commit!).trim());
  }
  throw new Error(`no commit up to ${rev} changed the desktop app's shell`);
}

function filesIn(dir: string): ArchivedFile[] {
  const out: ArchivedFile[] = [];
  const walk = (at: string) => {
    for (const name of readdirSync(at)) {
      const path = join(at, name);
      if (statSync(path).isDirectory()) walk(path);
      else out.push({ path: relative(dir, path).split(sep).join("/"), bytes: readFileSync(path) });
    }
  };
  walk(dir);
  return out;
}

function pack(out: string, build: number): void {
  const web = join(root, "dist", "cloud-web");
  const about = JSON.parse(readFileSync(join(web, "build.json"), "utf8")) as { build: number };
  if (about.build !== build) throw new Error(`dist/cloud-web is the build ${about.build}, not ${build}: build it at this commit`);
  const dir = join(out, "desktop", "web");
  mkdirSync(dir, { recursive: true });
  const name = `stillfail-beta-web-0.1.${build}.tar.gz`;
  writeFileSync(join(dir, name), writeArchive(filesIn(web)));
  const oldest = needs();
  execFileSync(process.execPath, [join(root, "scripts", "release-sign.ts"), "desktop-web", join(dir, "stillfail-beta-web.json"), join(dir, name), "--build", String(build), "--needs", String(oldest), ...(process.env.RELEASE_DIR ? ["--unsigned-ok"] : [])], { stdio: "inherit" });
  console.log(`${name}: ${statSync(join(dir, name)).size} bytes, for apps from 0.1.${oldest}`);
}

/** The files of the repository the shell's bundles (apps/desktop/build.sh's esbuild runs) take. */
async function shellInputs(): Promise<string[]> {
  const desktop = join(root, "apps", "desktop");
  // apps/desktop's esbuild, the one build.sh runs (the root has none of its own).
  const esbuild = createRequire(join(desktop, "package.json"))("esbuild") as { build(options: object): Promise<{ metafile: { inputs: Record<string, unknown> } }> };
  const runs: object[] = [
    { entryPoints: ["src/main.ts", "src/core.ts", "src/preload.ts"], platform: "node", format: "cjs", external: ["electron"], outdir: "out" },
    { entryPoints: [join(root, "client/core-ts/src/hosts/node.ts")], platform: "node", format: "cjs", target: "node22", external: ["electron", "bufferutil", "utf-8-validate"], outfile: "out/core-ts.js" },
    { entryPoints: [join(root, "web/src/annotate/frame.ts")], format: "iife", outfile: "out/annotate.js" },
  ];
  const files = new Set<string>();
  for (const run of runs) {
    const result = await esbuild.build({ ...run, absWorkingDir: desktop, bundle: true, write: false, metafile: true, logLevel: "error" });
    for (const input of Object.keys(result.metafile.inputs)) {
      const path = relative(root, join(desktop, input)).split(sep).join("/");
      if (!path.includes("node_modules/") && !path.startsWith("..")) files.add(path);
    }
  }
  return [...files].sort();
}

if (import.meta.main) {
  const [command, ...rest] = process.argv.slice(2);
  if (command === "plan") {
    const { desktop, desktopWeb } = plan(readFileSync(0, "utf8").split("\n").filter(Boolean));
    console.log(`desktop=${desktop}\ndesktop_web=${desktopWeb}`);
  } else if (command === "needs") {
    console.log(needs(rest[0]));
  } else if (command === "pack") {
    const i = rest.indexOf("--build");
    const build = Number(rest[i + 1]);
    if (!rest[0] || i < 0 || !Number.isSafeInteger(build)) throw new Error("pack DIR --build N");
    pack(rest[0], build);
  } else if (command === "check") {
    const missing = (await shellInputs()).filter((f) => !SHELL.test(f));
    if (missing.length) {
      console.error(`the desktop app's shell takes these, which scripts/desktop-web.ts SHELL does not hold (a change to them would go out as a web release alone):\n  ${missing.join("\n  ")}`);
      process.exit(1);
    }
  } else {
    console.error("usage: desktop-web.ts plan | needs [rev] | pack DIR --build N | check");
    process.exit(2);
  }
}

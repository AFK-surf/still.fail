// A module's package (docs/station-modules.md): what a station installs itself when its config.json names the module by
// `package` rather than by a command. A module's directory says how it is packed, in its module.json:
//   { "id": "media", "entry": "src/main.ts", "files": [], "needsStation": 3530 }
// `entry` and all it imports are bundled by esbuild into one plain ES module, main.mjs, which the station's own Node runs
// whatever it is (the desktop app's Electron, a Node that does not strip types): node's own modules left to it, no
// timestamps, no paths but relative ones, so the same sources give the same bytes. `files` (a file, or a directory
// taken whole) are carried beside it as they are. The package is an archive of plain files for every machine
// (station/src/updates/archive.ts): main.mjs, the files, and a module.json of the same shape saying `entry: "main.mjs"`.
// A module that runs programs of its own declares them as native parts (scripts/native.ts) in `native` (the media
// service: `"native": ["ffmpeg"]`): it is then packed once per platform those parts are built for, each archive with
// the parts' files in bin/ (as the release native-artifacts has them, never built here: `native.ts fetch`) and its
// module.json saying which of them run (`bin`: the station makes those executable and tells the module where they are,
// MODULE_BIN_DIR).
// `needsStation` is the oldest station it runs beside (its build), said in the signed feed. Its version is 0.1.<build>,
// the build of the newest commit that changed what is packed (module.json, the entry's folder, the files, what its
// native parts are made of: scripts/ffmpeg.ts) or how:
// packed again at a later commit it is the same version, byte for byte, so the stable channel and the beta name one
// archive (cloud/src/releases.ts keeps it for good).
//   node scripts/module-bundle.ts list                  the modules there are (their ids), one a line
//   node scripts/module-bundle.ts plan                  whether the files on stdin change a package: modules=true|false
//   node scripts/module-bundle.ts version ID|DIR        the build its package is
//   node scripts/module-bundle.ts pack ID|DIR OUT [--beta] [--build N] [--unsigned-ok]
//       OUT/modules/<id>/<id>-0.1.<build>.tar.gz (with native parts: <id>-0.1.<build>-<platform>.tar.gz, one for each
//       platform) and its feed OUT/modules/<id>/<id>[-beta].json, signed by scripts/release-sign.ts (`module`;
//       --unsigned-ok passed on to it); their names under OUT said on stdout, on one line, the feed last
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { type ArchivedFile, safePath, writeArchive } from "../station/src/updates/archive.ts";
import { filesOf as nativeFiles, inputsOf, isPart, targetsOf } from "./native.ts";

const root = join(import.meta.dirname, "..");

/// What the package runs: the entry, bundled.
export const BUNDLE = "main.mjs";

/// How a module is packed, as its module.json says it.
export type ModuleSpec = { id: string; entry: string; files: string[]; needsStation: number; native: string[] };

/// The platforms a station runs modules on (not Windows: docs/station-modules.md).
export const PLATFORMS = ["darwin-arm64", "linux-x64", "linux-arm64"];
/// Where a package's native parts are, in it.
export const BIN = "bin";

/// The module.json of the module in `dir`, checked.
export function specOf(dir: string): ModuleSpec {
  const said = JSON.parse(readFileSync(join(dir, "module.json"), "utf8"));
  const fail = (why: string): never => {
    throw new Error(`${join(dir, "module.json")}: ${why}`);
  };
  if (typeof said?.id !== "string" || !/^[a-z][a-z0-9]{0,31}$/.test(said.id)) fail("its id is a-z and 0-9, starting with a letter, at most 32");
  if (typeof said.entry !== "string" || !safePath(said.entry)) fail("its entry is a path in it");
  if (!Array.isArray(said.files) || !said.files.every((f: unknown) => typeof f === "string" && safePath(f) && f !== BUNDLE && f !== "module.json")) fail(`its files are paths in it (not ${BUNDLE} nor module.json)`);
  if (!Number.isSafeInteger(said.needsStation) || said.needsStation <= 0) fail("needsStation is a station's build");
  const native = said.native ?? [];
  if (!Array.isArray(native) || !native.every((p: unknown) => typeof p === "string" && isPart(p))) fail("its native parts are names of scripts/native.ts's");
  if (native.length > 0 && said.files.some((f: string) => f === BIN || f.startsWith(`${BIN}/`))) fail(`its files are not in ${BIN}/, where its native parts go`);
  return { id: said.id, entry: said.entry, files: said.files, needsStation: said.needsStation, native };
}

const git = (...args: string[]) => execFileSync("git", args, { cwd: root, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();

/// The directories of the repository's modules (each one a module.json), by id.
export function modules(): Map<string, string> {
  const found = new Map<string, string>();
  for (const path of git("ls-files", "--", "*module.json").split("\n")) {
    if (path === "" || (path !== "module.json" && !path.endsWith("/module.json"))) continue;
    const dir = join(root, path.slice(0, -"module.json".length));
    const { id } = specOf(dir);
    if (found.has(id)) throw new Error(`two modules are ${id}: ${found.get(id)} and ${dir}`);
    found.set(id, dir);
  }
  return found;
}

/// A module named by its id (one of the repository's) or its directory.
const dirOf = (named: string) => (existsSync(join(named, "module.json")) ? resolve(named) : (modules().get(named) ?? fail(`no module ${named}`)));

const fail = (why: string): never => {
  console.error(`module-bundle: ${why}`);
  process.exit(1);
};

/// esbuild, the one the station is built with (station/package.json), from the station's packages.
const esbuild = () =>
  createRequire(join(root, "station", "package.json"))("esbuild") as { buildSync(options: object): { outputFiles: { contents: Uint8Array }[] } };

/// The module's entry and all it imports as one plain ES module for Node 22 and newer: node's own modules (node:*, and
/// the bare names) left to it; nothing in it says when or where it was made.
export function bundle(dir: string, spec: ModuleSpec): Uint8Array {
  const { outputFiles } = esbuild().buildSync({
    absWorkingDir: dir,
    entryPoints: [spec.entry],
    outfile: join(dir, BUNDLE),
    write: false,
    bundle: true,
    platform: "node",
    format: "esm",
    target: "node22",
    legalComments: "none",
    sourcemap: false,
    charset: "utf8",
    logLevel: "warning",
  });
  if (outputFiles.length !== 1) throw new Error(`esbuild made ${outputFiles.length} files of the module ${spec.id}`);
  return outputFiles[0]!.contents;
}

/// The platforms a module is packed for: `any` (one archive for every machine), or, with native parts, each platform
/// they are all built for.
export function platformsOf(spec: ModuleSpec): string[] {
  if (spec.native.length === 0) return ["any"];
  return PLATFORMS.filter((p) => spec.native.every((part) => targetsOf(part).includes(p)));
}

/// Where a native part is for a platform: a directory of its files. By default scripts/native.ts fetch: the cache, or
/// the release native-artifacts, never built here, so a package carries the bytes the release has.
export type Natives = (part: string, platform: string) => string;
const fetchNative: Natives = (part, platform) =>
  execFileSync(process.execPath, [join(root, "scripts", "native.ts"), "fetch", part, platform], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }).trim();

/// The files packed: the entry bundled (main.mjs), its `files` by their paths in the module's directory, its native
/// parts' files in bin/ for `platform`, and module.json saying so (and which in bin/ are run: those executable).
export function filesOf(dir: string, spec: ModuleSpec, platform = "any", natives: Natives = fetchNative): ArchivedFile[] {
  const out = new Map<string, ArchivedFile>();
  const take = (path: string) => {
    const at = join(dir, path);
    // A directory's files but those hidden (an editor's, the Finder's).
    if (!statSync(at).isDirectory()) return void out.set(path, { path, bytes: readFileSync(at) });
    for (const name of readdirSync(at)) if (!name.startsWith(".")) take(`${path}/${name}`);
  };
  for (const path of spec.files) take(path);
  out.set(BUNDLE, { path: BUNDLE, bytes: bundle(dir, spec) });
  if (spec.native.length > 0 && platform === "any") throw new Error(`the module ${spec.id} has native parts: it is packed for a platform`);
  const bin: string[] = [];
  for (const part of spec.native) {
    const at = natives(part, platform);
    for (const name of nativeFiles(part, platform)) {
      const path = `${BIN}/${name}`;
      if (out.has(path)) throw new Error(`two native parts of the module ${spec.id} have ${name}`);
      out.set(path, { path, bytes: readFileSync(join(at, name)) });
      if (statSync(join(at, name)).mode & 0o111) bin.push(name);
    }
  }
  const packed = {
    id: spec.id,
    entry: BUNDLE,
    files: [BUNDLE, ...spec.files, ...(spec.native.length > 0 ? [BIN] : [])],
    needsStation: spec.needsStation,
    ...(spec.native.length > 0 ? { native: spec.native, bin } : {}),
  };
  out.set("module.json", { path: "module.json", bytes: Buffer.from(`${JSON.stringify(packed)}\n`) });
  return [...out.values()];
}

/// What a module packs, by its paths in the module's directory: module.json, the folder of its entry (what it imports
/// is there; the whole directory for an entry at its top), its files.
const sourcesOf = (spec: ModuleSpec) => ["module.json", dirname(spec.entry) === "." ? "." : dirname(spec.entry), ...spec.files];
/// What its native parts are made of, as paths in the repository: a change to them is another build of a part (its
/// key), so a new version of the package carrying it. (Nothing else may change their keys: a part's key moving under
/// a version already out makes other bytes of it, which release.sh refuses to put.)
const nativeSourcesOf = (spec: ModuleSpec) => spec.native.flatMap((p) => inputsOf(p));

/// The build its package is: that of the newest commit on main's line that changed what is packed, or how.
export function versionOf(dir: string, spec: ModuleSpec): number {
  const own = relative(root, dir);
  if (own.startsWith("..") || isAbsolute(own)) throw new Error(`${dir} is not in the repository: say its --build`);
  const paths = sourcesOf(spec).map((p) => join(own, p).split(sep).join("/"));
  const commit = git("log", "--first-parent", "--diff-merges=first-parent", "-1", "--format=%H", "--", ...paths, ...nativeSourcesOf(spec), ...PACKING);
  if (commit === "") throw new Error(`no commit has the module ${spec.id}`);
  return Number(git("rev-list", "--count", commit));
}

/// What packs the modules besides their own files: a change to it is a new version of each.
const PACKING = ["scripts/module-bundle.ts", "station/src/updates/archive.ts", "station/pnpm-lock.yaml"];

/// Whether `files` (paths in the repository) change a module's package: what one packs, or how (its feed's signing too).
export function changes(files: string[]): boolean {
  const packed = [...modules().values()].flatMap((dir) => {
    const own = relative(root, dir).split(sep).join("/");
    const spec = specOf(dir);
    return [...sourcesOf(spec).map((p) => (own === "" ? p : p === "." ? own : `${own}/${p}`)), ...nativeSourcesOf(spec)];
  });
  return files.some((f) => [...PACKING, "scripts/release-sign.ts"].includes(f) || packed.some((p) => p === "." || f === p || f.startsWith(`${p}/`)));
}

/// Packs the module in `dir` into `out`, an archive for each of its platforms (platformsOf), and signs its feed
/// (scripts/release-sign.ts, run with `env`: the key is its RELEASE_SIGNING_KEY): the archives' names under `out`, as
/// the releases name them (station/src/modules/packages.ts archiveOf), then the feed's.
export function pack(dir: string, out: string, o: { beta: boolean; build?: number | undefined; unsignedOk: boolean; env?: NodeJS.ProcessEnv | undefined; natives?: Natives }): string[] {
  const spec = specOf(dir);
  const build = o.build ?? versionOf(dir, spec);
  const at = `modules/${spec.id}`;
  const feed = `${at}/${spec.id}${o.beta ? "-beta" : ""}.json`;
  const platforms = platformsOf(spec);
  if (platforms.length === 0) throw new Error(`the native parts of the module ${spec.id} have no platform in common`);
  mkdirSync(join(out, at), { recursive: true });
  const archives = platforms.map((platform) => {
    const archive = `${at}/${spec.id}-0.1.${build}${platform === "any" ? "" : `-${platform}`}.tar.gz`;
    writeFileSync(join(out, archive), writeArchive(filesOf(dir, spec, platform, o.natives)));
    return { platform, archive };
  });
  execFileSync(
    process.execPath,
    [
      join(root, "scripts", "release-sign.ts"), "module", join(out, feed), "--id", spec.id, "--build", String(build), "--needs-station", String(spec.needsStation),
      ...archives.map((a) => `${a.platform}=${join(out, a.archive)}`), ...(o.unsignedOk ? ["--unsigned-ok"] : []),
    ],
    { stdio: ["ignore", "ignore", "inherit"], env: o.env ?? process.env },
  );
  return [...archives.map((a) => a.archive), feed];
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const valued = (name: string) => {
    const i = args.indexOf(name);
    return i >= 0 ? args[i + 1] : undefined;
  };
  const positional = args.filter((a, i) => !a.startsWith("--") && args[i - 1] !== "--build");
  const usage = () => fail("usage: module-bundle.ts list | version ID|DIR | pack ID|DIR OUT [--beta] [--build N] [--unsigned-ok]");
  switch (positional[0]) {
    case "list":
      for (const id of modules().keys()) console.log(id);
      break;
    case "plan":
      console.log(`modules=${changes(readFileSync(0, "utf8").split("\n").filter(Boolean))}`);
      break;
    case "version": {
      const dir = dirOf(positional[1] ?? usage());
      console.log(versionOf(dir, specOf(dir)));
      break;
    }
    case "pack": {
      const dir = dirOf(positional[1] ?? usage());
      const out = positional[2] ?? usage();
      const given = valued("--build");
      const build = given === undefined ? undefined : Number(given);
      if (build !== undefined && (!Number.isSafeInteger(build) || build <= 0)) usage();
      console.log(pack(dir, out, { beta: args.includes("--beta"), build, unsignedOk: args.includes("--unsigned-ok") }).join(" "));
      break;
    }
    default:
      usage();
  }
}

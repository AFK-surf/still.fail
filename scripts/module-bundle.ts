// A module's package (docs/station-modules.md): what a station installs itself when its config.json names the module by
// `package` rather than by a command. A module's directory says how it is packed, in its module.json:
//   { "id": "media", "entry": "src/main.ts", "files": [], "needsStation": 3530 }
// `entry` and all it imports are bundled by esbuild into one plain ES module, main.mjs, which the station's own Node runs
// whatever it is (the desktop app's Electron, a Node that does not strip types): node's own modules left to it, no
// timestamps, no paths but relative ones, so the same sources give the same bytes. `files` (a file, or a directory
// taken whole) are carried beside it as they are. The package is an archive of plain files for every machine
// (station/src/updates/archive.ts): main.mjs, the files, and a module.json of the same shape saying `entry: "main.mjs"`.
// `needsStation` is the oldest station it runs beside (its build), said in the signed feed. Its version is 0.1.<build>,
// the build of the newest commit that changed what is packed (module.json, the entry's folder, the files) or how:
// packed again at a later commit it is the same version, byte for byte, so the stable channel and the beta name one
// archive (cloud/src/releases.ts keeps it for good).
//   node scripts/module-bundle.ts list                  the modules there are (their ids), one a line
//   node scripts/module-bundle.ts plan                  whether the files on stdin change a package: modules=true|false
//   node scripts/module-bundle.ts version ID|DIR        the build its package is
//   node scripts/module-bundle.ts pack ID|DIR OUT [--beta] [--build N] [--unsigned-ok]
//       OUT/modules/<id>/<id>-0.1.<build>.tar.gz and its feed OUT/modules/<id>/<id>[-beta].json, signed by
//       scripts/release-sign.ts (`module`; --unsigned-ok passed on to it); the two names under OUT said on stdout
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { type ArchivedFile, safePath, writeArchive } from "../station/src/updates/archive.ts";

const root = join(import.meta.dirname, "..");

/// What the package runs: the entry, bundled.
export const BUNDLE = "main.mjs";

/// How a module is packed, as its module.json says it.
export type ModuleSpec = { id: string; entry: string; files: string[]; needsStation: number };

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
  return { id: said.id, entry: said.entry, files: said.files, needsStation: said.needsStation };
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

/// The files packed: the entry bundled (main.mjs), its `files` by their paths in the module's directory, and module.json
/// saying so.
export function filesOf(dir: string, spec: ModuleSpec): ArchivedFile[] {
  const out = new Map<string, ArchivedFile>();
  const take = (path: string) => {
    const at = join(dir, path);
    // A directory's files but those hidden (an editor's, the Finder's).
    if (!statSync(at).isDirectory()) return void out.set(path, { path, bytes: readFileSync(at) });
    for (const name of readdirSync(at)) if (!name.startsWith(".")) take(`${path}/${name}`);
  };
  for (const path of spec.files) take(path);
  out.set(BUNDLE, { path: BUNDLE, bytes: bundle(dir, spec) });
  const packed: ModuleSpec = { id: spec.id, entry: BUNDLE, files: [BUNDLE, ...spec.files], needsStation: spec.needsStation };
  out.set("module.json", { path: "module.json", bytes: Buffer.from(`${JSON.stringify(packed)}\n`) });
  return [...out.values()];
}

/// What a module packs, by its paths in the module's directory: module.json, the folder of its entry (what it imports
/// is there; the whole directory for an entry at its top), its files.
const sourcesOf = (spec: ModuleSpec) => ["module.json", dirname(spec.entry) === "." ? "." : dirname(spec.entry), ...spec.files];

/// The build its package is: that of the newest commit on main's line that changed what is packed, or how.
export function versionOf(dir: string, spec: ModuleSpec): number {
  const own = relative(root, dir);
  if (own.startsWith("..") || isAbsolute(own)) throw new Error(`${dir} is not in the repository: say its --build`);
  const paths = sourcesOf(spec).map((p) => join(own, p).split(sep).join("/"));
  const commit = git("log", "--first-parent", "--diff-merges=first-parent", "-1", "--format=%H", "--", ...paths, ...PACKING);
  if (commit === "") throw new Error(`no commit has the module ${spec.id}`);
  return Number(git("rev-list", "--count", commit));
}

/// What packs the modules besides their own files: a change to it is a new version of each.
const PACKING = ["scripts/module-bundle.ts", "station/src/updates/archive.ts", "station/pnpm-lock.yaml"];

/// Whether `files` (paths in the repository) change a module's package: what one packs, or how (its feed's signing too).
export function changes(files: string[]): boolean {
  const packed = [...modules().values()].flatMap((dir) => {
    const own = relative(root, dir).split(sep).join("/");
    return sourcesOf(specOf(dir)).map((p) => (own === "" ? p : p === "." ? own : `${own}/${p}`));
  });
  return files.some((f) => [...PACKING, "scripts/release-sign.ts"].includes(f) || packed.some((p) => p === "." || f === p || f.startsWith(`${p}/`)));
}

/// Packs the module in `dir` into `out` and signs its feed (scripts/release-sign.ts, run with `env`: the key is its
/// RELEASE_SIGNING_KEY): the archive's and the feed's names under `out`, as the releases name them.
export function pack(dir: string, out: string, o: { beta: boolean; build?: number | undefined; unsignedOk: boolean; env?: NodeJS.ProcessEnv | undefined }): [string, string] {
  const spec = specOf(dir);
  const build = o.build ?? versionOf(dir, spec);
  const at = `modules/${spec.id}`;
  const archive = `${at}/${spec.id}-0.1.${build}.tar.gz`;
  const feed = `${at}/${spec.id}${o.beta ? "-beta" : ""}.json`;
  mkdirSync(join(out, at), { recursive: true });
  writeFileSync(join(out, archive), writeArchive(filesOf(dir, spec)));
  execFileSync(
    process.execPath,
    [join(root, "scripts", "release-sign.ts"), "module", join(out, feed), "--id", spec.id, "--build", String(build), "--needs-station", String(spec.needsStation), `any=${join(out, archive)}`, ...(o.unsignedOk ? ["--unsigned-ok"] : [])],
    { stdio: ["ignore", "ignore", "inherit"], env: o.env ?? process.env },
  );
  return [archive, feed];
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

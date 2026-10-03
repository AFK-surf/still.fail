// The native parts the TypeScript station and clients use, prebuilt (docs/development.md, "Native parts"): each one
// is named by a key, the hash of all that goes into it (its sources, as git has them, and every vendored crate it
// uses; its Cargo.lock; the Rust toolchain; the target; how it is built), and found, in this order, in
//   1. the cache on this machine, which every worktree shares: ~/Library/Caches/stillfail-native (macOS),
//      $XDG_CACHE_HOME/stillfail-native or ~/.cache/stillfail-native (Linux), or $STILLFAIL_NATIVE_CACHE;
//   2. $STILLFAIL_NATIVE_INBOX, a directory of artifacts (CI: those a branch's natives job built, as a run artifact);
//   3. the release `native-artifacts` of AFK-surf/still.fail on GitHub (public: plain HTTPS, no login), which CI
//      publishes to from main;
//   4. built here, from the checkout (and said so).
// So an everyday build or test compiles no Rust; only a change to a part's own sources builds it, once per machine.
//
//   node scripts/native.ts path <part> [target]        where it is (a directory), getting or building it first
//   node scripts/native.ts file <part> [target]        its main file (mesh.node, stillfail-runner, …)
//   node scripts/native.ts key <part> [target]         its key
//   node scripts/native.ts fetch <part> [target]       into the cache, never building (fails when not prebuilt)
//   node scripts/native.ts build <part> [target]       built here, into the cache, whatever is there
//   node scripts/native.ts run <part>… -- <command…>   the command, with each part's variable set (STILLFAIL_MESH_NATIVE, …)
//   node scripts/native.ts iroh-pkg [dir]              the web's iroh (iroh-wasm) put in web/src/core/iroh-pkg
//   node scripts/native.ts status                      every part and target: key, and whether cached / published
//   node scripts/native.ts ensure [--publish] [--outbox DIR] [part[:target]…]
//        CI: each (default: all) in the cache, built when not prebuilt; --publish uploads what the release lacks
//        (gh, main only); --outbox copies the artifacts the release lacks there (a branch's run artifact)
//   node scripts/native.ts prune [N]                   the release keeps the newest N (20) of each part and target
//
// STILLFAIL_NATIVE=build never downloads (builds what the cache lacks); STILLFAIL_NATIVE=offline neither downloads nor
// builds. Builds go to $CARGO_TARGET_DIR/native/<part> when it is set, else the crate's own target/ (a worktree's own:
// a vendored crate built from two checkouts in one target confuses rustc, docs/operations.md).
import { execFileSync, spawnSync, type SpawnSyncOptions } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import {
  copyFileSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync,
} from "node:fs";
import { homedir, hostname, platform as osPlatform, arch as osArch, tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";

const ROOT = resolve(dirname(new URL(import.meta.url).pathname), "..");
/// The Rust every part is built with (rustup installs it on first use): part of each key, so a newer one is a rebuild.
const TOOLCHAIN = "1.95.0";
/// The NDK and the lowest Android API the app supports (apps/android/build.py has the same).
const NDK = "28.2.13676358";
const ANDROID_API = 29;
/// zig, for the Linux builds from a Mac (cargo-zigbuild): only its own version builds what gets published.
const ZIG = "0.16.0";
const REPO = process.env.STILLFAIL_NATIVE_REPO ?? "AFK-surf/still.fail";
const RELEASE = process.env.STILLFAIL_NATIVE_RELEASE ?? "native-artifacts";
const VENDORED = ["vendor/iroh", "vendor/iroh-mdns-address-lookup", "vendor/noq-udp", "vendor/swarm-discovery"];

type Target = "darwin-arm64" | "linux-x64" | "linux-arm64" | "wasm32" | "android-arm64";
type Part = {
  /// What the artifact holds.
  files: (target: Target) => string[];
  targets: Target[];
  /// The targets CI publishes (default: all).
  publish?: Target[];
  /// The variable its users read its main file from (`run`).
  env?: string;
  /// What goes into it, as git paths; and how it is built, as data (both are in the key).
  inputs?: string[];
  recipe: (target: Target) => unknown;
  /// Built into `out` (a fresh directory).
  build: (target: Target, out: string) => void;
};

const host = (): Target => {
  const os = osPlatform(), cpu = osArch();
  if (os === "darwin" && cpu === "arm64") return "darwin-arm64";
  if (os === "linux" && cpu === "x64") return "linux-x64";
  if (os === "linux" && cpu === "arm64") return "linux-arm64";
  throw new Error(`no native parts for ${os}-${cpu}`);
};
const TRIPLES: Record<string, string> = {
  "darwin-arm64": "aarch64-apple-darwin",
  "linux-x64": "x86_64-unknown-linux-gnu",
  "linux-arm64": "aarch64-unknown-linux-gnu",
  "android-arm64": "aarch64-linux-android",
};
const TRIPLE = (t: Target): string => TRIPLES[t] ?? fail(`no Rust target for ${t}`);
function fail(message: string): never {
  throw new Error(message);
}
const STATION: Target[] = ["darwin-arm64", "linux-x64", "linux-arm64"];

/// A Rust crate of its own (station/native/*), for a station platform: Linux from a Mac with cargo-zigbuild, for
/// glibc 2.28 and later (Debian 10, Ubuntu 20.04, RHEL 8 on).
function stationCrate(dir: string, artifact: (t: Target) => string, name: string, extra: string[] = []): Part {
  return {
    files: () => [name],
    targets: STATION,
    inputs: [dir, ...extra],
    recipe: (t) => ({ cargo: cargoCommand(t), artifact: artifact(t), name }),
    build(t, out) {
      const target = targetDir(join(ROOT, dir, "target"), basename(dir));
      cargo(cargoCommand(t), join(ROOT, dir), { CARGO_TARGET_DIR: target });
      copyFileSync(join(target, TRIPLE(t), "release", artifact(t)), join(out, name));
    },
  };
}
const cargoCommand = (t: Target, more: string[] = []) =>
  t === "darwin-arm64"
    ? ["build", "--release", "--locked", ...more, "--target", TRIPLE(t)]
    : ["zigbuild", "--release", "--locked", ...more, "--target", `${TRIPLE(t)}.2.28`];

const PARTS: Record<string, Part> = {
  // The station's iroh and image codecs, a Node addon (docs/station-ts-native.md §3); the desktop's core uses it too.
  mesh: {
    ...stationCrate("station/native/mesh", (t) => (t === "darwin-arm64" ? "libstillfail_mesh.dylib" : "libstillfail_mesh.so"), "mesh.node", VENDORED),
    env: "STILLFAIL_MESH_NATIVE",
  },
  // The TypeScript station's launcher (§2) and an agent's runner (§1).
  launcher: { ...stationCrate("station/native/launcher", () => "stillfail-station", "stillfail-station"), env: "STILLFAIL_LAUNCHER" },
  runner: { ...stationCrate("station/native/runner", () => "stillfail-runner", "stillfail-runner"), env: "STILLFAIL_RUNNER" },
  // For the station's tests: the Rust station's cold storage as a command (test/cold-compat.test.ts), and a member's
  // client asking a station over iroh (tools/load: test/e2e.sh, compare.sh). This machine's only.
  "archive-rs": {
    ...stationCrate("station/test/archive-rs", () => "archive-rs", "archive-rs"),
    env: "ARCHIVE_RS",
    publish: ["darwin-arm64"],
  },
  "station-load": { ...stationCrate("station/tools/load", () => "station-load", "station-load", VENDORED), env: "E2E_LOAD", publish: ["darwin-arm64"] },
  // The browser's iroh (web/src/core/iroh-pkg): wasm-bindgen's module, by client/iroh-wasm/build.sh.
  "iroh-wasm": {
    files: () => ["stillfail_iroh_wasm.js", "stillfail_iroh_wasm.d.ts", "stillfail_iroh_wasm_bg.wasm", "stillfail_iroh_wasm_bg.wasm.d.ts"],
    targets: ["wasm32"],
    inputs: ["client/iroh-wasm", "client/Cargo.toml", "client/Cargo.lock", ...VENDORED],
    recipe: () => ({ script: "client/iroh-wasm/build.sh" }),
    build(_t, out) {
      const target = targetDir(join(ROOT, "client/target"), "iroh-wasm");
      rustTarget("wasm32-unknown-unknown");
      run("sh", [join(ROOT, "client/iroh-wasm/build.sh"), out], { env: rustEnv({ CARGO_TARGET_DIR: target }) });
      for (const f of ["built.js", "built.d.ts"]) rmSync(join(out, f), { force: true });
    },
  },
  // The Android core's native shell (client/shell): HTTP, the cloud's socket, files, SQLite and iroh, behind a C ABI.
  shell: {
    files: () => ["libstillfail_shell.so"],
    targets: ["android-arm64"],
    inputs: ["client/shell", "client/Cargo.toml", "client/Cargo.lock", ...VENDORED],
    recipe: () => ({ ndk: NDK, api: ANDROID_API, cargo: shellCommand(), rustflags: SHELL_RUSTFLAGS }),
    build(_t, out) {
      const target = targetDir(join(ROOT, "client/target"), "shell");
      cargo(shellCommand(), join(ROOT, "client"), { CARGO_TARGET_DIR: target, ...ndkEnv() });
      copyFileSync(join(target, "aarch64-linux-android/release/libstillfail_shell.so"), join(out, "libstillfail_shell.so"));
    },
  },
  // The Android core's engine (apps/android/core/src/main/cpp): Hermes with the JSI built beside it, linked to the
  // shell. Gradle's CMake build, as :core does it, with the release's build type.
  engine: {
    // With the NDK's C++ runtime it was linked against, which the CMake build packs.
    files: () => ["libjsi.so", "libstillfail_hermes.so", "libc++_shared.so"],
    targets: ["android-arm64"],
    inputs: ["apps/android/core/src/main/cpp", "apps/android/core/build.gradle.kts"],
    recipe: () => ({ ndk: NDK, hermes: tomlVersion("hermes"), agp: tomlVersion("agp"), task: ":core:externalNativeBuildRelease" }),
    build(_t, out) {
      const app = join(ROOT, "apps/android");
      const jni = join(app, "core/build/generated/jniLibs/arm64-v8a");
      mkdirSync(jni, { recursive: true });
      copyFileSync(join(ensure("shell", "android-arm64"), "libstillfail_shell.so"), join(jni, "libstillfail_shell.so"));
      const cxx = join(app, "core/build/intermediates/cxx");
      rmSync(cxx, { recursive: true, force: true });
      run(join(app, "gradlew"), ["-p", app, "--console=plain", "--no-watch-fs", ":core:externalNativeBuildRelease"], { env: { ...process.env, ...androidEnv() } });
      for (const name of P("engine").files("android-arm64")) {
        const found = findFile(cxx, (p) => p.endsWith(`/obj/arm64-v8a/${name}`));
        if (!found) throw new Error(`${name} is not in ${cxx}`);
        copyFileSync(found, join(out, name));
      }
    },
  },
  // iroh's relay in dev mode, for the core's mesh tests (client/core-ts/test/mesh.test.ts): n0's own build, the
  // version still.fail's relays run (cloud/Dockerfile).
  "iroh-relay": {
    files: () => ["iroh-relay"],
    targets: ["darwin-arm64", "linux-x64", "linux-arm64"],
    env: "STILLFAIL_RELAY_BIN",
    recipe: (t) => RELAY[t] ?? null,
    build(t, out) {
      const { url, sha256 } = RELAY[t] ?? fail(`no relay for ${t}`);
      const tgz = join(out, "relay.tar.gz");
      run("curl", ["-fsSL", "--retry", "5", "--retry-all-errors", url, "-o", tgz]);
      const got = createHash("sha256").update(readFileSync(tgz)).digest("hex");
      if (got !== sha256) throw new Error(`${url}: sha256 ${got}, not ${sha256}`);
      run("tar", ["-xzf", tgz, "-C", out]);
      rmSync(tgz);
    },
  },
};
const RELAY_URL = (triple: string) => `https://github.com/n0-computer/iroh/releases/download/v1.1.0/iroh-relay-v1.1.0-${triple}.tar.gz`;
const RELAY: Record<string, { url: string; sha256: string }> = {
  "darwin-arm64": { url: RELAY_URL("aarch64-apple-darwin"), sha256: "abe9606e28749b7be4b602cbf48a7795755dfe484ccc9ff6f17a9c1b3cfd5c3f" },
  "linux-x64": { url: RELAY_URL("x86_64-unknown-linux-musl"), sha256: "9a68108b824e4164ad2eec729cf0e8167e4cb50581cb745a242bace135df7614" },
  "linux-arm64": { url: RELAY_URL("aarch64-unknown-linux-musl"), sha256: "1b4261b6dd0d17ae9a7516aa6d122b296a77678bac174ce30262702c9f91cb00" },
};
const SHELL_RUSTFLAGS = "-C link-arg=-Wl,-z,max-page-size=16384";
const shellCommand = () => [
  "rustc", "--locked", "-p", "stillfail-shell", "--lib", "--crate-type", "cdylib", "--target", "aarch64-linux-android", "--release",
  // Named by its file (SONAME): the engine that links it is then given its name, not where it was built.
  "--", "-C", "link-arg=-Wl,-soname,libstillfail_shell.so",
];
const P = (name: string): Part => PARTS[name] ?? fail(`no such part: ${name} (${Object.keys(PARTS).join(", ")})`);
const defaultTarget = (part: string): Target => P(part).targets.length === 1 ? P(part).targets[0]! : host();

// ── keys ──

function git(args: string[], input?: string): string {
  return execFileSync("git", args, { cwd: ROOT, encoding: "utf8", input, maxBuffer: 64 << 20 });
}
function tomlVersion(name: string): string {
  const toml = readFileSync(join(ROOT, "apps/android/gradle/libs.versions.toml"), "utf8");
  return toml.match(new RegExp(`^${name}\\s*=\\s*"([^"]+)"`, "m"))?.[1] ?? "";
}
/// Each input file and its content's git hash: as committed or staged, and as it is in the worktree when it differs
/// there (an edit not yet committed is another key), new files not ignored included.
function inputs(paths: string[]): [string, string][] {
  if (paths.length === 0) return [];
  const files = new Map<string, string>();
  for (const line of git(["ls-files", "-s", "-z", "--", ...paths]).split("\0")) {
    if (!line) continue;
    const [meta, path] = line.split("\t");
    files.set(path!, meta!.split(" ")[1]!);
  }
  const dirty = git(["ls-files", "-m", "-o", "--exclude-standard", "-z", "--", ...paths]).split("\0").filter(Boolean);
  const present = [...new Set(dirty)].filter((p) => existsSync(join(ROOT, p)) && statSync(join(ROOT, p)).isFile());
  for (const p of dirty) if (!present.includes(p)) files.delete(p);
  if (present.length > 0) {
    const hashes = git(["hash-object", "--stdin-paths"], present.join("\n") + "\n").trim().split("\n");
    present.forEach((p, i) => files.set(p, hashes[i]!));
  }
  return [...files].sort(([a], [b]) => (a < b ? -1 : 1));
}
function key(part: string, target: Target): string {
  const p = P(part);
  const what = { part, target, toolchain: TOOLCHAIN, zig: target.startsWith("linux") ? ZIG : undefined, recipe: p.recipe(target), files: p.files(target), inputs: inputs(p.inputs ?? []) };
  return createHash("sha256").update(JSON.stringify(what)).digest("hex").slice(0, 24);
}
const asset = (part: string, target: Target, k: string) => `${part}-${target}-${k}.tar.gz`;

// ── the cache ──

const CACHE = process.env.STILLFAIL_NATIVE_CACHE ??
  (osPlatform() === "darwin" ? join(homedir(), "Library/Caches/stillfail-native") : join(process.env.XDG_CACHE_HOME ?? join(homedir(), ".cache"), "stillfail-native"));
const cached = (part: string, target: Target, k: string) => join(CACHE, part, `${target}-${k}`);
const log = (msg: string) => process.stderr.write(`native: ${msg}\n`);

/// One process at a time gets or builds a key on this machine (the others wait for it): a directory made atomically,
/// holding the pid, taken over when that process is gone.
function acquire(dir: string): () => void {
  const lock = `${dir}.lock`;
  mkdirSync(dirname(lock), { recursive: true });
  let said = false;
  for (;;) {
    try {
      mkdirSync(lock);
      writeFileSync(join(lock, "pid"), String(process.pid));
      return () => rmSync(lock, { recursive: true, force: true });
    } catch {
      let pid = 0;
      try { pid = Number(readFileSync(join(lock, "pid"), "utf8")); } catch {}
      let alive = pid > 0;
      if (alive) try { process.kill(pid, 0); } catch { alive = false; }
      // A lock just made has no pid yet (one that stays without for a minute was left by a crash); one whose holder
      // is gone is taken.
      let old = false;
      try { old = !pid && Date.now() - statSync(lock).mtimeMs > 60_000; } catch {}
      if ((!alive && pid > 0) || old) { rmSync(lock, { recursive: true, force: true }); continue; }
      if (!said) { log(`waiting for another process (${pid || "?"}) getting ${basename(dir)}`); said = true; }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 500);
    }
  }
}

/// Puts a finished directory in place of `final` (a rename: whoever looks sees all of it or nothing).
function install(tmp: string, final: string, manifest: object) {
  writeFileSync(join(tmp, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  rmSync(final, { recursive: true, force: true });
  renameSync(tmp, final);
}
function fresh(part: string): string {
  const parent = join(CACHE, part);
  mkdirSync(parent, { recursive: true });
  // What a process killed while getting one left.
  for (const name of readdirSync(parent)) {
    const pid = Number(name.match(/^\.tmp-(\d+)-/)?.[1] ?? 0);
    if (!pid || pid === process.pid) continue;
    try { process.kill(pid, 0); } catch { rmSync(join(parent, name), { recursive: true, force: true }); }
  }
  const dir = join(parent, `.tmp-${process.pid}-${randomBytes(4).toString("hex")}`);
  mkdirSync(dir);
  return dir;
}
const complete = (dir: string, part: string, target: Target) =>
  existsSync(join(dir, "manifest.json")) && P(part).files(target).every((f) => existsSync(join(dir, f)));

function unpack(tgz: string, part: string, target: Target, k: string, from: string): string {
  const tmp = fresh(part);
  run("tar", ["-xzf", tgz, "-C", tmp]);
  if (!P(part).files(target).every((f) => existsSync(join(tmp, f)))) throw new Error(`${basename(tgz)} lacks ${P(part).files(target).join(", ")}`);
  const manifest = existsSync(join(tmp, "manifest.json")) ? JSON.parse(readFileSync(join(tmp, "manifest.json"), "utf8")) : {};
  const final = cached(part, target, k);
  install(tmp, final, { ...manifest, part, target, key: k, from });
  return final;
}

async function download(part: string, target: Target, k: string): Promise<string | null> {
  const name = asset(part, target, k);
  const inbox = process.env.STILLFAIL_NATIVE_INBOX;
  if (inbox && existsSync(join(inbox, name))) {
    log(`${part} ${target} ${k}: from ${inbox}`);
    return unpack(join(inbox, name), part, target, k, "inbox");
  }
  const url = `https://github.com/${REPO}/releases/download/${RELEASE}/${name}`;
  const started = Date.now();
  let response: Response;
  try {
    response = await fetch(url, { redirect: "follow", signal: AbortSignal.timeout(300_000) });
  } catch (e) {
    log(`${part} ${target}: could not reach GitHub (${(e as Error).message})`);
    return null;
  }
  if (response.status === 404) return null;
  if (!response.ok) { log(`${part} ${target}: ${url} answered ${response.status}`); return null; }
  const bytes = Buffer.from(await response.arrayBuffer());
  const tgz = join(tmpdir(), `${name}.${process.pid}`);
  writeFileSync(tgz, bytes);
  try {
    const dir = unpack(tgz, part, target, k, url);
    log(`${part} ${target} ${k}: downloaded (${(bytes.length / 1e6).toFixed(1)} MB, ${((Date.now() - started) / 1000).toFixed(1)} s)`);
    return dir;
  } finally { rmSync(tgz, { force: true }); }
}

function buildHere(part: string, target: Target, k: string): string {
  const started = Date.now();
  log(`${part} ${target} ${k}: not prebuilt; building it here${P(part).inputs ? " (cargo)" : ""}…`);
  const tmp = fresh(part);
  try {
    P(part).build(target, tmp);
  } catch (e) {
    rmSync(tmp, { recursive: true, force: true });
    throw e;
  }
  const final = cached(part, target, k);
  install(tmp, final, { part, target, key: k, from: "built", host: hostname(), builtAt: new Date().toISOString(), toolchain: TOOLCHAIN, commit: git(["rev-parse", "HEAD"]).trim() });
  log(`${part} ${target} ${k}: built in ${((Date.now() - started) / 1000).toFixed(0)} s`);
  return final;
}

/// The part's directory in the cache: there already, downloaded, or built.
async function get(part: string, target: Target, mode: "any" | "fetch" | "build" = "any"): Promise<string> {
  const k = key(part, target);
  const dir = cached(part, target, k);
  if (mode !== "build" && complete(dir, part, target)) return dir;
  const policy = process.env.STILLFAIL_NATIVE ?? "";
  return await lockedAsync(dir, async () => {
    if (mode !== "build" && complete(dir, part, target)) return dir;
    if (mode !== "build" && policy !== "build" && policy !== "offline") {
      const got = await download(part, target, k);
      if (got) return got;
    }
    if (mode === "fetch" || policy === "offline") throw new Error(`${part} ${target} ${k} is not prebuilt (STILLFAIL_NATIVE=${policy || "-"}, ${mode})`);
    // n0's relay is downloaded from n0 whatever the policy: "building" it is that.
    return buildHere(part, target, k);
  });
}
async function lockedAsync<T>(dir: string, f: () => Promise<T>): Promise<T> {
  const release = acquire(dir);
  try { return await f(); } finally { release(); }
}
/// For the builds of other parts (the engine needs the shell): synchronously, from the cache or built.
function ensure(part: string, target: Target): string {
  const k = key(part, target);
  const dir = cached(part, target, k);
  if (complete(dir, part, target)) return dir;
  const out = execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "path", part, target], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] });
  return out.trim();
}

// ── building ──

function run(cmd: string, args: string[], options: SpawnSyncOptions = {}) {
  const done = spawnSync(cmd, args, { stdio: ["ignore", process.stderr, process.stderr], ...options });
  if (done.error) throw done.error;
  if (done.status !== 0) throw new Error(`${cmd} ${args.join(" ")}: exit ${done.status ?? done.signal}`);
}
function rustEnv(extra: Record<string, string> = {}): NodeJS.ProcessEnv {
  const home = homedir();
  return {
    ...process.env,
    PATH: [join(home, ".cargo/bin"), "/opt/homebrew/bin", process.env.PATH].join(":"),
    RUSTUP_TOOLCHAIN: TOOLCHAIN,
    CARGO_INCREMENTAL: "0",
    ...extra,
  };
}
/// The toolchain and the target, installed when missing (rustup does it once per machine).
function rustTarget(triple: string) {
  const env = rustEnv();
  const installed = spawnSync("rustup", ["target", "list", "--installed", "--toolchain", TOOLCHAIN], { env, encoding: "utf8" });
  if (installed.status !== 0) run("rustup", ["toolchain", "install", TOOLCHAIN, "--profile", "minimal"], { env });
  if (!(installed.stdout ?? "").split("\n").includes(triple)) run("rustup", ["target", "add", "--toolchain", TOOLCHAIN, triple], { env });
}
function cargo(args: string[], cwd: string, extra: Record<string, string>) {
  const env = rustEnv(extra);
  rustTarget(args[args.indexOf("--target") + 1]!.replace(/\.2\.28$/, ""));
  if (args[0] === "zigbuild") {
    const zig = spawnSync("zig", ["version"], { env, encoding: "utf8" }).stdout?.trim();
    if (zig !== ZIG) log(`zig ${zig ?? "(none)"} here, the key assumes ${ZIG}`);
  }
  run("cargo", args, { cwd, env });
}
/// Where a part's cargo build goes: the job's own target (CI sets CARGO_TARGET_DIR), a directory of its own in it.
const targetDir = (own: string, part: string) => (process.env.CARGO_TARGET_DIR ? join(process.env.CARGO_TARGET_DIR, "native", part) : own);
function androidHome(): string {
  return process.env.ANDROID_HOME ?? (osPlatform() === "darwin" ? join(homedir(), "Library/Android/sdk") : join(homedir(), "Android/Sdk"));
}
function androidEnv(): Record<string, string> {
  const env: Record<string, string> = { ANDROID_HOME: androidHome(), ANDROID_NDK_HOME: join(androidHome(), "ndk", NDK) };
  if (!process.env.JAVA_HOME && existsSync("/usr/libexec/java_home")) env.JAVA_HOME = execFileSync("/usr/libexec/java_home", { encoding: "utf8" }).trim();
  return env;
}
function ndkEnv(): Record<string, string> {
  const ndk = join(androidHome(), "ndk", NDK);
  const llvm = join(ndk, "toolchains/llvm/prebuilt", osPlatform() === "darwin" ? "darwin-x86_64" : "linux-x86_64", "bin");
  const clang = join(llvm, `aarch64-linux-android${ANDROID_API}-clang`);
  if (!existsSync(clang)) throw new Error(`Missing NDK: install ndk;${NDK} in ${androidHome()}`);
  return {
    ...androidEnv(),
    CC_aarch64_linux_android: clang,
    AR_aarch64_linux_android: join(llvm, "llvm-ar"),
    CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER: clang,
    // Android 15+ devices may use 16 KiB pages.
    CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS: SHELL_RUSTFLAGS,
  };
}
function findFile(dir: string, match: (path: string) => boolean): string | null {
  if (!existsSync(dir)) return null;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) { const f = findFile(p, match); if (f) return f; } else if (match(p)) return p;
  }
  return null;
}

// ── publishing (CI on main) ──

function gh(args: string[], options: { allowFail?: boolean } = {}): string {
  const done = spawnSync("gh", args, { encoding: "utf8", maxBuffer: 64 << 20 });
  if (done.status !== 0 && !options.allowFail) throw new Error(`gh ${args.join(" ")}: ${done.stderr}`);
  return done.status === 0 ? done.stdout : "";
}
function published(): Set<string> | null {
  const out = gh(["api", "--paginate", `repos/${REPO}/releases/tags/${RELEASE}`, "--jq", ".assets[].name"], { allowFail: true });
  return out ? new Set(out.split("\n").filter(Boolean)) : null;
}
async function exists(name: string): Promise<boolean> {
  const r = await fetch(`https://github.com/${REPO}/releases/download/${RELEASE}/${name}`, { method: "HEAD", redirect: "manual" });
  return r.status === 302 || r.status === 200;
}
function pack(dir: string, name: string, into: string): string {
  const file = join(into, name);
  run("tar", ["-czf", file, "-C", dir, "."]);
  return file;
}

// ── commands ──

const pair = (args: string[]): [string, Target] => {
  const part = args[0] ?? fail("which part?");
  P(part);
  const target = (args[1] as Target) ?? defaultTarget(part);
  if (!P(part).targets.includes(target)) throw new Error(`${part} has no target ${target} (${P(part).targets.join(", ")})`);
  return [part, target];
};
const mainFile = (part: string, target: Target, dir: string) => join(dir, P(part).files(target)[0]!);

async function main(argv: string[]) {
  const [cmd, ...args] = argv;
  switch (cmd) {
    case "key": { const [p, t] = pair(args); console.log(key(p, t)); return; }
    case "path": { const [p, t] = pair(args); console.log(await get(p, t)); return; }
    case "file": { const [p, t] = pair(args); console.log(mainFile(p, t, await get(p, t))); return; }
    case "fetch": { const [p, t] = pair(args); console.log(await get(p, t, "fetch")); return; }
    case "build": { const [p, t] = pair(args); console.log(await get(p, t, "build")); return; }
    case "run": {
      const at = args.indexOf("--");
      if (at < 1) throw new Error("usage: native.ts run <part>… -- <command…>");
      const env = { ...process.env };
      for (const part of args.slice(0, at)) {
        const [p, t] = pair([part]);
        const name = P(p).env;
        if (!name) throw new Error(`${p} has no variable`);
        if (!env[name]) env[name] = mainFile(p, t, await get(p, t));
      }
      const [command, ...rest] = args.slice(at + 1);
      const done = spawnSync(command ?? fail("no command"), rest, { stdio: "inherit", env });
      process.exit(done.status ?? 1);
    }
    case "iroh-pkg": {
      const out = resolve(args[0] ?? join(ROOT, "web/src/core/iroh-pkg"));
      const k = key("iroh-wasm", "wasm32");
      // Put there once per key: a dev server watching it sees a change only when there is one.
      if (existsSync(join(out, ".key")) && readFileSync(join(out, ".key"), "utf8").trim() === k && !existsSync(join(out, ".stand-in"))) { console.log(out); return; }
      const dir = await get("iroh-wasm", "wasm32");
      rmSync(out, { recursive: true, force: true });
      mkdirSync(out, { recursive: true });
      for (const f of P("iroh-wasm").files("wasm32")) copyFileSync(join(dir, f), join(out, f));
      // When this core was put here: a page on a newer one starts its own worker, and the older retires (web/src/core/built.ts).
      writeFileSync(join(out, "built.js"), `export const BUILT_AT = ${Date.now()};\n`);
      writeFileSync(join(out, "built.d.ts"), "export declare const BUILT_AT: number;\n");
      writeFileSync(join(out, ".key"), k + "\n");
      console.log(out);
      return;
    }
    case "status": {
      const remote = published();
      for (const [p, part] of Object.entries(PARTS)) for (const t of part.targets) {
        const k = key(p, t);
        const local = complete(cached(p, t, k), p, t) ? "cached" : "-";
        const up = remote ? (remote.has(asset(p, t, k)) ? "published" : "-") : (await exists(asset(p, t, k))) ? "published" : "-";
        console.log(`${p.padEnd(12)} ${t.padEnd(14)} ${k}  ${local.padEnd(7)} ${up}`);
      }
      return;
    }
    case "ensure": {
      let publish = false, outbox = "";
      const wanted: [string, Target][] = [];
      for (let i = 0; i < args.length; i++) {
        if (args[i] === "--publish") publish = true;
        else if (args[i] === "--outbox") outbox = args[++i] ?? fail("--outbox DIR");
        else { const [p, t] = args[i]!.split(":"); wanted.push(pair(t ? [p!, t] : [p!])); }
      }
      // Default: all of ours (n0's relay is not ours to publish).
      if (wanted.length === 0) for (const [p, part] of Object.entries(PARTS)) if (p !== "iroh-relay") for (const t of part.publish ?? part.targets) wanted.push([p, t]);
      const remote = published() ?? new Set<string>();
      if (publish && !gh(["release", "view", RELEASE, "-R", REPO, "--json", "name"], { allowFail: true })) {
        throw new Error(`the release ${RELEASE} is not on ${REPO}: make it once (docs/development.md, "Native parts")`);
      }
      const work = join(tmpdir(), `stillfail-native-${process.pid}`);
      mkdirSync(work, { recursive: true });
      if (outbox) mkdirSync(outbox, { recursive: true });
      const summary: string[] = [];
      for (const [p, t] of wanted) {
        const k = key(p, t);
        const name = asset(p, t, k);
        const there = remote.has(name);
        const before = complete(cached(p, t, k), p, t);
        const started = Date.now();
        const dir = await get(p, t);
        const took = ((Date.now() - started) / 1000).toFixed(0);
        const how = before ? "cached" : JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8")).from === "built" ? "built" : "downloaded";
        let note = "";
        if (!there && publish) {
          const file = pack(dir, name, work);
          gh(["release", "upload", RELEASE, file, "-R", REPO]);
          note = " → published";
        } else if (!there && outbox) {
          pack(dir, name, outbox);
          note = " → outbox";
        }
        summary.push(`${p} ${t} ${k}: ${how} (${took} s)${there ? ", published already" : note}`);
      }
      rmSync(work, { recursive: true, force: true });
      for (const line of summary) console.log(line);
      return;
    }
    case "prune": {
      const keep = Number(args[0] ?? 20);
      const assets = JSON.parse(gh(["api", "--paginate", `repos/${REPO}/releases/tags/${RELEASE}`, "--jq", "[.assets[] | {id, name, created_at}]"]) || "[]") as { id: number; name: string; created_at: string }[];
      const groups = new Map<string, typeof assets>();
      for (const a of assets) {
        const g = a.name.replace(/-[0-9a-f]{24}\.tar\.gz$/, "");
        groups.set(g, [...(groups.get(g) ?? []), a]);
      }
      for (const [, list] of groups) {
        list.sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
        for (const a of list.slice(keep)) { gh(["api", "-X", "DELETE", `repos/${REPO}/releases/assets/${a.id}`]); console.log(`deleted ${a.name}`); }
      }
      return;
    }
    default:
      process.stderr.write(readFileSync(new URL(import.meta.url), "utf8").split("\n").filter((l) => l.startsWith("//")).map((l) => l.slice(3)).join("\n") + "\n");
      process.exit(cmd ? 2 : 0);
  }
}

main(process.argv.slice(2)).catch((e) => {
  log((e as Error).message);
  process.exit(1);
});

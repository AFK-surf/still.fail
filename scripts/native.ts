// The native parts the TypeScript station and clients use, prebuilt (docs/development.md, "Native parts"): each one
// is named by a key, the hash of all that goes into it (its sources, as git has them, not its tests, and every vendored
// crate it uses; its Cargo.lock; the Rust toolchain; the target; how it is built), and found, in this order, in
//   1. the cache on this machine, which every worktree shares: ~/Library/Caches/stillfail-native (macOS),
//      $XDG_CACHE_HOME/stillfail-native or ~/.cache/stillfail-native (Linux), %LOCALAPPDATA%\stillfail-native (Windows),
//      or $STILLFAIL_NATIVE_CACHE;
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
//   node scripts/native.ts missing [--windows] [part[:target]…]    those (default: all of ours) the release lacks, one a line
//   node scripts/native.ts ensure [--windows] [--publish] [--outbox DIR] [part[:target]…]
//        CI: each (default: all) in the cache, built when not prebuilt; --publish uploads what the release lacks
//        (gh, main only); --outbox copies the artifacts the release lacks there (a branch's run artifact)
//        The default leaves out what only Windows builds (MSVC's: the mbui app's shell and engine); --windows is those.
//   node scripts/native.ts prune [N]                   the release keeps the newest N (20) of each part and target
//   node scripts/native.ts prebuild [--release] [part:target…]   a development machine's: each (default: the Windows
//        parts) the store (STORE: the releases bucket's natives/) lacks, got or built here (a Mac cross-builds the
//        Windows ones), then put there (scripts/release-put.sh: CLOUDFLARE_API_TOKEN, the releases bucket's), for CI to
//        fetch: CI never builds those (`msvc`), it says to prebuild them. --release: in the release native-artifacts
//        instead (gh), which native.ts fetches from after the store, for a machine without the bucket's token.
//   node scripts/native.ts store-sync                  CI on main: each prebuilt part (the Windows ones) at its key that the
//        release has and the store lacks, copied there (release-put.sh, CLOUDFLARE_API_TOKEN); never built
//
// STILLFAIL_NATIVE=build never downloads (builds what the cache lacks); STILLFAIL_NATIVE=offline neither downloads nor
// builds. Builds go to $CARGO_TARGET_DIR/native/<part> when it is set, else the crate's own target/ (a worktree's own:
// a vendored crate built from two checkouts in one target confuses rustc, docs/operations.md).
import { execFileSync, spawnSync, type SpawnSyncOptions } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import {
  copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync,
} from "node:fs";
import { homedir, hostname, platform as osPlatform, arch as osArch, tmpdir } from "node:os";
import { basename, delimiter, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as ffmpeg from "./ffmpeg.ts";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
/// The Rust every part is built with (rustup installs it on first use): part of each key, so a newer one is a rebuild.
const TOOLCHAIN = "1.95.0";
/// The NDK and the lowest Android API the app supports (apps/android/build.py has the same).
const NDK = "28.2.13676358";
const ANDROID_API = 29;
/// zig, for the Linux builds from a Mac (cargo-zigbuild): only its own version builds what gets published.
const ZIG = "0.16.0";
const REPO = process.env.STILLFAIL_NATIVE_REPO ?? "AFK-surf/still.fail";
const RELEASE = process.env.STILLFAIL_NATIVE_RELEASE ?? "native-artifacts";
/// The store of the parts prebuilt on a development machine (`prebuild`): the releases bucket's natives/, served by
/// still.fail cloud (install.ts releaseType) to anyone, as the release is by GitHub.
const STORE = process.env.STILLFAIL_NATIVE_STORE ?? "https://app.still.fail/releases/natives";
const HELPER_ICON = "apps/desktop/icon.png";
const VENDORED = ["vendor/iroh", "vendor/iroh-mdns-address-lookup", "vendor/noq-udp", "vendor/swarm-discovery"];
/// The Hermes Windows' engine is built from (there is no prebuilt one with its C++ API): facebook/hermes at the tag React
/// Native's Hermes is, the one Android's hermes-android (apps/android/gradle/libs.versions.toml `hermes`) is made from.
const HERMES = { rn: "0.81.4", tag: "hermes-2025-07-07-RNv0.81.0-e0fc67142ec0763c6b6153ca2bf96df815539782" };
/// How Hermes and the engine are built on Windows: clang-cl (MSVC's own fails on HadesGC.cpp at this tag), CMake and
/// Ninja, as a release with no debugger.
const HERMES_CMAKE = ["-G", "Ninja", "-DCMAKE_C_COMPILER=clang-cl", "-DCMAKE_CXX_COMPILER=clang-cl", "-DCMAKE_BUILD_TYPE=Release", "-DHERMES_ENABLE_DEBUGGER=OFF", "-DHERMES_ENABLE_TEST_SUITE=OFF"];
/// The bsdtar Windows has (Git Bash's GNU tar takes C:\… for a remote host).
const TAR = osPlatform() === "win32" ? join(process.env.SystemRoot ?? "C:\\Windows", "System32", "tar.exe") : "tar";

type Target = "darwin-arm64" | "linux-x64" | "linux-arm64" | "win32-x64" | "wasm32" | "android-arm64";
type Part = {
  /// What the artifact holds.
  files: (target: Target) => string[];
  targets: Target[];
  /// The targets CI publishes (default: all).
  publish?: Target[];
  /// The variable its users read its main file from (`run`).
  env?: string;
  /// What goes into it, as git paths (by target when they differ); and how it is built, as data (both are in the key).
  inputs?: string[] | ((target: Target) => string[]);
  recipe: (target: Target) => unknown;
  /// Built with no Rust: the toolchain is not in its key. With its own zig: that one is (not ZIG).
  rust?: false;
  zig?: string;
  /// Its win32-x64 is MSVC's (clang-cl's), built on a Windows machine, not MinGW's from a Mac: CI's natives-win job.
  msvc?: true;
  /// Built into `out` (a fresh directory).
  build: (target: Target, out: string) => void;
};

const host = (): Target => {
  const os = osPlatform(), cpu = osArch();
  if (os === "darwin" && cpu === "arm64") return "darwin-arm64";
  if (os === "linux" && cpu === "x64") return "linux-x64";
  if (os === "linux" && cpu === "arm64") return "linux-arm64";
  if (os === "win32" && cpu === "x64") return "win32-x64";
  throw new Error(`no native parts for ${os}-${cpu}`);
};
const TRIPLES: Record<string, string> = {
  "darwin-arm64": "aarch64-apple-darwin",
  "linux-x64": "x86_64-unknown-linux-gnu",
  "linux-arm64": "aarch64-unknown-linux-gnu",
  "win32-x64": "x86_64-pc-windows-gnu",
  "android-arm64": "aarch64-linux-android",
};
const TRIPLE = (t: Target): string => TRIPLES[t] ?? fail(`no Rust target for ${t}`);
function fail(message: string): never {
  throw new Error(message);
}
const STATION: Target[] = ["darwin-arm64", "linux-x64", "linux-arm64"];
/// The station's own executables: Windows' too (docs/station-ts-native.md, "Windows"), named as it names them.
const STATION_BINS: Target[] = [...STATION, "win32-x64"];
const exe = (name: string) => (t: Target) => (t === "win32-x64" ? `${name}.exe` : name);

/// A Rust crate of its own (station/native/*), for a station platform: Linux from a Mac with cargo-zigbuild, for
/// glibc 2.28 and later (Debian 10, Ubuntu 20.04, RHEL 8 on); Windows with it too, as MinGW's (napi-rs finds Node's
/// symbols in the process at run time, so no MSVC import library is needed). `name`: the file kept, by target.
function stationCrate(dir: string, artifact: (t: Target) => string, name: string | ((t: Target) => string), extra: string[] = []): Part {
  const named = (t: Target) => (typeof name === "string" ? name : name(t));
  return {
    files: (t) => [named(t)],
    targets: STATION,
    inputs: [dir, ...extra],
    recipe: (t) => ({ cargo: cargoCommand(t), artifact: artifact(t), name: named(t) }),
    build(t, out) {
      const target = targetDir(join(ROOT, dir, "target"), basename(dir));
      cargo(cargoCommand(t), join(ROOT, dir), { CARGO_TARGET_DIR: target, ...(t === "win32-x64" ? noLibnode(target) : {}) });
      copyFileSync(join(target, TRIPLE(t), "release", artifact(t)), join(out, named(t)));
    },
  };
}
/// napi-build links a MinGW addon to libnode.dll, which neither Node nor Electron has on Windows: their Node-API is in
/// the executable, and napi-sys (dyn-symbols, its default) looks every function up there when the addon loads. So it
/// is given an empty import library to link (nothing is taken from it) and a libnode.dll to find beside it.
function noLibnode(target: string): Record<string, string> {
  const dir = join(target, "no-libnode");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "libnode.dll"), "");
  writeFileSync(join(dir, "libnode.a"), "!<arch>\n");
  return { LIBNODE_PATH: dir };
}
const cargoCommand = (t: Target, more: string[] = []) =>
  t === "darwin-arm64"
    ? ["build", "--release", "--locked", ...more, "--target", TRIPLE(t)]
    : ["zigbuild", "--release", "--locked", ...more, "--target", t === "win32-x64" ? TRIPLE(t) : `${TRIPLE(t)}.2.28`];

/// The launcher's part: Windows' has its windowless start beside it (station/native/launcher/src/hidden.rs).
function withHidden(part: Part): Part {
  const hidden = "stillfail-station-w.exe";
  return {
    ...part,
    targets: STATION_BINS,
    env: "STILLFAIL_LAUNCHER",
    files: (t) => (t === "win32-x64" ? [...part.files(t), hidden] : part.files(t)),
    build(t, out) {
      part.build(t, out);
      if (t === "win32-x64") copyFileSync(join(targetDir(join(ROOT, "station/native/launcher/target"), "launcher"), TRIPLE(t), "release", hidden), join(out, hidden));
    },
  };
}

const MESH_LIB = (t: Target) => (t === "darwin-arm64" ? "libstillfail_mesh.dylib" : t === "win32-x64" ? "stillfail_mesh.dll" : "libstillfail_mesh.so");

const PARTS: Record<string, Part> = {
  // Windows' native maximize hit target, under the desktop page's self-drawn controls (Snap Layouts).
  "window-controls": {
    ...stationCrate("apps/desktop/window-controls", () => "stillfail_window_controls.dll", "window-controls.node"),
    targets: ["win32-x64"],
  },
  // Whether the system lets the desktop app show notifications (its notification settings show it).
  "notify-permission": {
    ...stationCrate("apps/desktop/notify-permission", (t) => (t === "win32-x64" ? "stillfail_notify_permission.dll" : "libstillfail_notify_permission.dylib"), "notify-permission.node"),
    targets: ["darwin-arm64", "win32-x64"],
  },
  // The station's iroh and image codecs, a Node addon (docs/station-ts-native.md §3); the desktop's core uses it too.
  mesh: {
    ...stationCrate("station/native/mesh", MESH_LIB, "mesh.node", VENDORED),
    // Windows for the desktop app's core and the station there.
    targets: STATION_BINS,
    env: "STILLFAIL_MESH_NATIVE",
  },
  // The TypeScript station's launcher (§2) and an agent's runner (§1).
  // On Windows with stillfail-station-w.exe beside it: the launcher as the logon task runs it, with no window.
  launcher: withHidden(stationCrate("station/native/launcher", exe("stillfail-station"), exe("stillfail-station"))),
  runner: { ...stationCrate("station/native/runner", exe("stillfail-runner"), exe("stillfail-runner")), targets: STATION_BINS, env: "STILLFAIL_RUNNER" },
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
  // The core's native shell (client/shell): HTTP, the cloud's socket, files, SQLite and iroh, behind a C ABI. Android's,
  // and the mbui app's on Windows (MSVC's: a DLL and its import library, which the engine links).
  shell: {
    // Windows': with its tests, built beside it, for a Windows machine to run (CI's natives-win)
    files: (t) => (t === "win32-x64" ? ["stillfail_shell.dll", "stillfail_shell.dll.lib", "tests"] : ["libstillfail_shell.so"]),
    targets: ["android-arm64", "win32-x64"],
    msvc: true,
    inputs: ["client/shell", "client/Cargo.toml", "client/Cargo.lock", ...VENDORED],
    recipe: (t) => (t === "win32-x64" ? { cargo: shellWinCommand(), tests: SHELL_TESTS, xwin: XWIN } : { ndk: NDK, api: ANDROID_API, cargo: shellCommand(), rustflags: SHELL_RUSTFLAGS }),
    build(t, out) {
      const target = targetDir(join(ROOT, "client/target"), "shell");
      if (t === "win32-x64") return shellWin(out);
      cargo(shellCommand(), join(ROOT, "client"), { CARGO_TARGET_DIR: target, ...ndkEnv() });
      copyFileSync(join(target, "aarch64-linux-android/release/libstillfail_shell.so"), join(out, "libstillfail_shell.so"));
    },
  },
  // The core's engine: Hermes and the core's loop on it, linked to the shell. Android's (apps/android/core/src/main/cpp):
  // Hermes with the JSI built beside it, Gradle's CMake build, as :core does it, with the release's build type. The
  // mbui app's on Windows (apps/mbui/engine): Hermes built from its source (HERMES) with clang-cl, static, in one DLL
  // with the loop, whose C API (engine.h) the app calls; with that build's hermesc, for the core's bytecode.
  engine: {
    // With the NDK's C++ runtime it was linked against, which the CMake build packs.
    files: (t) => (t === "win32-x64" ? ["stillfail_engine.dll", "stillfail_engine.lib", "hermesc.exe"] : ["libjsi.so", "libstillfail_hermes.so", "libc++_shared.so"]),
    targets: ["android-arm64", "win32-x64"],
    msvc: true,
    inputs: (t) => (t === "win32-x64" ? ["apps/mbui/engine"] : ["apps/android/core/src/main/cpp", "apps/android/core/build.gradle.kts"]),
    recipe: (t) => (t === "win32-x64" ? { hermes: HERMES, cmake: HERMES_CMAKE, targets: ["stillfail_engine", "hermesc"] } : { ndk: NDK, hermes: tomlVersion("hermes"), agp: tomlVersion("agp"), task: ":core:externalNativeBuildRelease" }),
    build(t, out) {
      if (t === "win32-x64") return engineWin(out);
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
  // The desktop app's dock (apps/desktop/dock, docs/desktop-dock.md): a SwiftUI helper, built with the Xcode the Mac
  // has (its SDK decides whether the glass is Liquid Glass: macOS 26's or later).
  dock: {
    files: () => ["StillfailDock"],
    targets: ["darwin-arm64"],
    inputs: ["apps/desktop/dock"],
    recipe: () => ({ swift: DOCK_BUILD, sdk: "macOS 26" }),
    build(_t, out) {
      const dir = join(ROOT, "apps/desktop/dock");
      const scratch = process.env.CARGO_TARGET_DIR ? join(process.env.CARGO_TARGET_DIR, "native", "dock") : join(dir, ".build");
      run("swift", [...DOCK_BUILD, "--scratch-path", scratch], { cwd: dir });
      copyFileSync(join(scratch, "arm64-apple-macosx/release/StillfailDock"), join(out, "StillfailDock"));
    },
  },
  // still.fail Helper (station/native/helper, docs/station-ts-native.md §4): the station's macOS app for what macOS
  // grants an app (the screen, docs/remote-screens.md), Swift built with the Mac's Xcode, put in its bundle with its
  // Info.plist and the desktop app's icon (its permission window and System Settings show it) and signed ad hoc (a
  // release signs it again, scripts/station-bundle.sh).
  helper: {
    files: () => [HELPER_APP],
    targets: ["darwin-arm64"],
    env: "STILLFAIL_HELPER",
    inputs: ["station/native/helper", "vendor/PermissionFlow", HELPER_ICON],
    recipe: () => ({ swift: DOCK_BUILD, app: HELPER_APP }),
    build(_t, out) {
      const dir = join(ROOT, "station/native/helper");
      const scratch = process.env.CARGO_TARGET_DIR ? join(process.env.CARGO_TARGET_DIR, "native", "helper") : join(dir, ".build");
      run("swift", [...DOCK_BUILD, "--scratch-path", scratch], { cwd: dir });
      const app = join(out, HELPER_APP);
      mkdirSync(join(app, "Contents/MacOS"), { recursive: true });
      copyFileSync(join(scratch, "arm64-apple-macosx/release/stillfail-helper"), join(app, "Contents/MacOS/stillfail-helper"));
      copyFileSync(join(dir, "Info.plist"), join(app, "Contents/Info.plist"));
      const iconset = join(out, "AppIcon.iconset");
      mkdirSync(iconset);
      for (const size of [16, 32, 128, 256, 512]) {
        for (const scale of [1, 2]) {
          const name = `icon_${size}x${size}${scale === 2 ? "@2x" : ""}.png`;
          run("sips", ["-z", String(size * scale), String(size * scale), join(ROOT, HELPER_ICON), "--out", join(iconset, name)], { stdio: ["ignore", "ignore", process.stderr] });
        }
      }
      mkdirSync(join(app, "Contents/Resources"), { recursive: true });
      run("iconutil", ["-c", "icns", iconset, "-o", join(app, "Contents/Resources/AppIcon.icns")]);
      rmSync(iconset, { recursive: true });
      writeFileSync(join(app, "Contents/PkgInfo"), "APPL????");
      run("codesign", ["--force", "--sign", "-", "--identifier", "fail.still.helper", app]);
    },
  },
  // ffmpeg and ffprobe for the media service, LGPL only, from FFmpeg's source (scripts/ffmpeg.ts: its key is that file
  // alone, and the media service's package carries it: scripts/module-bundle.ts).
  ffmpeg: {
    files: (t) => ffmpeg.files(t as ffmpeg.FfmpegTarget),
    targets: ffmpeg.TARGETS,
    env: "MEDIA_FFMPEG",
    inputs: ["scripts/ffmpeg.ts"],
    rust: false,
    zig: ffmpeg.ZIG,
    recipe: (t) => ffmpeg.recipe(t as ffmpeg.FfmpegTarget),
    build: (t, out) => ffmpeg.build(t as ffmpeg.FfmpegTarget, out),
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
const DOCK_BUILD = ["build", "-c", "release", "--arch", "arm64"];
const HELPER_APP = "still.fail Helper.app";
const SHELL_RUSTFLAGS = "-C link-arg=-Wl,-z,max-page-size=16384";
const shellCommand = () => [
  "rustc", "--locked", "-p", "stillfail-shell", "--lib", "--crate-type", "cdylib", "--target", "aarch64-linux-android", "--release",
  // Named by its file (SONAME): the engine that links it is then given its name, not where it was built.
  "--", "-C", "link-arg=-Wl,-soname,libstillfail_shell.so",
];
/// The Windows shell: the crate's cdylib (a DLL with its import library, which the engine links); and its tests, built
/// beside it, not run (a Mac builds them; CI's Windows runs them).
const shellWinCommand = () => ["rustc", "--locked", "-p", "stillfail-shell", "--lib", "--crate-type", "cdylib", "--target", "x86_64-pc-windows-msvc", "--release"];
const SHELL_TESTS = ["test", "--release", "--locked", "-p", "stillfail-shell", "--target", "x86_64-pc-windows-msvc", "--no-run", "--message-format=json-render-diagnostics"];
/// cargo-xwin, which cross-builds the Windows parts on a Mac with the Windows SDK and MSVC's CRT (Microsoft's, which it
/// downloads: xwin), clang-cl and lld-link (Homebrew's llvm and lld).
const XWIN = "0.23.1";
/// Where a development machine keeps the cross-builds' tools and output (cargo-xwin, the SDK, cargo's target, Hermes's
/// checkout and builds): beside the cache, shared by every worktree, so a change builds only what it changed.
const BUILD = () => process.env.STILLFAIL_NATIVE_BUILD ?? join(CACHE, ".build");
const LLVM = "/opt/homebrew/opt/llvm/bin";
/// cargo-xwin's environment on a Mac (installed into BUILD once): the SDK it keeps there, clang-cl first on PATH.
function xwinEnv(): { XWIN_CACHE_DIR: string; PATH: string } {
  const tools = join(BUILD(), "tools");
  const env = { XWIN_CACHE_DIR: join(BUILD(), "xwin"), PATH: [join(tools, "bin"), join(homedir(), ".cargo/bin"), LLVM, "/opt/homebrew/bin", process.env.PATH].join(delimiter) };
  if (!existsSync(join(tools, "bin", "cargo-xwin"))) {
    if (!existsSync(join(LLVM, "clang-cl"))) throw new Error("cross-building for Windows needs Homebrew's llvm and lld (brew install llvm lld)");
    run("cargo", ["install", "--locked", "--root", tools, "cargo-xwin", "--version", XWIN], { env: rustEnv(env) });
  }
  return env;
}
/// The Windows shell and its tests, here: natively on Windows, with cargo-xwin on a Mac.
function shellWin(out: string) {
  const cross = osPlatform() === "darwin";
  const target = cross ? join(BUILD(), "target") : targetDir(join(ROOT, "client/target"), "shell");
  const env = { CARGO_TARGET_DIR: target, ...(cross ? xwinEnv() : {}) };
  const xwin = (args: string[]) => (cross ? ["xwin", ...args] : args);
  cargo(xwin(shellWinCommand()), join(ROOT, "client"), env);
  const release = join(target, "x86_64-pc-windows-msvc/release");
  for (const f of ["stillfail_shell.dll", "stillfail_shell.dll.lib"]) copyFileSync(existsSync(join(release, f)) ? join(release, f) : join(release, "deps", f), join(out, f));
  // the tests' executables, from cargo's own account of what it built
  rustTarget("x86_64-pc-windows-msvc");
  const done = spawnSync("cargo", xwin(SHELL_TESTS), { cwd: join(ROOT, "client"), env: rustEnv(env), encoding: "utf8", maxBuffer: 256 << 20, stdio: ["ignore", "pipe", "inherit"] });
  if (done.status !== 0) throw new Error(`cargo ${xwin(SHELL_TESTS).join(" ")}: exit ${done.status}`);
  mkdirSync(join(out, "tests"));
  for (const line of done.stdout.split("\n")) {
    if (!line.startsWith("{")) continue;
    const m = JSON.parse(line);
    if (m.reason !== "compiler-artifact" || !m.profile?.test || !m.executable) continue;
    copyFileSync(m.executable, join(out, "tests", `${m.target.kind.includes("lib") ? "lib" : m.target.name}.exe`));
  }
  if (readdirSync(join(out, "tests")).length === 0) throw new Error("the shell's tests were not built");
}
/// The Windows engine (apps/mbui/engine) in Hermes's own CMake build (its libhermes, static, linked into the DLL),
/// linked to the shell by name (an import library made from the shell's C ABI, stillfail_shell.def: the shell itself
/// is not needed to build it). The checkout and the build stay in the part's target directory, so a change to the loop
/// alone compiles only it.
function engineWin(out: string) {
  if (tomlVersion("hermes") !== HERMES.rn) throw new Error(`Android's Hermes is ${tomlVersion("hermes")}, Windows' tag is React Native ${HERMES.rn}'s: move HERMES with it`);
  // natively on Windows; on a Mac with clang-cl and xwin's SDK (cargo-xwin's), Hermes's own tools built for the Mac
  const cross = osPlatform() === "darwin";
  const work = cross ? join(BUILD(), "hermes") : targetDir(join(ROOT, "apps/mbui/engine/target"), "engine");
  const src = join(work, "hermes");
  mkdirSync(work, { recursive: true });
  if (!existsSync(join(src, ".stillfail-tag")) || readFileSync(join(src, ".stillfail-tag"), "utf8") !== HERMES.tag) {
    rmSync(src, { recursive: true, force: true });
    // the tag's tarball, tried again on the way (a clone over Studio's TLS broke off, 2026-10-19)
    mkdirSync(src, { recursive: true });
    const tgz = join(work, "hermes.tar.gz");
    run("curl", ["-fsSL", "--retry", "5", "--retry-all-errors", "--retry-delay", "5", "-o", tgz, `https://github.com/facebook/hermes/archive/refs/tags/${HERMES.tag}.tar.gz`]);
    run(TAR, ["-xzf", tgz, "-C", src, "--strip-components=1"]);
    rmSync(tgz, { force: true });
    // the loop in Hermes's tree, as one of its directories (it links Hermes's own targets)
    writeFileSync(join(src, "CMakeLists.txt"), readFileSync(join(src, "CMakeLists.txt"), "utf8") + "\nadd_subdirectory(stillfail-engine)\n");
    writeFileSync(join(src, ".stillfail-tag"), HERMES.tag);
  }
  rmSync(join(src, "stillfail-engine"), { recursive: true, force: true });
  mkdirSync(join(src, "stillfail-engine"));
  for (const e of readdirSync(join(ROOT, "apps/mbui/engine"), { withFileTypes: true })) {
    if (e.isFile()) copyFileSync(join(ROOT, "apps/mbui/engine", e.name), join(src, "stillfail-engine", e.name));
  }
  const build = join(work, "build");
  run("cmake", ["-S", src, "-B", build, ...(cross ? hermesCross(src, work) : HERMES_CMAKE)]);
  run("cmake", ["--build", build, "--target", "stillfail_engine", "hermesc"]);
  for (const f of ["stillfail_engine.dll", "stillfail_engine.lib"]) copyFileSync(join(build, "stillfail-engine", f), join(out, f));
  copyFileSync(join(build, "bin", "hermesc.exe"), join(out, "hermesc.exe"));
}
/// Hermes for Windows from a Mac: the hermesc it compiles its own JS with built for the Mac first (Hermes's cross build
/// imports it), then a CMake toolchain of clang-cl, lld-link and llvm-lib on xwin's SDK and CRT (the release CRT: xwin
/// has no debug one, so CMake's own test compiles are release builds too).
function hermesCross(src: string, work: string): string[] {
  const env = xwinEnv();
  const sdk = join(env.XWIN_CACHE_DIR, "xwin");
  if (!existsSync(join(sdk, "crt"))) run("cargo", ["xwin", "env", "--target", "x86_64-pc-windows-msvc"], { env: rustEnv(env), stdio: ["ignore", "ignore", process.stderr] });
  if (!existsSync(join(sdk, "crt"))) throw new Error(`no Windows SDK in ${sdk} (cargo-xwin's)`);
  const host = join(work, "hermesc-host");
  run("cmake", ["-S", src, "-B", host, "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release", "-DHERMES_ENABLE_DEBUGGER=OFF", "-DHERMES_ENABLE_TEST_SUITE=OFF"]);
  run("cmake", ["--build", host, "--target", "hermesc"]);
  const inc = ["crt/include", "sdk/include/ucrt", "sdk/include/um", "sdk/include/shared"].map((d) => `/imsvc${join(sdk, d)}`).join(" ");
  const libs = ["crt/lib/x86_64", "sdk/lib/um/x86_64", "sdk/lib/ucrt/x86_64"].map((d) => `/libpath:${join(sdk, d)}`).join(" ");
  const toolchain = join(work, "clang-cl-windows.cmake");
  writeFileSync(toolchain, [
    "set(CMAKE_SYSTEM_NAME Windows)",
    "set(CMAKE_SYSTEM_PROCESSOR AMD64)",
    `set(CMAKE_C_COMPILER ${LLVM}/clang-cl)`,
    `set(CMAKE_CXX_COMPILER ${LLVM}/clang-cl)`,
    `set(CMAKE_LINKER ${existsSync(join(LLVM, "lld-link")) ? join(LLVM, "lld-link") : "/opt/homebrew/bin/lld-link"})`,
    `set(CMAKE_AR ${LLVM}/llvm-lib)`,
    `set(CMAKE_RC_COMPILER ${LLVM}/llvm-rc)`,
    `set(CMAKE_MT ${LLVM}/llvm-mt)`,
    `set(CMAKE_C_FLAGS_INIT "--target=x86_64-pc-windows-msvc ${inc}")`,
    `set(CMAKE_CXX_FLAGS_INIT "--target=x86_64-pc-windows-msvc ${inc}")`,
    ...["EXE", "SHARED", "MODULE"].map((k) => `set(CMAKE_${k}_LINKER_FLAGS_INIT "${libs} /manifest:no")`),
    "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)",
    "set(CMAKE_TRY_COMPILE_CONFIGURATION Release)",
    "set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)",
    "set(CMAKE_POLICY_DEFAULT_CMP0091 NEW)",
    "",
  ].join("\n"));
  return ["-G", "Ninja", `-DCMAKE_TOOLCHAIN_FILE=${toolchain}`, "-DCMAKE_BUILD_TYPE=Release", "-DHERMES_ENABLE_DEBUGGER=OFF", "-DHERMES_ENABLE_TEST_SUITE=OFF", `-DIMPORT_HERMESC=${join(host, "ImportHermesc.cmake")}`];
}
const P = (name: string): Part => PARTS[name] ?? fail(`no such part: ${name} (${Object.keys(PARTS).join(", ")})`);
const inputsFor = (p: Part, t: Target): string[] => (typeof p.inputs === "function" ? p.inputs(t) : p.inputs ?? []);
/// Built only on Windows (msvc).
const onWindows = (part: string, t: Target): boolean => t === "win32-x64" && P(part).msvc === true;
/// This machine's when the part is built for it, else the part's first target (Android's shell and engine on a Mac).
const defaultTarget = (part: string): Target => {
  const { targets } = P(part);
  let here: Target | null = null;
  try { here = host(); } catch {}
  return here && targets.includes(here) ? here : targets[0]!;
};

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
  // A crate's tests, benches and examples are not in what it builds: changed, it is the same part (a test-only change
  // built the launcher and runner again for three platforms on 2026-10-04).
  for (const p of [...files.keys()]) if (/(^|\/)(tests|benches|examples)\//.test(p)) files.delete(p);
  return [...files].sort(([a], [b]) => (a < b ? -1 : 1));
}
function key(part: string, target: Target): string {
  const p = P(part);
  const zig = target.startsWith("linux") || (target === "win32-x64" && !onWindows(part, target)) ? (p.zig ?? ZIG) : undefined;
  const what = { part, target, toolchain: p.rust === false ? undefined : TOOLCHAIN, zig, recipe: p.recipe(target), files: p.files(target), inputs: inputs(inputsFor(p, target)) };
  return createHash("sha256").update(JSON.stringify(what)).digest("hex").slice(0, 24);
}
const asset = (part: string, target: Target, k: string) => `${part}-${target}-${k}.tar.gz`;

// ── the cache ──

const CACHE = process.env.STILLFAIL_NATIVE_CACHE ??
  (osPlatform() === "darwin" ? join(homedir(), "Library/Caches/stillfail-native")
    : osPlatform() === "win32" ? join(process.env.LOCALAPPDATA ?? join(homedir(), "AppData/Local"), "stillfail-native")
    : join(process.env.XDG_CACHE_HOME ?? join(homedir(), ".cache"), "stillfail-native"));
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
  run(TAR, ["-xzf", tgz, "-C", tmp]);
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
  // a prebuilt one's store, then the release CI publishes to
  const started = Date.now();
  let url = "";
  let response: Response | null = null;
  for (const at of [`${STORE}/${name}`, `https://github.com/${REPO}/releases/download/${RELEASE}/${name}`]) {
    try {
      const r = await fetch(at, { redirect: "follow", signal: AbortSignal.timeout(300_000) });
      if (r.ok) { url = at; response = r; break; }
      if (r.status !== 404) log(`${part} ${target}: ${at} answered ${r.status}`);
    } catch (e) {
      log(`${part} ${target}: could not reach ${new URL(at).host} (${(e as Error).message})`);
    }
  }
  if (!response) return null;
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
  if (onWindows(part, target) && !["win32", "darwin"].includes(osPlatform())) throw new Error(`${part} ${target} ${k} is not prebuilt: Windows builds it, or a Mac cross-builds it (node scripts/native.ts prebuild ${part}:${target})`);
  log(`${part} ${target} ${k}: not prebuilt; building it here${P(part).inputs && P(part).rust !== false ? " (cargo)" : ""}…`);
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
    // What a development machine prebuilds is never built on CI: said, with how.
    if (onWindows(part, target) && (process.env.CI || mode === "fetch")) throw new Error(`${part} ${target} ${k} is not prebuilt: prebuild it on a Mac (Studio), node scripts/native.ts prebuild ${part}:${target}`);
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
    PATH: [join(home, ".cargo/bin"), "/opt/homebrew/bin", process.env.PATH].join(delimiter),
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
/// Whether the store of prebuilt parts has it.
async function inStore(name: string): Promise<boolean> {
  try {
    const r = await fetch(`${STORE}/${name}`, { method: "HEAD", redirect: "follow", signal: AbortSignal.timeout(30_000) });
    return r.ok;
  } catch {
    return false;
  }
}
function pack(dir: string, name: string, into: string): string {
  const file = join(into, name);
  run(TAR, ["-czf", file, "-C", dir, "."]);
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
    case "missing": {
      // Each part (default: all of ours) the release lacks, one a line: CI's plan skips the natives job when none is.
      // --windows: those only Windows builds (the natives-win job's); without it, the others.
      const windows = args.includes("--windows");
      const wanted: [string, Target][] = [];
      for (const a of args.filter((a) => a !== "--windows")) { const [p, t] = a.split(":"); wanted.push(pair(t ? [p!, t] : [p!])); }
      if (wanted.length === 0) for (const [p, t] of ours()) if (onWindows(p, t) === windows) wanted.push([p, t]);
      const remote = published() ?? fail("the release's assets could not be listed");
      for (const [p, t] of wanted) if (!remote.has(asset(p, t, key(p, t)))) console.log(`${p}:${t}`);
      return;
    }
    case "ensure": {
      let publish = false, outbox = "", windows = false;
      const wanted: [string, Target][] = [];
      for (let i = 0; i < args.length; i++) {
        if (args[i] === "--publish") publish = true;
        else if (args[i] === "--windows") windows = true;
        else if (args[i] === "--outbox") outbox = args[++i] ?? fail("--outbox DIR");
        else { const [p, t] = args[i]!.split(":"); wanted.push(pair(t ? [p!, t] : [p!])); }
      }
      // Default: all of ours that this kind of machine builds (--windows: what only Windows does).
      if (wanted.length === 0) for (const [p, t] of ours()) if (onWindows(p, t) === windows) wanted.push([p, t]);
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
    case "prebuild": {
      const toRelease = args.includes("--release");
      const wanted: [string, Target][] = [];
      for (const a of args.filter((a) => a !== "--release")) { const [p, t] = a.split(":"); wanted.push(pair(t ? [p!, t] : [p!])); }
      if (wanted.length === 0) for (const [p, t] of ours()) if (onWindows(p, t)) wanted.push([p, t]);
      const work = join(tmpdir(), `stillfail-prebuild-${process.pid}`);
      mkdirSync(join(work, "natives"), { recursive: true });
      let any = false;
      for (const [p, t] of wanted) {
        const k = key(p, t);
        const name = asset(p, t, k);
        if (toRelease ? await exists(name) : await inStore(name)) { console.log(`${p} ${t} ${k}: there already`); continue; }
        const started = Date.now();
        const dir = await get(p, t);
        pack(dir, name, join(work, "natives"));
        console.log(`${p} ${t} ${k}: ready (${((Date.now() - started) / 1000).toFixed(0)} s), putting it in the store`);
        any = true;
      }
      try {
        if (any && toRelease) for (const f of readdirSync(join(work, "natives"))) gh(["release", "upload", RELEASE, join(work, "natives", f), "-R", REPO]);
        else if (any) run("sh", [join(ROOT, "scripts/release-put.sh"), "--files", work], { stdio: "inherit" });
      } finally { rmSync(work, { recursive: true, force: true }); }
      return;
    }
    case "store-sync": {
      const work = join(tmpdir(), `stillfail-store-sync-${process.pid}`);
      mkdirSync(join(work, "natives"), { recursive: true });
      let any = false;
      try {
        for (const [p, t] of ours()) {
          if (!onWindows(p, t)) continue;
          const name = asset(p, t, key(p, t));
          if (await inStore(name)) { console.log(`${name}: in the store`); continue; }
          if (!(await exists(name))) { console.log(`${name}: in neither (prebuild it: node scripts/native.ts prebuild ${p}:${t})`); continue; }
          const r = await fetch(`https://github.com/${REPO}/releases/download/${RELEASE}/${name}`, { redirect: "follow", signal: AbortSignal.timeout(300_000) });
          if (!r.ok) throw new Error(`${name}: the release answered ${r.status}`);
          writeFileSync(join(work, "natives", name), Buffer.from(await r.arrayBuffer()));
          console.log(`${name}: from the release, to the store`);
          any = true;
        }
        if (any) run("sh", [join(ROOT, "scripts/release-put.sh"), "--files", work], { stdio: "inherit" });
      } finally { rmSync(work, { recursive: true, force: true }); }
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

/// Every part and target of ours CI publishes (n0's relay is not ours to publish).
function ours(): [string, Target][] {
  const all: [string, Target][] = [];
  for (const [p, part] of Object.entries(PARTS)) if (p !== "iroh-relay") for (const t of part.publish ?? part.targets) all.push([p, t]);
  return all;
}

/// What a part is made of, as paths in the repository (scripts/module-bundle.ts: a package carrying the part is a new
/// version when they change): for every target.
export const inputsOf = (part: string): string[] => [...new Set(P(part).targets.flatMap((t) => inputsFor(P(part), t)))];
/// The targets a part is built for.
export const targetsOf = (part: string): string[] => P(part).targets;
/// The files a part's artifact holds for a target.
export const filesOf = (part: string, target: string): string[] => P(part).files(target as Target);
/// Whether there is such a part.
export const isPart = (name: string): boolean => Object.hasOwn(PARTS, name);

if (import.meta.main) {
  main(process.argv.slice(2)).catch((e) => {
    log((e as Error).message);
    process.exit(1);
  });
}

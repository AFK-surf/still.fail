# Development

The commands below run from the repository root unless noted. The station, the client core, the web UI and the Cloudflare Workers are TypeScript (Node.js); a few native parts are Rust, prebuilt. Start with cloud tests if you do not need to build a client.

## Prerequisites

- Git, Python 3, Node.js 24 or later, and pnpm 10.33.0 (every `package.json` names it in `packageManager`).
- Rust is optional for everyday work: the native parts the TypeScript station and clients use are prebuilt (see [Native parts](#native-parts)). To change one of them you need rustup (the parts are built with the toolchain pinned in `scripts/native.ts`, which rustup installs on first use), plus, per part: the `wasm32-unknown-unknown` target, `wasm-bindgen-cli` matching `wasm-bindgen` in `client/Cargo.lock` (currently 0.2.129) and LLVM's `clang`/`llvm-ar` with WebAssembly support for the browser's iroh; the NDK below for Android's shell and engine; zig and cargo-zigbuild for the Linux station parts from a Mac.
- Android additionally needs JDK 17 and the Android SDK (NDK 28.2.13676358 to build its shell or engine, or to strip them when packing); the apps (`apps/mbui/`) need MoonBit and their platform's toolchain, as [its README](../apps/mbui/README.md) says.

```sh
git clone https://github.com/AFK-surf/still.fail.git
cd still.fail
pnpm install --frozen-lockfile
(cd cloud && pnpm install --frozen-lockfile)
```

## Cloud tests without deployment credentials

```sh
cd cloud
pnpm run types
pnpm run check
pnpm test
```

The tests use Miniflare and mock external services. No Cloudflare account, Google OAuth client secret or production deployment credentials are needed.

## Native parts

Everything Rust that the TypeScript station, the clients, their builds and their tests need is a *native part*, prebuilt, and fetched by `scripts/native.ts`:

| Part | What | Targets | Used by |
| --- | --- | --- | --- |
| `mesh` | `station/native/mesh`: the station's iroh and image codecs, a Node addon (`mesh.node`) | darwin-arm64, linux-x64, linux-arm64 | station tests and bundle, core-ts tests, the desktop app's core |
| `launcher` | `station/native/launcher`: the station's `stillfail-station` | same | the station's bundle (releases, the desktop app), `station/test/e2e.sh` |
| `runner` | `station/native/runner`: `stillfail-runner` | same | station tests and bundle |
| `iroh-wasm` | `client/iroh-wasm`: the browser's iroh (`web/src/core/iroh-pkg`) | wasm32 | web build, web typecheck and tests |
| `shell` | `client/shell`: the core's IO (`libstillfail_shell.so`; on Windows MSVC's `stillfail_shell.dll` and its import library) | android-arm64, win32-x64, linux-x64, linux-arm64 | the mbui app on Android, Windows (`apps/mbui/scripts/win.sh`) and Linux |
| `engine` | `apps/mbui/engine`: Hermes and the core's loop on it (its C API `engine.h`). Android's: hermes-android with its JSI (`libstillfail_hermes.so`, `libjsi.so`, the NDK's `libc++_shared.so`), the NDK's CMake (`apps/mbui/engine/android`); Windows': Hermes 0.81.4 built from its source with clang-cl, static, in `stillfail_engine.dll` (and that build's `hermesc.exe`); Linux's: the same with clang, `libstillfail_engine.so` with its ICU | android-arm64, win32-x64, linux-x64, linux-arm64 | the mbui app on Android, Windows and Linux |
| `archive-rs`, `station-load` | `station/test/archive-rs` (the Rust station's cold storage, kept for data it left), `station/tools/load`: test tools | darwin-arm64 published | station tests, `e2e.sh`, `compare.sh` |
| `helper` | `station/native/helper`: still.fail Helper, the station's macOS app for what macOS grants (`still.fail Helper.app`, Swift: the screen with ScreenCaptureKit, VideoToolbox, CGEvent; its permission window with `vendor/PermissionFlow`) | darwin-arm64 | the station's bundle, `station/side/screen-desktop.test.ts`, `station/side/screen-e2e.ts` |
| `ffmpeg` | `scripts/ffmpeg.ts`: `ffmpeg` and `ffprobe` from FFmpeg's release tarball, LGPL only and minimal, with their license files and `SOURCE` (VideoToolbox's H.264 encoder on macOS; zig-built, with openh264 and zlib, for Linux; NASM built for the x64 one). Its key is that file alone (no Rust toolchain; its own zig pin) | darwin-arm64, linux-x64, linux-arm64 | the media service's package (`scripts/module-bundle.ts`: `bin/`), `native.ts run ffmpeg` (`MEDIA_FFMPEG`) |
| `iroh-relay` | n0's release v1.1.0, checked against its SHA-256 (not ours to publish) | darwin-arm64, linux | core-ts side run (`side/mesh-real.test.ts`) |

**Keys.** A part's key is the SHA-256 of: the git hash of every file it is made from (its crate, its `Cargo.lock`, the vendored crates it patches in, …: `inputs` in `scripts/native.ts`), as committed or as edited in the worktree; the Rust toolchain (pinned there, `TOOLCHAIN`, and installed by rustup when building); zig's version for Linux; the target; and the build's command, flags, NDK, Hermes and AGP versions. Nothing else changes a key, so a change anywhere else compiles no Rust. `node scripts/native.ts status` lists every part's key and where it is.

**Where they are**, in this order:

1. The machine's cache, shared by every worktree: `~/Library/Caches/stillfail-native/<part>/<target>-<key>/` on macOS, `$XDG_CACHE_HOME/stillfail-native` (or `~/.cache/stillfail-native`) on Linux, or `$STILLFAIL_NATIVE_CACHE`. A new worktree finds what another already got.
2. `$STILLFAIL_NATIVE_INBOX` (CI: a branch's run artifact, below).
3. The GitHub release [`native-artifacts`](https://github.com/AFK-surf/still.fail/releases/tag/native-artifacts), one asset per key (`<part>-<target>-<key>.tar.gz`). The repository is public, so any machine reads it with plain HTTPS: no login, no token, no cloud change. (The releases bucket was the other candidate: reading it outside still.fail cloud's `/releases/` whitelist needs Cloudflare credentials, and the whitelist is a Worker change per new file kind.)
4. Built here from the checkout, said on stderr (`native: mesh darwin-arm64 …: not prebuilt; building it here (cargo)…`), into the cache. Builds go to the crate's own `target/` (a worktree's own; never one shared between checkouts), or `$CARGO_TARGET_DIR/native/<part>` when that is set.

One process at a time gets or builds a key on a machine; others wait for it (a lock directory beside the cache entry), so parallel checks or worktrees never build a part twice. A cache entry appears atomically (renamed into place when complete).

**Who uses them.** `pnpm test` in `station/` and `client/core-ts/` runs `node ../scripts/native.ts run <parts> -- node --test …`, which sets `STILLFAIL_MESH_NATIVE`, `STILLFAIL_RUNNER`, `ARCHIVE_RS` and `STILLFAIL_RELAY_BIN` (unless already set). `pnpm run build` and `build:cloud` run `node scripts/native.ts iroh-pkg`, which puts the browser's iroh in `web/src/core/iroh-pkg` once per key. `scripts/station-bundle.sh` and the mbui app's scripts (`apps/mbui/scripts/`) take theirs from `native.ts file|path|fetch`. `scripts/check.sh` compiles Rust only for Rust's own tests (`cargo test` in `client/` and `station/native/*`), each only when that Rust changed.

```sh
node scripts/native.ts file mesh                 # the addon for this machine (prebuilt, or built)
node scripts/native.ts path engine android-arm64 # a directory
node scripts/native.ts key iroh-wasm             # its key
node scripts/native.ts build mesh linux-x64      # build it here, whatever is cached
STILLFAIL_NATIVE=build …                         # never download: build what the cache lacks
STILLFAIL_NATIVE=offline …                       # neither download nor build
```

**Prebuilt, built when asked: the mbui app's shell and engine.** `shell` and `engine` (`msvc` in `scripts/native.ts`: Windows' are MSVC's) are what the mbui app's jobs only fetch, Android's and Windows'; CI builds them only when asked. A branch whose change makes a new one (`apps/mbui/engine`, `client/shell`, …) fails in those jobs (mbui's `android` and `windows`, the pipeline's `windows-natives`) with what to run: `gh workflow run prebuild.yml -R AFK-surf/still.fail --ref <branch>`. That workflow (`.github/workflows/prebuild.yml`) builds each that neither the store nor the release has from the branch's checkout, Windows' on GitHub's Windows (MSVC's environment with clang-cl, CMake and Ninja; under Git Bash `CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER` naming MSVC's `link.exe`), Android's on Linux with the NDK, puts them in the release `native-artifacts` (`node scripts/native.ts prebuild --release`), and runs the failed jobs of the commit's pipeline and mbui runs again (not on main). A Mac can prebuild them too, cross-building the Windows ones with cargo-xwin (the shell, which carries its tests' executables in `tests/`) and with clang-cl on xwin's Windows SDK (Hermes and the engine; Hermes's own hermesc is built for the Mac first), into the releases bucket's `natives/` by their keys: `node scripts/native.ts prebuild` (the Windows ones; or `prebuild shell:win32-x64`), with the bucket's `CLOUDFLARE_API_TOKEN` as `scripts/release-put.sh` takes it, or `--release` to the release with gh. It needs Homebrew's `llvm` and `lld`; cargo-xwin, the SDK (1.1 GB), cargo's target and Hermes's builds stay in the cache's `.build/` (`$STILLFAIL_NATIVE_BUILD`), so a change rebuilds only itself. Everyone fetches them from `https://app.still.fail/releases/natives/` (`$STILLFAIL_NATIVE_STORE`; still.fail cloud serves it, `cloud/src/install.ts`), else the release; main's `natives-store` copies the Windows ones from the release into the store. The pipeline's `windows-natives` job fetches both Windows ones on GitHub's Windows for a change to what they are made of and runs the shell's tests there.

**Publishing** happens only in CI, on main: the pipeline's `natives` job (mini1) runs `node scripts/native.ts ensure --publish`, which builds every part (and target) whose key the release lacks and uploads it with the run's token, then `prune 20` keeps the newest 20 assets of each part and target. A branch publishes nothing: its `natives` job builds what the release lacks of what its checks and builds use, and hands it to its other jobs as the run artifact `natives-<sha>` (`STILLFAIL_NATIVE_INBOX`, `.github/actions/natives`); on mini1 the jobs share the cache anyway. Every job after it (checks, the web build, Android on Blacksmith, the desktop and station on mini1) then compiles no Rust; the station's releases (all three platforms) take the parts main's natives job published. The release is a prerelease, made once by hand (`gh release create native-artifacts --prerelease --target <a main commit> -t "Prebuilt native parts"`): GitHub refuses the run's token a new tag at a commit that changes a workflow.

Measured on studio, a fresh worktree each, step by step (seconds; rustc calls in brackets where there were any):

| Step | Parts in the machine's cache (39eced35) | Nothing prebuilt, built here through sccache (39eced35) | Rust era (b98a7f6e) |
| --- | --- | --- | --- |
| worktree + install | 5.6 | 5.6 | 3.4 |
| web's iroh | 0.4 | 50.9 (280) | 106.9 (308) |
| typecheck | 6.2 | 6.1 | 2.4 |
| station tests | 3.9 | 71.4 (434) | 56.0 (486) |
| core tests | 9.9 | 12.8 | 61.6 (504) |
| web build | 13.4 | 13.5 | 11.2 |
| desktop build (unsigned) | 24.8 | 99.1 (442) | 154.9 (890) |
| Android debug build | 21.5 | 79.4 (374) | 81.6 (454) |
| **total** | **85.9** | **339.0 (1,530)** | **478.3 (2,642)** |

With the parts published and an empty cache, the first column plus their download (33 MB, about 12 s; measured at f5b84fbf, when the core tests still took 58 s: 144 s on studio, 150 s on mini1). A worktree takes 2.1 GB (no Cargo target) against 4.8 GB building the parts and 11.1 GB in the Rust era; the shared cache 0.09 GB. A TypeScript-only commit's full check, part by part as CI runs it, made no rustc call and ran no cargo.

## Node

One Node version everywhere, `.node-version`'s: CI (`.github/actions/setup`, and on the Macs `scripts/node-here.sh`),
the station's releases (which name it in `NODE_VERSION` rather than carry it: the installer gets it once per version,
`scripts/node-dist.sh` puts it beside the releases).

## Tests: CI's and the side run's

A test CI runs is the same every run: what it shows is decided by the code alone, never by how fast or busy the machine
is, the time of day, real timers, or real sockets and processes taking their time. So a failure in CI is the code's,
and fails again, the same way, anywhere. Time is a test's clock (Effect's `TestClock`, the core's `FakeHost`), moved on
by the test; networks are simulated (`client/core-ts/test/sim-iroh.ts`: relays, their lines' latency and speed, outages,
on the test's clock). A test does not sleep and then assert that nothing more happened, poll against a deadline, or
assert how long something took: it moves its clock past the time in question and looks.

Where a seed decides what a simulated run leaves open (jitter, how writes are cut), the seeds are fixed
(`client/core-ts/test/sim-seeds.ts`); a failure names its seed and network, and `SIM_SEED=<seed>` runs only it.

What cannot be made the same every run (real processes and signals, the native addon and iroh-relay over real
sockets, networks made up at random) is the side run's: `sh scripts/side.sh` (each package's `side/`; Rust's
`#[ignore = "side: …"]`), every four hours on main in CI (`.github/workflows/side.yml`, on mini1, each part on a runner of
its own; run it by hand with `gh workflow run side`), blocking nothing. A side failure goes to an agent, which
reproduces it as a test CI runs, failing the same way every time, and fixes it; one it cannot reproduce is let be.
Never a retry, a longer deadline or a looser bound to make a test pass.

## CI time

Every run of the pipeline ends with `timing` (`scripts/ci-time.ts`): the time from its first job starting to its last
ending, against a budget, in the run's summary, with a warning when over. The budgets (`BUDGET` there):

| Run | Budget | Typical (2026-10-04) |
|---|---|---|
| A branch | 180 s | ~100 s with caches warm |
| main, releasing nothing | 180 s | ~100 s |
| A branch or main that checked the Android app (`check-android`) | 240 s | ~190 s (2026-10-07) |
| main, releasing apps or the station | 480 s | — |

`node scripts/ci-time.ts <run id>` prints any run's jobs and longest steps. A run over its budget is a regression to
find the cause of, as one that fails is: what got slower (a step, a cache missed, a test waiting in real time, jobs
queued behind one another on mini1), fixed or the budget changed on purpose, not left. The check's Rust tests are
remembered by their inputs (`scripts/check.sh`, `rust_step`), and CI keeps Gradle's caches (`.github/actions/setup`):
a run that missed them is the usual first suspect.

## Browser and station builds

`client/iroh-wasm/build.sh` (what builds the `iroh-wasm` part) uses `LLVM_BIN` when set, otherwise checks Homebrew LLVM installations and then `clang`/`llvm-ar` on `PATH`. It checks for WebAssembly support before compiling. To choose a particular LLVM installation, set `LLVM_BIN` to its `bin` directory.

```sh
STILLFAIL_PREVIEW_ORIGIN=http://127.0.0.1:8790 pnpm run build:cloud
(cd station && pnpm install --frozen-lockfile)
sh scripts/station-bundle.sh /tmp/station   # [darwin-arm64|linux-x64|linux-arm64]
```

The first command gets the browser's iroh (WebAssembly, prebuilt; the core itself is TypeScript, client/core-ts) and builds the local cloud's web/admin/preview assets, with previews pointing at the local preview host. This variable is read at build time; changing it requires rebuilding the web assets. If you change the development server's `PORT`, use its preview port (`PORT + 3`) here. Without this variable, the web build uses the hosted preview service.

The last one lays out a station release in `/tmp/station/stillfail` (the layout `scripts/station-bundle.sh` describes): the station bundled, its Node, its native parts (prebuilt) and `bin/stillfail`, as the installer and the desktop app have it.

## Isolated local development

Install an `iroh-relay` compatible with the project's iroh version. The hosted relays run still.fail's branch of it (see `cloud/Dockerfile`), which speaks the same protocol as upstream 1.1.0; prebuilt binaries are available in the [upstream release](https://github.com/n0-computer/iroh/releases/tag/v1.1.0). Run it locally in its own terminal:

```sh
iroh-relay --dev
```

It listens on port 3340. Then, in a separate terminal:

```sh
cd cloud
RELAY=http://127.0.0.1:3340 pnpm exec tsx test/dev.ts
```

The development server prints enrollment commands and serves:

| Address | Purpose |
| --- | --- |
| `http://127.0.0.1:8787/__dev/login?user=alice` | Web app with mock login |
| `http://127.0.0.1:8789/__dev/login?user=alice` | Admin console with mock login |
| `http://127.0.0.1:8790` | Preview host |
| `http://127.0.0.1:8791/__dev/login?user=alice` | Beta web app |

Use a fresh station data directory. For example, in another terminal at the repository root:

```sh
export STILLFAIL_DATA="$(mktemp -d)"
# Substitute the token printed in an ENROLL line by the development server:
/tmp/station/stillfail/bin/stillfail station enroll http://127.0.0.1:8787 <enrollment-token>
/tmp/station/stillfail/bin/stillfail start
```

The enrollment token is temporary; do not commit it. Keep `STILLFAIL_DATA` set to the same directory for subsequent station commands. Rebuild the release (the last command above) after changing the station. Configure your agent runtime in the local app when you need real agent execution; that step uses your own runtime account.

The mock login routes are for loopback development only. Restarting the local cloud recreates its test identities and workspace, so enroll a fresh test station again. The station's old local admin URL is a redirect, not a standalone UI.

## A station on Windows (proof of concept)

The station runs natively on Windows x64 from a checkout; there is no Windows installer or release yet (docs/station-ts-native.md, "Windows"). It needs Git for Windows: jobs and device commands run under its `sh`, as Claude Code's own commands do there. From PowerShell (Git Bash's `tar` takes `C:` for a host, so `scripts/native.ts` runs from PowerShell):

```powershell
corepack pnpm install --frozen-lockfile --ignore-scripts
cd station; corepack pnpm install --frozen-lockfile --ignore-scripts
cd native\runner; cargo build --release; cd ..\launcher; cargo build --release; cd ..\..
$env:STILLFAIL_MESH_NATIVE = node ..\scripts\native.ts file mesh   # win32-x64 is prebuilt for the desktop app
$env:STILLFAIL_RUNNER = "$PWD\native\runner\target\release\stillfail-runner.exe"
node src\main.ts run --app $PWD --data $env:TEMP\stillfail-test
```

`cargo test --release` in `native\runner` runs its Windows tests (`tests\windows.rs`); `node --test test\runner-windows.test.ts test\jobs.test.ts test\device-tools.test.ts test\remote.test.ts` the station's that run there. Most other station tests still assume Unix (fifos, `/tmp`, `sh` scripts as commands).

## Local desktop packages

The desktop apps are mbui's (`apps/mbui/`): `apps/mbui/scripts/mac-app.sh` makes the macOS app (signed ad hoc without `MAC_SIGN_IDENTITY`), `apps/mbui/scripts/win.sh build` and `win.sh setup` the Windows app and its installer (Git Bash with MSVC's environment); `MBUI_VARIANT=stable` or `beta` builds them as still.fail's released apps rather than still.fail mbui, a test app of its own. None of these publishes or installs the app. A redistributed fork also needs its own application identity, cloud origin and update feed; building alone does not configure those.

## Production self-hosting

The production path is Cloudflare-specific: Workers, Durable Objects, R2 and the relay Container, plus your own domains and Google OAuth client. Review `cloud/wrangler*.jsonc`, `cloud/deploy.py` and [cloud.md](cloud.md) before adapting it. The checked-in routes and release scripts target the maintainers' hosted service. Do not run them unchanged against a different account.

Keep secrets in an external deployment directory selected by `STILLFAIL_DEPLOY_DIR`; see the inputs documented at the top of `cloud/deploy.py`. Firebase push, Axiom and PostHog are additional integrations, not prerequisites for the mocked local cloud. Existing operations notes include historical deployment details and are not a turnkey self-hosting guide.

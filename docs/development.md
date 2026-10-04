# Development

The commands below run from the repository root unless noted. The station, the client core, the web UI and the Cloudflare Workers are TypeScript (Node.js); a few native parts are Rust, prebuilt. Start with cloud tests if you do not need to build a client.

## Prerequisites

- Git, Python 3, Node.js 24 or later, and pnpm 10.33.0 (every `package.json` names it in `packageManager`).
- Rust is optional for everyday work: the native parts the TypeScript station and clients use are prebuilt (see [Native parts](#native-parts)). To change one of them you need rustup (the parts are built with the toolchain pinned in `scripts/native.ts`, which rustup installs on first use), plus, per part: the `wasm32-unknown-unknown` target, `wasm-bindgen-cli` matching `wasm-bindgen` in `client/Cargo.lock` (currently 0.2.129) and LLVM's `clang`/`llvm-ar` with WebAssembly support for the browser's iroh; the NDK below for Android's shell and engine; zig and cargo-zigbuild for the Linux station parts from a Mac.
- Android additionally needs JDK 17 and the Android SDK (NDK 28.2.13676358 to build its shell or engine, or to strip them when packing); desktop packaging has its own dependencies in `apps/desktop/`.

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
| `shell` | `client/shell`: the Android core's IO (`libstillfail_shell.so`) | android-arm64 | `apps/android/build.py` |
| `engine` | `apps/android/core/src/main/cpp`: Hermes with its JSI (`libstillfail_hermes.so`, `libjsi.so`, the NDK's `libc++_shared.so`) | android-arm64 | `apps/android/build.py` |
| `archive-rs`, `station-load` | `station/test/archive-rs` (the Rust station's cold storage, kept for data it left), `station/tools/load`: test tools | darwin-arm64 published | station tests, `e2e.sh`, `compare.sh` |
| `iroh-relay` | n0's release v1.1.0, checked against its SHA-256 (not ours to publish) | darwin-arm64, linux | core-ts mesh tests |

**Keys.** A part's key is the SHA-256 of: the git hash of every file it is made from (its crate, its `Cargo.lock`, the vendored crates it patches in, …: `inputs` in `scripts/native.ts`), as committed or as edited in the worktree; the Rust toolchain (pinned there, `TOOLCHAIN`, and installed by rustup when building); zig's version for Linux; the target; and the build's command, flags, NDK, Hermes and AGP versions. Nothing else changes a key, so a change anywhere else compiles no Rust. `node scripts/native.ts status` lists every part's key and where it is.

**Where they are**, in this order:

1. The machine's cache, shared by every worktree: `~/Library/Caches/stillfail-native/<part>/<target>-<key>/` on macOS, `$XDG_CACHE_HOME/stillfail-native` (or `~/.cache/stillfail-native`) on Linux, or `$STILLFAIL_NATIVE_CACHE`. A new worktree finds what another already got.
2. `$STILLFAIL_NATIVE_INBOX` (CI: a branch's run artifact, below).
3. The GitHub release [`native-artifacts`](https://github.com/AFK-surf/still.fail/releases/tag/native-artifacts), one asset per key (`<part>-<target>-<key>.tar.gz`). The repository is public, so any machine reads it with plain HTTPS: no login, no token, no cloud change. (The releases bucket was the other candidate: reading it outside still.fail cloud's `/releases/` whitelist needs Cloudflare credentials, and the whitelist is a Worker change per new file kind.)
4. Built here from the checkout, said on stderr (`native: mesh darwin-arm64 …: not prebuilt; building it here (cargo)…`), into the cache. Builds go to the crate's own `target/` (a worktree's own; never one shared between checkouts), or `$CARGO_TARGET_DIR/native/<part>` when that is set.

One process at a time gets or builds a key on a machine; others wait for it (a lock directory beside the cache entry), so parallel checks or worktrees never build a part twice. A cache entry appears atomically (renamed into place when complete).

**Who uses them.** `pnpm test` in `station/` and `client/core-ts/` runs `node ../scripts/native.ts run <parts> -- node --test …`, which sets `STILLFAIL_MESH_NATIVE`, `STILLFAIL_RUNNER`, `ARCHIVE_RS` and `STILLFAIL_RELAY_BIN` (unless already set). `pnpm run build` and `build:cloud` run `node scripts/native.ts iroh-pkg`, which puts the browser's iroh in `web/src/core/iroh-pkg` once per key. `scripts/station-bundle.sh`, `apps/desktop/build.sh` and `apps/android/build.py` take theirs from `native.ts file|path`. `scripts/check.sh` compiles Rust only for Rust's own tests (`cargo test` in `client/` and `station/native/*`), each only when that Rust changed.

```sh
node scripts/native.ts file mesh                 # the addon for this machine (prebuilt, or built)
node scripts/native.ts path engine android-arm64 # a directory
node scripts/native.ts key iroh-wasm             # its key
node scripts/native.ts build mesh linux-x64      # build it here, whatever is cached
STILLFAIL_NATIVE=build …                         # never download: build what the cache lacks
STILLFAIL_NATIVE=offline …                       # neither download nor build
STILLFAIL_ENGINE=cmake python3 apps/android/build.py  # the engine built by Gradle's CMake (working on engine.cpp)
```

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
`scripts/node-dist.sh` puts it beside the releases) and the desktop app, which runs its station on its own Electron as
Node. It is Electron's Node: upgrading Electron, `.node-version` goes with it (`apps/desktop/build.sh` stops otherwise).

## CI time

Every run of the pipeline ends with `timing` (`scripts/ci-time.ts`): the time from its first job starting to its last
ending, against a budget, in the run's summary, with a warning when over. The budgets (`BUDGET` there):

| Run | Budget | Typical (2026-10-04) |
|---|---|---|
| A branch | 180 s | ~100 s with caches warm |
| main, releasing nothing | 180 s | ~100 s |
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

Install an `iroh-relay` compatible with the project's iroh version. The hosted relay image currently uses 1.1.0 (see `cloud/Dockerfile`); prebuilt binaries are available in the [upstream release](https://github.com/n0-computer/iroh/releases/tag/v1.1.0). Run it locally in its own terminal:

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

## Local desktop packages

The desktop build currently targets macOS on Apple silicon. Install its dependencies and opt out of the maintainer's signing identity when making a local package:

```sh
(cd apps/desktop && pnpm install --frozen-lockfile)
UNSIGNED=1 sh apps/desktop/build.sh
# Or the beta app:
UNSIGNED=1 sh apps/desktop/build.sh --beta
```

`UNSIGNED=1` applies to both channels; it does not publish or install the app. The output is under `apps/desktop/out/mac-arm64/`. `DEV=1` stops before packaging. A redistributed fork also needs its own application identity, cloud origin and update feed; unsigned packaging alone does not configure those.

## Production self-hosting

The production path is Cloudflare-specific: Workers, Durable Objects, R2 and the relay Container, plus your own domains and Google OAuth client. Review `cloud/wrangler*.jsonc`, `cloud/deploy.py` and [cloud.md](cloud.md) before adapting it. The checked-in routes and release scripts target the maintainers' hosted service. Do not run them unchanged against a different account.

Keep secrets in an external deployment directory selected by `STILLFAIL_DEPLOY_DIR`; see the inputs documented at the top of `cloud/deploy.py`. Firebase push, Axiom and PostHog are additional integrations, not prerequisites for the mocked local cloud. Existing operations notes include historical deployment details and are not a turnkey self-hosting guide.

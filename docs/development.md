# Development

> Machine names in examples and measurements are anonymized; they are not requirements for the reader’s environment.


The commands below run from the repository root unless noted. The station, the client core and the Cloudflare Workers are TypeScript (Node.js); the app on every platform, the web's included, is MoonBit (`apps/mbui/`); a few native parts are Rust, prebuilt. Start with cloud tests if you do not need to build a client.

## Prerequisites

- Git, Python 3, Node.js 24 or later, and pnpm 10.33.0 (every `package.json` names it in `packageManager`).
- Rust is optional for everyday work: the native parts the TypeScript station and clients use are prebuilt (`scripts/native.ts`). To change one of them you need rustup (the parts are built with the toolchain pinned in `scripts/native.ts`, which rustup installs on first use), plus, per part: the `wasm32-unknown-unknown` target, `wasm-bindgen-cli` matching `wasm-bindgen` in `client/Cargo.lock` (currently 0.2.129) and LLVM's `clang`/`llvm-ar` with WebAssembly support for the browser's iroh; the NDK below for Android's shell and engine; zig and cargo-zigbuild for the Linux station parts from a Mac. libghostty-vt (`ghostty-vt`, the terminal's) needs nothing installed: its build fetches the zig its release asks for; CI never builds it, so a change to its version is prebuilt by hand on a Mac and published before the change is pushed (`node scripts/native.ts prebuild --release ghostty-vt:<target>…`, each of its targets).
- Android additionally needs JDK 17 and the Android SDK (NDK 28.2.13676358 to build its shell or engine, or to strip them when packing); the apps (`apps/mbui/`), the web app included, need MoonBit and their platform's toolchain, as [its README](../apps/mbui/README.md) says.

```sh
git clone https://github.com/AFK-surf/monoid.git
cd monoid
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

What cannot be made the same every run (real processes and signals, the native addon and iroh-relay over real sockets,
networks made up at random) is the side run's: `sh scripts/side.sh` (each package's `side/`; Rust's
`#[ignore = "side: …"]`; the locks and a rig end to end, `apps/mbui/scripts/e2e-local.sh locks-all` and
`rigs-all`), every four hours on main in CI (`.github/workflows/side.yml`, each part on a runner of its own; run it by hand with `gh workflow run side`),
blocking nothing. A side failure goes to an agent, which reproduces it as a test CI runs, failing the same way every
time, and fixes it; one it cannot reproduce is let be. Never a retry, a longer deadline or a looser bound to make a
test pass. A failed locks or rigs leaves its logs (the cloud's, the relay's, each station's apart), each device's record
of what its links did and the stations' locks as the run's artifact `side-<part>-<run>-<attempt>`, kept 3 days
(`gh run download <run>`; `apps/mbui/scripts/e2e-local.sh`, `kept`, says what is in it); in the job's log a device's lines begin
with its name (`E| …`).

## Browser and station builds

`client/iroh-wasm/build.sh` (what builds the `iroh-wasm` part) uses `LLVM_BIN` when set, otherwise checks Homebrew LLVM installations and then `clang`/`llvm-ar` on `PATH`. It checks for WebAssembly support before compiling. To choose a particular LLVM installation, set `LLVM_BIN` to its `bin` directory.

```sh
bash apps/mbui/scripts/web-app.sh
STILLFAIL_PREVIEW_ORIGIN=http://127.0.0.1:8790 pnpm run build:cloud
(cd station && pnpm install --frozen-lockfile)
sh scripts/station-bundle.sh /tmp/station   # [darwin-arm64|linux-x64|linux-arm64]
```

The first command builds the app for the browser into `web/public/mbui` (MoonBit; without it the web app's page has no app to draw). The second gets the browser's iroh (WebAssembly, prebuilt; the core itself is TypeScript, client/core-ts) and builds the local cloud's web/admin/preview assets, with previews pointing at the local preview host. This variable is read at build time; changing it requires rebuilding the web assets. If you change the development server's `PORT`, use its preview port (`PORT + 3`) here. Without this variable, the web build uses the hosted preview service.

The last one lays out a station release in `/tmp/station/stillfail` (the layout `scripts/station-bundle.sh` describes): the station bundled, its Node, its native parts (prebuilt) and `bin/stillfail`, as the installer has it.

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

## A station on Windows from a checkout

The station runs natively on Windows x64 from a checkout. It needs Git for Windows: jobs and device commands run under its `sh`, as Claude Code's own commands do there. From PowerShell (Git Bash's `tar` takes `C:` for a host, so `scripts/native.ts` runs from PowerShell):

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

The desktop apps are mbui's (`apps/mbui/`): `apps/mbui/scripts/mac-app.sh` makes the macOS app (signed ad hoc without `MAC_SIGN_IDENTITY`), `apps/mbui/scripts/win.sh build` and `win.sh setup` the Windows app and its installer (Git Bash with MSVC's environment); `MBUI_VARIANT=stable` or `beta` builds them as still.fail's released apps rather than still.fail preview, a test app of its own. None of these publishes or installs the app. A redistributed fork also needs its own application identity, cloud origin and update feed; building alone does not configure those.

## Production self-hosting

Outside Cloudflare, the cloud runs on workerd: [cloud/selfhost/README.md](../cloud/selfhost/README.md) (`node cloud/selfhost/build.ts`). On Cloudflare:

The production path is Cloudflare-specific: Workers, Durable Objects, R2 and the relay Container, plus your own domains and Google OAuth client. Review `cloud/wrangler*.jsonc` and `cloud/deploy.py` before adapting it. The checked-in routes and release scripts target the maintainers' hosted service. Do not run them unchanged against a different account.

Keep secrets in an external deployment directory selected by `STILLFAIL_DEPLOY_DIR`; see the inputs documented at the top of `cloud/deploy.py`. Firebase push, Google Cloud telemetry and PostHog are additional integrations, not prerequisites for the mocked local cloud. Existing operations notes include historical deployment details and are not a turnkey self-hosting guide.

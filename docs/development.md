# Development

The commands below run from the repository root unless noted. The core/station use Rust; the web UI and Cloudflare Workers use Node.js. Start with cloud tests if you do not need to build a client.

## Prerequisites

- Git, Python 3, Node.js 24 or later, and pnpm (the root manifest pins 10.11.1; `cloud/` pins 10.33.0).
- Rust via rustup, with an edition-2024 toolchain satisfying the dependency requirements (vendored iroh requires at least Rust 1.91).
- For the browser core: the `wasm32-unknown-unknown` target, `wasm-bindgen-cli` matching `wasm-bindgen` in `client/Cargo.lock` (currently 0.2.129), and LLVM's `clang`/`llvm-ar` with WebAssembly support.
- Native build tools for your OS. Android additionally needs JDK 17, the Android SDK and NDK 28.2.13676358; desktop packaging has its own dependencies in `apps/desktop/`.

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

## Browser and station builds

```sh
rustup target add wasm32-unknown-unknown
cargo install wasm-bindgen-cli --version 0.2.129 --locked
```

`client/wasm/build.sh` uses `LLVM_BIN` when set, otherwise checks Homebrew LLVM installations and then `clang`/`llvm-ar` on `PATH`. It checks for WebAssembly support before compiling. To choose a particular LLVM installation, set `LLVM_BIN` to its `bin` directory.

```sh
STILLFAIL_PREVIEW_ORIGIN=http://127.0.0.1:8790 pnpm run build:cloud
(cd mesh && cargo build --locked --release -p stillfail-station)
```

The first command builds the WebAssembly core and the local cloud's web/admin/preview assets, with previews pointing at the local preview host. This variable is read at build time; changing it requires rebuilding the web assets. If you change the development server's `PORT`, use its preview port (`PORT + 3`) here. Without this variable, the web build uses the hosted preview service.

The second command builds `mesh/target/release/stillfail-station` (or the directory selected by `CARGO_TARGET_DIR`).

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
bin/stillfail station enroll http://127.0.0.1:8787 <enrollment-token>
bin/stillfail start
```

The enrollment token is temporary; do not commit it. Keep `STILLFAIL_DATA` set to the same directory for subsequent station commands. If you use `CARGO_TARGET_DIR`, also set `STILLFAIL_STATION_BIN` to the built station executable. Configure your agent runtime in the local app when you need real agent execution; that step uses your own runtime account.

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

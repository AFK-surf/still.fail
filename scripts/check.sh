#!/bin/sh
# The checks for what changed. Two kinds:
#   quick: what a commit or push touches, in seconds (icons, TypeScript); the git hooks (.githooks) run it, on
#          whoever commits or pushes, so merging stays quick.
#   full:  that, the tests, cloud's tests, the core's tests, the web against the real iroh wasm, Rust and Android:
#          minutes. Run before a deploy (~/bin/ember-deploy on studio runs it on what the deploy carries).
#
#   sh scripts/check.sh commit        quick, on what is staged (pre-commit)
#   sh scripts/check.sh push <range>  quick, on what a push carries (pre-push), e.g. origin/main..HEAD
#   sh scripts/check.sh full <range>  full, on what the range changed
#   sh scripts/check.sh all           full, as if every file changed
#
# STILLFAIL_CHECK_PART=ts|station|core|android runs only that part of it (CI runs the four side by side): ts the
# icons, the clients' types and bindings, TypeScript, release notes and the tests run by node (web, scripts, cloud, the
# core: client/core-ts); station the station in TypeScript (station/, its typecheck and tests), its native parts'
# own tests (station/native) and the Rust station (mesh/); core client/'s Rust (the core's native shells: iroh for the
# web and Android's IO, the words); android the app. Unset: all of them.
#
# The native parts the TypeScript builds and tests use (the station's mesh addon and runner, the web's iroh, the
# Android shell and engine, …) are prebuilt (scripts/native.ts): Rust is compiled only where Rust changed, for its
# own tests, or for a native part whose source changed and that nobody has published yet.
#
# STILLFAIL_SKIP_CHECKS=1 (or EMBER_SKIP_CHECKS=1) skips it all (git's --no-verify does too); say why when you do.
set -eu
cd "$(dirname "$0")/.."
[ -n "${STILLFAIL_SKIP_CHECKS:-${EMBER_SKIP_CHECKS:-}}" ] && { echo "checks skipped (STILLFAIL_SKIP_CHECKS)"; exit 0; }
export PATH="$HOME/.cargo/bin:$PATH"
# One-off builds: incremental state only fills target/, and sccache (if set as the rustc wrapper) skips
# incremental crates.
export CARGO_INCREMENTAL=0

mode=${1:-commit}
full=0
case "$mode" in
  commit) changed=$(git diff --cached --name-only --diff-filter=ACMRD) ;;
  push) changed=$(git diff --name-only "${2:?push needs a range}") ;;
  full) full=1; changed=$(git diff --name-only "${2:?full needs a range}") ;;
  all) full=1; changed=$(git ls-files) ;;
  *) echo "usage: sh scripts/check.sh commit | push <range> | full <range> | all" >&2; exit 2 ;;
esac
[ -n "$changed" ] || exit 0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
touches() { printf '%s\n' "$changed" | grep -qE "$1"; }
# Whether this run does a part (STILLFAIL_CHECK_PART): any when it says none.
part() { [ -z "${STILLFAIL_CHECK_PART:-}" ] || [ "$STILLFAIL_CHECK_PART" = "$1" ]; }

failed=""
step() {
  name=$1; shift
  printf '· %s … ' "$name"
  log=$(mktemp)
  if "$@" > "$log" 2>&1; then echo ok; else echo FAILED; tail -40 "$log" | sed 's/^/    /'; failed="$failed $name"; fi
  rm -f "$log"
}
# What this machine has no toolchain for: fine for the quick check, a failure in the full one.
later() { if [ $full = 1 ]; then failed="$failed $1(no toolchain)"; fi; }
has() { command -v "$1" > /dev/null 2>&1; }

# node_modules as the lockfile says: a fresh worktree has none, an old checkout may miss what was added since.
# pnpm links from its store, and does nothing when all is there: quick either way.
deps() { (cd "$1" && pnpm install --frozen-lockfile --prefer-offline > /dev/null 2>&1); }

# The web core's iroh comes from its wasm build (web/src/core/iroh-pkg, not committed; the core itself is client/core-ts),
# prebuilt for its source (scripts/native.ts iroh-pkg). A machine that can neither get nor build it checks the web
# against stand-ins for the two modules it imports from there; main's deploy checks the real ones.
wasm_pkg() {
  pkg=web/src/core/iroh-pkg
  if node scripts/native.ts iroh-pkg > /dev/null 2>"$tmp/native.log"; then return 0; fi
  sed 's/^/    /' "$tmp/native.log"
  mkdir -p "$pkg"
  cat > "$pkg/stillfail_iroh_wasm.d.ts" <<'TS'
// A stand-in written by scripts/check.sh where iroh's wasm cannot be built (client/iroh-wasm/build.sh replaces it):
// what web/src/core/worker.ts uses of its exports.
export function bind(options: { secretKey: Uint8Array; relayUrls: string[] }): Promise<unknown>;
export default function init(module_or_path?: any): Promise<unknown>;
TS
  printf 'export declare const BUILT_AT: number;\n' > "$pkg/built.d.ts"
  printf 'export const BUILT_AT = 0;\n' > "$pkg/built.js"
  : > "$pkg/.stand-in"
}

if part ts; then
  ts_root='^(scripts|test|spike)/.*\.ts$|^(tsconfig\.json|package\.json|pnpm-lock\.yaml)$'
  ts_web='^web/'
  ts_cloud='^cloud/'
  ts_desktop='^apps/desktop/'
  ts_core='^client/core-ts/|^web/src/core/delta\.ts$'

  # The clients' types and the UIs' operation bindings are made from the core's (client/core-ts/src/shapes/schema.ts,
  # src/ops.ts): checked in, and never other than what those make.
  if touches '^client/core-ts/(src/shapes/|src/ops\.ts$|scripts/(shapes|operations)\.ts$)|^web/src/core/(shapes|operations)\.ts$|/data/(Shapes|Operations)\.kt$'; then
    deps client/core-ts
    step "clients' types" node client/core-ts/scripts/shapes.ts --check
    step "operation bindings" node client/core-ts/scripts/operations.ts --check
  fi

  if touches '^design/icons/|^scripts/icons\.py$|^web/src/icons\.tsx$|/ui/Icons\.kt$'; then
    step icons python3 scripts/icons.py --check
  fi
  # The UIs never make a request of a station or still.fail cloud themselves: they name what they want done
  # (client/core-ts/src/ops.ts), and the core, which knows what it changes, brings every topic that shows it up to date.
  if touches '^(web/src|apps/desktop/src|apps/android)/'; then
    step "no requests from the UIs" sh -c '! git grep -nE "(station|cloud)\.request" -- web/src apps/desktop/src apps/android'
  fi
  # Core tests also run for Rust-only client changes. A fresh CI checkout needs both
  # their JS dependencies and the real wasm package even when no TS file changed.
  core_tests=0
  if [ $full = 1 ] && touches '^(test|client|web/src/core)/|^package\.json$'; then core_tests=1; fi
  if touches "$ts_root" || touches "$ts_web" || touches "$ts_cloud" || touches "$ts_desktop" || [ $core_tests = 1 ]; then deps .; fi
  if touches "$ts_root" || touches "$ts_web" || [ $core_tests = 1 ]; then wasm_pkg; fi
  # The stable channel's release notes (docs/changelog.md): each one read as CI will.
  if touches '^docs/releases/|^scripts/changelog\.ts$'; then step "release notes" sh -c 'node scripts/changelog.ts --stable > /dev/null'; fi
  if touches "$ts_root"; then step "typecheck: scripts and tests" pnpm exec tsgo -p tsconfig.json; fi
  if touches "$ts_web"; then
    step "typecheck: web" pnpm exec tsgo -p web/tsconfig.json
    [ -f web/src/core/iroh-pkg/.stand-in ] && later "web against the real iroh wasm"
  fi
  if touches "$ts_cloud"; then
    deps cloud
    [ -f cloud/worker-configuration.d.ts ] || (cd cloud && pnpm run types > /dev/null 2>&1)
    step "typecheck: cloud" sh -c 'cd cloud && pnpm run check'
  fi
  if touches "$ts_desktop"; then deps apps/desktop; step "typecheck: desktop" sh -c 'cd apps/desktop && pnpm run typecheck'; fi
  # The TypeScript core (docs/core-ts.md): its own tsconfig.
  if touches "$ts_core"; then deps client/core-ts; step "typecheck: core-ts" sh -c 'cd client/core-ts && pnpm exec tsgo --noEmit'; fi

fi

if [ $full = 1 ]; then
  # The tests drive the web core itself (test/core-client.test.ts): only with a real build of it.
  if part ts && [ $core_tests = 1 ]; then
    if [ -f web/src/core/iroh-pkg/.stand-in ] || [ ! -f web/src/core/iroh-pkg/built.js ]; then later "tests (need the iroh wasm)"; else step "tests" pnpm test; fi
  fi
  # The TypeScript core's own tests; its mesh tests use the station's addon and n0's relay, prebuilt (its package.json).
  if part ts && touches "$ts_core|^station/native/mesh/|^vendor/"; then deps client/core-ts; step "tests: core-ts" sh -c 'cd client/core-ts && pnpm test'; fi
  if part ts && touches "$ts_cloud"; then step "tests: cloud" sh -c 'cd cloud && pnpm test'; fi
  # The station in TypeScript, with its native parts prebuilt (mesh addon, runner, the Rust archive for the
  # compatibility tests): its tests run whenever it or one of them changed.
  if part station && touches '^station/|^vendor/|^mesh/app/src/(archive\.rs|skills/)|^scripts/native\.ts$'; then
    deps station
    step "typecheck: station" sh -c 'cd station && pnpm exec tsgo --noEmit'
    step "tests: station" sh -c 'cd station && pnpm test'
  fi
  # The native parts' own tests, where their Rust changed.
  for crate in launcher runner mesh; do
    if part station && touches "^station/native/$crate/"; then
      if has cargo; then step "Rust: station/native/$crate" sh -c "cd station/native/$crate && cargo test --locked -q"; else later "Rust: station/native/$crate"; fi
    fi
  done
  # The Rust station (mesh/, which shares client/shapes and client/i18n), only when it changed.
  if part station && touches '^(mesh|vendor)/|^client/(shapes|i18n)/'; then
    if has cargo; then step "Rust: station" sh -c 'cd mesh && cargo test --workspace -q'; else later "Rust: station"; fi
  fi
  # The core's native shells (client/shell for Android, client/iroh-wasm for the web), the words, the shapes the Rust
  # station shares.
  if part core && touches '^client/(shell|iroh-wasm|i18n|shapes)/|^client/Cargo\.(toml|lock)$|^vendor/'; then
    if has cargo; then step "Rust: client" sh -c 'cd client && cargo test --workspace -q'; else later "Rust: client"; fi
  fi
  # Its shell and engine prebuilt (apps/android/build.py): only a JDK and the SDK needed.
  if part android && touches '^(apps/android|client)/'; then
    sdk=${ANDROID_HOME:-$HOME/Library/Android/sdk}
    if [ -d "$sdk/platforms" ]; then
      step "Android" python3 apps/android/build.py --tasks :app:compileDebugKotlin :app:testDebugUnitTest :core:testDebugUnitTest
    else later "Android"; fi
  fi
fi

if [ -n "$failed" ]; then
  echo "failed:$failed"
  [ $full = 0 ] && echo "(fix it; or, knowing why, skip once with git's --no-verify)"
  exit 1
fi

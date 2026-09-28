#!/bin/sh
# The checks for what changed, run where the change is made (.githooks: pre-commit and pre-push), so CI does not
# have to: whoever commits or pushes runs them. main's deploy (.github/workflows/main.yml) runs again only what a
# machine here could not (no Rust, no Android SDK).
#
#   sh scripts/check.sh commit        what is staged: icons, and the TypeScript of the parts it touches (seconds)
#   sh scripts/check.sh push <range>  what a push carries (e.g. origin/main..HEAD): typechecks, tests, cloud's tests,
#                                     and Rust, the clients' shapes and Android where their toolchains are here
#   sh scripts/check.sh all           everything, as if every file changed
#
# EMBER_SKIP_CHECKS=1 skips it all (git's --no-verify does too); say why when you do.
set -eu
cd "$(dirname "$0")/.."
[ -n "${EMBER_SKIP_CHECKS:-}" ] && { echo "checks skipped (EMBER_SKIP_CHECKS)"; exit 0; }
export PATH="$HOME/.cargo/bin:$PATH"

mode=${1:-commit}
case "$mode" in
  commit) changed=$(git diff --cached --name-only --diff-filter=ACMRD) ;;
  push) changed=$(git diff --name-only "${2:?push needs a range}") ;;
  all) changed=$(git ls-files) ;;
  *) echo "usage: sh scripts/check.sh commit | push <range> | all" >&2; exit 2 ;;
esac
[ -n "$changed" ] || exit 0
touches() { printf '%s\n' "$changed" | grep -qE "$1"; }

failed=""
left=""
step() {
  name=$1; shift
  printf '· %s … ' "$name"
  log=$(mktemp)
  if "$@" > "$log" 2>&1; then echo ok; else echo FAILED; tail -40 "$log" | sed 's/^/    /'; failed="$failed $name"; fi
  rm -f "$log"
}
later() { left="$left $1"; }
has() { command -v "$1" > /dev/null 2>&1; }

# node_modules where a fresh worktree has none (pnpm links from its store: quick).
deps() { [ -d "$1/node_modules" ] || (cd "$1" && pnpm install --frozen-lockfile --prefer-offline > /dev/null 2>&1); }

# The web core's types come from its wasm build (web/src/core/pkg, not committed). A machine that cannot build it
# checks the web against stand-ins for the two modules it imports from there; main's deploy checks the real ones.
wasm_pkg() {
  pkg=web/src/core/pkg
  [ -f "$pkg/ember_core_wasm.d.ts" ] && [ ! -f "$pkg/.stand-in" ] && return 0
  if has cargo && has wasm-bindgen && sh client/wasm/build.sh > /dev/null 2>&1; then return 0; fi
  mkdir -p "$pkg"
  cat > "$pkg/ember_core_wasm.d.ts" <<'TS'
// A stand-in written by scripts/check.sh where the wasm core cannot be built (client/wasm/build.sh replaces it):
// what web/src/core/worker.ts uses of client/wasm's exports.
export class EmberCore {
  private constructor();
  free(): void;
  connect(): number;
  disconnect(client: number): void;
  receive(client: number, message: any): void;
}
export function start(emit: Function): Promise<EmberCore>;
export default function init(module_or_path?: any): Promise<unknown>;
TS
  printf 'export declare const BUILT_AT: number;\n' > "$pkg/built.d.ts"
  : > "$pkg/.stand-in"
}

ts_root='^(scripts|test|spike)/.*\.ts$|^(tsconfig\.json|package\.json|pnpm-lock\.yaml)$'
ts_web='^web/|^client/shapes/'
ts_cloud='^cloud/'
ts_desktop='^apps/desktop/'

if touches '^design/icons/|^scripts/icons\.py$|^web/src/icons\.tsx$|/ui/Icons\.kt$'; then
  step icons python3 scripts/icons.py --check
fi
if touches "$ts_root" || touches "$ts_web" || touches "$ts_cloud" || touches "$ts_desktop"; then deps .; fi
# The tests import the web core too.
if touches "$ts_root" || touches "$ts_web"; then wasm_pkg; fi
if touches "$ts_root"; then step "typecheck: scripts and tests" pnpm exec tsgo -p tsconfig.json; fi
if touches "$ts_web"; then
  step "typecheck: web" pnpm exec tsgo -p web/tsconfig.json
  [ -f web/src/core/pkg/.stand-in ] && later "web against the real wasm core"
fi
if touches "$ts_cloud"; then
  deps cloud
  [ -f cloud/worker-configuration.d.ts ] || (cd cloud && pnpm run types > /dev/null 2>&1)
  step "typecheck: cloud" sh -c 'cd cloud && pnpm run check'
fi
if touches "$ts_desktop"; then deps apps/desktop; step "typecheck: desktop" sh -c 'cd apps/desktop && pnpm run typecheck'; fi

if [ "$mode" != commit ]; then
  # The tests drive the web core itself (test/core-client.test.ts): only with a real build of it.
  if touches '^(test|client|web/src/core)/|^package\.json$'; then
    if [ -f web/src/core/pkg/.stand-in ] || [ ! -f web/src/core/pkg/built.js ]; then later "tests (need the wasm core)"; else step "tests" pnpm test; fi
  fi
  if touches "$ts_cloud"; then step "tests: cloud" sh -c 'cd cloud && pnpm test'; fi
  if touches '^client/shapes/|^web/src/core/shapes\.ts$|/data/Shapes\.kt$'; then
    if has cargo; then step "shapes" sh scripts/shapes.sh --check; else later "shapes"; fi
  fi
  if touches '^(mesh|vendor)/'; then
    if has cargo; then step "Rust: station" sh -c 'cd mesh && cargo test --workspace -q'; else later "Rust: station"; fi
  fi
  if touches '^client/'; then
    if has cargo; then step "Rust: client core" sh -c 'cd client && cargo test --workspace --exclude ember-core-wasm -q'; else later "Rust: client core"; fi
  fi
  if touches '^(apps/android|client)/'; then
    sdk=${ANDROID_HOME:-$HOME/Library/Android/sdk}
    if has cargo && [ -d "$sdk/ndk/28.2.13676358" ]; then
      step "Android" python3 apps/android/build.py --tasks :app:compileDebugKotlin :core:testDebugUnitTest
    else later "Android"; fi
  fi
fi

[ -n "$left" ] && echo "not checked here (no toolchain), left to main's deploy:$left"
if [ -n "$failed" ]; then
  echo "failed:$failed"
  echo "(fix it; or, knowing why, skip once with git's --no-verify)"
  exit 1
fi

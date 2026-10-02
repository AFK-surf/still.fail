#!/bin/sh
# The checks for what changed. Two kinds:
#   quick: what a commit or push touches, in seconds (icons, TypeScript); the git hooks (.githooks) run it, on
#          whoever commits or pushes, so merging stays quick.
#   full:  that, the tests, cloud's tests, the web against the real wasm core, the clients' shapes, Rust and
#          Android: minutes. Run before a deploy (~/bin/ember-deploy on studio runs it on what the deploy carries).
#
#   sh scripts/check.sh commit        quick, on what is staged (pre-commit)
#   sh scripts/check.sh push <range>  quick, on what a push carries (pre-push), e.g. origin/main..HEAD
#   sh scripts/check.sh full <range>  full, on what the range changed
#   sh scripts/check.sh all           full, as if every file changed
#
# STILLFAIL_SKIP_CHECKS=1 (or EMBER_SKIP_CHECKS=1) skips it all (git's --no-verify does too); say why when you do.
set -eu
cd "$(dirname "$0")/.."
[ -n "${STILLFAIL_SKIP_CHECKS:-${EMBER_SKIP_CHECKS:-}}" ] && { echo "checks skipped (STILLFAIL_SKIP_CHECKS)"; exit 0; }
export PATH="$HOME/.cargo/bin:$PATH"

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
touches() { printf '%s\n' "$changed" | grep -qE "$1"; }

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

# The web core's types come from its wasm build (web/src/core/pkg, not committed). A machine that cannot build it
# checks the web against stand-ins for the two modules it imports from there; main's deploy checks the real ones.
wasm_pkg() {
  pkg=web/src/core/pkg
  # A real build kept from before is current only while the core is unchanged: built again when it changed.
  [ -f "$pkg/stillfail_core_wasm.d.ts" ] && [ ! -f "$pkg/.stand-in" ] && ! touches '^client/' && return 0
  if has cargo && has wasm-bindgen && sh client/wasm/build.sh > /dev/null 2>&1; then return 0; fi
  mkdir -p "$pkg"
  cat > "$pkg/stillfail_core_wasm.d.ts" <<'TS'
// A stand-in written by scripts/check.sh where the wasm core cannot be built (client/wasm/build.sh replaces it):
// what web/src/core/worker.ts uses of client/wasm's exports.
export class StillFailCore {
  private constructor();
  free(): void;
  connect(): number;
  disconnect(client: number): void;
  receive(client: number, message: any): void;
}
export function start(emit: Function, test_channel?: boolean | null): Promise<StillFailCore>;
export default function init(module_or_path?: any): Promise<unknown>;
TS
  printf 'export declare const BUILT_AT: number;\n' > "$pkg/built.d.ts"
  : > "$pkg/.stand-in"
}

if touches '^client/core/src/(ops|doing)\.rs$|^scripts/operations\.py$|^web/src/core/operations\.ts$|/data/Operations\.kt$'; then
  step "operation bindings" python3 scripts/operations.py --check
fi

ts_root='^(scripts|test|spike)/.*\.ts$|^(tsconfig\.json|package\.json|pnpm-lock\.yaml)$'
ts_web='^web/|^client/shapes/'
ts_cloud='^cloud/'
ts_desktop='^apps/desktop/'

if touches '^design/icons/|^scripts/icons\.py$|^web/src/icons\.tsx$|/ui/Icons\.kt$'; then
  step icons python3 scripts/icons.py --check
fi
# The UIs never make a request of a station or still.fail cloud themselves: they name what they want done (client/core/src/
# ops.rs), and the core, which knows what it changes, brings every topic that shows it up to date.
if touches '^(web/src|apps/desktop/src|apps/android)/'; then
  step "no requests from the UIs" sh -c '! git grep -nE "(station|cloud)\.request" -- web/src apps/desktop/src apps/android'
fi
if touches "$ts_root" || touches "$ts_web" || touches "$ts_cloud" || touches "$ts_desktop"; then deps .; fi
# The tests import the web core too.
if touches "$ts_root" || touches "$ts_web"; then wasm_pkg; fi
# The stable channel's release notes (docs/changelog.md): each one read as CI will.
if touches '^docs/releases/|^scripts/changelog\.ts$'; then step "release notes" sh -c 'node scripts/changelog.ts --stable > /dev/null'; fi
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

if [ $full = 1 ]; then
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
    if has cargo; then step "Rust: client core" sh -c 'cd client && cargo test --workspace --exclude stillfail-core-wasm -q'; else later "Rust: client core"; fi
  fi
  if touches '^(apps/android|client)/'; then
    sdk=${ANDROID_HOME:-$HOME/Library/Android/sdk}
    if has cargo && [ -d "$sdk/ndk/28.2.13676358" ]; then
      step "Android" python3 apps/android/build.py --tasks :app:compileDebugKotlin :app:testDebugUnitTest :core:testDebugUnitTest
    else later "Android"; fi
  fi
fi

if [ -n "$failed" ]; then
  echo "failed:$failed"
  [ $full = 0 ] && echo "(fix it; or, knowing why, skip once with git's --no-verify)"
  exit 1
fi

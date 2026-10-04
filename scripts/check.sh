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
# STILLFAIL_CHECK_PART="<part> …" (ts, station, core, android) runs only those parts of it: ts the icons, the clients' types and
# bindings, TypeScript, release notes and the tests run by node (web, scripts, cloud, the core: client/core-ts); station
# the station (station/, its typecheck and tests) and its native parts' own tests (station/native); core client/'s Rust
# (the core's native shells: iroh for the web and Android's IO); android the app. Unset: all of them.
#
# The steps run side by side, each as soon as what it needs is there (a directory's node_modules: `prep`); each one's
# output is kept to itself, and they are reported in the order they are listed here, as each is done, with the seconds
# it took (the end of its output when it failed). A run takes as long as its longest step, not all of them.
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
part() { [ -z "${STILLFAIL_CHECK_PART:-}" ] || case " $STILLFAIL_CHECK_PART " in *" $1 "*) true ;; *) false ;; esac; }

failed=""
n=0
light=""
# step <name> [after <prep>…] [heavy] <command…>: started now, in the background, once the preps it names are done. A
# heavy one (compiling: Rust, Android) waits for the light ones listed before it: those run in real time (the core's
# mesh, the station's agents, cloud's workers) and on a machine all of whose cores compile they ran out of time.
step() {
  n=$((n + 1))
  printf '%s\n' "$1" > "$tmp/step.$n.name"
  shift
  waits=""
  while [ "$1" = after ]; do waits="$waits $2"; shift 2; done
  before=""
  if [ "$1" = heavy ]; then before=$light; shift; else light="$light $n"; fi
  (
    set +e
    for k in $before; do until [ -e "$tmp/step.$k.done" ]; do sleep 0.1; done; done
    start=$(date +%s)
    {
      ok=1
      for w in $waits; do ready "$w" || { echo "preparing $w failed:"; cat "$tmp/prep.$w.log"; ok=0; break; }; done
      [ $ok = 1 ] && "$@"
    } > "$tmp/step.$n.log" 2>&1
    echo "$? $(( $(date +%s) - start ))" > "$tmp/step.$n.part"
    mv "$tmp/step.$n.part" "$tmp/step.$n.done"
  ) &
}
# prep <name> <command…>: something steps wait for (`after <name>`), started now in the background, once.
prep() {
  [ -e "$tmp/prep.$1.log" ] && return 0
  : > "$tmp/prep.$1.log"
  name=$1; shift
  ( set +e; "$@" > "$tmp/prep.$name.log" 2>&1; echo $? > "$tmp/prep.$name.part"; mv "$tmp/prep.$name.part" "$tmp/prep.$name.done" ) &
}
ready() {
  until [ -e "$tmp/prep.$1.done" ]; do sleep 0.1; done
  [ "$(cat "$tmp/prep.$1.done")" = 0 ]
}
# Says each step, in order, as it is done.
report() {
  i=0
  while [ $i -lt $n ]; do
    i=$((i + 1))
    name=$(cat "$tmp/step.$i.name")
    until [ -e "$tmp/step.$i.done" ]; do sleep 0.1; done
    read -r rc took < "$tmp/step.$i.done"
    if [ "$rc" = 0 ]; then echo "· $name … ok (${took} s)"; else
      echo "· $name … FAILED (${took} s)"
      tail -40 "$tmp/step.$i.log" | sed 's/^/    /'
      failed="$failed $name"
    fi
  done
  wait
}
# What this machine has no toolchain for: fine for the quick check, a failure in the full one.
later() { if [ $full = 1 ]; then failed="$failed $1(no toolchain)"; fi; }
has() { command -v "$1" > /dev/null 2>&1; }

# node_modules as the lockfile says: a fresh worktree has none, an old checkout may miss what was added since.
# pnpm links from its store, and does nothing when all is there: quick either way.
deps() { (cd "$1" && pnpm install --frozen-lockfile --prefer-offline); }
# The Rust each step builds goes to a target of its own where CARGO_TARGET_DIR names one for all (CI): steps side by
# side would otherwise wait on its lock, and two workspaces' builds of the vendored crates in one target can mix.
cargo_test() { (cd "$1" && shift && if [ -n "${CARGO_TARGET_DIR:-}" ]; then CARGO_TARGET_DIR="$CARGO_TARGET_DIR/$(printf '%s' "$PWD" | cksum | cut -d' ' -f1)"; fi && cargo test "$@"); }

# Tests remembered by what goes into them: where every input is committed (none changed in the worktree), the key is
# their git trees, this script, the toolchains and the machine's kind, and a step that passed at a key on this machine
# passes there again without running (a run of every part, CI's when .github/ changed, built each Rust crate's tests
# for a minute to run them for a second, and ran every suite again). A step's inputs are all it reads: its own
# directory and what it imports or runs from outside it (the native parts, by their sources: scripts/native.ts).
passed_dir=${XDG_CACHE_HOME:-$HOME/.cache}/stillfail-check/passed
inputs_key() {
  [ -z "$(git status --porcelain -- "$@" scripts/check.sh)" ] || return 1
  { git ls-tree HEAD -- "$@" scripts/check.sh; rustc -V; node -v; uname -sm; } 2>/dev/null | cksum | tr ' ' -
}
# remember <key> <command…>: runs it, and marks the key passed when it does.
remember() {
  key=$1; shift
  "$@" || return 1
  [ -n "$key" ] && mkdir -p "$passed_dir" && : > "$passed_dir/$key"
  return 0
}
# remembered <name> <inputs> [after <prep>…] [heavy] <command…>: the step, or that it passed before at these inputs.
remembered() {
  name=$1; inputs=$2; shift 2
  # shellcheck disable=SC2086 # the inputs are paths, split on purpose
  key=$(inputs_key $inputs) && key="$(printf '%s' "$name" | cksum | cut -d' ' -f1)-$key" || key=""
  if [ -n "$key" ] && [ -e "$passed_dir/$key" ]; then
    step "$name (passed before, same inputs)" true
    return
  fi
  opts=""
  while [ "$1" = after ]; do opts="$opts after $2"; shift 2; done
  [ "$1" = heavy ] && { opts="$opts heavy"; shift; }
  # shellcheck disable=SC2086 # the options are words, split on purpose
  step "$name" $opts remember "$key" "$@"
}

# Cloudflare's types for the worker (cloud/worker-configuration.d.ts, not committed), once its dependencies are there:
# `wrangler types` takes seconds, so what it made is kept, by what it is made from, for every worktree on this machine.
after_cloud_types() {
  ready cloud || return 1
  [ -f cloud/worker-configuration.d.ts ] && return 0
  key=$(cat cloud/wrangler.jsonc cloud/pnpm-lock.yaml cloud/.dev.vars 2>/dev/null | cksum | tr ' ' -)
  cache=${XDG_CACHE_HOME:-$HOME/.cache}/stillfail-check/worker-configuration-$key.d.ts
  if [ -f "$cache" ]; then cp "$cache" cloud/worker-configuration.d.ts; return 0; fi
  (cd cloud && pnpm run types) || return 1
  mkdir -p "$(dirname "$cache")" && cp cloud/worker-configuration.d.ts "$cache.$$" && mv "$cache.$$" "$cache"
}

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
    prep core deps client/core-ts
    step "clients' types" after core node client/core-ts/scripts/shapes.ts --check
    step "operation bindings" after core node client/core-ts/scripts/operations.ts --check
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
  if touches "$ts_root" || touches "$ts_web" || touches "$ts_cloud" || touches "$ts_desktop" || [ $core_tests = 1 ]; then prep root deps .; fi
  if touches "$ts_root" || touches "$ts_web" || [ $core_tests = 1 ]; then wasm_pkg; fi
  # The stable channel's release notes (docs/changelog.md): each one read as CI will.
  if touches '^docs/releases/|^scripts/changelog\.ts$'; then step "release notes" sh -c 'node scripts/changelog.ts --stable > /dev/null'; fi
  if touches "$ts_root"; then step "typecheck: scripts and tests" after root pnpm exec tsgo -p tsconfig.json; fi
  if touches "$ts_web"; then
    step "typecheck: web" after root pnpm exec tsgo -p web/tsconfig.json
    [ -f web/src/core/iroh-pkg/.stand-in ] && later "web against the real iroh wasm"
  fi
  if touches "$ts_cloud"; then
    prep cloud deps cloud
    prep cloud-types after_cloud_types
    step "typecheck: cloud" after cloud after cloud-types sh -c 'cd cloud && pnpm run check'
  fi
  if touches "$ts_desktop"; then prep desktop deps apps/desktop; step "typecheck: desktop" after desktop sh -c 'cd apps/desktop && pnpm run typecheck'; fi
  # The TypeScript core (docs/core-ts.md): its own tsconfig.
  if touches "$ts_core"; then prep core deps client/core-ts; step "typecheck: core-ts" after core sh -c 'cd client/core-ts && pnpm exec tsgo --noEmit'; fi

fi

if [ $full = 1 ]; then
  # The tests drive the web core itself (test/core-client.test.ts): only with a real build of it.
  if part ts && [ $core_tests = 1 ]; then
    if [ -f web/src/core/iroh-pkg/.stand-in ] || [ ! -f web/src/core/iroh-pkg/built.js ]; then later "tests (need the iroh wasm)"; else step "tests" after root pnpm test; fi
  fi
  # The TypeScript core's own tests; its mesh tests use the station's addon and n0's relay, prebuilt (its package.json).
  if part ts && touches "$ts_core|^station/native/mesh/|^vendor/"; then prep core deps client/core-ts; remembered "tests: core-ts" "client/core-ts client/i18n web/src/core web/public/avatars station/native/mesh vendor scripts/native.ts" after core sh -c 'cd client/core-ts && pnpm test'; fi
  if part ts && touches "$ts_cloud"; then remembered "tests: cloud" "cloud client/i18n" after cloud sh -c 'cd cloud && pnpm test'; fi
  # The station, with its native parts prebuilt (mesh addon, runner, the Rust station's archive for the compatibility
  # tests): its tests run whenever it, one of them or the words it says changed.
  if part station && touches '^station/|^vendor/|^client/i18n/|^scripts/native\.ts$'; then
    prep station deps station
    step "typecheck: station" after station sh -c 'cd station && pnpm exec tsgo --noEmit'
    # The station's time is its Clock's (docs/station-ts.md, 写法): the machine's only through ops/fibers.ts' wall.
    step "station: time through its clock" sh -c '! git grep -nE "Date\.now\(|new Date\(\)|setTimeout\(|setInterval\(" -- station/src ":!station/src/ops/fibers.ts"'
    remembered "tests: station" "station client/i18n vendor scripts/native.ts" after station sh -c 'cd station && pnpm test'
  fi
  # The native parts' own tests, where their Rust changed (the mesh addon's: the vendored crates it patches in, too).
  for crate in launcher runner mesh; do
    also='^$'; [ $crate = mesh ] && also='^vendor/'
    if part station && { touches "^station/native/$crate/" || touches "$also"; }; then
      inputs="station/native/$crate"; [ $crate = mesh ] && inputs="$inputs vendor"
      if has cargo; then remembered "Rust: station/native/$crate" "$inputs" heavy cargo_test "station/native/$crate" --locked -q; else later "Rust: station/native/$crate"; fi
    fi
  done
  # The core's native shells (client/shell for Android, client/iroh-wasm for the web).
  if part core && touches '^client/(shell|iroh-wasm)/|^client/Cargo\.(toml|lock)$|^vendor/'; then
    if has cargo; then remembered "Rust: client" "client vendor" heavy cargo_test client --workspace -q; else later "Rust: client"; fi
  fi
  # Its shell and engine prebuilt (apps/android/build.py): only a JDK and the SDK needed.
  # The app carries the visualizations' page (web/src/viz) and the native parts. STILLFAIL_CHECK_APK=1 (a branch's CI)
  # makes the debug app in the same Gradle run, as evidence it builds: one build, not a second job doing it again.
  if part android && touches '^(apps/android|client|web/src/viz)/|^scripts/native\.ts$'; then
    sdk=${ANDROID_HOME:-$HOME/Library/Android/sdk}
    if [ -d "$sdk/platforms" ]; then
      remembered "Android${STILLFAIL_CHECK_APK:+ (and the debug app)}" "apps/android client web/src/viz scripts/native.ts scripts/icons.py design/icons package.json pnpm-lock.yaml" heavy python3 apps/android/build.py --tasks :app:compileDebugKotlin :app:testDebugUnitTest :core:testDebugUnitTest :app:lintDebug :core:lintDebug ${STILLFAIL_CHECK_APK:+:app:assembleDebug}
    else later "Android"; fi
  fi
fi

report
if [ -n "$failed" ]; then
  echo "failed:$failed"
  [ $full = 0 ] && echo "(fix it; or, knowing why, skip once with git's --no-verify)"
  exit 1
fi

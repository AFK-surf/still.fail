#!/bin/sh
# The checks for what changed. Two kinds:
#   quick: what a commit or push touches, in seconds (icons, TypeScript); the git hooks (.githooks) run it, on
#          whoever commits or pushes, so merging stays quick.
#   full:  that, the tests, cloud's tests, the core's tests, the web against the real iroh wasm, Rust:
#          minutes. Run before a deploy on what the deploy carries.
#
#   sh scripts/check.sh commit        quick, on what is staged (pre-commit)
#   sh scripts/check.sh push <range>  quick, on what a push carries (pre-push), e.g. origin/main..HEAD
#   sh scripts/check.sh full <range>  full, on what the range changed
#   sh scripts/check.sh all           full, as if every file changed
#
# STILLFAIL_CHECK_PART="<part> …" (ts, core-tests, station, station-tests, core) runs only those parts of it: ts the
# icons, the clients' types and bindings, TypeScript, release notes and the tests run by node (web, scripts, cloud);
# core-tests the core's own tests (client/core-ts/test), all of them or, with STILLFAIL_CORE_SHARD="<i>/<n>", the i-th
# slice of n; station the station (station/: its typecheck, its programs in MoonBit) and its native parts' own
# tests (station/native); station-tests the station's tests (station/test), all of them or, with
# STILLFAIL_STATION_SHARD="<i>/<n>", the i-th slice of n; core client/'s Rust (the core's native shells: iroh for the
# web and the apps' IO). Unset: all of them.
#
# The steps run side by side, each as soon as what it needs is there (a directory's node_modules: `prep`); each one's
# output is kept to itself, and they are reported in the order they are listed here, as each is done, with the seconds
# it took (the end of its output when it failed). A run takes as long as its longest step, not all of them.
#
# STILLFAIL_SKIP_CHECKS=1 skips it all (git's --no-verify does too); say why when you do.
set -eu
cd "$(dirname "$0")/.."
[ -n "${STILLFAIL_SKIP_CHECKS:-}" ] && { echo "checks skipped (STILLFAIL_SKIP_CHECKS)"; exit 0; }
export PATH="$HOME/.cargo/bin:$PATH"
# One-off builds: incremental state only fills target/, and sccache (if set as the rustc wrapper) skips
# incremental crates.
export CARGO_INCREMENTAL=0

mode=${1:-commit}
full=0
# A commit that concludes a merge (main merged into a branch) is checked against what is merged in: what the branch has
# that main does not, as CI checks it. Against HEAD it would be all main got meanwhile, none of it this commit's.
against=HEAD
if [ "$mode" = commit ] && git rev-parse -q --verify MERGE_HEAD > /dev/null; then against=MERGE_HEAD; fi
case "$mode" in
  commit) changed=$(git diff --cached --name-only --diff-filter=ACMRD "$against" 2>/dev/null || git diff --cached --name-only --diff-filter=ACMRD) ;;
  push) range=${2:?push needs a range}; changed=$(git diff --name-only "$range") ;;
  full) full=1; range=${2:?full needs a range}; changed=$(git diff --name-only "$range") ;;
  all) full=1; changed=$(git ls-files) ;;
  *) echo "usage: sh scripts/check.sh commit | push <range> | full <range> | all" >&2; exit 2 ;;
esac
[ -n "$changed" ] || exit 0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
touches() { printf '%s\n' "$changed" | grep -qE "$1"; }
# The lines this run's change adds to the files given (none for `all`, which checks what is, not what changed). A line
# it only moves (taken out of one of them, put in another as it was: a part moved into web/ui) is not added.
added() {
  case "$mode" in
    commit) git diff --cached -U0 "$against" -- "$@" 2>/dev/null || git diff --cached -U0 -- "$@" ;;
    push|full) git diff -U0 "$range" -- "$@" ;;
    *) ;;
  esac > "$tmp/diff"
  grep -E '^-[^-]' "$tmp/diff" | cut -c2- > "$tmp/taken" || true
  grep -E '^\+[^+]' "$tmp/diff" | cut -c2- | grep -vxF -f "$tmp/taken" | sed 's/^/+/' || true
}
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
    echo "$start" > "$tmp/step.$n.start"
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
# The steps started and not done, with how long each has run (and with `tail`, the end of each one's output so far).
running() {
  now=$(date +%s)
  k=0
  while [ $k -lt $n ]; do
    k=$((k + 1))
    [ -e "$tmp/step.$k.start" ] && [ ! -e "$tmp/step.$k.done" ] || continue
    echo "  … $(cat "$tmp/step.$k.name"): running, $((now - $(cat "$tmp/step.$k.start"))) s"
    [ -z "${1:-}" ] || tail -20 "$tmp/step.$k.log" | sed 's/^/      /'
  done
}
# Stopped (CI's time up, ^C): which steps were still running, and where each had got to, said before it ends (a
# check stopped after 10 minutes said only the last step done, not the one it waited for: 39468530573).
# And the test files still running under it, how long each had run: a step's output says only the tests that ended, and
# the one that hung never does (the station's tests stopped at 5 minutes, feat/outflow-tailcat, 41570711413).
below() { for c in $(pgrep -P "$1" 2>/dev/null); do echo "$c"; below "$c"; done; }
open_tests() {
  for p in $(below $$); do ps -o etime= -o args= -p "$p" 2>/dev/null; done | awk 'gsub(/\.test\.(ts|mts|mjs|js)/, "&") == 1 { for (i = 2; i <= NF; i++) if ($i ~ /\.test\.(ts|mts|mjs|js)$/) print "  ◦ " $1 " " $i }'
  # Each of them asked which of its tests runs, or what it still has open (station/test/setup-env.mjs), and the
  # processes under it: the file alone did not say which test hung (41597210040, test/sandbox.test.ts).
  hung=""
  # (One file each: the runner above them names them all.)
  for p in $(below $$); do ps -o args= -p "$p" 2>/dev/null | awk 'gsub(/\.test\.(ts|mts|mjs|js)/, "&") != 1 { exit 1 }' && kill -USR2 "$p" 2>/dev/null && hung="$hung $p"; done
  [ -n "$hung" ] || return 0
  # Until each has answered, half a second at most: the runner ends the job about a second after its signal, and a
  # whole second waited here was all of it (42939482348: test/screens.test.ts, hung with every test passed, was named
  # and the job ended before what it had open was said).
  w=0
  while [ $w -lt 5 ]; do
    answered=1
    for p in $hung; do [ -e "$STILLFAIL_TEST_HUNG/$p" ] || answered=0; done
    [ $answered = 0 ] || break
    sleep 0.1
    w=$((w + 1))
  done
  for p in $hung; do
    # (One that wrote nothing did not get to the signal: its thread held in a call, or the process ending. Its state
    # and the CPU it takes say which.)
    [ -e "$STILLFAIL_TEST_HUNG/$p" ] || ps -o pid= -o stat= -o pcpu= -o etime= -p "$p" 2>/dev/null | sed 's/^/    did not answer (pid, state, CPU %, since): /'
    sed 's/^/    /' "$STILLFAIL_TEST_HUNG/$p" 2>/dev/null
    for c in $(below "$p"); do ps -o pid= -o etime= -o args= -p "$c" 2>/dev/null | cut -c1-200 | sed 's/^/      under it: /'; done
  done
}
export STILLFAIL_TEST_HUNG="$tmp/hung"
mkdir -p "$STILLFAIL_TEST_HUNG"
trap 'echo "stopped; still running:"; running tail; open_tests; exit 1' INT TERM
# Says each step, in order, as it is done; every minute spent waiting, the ones still running.
report() {
  i=0
  while [ $i -lt $n ]; do
    i=$((i + 1))
    name=$(cat "$tmp/step.$i.name")
    w=0
    until [ -e "$tmp/step.$i.done" ]; do
      sleep 0.1
      w=$((w + 1))
      [ $((w % 600)) != 0 ] || running
    done
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
  # (the core's own files the web imports and typechecks under its stricter settings: a change there alone, #2395's
  # util.ts import in error.ts, passed its own check and turned main red at the next change to the web, 8cb036d5)
  web_reads='^client/core-ts/src/'
  # (cloud's lock is station's, through the rules: cloud/src/lock.ts imports station/src/cloud/lock.ts)
  ts_cloud='^cloud/|^station/src/cloud/lock\.ts$|^client/core-ts/src/lock-form\.ts$|^rules/js/'
  ts_core='^client/core-ts/|^web/src/core/delta\.ts$'

  # The clients' types and the UIs' operation bindings are made from the core's (client/core-ts/src/shapes/schema.ts,
  # src/ops.ts): checked in, and never other than what those make.
  if touches '^client/core-ts/(src/shapes/|src/ops\.ts$|scripts/(shapes|operations)\.ts$)|^web/src/core/(shapes|operations)\.ts$'; then
    prep core deps client/core-ts
    step "clients' types" after core node client/core-ts/scripts/shapes.ts --check
    step "operation bindings" after core node client/core-ts/scripts/operations.ts --check
  fi
  # still.fail's colours are web/ui/src/palette.ts's (the app's palette made from it); the web's curves are the app's.
  if touches '^web/ui/src/(palette|curves-data)\.ts$|^scripts/(palette|curves)\.ts$|^apps/mbui/src/sf/(palette_data|tokens)\.mbt$|^libs/mbui/src/ui/motion\.mbt$'; then
    step "palette and curves" sh -c 'node scripts/palette.ts --check && node scripts/curves.ts --check'
  fi
  # The app's UI fault categories are the core's (client/core-ts/src/ui-faults.ts).
  if touches '^client/core-ts/(src/ui-faults\.ts|scripts/ui-faults\.ts)$|^apps/mbui/src/stillfail/ui_faults\.mbt$'; then
    step "UI fault categories" node client/core-ts/scripts/ui-faults.ts --check
  fi

  # The agents' rules name only what is there (AGENTS.md: These files are kept true): any change may move what one names.
  step "AGENTS.md paths" node scripts/agents-paths.ts

  if touches '^design/(station-)?icons/|^apps/mbui/(tools/icons/|scripts/icons$)|^web/ui/src/icons\.tsx$'; then
    step icons bash apps/mbui/scripts/icons . --check
  fi
  # Every file cloud's api, the station and the beta apps' core are built from deploys them (scripts/plan.sh).
  if touches '^(cloud/src/|station/src/|client/|apps/mbui/core/|rules/|scripts/plan)'; then
    prep station deps station
    step "what is deployed for each file" after station node scripts/plan-covers.ts
  fi
  # Every CI job may take 5 minutes at most (only scripts/ci-timeouts.py's LONGER 10), and says so (timeout-minutes).
  if touches '^\.github/workflows/|^scripts/ci-timeouts\.py$'; then
    step "CI jobs: 5 minutes at most" python3 scripts/ci-timeouts.py
  fi
  # The UIs never make a request of a station or still.fail cloud themselves: they name what they want done
  # (client/core-ts/src/ops.ts), and the core, which knows what it changes, brings every topic that shows it up to date.
  # the Wasm side of the native host's calls as their declarations make it
  if touches '^libs/mbui/src/host/.*native\.mbt$|^apps/mbui/src/(core|stillfail|pinyin|sfreplay)/.*native\.mbt$|^libs/mbui/tools/wasmhost/'; then
    step "wasm host calls" bash apps/mbui/scripts/wasm-app.sh check
  fi
  if touches '^(web/src|web/ui|apps/mbui/src)/'; then
    step "no requests from the UIs" sh -c '! git grep -nE "(station|cloud)\.request" -- web/src web/ui apps/mbui/src'
  fi
  # The design system (web/ui, @stillfail/ui) stands on its own: nothing of the app's (web/src: its core, station,
  # cloud, preferences), so the share page and anything else can draw with it. The app gives it what it needs (words,
  # language, shortcut keys) through its setters.
  if touches '^web/ui/'; then
    step "the design system on its own" sh -c '! git grep -nE "(from|import) +\"(\.\./)+(src|client|station|cloud)/|@stillfail/core-ts" -- web/ui'
  fi
  # Colours mixed in sRGB: Chromium leaves an OKLCH mix of near greys with its hue unset but a little chroma, and draws
  # it at hue 0, so the grey grounds (code, tables, tool steps) turned pink.
  if touches '^(web/src|web/ui)/'; then
    step "colours mixed in sRGB" sh -c '! git grep -n "in oklch" -- web/src web/ui'
  fi
  # Prefixes are the build's (Lightning CSS adds -webkit- where the browsers built for want it). Written by hand after
  # the standard property, Lightning CSS keeps only the last of the two, the prefixed one: Chrome drew no frosted glass
  # behind the site's bar, the composer or the viewers, and selected text the styles said not to.
  if touches '^(web/src|web/ui)/'; then
    step "prefixes from the build" sh -c '! git grep -nE "Webkit(BackdropFilter|UserSelect|Mask[A-Za-z]*|BoxDecorationBreak):" -- web/src web/ui'
  fi
  # Type sizes are the tokens' (web/ui/src/styles/tokens.css.ts: text-micro … text-display), never a style's own (an em, relative to its text, may be).
  if touches '^web/(src|ui)/'; then
    step "type sizes from tokens" sh -c '! git grep -nE "fontSize: *(\"[0-9.]+(px|rem)|[0-9])|font: *\"[^\"]*[0-9.]+px" -- "web/src/*.css.ts" "web/ui/*.css.ts"'
    # Three weights: 400, 500 to stand out, 600 for titles (the official site's hero aside).
    step "three type weights" sh -c '! git grep -nE "fontWeight: *\"?(100|200|300|[5-6][1-9]0|[5-6][0-9][1-9]|7[0-9]{2}|8[0-9]{2}|9[0-9]{2}|bold|bolder|lighter)\b" -- "web/src/*.css.ts" "web/ui/*.css.ts" ":!web/src/site/"'
    # The safe area is read through --safe-top … (styles/global.css.ts), never env() itself: the stories put the page on
    # each phone's by setting those.
    step "safe area through its vars" sh -c '! git grep -n "env(safe-area-inset" -- "web/src/*.ts" "web/src/*.tsx" "web/ui/*.ts" "web/ui/*.tsx" ":!web/src/styles/global.css.ts"'
    # Motion reduced is read from the page's root (@stillfail/ui styles/still.ts STILL, motion.ts reducedMotion), which
    # the 外观 page's setting decides when it says so; a media query of its own would not hear the setting. The official
    # site's own motion, before its script runs, goes by the query.
    step "reduced motion from the root" sh -c '! git grep -n "prefers-reduced-motion" -- "web/src/*.ts" "web/src/*.tsx" "web/ui/*.ts" "web/ui/*.tsx" ":!web/ui/src/motion.ts" ":!web/ui/src/styles/still.ts" ":!web/src/site/"'
    # Motion reduced is one clock, not a way of its own (motion.ts reducedMotion): a script plays through it (Motion's
    # animate, play, motionMs, glideShare) and does what it does as ever, its motion only taking no time. What loops
    # (motion.ts restingLoop), the phone's bar on its own springs and the official site's pointer play are all that ask.
    step "reduced motion as one clock" sh -c '! git grep -nE "reducedMotion\(\)|\.animate\(" -- "web/src/*.ts" "web/src/*.tsx" "web/ui/*.ts" "web/ui/*.tsx" ":!web/ui/src/motion.ts" ":!web/src/mobile/Bar.tsx" ":!web/src/site/motion.ts"'
    # No corner of its own in what a change adds: a corner is a token (vars.r*) or follows what it sits in (align.ts
    # surface/inner, docs/ui-panels.md); circles, capsules and marks of 4 or less may say theirs, as may a line that says
    # why with "own corner:".
    added 'web/src/*.css.ts' 'web/ui/*.css.ts' | grep -E '[bB]order[A-Za-z]*Radius: *([`"][^`"]*([5-9]|[1-9][0-9]+)(\.[0-9]+)?px|([5-9]|[1-9][0-9]+)\b)' \
      | grep -vE 'Radius: *("999px"|999\b)|own corner:' > "$tmp/corners" || true
    step "no corner of its own (in what this adds)" sh -c "! grep . '$tmp/corners'"
    # One light for the pointer in what a change adds: a hover lays the ink, `vars.hover` (lit.ts
    # `litOver` over a ground of its own), or takes a solid ground a step towards the page (`vars.primaryHover`, a colour
    # 85% mixed with the canvas); never a colour, a tint or a filter of its own. One that must says why with "own hover:".
    added 'web/src/*.css.ts' 'web/ui/*.css.ts' | grep -E ':hover[^{]*\{[^}]*(background(Color)?|filter): *' \
      | grep -vE '(background(Color)?): *(vars\.hover|vars\.primaryHover|ink|"none"|"transparent")\b|85%, \$\{vars\.canvas\}|own hover:' > "$tmp/hovers" || true
    step "one light for the pointer (in what this adds)" sh -c "! grep . '$tmp/hovers'"
    # No margin taken back by hand: a ground reaching past its words, a corner, a column, a centring is one of
    # styles/align.ts's (bleedX, surface, columns, centred…), so its numbers are said once (a var's own negative may be).
    step "no hand-written negative margins" sh -c '! git grep -nE "margin[A-Za-z]*: *(-[0-9]|[\"\`][^\"\`]*[ (]-[0-9]|[\"\`]-[0-9])" -- "web/src/*.css.ts" "web/ui/*.css.ts" | grep -v "calc(-1 \* var("'
    # A small panel stands on controls.css.ts popover: surface() only for it and the three that are not
    # popovers (a notice, ⌘K, the composer's list of chats).
    step "small panels on one ground" sh -c '! git grep -n "\.\.\.surface(" -- "web/src/*.css.ts" "web/ui/*.css.ts" ":!web/ui/src/styles/controls.css.ts" ":!web/src/SystemBubbles.css.ts" ":!web/src/Switcher.css.ts" ":!web/src/ChatRef.css.ts"'
  fi
  # (Its own condition: inside the web pages' block it ran only when a change touched web/src or web/ui.)
  if touches '^(client/core-ts/src|station/src|cloud/src)/'; then
    # No polling between still.fail's own parts (AGENTS.md): what a change adds to the core, the station or the cloud sets
    # no timer that reads something of another part again; that part tells (an event, a stream). A timer that must be
    # says on its line which it is with "timer:" (a heartbeat, a sample of this machine, a retry after a failure, a
    # timeout or deadline, a debounce, an outside system that tells nothing). (`.every(` with a time: a list's is not one.)
    added 'client/core-ts/src/*.ts' 'station/src/*.ts' 'cloud/src/*.ts' | grep -nE '\.every\(([A-Z0-9]|this\.timing)|setInterval\(|Schedule\.(spaced|fixed|exponential)|Effect\.repeat\(|Effect\.forever\(' \
      | grep -v 'timer:' > "$tmp/timers" || true
    step "no polling between still.fail's parts (in what this adds)" sh -c "! grep . '$tmp/timers'"
  fi
  # The station's main thread waits on nothing (station/AGENTS.md): what a change adds there calls no synchronous file
  # call, process or compression of node's (fs, child_process, zlib) unless its line says why with "sync:". What runs on
  # no other thread may: a worker's own file (`*worker.ts`), the readers' (src/read/, but for what of it the main thread
  # runs: the pool, the builders and their requests, and the transcripts it follows), the command line (src/cli.ts), and
  # the update's (src/updates/command.ts, `stillfail-station update`, and the delta applier it alone runs,
  # src/updates/delta.ts: a process apart, release.ts applyApart; flagged on main 154f6d15, 42758290890, 2026-11-10).
  if touches '^station/src/'; then
    {
      added 'station/src/*.ts' ':(exclude,glob)station/src/**/*worker.ts' ':(exclude)station/src/read' ':(exclude)station/src/cli.ts' \
        ':(exclude)station/src/updates/command.ts' ':(exclude)station/src/updates/delta.ts'
      added 'station/src/read/pool.ts' 'station/src/read/mb-reader.ts' 'station/src/read/tail.ts' 'station/src/read/transcript.ts' \
        'station/src/read/packed.ts' 'station/src/read/plan.ts' 'station/src/read/*-builder.ts' 'station/src/read/*-requests.ts' ':(exclude,glob)station/src/**/*worker.ts'
    } | grep -nE '\b(access|appendFile|chmod|chown|close|copyFile|cp|exists|fchmod|fchown|fdatasync|fstat|fsync|ftruncate|futimes|lchown|link|lstat|lutimes|mkdir|mkdtemp|open|opendir|read|readdir|readFile|readlink|readv|realpath|rename|rm|rmdir|stat|statfs|symlink|truncate|unlink|utimes|write|writeFile|writev|exec|execFile|spawn|gzip|gunzip|deflate|deflateRaw|inflate|inflateRaw|unzip|brotliCompress|brotliDecompress|zstdCompress|zstdDecompress)Sync(\.native)?\(' \
      | grep -v 'sync:' > "$tmp/syncs" || true
    step "the station's main thread waits on nothing (in what this adds)" sh -c "! grep . '$tmp/syncs'"
  fi
  # No way into a station from outside (AGENTS.md): every socket a station listens on is this machine's own, and says
  # so on its line (127.0.0.1; the fd the launcher holds, a Unix socket's path); the mesh's endpoint is bound by
  # mesh/native.ts. No tunnel in the station or the cloud. (A `.listen(` given a function is an event's, not a socket's.)
  if touches '^(station/src|station/native|cloud/src)/'; then
    step "stations listen on this machine only" sh -c '! git grep -nE "\.listen\((\{|[^()=>]*,)|TcpListener::bind|UdpSocket::bind" -- station/src station/native cloud/src ":!*/tests/*" ":!*.test.*" | grep -vE "127\.0\.0\.1|\bfd\b|\bpath\b"'
    step "no tunnel into a station" sh -c '! git grep -niE "tailcat|ngrok|cloudflared|localtunnel|trycloudflare|tailscale (funnel|serve)" -- station/src station/native cloud/src'
  fi
  # The mesh's base (station/AGENTS.md, Its shape): its wire and door, and what they stand on, serve another program
  # without the station's business, so none of them imports a file outside their own set, a type's either
  # (scripts/mesh-base.ts lists the set and the leaves it may import).
  if touches '^station/src/|^scripts/mesh-base\.ts$'; then
    step "the mesh's base imports nothing of the station's business" node scripts/mesh-base.ts
  fi
  # Core tests also run for Rust-only client changes. A fresh CI checkout needs both
  # their JS dependencies and the real wasm package even when no TS file changed.
  core_tests=0
  if [ $full = 1 ] && touches '^(test|client|web/src/core)/|^package\.json$'; then core_tests=1; fi
  if touches "$ts_root" || touches "$ts_web" || touches "$web_reads" || touches "$ts_cloud" || [ $core_tests = 1 ]; then prep root deps .; fi
  if touches "$ts_root" || touches "$ts_web" || touches "$web_reads" || [ $core_tests = 1 ]; then wasm_pkg; fi
  # The stable channel's release notes (scripts/changelog.ts): each one read as CI will.
  if touches '^docs/releases/|^scripts/changelog\.ts$'; then step "release notes" sh -c 'node scripts/changelog.ts --stable > /dev/null'; fi
  # Root tests also import the core's Markdown reader. Wait for its packages on a cold checkout, as the web does.
  if touches "$ts_root" || [ $core_tests = 1 ]; then prep core deps client/core-ts; fi
  if touches "$ts_root"; then step "typecheck: scripts and tests" after root after core pnpm exec tsgo -p tsconfig.json; fi
  if touches "$ts_web" || touches "$web_reads"; then
    # The web reads the core's own files (its Markdown, client/core-ts/src/markdown.ts), which read the core's packages.
    prep core deps client/core-ts
    step "typecheck: web" after root after core pnpm exec tsgo -p web/tsconfig.json
    [ -f web/src/core/iroh-pkg/.stand-in ] && later "web against the real iroh wasm"
  fi
  if touches "$ts_cloud"; then
    prep cloud deps cloud
    prep cloud-types after_cloud_types
    step "typecheck: cloud" after cloud after cloud-types sh -c 'cd cloud && pnpm run check'
  fi
  # The TypeScript core: its own tsconfig.
  if touches "$ts_core"; then prep core deps client/core-ts; step "typecheck: core-ts" after core sh -c 'cd client/core-ts && pnpm exec tsgo --noEmit'; fi
  if touches "$ts_core|^client/math/|^apps/mbui/src/sf/math_glyphs\\.mbt$"; then prep core deps client/core-ts; step "shared math alphabet" after core node client/core-ts/scripts/math-font.ts --check; fi
  if touches "$ts_core|^client/fixtures/math\\.json$|^apps/mbui/src/sf/math\\.json$"; then prep core deps client/core-ts; step "shared math fixture" after core node client/core-ts/scripts/math-fixture.ts --check; fi
  # The core's pure answers the mbui app's runs without a core keep (apps/mbui/src/sfkept), as the core answers them now.
  if touches "$ts_core|^apps/mbui/src/sfkept/kept\\.mbt$"; then prep core deps client/core-ts; step "kept core answers" after core node client/core-ts/scripts/kept-answers.ts --check; fi
  # What makes the views writes only on what it made, never on what it was given (「谁能改什么」).
  if touches '^client/core-ts/(src|scripts)/'; then prep core deps client/core-ts; step "core writes on its own" after core node client/core-ts/scripts/writes.ts --check; fi
  # Nothing that answers the app reads a station's chats whole: the chat table is read by what a view shows.
  if touches '^client/core-ts/(src|scripts)/'; then step "core reads no chat list whole" after core node client/core-ts/scripts/whole-lists.ts --check; fi

fi

if [ $full = 1 ]; then
  # The tests drive the web core itself (test/core-client.test.ts): only with a real build of it.
  if part ts && [ $core_tests = 1 ]; then
    if [ -f web/src/core/iroh-pkg/.stand-in ] || [ ! -f web/src/core/iroh-pkg/built.js ]; then later "tests (need the iroh wasm)"; else step "tests" after root after core pnpm test; fi
  fi
  # The TypeScript core's own tests; its mesh tests on a simulated network, a few over the station's addon, prebuilt (its
  # package.json). Its side run's (real relays, networks made up at random) are scripts/side.sh's.
  # Run whenever one of what they read changed (the list `remembered` keys them by): a change to the words alone
  # (client/i18n) broke them on main unseen (2026-10-17, a28f78496).
  # (core-ts's tests import the station's (test/rigs.test.ts its rig's grants, which import effect): its deps too, or a
  # change that runs core-ts's tests alone fails rigs.test.ts at its import, #5386's check-linux 42962214582, 2026-11-11)
  # One slice of them, or all (STILLFAIL_CORE_SHARD="<i>/<n>": the files in order, every n-th from the i-th). CI runs
  # them in slices on Linux runners of their own (pipeline.yml, check-core), as the station's: in check-linux beside the
  # rest of ts they went from 3.5 to past its five minutes as files were added (179 files; main 6045382883 cancelled at
  # 5:05, 43272321433, 2026-11-12), each file small and none worth cutting (212 s of CPU in all on a Mac, the most 17).
  # (core_test_paths: scripts/plan.sh reads it from this line for CI's check-core)
  core_test_paths='^client/core-ts/|^client/i18n/|^web/src/core/|^web/public/avatars/|^station/native/mesh/|^vendor/|^rules/js/|^station/src/cloud/lock\.ts$|^station/test/lock-(chains|oracle)\.ts$|^scripts/native\.ts$'
  if part core-tests && touches "$core_test_paths"; then
    prep core deps client/core-ts; prep station deps station
    slice=${STILLFAIL_CORE_SHARD:-}
    # shellcheck disable=SC2016 # the command's own variables, expanded by its shell
    remembered "tests: core-ts${slice:+ $slice}" "client/core-ts client/i18n web/src/core web/public/avatars station/native/mesh vendor rules/js station/src/cloud/lock.ts station/test/lock-chains.ts station/test/lock-oracle.ts scripts/native.ts" after core after station env CORE_SLICE="$slice" sh -c 'cd client/core-ts && files=$(ls test/*.test.ts | awk -v s="${CORE_SLICE:-0/1}" '"'"'BEGIN { split(s, a, "/") } NR % a[2] == a[1]'"'"') && [ -n "$files" ] && node ../../scripts/native.ts run mesh -- node --test --test-force-exit $files'
  fi
  if part ts && touches "$ts_cloud"; then remembered "tests: cloud" "cloud client/i18n station/src/cloud/lock.ts client/core-ts/src/lock-form.ts rules/js" after cloud sh -c 'cd cloud && pnpm test'; fi
  # The station: it and its tests run whenever it, one of its native parts or the words it says changed (station_paths:
  # scripts/plan.sh reads it from this line for CI's check-station).
  station_paths='^station/|^vendor/|^client/i18n/|^client/shell/|^libs/mbui/src/effect/|^rules/js/|^scripts/native\.ts$|^scripts/station-slice\.sh$'
  # Its tests' native parts, prebuilt (mesh addon, runner, the reader in MoonBit; on a Mac the Rust station's archive
  # command too, for the compatibility tests, which skip themselves without it: it is prebuilt for darwin alone).
  station_natives="mesh runner reader"
  [ "$(uname -s)" = Darwin ] && station_natives="mesh runner archive-rs reader"
  if part station && touches "$station_paths"; then
    prep station deps station
    # Its programs in MoonBit (station/mb): what of them runs without a host (src/wire).
    remembered "tests: station's MoonBit" "station/mb libs/mbui/src/effect libs/mbui/moon.mod" sh -c 'cd station/mb && moon test --target native src/wire && moon test --target native src/jsjson && moon test --target native src/nodepath && moon test --target native src/jscase'
    step "typecheck: station" after station sh -c 'cd station && pnpm exec tsgo --noEmit'
    # The station's time is its Clock's (写法): the machine's only through ops/fibers.ts' wall. Cursor's
    # driver (agents/cursor-bridge.mjs) and the sandbox bridge (agents/sandbox-bridge.mjs) run in processes of their own,
    # not the station's.
    step "station: time through its clock" sh -c '! git grep -nE "Date\.now\(|new Date\(\)|setTimeout\(|setInterval\(" -- station/src ":!station/src/ops/fibers.ts" ":!station/src/agents/cursor-bridge.mjs" ":!station/src/agents/sandbox-bridge.mjs"'
    # Where the station's tests are another run's (CI: check-station's, on Linux), the ones only a Mac can run are
    # this one's: those of the Rust station's archive command (test/cold-compat.test.ts, 8 tests; every other test
    # ran on Linux as on a Mac, 2026-11-10).
    if ! part station-tests && [ "$(uname -s)" = Darwin ]; then
      remembered "tests: station, a Mac's alone" "station scripts/native.ts" after station sh -c 'cd station && node ../scripts/native.ts run mesh runner archive-rs reader -- node --import ./test/setup-env.mjs --test --test-timeout=600000 test/cold-compat.test.ts'
    fi
  fi
  # The station's tests (station/test): every file, or one slice of them (STILLFAIL_STATION_SHARD="<i>/<n>": the
  # longest files one to a slice first, then the rest in order, every n-th: scripts/station-slice.sh). CI runs them in slices on Linux runners of their own (pipeline.yml,
  # check-station), not on macos-ci: four runners share that Mac, the tests took 2.3 to 4.1 minutes there by what else
  # ran, and three checks at once went past the job's five (6 of some 18 in half a day, 2026-11-09; the files doubled
  # in the five days before). A machine to itself, a slice takes the same every run.
  if part station-tests && touches "$station_paths"; then
    prep station deps station
    slice=${STILLFAIL_STATION_SHARD:-}
    # (STILLFAIL_NODE_TEST_JOBS: that many files at a time rather than Node's own count)
    # shellcheck disable=SC2016 # the command's own variables, expanded by its shell
    remembered "tests: station${slice:+ $slice}" "station client/i18n client/shell vendor rules/js libs/mbui/src/effect scripts/native.ts scripts/station-slice.sh" after station env STATION_SLICE="$slice" STATION_NATIVES="$station_natives" sh -c 'cd station && files=$(sh ../scripts/station-slice.sh "${STATION_SLICE:-0/1}") && [ -n "$files" ] && node ../scripts/native.ts run $STATION_NATIVES -- node --import ./test/setup-env.mjs --test ${STILLFAIL_NODE_TEST_JOBS:+--test-concurrency="$STILLFAIL_NODE_TEST_JOBS"} --test-timeout=600000 $files'
  fi
  # The usage stream exercises the real station reader and the client together. Keep it out of either side's own
  # typecheck and prepare both sides before checking and running it, including on a fresh checkout.
  if part station && touches '^station/(src/|integration/|test/setup-env\.mjs$)|^client/core-ts/(src/|test/(helpers|station-fixture)\.ts$)|^scripts/check\.sh$'; then
    prep station deps station
    prep core deps client/core-ts
    step "tests: station and core usage stream" after station after core sh -c 'cd station && pnpm exec tsgo -p integration/tsconfig.json && node --disable-warning=ExperimentalWarning --import ./test/setup-env.mjs --test --test-timeout=30000 integration/usage-client-stream.test.ts'
  fi
  # The native parts' own tests, where their Rust changed (the mesh addon's: the vendored crates it patches in, too).
  for crate in launcher runner mesh screen; do
    also='^$'; [ $crate = mesh ] && also='^vendor/'
    if part station && { touches "^station/native/$crate/" || touches "$also"; }; then
      inputs="station/native/$crate"; [ $crate = mesh ] && inputs="$inputs vendor"; [ $crate = launcher ] && inputs="$inputs .node-version"
      if has cargo; then remembered "Rust: station/native/$crate" "$inputs" heavy cargo_test "station/native/$crate" --locked -q; else later "Rust: station/native/$crate"; fi
    fi
  done
  # still.fail Helper (Swift, station/native/helper and the PermissionFlow it uses): built where it changed, on a Mac.
  if part station && touches '^station/native/helper/|^vendor/PermissionFlow/' && has swift; then step "Swift: station/native/helper" node scripts/native.ts path helper; fi
  # The iOS app's crash reports as PostHog is sent them (apps/mbui/src/host/apple_reports.m), where they changed, on a Mac.
  if touches '^apps/mbui/(src/host/apple_reports\.m|scripts/ios-reports-test\.sh|scripts/ios_reports_test\.m)$' && has xcrun; then
    step "iOS crash reports" bash apps/mbui/scripts/ios-reports-test.sh
  fi
  # The core's native shells (client/shell for Android, client/iroh-wasm for the web).
  if part core && touches '^client/(shell|iroh-wasm)/|^client/Cargo\.(toml|lock)$|^vendor/'; then
    if has cargo; then remembered "Rust: client" "client vendor" heavy cargo_test client --workspace -q; else later "Rust: client"; fi
  fi
fi

report
if [ -n "$failed" ]; then
  echo "failed:$failed"
  [ $full = 0 ] && echo "(fix it; or, knowing why, skip once with git's --no-verify)"
  exit 1
fi

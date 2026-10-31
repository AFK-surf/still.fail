#!/bin/sh
# The checks for what changed. Two kinds:
#   quick: what a commit or push touches, in seconds (icons, TypeScript); the git hooks (.githooks) run it, on
#          whoever commits or pushes, so merging stays quick.
#   full:  that, the tests, cloud's tests, the core's tests, the web against the real iroh wasm, Rust:
#          minutes. Run before a deploy (~/bin/ember-deploy on studio runs it on what the deploy carries).
#
#   sh scripts/check.sh commit        quick, on what is staged (pre-commit)
#   sh scripts/check.sh push <range>  quick, on what a push carries (pre-push), e.g. origin/main..HEAD
#   sh scripts/check.sh full <range>  full, on what the range changed
#   sh scripts/check.sh all           full, as if every file changed
#
# STILLFAIL_CHECK_PART="<part> …" (ts, browser, station, core) runs only those parts of it: ts the icons, the clients'
# types and bindings, TypeScript, release notes and the tests run by node (web, scripts, cloud, the core: client/core-ts);
# browser the web in Chrome (its stories measured, the message list's motion watched; STILLFAIL_BROWSER="stories <i>/<n>"
# or "motion <i>/<n>" one share of it); station the station (station/, its typecheck and tests) and its native parts' own tests
# (station/native); core client/'s Rust (the core's native shells: iroh for the web and the apps' IO).
# Unset: all of them.
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
    commit) git diff --cached -U0 -- "$@" ;;
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
trap 'echo "stopped; still running:"; running tail; exit 1' INT TERM
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
  ts_cloud='^cloud/'
  ts_core='^client/core-ts/|^web/src/core/delta\.ts$'

  # The clients' types and the UIs' operation bindings are made from the core's (client/core-ts/src/shapes/schema.ts,
  # src/ops.ts): checked in, and never other than what those make.
  if touches '^client/core-ts/(src/shapes/|src/ops\.ts$|scripts/(shapes|operations)\.ts$)|^web/src/core/(shapes|operations)\.ts$'; then
    prep core deps client/core-ts
    step "clients' types" after core node client/core-ts/scripts/shapes.ts --check
    step "operation bindings" after core node client/core-ts/scripts/operations.ts --check
  fi

  if touches '^design/(station-)?icons/|^apps/mbui/(tools/icons/|scripts/icons$)|^web/ui/src/icons\.tsx$'; then
    step icons bash apps/mbui/scripts/icons . --check
  fi
  # Every CI job may take 5 minutes at most (only scripts/ci-timeouts.py's LONGER 10), and says so (timeout-minutes).
  if touches '^\.github/workflows/|^scripts/ci-timeouts\.py$'; then
    step "CI jobs: 5 minutes at most" python3 scripts/ci-timeouts.py
  fi
  # The UIs never make a request of a station or still.fail cloud themselves: they name what they want done
  # (client/core-ts/src/ops.ts), and the core, which knows what it changes, brings every topic that shows it up to date.
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
    # One light for the pointer in what a change adds (docs/ui-panels.md 悬停): a hover lays the ink, `vars.hover` (lit.ts
    # `litOver` over a ground of its own), or takes a solid ground a step towards the page (`vars.primaryHover`, a colour
    # 85% mixed with the canvas); never a colour, a tint or a filter of its own. One that must says why with "own hover:".
    added 'web/src/*.css.ts' 'web/ui/*.css.ts' | grep -E ':hover[^{]*\{[^}]*(background(Color)?|filter): *' \
      | grep -vE '(background(Color)?): *(vars\.hover|vars\.primaryHover|ink|"none"|"transparent")\b|85%, \$\{vars\.canvas\}|own hover:' > "$tmp/hovers" || true
    step "one light for the pointer (in what this adds)" sh -c "! grep . '$tmp/hovers'"
    # No margin taken back by hand: a ground reaching past its words, a corner, a column, a centring is one of
    # styles/align.ts's (bleedX, surface, columns, centred…), so its numbers are said once (a var's own negative may be).
    step "no hand-written negative margins" sh -c '! git grep -nE "margin[A-Za-z]*: *(-[0-9]|[\"\`][^\"\`]*[ (]-[0-9]|[\"\`]-[0-9])" -- "web/src/*.css.ts" "web/ui/*.css.ts" | grep -v "calc(-1 \* var("'
    # A small panel stands on controls.css.ts popover (docs/ui-panels.md): surface() only for it and the three that are not
    # popovers (a notice, ⌘K, the composer's list of chats).
    step "small panels on one ground" sh -c '! git grep -n "\.\.\.surface(" -- "web/src/*.css.ts" "web/ui/*.css.ts" ":!web/ui/src/styles/controls.css.ts" ":!web/src/SystemBubbles.css.ts" ":!web/src/Switcher.css.ts" ":!web/src/ChatRef.css.ts"'
  fi
  # Core tests also run for Rust-only client changes. A fresh CI checkout needs both
  # their JS dependencies and the real wasm package even when no TS file changed.
  core_tests=0
  if [ $full = 1 ] && touches '^(test|client|web/src/core)/|^package\.json$'; then core_tests=1; fi
  if touches "$ts_root" || touches "$ts_web" || touches "$web_reads" || touches "$ts_cloud" || [ $core_tests = 1 ]; then prep root deps .; fi
  if touches "$ts_root" || touches "$ts_web" || touches "$web_reads" || [ $core_tests = 1 ]; then wasm_pkg; fi
  # The stable channel's release notes (docs/changelog.md): each one read as CI will.
  if touches '^docs/releases/|^scripts/changelog\.ts$'; then step "release notes" sh -c 'node scripts/changelog.ts --stable > /dev/null'; fi
  # Root tests also import the core's Markdown reader. Wait for its packages on a cold checkout, as the web does.
  if touches "$ts_root" || [ $core_tests = 1 ]; then prep core deps client/core-ts; fi
  if touches "$ts_root"; then step "typecheck: scripts and tests" after root after core pnpm exec tsgo -p tsconfig.json; fi
  if touches "$ts_web" || touches "$web_reads"; then
    # The web reads the core's own files (its Markdown, client/core-ts/src/markdown.ts), which read the core's packages.
    prep core deps client/core-ts
    step "typecheck: web" after root after core pnpm exec tsgo -p web/tsconfig.json
    [ -f web/src/core/iroh-pkg/.stand-in ] && later "web against the real iroh wasm"
    # The web in Chrome (its stories, its message list's motion): the browser part, with the full check's steps below.
  fi
  if touches "$ts_cloud"; then
    prep cloud deps cloud
    prep cloud-types after_cloud_types
    step "typecheck: cloud" after cloud after cloud-types sh -c 'cd cloud && pnpm run check'
  fi
  # The TypeScript core (docs/core-ts.md): its own tsconfig.
  if touches "$ts_core"; then prep core deps client/core-ts; step "typecheck: core-ts" after core sh -c 'cd client/core-ts && pnpm exec tsgo --noEmit'; fi
  if touches "$ts_core|^client/math/|^apps/mbui/src/sf/math_glyphs\\.mbt$"; then prep core deps client/core-ts; step "shared math alphabet" after core node client/core-ts/scripts/math-font.ts --check; fi
  if touches "$ts_core|^client/fixtures/math\\.json$|^apps/mbui/src/sf/math\\.json$"; then prep core deps client/core-ts; step "shared math fixture" after core node client/core-ts/scripts/math-fixture.ts --check; fi
  # The core's pure answers the mbui app's runs without a core keep (apps/mbui/src/sfkept), as the core answers them now.
  if touches "$ts_core|^apps/mbui/src/sfkept/kept\\.mbt$"; then prep core deps client/core-ts; step "kept core answers" after core node client/core-ts/scripts/kept-answers.ts --check; fi
  # What makes the views writes only on what it made, never on what it was given (docs/core-ts.md「谁能改什么」).
  if touches '^client/core-ts/(src|scripts)/'; then prep core deps client/core-ts; step "core writes on its own" after core node client/core-ts/scripts/writes.ts --check; fi
  # The media app's service and its module of the core (media/, docs/media-service.md, docs/core-modules.md).
  if touches '^media/'; then
    prep root deps .
    prep core deps client/core-ts
    prep media-core deps media/core
    step "typecheck: media" after root after core after media-core sh -c 'pnpm exec tsgo -p media/service/tsconfig.json && cd media/core && ../../node_modules/.bin/tsgo -p tsconfig.json'
  fi

fi

if [ $full = 1 ]; then
  # Every story (web/stories) opened and every corner and small panel in it measured (test/browser/stories.mjs,
  # docs/ui-panels.md), then what moves in a chat's message list watched frame by frame (test/browser/list-settle.mjs,
  # docs/list-motion.md), a viewer's bar staying while pointed at (test/browser/viewer-bar.mjs, the motion's last share),
  # a folder dropped in the files' columns leaving nothing said over the list (test/browser/drive-drop.mjs, there too),
  # a wheel over a files column scrolling it alone, never the page under them (test/browser/drive-columns-wheel.mjs, there too),
  # a chat's side panel giving way to the chat once the window narrows (test/browser/side-panel-width.mjs, there too)
  # and a station's screen driven by a mouse, keys and fingers (test/browser/screen-input.mjs, there too):
  # on a Chrome the machine has (CI's Linux runners have one). On CI shared out between jobs side by
  # side (STILLFAIL_BROWSER): on one of GitHub's four cores it all took ~3 minutes (2026-10-15).
  if part browser && { touches '^web/' || touches '^test/browser/(stories|measure|list-settle|viewer-bar|drive-drop|drive-columns-wheel|side-panel-width|chat-pagination|screen-input|share-markdown)\.mjs$'; }; then
    if command -v google-chrome >/dev/null 2>&1; then
      prep root deps .
      wasm_pkg
      prep core deps client/core-ts
      chrome='export PLAYWRIGHT_MODULE=playwright-core PLAYWRIGHT_CHANNEL=chrome'
      # Its share: "<part> <i>/<n>" (none said: all of it).
      share=${STILLFAIL_BROWSER#* }; [ "$share" = "${STILLFAIL_BROWSER:-}" ] && share=1/1
      case "${STILLFAIL_BROWSER:-}" in
        stories*) step "web: stories measured (${STILLFAIL_BROWSER#stories })" after root after core sh -c "$chrome SHARD='${STILLFAIL_BROWSER#stories }'; node test/browser/stories.mjs" ;;
        motion*) step "web: the message list's motion watched ($share), a viewer's bar kept" after root after core sh -c "$chrome SHARD='$share'; node test/browser/list-settle.mjs && { [ '${share%/*}' != '${share#*/}' ] || { node test/browser/viewer-bar.mjs && node test/browser/drive-drop.mjs && node test/browser/drive-columns-wheel.mjs && node test/browser/side-panel-width.mjs && node test/browser/chat-pagination.mjs && node test/browser/screen-input.mjs; }; }" ;;
        *) step "web: stories measured, the message list's motion watched, a viewer's bar kept" after root after core sh -c "$chrome; node test/browser/stories.mjs && node test/browser/list-settle.mjs && node test/browser/viewer-bar.mjs && node test/browser/drive-drop.mjs && node test/browser/drive-columns-wheel.mjs && node test/browser/side-panel-width.mjs && node test/browser/chat-pagination.mjs && node test/browser/screen-input.mjs" ;;
      esac
      case "${STILLFAIL_BROWSER:-}" in
        ""|motion*)
          if [ "${share%/*}" = "${share#*/}" ]; then
            step "web: share Markdown and file previews" after root after core sh -c "$chrome; node test/browser/share-markdown.mjs"
          fi ;;
      esac
    else
      later "web: stories measured, the message list's motion watched (no Chrome here)"
    fi
  fi
  # The tests drive the web core itself (test/core-client.test.ts): only with a real build of it.
  if part ts && [ $core_tests = 1 ]; then
    if [ -f web/src/core/iroh-pkg/.stand-in ] || [ ! -f web/src/core/iroh-pkg/built.js ]; then later "tests (need the iroh wasm)"; else step "tests" after root after core pnpm test; fi
  fi
  # The TypeScript core's own tests; its mesh tests on a simulated network, a few over the station's addon, prebuilt (its
  # package.json). Its side run's (real relays, networks made up at random) are scripts/side.sh's.
  # Run whenever one of what they read changed (the list `remembered` keys them by): a change to the words alone
  # (client/i18n) broke them on main unseen (2026-10-17, a28f78496).
  if part ts && touches "$ts_core|^client/i18n/|^web/src/core/|^web/public/avatars/|^station/native/mesh/|^vendor/|^scripts/native\.ts$"; then prep core deps client/core-ts; remembered "tests: core-ts" "client/core-ts client/i18n web/src/core web/public/avatars station/native/mesh vendor scripts/native.ts" after core sh -c 'cd client/core-ts && pnpm test'; fi
  if part ts && touches "$ts_cloud"; then remembered "tests: cloud" "cloud client/i18n" after cloud sh -c 'cd cloud && pnpm test'; fi
  # The station, with its native parts prebuilt (mesh addon, runner, the Rust station's archive for the compatibility
  # tests): its tests run whenever it, one of them or the words it says changed.
  if part station && touches '^station/|^vendor/|^client/i18n/|^scripts/native\.ts$'; then
    prep station deps station
    step "typecheck: station" after station sh -c 'cd station && pnpm exec tsgo --noEmit'
    # The station's time is its Clock's (docs/station-ts.md, 写法): the machine's only through ops/fibers.ts' wall. Cursor's
    # driver (agents/cursor-bridge.mjs) and the sandbox bridge (agents/sandbox-bridge.mjs) run in processes of their own,
    # not the station's.
    step "station: time through its clock" sh -c '! git grep -nE "Date\.now\(|new Date\(\)|setTimeout\(|setInterval\(" -- station/src ":!station/src/ops/fibers.ts" ":!station/src/agents/cursor-bridge.mjs" ":!station/src/agents/sandbox-bridge.mjs"'
    remembered "tests: station" "station client/i18n vendor scripts/native.ts" after station sh -c 'cd station && pnpm test'
  fi
  # The media app's (media/): its service's tests, its core module's, and the two end to end beside the station's module
  # layer (media/test): whenever it, the core or the station changed.
  if part station && touches '^media/|^client/core-ts/src/|^station/src/|^scripts/native\.ts$'; then
    prep station deps station
    prep core deps client/core-ts
    prep media-core deps media/core
    prep media-test deps media/test
    remembered "tests: media" "media client/core-ts station/src scripts/native.ts" after station after core after media-core after media-test sh -c 'cd media/service && node --test --test-timeout=120000 test/*.test.ts && cd ../core && pnpm test && cd ../test && pnpm test'
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

#!/bin/bash
# The still.fail client core (client/core-ts of github.com/zzj3720/ember) in JavaScriptCore, on its Rust shell
# (client/shell): builds the pieces from an ember checkout and runs a headless smoke test. See core/README.md.
#   scripts/core.sh deps | shell [TARGET] | bundle | smoke [build|run] | vectors | sizes | clean | all
# EMBER: the ember checkout (default: ember-src beside this session's tools); out/core/ gets everything built.
# TARGET: a Rust target (default aarch64-apple-darwin; aarch64-apple-ios, aarch64-apple-ios-sim for iOS).
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
ROOT=$PWD
EMBER=${EMBER:-$(cd "$TOOLS/.." && pwd)/ember-src}
OUT=$ROOT/out/core
CORE_TS=$EMBER/client/core-ts
# The shell's intermediate build lives outside the checkout (and outside this repo): only the .a is kept in out/core.
CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$(cd "$TOOLS/.." && pwd)/core-target}
export CARGO_TARGET_DIR
# rustup's cargo (it has the iOS/Android targets), before Homebrew's.
[ -x "$HOME/.cargo/bin/cargo" ] && export PATH=$HOME/.cargo/bin:$PATH
mkdir -p $OUT

now() { python3 -c 'import time;print(time.time())'; }
since() { python3 -c "print(round($(now)-$1,2))"; }

deps() {
  [ -d "$CORE_TS" ] || { echo "no ember checkout at $EMBER (EMBER=...)"; exit 1; }
  (cd $CORE_TS && pnpm install --frozen-lockfile --prefer-offline 2>&1 | tail -5)
}

# libstillfail_shell.a for TARGET: the crate is a cdylib + lib; `cargo rustc --crate-type staticlib` makes the
# archive without touching ember's Cargo.toml. What it needs from the system goes to out/core/shell-<target>.libs.
shell() {
  local target=${1:-aarch64-apple-darwin}
  local t0=$(now)
  (cd $EMBER/client/shell && cargo rustc --release --lib --crate-type staticlib --target $target \
      -- --print native-static-libs 2> >(tee $OUT/shell-$target.log >&2))
  # (rustc prints it only when it builds: a fresh build keeps the last one)
  local libs=$(grep -o 'native-static-libs: .*' $OUT/shell-$target.log | tail -1 | sed 's/native-static-libs: //')
  [ -n "$libs" ] && echo "$libs" > $OUT/shell-$target.libs
  mkdir -p $OUT/$target
  cp $CARGO_TARGET_DIR/$target/release/libstillfail_shell.a $OUT/$target/
  strip -S -x -o $OUT/$target/libstillfail_shell.stripped.a $OUT/$target/libstillfail_shell.a 2>/dev/null || true
  echo "shell $target in $(since $t0) s: $(stat -f %z $OUT/$target/libstillfail_shell.a) bytes; links: $(libs $target)"
}

# The core as one script for JavaScriptCore: core/jsc.ts (core/jsc-start.ts: hermes-globals' polyfills, then ember's
# hosts/engine.ts; ENTRY: an app's own entry, with its modules), esbuild IIFE, ES2020. `@core/` is client/core-ts/src.
# Not ember's scripts/hermes-bundle.ts: its Babel pass (classes as functions) is Hermes's need, and it resolves imports
# only from inside ember; JavaScriptCore runs classes as they are.
bundle() {
  local t0=$(now)
  $CORE_TS/node_modules/.bin/esbuild ${ENTRY:-$ROOT/core/jsc.ts} --bundle --format=iife --platform=neutral \
    --main-fields=module,main --target=es2020 --minify --legal-comments=none \
    --alias:@core=$CORE_TS/src --alias:@ember=$EMBER --resolve-extensions=.ts,.js,.mjs \
    --outfile=$OUT/core.js --metafile=$OUT/core.meta.json --log-level=warning
  echo "bundle in $(since $t0) s: $(stat -f %z $OUT/core.js) bytes ($(gzip -9c $OUT/core.js | wc -c | tr -d ' ') gzipped)"
}

# The shell's link line for TARGET, each library once (-framework X, -lY; clang adds -lSystem and -lobjc itself).
libs() {
  python3 -c '
import sys
t = open(sys.argv[1]).read().split(); out = []; i = 0
while i < len(t):
    x = t[i:i + 2] if t[i] == "-framework" else t[i:i + 1]; i += len(x)
    if " ".join(x) not in out and x[0] not in ("-lSystem", "-lobjc"): out.append(" ".join(x))
print(" ".join(out))' $OUT/shell-$1.libs
}

# core/smoke.m + src/host/apple_core.m + the shell, for macOS.
smoke_build() {
  local target=aarch64-apple-darwin
  [ -f $OUT/$target/libstillfail_shell.a ] || shell $target
  clang -fobjc-arc -O2 -Wall -Isrc/host core/smoke.m src/host/apple_core.m \
    $OUT/$target/libstillfail_shell.a $(libs $target) \
    -framework Foundation -framework JavaScriptCore -Wl,-dead_strip -o $OUT/smoke
  strip -o $OUT/smoke.stripped $OUT/smoke
  echo "smoke: $(stat -f %z $OUT/smoke) bytes, stripped $(stat -f %z $OUT/smoke.stripped)"
}

# Twice on one data directory: a first start (no files yet), then one over what the first left.
# /usr/bin/time -l: the process's peak resident size and footprint. MB_CORE_TRACE=1 shows the shell's operations.
smoke_run() {
  local dir=$(mktemp -d /tmp/mbui-core-smoke.XXXXXX) code=0
  : > $OUT/smoke.log
  for run in first again; do
    echo "== $run run ==" | tee -a $OUT/smoke.log
    MB_CORE_BUNDLE=$OUT/core.js /usr/bin/time -l $OUT/smoke "$dir" ${CLOUD:-https://app.still.fail} > $OUT/smoke-$run.log 2>&1 || code=1
    cat $OUT/smoke-$run.log >> $OUT/smoke.log
    grep -v '^ *0  \|messages\|signals\|swaps\|block\|context switches\|page' $OUT/smoke-$run.log
    echo "data dir after it: $(cd "$dir" && find . -type f | sort | tr '\n' ' ')" | tee -a $OUT/smoke.log
  done
  rm -rf "$dir"
  return $code
}

# src/core/vectors_test.mbt: core-ts's diff and apply over values shaped like the topics (core/delta-vectors.ts).
vectors() {
  EMBER=$EMBER node core/delta-vectors.ts > src/core/vectors_test.mbt
  echo "vectors: $(grep -c '^test ' src/core/vectors_test.mbt) tests in src/core/vectors_test.mbt"
}

sizes() {
  ls -la $OUT/core.js $OUT/*/libstillfail_shell*.a $OUT/smoke $OUT/smoke.stripped 2>/dev/null
}

case "${1:-all}" in
  deps) deps ;;
  shell) shell "$2" ;;
  bundle) bundle ;;
  smoke)
    case "${2:-all}" in
      build) smoke_build ;;
      run) smoke_run ;;
      *) bundle; smoke_build; smoke_run ;;
    esac ;;
  vectors) vectors ;;
  sizes) sizes ;;
  clean) rm -rf "$CARGO_TARGET_DIR"; echo "removed $CARGO_TARGET_DIR (out/core kept)" ;;
  all) deps; shell; bundle; smoke_build; smoke_run; sizes ;;
  *) echo "usage: scripts/core.sh deps | shell [TARGET] | bundle | smoke [build|run] | vectors | sizes | clean | all"; exit 2 ;;
esac

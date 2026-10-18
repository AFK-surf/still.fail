#!/bin/bash
# The still.fail client core (client/core-ts of github.com/zzj3720/ember) in JavaScriptCore, on its Rust shell
# (client/shell): builds the pieces from an ember checkout and runs a headless smoke test. See core/README.md.
#   scripts/core.sh deps | shell [TARGET] | bundle | smoke [build|run] | listen | login-test | vectors | sizes | clean | all
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
  clang -fobjc-arc -O2 -Wall -Isrc/host core/smoke.m src/host/apple_core.m src/host/apple_listen.m \
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

# listen.* (apple_core.m on apple_listen.m) with core/listen-test.js in the core's place: core/listen_test.m.
listen_test() {
  local target=aarch64-apple-darwin
  [ -f $OUT/$target/libstillfail_shell.a ] || shell $target
  clang -fobjc-arc -O2 -Wall -Isrc/host core/listen_test.m src/host/apple_core.m src/host/apple_listen.m \
    $OUT/$target/libstillfail_shell.a $(libs $target) \
    -framework Foundation -framework JavaScriptCore -Wl,-dead_strip -o $OUT/listen_test
  local dir=$(mktemp -d /tmp/mbui-core-listen.XXXXXX) code=0
  MB_CORE_BUNDLE=$ROOT/core/listen-test.js $OUT/listen_test "$dir" || code=1
  rm -rf "$dir"
  return $code
}

# The core demo's login command (scripts/mac.sh login, MBUI_AUTH_LOGIN) as a station's remote login would run it, up
# to the person's browser step, against still.fail cloud: a fresh data directory, BROWSER a stand-in that keeps the
# page's address. Nobody signs in: the browser that comes back is curl, with a state that is not the sign-in's.
login_test() {
  MBUI_CORE=1 "$D/mac.sh" build > /dev/null
  local exe=$ROOT/_build/native/release/build/coredemo/coredemo.exe
  local dir=$(mktemp -d /tmp/mbui-login.XXXXXX) code=0
  printf '#!/bin/sh\necho "$1" > "%s/url"\n' "$dir" > $dir/browser
  chmod +x $dir/browser
  MB_CORE_BUNDLE=$OUT/core.js MBUI_CORE_DATA=$dir/data BROWSER=$dir/browser MBUI_AUTH_LOGIN=1 $exe > $dir/out.log 2>&1 &
  local pid=$!
  # Not waited for forever: a minute is ample for what follows.
  (sleep 60; kill $pid 2> /dev/null) &
  local watchdog=$!
  for _ in $(seq 60); do [ -s $dir/url ] && break; sleep 0.5; done
  local url=$(cat $dir/url 2>/dev/null)
  ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; code=1; fi; }
  ok "the page went to BROWSER" '[ -n "$url" ]'
  local port=$(python3 -c '
import sys, urllib.parse as u
p = u.urlparse(sys.argv[1]); q = u.parse_qs(p.query); back = u.urlparse(q.get("redirect_uri", [""])[0])
ok = p.scheme == "https" and p.path == "/v1/auth/google/start" and "state" in q and back.scheme == "http" and back.hostname == "127.0.0.1" and back.path == "/oauth/callback"
print(back.port if ok else 0)' "$url")
  ok "it is still.fail cloud's login page, coming back to 127.0.0.1:$port/oauth/callback" '[ "$port" -gt 0 ]'
  if [ -f "$EMBER/station/src/logins/parse.ts" ]; then
    local seen=$(node --experimental-strip-types --no-warnings --input-type=module -e "
const { loopbackOf } = await import('$EMBER/station/src/logins/parse.ts');
const b = loopbackOf(process.argv[1]);
console.log(b && b.state ? b.host + ':' + b.port + b.path : 'none');" "$url" 2>&1)
    ok "a station's login takes it as a loopback login with a state ($seen)" '[ "$seen" = "127.0.0.1:$port/oauth/callback" ]'
  fi
  ok "the app itself listens there (lsof, as the station checks before relaying)" 'lsof -a -p $pid -iTCP:$port -sTCP:LISTEN -n -P | grep -q "127.0.0.1:$port"'
  ok "another path is not taken" '[ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$port/favicon.ico)" = 404 ]'
  ok "nor the callback under another host name" '[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Host: elsewhere.example:$port" "http://127.0.0.1:$port/oauth/callback?code=x&state=y")" = 404 ]'
  ok "the app still waits" 'kill -0 $pid 2>/dev/null'
  local page=$(curl -s "http://127.0.0.1:$port/oauth/callback?code=x&state=not-this-one")
  ok "the browser coming back gets the app's page" 'echo "$page" | grep -q "登录没有完成"'
  local exit_code=0
  wait $pid || exit_code=$?
  kill $watchdog 2> /dev/null || true
  wait $watchdog 2> /dev/null || true
  ok "the app exits 1 (the state was not the sign-in's: $(grep -a 'Sign-in failed' $dir/out.log | head -1))" '[ $exit_code = 1 ] && grep -q "Sign-in failed" $dir/out.log'
  ok "it no longer listens" '! lsof -iTCP:$port -sTCP:LISTEN -n -P > /dev/null'
  [ $code = 0 ] || cat $dir/out.log
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
  listen) listen_test ;;
  login-test) login_test ;;
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
  *) echo "usage: scripts/core.sh deps | shell [TARGET] | bundle | smoke [build|run] | listen | login-test | vectors | sizes | clean | all"; exit 2 ;;
esac

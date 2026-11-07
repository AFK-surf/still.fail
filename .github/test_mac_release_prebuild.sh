#!/bin/bash
# Exercise the background build's ordering and failures without building an app or touching the real cache.
set -eu
script=$(cd "$(dirname "$0")" && pwd)/mac-release-prebuild.sh
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
case_dir() {
  export GITHUB_WORKSPACE="$root/$1/work" RUNNER_TEMP="$root/$1/temp" RUNNER_TOOL_CACHE="$root/$1/tools"
  mkdir -p "$GITHUB_WORKSPACE/apps/mbui/scripts" "$GITHUB_WORKSPACE/apps/mbui/mbui/scripts" \
    "$GITHUB_WORKSPACE/apps/mbui/_build" "$RUNNER_TEMP" "$RUNNER_TOOL_CACHE"
  cat > "$GITHUB_WORKSPACE/apps/mbui/scripts/env.sh" <<'EOF'
A="$GITHUB_WORKSPACE/apps/mbui"
MBUI_DIR="$A/mbui"
export A MBUI_DIR
EOF
  cat > "$GITHUB_WORKSPACE/apps/mbui/scripts/core.sh" <<'EOF'
#!/bin/bash
set -eu
[ "$*" = 'apple-native aarch64-apple-darwin' ]
[ "$MACOSX_DEPLOYMENT_TARGET" = 12.0 ]
[ "$CARGO_TARGET_DIR" = "$GITHUB_WORKSPACE/apps/mbui/out/core-target-macos12.0" ]
[ "${FAIL_CORE:-0}" = 0 ] || exit 7
touch "$RUNNER_TEMP/core-finished"
EOF
  cat > "$GITHUB_WORKSPACE/apps/mbui/mbui/scripts/mac.sh" <<'EOF'
#!/bin/bash
set -eu
[ "$*" = build ]
[ "$APP" = stillfail ] && [ "$MODE" = release ]
[ "$MOON_HOME" = "$RUNNER_TOOL_CACHE/moon-ci" ]
touch "$RUNNER_TEMP/app-built"
[ "${FAIL_APP:-0}" = 0 ] || exit 8
EOF
}
case_dir exit_race
mkdir -p "$RUNNER_TEMP/mac-prebuild"
printf '99999999\n' > "$RUNNER_TEMP/mac-prebuild/pid"
: > "$RUNNER_TEMP/mac-prebuild/log"
# The worker can write its result and exit after wait checks the file but before it probes the PID.
kill() {
  [ "$1" = -0 ] && [ "$2" = 99999999 ] || return 2
  printf '0\n' > "$RUNNER_TEMP/mac-prebuild/status"
  return 1
}
export -f kill
bash "$script" wait
unset -f kill

case_dir dead_worker
mkdir -p "$RUNNER_TEMP/mac-prebuild"
printf '99999999\n' > "$RUNNER_TEMP/mac-prebuild/pid"
: > "$RUNNER_TEMP/mac-prebuild/log"
if bash "$script" wait; then echo 'a worker that exited without a result was not reported' >&2; exit 1; fi

case_dir order
echo 12.0 > "$GITHUB_WORKSPACE/apps/mbui/_build/.macos-min"
bash "$script" start
for i in 1 2 3 4 5; do [ ! -f "$RUNNER_TEMP/core-finished" ] || break; sleep 1; done
[ -f "$RUNNER_TEMP/core-finished" ] && [ ! -e "$RUNNER_TEMP/app-built" ]
bash "$script" ready
bash "$script" wait
[ -f "$RUNNER_TEMP/app-built" ]

case_dir uncached
bash "$script" start
bash "$script" ready
bash "$script" wait
[ -e "$RUNNER_TEMP/app-built" ]
[ "$(cat "$GITHUB_WORKSPACE/apps/mbui/_build/.macos-min")" = 12.0 ]

case_dir core_failure
export FAIL_CORE=1
bash "$script" start
if bash "$script" wait; then echo 'native failure was not reported' >&2; exit 1; fi
unset FAIL_CORE

case_dir app_failure
echo 12.0 > "$GITHUB_WORKSPACE/apps/mbui/_build/.macos-min"
export FAIL_APP=1
bash "$script" start
bash "$script" ready
if bash "$script" wait; then echo 'app failure was not reported' >&2; exit 1; fi
unset FAIL_APP
case_dir handoff
exe="$GITHUB_WORKSPACE/apps/mbui/_build/native/release/build/stillfail/stillfail"
core="$GITHUB_WORKSPACE/apps/mbui/out/core"
framework="$core/hermes/Library/Frameworks/macosx/hermes.framework"
mkdir -p "$exe" "$framework/Versions/A" "$RUNNER_TEMP/mac-prebuild"
printf '#!/bin/sh\nexit 0\n' > "$exe/stillfail.exe"
chmod +x "$exe/stillfail.exe"
printf 'bytecode' > "$core/core.hbc"
printf 'runtime' > "$framework/Versions/A/hermes"
ln -s A "$framework/Versions/Current"
ln -s Versions/Current/hermes "$framework/hermes"
: > "$RUNNER_TEMP/mac-prebuild/log"
GIT_DIR=$(git -C "$(dirname "$script")" rev-parse --absolute-git-dir) bash "$script" pack "$RUNNER_TEMP/compiled.tar"
mkdir "$RUNNER_TEMP/unpacked"
tar -xf "$RUNNER_TEMP/compiled.tar" -C "$RUNNER_TEMP/unpacked"
test -x "$RUNNER_TEMP/unpacked/stillfail.exe"
cmp "$core/core.hbc" "$RUNNER_TEMP/unpacked/core.hbc"
test -L "$RUNNER_TEMP/unpacked/hermes.framework/Versions/Current"
test "$(cat "$RUNNER_TEMP/unpacked/hermes.framework/hermes")" = runtime
test "$(cat "$RUNNER_TEMP/unpacked/revision")" = "$(git -C "$(dirname "$script")" rev-parse HEAD)"
printf 'built for newer macOS version' > "$RUNNER_TEMP/mac-prebuild/log"
if bash "$script" pack "$RUNNER_TEMP/wrong.tar"; then echo 'incompatible deployment target was handed over' >&2; exit 1; fi
echo 'Mac prebuild ordering, failure handling and artifact handoff passed'

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
[ ! -e "$RUNNER_TEMP/app-built" ]

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
echo 'Mac prebuild ordering and failure handling passed'

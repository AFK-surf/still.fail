#!/bin/bash
# The desktop job's native parts and Moon build, started while it restores the tools and packages they do not need.
# `ready` means the Moon toolchain and _build cache have been restored and source mtimes set. `wait` reports failures
# before `pack` hands this commit's program and runtime to the separate bundling/signing job.
set -eu
dir="$RUNNER_TEMP/mac-prebuild"
case "${1:-}" in
  start)
    mkdir -p "$dir"
    nohup bash "$0" work > "$dir/log" 2>&1 < /dev/null &
    echo "$!" > "$dir/pid"
    ;;
  ready)
    touch "$dir/ready"
    ;;
  wait)
    while [ ! -s "$dir/status" ]; do
      if ! kill -0 "$(cat "$dir/pid")" 2>/dev/null; then
        # The worker may have written its result after the loop's check and then exited.
        [ ! -s "$dir/status" ] || break
        cat "$dir/log"
        echo 'Mac prebuild exited without reporting its result' >&2
        exit 1
      fi
      sleep 1
    done
    cat "$dir/log"
    [ "$(cat "$dir/status")" = 0 ] || exit 1
    ;;
  work)
    set +e
    bash "$0" build
    result=$?
    printf '%s\n' "$result" > "$dir/status.tmp"
    mv "$dir/status.tmp" "$dir/status"
    exit "$result"
    ;;
  build)
    cd "$GITHUB_WORKSPACE"
    . apps/mbui/scripts/env.sh
    export MACOSX_DEPLOYMENT_TARGET=12.0
    export CARGO_TARGET_DIR="$A/out/core-target-macos$MACOSX_DEPLOYMENT_TARGET"
    bash "$A/scripts/core.sh" apple-native aarch64-apple-darwin
    while [ ! -f "$dir/ready" ]; do sleep 1; done
    # Initialize cold or incompatible Moon outputs here too: the next job only bundles the compiled program.
    if [ "$(cat "$A/_build/.macos-min" 2>/dev/null || :)" != "$MACOSX_DEPLOYMENT_TARGET" ]; then
      rm -rf "$A/_build" "$A/out/mbc"
      mkdir -p "$A/_build"
      echo "$MACOSX_DEPLOYMENT_TARGET" > "$A/_build/.macos-min"
    fi
    exe="$A/_build/native/release/build/stillfail/stillfail/stillfail.exe"
    [ ! -f "$exe" ] || [ ! "$A/out/core/aarch64-apple-darwin/libmbui_core.a" -nt "$exe" ] || touch "$A/src/stillfail/core_engine.m"
    export MOON_HOME="$RUNNER_TOOL_CACHE/moon-ci"
    export PATH="$MOON_HOME/bin:$PATH" APP=stillfail MODE=release
    bash "$MBUI_DIR/scripts/mac.sh" build
    ;;
  pack)
    cd "$GITHUB_WORKSPACE"
    stage="$RUNNER_TEMP/mac-compiled"
    mkdir -p "$stage"
    if grep -q 'built for newer macOS version' "$dir/log"; then cat "$dir/log"; exit 1; fi
    cp -p apps/mbui/_build/native/release/build/stillfail/stillfail/stillfail.exe "$stage/stillfail.exe"
    cp apps/mbui/out/core/core.hbc "$stage/core.hbc"
    ditto apps/mbui/out/core/hermes/Library/Frameworks/macosx/hermes.framework "$stage/hermes.framework"
    git rev-parse HEAD > "$stage/revision"
    tar -cf "$2" -C "$stage" .
    ;;
  *) echo "usage: $0 start|ready|wait|pack ARCHIVE" >&2; exit 2 ;;
esac

#!/bin/bash
# The desktop job's native parts, Moon build and core bytecode, started while it restores what they do not need.
# `ready` means the Moon toolchain and _build cache have been restored and source mtimes set; `packages` that the job's
# pnpm install is over, the core's bytecode's own install waiting for it (one store, two installs at once lost files:
# its pending file, made at the start, taken away). `wait` reports failures
# before the usual release script signs or publishes anything; that script still does its own up-to-date build.
set -eu
dir="$RUNNER_TEMP/mac-prebuild"
case "${1:-}" in
  start)
    mkdir -p "$dir"
    # the PostHog project the core sends what people use to (scripts/core.sh posthog_define): the file the bundling
    # step writes too, the same, so that core.hbc made here is the one it takes
    if [ -n "${POSTHOG_JSON:-}" ]; then
      (umask 077 && printf '%s' "$POSTHOG_JSON" > "$RUNNER_TEMP/posthog.json")
      export STILLFAIL_POSTHOG="$RUNNER_TEMP/posthog.json"
    fi
    unset POSTHOG_JSON
    : > "$dir/packages-pending"
    nohup bash "$0" work > "$dir/log" 2>&1 < /dev/null &
    echo "$!" > "$dir/pid"
    ;;
  ready)
    touch "$dir/ready"
    ;;
  packages)
    rm -f "$dir/packages-pending"
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
    # mac-app.sh clears outputs when this marker differs. Let it do so and build normally in that case.
    if [ "$(cat "$A/_build/.macos-min" 2>/dev/null || :)" != "$MACOSX_DEPLOYMENT_TARGET" ]; then
      echo 'Mac prebuild: no matching Moon build; the release builds it normally'
      exit 0
    fi
    exe="$A/_build/native/release/build/stillfail/stillfail/stillfail.exe"
    [ ! -f "$exe" ] || [ ! "$A/out/core/aarch64-apple-darwin/libmbui_core.a" -nt "$exe" ] || touch "$A/src/stillfail/core_engine.m"
    export MOON_HOME="$RUNNER_TOOL_CACHE/moon-ci"
    export PATH="$MOON_HOME/bin:$PATH" APP=stillfail MODE=release MBUI_PACKAGES_PENDING="$dir/packages-pending"
    # The app's wrapper builds core.hbc beside the app. Leaving it until mac-app.sh bundled the app added 26 s after
    # the compile and let a successful build time out during cleanup (42588746155, 2026-11-09).
    bash "$A/scripts/mac.sh" build
    ;;
  *) echo "usage: $0 start|ready|packages|wait" >&2; exit 2 ;;
esac

#!/bin/bash
# The Android app: mbui's scripts/android.sh (its commands: build | emu | run [script] | shot NAME | record NAME SECONDS
# [drive] | log | stop | delete) on this module's apps, packed by this module's Gradle project (android/: the still.fail
# mbui app, fail.still.mbui; the debug build fail.still.mbui.debug), with the still.fail core in coredemo and stillfail
# (scripts/android-core.sh; listen-test, its own command). APP=stillfail by default; VARIANT=release the beta app;
# VARIANT=stable and beta still.fail's Android app's own (fail.still.android, fail.still.android.beta: android/apk.json).
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
export APP=${APP:-stillfail}
export MBUI_ANDROID=$A/android
case "${VARIANT:-debug}" in
  release) export MBUI_APP_ID=${MBUI_APP_ID:-fail.still.mbui} ;;
  stable) export MBUI_APP_ID=${MBUI_APP_ID:-fail.still.android} ;;
  beta) export MBUI_APP_ID=${MBUI_APP_ID:-fail.still.android.beta} ;;
  *) export MBUI_APP_ID=${MBUI_APP_ID:-fail.still.mbui.debug} ;;
esac
case $APP in coredemo | stillfail) export MBUI_ANDROID_HOOK=$D/android-core.sh ;; esac
exec bash "$MBUI_DIR/scripts/android.sh" "$@"

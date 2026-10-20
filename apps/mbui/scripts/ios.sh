#!/bin/bash
# The iOS simulator app: mbui's scripts/ios.sh (build | run [script] | log [N] | stop | shot NAME | delete) on this
# module's apps (APP=stillfail by default; coredemo, sffix, sfkit…), packed as still.fail mbui's (ios/Info.plist; the
# debug build's id fail.still.mbui.debug, MBUI_IOS_ID), on a simulator of its own (MBUI_IOS_DEVICE, default
# ios-mbui-sf: made when missing, never another's). stillfail and coredemo carry the still.fail core in Hermes
# (scripts/ios-core.sh). ENV="K=V;K2=V2" gives `run` the app's environment; its log is out/ios/app.log.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
export APP=${APP:-stillfail}
export MBUI_IOS_PLIST=$A/ios/Info.plist
export MBUI_IOS_ID=${MBUI_IOS_ID:-fail.still.mbui.debug}
export MBUI_IOS_DEVICE=${MBUI_IOS_DEVICE:-ios-mbui-sf}
case $APP in coredemo | stillfail) export MBUI_IOS_HOOK=$D/ios-core.sh ;; esac
exec bash "$MBUI_DIR/scripts/ios.sh" "$@"

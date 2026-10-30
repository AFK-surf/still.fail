#!/bin/bash
# The iOS simulator app: mbui's scripts/ios.sh (build | run [script] | log [N] | stop | shot NAME | delete) on this
# module's apps (APP=stillfail by default; coredemo, sffix, sfkit…), packed as still.fail mbui's (ios/Info.plist; the
# debug build's id fail.still.mbui.debug, MBUI_IOS_ID), on a simulator of its own (MBUI_IOS_DEVICE, default
# ios-mbui-sf: made when missing, never another's). stillfail and coredemo carry the still.fail core in Hermes
# (scripts/ios-core.sh). ENV="K=V;K2=V2" gives `run` the app's environment; its log is out/ios/app.log.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# Match mbui's explicit iOS 17.0 link target for Rust and cc-rs native dependencies too.
# Otherwise the installed SDK's default can produce dependencies requiring a newer iOS.
export IPHONEOS_DEPLOYMENT_TARGET=17.0
export APP=${APP:-stillfail}
export MBUI_IOS_PLIST=$A/ios/Info.plist
export MBUI_IOS_ID=${MBUI_IOS_ID:-fail.still.mbui.debug}
export MBUI_IOS_DEVICE=${MBUI_IOS_DEVICE:-ios-mbui-sf}
# its share extension (mbui's src/host/ios_share.m): what another app shares, kept for the app to show
export MBUI_IOS_SHARE_PLIST=$A/ios/Share-Info.plist
# the build's number as Android's versionCode (main's commits: git rev-list --count HEAD), where this is a checkout;
# MBUI_IOS_BUILD says it otherwise
if [ -z "${MBUI_IOS_BUILD:-}" ] && n=$(git -C "$A" rev-list --count HEAD 2>/dev/null); then export MBUI_IOS_BUILD=$n; fi
# the asset catalog: the icon (Android's launcher icon, as macOS's: scripts/mac-icon.swift, still.fail's black face and,
# for a dark Home Screen, its white one; made once for each version of its script) and the launch screen's ground (Paper: the page's paper, light and dark, as Android's windowBackground
# is, so opening does not flash white or black)
if [ "${1:-build}" = build ]; then
  export MBUI_IOS_ASSETS=$A/out/ios-assets-$(cat "$D/mac-icon.swift" "$0" | shasum -a 256 | cut -c1-12)/Assets.xcassets
  if [ ! -f "$MBUI_IOS_ASSETS/AppIcon.appiconset/icon.png" ]; then
    mkdir -p "$MBUI_IOS_ASSETS/AppIcon.appiconset" "$MBUI_IOS_ASSETS/Paper.colorset"
    echo '{"info":{"author":"xcode","version":1}}' > "$MBUI_IOS_ASSETS/Contents.json"
    echo '{"images":[{"filename":"icon.png","idiom":"universal","platform":"ios","size":"1024x1024"},{"appearances":[{"appearance":"luminosity","value":"dark"}],"filename":"icon-dark.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}' \
      > "$MBUI_IOS_ASSETS/AppIcon.appiconset/Contents.json"
    paper() { echo "{\"color\":{\"color-space\":\"srgb\",\"components\":{\"red\":\"0x$1\",\"green\":\"0x$2\",\"blue\":\"0x$3\",\"alpha\":\"1.000\"}},\"idiom\":\"universal\"$4}"; }
    echo "{\"colors\":[$(paper F5 F3 EF),$(paper 1B 1C 1F ',"appearances":[{"appearance":"luminosity","value":"dark"}]')],\"info\":{\"author\":\"xcode\",\"version\":1}}" \
      > "$MBUI_IOS_ASSETS/Paper.colorset/Contents.json"
    swift "$D/mac-icon.swift" --ios "$MBUI_IOS_ASSETS/AppIcon.appiconset/icon.png" > /dev/null
    swift "$D/mac-icon.swift" --ios stable-dark "$MBUI_IOS_ASSETS/AppIcon.appiconset/icon-dark.png" > /dev/null
  fi
fi
case $APP in coredemo | stillfail) export MBUI_IOS_HOOK=$D/ios-core.sh ;; esac
exec bash "$MBUI_DIR/scripts/ios.sh" "$@"

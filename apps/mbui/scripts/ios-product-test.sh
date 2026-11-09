#!/bin/bash
# The real bundle hook and its environment reader, with dummy core assets. Foundation alone; no iOS SDK or network.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/out/core" "$T/hermes/hermes.framework" "$T/MBUI.app/PlugIns/Share.appex"
printf core > "$T/out/core/core.hbc"
printf framework > "$T/hermes/hermes.framework/hermes"
cp "$D/../ios/Info.plist" "$T/MBUI.app/Info.plist"
cp "$D/../ios/Share-Info.plist" "$T/MBUI.app/PlugIns/Share.appex/Info.plist"
(
  cd "$T"
  PKG=stillfail
  . "$D/ios-core.sh"
  HERMES_SLICE=$T/hermes APPDIR=$T/MBUI.app MBUI_IOS_PRODUCT=monoid app_bundle
)
for p in "$T/MBUI.app/Info.plist" "$T/MBUI.app/PlugIns/Share.appex/Info.plist"; do
  [ "$(plutil -extract CFBundleName raw -o - "$p")" = monoid ]
  [ "$(plutil -extract CFBundleDisplayName raw -o - "$p")" = monoid ]
done
[ "$(plutil -extract MBUIShareTaken raw -o - "$T/MBUI.app/PlugIns/Share.appex/Info.plist")" = '已收下。打开 monoid，选要发到的对话。' ]
clang -fobjc-arc -framework Foundation "$D/ios-product-test.m" -o "$T/product-test"
"$T/product-test" "$T/MBUI.app/Info.plist"

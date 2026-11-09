#!/bin/bash
# What the app's builds weigh, in bytes, printed as JSON (the trend's: .github/workflows/mbui-size.yml):
#   web DIR      the web's build (scripts/web-app.sh's web/public/mbui): app.js and host.js as they are, gzip -9'd and
#                brotli -q 11'd (what a browser downloads), the assets beside them
#   apk APK      the Android app: the file, and its largest parts as they are and as packed
#   mac APP|ZIP  the Mac app: the zip (when given one), the .app's files, its program and the core
#   scripts/size.sh web web/public/mbui    scripts/size.sh apk stillfail-beta-7963.apk    scripts/size.sh mac app.zip
set -eo pipefail
bytes() { wc -c < "$1" | tr -d ' '; }
packed() { printf '{"raw":%s,"gzip":%s,"brotli":%s}' "$(bytes "$1")" "$(gzip -9 -c "$1" | wc -c | tr -d ' ')" \
  "$(brotli -q 11 -c "$1" | wc -c | tr -d ' ')"; }
files() { find "$1" -type f -print0 | xargs -0 cat | wc -c | tr -d ' '; }
case $1 in
  web)
    printf '{"web":{"app_js":%s,"host_js":%s,"assets":%s}}\n' "$(packed "$2/app.js")" "$(packed "$2/host.js")" \
      "$(files "$2/assets")"
    ;;
  apk)
    # (unzip -lv: length, method, size as packed, ..., name)
    part() { unzip -lv "$2" | awk -v n="$1" '$NF == n {printf "{\"raw\":%s,\"packed\":%s}", $1, $3; f=1} END {if (!f) printf "null"}'; }
    printf '{"android":{"apk":%s,"libmbui_so":%s,"shell_so":%s,"core_hbc":%s,"dex":%s}}\n' "$(bytes "$2")" \
      "$(part lib/arm64-v8a/libmbui.so "$2")" "$(part lib/arm64-v8a/libstillfail_shell.so "$2")" \
      "$(part assets/core.hbc "$2")" "$(part classes.dex "$2")"
    ;;
  mac)
    zip=null app=$2
    if [ -f "$2" ]; then
      zip=$(bytes "$2")
      tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
      unzip -q "$2" -d "$tmp"
      app=$(ls -d "$tmp"/*.app | head -1)
    fi
    exe=$(sed -n '/<key>CFBundleExecutable<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$app/Contents/Info.plist")
    printf '{"mac":{"zip":%s,"app":%s,"program":%s,"core_hbc":%s}}\n' "$zip" "$(files "$app")" \
      "$(bytes "$app/Contents/MacOS/$exe")" "$(bytes "$app/Contents/Resources/core.hbc")"
    ;;
  *) echo "size.sh web DIR | apk APK | mac APP|ZIP" >&2; exit 2 ;;
esac

#!/bin/bash
# What an app's builds weigh, in bytes, printed as JSON (the trend's: .github/workflows/mbui-size.yml):
#   web DIR      the browser build (scripts/web.sh bundle): app.js (or demo.js) and host.js as they are, gzip -9'd and
#                brotli -q 11'd (what a browser downloads), the assets beside them
#   apk APK      the Android app: the file, and its largest parts as they are and as packed
#   mac APP|ZIP  the Mac app: the zip (when given one), the .app's files, its program and its bundle bytecode
#   scripts/size.sh web out/web    scripts/size.sh apk app-release.apk    scripts/size.sh mac out/mac/demo-mac.zip
set -eo pipefail
P=${MBUI_SIZE_PREFIX:-}
bytes() { wc -c < "$1" | tr -d ' '; }
packed() {
  local raw gz br
  raw=$(bytes "$1")
  gz=$(gzip -9 -c "$1" | wc -c | tr -d ' ')
  if [ -f "$1.br" ]; then
    br=$(bytes "$1.br")
  elif command -v brotli >/dev/null 2>&1; then
    br=$(brotli -q 11 -c "$1" | wc -c | tr -d ' ')
  else
    br=$(node -e 'const z=require("node:zlib"),fs=require("node:fs"),b=fs.readFileSync(process.argv[1]);process.stdout.write(String(z.brotliCompressSync(b,{params:{[z.constants.BROTLI_PARAM_QUALITY]:11,[z.constants.BROTLI_PARAM_LGWIN]:24,[z.constants.BROTLI_PARAM_SIZE_HINT]:b.length}}).length))' "$1")
  fi
  printf '{"raw":%s,"gzip":%s,"brotli":%s}' "$raw" "$gz" "$br"
}
files() {
  [ -d "$1" ] || { echo 0; return; }
  find "$1" -type f -print0 | xargs -0 cat 2>/dev/null | wc -c | tr -d ' '
}
case ${1:-} in
  web)
    js="$2/app.js"; [ -f "$js" ] || js="$2/demo.js"
    printf '{"%sweb":{"app_js":%s,"host_js":%s,"assets":%s}}\n' "$P" "$(packed "$js")" "$(packed "$2/host.js")" \
      "$(files "$2/assets")"
    ;;
  apk)
    # (unzip -lv: length, method, size as packed, ..., name)
    part() { [ -n "$1" ] || { printf "null"; return; }; unzip -lv "$2" | awk -v n="$1" '$NF == n {printf "{\"raw\":%s,\"packed\":%s}", $1, $3; f=1} END {if (!f) printf "null"}'; }
    printf '{"%sandroid":{"apk":%s,"libmbui_so":%s,"shell_so":%s,"core_hbc":%s,"dex":%s}}\n' "$P" "$(bytes "$2")" \
      "$(part lib/arm64-v8a/libmbui.so "$2")" "$(part "${MBUI_APK_SHELL_SO:-}" "$2")" \
      "$(part assets/core.hbc "$2")" "$(part classes.dex "$2")"
    ;;
  mac)
    zip=null app=$2
    if [ -f "$2" ]; then
      zip=$(bytes "$2")
      tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
      unzip -q "$2" -d "$tmp"
      app=$(find "$tmp" -maxdepth 2 -name '*.app' -not -path '*/__MACOSX/*' | head -1)
    fi
    exe=$(sed -n '/<key>CFBundleExecutable<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$app/Contents/Info.plist")
    hbc=null
    [ ! -f "$app/Contents/Resources/core.hbc" ] || hbc=$(bytes "$app/Contents/Resources/core.hbc")
    printf '{"%smac":{"zip":%s,"app":%s,"program":%s,"core_hbc":%s}}\n' "$P" "$zip" "$(files "$app")" \
      "$(bytes "$app/Contents/MacOS/$exe")" "$hbc"
    ;;
  *) echo "size.sh web DIR | apk APK | mac APP|ZIP" >&2; exit 2 ;;
esac

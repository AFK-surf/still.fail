#!/bin/sh
# The Windows app's feeds for an installer of it (apps/mbui/windows/setup.c), as scripts/mac-feeds.sh writes the Mac
# app's: mbui's own updater's, an AppRelease (versionCode, versionName, its file under /releases/, sha256, size)
# carrying the installer's signed words (`signed`: its .sig, scripts/release-sign.ts file; the core offers the build
# only as they say it: client/core-ts src/app-release.ts), and, given a name for it, electron-updater's (version, the
# file's sha512 and size, as electron-builder writes it), which moves an installed desktop app (Electron's) over to it
# (that app checks the .sig beside the installer before it runs it). apps/mbui/e2e/win.sh's: a test's own release.
#   scripts/win-feeds.sh <installer> <its path under /releases/> <build> <its .sig> <the AppRelease's file> [<the yml's file>]
set -eu
exe=$1 file=$2 build=$3 sig=$4
size=$(wc -c < "$exe" | tr -d ' ')
sha256=$(openssl dgst -sha256 -r "$exe" | cut -d' ' -f1)
signed=""
[ ! -f "$sig" ] || signed=",\"signed\":$(tr -d '\r\n' < "$sig")"
printf '{"versionCode":%s,"versionName":"0.1.%s","file":"%s","sha256":"%s","size":%s%s}\n' \
  "$build" "$build" "$file" "$sha256" "$size" "$signed" > "$5"
[ -n "${6:-}" ] || exit 0
name=$(basename "$file")
sha512=$(openssl dgst -sha512 -binary "$exe" | base64 | tr -d '\r\n')
printf "version: 0.1.%s\nfiles:\n  - url: %s\n    sha512: %s\n    size: %s\npath: %s\nsha512: %s\nreleaseDate: '%s'\n" \
  "$build" "$name" "$sha512" "$size" "$name" "$sha512" "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" > "$6"

#!/bin/sh
# The Mac app's two feeds for its zip (scripts/release.sh desktop; apps/mbui/scripts/handoff.sh tries them): mbui's own
# updater's, an AppRelease (versionCode, versionName, its file under /releases/, sha256, size: what the core's
# app.update reads), and electron-updater's (version, the file's sha512 and size, as electron-builder writes it), which
# moves an installed Electron app over to it.
#   scripts/mac-feeds.sh <zip> <its name in desktop/> <build> <the AppRelease's file> <the yml's file>
set -eu
zip=$1 name=$2 build=$3
size=$(wc -c < "$zip" | tr -d ' ')
printf '{"versionCode":%s,"versionName":"0.1.%s","file":"desktop/%s","sha256":"%s","size":%s}\n' \
  "$build" "$build" "$name" "$(shasum -a 256 "$zip" | cut -d' ' -f1)" "$size" > "$4"
sha512=$(openssl dgst -sha512 -binary "$zip" | base64 | tr -d '\n')
printf "version: 0.1.%s\nfiles:\n  - url: %s\n    sha512: %s\n    size: %s\npath: %s\nsha512: %s\nreleaseDate: '%s'\n" \
  "$build" "$name" "$sha512" "$size" "$name" "$sha512" "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" > "$5"

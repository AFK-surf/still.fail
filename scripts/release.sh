#!/bin/sh
# Builds the still.fail station's releases (the station in TypeScript, laid out by scripts/station-bundle.sh) and puts
# them in the cloud's releases bucket, where install.sh (cloud/src/install.ts) gets them: darwin-arm64, linux-x64 and
# linux-arm64, each with its Node and its native parts (prebuilt for that platform: scripts/native.ts); and win32-x64,
# a zip, which install.ps1 gets (cloud/src/install-windows.ts), its Node nodejs.org's zip.
# The apps too, for their updaters: `desktop` (the Mac app: apps/mbui's in the Electron app's place, scripts/beta.sh mac
# MBUI_VARIANT=stable: its zip in desktop/, its feeds mac/latest.json and stillfail-mac.yml, below),
# `desktop-win` (the Windows app: apps/mbui's in the Electron app's place, built on Windows, scripts/win.sh
# MBUI_VARIANT=stable: its installer stillfail-<version>-x64-win.exe in desktop/, not code-signed yet, its feeds
# win/latest.json and stillfail.yml, below) and
# `android` (the Android app: apps/mbui's in the Kotlin one's place, scripts/beta.sh build, MBUI_VARIANT=stable or
# beta: its APK and latest.json, in android/; still.fail's with its native library's symbols, symbols/android/). Their
# version is the commits in the history, so a release is made from a new commit; the latest is put last, once its files
# are there.
#   release.sh [--beta] [PLATFORM…]   (default: the station's four; desktop and android only when named)
#   release.sh promote [station]
# --beta: to the test channel instead (cloud/src/install.ts): the station's tarballs in beta/ and station-beta.json; the
# beta apps, apps of their own beside the released ones (fail.still.desktop.beta: apps/mbui's MBUI_VARIANT=beta, its
# stillfail-beta-<version> zip, its feeds mac/beta/latest.json and desktop/stillfail-beta-mac.yml, electron-updater's
# channel stillfail-beta; the Windows one MBUI_VARIANT=beta, win/beta/latest.json and desktop/stillfail-beta.yml;
# fail.still.android.beta: apps/mbui's,
# MBUI_VARIANT=beta, android/stillfail-beta-<n>.apk and android/beta/latest.json).
# promote: the test channel's station release becomes the stable one: its tarballs and station.json copied to the
# stable names, nothing built (the signed words name no channel: they hold for both). (The beta apps are other apps: a released app is released by release.sh desktop/android.
# The web app is promoted by cloud/deploy.py promote-web.)
# A station's release names the Node it runs on (its NODE_VERSION), which is not in it: that Node goes beside the releases, once
# per version (node/node-v<version>-<platform>.tar.gz and its .sha256: scripts/node-dist.sh), when they lack it.
# RELEASE_DIR=dir: into that directory instead of the bucket (the dev cloud serves them from dist/releases: cloud/test/dev.ts).
# RELEASES=<url>: where the releases are read from, to see whether a Node is there already (still.fail cloud's; "" with
# RELEASE_DIR: only that directory is looked in).
# A feed put straight into the bucket (not into RELEASE_DIR, whose put makes them: .github/workflows/pipeline.yml deltas)
# is put with the deltas from the builds before it (put_feed, scripts/release-deltas.ts; STILLFAIL_DELTAS_SECONDS: how
# long they may take, 90 s), which never hold a release back. The Windows installer goes with its raw form (`--raw`,
# <exe>.raw.zst: what later releases' deltas are made from), its hash in the signed words.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

# r2 <get|put> <key> <wrangler's other arguments>: the bucket's object, tried again twice when Cloudflare's API fails on
# the way (a 502, "fetch failed": three releases stopped on one on 2026-10-02); putting or getting it again is harmless.
r2() {
  verb=$1 key=$2; shift 2
  for try in 1 2 3; do
    (cd "$root/cloud" && pnpm exec wrangler r2 object "$verb" "stillfail-releases/$key" "$@" --remote >/dev/null) && return 0
    [ $try = 3 ] || { echo "r2 $verb $key failed (try $try), trying again" >&2; sleep 15; }
  done
  return 1
}

# copy <name in the bucket> <new name> <content type>: within the bucket (or RELEASE_DIR).
copy() {
  if [ -n "${RELEASE_DIR:-}" ]; then
    mkdir -p "$RELEASE_DIR/$(dirname "$2")" && cp "$RELEASE_DIR/$1" "$RELEASE_DIR/$2" && echo "copied $1 to $2 in $RELEASE_DIR"
  else
    r2 get "$1" --file "$out/copy"
    r2 put "$2" --file "$out/copy" --content-type "$3"
    rm -f "$out/copy"
    echo "copied $1 to $2"
  fi
}

# put <file> <name in the bucket> <content type>
put() {
  if [ -n "${RELEASE_DIR:-}" ]; then
    mkdir -p "$RELEASE_DIR/$(dirname "$2")" && cp "$1" "$RELEASE_DIR/$2" && echo "put $2 in $RELEASE_DIR"
  else
    # (its failure returned: a caller that goes on without it, as the symbols' below, runs it outside set -e)
    r2 put "$2" --file "$1" --content-type "$3" || return 1
    echo "uploaded $2 ($(du -h "$1" | cut -f1))"
  fi
}

# Where the releases are now, for the deltas from the builds before (monoid's: its own cloud's, below).
deltas_from=${RELEASES:-https://app.still.fail/releases}
# put_feed <file> <name in the bucket> <content type> [<a package's name in the bucket>=<its file>…]: a feed, after the
# files it names. Into RELEASE_DIR as it is; into the bucket with the deltas to it from the builds before (made in a
# directory of their own holding the feed and its packages: scripts/release-deltas.ts), put before it. Without them
# (none made, or one not put) the feed is put as it was: a delta only spares a download.
put_feed() {
  feed_file=$1 feed_name=$2 feed_type=$3
  shift 3
  if [ -n "${RELEASE_DIR:-}" ]; then put "$feed_file" "$feed_name" "$feed_type"; return; fi
  rm -rf "$out/deltas" "$out/deltas-made" && mkdir -p "$out/deltas/$(dirname "$feed_name")" "$out/deltas-made"
  cp "$feed_file" "$out/deltas/$feed_name"
  for package in "$@"; do
    mkdir -p "$out/deltas/$(dirname "${package%%=*}")"
    ln -s "${package#*=}" "$out/deltas/${package%%=*}" 2>/dev/null || cp "${package#*=}" "$out/deltas/${package%%=*}"
  done
  node "$root/scripts/release-deltas.ts" "$out/deltas" --into "$out/deltas-made" --releases "$deltas_from" \
    --deadline "${STILLFAIL_DELTAS_SECONDS:-90}" || echo "release.sh: no deltas for $feed_name (scripts/release-deltas.ts failed)" >&2
  whole=yes
  for name in $(cd "$out/deltas-made" && find . -type f | sed 's|^\./||' | sort); do
    [ "$name" != "$feed_name" ] || continue
    case $name in *.zip) ctype=application/zip ;; *.tar.gz) ctype=application/gzip ;; *) ctype=application/octet-stream ;; esac
    if r2 put "$name" --file "$out/deltas-made/$name" --content-type "$ctype"; then echo "uploaded $name ($(du -h "$out/deltas-made/$name" | cut -f1))"
    else whole=""; echo "release.sh: $name not put: $feed_name is put without its deltas" >&2; fi
  done
  if [ -n "$whole" ] && [ -f "$out/deltas-made/$feed_name" ]; then put "$out/deltas-made/$feed_name" "$feed_name" "$feed_type"
  else put "$feed_file" "$feed_name" "$feed_type"; fi
  rm -rf "$out/deltas" "$out/deltas-made"
}

if [ "${1:-}" = promote ]; then
  shift
  for what in ${*:-station}; do
    case $what in
      # The tarballs first, the feed that says they are out last: the test channel's without its deltas (from the test
      # channel's builds), with the deltas from the stable channel's own builds before it (put_feed).
      station)
        for platform in darwin-arm64 linux-x64 linux-arm64; do copy "beta/stillfail-station-$platform.tar.gz" "stillfail-station-$platform.tar.gz" application/gzip; done
        copy beta/stillfail-station-win32-x64.zip stillfail-station-win32-x64.zip application/zip
        if [ -n "${RELEASE_DIR:-}" ]; then cp "$RELEASE_DIR/station-beta.json" "$out/station.json"; else r2 get station-beta.json --file "$out/station.json"; fi
        node -e 'const fs = require("fs"), f = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); delete f.deltas; fs.writeFileSync(process.argv[1], JSON.stringify(f) + "\n")' "$out/station.json"
        put_feed "$out/station.json" station.json application/json
        ;;
      *) echo "promote what? only the station (the beta apps are apps of their own: release.sh desktop or android releases the stable ones), not $what" >&2; exit 2 ;;
    esac
  done
  exit 0
fi

# --product monoid: monoid's apps (the same apps on monoid's cloud: apps/mbui's monoid and monoid-beta variants), for
# monoid's bucket (in the company's Cloudflare account: CLOUDFLARE_API_TOKEN its), named monoid(-beta)-…; its stations
# install still.fail's releases (cloud/src/install.ts sharedRelease), so only the apps.
product=stillfail
if [ "${1:-}" = --product ]; then product=$2; shift 2; fi
case $product in stillfail | monoid) ;; *) echo "release.sh: --product is stillfail or monoid, not $product" >&2; exit 2 ;; esac
[ "$product" = stillfail ] || deltas_from=${RELEASES:-https://app.$product.build/releases}
beta=""
if [ "${1:-}" = --beta ]; then beta=yes; shift; fi
platforms=${*:-darwin-arm64 linux-x64 linux-arm64 win32-x64}
for platform in $platforms; do
  case "$product $platform" in
    "monoid android" | "monoid desktop" | "monoid desktop-win") ;;
    monoid\ *) echo "release.sh: monoid releases its apps alone (android, desktop, desktop-win), not $platform" >&2; exit 2 ;;
  esac
  # (the Windows app is mbui's, built on Windows: below)
  if [ "$platform" = desktop-win ]; then
    case "$(uname -s)" in MINGW* | MSYS*) continue ;; esac
    echo "the Windows app's release requires Windows (Git Bash, MSVC's environment: apps/mbui/scripts/win.sh)" >&2; exit 1
  fi
  if [ "$platform" != android ] && [ "$(uname -s)-$(uname -m)" != Darwin-arm64 ]; then
    echo "$platform releases require a Mac with Apple silicon" >&2; exit 1
  fi
done

build=$(git -C "$root" rev-list --count HEAD)
releases=${RELEASES-https://app.still.fail/releases}
# Whether the releases have <name> already: in RELEASE_DIR, or where they are read from.
released() {
  # Its first byte asked for: the releases answer GET (ranges too), not HEAD.
  { [ -n "${RELEASE_DIR:-}" ] && [ -f "$RELEASE_DIR/$1" ]; } || { [ -n "$releases" ] && curl -fs -r 0-0 -o /dev/null "$releases/$1"; }
}
[ -z "$(git -C "$root" status --porcelain)" ] || echo "note: the working tree has changes; the apps are numbered by the commit ($build) all the same" >&2

# The station's native parts for each platform asked for side by side first, so station-bundle.sh finds them in the
# cache: one after another, a stable release's (a day old, its parts gone from the CI Mac's cache) took 8 minutes of its
# job's 10 (43460534865, 2026-11-13). One not got here is got (or built) there as before.
for platform in $platforms; do
  case $platform in desktop | desktop-win | android) continue ;; esac
  parts="launcher mesh runner reader"
  [ "$platform" = darwin-arm64 ] && parts="$parts helper"
  [ "$platform" = win32-x64 ] && parts="$parts screen agent-desktop"
  for part in $parts; do node "$root/scripts/native.ts" fetch "$part" "$platform" > /dev/null || : & done
done
wait

for platform in $platforms; do
  case $platform in
    desktop)
      # The Mac app (fail.still.desktop) on its feeds; with --beta the beta app (fail.still.desktop.beta). Both are
      # mbui's (apps/mbui) in the Electron app's place, the beta's since 2026-10-26 (#1980), the stable one's after it
      # (as asked): mac-app.sh's stable or beta variant, with the Electron app's ids, name, program and links, signed by
      # the same team, so an installed Electron app's updater takes it (Squirrel.Mac installs an update only if it
      # meets the running app's designated requirement, which the Electron app's builds made AFK's team, not one
      # certificate; apps/mbui/scripts/handoff.sh tries it) and it keeps that app's data, sign-in and sealed keys
      # where they were (apps/mbui src/sfcore/apple_engine.m, src/host/apple_core.mm). Built as apps/mbui's own app is
      # (scripts/beta.sh mac: MoonBit, the core's shell prebuilt), warm in a cache of its own. Its zip is named as the
      # Electron app's were (the site's download, /releases/latest/mac, and release-prune.ts go by the yml's), on two
      # feeds (scripts/mac-feeds.sh): mbui's own updater's (mac/latest.json, mac/beta/latest.json, an AppRelease: what
      # the core's app.update reads) and electron-updater's (stillfail(-beta)-mac.yml), which moves an installed
      # Electron app over.
      variant=${beta:+beta}
      variant=${variant:-stable}
      # (monoid's: build.monoid.desktop, .beta, its own name and links; no Electron app of its own to move over)
      [ "$product" = stillfail ] || variant=$product${beta:+-beta}
      mbui_cache=${MBUI_MAC_CACHE:-$HOME/stillfail-ci/mbui-mac-$variant}
      tools=
      # A fresh CI checkout already has MoonBit on PATH; a persistent machine keeps its own toolchain in the cache.
      if [ "${MBUI_FRESH:-}" = 1 ]; then
        mbui_cache=${MBUI_MAC_CACHE:-${MBUI_CACHE:-$mbui_cache}}
      else
        MBUI_CACHE=$mbui_cache bash "$root/apps/mbui/scripts/beta.sh" tools
        tools=$mbui_cache/tools
      fi
      MBUI_CACHE=$mbui_cache MBUI_TOOLS=$tools MBUI_VARIANT=$variant RELEASE_DIR="$out/mbui" \
        bash "$root/apps/mbui/scripts/beta.sh" mac
      app_zip="$out/mbui/mac/app-$variant.zip"
      id=fail.still.desktop${beta:+.beta}
      [ "$product" = stillfail ] || id=build.$product.desktop${beta:+.beta}
      # what is in it checked before anything is uploaded: the app it replaces (its id), signed by still.fail's team
      # (an installed app takes nothing else; UNSIGNED=1, as build.sh's: for trying it out, never put), its build
      rm -rf "$out/mac-check" && mkdir -p "$out/mac-check" && ditto -x -k "$app_zip" "$out/mac-check"
      app=$(find "$out/mac-check" -maxdepth 1 -name '*.app' | head -1)
      [ -n "$app" ] || { echo "release.sh: no app in $app_zip" >&2; exit 1; }
      codesign --verify --deep --strict "$app" || { echo "release.sh: $app does not verify (codesign): not released" >&2; exit 1; }
      signed=$(codesign -dvv "$app" 2>&1)
      have_id=$(printf '%s\n' "$signed" | sed -n 's/^Identifier=//p')
      have_team=$(printf '%s\n' "$signed" | sed -n 's/^TeamIdentifier=//p')
      have_build=$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")
      [ "$have_id" = "$id" ] && [ "$have_build" = "$build" ] || { echo "release.sh: $app is $have_id $have_build, not $id $build: not released" >&2; exit 1; }
      [ "$have_team" = D9AAN3VJK8 ] || [ -n "${UNSIGNED:-}" ] || { echo "release.sh: $app is signed by ${have_team:-no team}, not still.fail's (D9AAN3VJK8): not released" >&2; exit 1; }
      echo "$app: $have_id $have_build, signed by team $have_team"
      zip="$product${beta:+-beta}-0.1.$build-arm64-mac.zip"
      put "$app_zip" "desktop/$zip" application/zip
      if [ -z "${RELEASE_DIR:-}" ]; then
        work=${WORK:-"$mbui_cache/work"}
        if [ "${MBUI_FRESH:-}" = 1 ]; then work="$root/apps/mbui"; fi
        sh "$root/scripts/release-put.sh" --clean-uploaded "desktop/$zip" "$work/out/mac/$product${beta:+-beta}-$build-arm64-mac.zip"
      fi
      sh "$root/scripts/mac-feeds.sh" "$app_zip" "$zip" "$build" "$out/mac-latest.json" "$out/mac.yml"
      put_feed "$out/mac-latest.json" "mac/${beta:+beta/}latest.json" application/json "desktop/$zip=$app_zip"
      # (electron-updater's, which moves an installed Electron app over: still.fail's alone had one)
      [ "$product" != stillfail ] || put "$out/mac.yml" "desktop/stillfail${beta:+-beta}-mac.yml" "text/yaml; charset=utf-8"
      ;;
    desktop-win)
      # The Windows app (fail.still.desktop; with --beta the beta app, fail.still.desktop.beta) is mbui's (apps/mbui) in
      # the Electron app's place, as the Mac one is, the beta's since 2026-10-26 (#2086), the stable one's after it:
      # scripts/win.sh's stable or beta variant (the Electron app's id, name, program and links, its data, sign-in and
      # sealed keys where they were: src/host/win_core.c), packed in its installer (apps/mbui/windows/setup.c), which an
      # installed Electron app's updater runs as it ran its own (--updated /S --force-run). Named as the Electron app's
      # were (the site's download, /releases/latest/win(-beta), and release-prune.ts go by the yml's), signed (its .sig,
      # which that app checks before it runs it), on two feeds (scripts/win-feeds.sh): mbui's own updater's
      # (win/latest.json, win/beta/latest.json, an AppRelease carrying the signed words: what the core's app.update
      # takes) and electron-updater's (stillfail(-beta).yml), which moves an installed Electron app over.
      variant=${beta:+beta}
      variant=${variant:-stable}
      id=fail.still.desktop${beta:+.beta}
      program=still.fail
      [ -z "$beta" ] || program=youdid.wtf
      # (monoid's: build.monoid.desktop, .beta, its program monoid or monoid.zone: apps/mbui/scripts/win.sh)
      if [ "$product" = monoid ]; then
        variant=monoid${beta:+-beta} id=build.monoid.desktop${beta:+.beta} program=monoid
        [ -z "$beta" ] || program=monoid.zone
      fi
      exe="$product${beta:+-beta}-0.1.$build-x64-win.exe"
      MBUI_VARIANT=$variant MBUI_BUILD=$build bash "$root/apps/mbui/scripts/win.sh" build
      MBUI_VARIANT=$variant MBUI_BUILD=$build MBUI_SETUP_NAME=$exe bash "$root/apps/mbui/scripts/win.sh" setup
      setup_out=$root/apps/mbui/out/setup
      # what is in it checked before anything is uploaded: the app it replaces (its id, its program), its build
      grep -qx "APP_ID=$id" "$setup_out/setup.env" && grep -qx "EXE=$program" "$setup_out/setup.env" &&
        grep -qx "VERSION=0.1.$build" "$setup_out/setup.env" || { echo "release.sh: $exe is not $id 0.1.$build: not released" >&2; cat "$setup_out/setup.env" >&2; exit 1; }
      rm -f "$setup_out/$exe.sig" "$setup_out/$exe.raw" "$setup_out/$exe.raw.zst"
      # its raw form (what it carries stored: setup.c --raw), what deltas to it make and later ones are made from; its hash
      # in the signed words (the apps' core takes it from there alone), it beside the installer zstd'd (a few seconds of
      # this job's: the deltas are made after, elsewhere). Without it the release goes out all the same, with no deltas.
      raw=""
      if "$setup_out/$exe" --raw "$setup_out/$exe.raw" && [ -s "$setup_out/$exe.raw" ]; then raw="$setup_out/$exe.raw"
      else echo "release.sh: warning: $exe --raw made nothing: released without its raw form (no deltas to it)" >&2; fi
      node "$root/scripts/release-sign.ts" file "$setup_out/$exe" --kind stillfail-desktop-win --build "$build" ${raw:+--raw "$raw"} ${RELEASE_DIR:+--unsigned-ok}
      put "$setup_out/$exe" "desktop/$exe" application/vnd.microsoft.portable-executable
      [ ! -f "$setup_out/$exe.sig" ] || put "$setup_out/$exe.sig" "desktop/$exe.sig" application/json
      if [ -n "$raw" ]; then
        node "$root/scripts/release-deltas.ts" --zst "$raw" "$raw.zst" && rm -f "$raw"
        put "$raw.zst" "desktop/$exe.raw.zst" application/zstd
      fi
      sh "$root/scripts/win-feeds.sh" "$setup_out/$exe" "desktop/$exe" "$build" "$setup_out/$exe.sig" "$out/win-latest.json" "$out/win.yml"
      put_feed "$out/win-latest.json" "win/${beta:+beta/}latest.json" application/json "desktop/$exe=$setup_out/$exe" ${raw:+"desktop/$exe.raw.zst=$raw.zst"}
      [ "$product" != stillfail ] || put "$out/win.yml" "desktop/stillfail${beta:+-beta}.yml" "text/yaml; charset=utf-8"
      ;;
    android)
      # fail.still.android on android/latest.json; with --beta fail.still.android.beta on android/beta/latest.json. The
      # beta app is mbui's (apps/mbui) in the place of the one in Kotlin: the same package, signed with
      # the same key, so an installed beta updates to it, its files and sign-ins taken as they are (apps/mbui's
      # CoreHost); built as apps/mbui's own beta is (scripts/beta.sh: MoonBit, the engine and shell prebuilt), warm in
      # a cache of its own. The stable app is mbui's too since 2026-10-24 (as asked; the Kotlin one stopped at
      # 0.1.4520): apk.json's `stable` variant, fail.still.android, the same key, updating the Kotlin app in place.
      variant=${beta:+beta}
      variant=${variant:-stable}
      # (monoid's: build.monoid.android, .beta, the same key)
      [ "$product" = stillfail ] || variant=$product${beta:+-beta}
      mbui_cache=${MBUI_CACHE:-$HOME/stillfail-ci/mbui-beta}
      # (one build in the cache at a time: still.fail's and monoid's Android apps are built on the same machine, often
      # at once, and wrote each other's C over in its work/out (2026-11-04, "mbc: cannot write"); lockf's lock goes with
      # the build that holds it, however it ends)
      mkdir -p "$mbui_cache"
      lockf -k "$mbui_cache/.build.lock" env MBUI_CACHE="$mbui_cache" MBUI_VARIANT="$variant" RELEASE_DIR="$out/mbui" \
        root="$root" sh -c '
          set -e
          bash "$root/apps/mbui/scripts/beta.sh" tools
          node "$root/scripts/native.ts" fetch engine android-arm64 > /dev/null
          node "$root/scripts/native.ts" fetch shell android-arm64 > /dev/null
          MBUI_TOOLS=$MBUI_CACHE/tools bash "$root/apps/mbui/scripts/beta.sh" build
        '
      apk="$out/mbui/android/app-$variant.apk"
      # its signature verified before anything is uploaded: one that does not verify is not released (it was, printed
      # and passed over, until 2026-10-20)
      apksigner="${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/36.0.0/apksigner"
      "$apksigner" verify "$apk" || { echo "release.sh: $apk does not verify (apksigner): not released" >&2; exit 1; }
      # and signed with our key, not merely a key: an installed app updates only to an APK of the same certificate.
      # The certificate expected for releases (ANDROID_DEBUG_KEYSTORE_B64), checked against an earlier release.
      want=a01a48b5e1a6d2abfbea3457b6c71d1257bc429793bd8b3ebef6be8ee155b56a
      have=$("$apksigner" verify --print-certs "$apk" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
      [ "$have" = "$want" ] || { echo "release.sh: $apk is signed with ${have:-no certificate}, not $want: not released" >&2; exit 1; }
      echo "$apk: signed with $have (SHA-256), release key"
      name="$product${beta:+-beta}-$build.apk"
      put "$apk" "android/$name" application/vnd.android.package-archive
      printf '{"versionCode":%s,"versionName":"0.1.%s","file":"android/%s","sha256":"%s","size":%s}\n' \
        "$build" "$build" "$name" "$(shasum -a 256 "$apk" | cut -d' ' -f1)" "$(wc -c < "$apk" | tr -d ' ')" > "$out/latest.json"
      put_feed "$out/latest.json" "android/${beta:+beta/}latest.json" application/json "android/$name=$apk"
      # Its libmbui.so's function symbols (beta.sh build: the library as linked, before the APK stripped it), to name the
      # frames of its crash reports (scripts/crash-symbols.ts), kept 30 days (scripts/release-prune.ts; the owner,
      # 2026-11-11) and never served (cloud/src/install.ts releaseType). Put after the feed, and never a reason to fail
      # or hold back the release: a warning. still.fail's own app's only (monoid's: none made).
      syms="$out/mbui/android/app-$variant.syms.xz"
      if [ "$product" = stillfail ]; then
        if [ ! -s "$syms" ]; then echo "release.sh: warning: no symbols of $name (beta.sh build made none)" >&2
        elif ! put "$syms" "symbols/android/${name%.apk}.syms.xz" application/x-xz; then
          echo "release.sh: warning: the symbols of $name were not put" >&2
        fi
      fi
      ;;
    *)
      sh "$root/scripts/station-bundle.sh" "$out/$platform" "$platform"
      # Packed and put beside the next platform's bundling (each ~20 s, one after another before 2026-10-04).
      # Windows' a zip (install.ps1 opens it with Expand-Archive), its Node nodejs.org's own zip (node-dist.sh).
      if [ "$platform" = win32-x64 ]; then
        file="stillfail-station-$platform.zip"
        station_files="${station_files:-} ${beta:+beta/}$file=$out/$file"
        (rm -f "$out/$file" && (cd "$out/$platform" && zip -qr "$out/$file" stillfail) && put "$out/$file" "${beta:+beta/}$file" application/zip) &
        node_file="node/node-v$(cat "$root/.node-version")-win-x64.zip"
      else
        file="stillfail-station-$platform.tar.gz"
        station_files="${station_files:-} ${beta:+beta/}$file=$out/$file"
        (tar -czf "$out/$file" -C "$out/$platform" stillfail && put "$out/$file" "${beta:+beta/}$file" application/gzip) &
        node_file="node/node-v$(cat "$root/.node-version")-$platform.tar.gz"
      fi
      putting="${putting:-} $!"
      # Its Node (cached by node-dist.sh): its binary's hash is in the signed words; put unless the releases have that
      # version already.
      dist=$(sh "$root/scripts/node-dist.sh" "$out/node-$platform" "$platform")
      signing="${signing:-} $platform=$out/$file,$dist"
      if ! released "$node_file"; then
        node_type=application/gzip; [ "$platform" = win32-x64 ] && node_type=application/zip
        put "$dist" "$node_file" "$node_type"
        put "$dist.sha256" "$node_file.sha256" "text/plain; charset=utf-8"
      fi
      station=yes
      ;;
  esac
done
for pid in ${putting:-}; do wait "$pid" || { echo "a station release was not put" >&2; exit 1; }; done
# What stations read to say a newer release is out (station/src/updates/updates.ts), once its files are there: its
# version, and the words naming each archive and its Node, signed with $RELEASE_SIGNING_KEY (scripts/release-sign.ts,
# scripts/release-sign.ts). Not signing is an error but into RELEASE_DIR outside CI (a dev cloud's), where it warns.
if [ -n "${station:-}" ]; then
  node "$root/scripts/release-sign.ts" station "$out/station.json" --build "$build" --commit "$(git -C "$root" rev-parse HEAD)" \
    --node "$(cat "$root/.node-version")" ${RELEASE_DIR:+--unsigned-ok} $signing
  # shellcheck disable=SC2086 # name=file pairs, one word each
  put_feed "$out/station.json" "station${beta:+-beta}.json" application/json $station_files
fi

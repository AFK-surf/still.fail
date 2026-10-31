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
# beta: its APK and latest.json, in android/). Their version is the
# commits in the history, so a release is made from a new commit; the latest is put last, once its files are there.
# And `modules`: the packages of the modules stations install themselves (scripts/module-bundle.ts: each one's archive
# in modules/<id>/, and its feed, modules/<id>/<id>.json or with --beta <id>-beta.json; any machine builds them).
#   release.sh [--beta] [PLATFORM…]   (default: the station's four; desktop, android and modules only when named)
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

if [ "${1:-}" = promote ]; then
  shift
  for what in ${*:-station}; do
    case $what in
      # The tarballs first, the feed that says they are out last.
      station)
        for platform in darwin-arm64 linux-x64 linux-arm64; do copy "beta/stillfail-station-$platform.tar.gz" "stillfail-station-$platform.tar.gz" application/gzip; done
        copy beta/stillfail-station-win32-x64.zip stillfail-station-win32-x64.zip application/zip
        copy station-beta.json station.json application/json
        ;;
      *) echo "promote what? only the station (the beta apps are apps of their own: release.sh desktop or android releases the stable ones), not $what" >&2; exit 2 ;;
    esac
  done
  exit 0
fi

beta=""
if [ "${1:-}" = --beta ]; then beta=yes; shift; fi
platforms=${*:-darwin-arm64 linux-x64 linux-arm64 win32-x64}
for platform in $platforms; do
  # (the Windows app is mbui's, built on Windows: below)
  if [ "$platform" = desktop-win ]; then
    case "$(uname -s)" in MINGW* | MSYS*) continue ;; esac
    echo "the Windows app's release requires Windows (Git Bash, MSVC's environment: apps/mbui/scripts/win.sh)" >&2; exit 1
  fi
  if [ "$platform" != android ] && [ "$platform" != modules ] && [ "$(uname -s)-$(uname -m)" != Darwin-arm64 ]; then
    echo "$platform releases require a Mac with Apple silicon" >&2; exit 1
  fi
done

# put <file> <name in the bucket> <content type>
put() {
  if [ -n "${RELEASE_DIR:-}" ]; then
    mkdir -p "$RELEASE_DIR/$(dirname "$2")" && cp "$1" "$RELEASE_DIR/$2" && echo "put $2 in $RELEASE_DIR"
  else
    r2 put "$2" --file "$1" --content-type "$3"
    echo "uploaded $2 ($(du -h "$1" | cut -f1))"
  fi
}

build=$(git -C "$root" rev-list --count HEAD)
releases=${RELEASES-https://app.still.fail/releases}
# Whether the releases have <name> already: in RELEASE_DIR, or where they are read from.
released() {
  # Its first byte asked for: the releases answer GET (ranges too), not HEAD.
  { [ -n "${RELEASE_DIR:-}" ] && [ -f "$RELEASE_DIR/$1" ]; } || { [ -n "$releases" ] && curl -fs -r 0-0 -o /dev/null "$releases/$1"; }
}
[ -z "$(git -C "$root" status --porcelain)" ] || echo "note: the working tree has changes; the apps are numbered by the commit ($build) all the same" >&2

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
      mbui_cache=${MBUI_MAC_CACHE:-$HOME/stillfail-ci/mbui-mac-$variant}
      MBUI_CACHE=$mbui_cache bash "$root/apps/mbui/scripts/beta.sh" tools
      MBUI_CACHE=$mbui_cache MBUI_TOOLS=$mbui_cache/tools MBUI_VARIANT=$variant RELEASE_DIR="$out/mbui" \
        bash "$root/apps/mbui/scripts/beta.sh" mac
      app_zip="$out/mbui/mac/app-$variant.zip"
      id=fail.still.desktop${beta:+.beta}
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
      zip="stillfail${beta:+-beta}-0.1.$build-arm64-mac.zip"
      put "$app_zip" "desktop/$zip" application/zip
      if [ -z "${RELEASE_DIR:-}" ]; then
        work=${WORK:-"$mbui_cache/work"}
        if [ "${MBUI_FRESH:-}" = 1 ]; then work="$root/apps/mbui"; fi
        sh "$root/scripts/release-put.sh" --clean-uploaded "desktop/$zip" "$work/out/mac/stillfail${beta:+-beta}-$build-arm64-mac.zip"
      fi
      sh "$root/scripts/mac-feeds.sh" "$app_zip" "$zip" "$build" "$out/mac-latest.json" "$out/mac.yml"
      put "$out/mac-latest.json" "mac/${beta:+beta/}latest.json" application/json
      put "$out/mac.yml" "desktop/stillfail${beta:+-beta}-mac.yml" "text/yaml; charset=utf-8"
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
      exe="stillfail${beta:+-beta}-0.1.$build-x64-win.exe"
      MBUI_VARIANT=$variant MBUI_BUILD=$build bash "$root/apps/mbui/scripts/win.sh" build
      MBUI_VARIANT=$variant MBUI_BUILD=$build MBUI_SETUP_NAME=$exe bash "$root/apps/mbui/scripts/win.sh" setup
      setup_out=$root/apps/mbui/out/setup
      # what is in it checked before anything is uploaded: the app it replaces (its id, its program), its build
      grep -qx "APP_ID=$id" "$setup_out/setup.env" && grep -qx "EXE=$program" "$setup_out/setup.env" &&
        grep -qx "VERSION=0.1.$build" "$setup_out/setup.env" || { echo "release.sh: $exe is not $id 0.1.$build: not released" >&2; cat "$setup_out/setup.env" >&2; exit 1; }
      rm -f "$setup_out/$exe.sig"
      node "$root/scripts/release-sign.ts" file "$setup_out/$exe" --kind stillfail-desktop-win --build "$build" ${RELEASE_DIR:+--unsigned-ok}
      put "$setup_out/$exe" "desktop/$exe" application/vnd.microsoft.portable-executable
      [ ! -f "$setup_out/$exe.sig" ] || put "$setup_out/$exe.sig" "desktop/$exe.sig" application/json
      sh "$root/scripts/win-feeds.sh" "$setup_out/$exe" "desktop/$exe" "$build" "$setup_out/$exe.sig" "$out/win-latest.json" "$out/win.yml"
      put "$out/win-latest.json" "win/${beta:+beta/}latest.json" application/json
      put "$out/win.yml" "desktop/stillfail${beta:+-beta}.yml" "text/yaml; charset=utf-8"
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
      mbui_cache=${MBUI_CACHE:-$HOME/stillfail-ci/mbui-beta}
      MBUI_CACHE=$mbui_cache bash "$root/apps/mbui/scripts/beta.sh" tools
      node "$root/scripts/native.ts" fetch engine android-arm64 > /dev/null
      node "$root/scripts/native.ts" fetch shell android-arm64 > /dev/null
      MBUI_CACHE=$mbui_cache MBUI_TOOLS=$mbui_cache/tools MBUI_VARIANT=$variant RELEASE_DIR="$out/mbui" \
        bash "$root/apps/mbui/scripts/beta.sh" build
      apk="$out/mbui/android/app-$variant.apk"
      # its signature verified before anything is uploaded: one that does not verify is not released (it was, printed
      # and passed over, until 2026-10-20)
      apksigner="${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/36.0.0/apksigner"
      "$apksigner" verify "$apk" || { echo "release.sh: $apk does not verify (apksigner): not released" >&2; exit 1; }
      # and signed with our key, not merely a key: an installed app updates only to an APK of the same certificate.
      # The certificate of studio's ~/.android/debug.keystore (ANDROID_DEBUG_KEYSTORE_B64), as every release so far has
      # it (apksigner verify --print-certs of stillfail-beta-3787.apk, 2026-10-20)
      want=a01a48b5e1a6d2abfbea3457b6c71d1257bc429793bd8b3ebef6be8ee155b56a
      have=$("$apksigner" verify --print-certs "$apk" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
      [ "$have" = "$want" ] || { echo "release.sh: $apk is signed with ${have:-no certificate}, not $want (studio's key): not released" >&2; exit 1; }
      echo "$apk: signed with $have (SHA-256), studio's key"
      name="stillfail${beta:+-beta}-$build.apk"
      put "$apk" "android/$name" application/vnd.android.package-archive
      printf '{"versionCode":%s,"versionName":"0.1.%s","file":"android/%s","sha256":"%s","size":%s}\n' \
        "$build" "$build" "$name" "$(shasum -a 256 "$apk" | cut -d' ' -f1)" "$(wc -c < "$apk" | tr -d ' ')" > "$out/latest.json"
      put "$out/latest.json" "android/${beta:+beta/}latest.json" application/json
      ;;
    modules)
      # Each module's package (scripts/module-bundle.ts, docs/station-modules.md): its archive, named by its version, and
      # its feed on this channel, signed as the station's is. The archive is the same bytes whenever its version is packed
      # (the other channel's, a later commit's): one already out is checked to be these, never put over (it is kept for
      # good where it is served: cloud/src/releases.ts). A module with native parts (the media service's ffmpeg) has an
      # archive per platform, each carrying the parts the release native-artifacts has (the natives job published them).
      ids=$(node "$root/scripts/module-bundle.ts" list)
      for id in $ids; do
        node "$root/scripts/module-bundle.ts" pack "$id" "$out/module" ${beta:+--beta} ${RELEASE_DIR:+--unsigned-ok} > "$out/module.names"
        names=$(cat "$out/module.names")
        feed=${names##* }
        for archive in ${names% *}; do
          if released "$archive"; then
            { { [ -n "${RELEASE_DIR:-}" ] && [ -f "$RELEASE_DIR/$archive" ] && cp "$RELEASE_DIR/$archive" "$out/module.was"; } || curl -fsS -o "$out/module.was" "$releases/$archive"; } &&
              cmp -s "$out/module.was" "$out/module/$archive" ||
              { echo "$archive is out already, with other bytes than packed here: not put over (a change to how modules are packed, or to a native part they carry, is a new version)" >&2; exit 1; }
            echo "$archive is out already, the same"
          else
            put "$out/module/$archive" "$archive" application/gzip
          fi
        done
        put "$out/module/$feed" "$feed" application/json
      done
      ;;
    *)
      sh "$root/scripts/station-bundle.sh" "$out/$platform" "$platform"
      # Under the new name only: the old name (ember-station-*.tar.gz) keeps the last release from before the rename,
      # for the cloud's installer from before it, which would not know this layout (cloud/src/install.ts).
      # Packed and put beside the next platform's bundling (each ~20 s, one after another before 2026-10-04).
      # Windows' a zip (install.ps1 opens it with Expand-Archive), its Node nodejs.org's own zip (node-dist.sh).
      if [ "$platform" = win32-x64 ]; then
        file="stillfail-station-$platform.zip"
        (rm -f "$out/$file" && (cd "$out/$platform" && zip -qr "$out/$file" stillfail) && put "$out/$file" "${beta:+beta/}$file" application/zip) &
        node_file="node/node-v$(cat "$root/.node-version")-win-x64.zip"
      else
        file="stillfail-station-$platform.tar.gz"
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
# docs/release-signing.md). Not signing is an error but into RELEASE_DIR outside CI (a dev cloud's), where it warns.
if [ -n "${station:-}" ]; then
  node "$root/scripts/release-sign.ts" station "$out/station.json" --build "$build" --commit "$(git -C "$root" rev-parse HEAD)" \
    --node "$(cat "$root/.node-version")" ${RELEASE_DIR:+--unsigned-ok} $signing
  put "$out/station.json" "station${beta:+-beta}.json" application/json
fi

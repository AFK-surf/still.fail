#!/bin/bash
# still.fail mbui's beta (fail.still.mbui, "still.fail mbui": the release build of apps/mbui's Android app), built,
# signed and put in the releases bucket as .github/workflows/mbui.yml does on mini1:
#   apps/mbui/scripts/beta.sh tools      MoonBit, its latest release (installed again only when cli.moonbitlang.com
#                                        has a newer one: its ETag), mbui (apps/mbui/mbui), the core's packages
#   apps/mbui/scripts/beta.sh build      the APK (scripts/android.sh, VARIANT=release; MBUI_VARIANT=stable or beta
#                                        still.fail's Android app's own, for scripts/release.sh): versionCode the build (git
#                                        rev-list --count HEAD), signed with ANDROID_DEBUG_KEYSTORE_B64 (every still.fail
#                                        Android release's key; POSTHOG_JSON: the key its crash reports go with), into
#                                        $RELEASE_DIR as android/stillfail-mbui-<n>.apk and android/mbui/latest.json
#                                        (still.fail's AppRelease, news: the commits since the build the feed names now,
#                                        of what the app is built from)
#   apps/mbui/scripts/beta.sh mac        the macOS app (scripts/mac-app.sh: still.fail mbui.app, fail.still.mbui),
#                                        signed with still.fail's identity (.github/mac_signing.py), zipped, into
#                                        $RELEASE_DIR as mac/stillfail-mbui-<n>-arm64-mac.zip and mac/mbui/latest.json
#                                        (MBUI_VARIANT=stable or beta: still.fail's Mac app itself, in the Electron
#                                        app's place, for scripts/release.sh: $RELEASE_DIR/mac/app-<variant>.zip)
#   apps/mbui/scripts/beta.sh win        the Windows app's installer (scripts/win.sh setup: the build, its engine, shell
#                                        and core.hbc packed in it), signed, into $RELEASE_DIR as
#                                        win/stillfail-mbui-<n>-x64-win.exe and win/mbui/latest.json (carrying its .sig)
#   apps/mbui/scripts/beta.sh linux      the Linux app (scripts/linux.sh's build, its engine, shell and core.hbc beside it),
#                                        with its icon and linux/install.sh, in still.fail-mbui/, into $RELEASE_DIR as
#                                        linux/stillfail-mbui-<n>-<x64|arm64>-linux.tar.gz and its machine's feed: x64's
#                                        linux/mbui/latest.json, arm64's linux-arm64/mbui/latest.json (its part, below)
#   apps/mbui/scripts/beta.sh changed android|mac|win|linux|linux-arm64
#                                        yes when what the app is made of (APP_SRC: its code, not its tests, docs,
#                                        scripts or CI) changed since the build that feed names now (or it has none),
#                                        else no: main's push makes and puts a package only then
#   apps/mbui/scripts/beta.sh publish android|mac|win|linux|linux-arm64
#                                        what `build` or `mac` made put (scripts/release-put.sh), fetched back from where
#                                        it is served and checked (size, SHA-256), then its feed: https://app.still.fail/
#                                        releases/latest/android-mbui (mac-mbui) is the newest from then on
# MBUI_FRESH=1 (GitHub's runners, .github/workflows/mbui.yml): the checkout built in place (WORK=apps/mbui), what stays
# between runs the Actions cache's (MBC_STORE, MBC_LTO_CACHE, HBC_CACHE, the core's parts in out/core), the release in
# MBUI_CACHE ($RUNNER_TEMP's).
# Warm between runs on a machine of its own (WORK, MBUI_CACHE): the build runs in a copy of apps/mbui kept outside the job's checkout (which the
# other jobs' clean takes), so moonc's and the compiler's outputs and the link stay; core.hbc is kept by its inputs
# (HBC_CACHE), the APK's dex by its own (mbui's scripts/apk: APK_CACHE).
set -eo pipefail
A=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$A/../.." && pwd)
C=${MBUI_CACHE:-$HOME/stillfail-ci/mbui}
if [ "${MBUI_FRESH:-}" = 1 ]; then WORK=$A; else WORK=${WORK:-$C/work}; fi
RELEASE_DIR=${RELEASE_DIR:-$C/release}
ORIGIN=${STILLFAIL_ORIGIN:-https://app.still.fail}
mkdir -p "$C"
now() { python3 -c 'import time;print(time.time())'; }
secs() { python3 -c "print(f'{$(now)-$1:.1f}')"; }
summary() { [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "$*" >> "$GITHUB_STEP_SUMMARY"; echo "$*"; }
setenv() { export "$1=$2"; [ -z "${GITHUB_ENV:-}" ] || echo "$1=$2" >> "$GITHUB_ENV"; }
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
BT=$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1 || true)
build_number() { git -C "$REPO" rev-list --count HEAD; }
# What the app is made of: its code, what it is built with (mbui, its Android host's Java and resources among it:
# apps/mbui/android/apk.json; the core, the client's packages, media's, vendor's crates), not their tests, docs, the
# scripts or CI (a push of those alone is no new package: 2026-10-21)
APP_SRC=(apps/mbui/src apps/mbui/core apps/mbui/android apps/mbui/ios apps/mbui/windows apps/mbui/engine
  apps/mbui/mbui/src apps/mbui/mbui/android apps/mbui/mbui/moon.mod apps/mbui/moon.mod apps/mbui/moon.work client media vendor
  ':(exclude,glob)**/test/**' ':(exclude,glob)**/tests/**' ':(exclude,glob)**/*_test.mbt' ':(exclude,glob)**/*_wbtest.mbt' ':(exclude,glob)**/*.test.*'
  ':(exclude,glob)**/*.md')
# the commit PART's feed names now (versionCode n is main's nth commit); nothing when it has none
released() {
  local n
  n=$(curl -fsS --max-time 10 "$ORIGIN/releases/$1/mbui/latest.json" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["versionCode"])' 2>/dev/null || true)
  [ -z "$n" ] || git -C "$REPO" rev-list --reverse HEAD | sed -n "${n}p"
}
changed() {
  local prev
  prev=$(released "$1")
  if [ -n "$prev" ] && git -C "$REPO" diff --quiet --no-renames "$prev" HEAD -- "${APP_SRC[@]}"; then echo no; else echo yes; fi
}

# The latest MoonBit, in $C/moon/<its ETag's hash>, MBUI_TOOLS=$C/tools (tools/moon: that one) for mbui's env.sh: the
# ETags of the release's two downloads (the binaries and the core) asked each run (a HEAD each), the install only when
# they changed; the one before is kept.
moon_tools() {
  local base=https://cli.moonbitlang.com tag dir
  mkdir -p "$C/moon" "$C/tools"
  # (a curl that fails, as mini1's line now and then does, is an answer missing: the MoonBit there is kept below)
  tag=$( { curl -sfI --max-time 5 $base/binaries/latest/moonbit-darwin-aarch64.tar.gz || true; curl -sfI --max-time 5 $base/cores/core-latest.tar.gz || true; } \
    | tr -d '\r' | awk -F': ' 'tolower($1) == "etag" { print $2 }' | tr -d '\n')
  if [ "$(printf '%s' "$tag" | tr -cd '"' | wc -c | tr -d ' ')" != 4 ]; then
    dir=$(readlink "$C/tools/moon" 2>/dev/null || true)
    [ -n "$dir" ] || { echo "beta: no MoonBit, and cli.moonbitlang.com does not answer" >&2; exit 1; }
    echo "beta: cli.moonbitlang.com did not answer; MoonBit as it is ($(basename "$dir"))"
  else
    dir=$C/moon/$(printf '%s' "$tag" | shasum -a 256 | cut -c1-16)
    if [ ! -x "$dir/bin/moon" ]; then
      local t0=$(now) tmp=$C/moon/new.$$
      echo "beta: MoonBit has a new release ($tag): installing it"
      rm -rf "$tmp" && mkdir -p "$tmp"
      curl -fsSL --max-time 60 --retry 2 https://cli.moonbitlang.com/install/unix.sh -o "$tmp/install.sh"
      # (its HOME for the download, its bin first on PATH: it leaves the shell's rc files alone)
      HOME=$tmp MOON_HOME=$tmp PATH="$tmp/bin:$PATH" bash "$tmp/install.sh" > "$C/moon/install.log" 2>&1 \
        || { tail -20 "$C/moon/install.log"; rm -rf "$tmp"; exit 1; }
      rm -f "$tmp/install.sh"
      mv "$tmp" "$dir"
      echo "beta: MoonBit installed in $(secs $t0) s"
    fi
    ln -sfn "$dir" "$C/tools/moon.new" && mv -fh "$C/tools/moon.new" "$C/tools/moon"
    ls -dt "$C"/moon/*/ | tail -n +3 | xargs rm -rf
  fi
}

tools() {
  local t0=$(now)
  moon_tools
  setenv MBUI_TOOLS "$C/tools"
  local mbui
  mbui=$(sh "$A/scripts/mbui.sh")
  (cd "$REPO/client/core-ts" && pnpm install --frozen-lockfile --prefer-offline 2>&1 | tail -1)
  summary "- MoonBit $("$C/tools/moon/bin/moon" version | head -1); mbui $(git -C "$A" log -1 --format=%h -- mbui); tools in $(secs $t0) s"
}

# apps/mbui into WORK as git has it (a file gone goes there too, mbui's as well), by content: a file that did not change
# keeps its time, and moon sees it as it was; the build's outputs (what git ignores) stay.
copy() {
  [ "$WORK" != "$A" ] || return 0
  mkdir -p "$WORK"
  # (WORK's mbui was once a link of its own, to a checkout beside it: mbui is apps/mbui/mbui's files now)
  [ ! -L "$WORK/mbui" ] || rm "$WORK/mbui"
  (cd "$A" && git ls-files -z) | python3 -c '
import os, shutil, subprocess, sys
src, dst = sys.argv[1:3]
keep = {"out", "_build", ".mooncakes", "android/app/build", "android/app/src/main/jniLibs"}
# (the folders the builds write into, wherever they are: in mbui too)
outputs = {"_build", ".mooncakes", "target", "out", "dist"}
files = [f for f in sys.stdin.buffer.read().decode().split("\0") if f]
for f in files:
    a, b = os.path.join(src, f), os.path.join(dst, f)
    if os.path.islink(a) or not os.path.isfile(a):
        continue
    same = os.path.isfile(b) and os.path.getsize(a) == os.path.getsize(b) and open(a, "rb").read() == open(b, "rb").read()
    if not same:
        os.makedirs(os.path.dirname(b), exist_ok=True)
        shutil.copy2(a, b)
        os.utime(b)
    if os.access(a, os.X_OK) != os.access(b, os.X_OK):
        os.chmod(b, os.stat(a).st_mode)
tracked = set(files)
gone = []
for root, dirs, names in os.walk(dst):
    rel = os.path.relpath(root, dst)
    dirs[:] = [d for d in dirs if d not in outputs and os.path.normpath(os.path.join(rel, d)) not in keep]
    for n in names:
        r = os.path.normpath(os.path.join(rel, n))
        if r not in tracked and r not in keep:
            gone.append(r)
# (what git ignores is an output, kept: a file it would track is one gone from the checkout)
ignored = set(subprocess.run(["git", "-C", src, "check-ignore", "--no-index", "-z", "--stdin"], input="\0".join(gone).encode(),
    capture_output=True).stdout.decode().split("\0")) if gone else set()
for r in gone:
    if r not in ignored:
        os.remove(os.path.join(dst, r))
' "$A" "$WORK"
}

# feed PART N NAME FILE [SIGNED]: $RELEASE_DIR/PART/PART/mbui/latest.json (still.fail's AppRelease) for FILE, put as
# NAME; news: what came since the build the feed names now (versionCode n is main's nth commit), of what the app is made
# of; SIGNED: FILE's .sig, carried as `signed` (the Windows app's: the core offers it only as its signed words say it)
feed() {
  local part=$1 n=$2 name=$3 file=$4 signed=${5:-} prev_sha
  prev_sha=$(released "$part")
  mkdir -p "$RELEASE_DIR/$part/$part/mbui"
  git -C "$REPO" log --format=%s ${prev_sha:+$prev_sha..}HEAD -n 30 -- "${APP_SRC[@]}" \
    | python3 -c '
import json, sys
n, name, sha, size, out, signed = sys.argv[1:7]
news = [l.strip() for l in sys.stdin if l.strip()]
feed = {"versionCode": int(n), "versionName": "0.1." + n, "file": name, "sha256": sha, "size": int(size), "news": news}
if signed: feed["signed"] = json.load(open(signed))
json.dump(feed, open(out, "w"), ensure_ascii=False)' "$n" "$name" "$(shasum -a 256 "$file" | cut -d' ' -f1)" "$(wc -c < "$file" | tr -d ' ')" \
      "$RELEASE_DIR/$part/$part/mbui/latest.json" "$signed"
}

build() {
  local t0=$(now) n apk name sum size badging cert prev prev_sha
  # (MBUI_VARIANT=stable or beta: still.fail's Android app's own, fail.still.android(.beta), for scripts/release.sh, which
  # puts it on that app's feed; the APK alone, in $RELEASE_DIR/android/app-<variant>.apk)
  local variant=${MBUI_VARIANT:-release} id=fail.still.mbui
  case $variant in stable) id=fail.still.android ;; beta) id=fail.still.android.beta ;; esac
  n=$(build_number)
  copy
  rm -rf "$RELEASE_DIR/android" && mkdir -p "$RELEASE_DIR/android/android/mbui"
  # every still.fail Android release's key (the debug keystore $ANDROID_USER_HOME holds, as the Android Gradle plugin's
  # signingConfigs.debug had it: mbui's scripts/apk signs with it)
  if [ -n "${ANDROID_DEBUG_KEYSTORE_B64:-}" ]; then
    export ANDROID_USER_HOME=$(mktemp -d "${RUNNER_TEMP:-/tmp}/mbui-key.XXXXXX")
    printf '%s' "$ANDROID_DEBUG_KEYSTORE_B64" | base64 -d > "$ANDROID_USER_HOME/debug.keystore"
  fi
  # PostHog's key the app reports its crashes with (android/apk.json's strings, Crashes.java), as still.fail's Android release
  # has it (.github/release.sh): the file STILLFAIL_POSTHOG names, written from POSTHOG_JSON, removed after
  local posthog=
  if [ -n "${POSTHOG_JSON:-}" ]; then
    posthog=$(mktemp -d "${RUNNER_TEMP:-/tmp}/mbui-posthog.XXXXXX")
    (umask 077 && printf '%s' "$POSTHOG_JSON" > "$posthog/posthog.json")
    export STILLFAIL_POSTHOG="$posthog/posthog.json"
  fi
  local r=0
  env APP=stillfail VARIANT=$variant HBC_CACHE="${HBC_CACHE:-$C/hbc}" EMBER="$REPO" ORG_GRADLE_PROJECT_stillfailBuild=$n \
    bash "$WORK/scripts/android.sh" build 2>&1 | tee "$C/build.log" || r=$?
  [ -z "${ANDROID_DEBUG_KEYSTORE_B64:-}" ] || rm -rf "$ANDROID_USER_HOME"
  [ -z "$posthog" ] || rm -rf "$posthog"
  [ $r = 0 ] || exit $r
  apk=$WORK/android/app/build/outputs/apk/$variant/app-$variant.apk
  badging=$("$BT/aapt2" dump badging "$apk" | sed -n '1p')
  echo "$badging" | grep -q "name='$id' versionCode='$n' " || { echo "beta: not this build's APK: $badging" >&2; exit 1; }
  cert=$("$BT/apksigner" verify --print-certs "$apk" | sed -n '/certificate SHA-256 digest/{s/.*: //;p;}' | sed -n '1p')
  if [ "$variant" != release ]; then
    cp "$apk" "$RELEASE_DIR/android/app-$variant.apk"
    summary "- $id 0.1.$n: $(wc -c < "$apk" | tr -d ' ') bytes, signed by $cert; built in $(secs $t0) s"
    return 0
  fi
  name=android/stillfail-mbui-$n.apk
  cp "$apk" "$RELEASE_DIR/android/$name"
  sum=$(shasum -a 256 "$apk" | cut -d' ' -f1)
  size=$(wc -c < "$apk" | tr -d ' ')
  feed android "$n" "$name" "$apk"
  summary "- APK 0.1.$n: $size bytes, SHA-256 $sum, signed by $cert"
  summary "- $(grep '^android.sh: APP=' "$C/build.log" | sed 's/^android.sh: //'); $(grep '^core.hbc ' "$C/build.log" | head -1); build in $(secs $t0) s"
}

# The macOS app, built in WORK (warm as the APK's: moon's outputs, the compiler's; the core's shell is
# still.fail's natives, scripts/core.sh apple), signed under .github/mac_signing.py (still.fail's identity, its signing
# lock held for the signing only; a caller holding it already, .github/release-desktop.py, signs in its keychain:
# MAC_SIGN_IDENTITY set). MBUI_VARIANT=stable or beta: still.fail's Mac app itself, in the Electron app's place
# (mac-app.sh's variants: fail.still.desktop(.beta)), for scripts/release.sh, which puts it on that app's feeds: the
# signed app's zip alone, in $RELEASE_DIR/mac/app-<variant>.zip.
mac() {
  local t0=$(now) n zip name tb variant=${MBUI_VARIANT:-mbui} sign
  n=$(build_number)
  copy
  rm -rf "$RELEASE_DIR/mac" && mkdir -p "$RELEASE_DIR/mac/mac"
  env MBUI_BUILD=$n EMBER="$REPO" bash "$WORK/scripts/mac-app.sh" build 2>&1 \
    | tee "$C/mac-build.log"
  tb=$(secs $t0)
  sign=(python3 "$REPO/.github/mac_signing.py" run --)
  [ -z "${MAC_SIGN_IDENTITY:-}" ] || sign=()
  MBUI_BUILD=$n EMBER="$REPO" "${sign[@]}" bash "$WORK/scripts/mac-app.sh" sign 2>&1 | tee "$C/mac-sign.log"
  case $variant in
    stable) zip=$WORK/out/mac/stillfail-$n-arm64-mac.zip ;;
    beta) zip=$WORK/out/mac/stillfail-beta-$n-arm64-mac.zip ;;
    *) zip=$WORK/out/mac/stillfail-mbui-$n-arm64-mac.zip ;;
  esac
  [ -f "$zip" ] || { echo "beta: no zip of the app" >&2; exit 1; }
  # (UNSIGNED=1, as scripts/release.sh's: trying it out, signed ad hoc; never put)
  grep -q '^codesign: Authority=' "$C/mac-sign.log" || [ -n "${UNSIGNED:-}" ] || { echo "beta: the app is not signed with an identity" >&2; exit 1; }
  if [ "$variant" != mbui ]; then
    cp "$zip" "$RELEASE_DIR/mac/app-$variant.zip"
    summary "- macOS app ($variant) 0.1.$n: $(wc -c < "$zip" | tr -d ' ') bytes, $(grep '^codesign: Authority=' "$C/mac-sign.log" | head -1 | sed 's/^codesign: //'); built in $tb s, signed and zipped in $(secs $t0) s"
    return 0
  fi
  name=mac/stillfail-mbui-$n-arm64-mac.zip
  cp "$zip" "$RELEASE_DIR/mac/$name"
  feed mac "$n" "$name" "$zip"
  summary "- macOS app 0.1.$n: $(wc -c < "$zip" | tr -d ' ') bytes, $(grep '^codesign: Authority=' "$C/mac-sign.log" | head -1 | sed 's/^codesign: //'); built in $tb s, signed and zipped in $(secs $t0) s"
  summary "- $(grep '^mac-app.sh: .*\.app' "$C/mac-build.log" | sed 's/^mac-app.sh: //')"
}

# The Windows app's installer as win.sh setup made it (windows/setup.c: the program, the engine's and the shell's DLLs
# and core.hbc packed after it, put into %LOCALAPPDATA%\Programs\stillfail-mbui), signed (RELEASE_SIGNING_KEY: its
# .sig, which the feed carries; the app updates itself to it as still.fail's desktop app did)
win() {
  local t0=$(now) n setup exe name
  n=$(build_number)
  setup=$A/out/setup/stillfail-setup-0.1.$n.exe
  [ -f "$setup" ] || { echo "beta: no $setup (win.sh setup)" >&2; exit 1; }
  rm -rf "$RELEASE_DIR/win" "$C/win-sig" && mkdir -p "$RELEASE_DIR/win/win" "$C/win-sig"
  name=win/stillfail-mbui-$n-x64-win.exe
  exe=$C/win-sig/$(basename "$name")
  cp "$setup" "$exe"
  node "$REPO/scripts/release-sign.ts" file "$exe" --kind stillfail-desktop-win --build "$n"
  cp "$exe" "$RELEASE_DIR/win/$name"
  feed win "$n" "$name" "$exe" "$exe.sig"
  summary "- Windows app 0.1.$n: its installer $(wc -c < "$exe" | tr -d ' ') bytes, signed in $(secs $t0) s"
}

# The Linux app as linux.sh built and put it (the program, the engine's and the shell's libraries, core.hbc), with its
# icon (linux/AppIcon-<mac-icon.swift's hash>.png: drawn on a Mac) and the script that installs it for the person who
# unpacks it (linux/install.sh), in one folder, still.fail-mbui/, tarred
linux() {
  local t0=$(now) n dir arch name tgz stage icon
  n=$(build_number)
  local MBUI_DIR
  MBUI_DIR=$(sh "$A/scripts/mbui.sh")
  . "$MBUI_DIR/scripts/env.sh"
  dir=$MBUI_DIR/out/linux/app/$(cd "$MBUI_DIR/out/linux/app" && pkg_build stillfail native release)
  [ -f "$dir/stillfail.exe" ] || { echo "beta: no stillfail.exe in $dir (linux.sh build, put)" >&2; exit 1; }
  icon=$A/linux/AppIcon-$(sha256sum "$A/scripts/mac-icon.swift" | cut -c1-12).png
  [ -f "$icon" ] || { echo "beta: no $icon (scripts/mac-icon.swift changed: swift scripts/mac-icon.swift --png $icon, on a Mac)" >&2; exit 1; }
  arch=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
  # (each machine's its own feed, so an app is offered only its own machine's builds: x64's the part linux, as it was)
  local part=linux
  [ "$arch" = x64 ] || part=linux-$arch
  stage=$C/linux-stage/still.fail-mbui
  rm -rf "$C/linux-stage" && mkdir -p "$stage"
  cp "$dir/stillfail.exe" "$stage/stillfail"
  cp "$dir"/lib*.so* "$dir/core.hbc" "$A/linux/install.sh" "$stage/"
  cp "$icon" "$stage/icon.png"
  echo "0.1.$n" > "$stage/VERSION"
  rm -rf "$RELEASE_DIR/$part" && mkdir -p "$RELEASE_DIR/$part/linux"
  name=linux/stillfail-mbui-$n-$arch-linux.tar.gz
  tgz=$RELEASE_DIR/$part/$name
  tar -C "$C/linux-stage" -czf "$tgz" still.fail-mbui
  feed "$part" "$n" "$name" "$tgz"
  summary "- Linux app 0.1.$n ($arch): $(wc -c < "$tgz" | tr -d ' ') bytes, tarred in $(secs $t0) s"
}

# fetched back and the same bytes as made: from R2 itself through Cloudflare's API when there is a token (R2 reads what
# was written, at once: no waiting for it to show), else from the public URL; a request the line from mini1 drops
# tried again by curl itself (--retry: its network errors, not a wait for the object)
# (into a file, and its bytes read only once curl said it got them all: piped to shasum, a fetch cut off by --max-time
# was hashed as it stood, and the retries' bytes after it, linux x64's 36 MB taking 74 s from GitHub's runner on main
# 57dd8b8e, said "not as made" of what was put whole. A fetch that stalls gives up by its speed, not a fixed time)
# (and a connection not made in 15 s given up and tried again, as scripts/release-put.sh's: curl's own wait for one is
# 300 s, and the Windows installer's check said nothing for the 150 s its step waits after the put, main d2791c4f,
# 41379568722, 2026-11-02)
check_put() {
  local name=$1 file=$2 want got= account back limits="--connect-timeout 15 --speed-limit 1024 --speed-time 30"
  want=$(shasum -a 256 "$file" | cut -d' ' -f1)
  back=$(mktemp)
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    account=${CLOUDFLARE_ACCOUNT_ID:-$(curl -fsS $limits --retry 4 --retry-all-errors -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" https://api.cloudflare.com/client/v4/accounts | grep -o '"id":"[0-9a-f]\{32\}"' | head -1 | cut -d'"' -f4)}
    curl -fsS $limits --retry 4 --retry-all-errors -o "$back" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$account/r2/buckets/stillfail-releases/objects/$name" 2>/dev/null \
      && got=$(shasum -a 256 "$back" | cut -d' ' -f1)
  else
    curl -fsS $limits --retry 4 --retry-all-errors -o "$back" "$ORIGIN/releases/$name" 2>/dev/null \
      && got=$(shasum -a 256 "$back" | cut -d' ' -f1)
  fi
  rm -f "$back"
  [ "$got" = "$want" ] && return 0
  echo "beta: $name is not as made in the bucket (sha256 ${got:-not fetched}, made $want)" >&2
  return 1
}

publish() {
  local part=${1:-android} t0=$(now) name n dir
  dir=$RELEASE_DIR/$part
  n=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["versionCode"])' "$dir/$part/mbui/latest.json")
  name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["file"])' "$dir/$part/mbui/latest.json")
  cp "$dir/$name" "$C/last-$part"
  # (wrangler's, when Cloudflare's API cannot be used: without the token)
  [ -n "${CLOUDFLARE_API_TOKEN:-}" ] || (cd "$REPO/cloud" && pnpm install --frozen-lockfile --prefer-offline > /dev/null)
  sh "$REPO/scripts/release-put.sh" --files "$dir"
  local tp=$(secs $t0)
  check_put "$name" "$C/last-$part" || { echo "beta: $name did not come back as made: the feed stays as it was" >&2; exit 1; }
  local tc=$(secs $t0)
  sh "$REPO/scripts/release-put.sh" --feeds "$dir"
  if [ "$part" = mac ]; then
    local built="$WORK/out/mac/stillfail-mbui-$n-arm64-mac.zip"
    # check_put just verified last-mac against R2; only remove the matching warm build copy.
    if [ -f "$built" ] && cmp -s "$built" "$C/last-mac"; then rm -f "$built"; fi
  fi
  summary "- put $name (${tp} s), checked (${tc} s), the feed: $ORIGIN/releases/$part/mbui/latest.json, $ORIGIN/releases/latest/$part-mbui ($(secs $t0) s)"
}

case "${1:-}" in
  tools) tools ;;
  build) build ;;
  mac) mac ;;
  win) win ;;
  linux) linux ;;
  changed) changed "${2:-android}" ;;
  publish) publish "${2:-android}" ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac

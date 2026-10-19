#!/bin/bash
# still.fail mbui's beta (fail.still.mbui, "still.fail mbui": the release build of apps/mbui's Android app), built,
# signed and put in the releases bucket as .github/workflows/mbui.yml does on mini1:
#   apps/mbui/scripts/beta.sh tools      MoonBit, its latest release (installed again only when cli.moonbitlang.com
#                                        has a newer one: its ETag), mbui at mbui.rev (scripts/mbui.sh), the core's packages
#   apps/mbui/scripts/beta.sh build      the APK (scripts/android.sh, VARIANT=release): versionCode the build (git
#                                        rev-list --count HEAD), signed with ANDROID_DEBUG_KEYSTORE_B64 (every still.fail
#                                        Android release's key), into $RELEASE_DIR as android/stillfail-mbui-<n>.apk
#                                        and android/mbui/latest.json (still.fail's AppRelease, news: the commits since
#                                        the build the feed names now, of what the app is built from)
#   apps/mbui/scripts/beta.sh mac        the macOS app (scripts/mac-app.sh: still.fail mbui.app, fail.still.mbui),
#                                        signed with still.fail's identity (scripts/mac-sign.py), zipped, into
#                                        $RELEASE_DIR as mac/stillfail-mbui-<n>-arm64-mac.zip and mac/mbui/latest.json
#   apps/mbui/scripts/beta.sh publish android|mac
#                                        what `build` or `mac` made put (scripts/release-put.sh), fetched back from where
#                                        it is served and checked (size, SHA-256), then its feed: https://app.still.fail/
#                                        releases/latest/android-mbui (mac-mbui) is the newest from then on
# Warm between runs (WORK, MBUI_CACHE): the build runs in a copy of apps/mbui kept outside the job's checkout (which the
# other jobs' clean takes), so moonc's and the compiler's outputs, the link and Gradle's build stay; core.hbc is kept
# by its inputs (HBC_CACHE); Gradle's daemon lives on between builds for its idle timeout (android/gradle.properties).
set -eo pipefail
A=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$A/../.." && pwd)
C=${MBUI_CACHE:-$HOME/stillfail-ci/mbui}
WORK=${WORK:-$C/work}
RELEASE_DIR=${RELEASE_DIR:-$C/release}
ORIGIN=${STILLFAIL_ORIGIN:-https://app.still.fail}
mkdir -p "$C"
now() { python3 -c 'import time;print(time.time())'; }
secs() { python3 -c "print(f'{$(now)-$1:.1f}')"; }
summary() { [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "$*" >> "$GITHUB_STEP_SUMMARY"; echo "$*"; }
setenv() { export "$1=$2"; [ -z "${GITHUB_ENV:-}" ] || echo "$1=$2" >> "$GITHUB_ENV"; }
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
BT=$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)
build_number() { git -C "$REPO" rev-list --count HEAD; }

# The latest MoonBit, in $C/moon/<its ETag's hash>, MBUI_TOOLS=$C/tools (tools/moon: that one) for mbui's env.sh: the
# ETags of the release's two downloads (the binaries and the core) asked each run (a HEAD each), the install only when
# they changed; the one before is kept.
moon_tools() {
  local base=https://cli.moonbitlang.com tag dir
  mkdir -p "$C/moon" "$C/tools"
  tag=$( { curl -sfI --max-time 5 $base/binaries/latest/moonbit-darwin-aarch64.tar.gz; curl -sfI --max-time 5 $base/cores/core-latest.tar.gz; } \
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
  summary "- MoonBit $("$C/tools/moon/bin/moon" version | head -1); mbui $(tr -d '\n' < "$A/mbui.rev" | cut -c1-9); tools in $(secs $t0) s"
}

# apps/mbui into WORK as git has it (a file gone goes there too), by content: a file that did not change keeps its time,
# and moon and Gradle see it as it was; the build's outputs (ignored by git) stay. Its own link to mbui made there.
copy() {
  mkdir -p "$WORK"
  (cd "$A" && git ls-files -z) | python3 -c '
import os, shutil, sys
src, dst = sys.argv[1:3]
keep = {"out", "_build", "mbui", ".mooncakes", "android/app/build", "android/.gradle", "android/app/src/main/jniLibs"}
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
for root, dirs, names in os.walk(dst):
    rel = os.path.relpath(root, dst)
    dirs[:] = [d for d in dirs if os.path.normpath(os.path.join(rel, d)) not in keep]
    for n in names:
        r = os.path.normpath(os.path.join(rel, n))
        if r not in tracked and r not in keep:
            os.remove(os.path.join(root, n))
' "$A" "$WORK"
}

# feed PART N NAME FILE: $RELEASE_DIR/PART/PART/mbui/latest.json (still.fail's AppRelease) for FILE, put as NAME; news:
# what came since the build the feed names now (versionCode n is main's nth commit), of what the app is made of
feed() {
  local part=$1 n=$2 name=$3 file=$4 prev prev_sha
  prev=$(curl -fsS --max-time 10 "$ORIGIN/releases/$part/mbui/latest.json" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["versionCode"])' 2>/dev/null || true)
  prev_sha=
  [ -z "$prev" ] || prev_sha=$(git -C "$REPO" rev-list --reverse HEAD | sed -n "${prev}p")
  mkdir -p "$RELEASE_DIR/$part/$part/mbui"
  git -C "$REPO" log --format=%s ${prev_sha:+$prev_sha..}HEAD -n 30 -- apps/mbui client media \
    | python3 -c '
import json, sys
n, name, sha, size, out = sys.argv[1:6]
news = [l.strip() for l in sys.stdin if l.strip()]
json.dump({"versionCode": int(n), "versionName": "0.1." + n, "file": name, "sha256": sha, "size": int(size), "news": news},
          open(out, "w"), ensure_ascii=False)' "$n" "$name" "$(shasum -a 256 "$file" | cut -d' ' -f1)" "$(wc -c < "$file" | tr -d ' ')" \
      "$RELEASE_DIR/$part/$part/mbui/latest.json"
}

build() {
  local t0=$(now) n apk name sum size badging cert prev prev_sha
  n=$(build_number)
  copy
  rm -rf "$RELEASE_DIR/android" && mkdir -p "$RELEASE_DIR/android/android/mbui"
  # every still.fail Android release's key (the Android Gradle plugin's signingConfigs.debug: $ANDROID_USER_HOME's)
  if [ -n "${ANDROID_DEBUG_KEYSTORE_B64:-}" ]; then
    export ANDROID_USER_HOME=$(mktemp -d "${RUNNER_TEMP:-/tmp}/mbui-key.XXXXXX")
    printf '%s' "$ANDROID_DEBUG_KEYSTORE_B64" | base64 -d > "$ANDROID_USER_HOME/debug.keystore"
  fi
  local r=0
  # MBUI_KEEP_DAEMON=1 (main's beta): the run's process tracking off for Gradle's daemon, which lives on to the next
  # build for its idle timeout (~2 GB resident); a branch's build leaves it to the runner, which ends it with the job
  local keep=
  [ "${MBUI_KEEP_DAEMON:-}" != 1 ] || keep="-u RUNNER_TRACKING_ID"
  env $keep APP=stillfail VARIANT=release HBC_CACHE="$C/hbc" EMBER="$REPO" ORG_GRADLE_PROJECT_stillfailBuild=$n \
    bash "$WORK/scripts/android.sh" build 2>&1 | tee "$C/build.log" || r=$?
  [ -z "${ANDROID_DEBUG_KEYSTORE_B64:-}" ] || rm -rf "$ANDROID_USER_HOME"
  [ $r = 0 ] || exit $r
  apk=$WORK/android/app/build/outputs/apk/release/app-release.apk
  badging=$("$BT/aapt2" dump badging "$apk" | head -1)
  echo "$badging" | grep -q "name='fail.still.mbui' versionCode='$n' " || { echo "beta: not this build's APK: $badging" >&2; exit 1; }
  cert=$("$BT/apksigner" verify --print-certs "$apk" | grep 'certificate SHA-256 digest' | head -1 | sed 's/.*: //')
  name=android/stillfail-mbui-$n.apk
  cp "$apk" "$RELEASE_DIR/android/$name"
  sum=$(shasum -a 256 "$apk" | cut -d' ' -f1)
  size=$(wc -c < "$apk" | tr -d ' ')
  feed android "$n" "$name" "$apk"
  summary "- APK 0.1.$n: $size bytes, SHA-256 $sum, signed by $cert"
  summary "- $(grep '^android.sh: APP=' "$C/build.log" | sed 's/^android.sh: //'); $(grep '^core.hbc ' "$C/build.log" | head -1); build in $(secs $t0) s"
  # what this app's Gradle daemon (android/gradle.properties: -Xmx2048m, 30 minutes idle) holds of the machine's memory
  summary "- its Gradle daemon: $(ps -eo rss,args | grep '[G]radleDaemon' | grep -e '-Xmx2048m' | awk '{s += $1} END {printf "%d MB resident", s / 1024}')"
}

# The macOS app, built in WORK (warm as the APK's: moon's outputs, the compiler's, the Rust shell's target kept in
# $C/cargo-target), signed under scripts/mac-sign.py (still.fail's identity, its signing lock held for the signing only).
mac() {
  local t0=$(now) n zip name tb
  n=$(build_number)
  copy
  rm -rf "$RELEASE_DIR/mac" && mkdir -p "$RELEASE_DIR/mac/mac"
  # the core's Rust shell, linked in: cargo decides what changed (its target kept; through the job's sccache)
  CARGO_TARGET_DIR=$C/cargo-target MBUI_CORE_FRESH=1 MBUI_BUILD=$n EMBER="$REPO" bash "$WORK/scripts/mac-app.sh" build 2>&1 \
    | tee "$C/mac-build.log"
  tb=$(secs $t0)
  MBUI_BUILD=$n EMBER="$REPO" python3 "$A/scripts/mac-sign.py" -- bash "$WORK/scripts/mac-app.sh" sign 2>&1 | tee "$C/mac-sign.log"
  zip=$WORK/out/mac/stillfail-mbui-$n-arm64-mac.zip
  [ -f "$zip" ] || { echo "beta: no zip of the app" >&2; exit 1; }
  grep -q '^codesign: Authority=' "$C/mac-sign.log" || { echo "beta: the app is not signed with an identity" >&2; exit 1; }
  name=mac/stillfail-mbui-$n-arm64-mac.zip
  cp "$zip" "$RELEASE_DIR/mac/$name"
  feed mac "$n" "$name" "$zip"
  summary "- macOS app 0.1.$n: $(wc -c < "$zip" | tr -d ' ') bytes, $(grep '^codesign: Authority=' "$C/mac-sign.log" | head -1 | sed 's/^codesign: //'); built in $tb s, signed and zipped in $(secs $t0) s"
  summary "- $(grep '^mac-app.sh: .*\.app' "$C/mac-build.log" | sed 's/^mac-app.sh: //')"
}

# fetched back from where it is served (the public URL; Cloudflare's API while the cloud does not serve it yet), and
# the same bytes as made: tried a few times (R2 and the line from mini1 fail now and then)
check_put() {
  local name=$1 file=$2 want got tries
  want=$(shasum -a 256 "$file" | cut -d' ' -f1)
  for tries in 1 2 3 4 5; do
    got=$(curl -fsS --max-time 60 "$ORIGIN/releases/$name" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
    if [ "$got" != "$want" ] && [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
      local account=${CLOUDFLARE_ACCOUNT_ID:-$(curl -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" https://api.cloudflare.com/client/v4/accounts | grep -o '"id":"[0-9a-f]\{32\}"' | head -1 | cut -d'"' -f4)}
      got=$(curl -fsS --max-time 60 -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$account/r2/buckets/stillfail-releases/objects/$name" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
    fi
    [ "$got" = "$want" ] && return 0
    echo "beta: $name is not there as made yet (try $tries)" >&2
    sleep 5
  done
  return 1
}

publish() {
  local part=${1:-android} t0=$(now) name n dir
  dir=$RELEASE_DIR/$part
  n=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["versionCode"])' "$dir/$part/mbui/latest.json")
  name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["file"])' "$dir/$part/mbui/latest.json")
  cp "$dir/$name" "$C/last-$part"
  (cd "$REPO/cloud" && pnpm install --frozen-lockfile --prefer-offline > /dev/null)
  sh "$REPO/scripts/release-put.sh" --files "$dir"
  local tp=$(secs $t0)
  check_put "$name" "$C/last-$part" || { echo "beta: $name did not come back as made: the feed stays as it was" >&2; exit 1; }
  local tc=$(secs $t0)
  sh "$REPO/scripts/release-put.sh" --feeds "$dir"
  summary "- put $name (${tp} s), checked (${tc} s), the feed: $ORIGIN/releases/$part/mbui/latest.json, $ORIGIN/releases/latest/$part-mbui ($(secs $t0) s)"
}

case "${1:-}" in
  tools) tools ;;
  build) build ;;
  mac) mac ;;
  publish) publish "${2:-android}" ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac

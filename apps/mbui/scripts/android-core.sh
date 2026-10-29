# Sourced by scripts/android.sh for an app with the still.fail core in it (coredemo, stillfail; MBUI_ANDROID_HOOK):
# the core on the app's engine (src/sfcore/android_engine.c, which includes android_core.c; its C API apps/mbui/engine's
# engine.h). Into out/android/apk, which Gradle packs: the prebuilt engine and shell (EMBER: still.fail's checkout, as
# scripts/core.sh has it; `node scripts/native.ts path engine|shell android-arm64` there, prebuilt or built by it),
# libhermes.so from React Native's hermes-android (the Hermes the engine is built against: Gradle's cache, else Maven
# Central), and the core as Hermes bytecode (scripts/core.sh hermes; ENTRY picks the core's entry, by default the one
# with the media module).
#   HBC_CACHE (a directory: CI's): core.hbc kept there by what it is made of (scripts/core.sh hermes).
#   CORE_SCRIPT: a script in the core's place (listen-test).
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMBER=${EMBER:-$(cd "$TOOLS/.." 2>/dev/null && pwd)/ember-src}
APP_KIND=core
# mbui/core's queue, the keyboard's files (src/pinyin) and the app's engine (src/<app>/android_engine.c, which includes
# src/sfcore/android_engine.c)
APP_EXTRA="--extra=src/core/core_native.c --extra=src/pinyin/read_file.c --extra=src/$PKG/android_engine.c"
APP_LINK="-L$jni -lstillfail_hermes"
# (the engine's C API, engine.h)
CFLAGS="$CFLAGS -I$H/../engine"

# A .so of an AAR on Maven Central (GROUP/ARTIFACT VERSION FILE LIB SHA-256), fetched once and checked (mbui's
# scripts/apk fetch: kept in $APK_CACHE), into $jni.
aar_lib() {
  local aar
  aar=$("$MBUI_DIR/scripts/apk" fetch "$(echo ${1%/*} | tr . /)/${1#*/}/$2/$3" "$5") || exit 1
  unzip -o -q -j "$aar" jni/arm64-v8a/$4 -d $jni
}

# the .so files, which libmbui.so links against
app_libs() {
  local engine shell
  engine=$(cd "$EMBER" && node scripts/native.ts path engine android-arm64)
  shell=$(cd "$EMBER" && node scripts/native.ts path shell android-arm64)
  cp -p $engine/libstillfail_hermes.so $engine/libjsi.so $engine/libc++_shared.so $shell/libstillfail_shell.so $jni/
  # Hermes as React Native 0.81.4 has it, and the fbjni it needs (libc++_shared.so is the engine's, the NDK's, which
  # fbjni's AAR carries an older copy of)
  aar_lib com.facebook.react/hermes-android 0.81.4 hermes-android-0.81.4-release.aar libhermes.so \
    c883c5e24b1361d30a0c2f21cc40be41291648f19598f70f2a018e910d96b041
  aar_lib com.facebook.fbjni/fbjni 0.7.0 fbjni-0.7.0.aar libfbjni.so \
    7e319ae110ac5e5ef18904170aea5c3e753e915d196699d7fd39d36c8e1dfe36
  echo "core parts: $(cd $jni && for f in *.so; do printf '%s %s, ' $f $(size $f); done)"
}

# the core's bytecode, which only Gradle needs (HBC_CACHE: scripts/core.sh hermes keeps it there by its inputs)
app_assets() {
  if [ -n "${CORE_SCRIPT:-}" ]; then
    # a script in the core's place (listen-test: core/listen-test.js)
    EMBER=$EMBER "$H/core.sh" hermes-script "$CORE_SCRIPT" || { echo "android.sh: $CORE_SCRIPT did not compile" >&2; exit 1; }
  else
    EMBER=$EMBER ENTRY=${ENTRY:-$PWD/core/media-hermes.ts} "$H/core.sh" hermes \
      || { echo "android.sh: no core for the app (scripts/core.sh hermes failed)" >&2; exit 1; }  # with media, as on macOS
  fi
  cp -p out/core/core.hbc $apk/assets/
  echo "core.hbc $(size $apk/assets/core.hbc)"
  # the keyboard's words (src/pinyin, mbui's Keyboard.java copies assets/keyboard to where the keyboard reads them)
  mkdir -p $apk/assets/keyboard
  cp -p src/pinyin/words.txt $apk/assets/keyboard/
}

app_cmd() {
  case "$1" in
    listen-test) listen_test ;;
    *) echo "android.sh: no command $1" >&2; return 1 ;;
  esac
}

listen_test() {
    # listen.* (CoreHost on Loopback) with core/listen-test.js in the core's place, as scripts/core.sh listen on macOS:
    # it opens a listener on a port of the system's choosing (a second one there, and one off loopback, refused), this
    # sends it a POST from the emulator's shell, the script answers it, then closes it with a listen.next waiting.
    # Builds APP=coredemo with that script (build again without CORE_SCRIPT for the core).
    APP=coredemo CORE_SCRIPT=$PWD/core/listen-test.js "$0" build
    $ADB -s $SERIAL logcat -c
    APP=coredemo ENV="MB_CORE_TRACE=1" "$0" run
    # (the script's word of its listener, as logcat has it: scripts/waitfor.mjs)
    port=$(node "$H/waitfor.mjs" --deadline 60 --what "the script's listener" --run "$ADB -s $SERIAL logcat -s mbui:I" \
      --line 'core says \{"opened":[0-9]+' | sed -n 's/.*core says {"opened":\([0-9]*\).*/\1/p')
    [ -n "$port" ] || { echo "FAIL the script opened no listener"; "$0" log 60; exit 1; }
    echo "listening on 127.0.0.1:$port"
    # the POST from here through adb's forward, by curl, which reads the answer to its end (the Host the device's)
    hp=$($ADB -s $SERIAL forward tcp:0 tcp:$port)
    answer=$(curl -sS -i --max-time 30 -H "Host: 127.0.0.1:$port" -H 'Content-Type: application/x-www-form-urlencoded' \
      --data-raw 'state=s&x=1' "http://127.0.0.1:$hp/oauth/callback?code=c%20d&state=s")
    $ADB -s $SERIAL forward --remove tcp:$hp
    # (its last word: the listener closed with a listen.next waiting, and one after)
    node "$H/waitfor.mjs" --deadline 60 --what "the listener's end" --run "$ADB -s $SERIAL logcat -s mbui:I" \
      --line '"ended":\{"end":true\}' > /dev/null
    log=$($ADB -s $SERIAL logcat -d -s mbui:I)
    code=0
    ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; code=1; fi; }
    ok "a second listener on that port refused" 'echo "$log" | grep -q "\"taken\":\"[^\"]*in use"'
    ok "a listener off loopback refused" 'echo "$log" | grep -q "\"outside\":\"[^\"]*not a loopback address"'
    ok "the POST came whole (method, path with its query, Host, body)" 'echo "$log" | grep -q "\"method\":\"POST\",\"path\":\"/oauth/callback?code=c%20d&state=s\".*\"Host\",\"127.0.0.1:$port\".*\"body\":\"state=s&x=1\""'
    ok "the script's answer came back (status, its headers, its body)" 'echo "$answer" | grep -q "^HTTP/1.1 200 OK" && echo "$answer" | grep -q "^X-Test: yes" && echo "$answer" | grep -q "answered /oauth/callback?code=c%20d&state=s"'
    ok "its own Content-Length not passed on (the answer's length is the body's)" '! echo "$answer" | grep -q "^Content-Length: 1\r*$"'
    ok "a listen.next waiting as it closed, and one after, said {end}" 'echo "$log" | grep -q "\"ended\":{\"end\":true},\"after\":{\"end\":true}"'
    ok "it no longer listens" '! $ADB -s $SERIAL shell cat /proc/net/tcp | grep -qi ":$(printf %04X $port) 00000000:0000 0A"'
    echo "$answer" | tr -d '\r' | sed 's/^/  answer: /'
    echo "$log" | grep "core says\|core app call" | sed 's/^/  /' | tail -20
    return $code
}

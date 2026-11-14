# Sourced by mbui's scripts/ios.sh for an app with the still.fail core in it (coredemo, stillfail; MBUI_IOS_HOOK), in
# the module's directory: the core as on macOS (src/sfcore/apple_engine.m through the app's core_engine.m; the engine
# src/host/apple_core.mm as out/core/<target>/libmbui_core.a), built for the simulator (scripts/core.sh apple
# aarch64-apple-ios-sim, a device's aarch64-apple-ios: Hermes's xcframework, the engine, the shell's .a, core.hbc),
# and carried by the app: Frameworks/hermes.framework (React Native 0.81.4's, the simulator's or the device's slice)
# and core.hbc. MetricKit for the app's crash reports (src/host/apple_reports.m), and PostHog's project they go to in
# its Info.plist (StillfailPosthogHost, StillfailPosthogKey) from the file STILLFAIL_POSTHOG names ({host, key}:
#), as Android's apk.json strings: the TestFlight build's (scripts/testflight.sh, POSTHOG_JSON); a
# build without it sends nothing.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# (a device's app, mbui's MBUI_IOS_SDK=iphoneos: the device's target and Hermes's device slice)
if [ "${IOS_SDK:-iphonesimulator}" = iphoneos ]; then
  CORE_TARGET=aarch64-apple-ios
  HERMES_SLICE=out/core/hermes/Library/Frameworks/universal/hermes.xcframework/ios-arm64
else
  CORE_TARGET=aarch64-apple-ios-sim
  HERMES_SLICE=out/core/hermes/Library/Frameworks/universal/hermes.xcframework/ios-arm64_x86_64-simulator
fi
# mbui/core's queue and the app's engine (its core_engine.m, which includes
# src/sfcore/apple_engine.m)
APP_EXTRA="--extra=src/core/core_native.c --extra=src/$PKG/core_engine.m"
# the engine, the shell (and what it needs of the system: scripts/core.sh shell's native-static-libs for iOS), Hermes
APP_LINK="out/core/$CORE_TARGET/libmbui_core.a out/core/$CORE_TARGET/libstillfail_shell.a -F$HERMES_SLICE -framework hermes \
  -Wl,-rpath,@executable_path/Frameworks -lc++ -framework AuthenticationServices -framework Security -framework LocalAuthentication \
  -framework SystemConfiguration -framework Network -framework CoreFoundation -framework MetricKit -liconv -Wl,-dead_strip"

app_libs() {
  bash "$H/core.sh" apple $CORE_TARGET
}

app_bundle() {
  cp -p out/core/core.hbc $APPDIR/core.hbc
  mkdir -p $APPDIR/Frameworks
  rm -rf $APPDIR/Frameworks/hermes.framework
  cp -R $HERMES_SLICE/hermes.framework $APPDIR/Frameworks/
  # One monoid identity for TestFlight and App Store. iOS has no macOS LSEnvironment: the app reads these two signed
  # values before the core starts (src/sfcore/apple_engine.m), so sign-in and accounts go to monoid's cloud.
  case ${MBUI_IOS_PRODUCT:-stillfail} in
    stillfail) ;;
    monoid)
      for p in "$APPDIR/Info.plist" "$APPDIR/PlugIns/Share.appex/Info.plist"; do
        plutil -replace CFBundleName -string monoid "$p"
        plutil -replace CFBundleDisplayName -string monoid "$p"
      done
      plutil -replace MBUIShareTaken -string '已收下。打开 monoid，选要发到的对话。' "$APPDIR/PlugIns/Share.appex/Info.plist"
      plutil -replace MBUIEnvironment -json '{"MBUI_CLOUD":"https://app.monoid.build","MBUI_PRODUCT":"monoid"}' "$APPDIR/Info.plist"
      ;;
    *) echo 'ios-core: MBUI_IOS_PRODUCT must be stillfail or monoid' >&2; return 1 ;;
  esac
  if [ -n "${STILLFAIL_POSTHOG:-}" ]; then
    local host key
    host=$(plutil -extract host raw -o - "$STILLFAIL_POSTHOG") && key=$(plutil -extract key raw -o - "$STILLFAIL_POSTHOG") \
      && [ -n "$key" ] || { echo "ios-core: no PostHog key in $STILLFAIL_POSTHOG" >&2; return 1; }
    plutil -replace StillfailPosthogHost -string "$host" $APPDIR/Info.plist
    plutil -replace StillfailPosthogKey -string "$key" $APPDIR/Info.plist
    echo "PostHog's key: in the Info.plist (crash reports go)"
  fi
  echo "the core: core.hbc $(wc -c < $APPDIR/core.hbc | tr -d ' ') bytes, hermes.framework $(du -sh $APPDIR/Frameworks/hermes.framework | cut -f1)"
}

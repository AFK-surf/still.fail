# Sourced by mbui's scripts/ios.sh for an app with the still.fail core in it (coredemo, stillfail; MBUI_IOS_HOOK), in
# the module's directory: the core as on macOS (src/sfcore/apple_engine.m through the app's core_engine.m; the engine
# src/host/apple_core.mm as out/core/<target>/libmbui_core.a), built for the simulator (scripts/core.sh apple
# aarch64-apple-ios-sim, a device's aarch64-apple-ios: Hermes's xcframework, the engine, the shell's .a, core.hbc),
# and carried by the app: Frameworks/hermes.framework (React Native 0.81.4's, the simulator's or the device's slice)
# and core.hbc.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# (a device's app, mbui's MBUI_IOS_SDK=iphoneos: the device's target and Hermes's device slice)
if [ "${IOS_SDK:-iphonesimulator}" = iphoneos ]; then
  CORE_TARGET=aarch64-apple-ios
  HERMES_SLICE=out/core/hermes/Library/Frameworks/universal/hermes.xcframework/ios-arm64
else
  CORE_TARGET=aarch64-apple-ios-sim
  HERMES_SLICE=out/core/hermes/Library/Frameworks/universal/hermes.xcframework/ios-arm64_x86_64-simulator
fi
# mbui/core's queue and the app's engine (its core_engine.m, which includes src/sfcore/apple_engine.m)
APP_EXTRA="--extra=src/core/core_native.c --extra=src/$PKG/core_engine.m"
# the engine, the shell (and what it needs of the system: scripts/core.sh shell's native-static-libs for iOS), Hermes
APP_LINK="out/core/$CORE_TARGET/libmbui_core.a out/core/$CORE_TARGET/libstillfail_shell.a -F$HERMES_SLICE -framework hermes \
  -Wl,-rpath,@executable_path/Frameworks -lc++ -framework AuthenticationServices -framework Security \
  -framework SystemConfiguration -framework Network -framework CoreFoundation -liconv -Wl,-dead_strip"

app_libs() {
  bash "$H/core.sh" apple $CORE_TARGET
}

app_bundle() {
  cp -p out/core/core.hbc $APPDIR/core.hbc
  mkdir -p $APPDIR/Frameworks
  rm -rf $APPDIR/Frameworks/hermes.framework
  cp -R $HERMES_SLICE/hermes.framework $APPDIR/Frameworks/
  echo "the core: core.hbc $(wc -c < $APPDIR/core.hbc | tr -d ' ') bytes, hermes.framework $(du -sh $APPDIR/Frameworks/hermes.framework | cut -f1)"
}

#!/bin/bash
# The core for the RN app on Android: apps/android/core built as an AAR by apps/android/build.py (prebuilt shell and
# engine, the core as Hermes bytecode), put into modules/stillfail-core/android/repo as Maven artifact
# fail.still:core:0.1.0 with its dependencies (the core's POM).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/../.." && pwd)
export JAVA_HOME=${JAVA_HOME:-$HOME/.sdkman/candidates/java/17.0.18-tem}
[ -f "$root/apps/android/local.properties" ] || printf 'sdk.dir=%s\n' "${ANDROID_HOME:-$HOME/Library/Android/sdk}" > "$root/apps/android/local.properties"
python3 "$root/apps/android/build.py" --release --tasks :core:assembleRelease
out="$here/modules/stillfail-core/android/repo/fail/still/core/0.1.0"
mkdir -p "$out"
cp "$root/apps/android/core/build/outputs/aar/core-release.aar" "$out/core-0.1.0.aar"
versions="$root/apps/android/gradle/libs.versions.toml"
v() { sed -n "s/^$1 = \"\(.*\)\"/\1/p" "$versions"; }
cat > "$out/core-0.1.0.pom" <<POM
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>fail.still</groupId>
  <artifactId>core</artifactId>
  <version>0.1.0</version>
  <packaging>aar</packaging>
  <dependencies>
    <dependency><groupId>org.jetbrains.kotlinx</groupId><artifactId>kotlinx-coroutines-android</artifactId><version>$(v coroutines)</version></dependency>
    <dependency><groupId>org.jetbrains.kotlinx</groupId><artifactId>kotlinx-serialization-json</artifactId><version>$(v serialization)</version></dependency>
    <dependency><groupId>com.facebook.react</groupId><artifactId>hermes-android</artifactId><version>$(v hermes)</version></dependency>
  </dependencies>
</project>
POM
ls -la "$out"

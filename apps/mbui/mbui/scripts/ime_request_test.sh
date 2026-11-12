#!/bin/sh
# The Android host's IME request decisions, without Android or a device.
set -eu
cd "$(dirname "$0")/.."
OUT=${TMPDIR:-/tmp}/ime-request.$$
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' EXIT
javac -d "$OUT" android/app/src/main/java/dev/mbui/ImeRequest.java android/ime/ImeRequestTest.java
java -cp "$OUT" dev.mbui.ImeRequestTest

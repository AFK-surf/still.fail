#!/bin/bash
# Two independent pictures in one process, including after the first could not be written.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
APP=sffigurebatchcheck MODE=release bash scripts/mac.sh build
mkdir -p out
take=$(mktemp -d "$PWD/out/figure-live.XXXXXXXX")
trap 'rm -rf "$take"' EXIT
exe=./_build/native/release/build/stillfail/sffigurebatchcheck/sffigurebatchcheck.exe
MBUI_BATCH_OUT="$take" "$exe"
cmp "$take/1.png" "$take/2.png"
mv "$take/2.png" "$take/previous.png"
MBUI_BATCH_OUT="$take" MBUI_BATCH_FIRST_BAD=1 "$exe"
cmp "$take/previous.png" "$take/2.png"
MBUI_BATCH_OUT="$take" MBUI_BATCH_FAILED_FILM=1 "$exe"
cmp "$take/previous.png" "$take/2.png"
mkdir "$take/system" "$take/mixed"
MBUI_BATCH_OUT="$take/system" MBUI_BATCH_SYSTEM_ONLY=1 "$exe"
MBUI_BATCH_OUT="$take/mixed" MBUI_BATCH_FIRST_FACE_ONLY=1 "$exe"
cmp "$take/system/2.png" "$take/mixed/2.png"
echo 'figure-batch-live-test: repeated pictures, fonts and recovery after failed picture and film passed'

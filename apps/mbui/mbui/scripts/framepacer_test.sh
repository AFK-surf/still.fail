#!/bin/sh
# Android's frame pacing (android/app/.../FramePacer.java, MBView's) on a clock of its own: android/pacer/FramePacerTest.java,
# plain Java, no Android: a motion's refreshes each with a new frame, the display's rate while it moves and while the
# field is typed into, and a phone's recorded frames (android/pacer/devperf2-frames.txt: PERF's t, work, present)
# replayed. Needs a JDK (javac, java).
set -eu
cd "$(dirname "$0")/.."
OUT=${TMPDIR:-/tmp}/framepacer.$$
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' EXIT
javac -d "$OUT" android/app/src/main/java/dev/mbui/FramePacer.java android/pacer/FramePacerTest.java
java -cp "$OUT" dev.mbui.FramePacerTest android/pacer/devperf2-frames.txt

# The app's scenes measured in mbui's native shell (wasmtime), built for classic Wasm and for Wasm GC from the same
# sources: APPBENCH lines, and each frame's (out/gcbench/<target>-<scene>.frames).
W=$(cd .. && pwd); export MBUI_TOOLS=$W/tools; cd apps/mbui && . scripts/env.sh
mkdir -p out/gcbench
SC=${SCENES:-"open fling switch keyboard"}
for t in ${TARGETS:-wasm wasm-gc}; do
  WASM_TARGET=$t APP=sfbench bash scripts/wasm-app.sh build > out/gcbench/build-$t.log 2>&1 || { echo "build $t failed"; grep -a -A6 "^Error" out/gcbench/build-$t.log | head -30; continue; }
  cp $(find _build/$t/release/build -name sfbench.wasm | head -1) out/gcbench/sfbench-$t.wasm
  ls -la out/gcbench/sfbench-$t.wasm | awk '{print $5, $9}'
done
for scene in $SC; do
  row=$(awk -v s=$scene '$1==s' <<'T'
idle chat-long 1280x800 0 mouse
fling chat-long 390x844 2 finger
backswipe chat 390x844 2 finger
newchat home 390x844 2 finger
switch home 351x805 2 finger
keyboard chat 390x844 2 finger
open home 351x805 2 finger
T
)
  set -- $row
  for t in ${TARGETS:-wasm wasm-gc}; do
    [ -f out/gcbench/sfbench-$t.wasm ] || continue
    MBUI_BENCH_DRIVE=scripts/bench/$scene.drive MBUI_BENCH_NAME=$scene MBUI_FIXTURE=$2 MBUI_WIN=$3 MBUI_FILM_PLATFORM=$4 \
      MBUI_POINTING=$5 MBUI_BENCH_FRAMES=out/gcbench/$t-$scene.frames \
      out/wasm-app/shell out/gcbench/sfbench-$t.wasm > out/gcbench/$t-$scene.log 2>&1
    echo "== $scene $t exit $?"
    grep -a "APPBENCH\|wasm shell" out/gcbench/$t-$scene.log | cut -c1-900 | head -3
  done
done

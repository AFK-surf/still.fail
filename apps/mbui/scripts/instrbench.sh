#!/bin/bash
# still.fail's scenes, what each frame runs counted, instruction by instruction (mbui's wasmgas: its main.mbt says how):
# src/sfbench built for classic Wasm (scripts/wasm-app.sh's program and shell), made to count (wasmgas profile), and
# each scene's script run by the shell over sffix's made-up chats (MBUI_PROFILE_FILE: mbui's wasm_shell.c). The same
# count every run, whatever the machine and its load; what a frame of each kind of instruction runs, and which
# functions, said. Not the time a frame takes on a device: the native build's (scripts/appbench.sh) and a device's
# are that. What the Tester's fake host runs in its stead (its Host methods: a device's host's own code) is said apart.
# Numbers, never a verdict: what they say of a change is the reader's to weigh (the user, 2026-11-09).
#   scripts/instrbench.sh [run] [OUT]     every scene (SCENES="home" those) into OUT (out/instr/run), each said
#   scripts/instrbench.sh compare A B     two runs' OUTs side by side, A before and B after (each from its checkout),
#                                         both compiled by the same MoonBit (MBUI_TOOLS): another one's code is
#                                         another's (moon of 2026-10-16 and of 11-04: Home's frame 2.9% apart)
#   scripts/instrbench.sh allocs [update] OUT
#                                         each scene's allocations in OUT's run (the allocator's outermost calls, all
#                                         its measured frames') held to its bar in bench/allocs.txt, which only falls,
#                                         as detlint's counts (mbui's wasmgas allocs); update: the bars written as OUT's
#   TOP=20: how many functions are said. MBUI_PROFILE_EACH=1: each function's counts in each frame too (F lines)
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
# scene      script                           fixture    window
# (idle: a long chat open, untouched; home, medium: scrolled; stream: an agent's messages coming in, untouched)
table="idle idle-small chat-long 390x844
home scroll-home long 390x844
medium scroll-medium chat-long 690x840
stream stream chat-stream 390x844"
gas() { "$MBUI_DIR/scripts/wasmgas" "$@"; }
if [ "${1:-run}" = compare ]; then
  [ $# = 3 ] || { echo 'instrbench.sh compare BEFORE_OUT AFTER_OUT' >&2; exit 2; }
  # (what compiled each: another MoonBit compiles the same code to other instructions, its counts others too)
  echo "moon: $(cat "$2/moon" 2>/dev/null) before, $(cat "$3/moon" 2>/dev/null) after"
  echo
  while read -r scene _; do
    [ -f "$2/$scene.profile" ] && [ -f "$3/$scene.profile" ] || continue
    echo "== $scene"
    gas compare "$2/program.wasm" "$2/$scene.profile" "$3/program.wasm" "$3/$scene.profile" ${TOP:-20}
    echo
  done <<< "$table"
  exit 0
fi
if [ "${1:-run}" = allocs ]; then
  shift
  up=""
  [ "${1:-}" = update ] && { up=update; shift; }
  [ $# = 1 ] || { echo 'instrbench.sh allocs [update] OUT' >&2; exit 2; }
  runs=()
  while read -r scene _; do
    [ -f "$1/$scene.profile" ] && runs+=("$scene" "$1/$scene.profile")
  done <<< "$table"
  [ ${#runs[@]} -gt 0 ] || { echo "instrbench: no scene's profile in $1" >&2; exit 1; }
  gas allocs "$A/bench/allocs.txt" $up "${runs[@]}"
  exit
fi
[ "${1:-run}" = run ] && shift || true
O=$(mkdir -p "${1:-out/instr/run}" && cd "${1:-out/instr/run}" && pwd)
APP=sfbench bash "$D/wasm-app.sh" build > "$O/build.log" 2>&1 || { tail -30 "$O/build.log"; exit 1; }
cp "$A/$(pkg_build sfbench wasm release)/sfbench.wasm" "$O/program.wasm"
# (the Tester's fake host apart, its Host methods: what a device's host does in its own code, FakeHost::present's flat_from
# of every group header among them, is no work of the app's; each call of one counted as one host call)
gas profile "$O/program.wasm" "$O/profiled.wasm" _M0IP24mbui2ui8FakeHostP24mbui7hostapi4Host
git rev-parse --short HEAD > "$O/commit" 2>/dev/null || true
moon version 2>/dev/null | head -1 > "$O/moon"
while read -r scene drive fixture win; do
  [ -n "${SCENES:-}" ] && ! echo " $SCENES " | grep -q " $scene " && continue
  # (小屏 or 中屏 a finger's, at 60 frames a second: a phone's)
  if ! env MBUI_PROFILE_FILE="$O/$scene.profile" MBUI_BENCH_DRIVE="$A/scripts/bench/$drive.drive" MBUI_BENCH_NAME=$scene \
      MBUI_FIXTURE=$fixture MBUI_WIN=$win MBUI_FILM_PLATFORM=2 MBUI_POINTING=finger MBUI_BENCH_FPS=60 \
      "$A/out/wasm-app/shell" "$O/profiled.wasm" > "$O/$scene.log" 2>&1; then
    echo "$scene: the run did not pass"
    grep -E "^DRIVE|wasm shell" "$O/$scene.log" | tail -5
    exit 1
  fi
  echo "== $scene"
  gas report "$O/program.wasm" "$O/$scene.profile" ${TOP:-20}
  echo
done <<< "$table"
rm -f "$O/profiled.wasm"
echo "instrbench: $O"

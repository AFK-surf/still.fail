#!/bin/bash
# Check the orchestration with a frame producer and renderer of our own. A previously complete run cannot supply
# a frame the next run did not produce, in either the default output directory or a caller's reused directory.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$D/../out"
T=$(mktemp -d "$D/../out/paint-damage-script.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts"
cp "${1:-$D/render_paint_damage.sh}" "$T/scripts/render_paint_damage.sh"
cat > "$T/scripts/env.sh" <<'PRODUCER'
moon() {
  for name in typing-before typing-after caret-before caret-hidden caret-shown \
    regions-before regions-moved regions-shrunk regions-gone regions-new clips-before clips-after glass-before glass-after; do
    [ "$name" != "${PAINT_FRAME_OMIT:-}" ] || continue
    printf 'DLBEGIN %s\nthis run: %s\nDLEND\n' "$name" "$name"
  done
}
moon_tests() { moon "$@"; }
PRODUCER
cat > "$T/renderer" <<'RENDERER'
#!/bin/bash
set -eu
cat "$MBUI_DL_FROM" "$MBUI_DL" > "$MBUI_DL_PNG"
cp "$MBUI_DL_PNG" "${MBUI_DL_PNG%.png}.whole.png"
RENDERER
chmod +x "$T/renderer"
export MBUI_PAINT_DAMAGE_RENDERER="$T/renderer"
run_check() {
  if [ "$mode" = default ]; then
    bash "$T/scripts/render_paint_damage.sh"
  else
    bash "$T/scripts/render_paint_damage.sh" "$output"
  fi
}
for mode in default supplied; do
  if [ "$mode" = default ]; then
    output="$T/out/paint-damage"
  else
    output="$T/reused"
  fi
  for missing in typing-after caret-before; do
    PAINT_FRAME_OMIT= run_check > "$T/complete.log" 2>&1
    test -s "$output/$missing.dl"
    printf 'keep\n' > "$output/caller.txt"
    if PAINT_FRAME_OMIT="$missing" run_check > "$T/missing.log" 2>&1; then
      echo "paint damage script: accepted stale $missing in $mode directory"
      exit 1
    fi
    grep -q 'paint damage: missing draw list' "$T/missing.log"
    test ! -e "$output/$missing.dl"
    test ! -e "$output/$missing.png"
    test -s "$output/caller.txt"
  done
done
echo 'paint damage script: missing current frames fail in default and supplied directories'

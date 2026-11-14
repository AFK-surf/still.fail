#!/bin/bash
# Render a scripted mbui scene and keep the inputs and fingerprints needed to identify the result.
#   media.sh picture OUT.png DRIVE [PREPARE] | film OUT.mp4 DRIVE [PREPARE] | preview DRIVE [PREPARE], from apps/mbui
#   on an Apple Silicon Mac, e.g. MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 bash scripts/media.sh picture
#   out/home.png out/home.drive. PREPARE is a drive run before the recorded actions (`image_ready SRC` waits for an image).
#   Scene: MBUI_WIN, MBUI_FILM_SCALE, MBUI_FILM_PLATFORM, MBUI_NATIVE_INPUT, MBUI_POINTING, MBUI_KEYBOARD, MBUI_DARK,
#   MBUI_LOCALE, MBUI_FONT_SCALE and the fixture's (all of film's: mbui/src/film/film.mbt; the made-up station's pace,
#   MBUI_FIX_PACE=DELIVER,ANSWER,END and MBUI_FIX_CORE=MS: src/sffixture fix_pace_said). A picture: MBUI_PICTURE_FRAME=K
#   or MBUI_PICTURE_AT=MS, MBUI_PICTURE_TRANSPARENT=1. A film: MBUI_FILM_FPS (60), also OUT.last.png and OUT.textrec.
#   Beside each result OUT.scene.json records the scripts, settings and hashes. It fails rather than omit what mbui
#   cannot draw (a native view, an image not decoded, a corner fault) unless MBUI_FILM_ALLOW_INCOMPLETE=1 or
#   MBUI_FILM_ALLOW_CORNER_FAULTS=1, which the record says. A failure leaves an existing output in place.
#   Several pictures or films on another station without building there: media-job.sh.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
portable=0
if [ -n "${MBUI_MEDIA_RUNTIME:-}" ]; then
  exe=$MBUI_MEDIA_RUNTIME
  case "$exe" in /*) ;; *) exe="$PWD/$exe" ;; esac
  portable=1
elif [ -x "$D/sffilm" ]; then
  exe="$D/sffilm"
  portable=1
else
  . "$D/env.sh"
  cd "$A"
fi

if [ "${1:-}" = preview ]; then
  [ "$portable" = 0 ] || { echo 'media: preview requires the application source checkout' >&2; exit 2; }
  shift
  exec bash "$D/media-preview.sh" "$@"
fi
usage='media.sh picture|film OUTPUT DRIVE [PREPARE]'
[ "$#" -ge 3 ] && [ "$#" -le 4 ] || { echo "$usage" >&2; exit 2; }
kind=$1
out=$2
drive=$3
prepare=${4:-}
case "$kind:$out" in
  picture:*.png|film:*.mp4) ;;
  *) echo "$usage (picture: .png; film: .mp4)" >&2; exit 2 ;;
esac
[ -s "$drive" ] || { echo "media: cannot read drive $drive" >&2; exit 2; }
if [ -n "$prepare" ] && [ ! -s "$prepare" ]; then
  echo "media: cannot read preparation $prepare" >&2
  exit 2
fi
app=${MBUI_MEDIA_APP:-sffilm}
case "$app" in ''|*[!a-zA-Z0-9_-]*) echo 'media: invalid app name' >&2; exit 2 ;; esac
[ "$portable" = 0 ] || [ "$app" = sffilm ] || { echo 'media: a prebuilt runtime only supports sffilm' >&2; exit 2; }
command -v jq >/dev/null || { echo 'media: jq is required' >&2; exit 2; }
command -v shasum >/dev/null || { echo 'media: shasum is required' >&2; exit 2; }
jq -n --argjson extra "${MBUI_MEDIA_RECORD:-null}" '$extra' >/dev/null || { echo 'media: MBUI_MEDIA_RECORD must be JSON' >&2; exit 2; }
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
if [ -e "$out" ] && { [ "$drive" -ef "$out" ] || { [ -n "$prepare" ] && [ "$prepare" -ef "$out" ]; }; }; then
  echo 'media: the output cannot overwrite an input script' >&2
  exit 2
fi
# Read the source state before creating any output beside the requested path.
revision=''
dirty=unknown
runtime_key=''
if [ "$portable" = 1 ]; then
  manifest="$(dirname "$exe")/manifest.json"
  if [ -f "$manifest" ]; then
    revision=$(jq -r '.commit // ""' "$manifest")
    runtime_key=$(jq -r '.key // ""' "$manifest")
  fi
else
  revision=$(git rev-parse HEAD 2>/dev/null || true)
  if [ -n "$revision" ]; then
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then dirty=yes; else dirty=no; fi
  fi
fi
mkdir -p "$(dirname "$out")"

# A copied script is the exact input both the renderer and its record use, even if the original changes mid-run.
work=$(mktemp -d "${out}.media.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
cp "$drive" "$work/drive"
if [ -n "$prepare" ]; then cp "$prepare" "$work/prepare"; else : > "$work/prepare"; fi

if [ "$portable" = 0 ]; then
  if [ "$app" = sffilm ]; then
    # (the scene in Wasm and the Mac's renderer and writer, as a prepared job's: no C of the app compiled, the user
    # 2026-11-03; scripts/wasm-film-build.sh)
    bash "$D/wasm-film-build.sh" "$A/out/wasm-film" >&2
    exe="$A/out/wasm-film/sffilm"
  else
    APP="$app" MODE=release bash "$D/mac.sh" build
    exe="./_build/native/release/build/stillfail/$app/$app.exe"
  fi
fi
[ -x "$exe" ] || { echo "media: no executable for $app" >&2; exit 1; }
# this machine's station as the app's own native call says it (MBUI_LOCAL_STATION), as mbui's film takes such calls
if [ -n "${MBUI_LOCAL_STATION:-}" ]; then
  MBUI_APP_SAID=$(jq -cn --arg s "$MBUI_LOCAL_STATION" '{local_station: $s}')
  export MBUI_APP_SAID
fi
if [ "$kind" = picture ]; then
  env MBUI_FILM= MBUI_PICTURE="$work/result.png" MBUI_FILM_DRIVE="$work/drive" \
    MBUI_FILM_PREPARE="${prepare:+$work/prepare}" MBUI_FILM_LAST= MBUI_FILM_COPIED= "$exe"
  result="$work/result.png"
else
  env MBUI_PICTURE= MBUI_FILM="$work/result.mp4" MBUI_FILM_DRIVE="$work/drive" \
    MBUI_FILM_PREPARE="${prepare:+$work/prepare}" MBUI_FILM_LAST="$work/last.png" MBUI_FILM_COPIED= "$exe"
  result="$work/result.mp4"
fi

sha() { shasum -a 256 "$1" | awk '{print $1}'; }
wasm_sha=''
host_sha=''
runner_sha=''
compact_sha=''
if [ -f "$(dirname "$exe")/scene.wasm" ]; then
  wasm_sha=$(sha "$(dirname "$exe")/scene.wasm")
  host_sha=$(sha "$(dirname "$exe")/native.node")
  runner_sha=$(sha "$(dirname "$exe")/run.mjs")
  compact_sha=$(sha "$(dirname "$exe")/compact.mjs")
fi
last_sha=''
text_sha=''
if [ "$kind" = film ]; then
  last_sha=$(sha "$work/last.png")
  text_sha=$(sha "$work/result.mp4.textrec")
fi
os=$(sw_vers -productVersion 2>/dev/null || uname -sr)
# The explicit list avoids recording arbitrary environment variables or credentials. The local station description
# can contain private data, so record only its fingerprint. Script text is included: it describes the visible action.
local_station_hash=''
if [ -n "${MBUI_LOCAL_STATION:-}" ]; then
  local_station_hash=$(printf %s "$MBUI_LOCAL_STATION" | shasum -a 256 | awk '{print $1}')
fi
jq -n --rawfile drive "$work/drive" --rawfile prepare "$work/prepare" \
  --arg kind "$kind" --arg app "$app" --arg revision "$revision" --arg dirty "$dirty" --arg runtime_key "$runtime_key" \
  --arg exe_sha "$(sha "$exe")" --arg output_sha "$(sha "$result")" --arg last_sha "$last_sha" --arg text_sha "$text_sha" \
  --arg wasm_sha "$wasm_sha" --arg host_sha "$host_sha" --arg runner_sha "$runner_sha" --arg compact_sha "$compact_sha" \
  --arg drive_path "$drive" --arg drive_sha "$(sha "$work/drive")" \
  --arg prepare_path "$prepare" --arg prepare_sha "$(sha "$work/prepare")" \
  --arg made "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg os "$os" --arg arch "$(uname -m)" \
  --arg size "${MBUI_WIN:-390x844}" --arg scale "${MBUI_FILM_SCALE:-2}" \
  --arg fps "${MBUI_FILM_FPS:-60}" --arg platform "${MBUI_FILM_PLATFORM:-0}" \
  --arg fixture "${MBUI_FIXTURE:-}" --arg dark "${MBUI_DARK:-}" --arg locale "${MBUI_LOCALE:-}" \
  --arg native "${MBUI_NATIVE_INPUT:-}" --arg pointing "${MBUI_POINTING:-}" --arg keyboard "${MBUI_KEYBOARD:-}" \
  --arg font_scale "${MBUI_FONT_SCALE:-}" --arg inset "${MBUI_FILM_INSET:-}" \
  --arg corner "${MBUI_FILM_WINDOW_CORNER:-}" --arg nav "${MBUI_FILM_NAV_ABLE:-}" \
  --arg max "${MBUI_FILM_FRAMES:-3000}" --arg at "${MBUI_PICTURE_AT:-}" \
  --arg frame "${MBUI_PICTURE_FRAME:-}" --arg transparent "${MBUI_PICTURE_TRANSPARENT:-}" \
  --arg allow_incomplete "${MBUI_FILM_ALLOW_INCOMPLETE:-}" --arg allow_corner_faults "${MBUI_FILM_ALLOW_CORNER_FAULTS:-}" \
  --arg station_sha "$local_station_hash" --arg hold "${MBUI_HOLD:-}" --arg failed "${MBUI_FAILED:-}" \
  --arg failed_why "${MBUI_FAILED_WHY:-}" --arg window "${MBUI_WINDOW:-}" --arg said "${MBUI_SAID:-}" \
  --arg core_ms "${MBUI_CORE_MS:-}" --arg update "${MBUI_UPDATE:-}" --arg updates_ms "${MBUI_UPDATES_MS:-}" \
  --arg fix_pace "${MBUI_FIX_PACE:-}" --arg fix_core "${MBUI_FIX_CORE:-}" \
  --arg autofill "${MBUI_FILM_AUTOFILL:-}" --argjson extra "${MBUI_MEDIA_RECORD:-null}" \
  '{version: 1, kind: $kind, made_utc: $made, source: ({app: $app, revision: $revision, dirty: $dirty, runtime_key: $runtime_key, executable_sha256: $exe_sha} +
    (if $wasm_sha == "" then {} else {wasm_sha256: $wasm_sha, host_sha256: $host_sha, runner_sha256: $runner_sha, compact_sha256: $compact_sha} end)),
    host: {os: $os, architecture: $arch}, output_sha256: $output_sha,
    last_frame_sha256: $last_sha, text_record_sha256: $text_sha,
    drive: {path: $drive_path, sha256: $drive_sha, text: $drive},
    prepare: (if $prepare_path == "" then null else {path: $prepare_path, sha256: $prepare_sha, text: $prepare} end),
    settings: {window: $size, scale: $scale, fps: $fps, platform: $platform, fixture: $fixture, dark: $dark,
      locale: $locale, native_input: $native, pointing: $pointing, keyboard: $keyboard, font_scale: $font_scale,
      inset: $inset, window_corner: $corner, nav_able: $nav, max_frames: $max, at_ms: $at, frame: $frame,
      transparent: $transparent, allow_incomplete: $allow_incomplete, allow_corner_faults: $allow_corner_faults, local_station_sha256: $station_sha,
      fixture_options: {hold: $hold, failed: $failed, failed_why: $failed_why, window: $window, said: $said,
        core_ms: $core_ms, update: $update, updates_ms: $updates_ms, autofill: $autofill,
        fix_pace: $fix_pace, fix_core: $fix_core}}, extra: $extra}' > "$work/scene.json"

# The result is only published after the complete render and its record have succeeded. Each file is renamed on the
# same filesystem; the hash in the record lets a reader detect a mismatched file if publication was interrupted.
mv -f "$result" "$out"
if [ "$kind" = film ]; then
  mv -f "$work/last.png" "$out.last.png"
  mv -f "$work/result.mp4.textrec" "$out.textrec"
fi
mv -f "$work/scene.json" "$out.scene.json"
echo "media: $out"
echo "media: $out.scene.json"

#!/bin/bash
# Render a scripted mbui scene and keep the inputs and fingerprints needed to identify the result.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"

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
command -v jq >/dev/null || { echo 'media: jq is required' >&2; exit 2; }
command -v shasum >/dev/null || { echo 'media: shasum is required' >&2; exit 2; }
jq -n --argjson extra "${MBUI_MEDIA_RECORD:-null}" '$extra' >/dev/null || { echo 'media: MBUI_MEDIA_RECORD must be JSON' >&2; exit 2; }
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
if [ -e "$out" ] && { [ "$drive" -ef "$out" ] || { [ -n "$prepare" ] && [ "$prepare" -ef "$out" ]; }; }; then
  echo 'media: the output cannot overwrite an input script' >&2
  exit 2
fi
# Read the source state before creating any output beside the requested path.
revision=$(git rev-parse HEAD 2>/dev/null || true)
dirty=unknown
if [ -n "$revision" ]; then
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then dirty=yes; else dirty=no; fi
fi
mkdir -p "$(dirname "$out")"

# A copied script is the exact input both the renderer and its record use, even if the original changes mid-run.
work=$(mktemp -d "${out}.media.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
cp "$drive" "$work/drive"
if [ -n "$prepare" ]; then cp "$prepare" "$work/prepare"; else : > "$work/prepare"; fi

APP="$app" MODE=release bash "$D/mac.sh" build
exe="./_build/native/release/build/stillfail/$app/$app.exe"
[ -x "$exe" ] || { echo "media: no executable for $app" >&2; exit 1; }
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
  --arg kind "$kind" --arg app "$app" --arg revision "$revision" --arg dirty "$dirty" \
  --arg exe_sha "$(sha "$exe")" --arg output_sha "$(sha "$result")" --arg last_sha "$last_sha" --arg text_sha "$text_sha" \
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
  --arg station_sha "$local_station_hash" --arg hold "${MBUI_HOLD:-}" --arg failed "${MBUI_FAILED:-}" \
  --arg failed_why "${MBUI_FAILED_WHY:-}" --arg window "${MBUI_WINDOW:-}" --arg said "${MBUI_SAID:-}" \
  --arg core_ms "${MBUI_CORE_MS:-}" --arg update "${MBUI_UPDATE:-}" --arg updates_ms "${MBUI_UPDATES_MS:-}" \
  --arg autofill "${MBUI_FILM_AUTOFILL:-}" --argjson extra "${MBUI_MEDIA_RECORD:-null}" \
  '{version: 1, kind: $kind, made_utc: $made, source: {app: $app, revision: $revision, dirty: $dirty, executable_sha256: $exe_sha},
    host: {os: $os, architecture: $arch}, output_sha256: $output_sha,
    last_frame_sha256: $last_sha, text_record_sha256: $text_sha,
    drive: {path: $drive_path, sha256: $drive_sha, text: $drive},
    prepare: (if $prepare_path == "" then null else {path: $prepare_path, sha256: $prepare_sha, text: $prepare} end),
    settings: {window: $size, scale: $scale, fps: $fps, platform: $platform, fixture: $fixture, dark: $dark,
      locale: $locale, native_input: $native, pointing: $pointing, keyboard: $keyboard, font_scale: $font_scale,
      inset: $inset, window_corner: $corner, nav_able: $nav, max_frames: $max, at_ms: $at, frame: $frame,
      transparent: $transparent, local_station_sha256: $station_sha,
      fixture_options: {hold: $hold, failed: $failed, failed_why: $failed_why, window: $window, said: $said,
        core_ms: $core_ms, update: $update, updates_ms: $updates_ms, autofill: $autofill}}, extra: $extra}' > "$work/scene.json"

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

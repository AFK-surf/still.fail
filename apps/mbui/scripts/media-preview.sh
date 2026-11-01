#!/bin/bash
# Replay the same mbui scene in a native window, then leave it interactive.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'media.sh preview DRIVE [PREPARE]' >&2; exit 2; }
drive=$1
prepare=${2:-}
[ -s "$drive" ] || { echo "media preview: cannot read drive $drive" >&2; exit 2; }
if [ -n "$prepare" ] && [ ! -s "$prepare" ]; then
  echo "media preview: cannot read preparation $prepare" >&2
  exit 2
fi
# These values simulate a host under the offscreen Tester. The native window gets those details from its real host;
# refuse to pretend it reproduced an explicitly simulated system setting.
for name in MBUI_NATIVE_INPUT MBUI_KEYBOARD MBUI_FONT_SCALE MBUI_LOCAL_STATION MBUI_FILM_INSET MBUI_FILM_WINDOW_CORNER MBUI_FILM_NAV_ABLE; do
  value=${!name:-}
  [ -z "$value" ] || { echo "media preview: $name is only supported by the offscreen renderer" >&2; exit 2; }
done
app=${MBUI_MEDIA_APP:-sffilm}
case "$app" in ''|*[!a-zA-Z0-9_-]*) echo 'media preview: invalid app name' >&2; exit 2 ;; esac
mkdir -p out
work=$(mktemp -d "$PWD/out/media-preview.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
append() {
  # Each script may end in exit. Remove it when joining; a step after exit would never have run in the original.
  awk '
    /^[[:space:]]*(#.*)?$/ { next }
    /^[[:space:]]*exit[[:space:]]*$/ { ended=1; next }
    ended { print "media preview: a step follows exit in " FILENAME > "/dev/stderr"; exit 2 }
    { print }
  ' "$1" >> "$work/drive"
}
[ -z "$prepare" ] || append "$prepare"
append "$drive"
printf 'exit\n' >> "$work/drive"
APP="$app" MODE=release bash "$D/mac.sh" build
exe="./_build/native/release/build/stillfail/$app/$app.exe"
[ -x "$exe" ] || { echo "media preview: no executable for $app" >&2; exit 1; }
export MBUI_WIN="${MBUI_WIN:-390x844}" MBUI_MEDIA_PREVIEW=1 MBUI_DRIVE_KEEP_OPEN=1
export MBUI_DRIVE="$(cat "$work/drive")"
export MBUI_PICTURE= MBUI_FILM=
on_screen "$exe"

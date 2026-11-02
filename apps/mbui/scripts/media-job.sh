#!/bin/bash
# Prepare a small, self-contained remote job. Source and build output stay here; only the scene and native-part client go.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
repo=$(cd "$D/../../.." && pwd)
usage='media-job.sh figure SCENE.json JOB_DIR | media-job.sh film DRIVE JOB_DIR [PREPARE]'
[ "$#" -ge 3 ] && [ "$#" -le 4 ] || { echo "$usage" >&2; exit 2; }
kind=$1
input=$2
job=$3
prepare=${4:-}
case "$kind" in
  figure) [ "$#" -eq 3 ] || { echo "$usage" >&2; exit 2; }; part=mbui-figure ;;
  film) part=mbui-film ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
[ -s "$input" ] || { echo "media-job: cannot read $input" >&2; exit 2; }
if [ -n "$prepare" ] && [ ! -s "$prepare" ]; then
  echo "media-job: cannot read $prepare" >&2; exit 2
fi
# The key includes the checked-out and edited app/framework sources, never the scene file. A missing key is an error on
# the destination: another version's renderer must not silently stand in for the code this job was made from.
key=$(node "$repo/scripts/native.ts" key "$part" darwin-arm64)
mkdir -p "$(dirname "$job")"
mkdir "$job" || { echo "media-job: job directory already exists: $job" >&2; exit 2; }
mkdir "$job/scripts"
cp "$repo/scripts/native.ts" "$repo/scripts/ffmpeg.ts" "$job/scripts/"
printf '%s\n' "$key" > "$job/runtime.key"
printf '%s\n' "$part" > "$job/runtime.part"
if [ "$kind" = figure ]; then cp "$input" "$job/scene.json"; else cp "$input" "$job/action.drive"; fi
if [ -n "$prepare" ]; then cp "$prepare" "$job/prepare.drive"; fi
cat > "$job/run.sh" <<'RUN'
#!/bin/bash
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
part=$(cat "$D/runtime.part")
key=$(cat "$D/runtime.key")
renderer=$(node "$D/scripts/native.ts" file-key "$part" darwin-arm64 "$key")
case "$part" in
  mbui-figure)
    exec bash "$(dirname "$renderer")/figure-run.sh" --scene "$D/scene.json" "$D/result.png" ;;
  mbui-film)
    kind=${MBUI_MEDIA_KIND:-picture}
    case "$kind" in picture) out="$D/result.png" ;; film) out="$D/result.mp4" ;; *) echo 'media-job: MBUI_MEDIA_KIND must be picture or film' >&2; exit 2 ;; esac
    if [ -s "$D/prepare.drive" ]; then
      exec bash "$(dirname "$renderer")/media.sh" "$kind" "$out" "$D/action.drive" "$D/prepare.drive"
    else
      exec bash "$(dirname "$renderer")/media.sh" "$kind" "$out" "$D/action.drive"
    fi ;;
  *) echo 'media-job: invalid runtime part' >&2; exit 2 ;;
esac
RUN
chmod +x "$job/run.sh"
printf 'media-job: %s (%s %s)\n' "$job" "$part" "$key"

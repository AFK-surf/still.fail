#!/bin/bash
# A remote job contains only its input and prebuilt client; only code changes select a different runtime key.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
source_repo=$(cd ../.. && pwd)
mkdir -p out
take=$(mktemp -d "$PWD/out/media-job-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT
repo="$take/repo"
mkdir -p "$repo/scripts" "$repo/apps/mbui/scripts" "$repo/apps/mbui/src/example"
cp "$source_repo/scripts/native.ts" "$source_repo/scripts/ffmpeg.ts" "$repo/scripts/"
cp scripts/media-job.sh "$repo/apps/mbui/scripts/"
printf 'one\n' > "$repo/apps/mbui/src/example/example.mbt"
git -C "$repo" init -q
git -C "$repo" add .
printf '{"version":1}\n' > "$take/scene.json"
printf 'exit\n' > "$take/action.drive"
printf 'wait 10\nexit\n' > "$take/prepare.drive"
bash "$repo/apps/mbui/scripts/media-job.sh" figure "$take/scene.json" "$take/first"
printf '{"version":2}\n' > "$take/scene.json"
bash "$repo/apps/mbui/scripts/media-job.sh" figure "$take/scene.json" "$take/second"
cmp "$take/first/runtime.key" "$take/second/runtime.key"
if cmp -s "$take/first/scene.json" "$take/second/scene.json"; then
  echo 'media-job-test: scene change was not copied' >&2; exit 1
fi
printf 'two\n' > "$repo/apps/mbui/src/example/example.mbt"
bash "$repo/apps/mbui/scripts/media-job.sh" figure "$take/scene.json" "$take/changed"
if cmp -s "$take/first/runtime.key" "$take/changed/runtime.key"; then
  echo 'media-job-test: a source change kept the old runtime key' >&2; exit 1
fi
bash "$repo/apps/mbui/scripts/media-job.sh" film "$take/action.drive" "$take/film" "$take/prepare.drive"
[ "$(cat "$take/film/runtime.part")" = mbui-film ]
cmp "$take/action.drive" "$take/film/action.drive"
cmp "$take/prepare.drive" "$take/film/prepare.drive"
[ ! -e "$take/first/apps" ] && [ ! -e "$take/first/_build" ]
if bash "$repo/apps/mbui/scripts/media-job.sh" figure "$take/scene.json" "$take/first" >/dev/null 2>&1; then
  echo 'media-job-test: an existing job was overwritten' >&2; exit 1
fi
echo 'media-job-test: scenes and drives stay separate from the exact renderer version'

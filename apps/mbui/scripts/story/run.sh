#!/bin/bash
# A film of still.fail in use: scripts/story/<name>.json told over the app, driven by scripts/motion/story-<name>.drive,
# filmed on a phone (out/film/story-<name>.mp4). Markdown the run asked that is not kept is worked out by the core and the
# run made again (KEPT=0: not).
D="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$D"
name=${1:?name}
mkdir -p out/story
python3 scripts/story/make.py "$name.json" "$D/out/story/$name.json" || exit 1
film() {
  MBUI_FIXTURE=chat-story MBUI_STORY="$D/out/story/$name.json" MBUI_FILM_PLATFORM=${PLATFORM:-2} MBUI_WIN=${WIN:-390x800} MBUI_FILM_SCALE=${SCALE:-3} \
    MBUI_FILM_FRAMES=${FRAMES:-3000} MBUI_FILM_START=${START:-} bash scripts/film.sh "story-$name" "story-$name" > "out/story/$name.log" 2>&1
  echo "film: exit $?"; grep -v '^kept-answers-ask' "out/story/$name.log" | tail -15
}
film
n=$(grep -c '^kept-answers-ask' "out/story/$name.log")
echo "asked and not kept: $n"
if [ "$n" -gt 0 ] && [ "${KEPT:-1}" = 1 ]; then
  [ -d ../../client/core-ts/node_modules/@mathjax ] || (cd ../../client/core-ts && pnpm install --frozen-lockfile > out-pnpm.txt 2>&1; tail -3 out-pnpm.txt)
  node ../../client/core-ts/scripts/kept-answers.ts "out/story/$name.log" || exit 1
  film
  echo "asked and not kept now: $(grep -c '^kept-answers-ask' "out/story/$name.log")"
fi
ls -la out/film/story-$name.mp4

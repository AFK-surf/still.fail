#!/bin/bash
# still.fail's mbui app held against the web's stories by numbers (src/sflayout): each story taken on the page
# (scripts/web-layout.mjs: its elements' boxes and looks, the made-up core's topics), mbui's app given the same topics,
# size and steps in a Tester of this Mac's text, and what differs listed in OUT/STORY.md (missing, extra, off by N px,
# another corner, ground, words' size). Topics mbui's app asks that the page did not are taken from the page too, in a
# second round, which also takes each page again and fails where it is not the same as the first time. On a Mac
# (Studio: station_task), the repository's packages installed (root and client/core-ts). For
# finding what is left to port: not a check, not in CI.
#   apps/mbui/scripts/layout.sh [OUT] [STORY[@X,Y],…] [WxH]
#     (by default out/layout, the sidebar open, folded and shown a while: app-chat,app-sidebar-folded@640,400,
#     app-sidebar-peek; 1280x800)
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
out=$(mkdir -p "${1:-$A/out/layout}" && cd "${1:-$A/out/layout}" && pwd)
cd "$A"
stories=${2:-app-chat,app-sidebar-folded@640,400,app-sidebar-peek}
size=${3:-1280x800}
ids=$(echo "$stories" | node -e 'process.stdout.write(require("fs").readFileSync(0,"utf8").trim().split(/,(?![0-9])/).map((s)=>s.split("@")[0]).join(" "))')
export PLAYWRIGHT_MODULE=${PLAYWRIGHT_MODULE:-playwright-core} PLAYWRIGHT_CHANNEL=${PLAYWRIGHT_CHANNEL-chrome}
APP=sflayout MODE=release bash scripts/mac.sh build >"$out/build.log" 2>&1 || { grep -A12 '^Error' "$out/build.log" | head -120; exit 1; }
exe=$A/_build/native/release/build/stillfail/sflayout/sflayout.exe
echo '[]' > "$out/asked.json"
rm -f "$out"/*.web.before.json
for round in 1 2; do
  (cd "$EMBER" && node apps/mbui/scripts/web-layout.mjs "$out" "$stories" "$size" "$out/asked.json") || exit 1
  # the page taken again is the same page: its elements as the round before (else something not the run's got in)
  for id in $ids; do
    if [ -f "$out/$id.web.before.json" ]; then
      node -e 'const f=(p)=>JSON.stringify(JSON.parse(require("fs").readFileSync(p,"utf8")).elements);
        if (f(process.argv[1]) !== f(process.argv[2])) { console.log("the page of " + process.argv[3] + " is not as the round before"); process.exit(1); }' \
        "$out/$id.web.before.json" "$out/$id.web.json" "$id" || exit 1
    fi
    cp "$out/$id.web.json" "$out/$id.web.before.json"
  done
  for id in $ids; do
    LAYOUT_WEB=$out/$id.web.json LAYOUT_OUT=$out/$id.md LAYOUT_BOXES=$out/$id.mbui.json LAYOUT_ASKED=$out/$id.asked.json \
      "$exe" || exit 1
  done
  # what mbui's app asked that the page had not, all the stories', with what was asked before: a second round takes it
  n=$(cd "$out" && node -e '
    const fs = require("fs"); const all = new Map();
    for (const f of ["asked.json", ...process.argv.slice(1).map((id) => id + ".asked.json")])
      for (const k of JSON.parse(fs.readFileSync(f, "utf8"))) all.set(JSON.stringify(k), k);
    const before = JSON.parse(fs.readFileSync("asked.json", "utf8")).length;
    fs.writeFileSync("asked.json", JSON.stringify([...all.values()]));
    process.stdout.write(String(all.size - before));' $ids)
  [ $round = 1 ] && echo "round 1: $n topics more for the page to give"
done
ls "$out"/*.md

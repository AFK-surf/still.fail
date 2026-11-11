#!/bin/bash
# Each per-file bar of a run that counts or judges how what moves goes (MBUI_TEST_MOTION, its MOTION_OUT) set beside
# what was found under its file in that run (src/ui/tester_fps.mbt: motion_runs), said for people: a bar more than what
# was found falls, or what it was for is filed under another file (the file a Tester is made in is the bars' key: one
# made in a helper of another file's is that file's); a file still only counted (motion_counted) with nothing found
# leaves the list. Only files a Tester of these runs was made in; given all the jobs' of a run together (a Tester made
# in another file's helper is that file's, whose own tests may run in another job). Says, fails nothing (for now: the
# coordinator of the migration, 2026-11-12). scripts/motion_bars.sh FILE [TITLE]; in CI to the summary of a job after
# the runs at 60 and 120 (mbui-check's and mbui-ci's motion-bars).
f=${1:?motion_bars.sh FILE [TITLE]}
[ -s "$f" ] || { echo "### ${2:-bars}: nothing said"; exit 0; }
sort -u "$f" | awk -v title="${2:-bars}" '
  # MOTION made <file>
  $2 == "made" { made[$3] = 1; next }
  # MOTION bar <check> <file> <n>
  $2 == "bar" { bar[$3 " " $4] = $5; next }
  # MOTION counted <file>
  $2 == "counted" { counted[$3] = 1; next }
  # MOTION known <check> <file> <n>/<bar>: … (the most n a Tester came to)
  $2 == "known" { split($5, part, "/"); k = $3 " " $4; if (part[1] + 0 > found[k] + 0) found[k] = part[1] + 0; next }
  # MOTION held host_image_bytes <file> <bytes>
  $2 == "held" { k = $3 " " $4; if ($5 + 0 > found[k] + 0) found[k] = $5 + 0; next }
  # MOTION <check> <file>: … (counted: each fault once)
  { file = $3; sub(":$", "", file); k = $2 " " file; if (!(($0) in seen)) { seen[$0] = 1; counts[k]++; inlist[file]++ } }
  END {
    print "### " title
    print ""
    print "```"
    nb = 0; off = 0
    for (k in bar) {
      split(k, cf, " ")
      if (!(cf[2] in made)) continue
      nb++
      got = (k in counts) ? counts[k] : found[k] + 0
      if (cf[1] == "host_image_bytes") {
        if (got * 10 < bar[k] * 9) { printf "falls   %-16s %s: bar %d, held at most %d\n", cf[1], cf[2], bar[k], got; off++ }
      } else if (got < bar[k]) { printf "falls   %-16s %s: bar %d, found %d\n", cf[1], cf[2], bar[k], got; off++ }
    }
    for (c in counted) if ((c in made) && !(c in inlist)) { printf "leaves  motion_counted   %s: counted, nothing found\n", c; off++ }
    # (what a counted file showed, by check, where it has no bar of that check: what keeps it on the list)
    for (k in counts) { split(k, cf, " "); if (!(k in bar) && cf[1] ~ /^(gaps_steady|rows_steady|sizes_steady|words_over)$/) printf "counted %-16s %s: %d found\n", cf[1], cf[2], counts[k] }
    print nb " bars of files Testers were made in, " off " to fall or leave"
    print "```"
  }'

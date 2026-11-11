#!/bin/bash
# Each per-file bar of the runs that say them (src/ui/tester_fps.mbt: motion_runs; CI's at 60 and 120, which count or
# judge how what moves goes, and at the default rate, MBUI_TEST_BARS; their MOTION_OUT) set beside the most one Tester
# of its file found under it in those runs, said for people: a bar more than that falls, or what it was for is filed
# under another file (the file a Tester is made in is the bars' key: one made in a helper of another file's is that
# file's); a file still only counted (motion_counted) with nothing found at 60 or 120 leaves the list. A bar is how many
# one Tester may show, so it is set beside one Tester's most, never a sum of a file's. Only files a Tester of these runs
# was made in, and none of whose Testers is not judged on how what moves goes (Tester::motion_unjudged: what it finds
# is not looked for, so none found says nothing); given all the jobs' of a run together (a Tester made in another
# file's helper is that file's, whose own tests may run in another job). Says, fails nothing (for now: the coordinator
# of the migration, 2026-11-12). scripts/motion_bars.sh FILE [TITLE]; in CI to the summary of a job after the runs
# (mbui-check's and mbui-ci's motion-bars).
f=${1:?motion_bars.sh FILE [TITLE]}
[ -s "$f" ] || { echo "### ${2:-bars}: nothing said"; exit 0; }
sort -u "$f" | awk -v title="${2:-bars}" '
  # MOTION made <file>
  $2 == "made" { made[$3] = 1; next }
  # MOTION unjudged <file>
  $2 == "unjudged" { unjudged[$3] = 1; next }
  # MOTION bar <check> <file> <n>
  $2 == "bar" { bar[$3 " " $4] = $5; next }
  # MOTION counted <file>
  $2 == "counted" { counted[$3] = 1; next }
  # MOTION known <check> <file> <n>/<bar>: … (the most n one Tester came to, judged or counted)
  $2 == "known" { split($5, part, "/"); k = $3 " " $4; if (part[1] + 0 > found[k] + 0) found[k] = part[1] + 0; next }
  # MOTION held host_image_bytes <file> <bytes>
  $2 == "held" { k = $3 " " $4; if ($5 + 0 > found[k] + 0) found[k] = $5 + 0; next }
  # MOTION <check> <file>: … (a fault a counted file showed at 60 or 120; not the waits said as MOTION held_causes and
  # the like, Tester::wait_looked, which keep no file on the list)
  $2 ~ /^(gaps_steady|rows_steady|sizes_steady|words_over)$/ { file = $3; sub(":$", "", file); inlist[file] = 1 }
  END {
    print "### " title
    print ""
    print "```"
    nb = 0; off = 0
    for (k in bar) {
      split(k, cf, " ")
      if (!(cf[2] in made) || (cf[2] in unjudged)) continue
      nb++
      got = found[k] + 0
      if (cf[1] == "host_image_bytes") {
        if (got * 10 < bar[k] * 9) { printf "falls   %-16s %s: bar %d, held at most %d\n", cf[1], cf[2], bar[k], got; off++ }
      } else if (got < bar[k]) { printf "falls   %-16s %s: bar %d, one Tester found at most %d\n", cf[1], cf[2], bar[k], got; off++ }
    }
    for (c in counted) if ((c in made) && !(c in unjudged) && !(c in inlist)) { printf "leaves  motion_counted   %s: counted, nothing found\n", c; off++ }
    # (what a counted file showed, by check, where it has no bar of that check: what keeps it on the list)
    for (k in found) { split(k, cf, " "); if (!(k in bar) && (cf[2] in counted) && cf[1] ~ /^(gaps_steady|rows_steady|sizes_steady|words_over)$/) printf "counted %-16s %s: one Tester found at most %d\n", cf[1], cf[2], found[k] }
    nu = 0; for (u in unjudged) nu++
    print nb " bars of files Testers were made in, " off " to fall or leave; " nu " files not judged on how what moves goes, their bars left as they are"
    print "```"
  }'

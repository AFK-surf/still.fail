#!/bin/sh
# Writes scripts/page-seconds.txt again from check-mbui's runs RUN... (their app N/4 jobs' logs, testexe's "each file's
# seconds" line): each page file's median of what they saw at the default rate, at 60, 120, and 24 and 7 (a file's
# time differs by the runner and by what runs beside it: the most seen, of one run or a few, dealt app 1/4 at 120 fps
# 904 s of pages where it was told 697, 251 s of its 5 minutes, main 5d06cf01 42935951988, 2026-11-11). Its head (the
# lines of #) is kept.
# (A run before #5844 said its line without a package: its packages' programs said none, so all of it is sfapp's.)
# Needs gh. What no run measured (a file, a rate) keeps its old time.
set -e
[ $# -gt 0 ] || { echo "usage: $0 RUN..." >&2; exit 2; }
D="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
for run in "$@"; do
  gh run view "$run" -R AFK-surf/still.fail --json jobs \
    --jq '.jobs[] | select(.name | test("app [1-4]/4")) | "\(.databaseId) \(.name)"' |
    while read -r job name; do
      case "$name" in *"at 60 fps"*) col=3 ;; *"at 120 fps"*) col=4 ;; *" fps"*) col=5 ;; *) col=2 ;; esac
      gh api --allow-escape-sequences "repos/AFK-surf/still.fail/actions/jobs/$job/logs" 2>/dev/null |
        sed -n "s|.*testexe: each file's seconds\( of stillfail/sfapp\)\{0,1\}: ||p" | tr ',' '\n' |
        awk -v c=$col 'NF == 2 { print $1, c, $2 }'
    done
done > "$T/seen"
[ -s "$T/seen" ] || { echo "page-seconds: no run said its files' seconds" >&2; exit 1; }
grep '^#' "$D/page-seconds.txt" > "$T/new"
LC_ALL=C sort -k1,1 -k2,2n -k3,3n "$T/seen" | awk '
  { k = $1 SUBSEP $2; n[k]++; v[k, n[k]] = $3; f[$1] = 1; seen[k] = 1 }
  END { for (k in n) { m = n[k]; med[k] = (m % 2) ? v[k, (m + 1) / 2] : int((v[k, m / 2] + v[k, m / 2 + 1]) / 2) }
    for (k in med) print "M", k, med[k] }' | tr '\034' ' ' > "$T/med"
awk 'FNR == NR { m[$2, $3] = $4; seen[$2, $3] = 1; f[$2] = 1; next }
  /^#/ { next }
  { f[$1] = 1; for (c = 2; c <= 5; c++) if (!seen[$1, c]) m[$1, c] = $c }
  END { for (k in f) printf "%s %d %d %d %d\n", k, m[k, 2], m[k, 3], m[k, 4], m[k, 5] }' "$T/med" "$D/page-seconds.txt" |
  LC_ALL=C sort >> "$T/new"
mv "$T/new" "$D/page-seconds.txt"

#!/bin/bash
# What a run that counts how what moves goes (MBUI_TEST_MOTION=count, its MOTION_OUT) found, said for people: how many,
# then by check and file, the most first. scripts/motion_said.sh FILE [TITLE]; in CI to the job's summary.
f=${1:?motion_said.sh FILE [TITLE]}
[ -s "$f" ] || { echo "### ${2:-motion}: none"; exit 0; }
# (each fault once: a test that ran again in another shard or rate says it again; what the bars are and what was found
# within them is motion_bars.sh's)
u=$(grep -av '^MOTION \(bar\|made\|known\|counted\|held\|unjudged\|counting\) ' "$f" | sort -u)
[ -n "$u" ] || { echo "### ${2:-motion}: none"; exit 0; }
echo "### ${2:-motion}: $(echo "$u" | wc -l | tr -d ' ') faults"
echo
echo '```'
# ("MOTION <check> <file>: …")
echo "$u" | awk '{ sub(":$", "", $3); print $2, $3 }' | sort | uniq -c | sort -rn
echo '```'

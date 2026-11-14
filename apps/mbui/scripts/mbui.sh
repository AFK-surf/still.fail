#!/bin/sh
# mbui, the UI framework this app is written in: in this repository, at libs/mbui (moon.work names it a member;
# the build scripts are its scripts/). Its directory printed, for the scripts that ask where it is.
#   apps/mbui/scripts/mbui.sh
set -e
A="$(cd "$(dirname "$0")/.." && pwd)"
M="$A/../../libs/mbui"
[ -f "$M/moon.mod" ] || { echo "mbui.sh: no mbui at $M" >&2; exit 1; }
(cd "$M" && pwd)

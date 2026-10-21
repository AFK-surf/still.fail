#!/bin/sh
# mbui, the UI framework this app is written in: in this repository, at apps/mbui/mbui (moon.work names it a member;
# the build scripts are its scripts/). Its directory printed, for the scripts that ask where it is.
#   apps/mbui/scripts/mbui.sh
set -e
A="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$A/mbui/moon.mod" ] || { echo "mbui.sh: no mbui at $A/mbui" >&2; exit 1; }
echo "$A/mbui"

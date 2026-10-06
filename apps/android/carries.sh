#!/bin/sh
# Whether a change reaches the Android app: the changed paths on stdin, one a line; exits 0 when one does.
#   git diff --name-only <range> | sh apps/android/carries.sh
# What the app is built from (apps/android/build.py): its own sources, client/ (the core, its words, the shell), the
# visualizations' page, the avatars and icons the core and the app carry, the native parts' recipes; but for what
# apps/android/not-carried.txt says it does not carry.
here=$(dirname "$0")
grep -vE "$(grep -v '^#' "$here/not-carried.txt" | paste -sd'|' -)" \
  | grep -qE '^(apps/android|client|web/src/viz|web/public/avatars|design/icons)/|^scripts/(icons\.py|release\.sh|native\.ts)$'

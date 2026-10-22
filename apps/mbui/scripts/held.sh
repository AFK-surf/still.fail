#!/bin/sh
# What the directories hold, as a key (16 hex digits): their files' names and contents (the CI caches saved by it,
# .github/workflows/mbui.yml: one holding what the restored one held is not saved again).
#   sh apps/mbui/scripts/held.sh DIR…
find "$@" -type f ! -name "*.lock" 2>/dev/null | LC_ALL=C sort | xargs cksum 2>/dev/null | shasum -a 256 | cut -c1-16

#!/bin/sh
# What the directories hold, as a key (16 hex digits): their files' names and contents (the CI caches saved by it,
# .github/workflows/mbui.yml: one holding what the restored one held is not saved again).
#   sh apps/mbui/scripts/held.sh DIR…
# (sha256sum where there is no shasum: Windows' Git Bash, whose key was then the name alone, 41292344719)
if command -v shasum > /dev/null; then sum() { shasum -a 256; }; else sum() { sha256sum; }; fi
find "$@" -type f ! -name "*.lock" 2>/dev/null | LC_ALL=C sort | xargs cksum 2>/dev/null | sum | cut -c1-16

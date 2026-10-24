#!/bin/sh
# What a CI run used of the caches it restored, the rest deleted before they are saved again (.github/workflows/mbui.yml):
# of mbc's units (MBC_STORE: a unit's directory is newer than the run's start when the run made or took it) and of
# ThinLTO's cache (MBC_LTO_CACHE: the linker opens an entry it reads with its access time set, and writes what it makes).
# Without, both only grew: the macOS job's 1.7 GB, a minute to restore, one to save and one to hash for its key
# (2026-10-23, 40049963845). A ThinLTO cache no entry of which the run touched is kept whole (a linker that does not set
# the times would otherwise lose it all).
#   sh apps/mbui/scripts/used.sh START STORE [LTO]     START: a file touched as the run began
start=$1 store=$2 lto=${3:-}
mb() { du -sm "$1" 2>/dev/null | cut -f1; }
if [ -d "$store" ]; then
  before=$(mb "$store")
  find "$store" -name '*.lock' -delete
  find "$store" -mindepth 2 -maxdepth 2 -type d ! -newer "$start" -exec rm -rf {} +
  echo "used.sh: $store $before MB, $(mb "$store") MB of it used"
fi
if [ -n "$lto" ] && [ -d "$lto" ]; then
  before=$(mb "$lto")
  if [ -n "$(find "$lto" -type f -name 'llvmcache-*' -anewer "$start" | head -1)" ]; then
    find "$lto" -type f -name 'llvmcache-*' ! -anewer "$start" -delete
    echo "used.sh: $lto $before MB, $(mb "$lto") MB of it used"
  else
    echo "used.sh: $lto $before MB, none of it touched by this run: kept whole"
  fi
fi

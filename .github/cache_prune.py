#!/usr/bin/env python3
"""The Actions caches a newer one of the same kind has replaced, deleted (cache-prune.yml).

A repository has 10 GB of caches; past that GitHub evicts the least recently used. The build caches saved once per
commit or run (mbui-android-<sha>, mbui-mac-<sha>, ...) put ~0.5 GB in with every push to main, and what they pushed
out were the caches read seldom that jobs cannot do without (WARP, the emulator's system images and AVDs, MoonBit:
"no WARP 1.0.21 in the Actions cache", run 39536847651). A restore by restore-keys takes the newest of a prefix on its
ref (then main's), so the older ones of these prefixes are never read again: kept here is the newest of each prefix
on each ref, the rest deleted.

  python3 .github/cache_prune.py [--dry-run]     (GH_REPO=owner/name, gh logged in or GH_TOKEN with actions: write)
"""
import json
import os
import re
import subprocess
import sys

# a prefix, then what changes each commit or run (a sha, a run's id): one entry of each prefix per ref is read
ROLLING = [
    r"mbui-android-[0-9a-f]{40}$",
    r"mbui-mac-[0-9a-f]{40}$",
    r"mbui-ios-[0-9a-f]{40}$",
    r"mbui-ios-build-[0-9a-f]{40}$",
    r"mbui-ios-build-\d+-\d+$",
    r"mbui-win-build-mono-[0-9a-f]+$",
    # (.github/actions/setup: by the lockfiles' hash, restore-keys pnpm-<os>-: a changed lockfile leaves the old one)
    r"pnpm-Linux-[0-9a-f]{64}$",
    r"pnpm-Windows-[0-9a-f]{64}$",
    r"pnpm-macOS-[0-9a-f]{64}$",
]


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def main():
    dry = "--dry-run" in sys.argv
    repo = os.environ.get("GH_REPO") or os.environ["GITHUB_REPOSITORY"]
    caches = []
    for line in gh("api", "--paginate", f"repos/{repo}/actions/caches?per_page=100", "-q", ".actions_caches[]").splitlines():
        caches.append(json.loads(line))
    newest = {}
    gone = []
    for c in sorted(caches, key=lambda c: c["created_at"], reverse=True):
        kind = next((p for p in ROLLING if re.fullmatch(p, c["key"])), None)
        if kind is None:
            continue
        slot = (kind, c["ref"])
        if slot in newest:
            gone.append(c)
        else:
            newest[slot] = c
    freed = 0
    for c in gone:
        print(f"{'would delete' if dry else 'delete'} {c['key']} ({c['ref']}, {c['size_in_bytes'] // 1_000_000} MB, {c['created_at']})")
        if not dry:
            gh("api", "-X", "DELETE", f"repos/{repo}/actions/caches/{c['id']}")
        freed += c["size_in_bytes"]
    total = sum(c["size_in_bytes"] for c in caches)
    print(f"{len(gone)} of {len(caches)} caches, {freed // 1_000_000} MB of {total // 1_000_000} MB")


if __name__ == "__main__":
    main()

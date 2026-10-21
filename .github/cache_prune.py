#!/usr/bin/env python3
"""The Actions caches a newer one of the same kind has replaced, deleted (cache-prune.yml).

A repository has 10 GB of caches; past that GitHub evicts the least recently used. The build caches saved once per
commit or run (mbui-android-<sha>, mbui-mac-<sha>, ...) put ~0.5 GB in with every push to main, and what they pushed
out were the caches read seldom that jobs cannot do without (WARP, the emulator's system images and AVDs, MoonBit:
"no WARP 1.0.21 in the Actions cache", run 39536847651). A restore by restore-keys takes the newest of a prefix on its
ref (then main's), so the older ones of these prefixes are never read again: kept here is the newest of each prefix
on each ref, the rest deleted. Gradle's (setup-gradle): a Gradle home's entry per job and commit, the newest of each
job kept; its parts' entries (gradle-transforms-v1-*, gradle-dependencies-v1-*, ...: by their content, each read as a
home that names it is restored) deleted when none has read them for a day (at worst a job's Gradle starts cold).

  python3 .github/cache_prune.py [--dry-run]     (GH_REPO=owner/name, gh logged in or GH_TOKEN with actions: write)
"""
import datetime
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
    # (setup-gradle's Gradle home: gradle-home-v1|<os>|<job>[<matrix's hash>]-<sha>, the newest of a job restored)
    r"(gradle-home-v1\|[^|]+\|[^\]]+\])-[0-9a-f]{40}$",
]
# setup-gradle's parts of a Gradle home, by their content: read only as a home naming them is restored
PARTS = r"gradle-[a-z-]+-v1-[0-9a-f]{32}$"
STALE_PARTS_S = 24 * 3600


def parse(t):
    return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def main():
    dry = "--dry-run" in sys.argv
    repo = os.environ.get("GH_REPO") or os.environ["GITHUB_REPOSITORY"]
    caches = []
    for line in gh("api", "--paginate", f"repos/{repo}/actions/caches?per_page=100", "-q", ".actions_caches[]").splitlines():
        caches.append(json.loads(line))
    now = datetime.datetime.now(datetime.timezone.utc).timestamp()
    newest = {}
    gone = []
    for c in sorted(caches, key=lambda c: c["created_at"], reverse=True):
        if re.fullmatch(PARTS, c["key"]):
            if now - parse(c["last_accessed_at"]) > STALE_PARTS_S:
                gone.append(c)
            continue
        m = next((m for m in (re.fullmatch(p, c["key"]) for p in ROLLING) if m), None)
        if m is None:
            continue
        kind = (m.re.pattern, m.group(1) if m.re.groups else "")
        slot = (kind, c["ref"])
        if slot in newest:
            gone.append(c)
        else:
            newest[slot] = c
    freed = 0
    for c in gone:
        print(f"{'would delete' if dry else 'delete'} {c['key']} ({c['ref']}, {c['size_in_bytes'] // 1_000_000} MB, {c['created_at']})")
        if not dry:
            r = subprocess.run(["gh", "api", "-X", "DELETE", f"repos/{repo}/actions/caches/{c['id']}"], capture_output=True, text=True)
            # (gone already, between the list and here: GitHub's own eviction, run 39606378560)
            if r.returncode != 0 and "HTTP 404" not in r.stderr:
                sys.exit(f"cache_prune: deleting {c['key']}: {r.stderr.strip()}")
        freed += c["size_in_bytes"]
    total = sum(c["size_in_bytes"] for c in caches)
    print(f"{len(gone)} of {len(caches)} caches, {freed // 1_000_000} MB of {total // 1_000_000} MB")


if __name__ == "__main__":
    main()

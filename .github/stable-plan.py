#!/usr/bin/env python3
"""Resolve one reviewed, successfully tested revision before any stable publication.

The release's notes (docs/releases/0.1.<n>.md, on main) name it by its version, the commits up to it:
  - a main commit (the day before's, beta-tested for a day: the user, 2026-11-09), found on main by its commit count; the
    notes are merged into main after it, so they need not be in it. Its successful main pipeline's web artifact is
    promoted unchanged when it has one; else (no web change in that run) its web is built by Publish stable.
  - with `branch: release/<…>` in their front matter: that branch's newest commit (a main commit and the serious fixes
    cherry-picked onto it, the notes too), which must count n commits and carry the same notes, its branch pipeline
    successful. Its version can be a main commit's as well (the same number, other contents: allowed, the user,
    2026-11-09); its web is built by Publish stable, never on beta.
"""
import json
import os
import re
import subprocess

REPO = 'AFK-surf/monoid'


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def count(sha):
    return int(output('git', 'rev-list', '--count', sha))


def front(notes, key):
    m = re.search(rf'^{key}:\s*(\S+?)\s*(?:#.*)?$', notes.split('\n---', 1)[0], re.M)
    return m.group(1) if m else ''


def on_main(version):
    """main's commit that counts `version` commits: on its first-parent line, where the count only grows."""
    line = output('git', 'rev-list', '--first-parent', 'origin/main').splitlines()[::-1]
    low, high = 0, len(line) - 1
    while low <= high:
        middle = (low + high) // 2
        n = count(line[middle])
        if n == version:
            return line[middle]
        low, high = (middle + 1, high) if n < version else (low, middle - 1)
    raise SystemExit(f'No main commit counts {version} commits: the release notes name none.')


def runs(sha, branch):
    found = json.loads(output('gh', 'run', 'list', '-R', REPO, '-w', 'pipeline', '--branch', branch, '--commit', sha, '--limit', '100', '--json', 'databaseId,conclusion'))
    return [run['databaseId'] for run in found if run['conclusion'] == 'success']


def plan(revision=''):
    entries = json.loads(output('node', 'scripts/changelog.ts', '--stable'))
    if not entries:
        raise SystemExit('Write and review the stable release notes first (scripts/changelog.ts).')
    if revision and not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise SystemExit('revision must be a full commit SHA.')
    version = max(entry['version'] for entry in entries)
    if revision:
        version = count(output('git', 'rev-parse', '--verify', revision + '^{commit}'))
    notes = output('git', 'show', f'origin/main:docs/releases/0.1.{version}.md')
    branch = front(notes, 'branch')
    if branch:
        if not re.fullmatch(r'release/[0-9A-Za-z._-]+', branch):
            raise SystemExit(f'branch: {branch} is not a release branch (release/<name>).')
        sha = output('git', 'rev-parse', '--verify', f'origin/{branch}^{{commit}}')
        if revision and revision != sha:
            raise SystemExit(f'{revision} is not the newest commit of {branch}.')
        if count(sha) != version:
            raise SystemExit(f'{branch} counts {count(sha)} commits, not the notes\' {version}.')
        if output('git', 'show', f'{sha}:docs/releases/0.1.{version}.md') != notes:
            raise SystemExit(f'{branch} does not carry the release notes main has.')
        base = output('git', 'merge-base', sha, 'origin/main')
    else:
        sha = on_main(version)
        if revision and revision != sha:
            raise SystemExit('revision must be a main commit, or a release branch\'s its notes name.')
        base = sha
    if not re.search(rf'^version:\s*{version}\s*(?:#.*)?$', notes, re.M):
        raise SystemExit('The release notes do not say their own version.')
    stable = subprocess.run(['git', 'rev-parse', '-q', '--verify', 'refs/tags/deployed/stable^{commit}'], text=True, capture_output=True)
    if stable.returncode == 0:
        before = stable.stdout.strip()
        # Not backwards on main (the last release's base, when it was a release branch's) and a higher number than it, or
        # stations and apps would not take it; the same release again is a retry.
        subprocess.run(['git', 'merge-base', '--is-ancestor', output('git', 'merge-base', before, 'origin/main'), base], check=True)
        if before != sha and count(before) >= version:
            raise SystemExit(f'0.1.{version} is not above the last stable release, 0.1.{count(before)}: nothing would update to it.')
    if branch:
        if not runs(sha, branch):
            raise SystemExit(f'No successful pipeline of {branch} at {sha}. Wait for it, or fix it on the branch.')
        return {'sha': sha, 'version': str(version), 'web': 'build'}
    ids = runs(sha, 'main')
    if not ids:
        raise SystemExit('No successful main pipeline for this release. Pick a base whose beta publication finished.')
    for run in ids:
        artifacts = json.loads(output('gh', 'api', f'repos/{REPO}/actions/runs/{run}/artifacts'))['artifacts']
        if any(a['name'] == f'cloud-web-{sha}' and not a['expired'] for a in artifacts):
            return {'sha': sha, 'version': str(version), 'web': 'artifact'}
    return {'sha': sha, 'version': str(version), 'web': 'build'}


if __name__ == '__main__':
    result = plan(os.environ.get('RELEASE_REVISION', '').strip())
    for key, value in result.items():
        print(f'{key}={value}')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as target:
            target.writelines(f'{key}={value}\n' for key, value in result.items())

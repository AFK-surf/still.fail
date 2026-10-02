#!/usr/bin/env python3
"""Resolve one reviewed, successfully beta-tested main revision before any stable publication."""
import json
import os
import re
import subprocess


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def plan(revision=''):
    entries = json.loads(output('node', 'scripts/changelog.ts', '--stable'))
    if not entries:
        raise SystemExit('Write and review the stable release notes first (docs/changelog.md).')
    if revision:
        if not re.fullmatch(r'[0-9a-f]{40}', revision):
            raise SystemExit('revision must be a full commit SHA.')
        sha = output('git', 'rev-parse', '--verify', revision + '^{commit}')
        version = int(output('git', 'rev-list', '--count', sha))
    else:
        version = max(entry['version'] for entry in entries)
        # The notes' commit count is a version, not an index into a possibly merged DAG.
        candidates = output('git', 'log', '--format=%H', 'origin/main', '--', f'docs/releases/0.1.{version}.md').splitlines()
        sha = next((candidate for candidate in candidates if int(output('git', 'rev-list', '--count', candidate)) == version), None)
        if sha is None:
            raise SystemExit('Release notes do not identify a release commit on main.')
    subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'origin/main'], check=True)
    notes = output('git', 'show', f'{sha}:docs/releases/0.1.{version}.md')
    if not re.search(rf'^version:\s*{version}\s*(?:#.*)?$', notes, re.M):
        raise SystemExit('The selected revision does not contain its own release notes.')
    stable = subprocess.run(['git', 'rev-parse', '-q', '--verify', 'refs/tags/deployed/stable^{commit}'], text=True, capture_output=True)
    if stable.returncode == 0:
        subprocess.run(['git', 'merge-base', '--is-ancestor', stable.stdout.strip(), sha], check=True)
    runs = json.loads(output('gh', 'run', 'list', '-R', 'AFK-surf/still.fail', '-w', 'pipeline', '--branch', 'main', '--commit', sha, '--limit', '100', '--json', 'databaseId,conclusion'))
    for run in runs:
        if run['conclusion'] != 'success':
            continue
        artifacts = json.loads(output('gh', 'api', f"repos/AFK-surf/still.fail/actions/runs/{run['databaseId']}/artifacts"))['artifacts']
        if any(a['name'] == f'cloud-web-{sha}' and not a['expired'] for a in artifacts):
            return {'sha': sha, 'version': str(version)}
    raise SystemExit('No successful main pipeline with an unexpired web artifact for this release. Finish its beta publication first.')


if __name__ == '__main__':
    result = plan(os.environ.get('RELEASE_REVISION', '').strip())
    for key, value in result.items():
        print(f'{key}={value}')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as target:
            target.writelines(f'{key}={value}\n' for key, value in result.items())

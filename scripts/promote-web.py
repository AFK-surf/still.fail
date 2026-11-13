#!/usr/bin/env python3
"""Promote the exact deployed beta web artifact from GitHub Actions, without rebuilding.
Run on the deployment machine with gh authentication and the usual Cloudflare credentials.
"""
import argparse
import json
import os
import re
import subprocess
import tempfile
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
# Another cloud's (STILLFAIL_CLOUD, cloud/deploy.py CLOUDS) is a build of its own, its artifact named after it.
CLOUD = os.environ.get('STILLFAIL_CLOUD', '')
ARTIFACT = f'{CLOUD}-cloud-web' if CLOUD else 'cloud-web'

def gh(*args):
    return json.loads(subprocess.check_output(['gh', *args], text=True))

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--revision', help='Promote this successfully released main revision, even if beta has advanced')
args = parser.parse_args()
deployed = None
if args.revision:
    sha = args.revision
else:
    request = urllib.request.Request('https://app.youdid.wtf/build.json', headers={'user-agent': 'stillfail-promote'})
    with urllib.request.urlopen(request, timeout=30) as response:
        deployed = json.load(response)
    sha = deployed.get('revision', '')
if not re.fullmatch(r'[0-9a-f]{40}', sha):
    raise SystemExit('The beta site does not name a full revision; refusing to guess its build.')
runs = gh('run', 'list', '-R', 'AFK-surf/monoid', '-w', 'pipeline', '--branch', 'main', '--commit', sha, '--limit', '20', '--json', 'databaseId,conclusion')
for run in runs:
    if args.revision and run['conclusion'] != 'success':
        continue
    artifacts = gh('api', f"repos/AFK-surf/monoid/actions/runs/{run['databaseId']}/artifacts")['artifacts']
    if not any(a['name'] == f'{ARTIFACT}-{sha}' and not a['expired'] for a in artifacts):
        continue
    with tempfile.TemporaryDirectory(prefix='stillfail-promote-') as directory:
        subprocess.run(['gh', 'run', 'download', str(run['databaseId']), '-R', 'AFK-surf/monoid', '-n', f'{ARTIFACT}-{sha}', '-D', directory], check=True)
        metadata = json.loads((Path(directory) / 'build.json').read_text())
        if metadata.get('revision') != sha or (deployed is not None and metadata != deployed):
            raise SystemExit('Artifact metadata differs from the deployed beta build.')
        subprocess.run(['python3', 'deploy.py', 'promote-web', directory], cwd=REPO / 'cloud', check=True)
    print('Promoted unchanged GitHub artifact:', sha)
    break
else:
    raise SystemExit('No unexpired main artifact matches the deployed beta. Nothing deployed.')

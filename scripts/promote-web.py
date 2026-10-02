#!/usr/bin/env python3
"""Promote the exact deployed beta web artifact from GitHub Actions, without rebuilding.
Run on the deployment machine with gh authentication and the usual Cloudflare credentials.
"""
import json
import re
import subprocess
import tempfile
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

def gh(*args):
    return json.loads(subprocess.check_output(['gh', *args], text=True))

request = urllib.request.Request('https://app.youdid.wtf/build.json', headers={'user-agent': 'stillfail-promote'})
with urllib.request.urlopen(request, timeout=30) as response:
    deployed = json.load(response)
sha = deployed.get('revision', '')
if not re.fullmatch(r'[0-9a-f]{40}', sha):
    raise SystemExit('The beta site does not name a full revision; refusing to guess its build.')
runs = gh('run', 'list', '-R', 'AFK-surf/still.fail', '-w', 'pipeline', '--branch', 'main', '--commit', sha, '--limit', '20', '--json', 'databaseId')
for run in runs:
    artifacts = gh('api', f"repos/AFK-surf/still.fail/actions/runs/{run['databaseId']}/artifacts")['artifacts']
    if not any(a['name'] == f'cloud-web-{sha}' and not a['expired'] for a in artifacts):
        continue
    with tempfile.TemporaryDirectory(prefix='stillfail-promote-') as directory:
        subprocess.run(['gh', 'run', 'download', str(run['databaseId']), '-R', 'AFK-surf/still.fail', '-n', f'cloud-web-{sha}', '-D', directory], check=True)
        if json.loads((Path(directory) / 'build.json').read_text()) != deployed:
            raise SystemExit('Artifact metadata differs from the deployed beta build.')
        subprocess.run(['python3', 'deploy.py', 'promote-web', directory], cwd=REPO / 'cloud', check=True)
    print('Promoted unchanged GitHub artifact:', sha)
    break
else:
    raise SystemExit('No unexpired main artifact matches the deployed beta. Nothing deployed.')

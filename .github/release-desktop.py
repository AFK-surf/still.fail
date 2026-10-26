#!/usr/bin/env python3
"""Build and sign the Mac app on the organization's Mac runner; never publish an unsigned macOS update.

The Mac app is mbui's (apps/mbui) in the Electron app's place (scripts/release.sh desktop: its zip, mbui's feed
mac/latest.json or mac/beta/latest.json and electron-updater's stillfail(-beta)-mac.yml, which moves an installed
Electron app over). The Windows app, mbui's too, is built on GitHub's Windows runner (scripts/release.sh desktop-win):
it signs nothing with Apple's keys."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mac_signing  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--stable', action='store_true', help='Publish the stable channel; defaults to beta')
parser.add_argument('--out', help='Put the signed release in this directory (desktop/…) instead of the bucket: CI puts it once the check passed (scripts/release-put.sh)')
args = parser.parse_args()
suffix = '' if args.stable else '-beta'
root = Path(__file__).resolve().parents[1]

def run(args, **kwargs):
    result = subprocess.run(args, **kwargs)
    if result.returncode:
        raise SystemExit('Desktop release step failed: ' + args[0])
    return result

# The signing keychain (mac_signing.py: AFK's Developer ID and notary profile) is on the user's search list, which
# mini1's jobs share, only under the lock it holds until the keychain is gone.
with mac_signing.keychain() as opened, \
        tempfile.TemporaryDirectory(prefix='stillfail-release-', dir=os.environ.get('RUNNER_TEMP')) as directory:
    if not args.out and not os.environ.get('CLOUDFLARE_API_TOKEN'):
        raise SystemExit('CLOUDFLARE_API_TOKEN is required')
    for folder in (root, *(() if args.out else (root / 'cloud',))):
        run(['pnpm', 'install', '--frozen-lockfile', '--prefer-offline'], cwd=folder)
    env = mac_signing.signing_env(opened)
    env.pop('UNSIGNED', None)
    if env.get('POSTHOG_JSON'):
        posthog = Path(directory) / 'posthog.json'
        posthog.write_text(env['POSTHOG_JSON'])
        posthog.chmod(0o600)
        env['STILLFAIL_POSTHOG'] = str(posthog)
    env['RELEASE_DIR'] = str(Path(directory) / 'releases')
    # (release.sh checks the app it made before it puts it: verified, the Electron app's id, still.fail's team.
    # Signed with a Developer ID it is notarized, not stapled: apps/mbui/scripts/mac-app.sh)
    run(['sh', 'scripts/release.sh', *([] if args.stable else ['--beta']), 'desktop'], cwd=root, env=env)
    version = subprocess.check_output(['git', 'rev-list', '--count', 'HEAD'], cwd=root, text=True).strip()
    archive = f'desktop/stillfail{suffix}-0.1.{version}-arm64-mac.zip'
    files = (
        # The Mac app's zip, then its feeds: mbui's own updater's and electron-updater's (an installed Electron app's).
        (archive, 'application/zip'), (f'mac/{"" if args.stable else "beta/"}latest.json', 'application/json'),
        (f'desktop/stillfail{suffix}-mac.yml', 'text/yaml; charset=utf-8'),
    )
    for name, mime in files:
        path = Path(env['RELEASE_DIR']) / name
        if not path.is_file(): raise SystemExit('Expected desktop artifact missing: ' + name)
        if args.out:
            (Path(args.out) / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, Path(args.out) / name)
            continue
        put = ['pnpm', 'exec', 'wrangler', 'r2', 'object', 'put', 'stillfail-releases/' + name, '--file', str(path), '--content-type', mime, '--remote']
        # Cloudflare's API fails now and then on the way (a 502, "fetch failed"): put again, twice at most.
        for attempt in range(3):
            if subprocess.run(put, cwd=root / 'cloud', env=env).returncode == 0:
                break
            if attempt == 2:
                raise SystemExit('Desktop release step failed: uploading ' + name)
            print(f'uploading {name} failed (try {attempt + 1}), trying again', flush=True)
            time.sleep(15)

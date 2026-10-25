#!/usr/bin/env python3
"""Build and sign on the organization's Mac runner; never publish an unsigned macOS update.

The Mac app is mbui's (apps/mbui) in the Electron app's place (scripts/release.sh desktop: its zip, mbui's feed
mac/latest.json or mac/beta/latest.json and electron-updater's stillfail(-beta)-mac.yml, which moves an installed
Electron app over), the beta's since 2026-10-26, the stable one's after it. The Windows app is Electron's still
(apps/desktop/build.sh --win, from the Mac), not signed yet: no Windows code-signing certificate has been provisioned,
and an unsigned installer only makes SmartScreen warn on its first run."""
import argparse
import contextlib
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
parser.add_argument('--put-mac-early', action='store_true', help='With --out: put the Mac archive (named by its version, nothing points at it yet) in the bucket while the Windows app builds, and leave it out of --out')
parser.add_argument('--only', choices=('mac', 'win'), help="Build one of the two apps: CI builds them side by side, in jobs of their own (the Windows one needs no Apple certificate)")
args = parser.parse_args()
mac = args.only != 'win'
win = args.only != 'mac'
suffix = '' if args.stable else '-beta'
root = Path(__file__).resolve().parents[1]

def run(args, **kwargs):
    result = subprocess.run(args, **kwargs)
    if result.returncode:
        raise SystemExit('Desktop release step failed: ' + args[0])
    return result

# The signing keychain (mac_signing.py: AFK's Developer ID and notary profile) is on the user's search list, which
# mini1's jobs share, only under the lock it holds until the keychain is gone. The Windows app alone signs nothing with
# Apple's keychain: it neither waits for the lock nor touches the list.
with mac_signing.keychain() if mac else contextlib.nullcontext() as opened, \
        tempfile.TemporaryDirectory(prefix='stillfail-release-', dir=os.environ.get('RUNNER_TEMP')) as directory:
    if not args.out and not os.environ.get('CLOUDFLARE_API_TOKEN'):
        raise SystemExit('CLOUDFLARE_API_TOKEN is required')
    early = args.out and args.put_mac_early and mac and win
    if early and not os.environ.get('CLOUDFLARE_API_TOKEN'):
        raise SystemExit('--put-mac-early needs CLOUDFLARE_API_TOKEN')
    for folder in (root, *(() if args.out and not early else (root / 'cloud',)), *((root / 'apps/desktop',) if win else ())):
        run(['pnpm', 'install', '--frozen-lockfile', '--prefer-offline'], cwd=folder)
    env = mac_signing.signing_env(opened) if mac else dict(os.environ)
    env.pop('UNSIGNED', None)
    if env.get('POSTHOG_JSON'):
        posthog = Path(directory) / 'posthog.json'
        posthog.write_text(env['POSTHOG_JSON'])
        posthog.chmod(0o600)
        env['STILLFAIL_POSTHOG'] = str(posthog)
    env['RELEASE_DIR'] = str(Path(directory) / 'releases')
    if mac:
        # (release.sh checks the app it made before it puts it: verified, the Electron app's id, still.fail's team.
        # Signed with a Developer ID it is notarized, not stapled: apps/mbui/scripts/mac-app.sh)
        run(['sh', 'scripts/release.sh', *([] if args.stable else ['--beta']), 'desktop'], cwd=root, env=env)
    version = subprocess.check_output(['git', 'rev-list', '--count', 'HEAD'], cwd=root, text=True).strip()
    archive = f'desktop/stillfail{suffix}-0.1.{version}-arm64-mac.zip'
    installer = f'desktop/stillfail{suffix}-0.1.{version}-x64-win.exe'
    # mini1's line is the slow part of putting them (~5 MB/s, 2026-10-16: a 141 MB archive and a 127 MB installer
    # took 63 s after both were built): the archive goes up while the Windows app builds (~35 s).
    putting = None
    if early:
        (Path(directory) / 'early/desktop').mkdir(parents=True)
        shutil.copy2(Path(env['RELEASE_DIR']) / archive, Path(directory) / 'early' / archive)
        putting = subprocess.Popen(['sh', 'scripts/release-put.sh', '--files', str(Path(directory) / 'early')], cwd=root, env=env)
    if win:
        run(['sh', 'scripts/release.sh', *([] if args.stable else ['--beta']), 'desktop-win'], cwd=root, env=env)
    files = (
        # The Mac app's zip, then its feeds: mbui's own updater's and electron-updater's (an installed Electron app's).
        *(((archive, 'application/zip'), (f'mac/{"" if args.stable else "beta/"}latest.json', 'application/json'),
           (f'desktop/stillfail{suffix}-mac.yml', 'text/yaml; charset=utf-8')) if mac else ()),
        *(((installer, 'application/vnd.microsoft.portable-executable'), (installer + '.blockmap', 'application/octet-stream'),
           # Its signature (scripts/release-sign.ts), which the app checks before installing it: before the feed.
           (installer + '.sig', 'application/json'), (f'desktop/stillfail{suffix}.yml', 'text/yaml; charset=utf-8')) if win else ()),
    )
    for name, mime in files:
        path = Path(env['RELEASE_DIR']) / name
        # Unsigned only outside CI, without RELEASE_SIGNING_KEY (release-sign.ts refuses that in CI).
        if name.endswith('.sig') and not path.is_file() and not os.environ.get('CI'): continue
        if not path.is_file(): raise SystemExit('Expected desktop artifact missing: ' + name)
        if args.out:
            if putting and name == archive: continue
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
    if putting and putting.wait():
        raise SystemExit('Desktop release step failed: putting the Mac archive')

#!/usr/bin/env python3
"""Build and sign on the organization's Mac runner; never publish an unsigned update."""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import shlex
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--stable', action='store_true', help='Publish the stable channel; defaults to beta')
parser.add_argument('--out', help='Put the signed release in this directory (desktop/…) instead of the bucket: CI puts it once the check passed (scripts/release-put.sh)')
args = parser.parse_args()
suffix = '' if args.stable else '-beta'
root = Path(__file__).resolve().parents[1]
identity = json.loads((root / 'apps/desktop/package.json').read_text())['build']['mac']['identity']

def run(args, **kwargs):
    result = subprocess.run(args, **kwargs)
    if result.returncode:
        raise SystemExit('Desktop release step failed: ' + args[0])
    return result

previous = shlex.split(subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True))
with tempfile.TemporaryDirectory(prefix='stillfail-signing-', dir=os.environ.get('RUNNER_TEMP')) as directory:
    keychain = str(Path(directory) / 'signing.keychain-db')
    imported = False
    try:
        certificate = os.environ.get('MACOS_SIGNING_CERTIFICATE_B64')
        if certificate:
            password = os.environ.get('MACOS_SIGNING_CERTIFICATE_PASSWORD')
            if not password:
                raise SystemExit('MACOS_SIGNING_CERTIFICATE_PASSWORD is required')
            path = Path(directory) / 'certificate.p12'
            path.write_bytes(base64.b64decode(''.join(certificate.split()), validate=True))
            path.chmod(0o600)
            keypass = secrets.token_urlsafe(48)
            run(['security', 'create-keychain', '-p', keypass, keychain])
            imported = True
            run(['security', 'set-keychain-settings', '-lut', '21600', keychain])
            run(['security', 'unlock-keychain', '-p', keypass, keychain])
            run(['security', 'import', str(path), '-k', keychain, '-P', password, '-T', '/usr/bin/codesign'], stdout=subprocess.DEVNULL)
            run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-k', keypass, keychain], stdout=subprocess.DEVNULL)
            run(['security', 'list-keychains', '-d', 'user', '-s', keychain, *previous])
            path.unlink()
        elif os.environ.get('KEYCHAIN_PASSWORD_AFK'):
            run(['security', 'unlock-keychain', '-p', os.environ['KEYCHAIN_PASSWORD_AFK'], str(Path.home() / 'Library/Keychains/login.keychain-db')])
        identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
        if identity not in identities:
            raise SystemExit('Existing still.fail signing identity is missing. Provision MACOS_SIGNING_CERTIFICATE_B64 and MACOS_SIGNING_CERTIFICATE_PASSWORD in production; no unsigned replacement was published.')
        if not args.out and not os.environ.get('CLOUDFLARE_API_TOKEN'):
            raise SystemExit('CLOUDFLARE_API_TOKEN is required')
        for folder in (root, *(() if args.out else (root / 'cloud',)), root / 'apps/desktop'):
            run(['pnpm', 'install', '--frozen-lockfile', '--prefer-offline'], cwd=folder)
        env = dict(os.environ)
        env.pop('UNSIGNED', None)
        if env.get('POSTHOG_JSON'):
            posthog = Path(directory) / 'posthog.json'
            posthog.write_text(env['POSTHOG_JSON'])
            posthog.chmod(0o600)
            env['STILLFAIL_POSTHOG'] = str(posthog)
        env['RELEASE_DIR'] = str(Path(directory) / 'releases')
        run(['sh', 'scripts/release.sh', *([] if args.stable else ['--beta']), 'desktop'], cwd=root, env=env)
        run(['codesign', '--verify', '--deep', '--strict', str(root / 'apps/desktop/out/mac-arm64' / ('still.fail.app' if args.stable else 'youdid.wtf.app'))])
        version = subprocess.check_output(['git', 'rev-list', '--count', 'HEAD'], cwd=root, text=True).strip()
        archive = f'stillfail{suffix}-0.1.{version}-arm64-mac.zip'
        for name, mime in ((archive, 'application/zip'), (archive + '.blockmap', 'application/octet-stream'), (f'stillfail{suffix}-mac.yml', 'text/yaml; charset=utf-8')):
            path = Path(env['RELEASE_DIR']) / 'desktop' / name
            if not path.is_file(): raise SystemExit('Expected desktop artifact missing: ' + name)
            if args.out:
                (Path(args.out) / 'desktop').mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, Path(args.out) / 'desktop' / name)
                continue
            put = ['pnpm', 'exec', 'wrangler', 'r2', 'object', 'put', 'stillfail-releases/desktop/' + name, '--file', str(path), '--content-type', mime, '--remote']
            # Cloudflare's API fails now and then on the way (a 502, "fetch failed"): put again, twice at most.
            for attempt in range(3):
                if subprocess.run(put, cwd=root / 'cloud', env=env).returncode == 0:
                    break
                if attempt == 2:
                    raise SystemExit('Desktop release step failed: uploading ' + name)
                print(f'uploading {name} failed (try {attempt + 1}), trying again', flush=True)
                time.sleep(15)
    finally:
        if imported:
            subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *previous], stdout=subprocess.DEVNULL)
            subprocess.run(['security', 'delete-keychain', keychain], stdout=subprocess.DEVNULL)

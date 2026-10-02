#!/usr/bin/env python3
"""Copy the old R2 bucket into stillfail-releases without deleting any source objects.

Default: inventory only. --copy creates the target if needed, streams every object,
checks SHA-256 and metadata, and writes a private report. --verify-only rechecks
without writing. Run a final pass after old uploaders have stopped, before cutover.
Uses a loopback-only Wrangler process with remote bindings, never a public endpoint.
"""
import argparse
import json
import os
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
import deploy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--copy', action='store_true')
    modes.add_argument('--verify-only', action='store_true')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    account = deploy.account_id()
    auth = json.loads(deploy.wrangler('auth', 'token', '--json', capture=True))
    headers = {'user-agent': 'stillfail-resource-migration', 'content-type': 'application/json'}
    if auth.get('type') == 'api_key':
        headers.update({'x-auth-key': auth['key'], 'x-auth-email': auth['email']})
    else:
        headers['authorization'] = 'Bearer ' + auth['token']

    def api(path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(f'https://api.cloudflare.com/client/v4/accounts/{account}/{path}', headers=headers, data=data)
        with urllib.request.urlopen(req, timeout=60) as response:
            value = json.load(response)
        if not value.get('success'): raise RuntimeError('Cloudflare resource request failed')
        return value['result']

    buckets = {b['name'] for b in api('r2/buckets')['buckets']}
    if 'ember-releases' not in buckets: raise RuntimeError('source bucket is missing')
    if 'stillfail-releases' not in buckets:
        if args.copy: api('r2/buckets', {'name': 'stillfail-releases'})
        elif args.verify_only: raise RuntimeError('target bucket is missing')
    token = secrets.token_urlsafe(32)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix='stillfail-r2-migration-') as directory:
        root = Path(directory)
        config = root / 'wrangler.json'
        bindings = [{'binding': 'SOURCE', 'bucket_name': 'ember-releases', 'remote': True}]
        # Inventory does not need a target and must not create one.
        if args.copy or args.verify_only:
            bindings.append({'binding': 'TARGET', 'bucket_name': 'stillfail-releases', 'remote': True})
        deploy.write_private(config, {
            'name': 'stillfail-r2-migration', 'main': str(deploy.ROOT / 'migrations/release-bucket.ts'),
            'account_id': account, 'compatibility_date': '2026-09-08', 'compatibility_flags': ['nodejs_compat'],
            'workers_dev': False, 'r2_buckets': bindings, 'vars': {'MIGRATION_TOKEN': token},
        })
        logpath = root / 'wrangler.log'
        with logpath.open('w') as log:
            os.chmod(logpath, 0o600)
            child = subprocess.Popen(['pnpm', 'exec', 'wrangler', 'dev', '--config', str(config), '--ip', '127.0.0.1', '--port', str(port)], cwd=deploy.ROOT, stdout=log, stderr=log, start_new_session=True)
            try:
                def call(path, body=None):
                    data = None if body is None else json.dumps(body).encode()
                    req = urllib.request.Request(f'http://127.0.0.1:{port}{path}', data=data, headers={'authorization': f'Bearer {token}', 'content-type': 'application/json'})
                    try:
                        with urllib.request.urlopen(req, timeout=600) as response: return json.load(response)
                    except urllib.error.HTTPError as error:
                        raise RuntimeError(f"migration proxy HTTP {error.code}: {error.read(2000).decode(errors='replace')}") from None
                for attempt in range(90):
                    if child.poll() is not None: raise RuntimeError('Wrangler migration proxy exited; no cutover performed')
                    try:
                        page = call('/list')
                        break
                    except (OSError, ValueError): time.sleep(1)
                else: raise RuntimeError('Wrangler migration proxy did not become ready')
                report = {'source': 'ember-releases', 'target': 'stillfail-releases', 'mode': 'copy' if args.copy else 'verify' if args.verify_only else 'inventory', 'complete': False, 'objects': []}
                while True:
                    for obj in page['objects']:
                        if args.copy or args.verify_only:
                            obj = call('/copy', {'key': obj['key'], 'etag': obj['etag'], 'verifyOnly': args.verify_only})
                        report['objects'].append(obj)
                        deploy.write_private(args.report, report)
                        if len(report['objects']) % 25 == 0: print('verified objects:', len(report['objects']), flush=True)
                    if not page.get('cursor'): break
                    from urllib.parse import quote
                    page = call('/list?cursor=' + quote(page['cursor'], safe=''))
                report['complete'] = True
                deploy.write_private(args.report, report)
                print(f"{report['mode']}: {len(report['objects'])} objects, {sum(o['size'] for o in report['objects'])} bytes; report {args.report}", flush=True)
            finally:
                import signal
                try: os.killpg(child.pid, signal.SIGTERM)
                except ProcessLookupError: pass
                try: child.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()


if __name__ == '__main__': main()

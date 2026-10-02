#!/usr/bin/env python3
"""Prepare an existing stateful Worker under its stillfail name without changing routes.

Dry-run unless --apply. Transfers existing Durable Object namespaces (never creates
empty replacements), seeds the existing secrets before the transfer, and verifies
namespace IDs afterward. Old bindings continue forwarding to the same namespaces.
Keep the private report for cutover/rollback; do not delete either Worker here.
https://developers.cloudflare.com/durable-objects/reference/durable-object-class-migrations-legacy/
"""
import argparse
import json
import tempfile
import urllib.request
from pathlib import Path
import deploy

CLASSES = {'api': ['Account', 'Directory', 'LoginAttempt', 'LoginLimiter', 'TelemetryLimiter'], 'relay': ['Relay', 'RelayBudget']}
NAMES = {'api': ('ember-cloud', 'stillfail-cloud'), 'relay': ('ember-relay', 'stillfail-relay')}


def transfer_config(template, part, account):
    old, new = NAMES[part]
    config = {**template, 'name': new, 'account_id': account, 'routes': [], 'workers_dev': False, 'preview_urls': False}
    config['main'] = str(deploy.ROOT / template['main'])
    config['migrations'] = [{'tag': 'stillfail-v1', 'transferred_classes': [{'from': name, 'from_script': old, 'to': name} for name in CLASSES[part]]}]
    if 'containers' in config:
        config['containers'] = [{**c, 'image': str(deploy.ROOT / c['image'])} for c in config['containers']]
    return config


def without_containers(config):
    return {k: v for k, v in config.items() if k != 'containers'}


def relay_container(applications, namespaces):
    matches = [a for a in applications if a.get('durable_objects', {}).get('namespace_id') == namespaces['Relay']]
    if len(matches) != 1:
        raise RuntimeError('expected exactly one existing relay container application; no replacement will be created')
    return {k: matches[0][k] for k in ('id', 'name')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('part', choices=CLASSES)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    account = deploy.account_id()
    auth = json.loads(deploy.wrangler('auth', 'token', '--json', capture=True))
    headers = {'user-agent': 'stillfail-worker-migration'}
    if auth.get('type') == 'api_key': headers.update({'x-auth-key': auth['key'], 'x-auth-email': auth['email']})
    else: headers['authorization'] = 'Bearer ' + auth['token']
    def get(path):
        req = urllib.request.Request(f'https://api.cloudflare.com/client/v4/accounts/{account}/{path}', headers=headers)
        with urllib.request.urlopen(req, timeout=60) as response: value = json.load(response)
        if not value.get('success'): raise RuntimeError('Cloudflare inventory failed')
        return value['result']
    old, new = NAMES[args.part]
    namespaces = get('workers/durable_objects/namespaces')
    source = {n['class']: n['id'] for n in namespaces if n['script'] == old}
    target = {n['class']: n['id'] for n in namespaces if n['script'] == new}
    saved = json.loads(args.report.read_text()) if args.report.exists() else None
    if target:
        if not args.report.exists(): raise RuntimeError('target namespaces already exist without this migration report; refusing to guess')
        if target != saved['namespaces']: raise RuntimeError('target namespace IDs differ from the recorded source')
        if saved.get('prepared'):
            print('already transferred and verified', new)
            return
        source = target  # Resume container attachment after a successful transfer.
    if set(source) != set(CLASSES[args.part]): raise RuntimeError('unexpected source namespace inventory; no changes made')
    if not deploy.KEYS.exists(): raise RuntimeError('existing deployment keys are required; never generate new keys for a migration')
    secrets = deploy.keys()
    config = transfer_config(deploy.read_template(deploy.PARTS[args.part]), args.part, account)
    if args.part == 'api':
        oauth = json.loads((deploy.DEPLOY / 'google-oauth.json').read_text())['web']
        config['vars'] = {**config['vars'], 'GOOGLE_CLIENT_ID': oauth['client_id']}
        secrets = {**secrets, 'GOOGLE_CLIENT_SECRET': oauth['client_secret'], **deploy.axiom(), **deploy.push()}
        jwk = json.loads(secrets['GRANT_SIGNING_JWK'])
        req = urllib.request.Request(config['vars']['PUBLIC_ORIGIN'] + '/.well-known/stillfail-grant-keys', headers={'user-agent': 'stillfail-worker-migration'})
        with urllib.request.urlopen(req, timeout=30) as response: deployed_keys = json.load(response)['keys']
        if not any(k.get('x') == jwk['x'] for k in deployed_keys): raise RuntimeError('local grant signing key differs from the live key')
    else: secrets = {'ADMIN_TOKEN': secrets['ADMIN_TOKEN']}
    containers = get('containers/applications') if args.part == 'relay' else []
    container = relay_container(containers, source) if args.part == 'relay' else None
    if container:
        config['containers'] = [{**c, 'name': container['name']} for c in config['containers']]
    report = {'source': old, 'target': new, 'namespaces': source, 'prepared': False, 'routesChanged': False}
    if container: report['container'] = container
    if not args.apply:
        print(json.dumps({'target': new, 'transferClasses': sorted(source), 'routes': [], 'signingKeys': 'existing'}, indent=2))
        return
    deploy.write_private(args.report, report)
    with tempfile.TemporaryDirectory(prefix='stillfail-worker-migration-') as directory:
        root = Path(directory)
        bootstrap = root / 'bootstrap.js'
        bootstrap.write_text('export default { fetch() { return new Response("migration not routed", {status:503}); } };')
        bootstrap_config = root / 'bootstrap.json'
        deploy.write_private(bootstrap_config, {'name': new, 'account_id': account, 'main': str(bootstrap), 'compatibility_date': '2026-09-08', 'workers_dev': False, 'preview_urls': False, 'routes': []})
        scripts = {s['id'] for s in get('workers/scripts')}
        if new not in scripts: deploy.wrangler('deploy', '--config', str(bootstrap_config), capture=True)
        secret_file = root / 'secrets.json'
        deploy.write_private(secret_file, secrets)
        # Secrets arrive while the target has no routes or Durable Objects.
        deploy.wrangler('secret', 'bulk', str(secret_file), '--config', str(bootstrap_config), capture=True)
        real_config = root / 'transfer.json'
        deploy.write_private(real_config, config)
        if args.part == 'relay':
            # Cloudflare validates container storage before applying transferred_classes.
            # Transfer first, then attach the SAME application to its unchanged namespace.
            if not target:
                deploy.write_private(real_config, without_containers(config))
                deploy.wrangler('deploy', '--config', str(real_config), capture=True)
                moved = {n['class']: n['id'] for n in get('workers/durable_objects/namespaces') if n['script'] == new}
                if moved != source: raise RuntimeError('relay transfer IDs differ; refusing container attachment')
            deploy.write_private(real_config, config)
            with deploy.docker_env() as env:
                deploy.wrangler('deploy', '--config', str(real_config), '--containers-rollout', 'immediate', env=env, capture=True)
        else: deploy.wrangler('deploy', '--config', str(real_config), capture=True)
    after = {n['class']: n['id'] for n in get('workers/durable_objects/namespaces') if n['script'] == new}
    if after != source: raise RuntimeError('namespace verification failed; routes have not been changed')
    if container and relay_container(get('containers/applications'), source) != container:
        raise RuntimeError('container application identity changed; routes have not been changed')
    report['prepared'] = True
    deploy.write_private(args.report, report)
    print('prepared', new, 'with', len(after), 'unchanged namespace IDs; routes unchanged')


if __name__ == '__main__': main()

#!/usr/bin/env python3
"""Move existing API/relay route IDs to a prepared Worker. Dry-run unless --apply.
--rollback routes back to the preserved former Worker; transferred namespaces keep
forwarding to the same data. Never deploy the former namespace configuration again.
"""
import argparse
import importlib.util
import json
import urllib.parse
import urllib.request
from pathlib import Path
import deploy

spec = importlib.util.spec_from_file_location('migration', Path(__file__).with_name('migrate-workers.py'))
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('part', choices=migration.CLASSES)
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--apply', action='store_true')
    p.add_argument('--rollback', action='store_true')
    args = p.parse_args()
    state = json.loads(args.report.read_text())
    old, new = migration.NAMES[args.part]
    if not state.get('prepared') or state['source'] != old or state['target'] != new: raise RuntimeError('matching completed transfer report required')
    account = deploy.account_id()
    auth = json.loads(deploy.wrangler('auth', 'token', '--json', capture=True))
    headers = {'user-agent': 'stillfail-worker-cutover', 'content-type': 'application/json'}
    if auth.get('type') == 'api_key': headers.update({'x-auth-key': auth['key'], 'x-auth-email': auth['email']})
    else: headers['authorization'] = 'Bearer ' + auth['token']
    def api(path, body=None):
        req = urllib.request.Request('https://api.cloudflare.com/client/v4/' + path, headers=headers, data=None if body is None else json.dumps(body).encode(), method='GET' if body is None else 'PUT')
        with urllib.request.urlopen(req, timeout=60) as response: result = json.load(response)
        if not result.get('success'): raise RuntimeError('Cloudflare route operation failed')
        return result['result']
    namespaces = {n['class']: n['id'] for n in api(f'accounts/{account}/workers/durable_objects/namespaces') if n['script'] == new}
    if namespaces != state['namespaces']: raise RuntimeError('namespace identity changed; refusing cutover')
    template = deploy.read_template(deploy.PARTS[args.part])
    zones = {}
    moves = []
    for route in template['routes']:
        name = route['zone_name']
        if name not in zones:
            found = api('zones?name=' + urllib.parse.quote(name) + '&account.id=' + account)
            if len(found) != 1: raise RuntimeError('required route zone not found: ' + name)
            zone = found[0]['id']
            zones[name] = (zone, api(f'zones/{zone}/workers/routes'))
        zone, routes = zones[name]
        current = next((r for r in routes if r['pattern'] == route['pattern']), None)
        if not current or current.get('script') not in (old, new): raise RuntimeError('route is missing or belongs to another Worker: ' + route['pattern'])
        moves.append({'zone': zone, 'id': current['id'], 'pattern': current['pattern'], 'before': current['script'], 'after': old if args.rollback else new})
    if not args.apply:
        print(json.dumps({'routes': len(moves), 'target': old if args.rollback else new, 'namespaceIds': 'verified'}, indent=2))
        return
    state['routePlan'] = moves
    deploy.write_private(args.report, state)
    for move in moves:
        if move['before'] != move['after']:
            api(f"zones/{move['zone']}/workers/routes/{move['id']}", {'pattern': move['pattern'], 'script': move['after']})
    # Confirm the actual route table before marking completion.
    for zone, _ in zones.values():
        actual = {r['id']: r for r in api(f'zones/{zone}/workers/routes')}
        for move in (m for m in moves if m['zone'] == zone):
            if actual.get(move['id'], {}).get('script') != move['after']: raise RuntimeError('route cutover verification failed')
    state['routesChanged'] = not args.rollback
    deploy.write_private(args.report, state)
    print('verified', len(moves), 'routes to', old if args.rollback else new)


if __name__ == '__main__': main()

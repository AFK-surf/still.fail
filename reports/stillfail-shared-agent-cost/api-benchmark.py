#!/usr/bin/env python3
"""Real Anthropic Messages cache experiment; stdlib only. No network without --run.
Prices must be explicitly supplied from a checked official price page; no defaults.
"""
import argparse
import concurrent.futures
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
API = 'https://api.anthropic.com/v1/'
FILES = ['README.md', 'station/src/agents/instructions.ts', 'client/core-ts/src/cache-policy.ts']
TASK_COMMIT = '5e42d56b8e3c99a6a0856e61e6d064cc2c2b99d7'
FIELDS = ['id', 'group', 'n', 'phase', 'model', 'prefix_sha256', 'input_tokens',
          'cache_creation_input_tokens', 'cache_read_input_tokens', 'output_tokens',
          'token_hit_ratio', 'ttft_seconds', 'elapsed_seconds', 'usd', 'request_id', 'error']


def dump(path, obj):
    Path(path).write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n')


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args]).decode()


def request(endpoint, body):
    req = urllib.request.Request(API + endpoint, json.dumps(body).encode(), {
        'x-api-key': os.environ['ANTHROPIC_API_KEY'], 'anthropic-version': '2023-06-01',
        'content-type': 'application/json', 'accept': 'text/event-stream' if body.get('stream') else 'application/json'})
    # Deliberately no retries: failed/partial requests may already have been billed.
    return urllib.request.urlopen(req, timeout=120)


def worker(spec_path):
    spec = json.loads(Path(spec_path).read_text())
    start = time.perf_counter()
    result = {'id': spec['id'], 'events': [], 'usage': {}, 'ttft_seconds': None}
    try:
        with request('messages', spec['body']) as response:
            result['request_id'] = response.headers.get('request-id', '')
            event_lines = []
            for raw in response:
                line = raw.decode().rstrip('\r\n')
                if line:
                    if line.startswith('data:'):
                        event_lines.append(line[5:].lstrip())
                    continue
                if not event_lines:
                    continue
                event = json.loads('\n'.join(event_lines))
                event_lines = []
                result['events'].append(event)
                if event['type'] == 'message_start':
                    result['model'] = event['message']['model']
                    result['usage'].update(event['message']['usage'])
                if event['type'] == 'message_delta':
                    result['usage'].update(event.get('usage', {}))
                if event['type'] == 'content_block_delta' and event.get('delta', {}).get('type') == 'text_delta':
                    if result['ttft_seconds'] is None:
                        result['ttft_seconds'] = time.perf_counter() - start
                if event['type'] == 'error':
                    raise RuntimeError(json.dumps(event['error']))
            if not result['events'] or result['events'][-1]['type'] != 'message_stop':
                raise RuntimeError('Incomplete SSE stream; possible billed partial request. Stop and reconcile.')
            for field in ['input_tokens', 'output_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens']:
                if field not in result['usage']:
                    raise RuntimeError('Missing usage field: ' + field)
    except Exception as exc:
        result['error'] = str(exc)
    result['elapsed_seconds'] = time.perf_counter() - start
    dump(spec['result_path'], result)
    return 1 if result.get('error') else 0


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run', action='store_true', help='Allow real, billed API calls')
    p.add_argument('--model', default='claude-haiku-4-5-20251001')
    p.add_argument('--prices', type=Path, help='JSON: model,input,write_5m,read,output (USD/M tokens),source,checked')
    p.add_argument('--out', type=Path, default=Path('api-benchmark-results'))
    p.add_argument('--budget', type=float, default=3.0)
    p.add_argument('--min-cache-tokens', type=int, default=4096, help='Verify minimum for chosen model in official docs')
    p.add_argument('--ttl-seconds', type=int, default=310)
    p.add_argument('--worker', type=Path, help=argparse.SUPPRESS)
    a = p.parse_args()
    if a.worker:
        return worker(a.worker)
    if not 0 < a.budget <= 3 or a.ttl_seconds < 301 or a.min_cache_tokens <= 0:
        p.error('Require 0 < budget <= 3, ttl-seconds >= 301 and min-cache-tokens > 0')
    rev = git('rev-parse', 'HEAD').strip()
    task = git('show', '-s', '--format=%s%n%b', TASK_COMMIT).strip()
    # Original repository documentation is the system prompt; original source is user context.
    source = {path: git('show', f'{rev}:{path}') for path in FILES}
    context = '\n'.join(f'<source path="{path}">\n{source[path]}</source>' for path in FILES[1:])
    if not a.run:
        print('OFFLINE ONLY: no API calls. Workload files verified at ' + rev)
        print('Task is verbatim git commit subject/body: ' + TASK_COMMIT)
        print('Use --run --prices verified-prices.json with ANTHROPIC_API_KEY to execute A/B/C + TTL.')
        return 0
    if not os.environ.get('ANTHROPIC_API_KEY'):
        p.error('ANTHROPIC_API_KEY missing; Claude subscription login is not an API billing credential')
    if not a.prices:
        p.error('--prices is required: supply verified current official USD/M-token rates')
    prices = json.loads(a.prices.read_text())
    for key in ['input', 'write_5m', 'read', 'output']:
        if not isinstance(prices.get(key), (int, float)) or not 0 < prices[key] < 1000:
            p.error('Invalid price: ' + key)
    if prices.get('model') != a.model or not prices.get('checked') or not str(prices.get('source', '')).startswith('https://'):
        p.error('Pricing requires matching model, checked date and official source URL')
    # An output directory is never reused, preventing accidental overwrites/replays.
    a.out.mkdir(parents=True, exist_ok=False)
    dump(a.out / 'prices.json', prices)
    (a.out / 'system.txt').write_text(source['README.md'])
    (a.out / 'context.txt').write_text(context)
    (a.out / 'task.txt').write_text(task)
    run_id = uuid.uuid4().hex
    manifest = {'status': 'running', 'revision': rev, 'run_id': run_id, 'model': a.model,
                'task_commit': TASK_COMMIT, 'files': {k: hashlib.sha256(v.encode()).hexdigest() for k, v in source.items()},
                'budget_usd': a.budget, 'prices': prices, 'ttft_definition': 'first text_delta, measured from request start',
                'warning': 'USD is usage × supplied list prices, not an invoice. No retries; failures require billing reconciliation.'}
    dump(a.out / 'manifest.json', manifest)
    rows = []
    spent = 0.0

    def body(prefix):
        return {'model': a.model, 'max_tokens': 128, 'stream': True,
                'system': [{'type': 'text', 'text': prefix + source['README.md']}],
                'messages': [{'role': 'user', 'content': [
                    {'type': 'text', 'text': context, 'cache_control': {'type': 'ephemeral', 'ttl': '5m'}},
                    {'type': 'text', 'text': task}]}]}

    def batch(group, n, phase, prefixes, parallel=False):
        nonlocal spent
        specs = []
        reserves = []
        for prefix in prefixes:
            ident = f'{len(rows) + len(specs):03d}-{group}-{n}-{phase}'
            payload = body(prefix)
            counting = {k: v for k, v in payload.items() if k not in ('stream', 'max_tokens')}
            with request('messages/count_tokens', counting) as response:
                counted = json.load(response)
            dump(a.out / f'{ident}.count.json', counted)
            tokens = counted['input_tokens']
            if tokens < a.min_cache_tokens + 128:
                raise RuntimeError('Prefix may be below cache minimum; extend real source context before running')
            # Reserve the full input at the highest possible rate, even for expected hits.
            # Margin guards count_tokens approximation; this is a guard, not a billing result.
            reserve = ((tokens * 1.1 + 1024) * max(prices['input'], prices['write_5m'], prices['read']) + 128 * prices['output']) / 1e6
            reserves.append(reserve)
            spec = {'id': ident, 'body': payload, 'result_path': str((a.out / f'{ident}.raw.json').resolve())}
            dump(a.out / f'{ident}.request.json', spec)
            specs.append(spec)
        if spent + sum(reserves) > a.budget:
            raise RuntimeError('Budget guard stopped BEFORE this batch; earlier requests remain recorded')

        def launch(spec):
            # Fresh OS process for EVERY request; C starts N of them concurrently.
            return subprocess.run([sys.executable, str(Path(__file__).resolve()), '--worker',
                                   str((a.out / (spec['id'] + '.request.json')).resolve())], check=False).returncode
        if parallel:
            with concurrent.futures.ThreadPoolExecutor(max_workers=n) as pool:
                list(pool.map(launch, specs))
        else:
            for spec in specs:
                if launch(spec):
                    break
        failed = False
        for spec in specs:
            raw_path = Path(spec['result_path'])
            if not raw_path.exists():
                continue
            raw = json.loads(raw_path.read_text())
            usage = raw['usage']
            value = sum(usage.get(k, 0) * prices[rate] for k, rate in [
                ('input_tokens', 'input'), ('cache_creation_input_tokens', 'write_5m'),
                ('cache_read_input_tokens', 'read'), ('output_tokens', 'output')]) / 1e6
            spent += value
            total = sum(usage.get(k, 0) for k in ['input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens'])
            prefix_data = {'system': spec['body']['system'], 'context': spec['body']['messages'][0]['content'][0]}
            row = {'id': spec['id'], 'group': group, 'n': n, 'phase': phase, 'model': raw.get('model', a.model),
                   'prefix_sha256': hashlib.sha256(json.dumps(prefix_data, ensure_ascii=False, sort_keys=True).encode()).hexdigest(),
                   **{k: usage.get(k, '') for k in FIELDS[6:10]},
                   'token_hit_ratio': usage.get('cache_read_input_tokens', 0) / total if total else '',
                   'ttft_seconds': raw['ttft_seconds'], 'elapsed_seconds': raw['elapsed_seconds'],
                   'usd': value if not raw.get('error') else '', 'request_id': raw.get('request_id', ''), 'error': raw.get('error', '')}
            rows.append(row)
            failed |= bool(raw.get('error'))
        with (a.out / 'usage.csv').open('w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(rows)
        manifest['completed_requests'] = len(rows)
        manifest['usage_priced_usd'] = spent
        dump(a.out / 'manifest.json', manifest)
        if failed:
            raise RuntimeError('Request failed; no retries. Partial usage may understate billing; reconcile provider logs.')
        print(f'{group} N={n} {phase}: {len(specs)} requests recorded', flush=True)

    try:
        for n in [1, 5, 20]:
            # Different initial bytes isolate every cold A call, including from prior runs.
            batch('A', n, 'cold', [uuid.uuid4().hex + '\n' for _ in range(n)])
            shared = f'{run_id}-B-{n}\n'
            batch('B', n, 'sequential', [shared] * n)
            independent = f'{run_id}-C-{n}\n'
            # Cold concurrent requests test races before a cache is ready.
            batch('C', n, 'cold-concurrent', [independent] * n, True)
            # Prime explicitly, then test N fresh processes against an available cache.
            batch('C', n, 'prime', [independent])
            batch('C', n, 'warm-concurrent', [independent] * n, True)
        ttl = f'{run_id}-TTL\n'
        batch('TTL', 1, 'create', [ttl])
        batch('TTL', 1, 'confirm-read', [ttl])
        if rows[-1]['cache_read_input_tokens'] == 0:
            raise RuntimeError('TTL precondition failed: no cache read; cannot claim expiration test')
        print(f'Waiting {a.ttl_seconds}s after last completed read; no intervening calls to this prefix', flush=True)
        before = time.monotonic()
        time.sleep(a.ttl_seconds)
        manifest['ttl_idle_seconds'] = time.monotonic() - before
        batch('TTL', 1, 'after-expiry', [ttl])
        batch('TTL', 1, 'after-recreation-read', [ttl])
        manifest['status'] = 'complete'
    except Exception as exc:
        manifest['status'] = 'incomplete'
        manifest['error'] = str(exc)
        print(str(exc), file=sys.stderr)
    finally:
        dump(a.out / 'manifest.json', manifest)
    return 0 if manifest['status'] == 'complete' else 1


if __name__ == '__main__':
    raise SystemExit(main())

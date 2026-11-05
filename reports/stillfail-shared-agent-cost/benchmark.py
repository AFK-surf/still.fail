#!/usr/bin/env python3
"""One command: python3 benchmark.py --repo /path/to/still.fail --out ./results
No model calls or credentials. First run installs pinned tiktoken in a temporary venv.
Costs use proxy token counts, NOT Claude's official tokenizer or measured API usage.
"""
import argparse, csv, hashlib, importlib.metadata, json, os, pathlib, re, subprocess, sys, tempfile
try:
    import tiktoken
except ImportError:
    venv = pathlib.Path(tempfile.gettempdir()) / 'stillfail-cost-tiktoken-0.12.0'
    subprocess.run([sys.executable, '-m', 'venv', str(venv)], check=True)
    py = venv / 'bin/python'
    subprocess.run([str(py), '-m', 'pip', 'install', 'tiktoken==0.12.0'], check=True)
    os.execv(str(py), [str(py), __file__, *sys.argv[1:]])

REV = 'c789e5c30f48998eac66b7c9654aff0e068178b1'
FILES = ['station/src/agents/instructions.ts', 'station/src/agents/claude.ts',
         'station/src/sessions/presets.ts', 'station/src/usage/counter.ts']
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--repo', default='.')
ap.add_argument('--rev', default=REV)
ap.add_argument('--out', default='stillfail-cost-results')
ap.add_argument('--output-tokens', type=int, default=1000, help='ASSUMED, not generated')
a = ap.parse_args()
out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
def git(*args):
    return subprocess.check_output(['git', '-C', a.repo, *args])
rev = git('rev-parse', a.rev).decode().strip()
def source(path): return git('show', f'{rev}:{path}').decode()
enc = tiktoken.get_encoding('cl100k_base')
prefix = 'Reference source from AFK-surf/still.fail. Use it to answer the task below.\n'
manifest = []
for path in FILES:
    body = source(path)
    manifest.append({'path':path,'bytes':len(body.encode()),'sha256':hashlib.sha256(body.encode()).hexdigest(),'proxy_tokens':len(enc.encode(body))})
    prefix += f'\n<source path="{path}">\n{body}\n</source>\n'
query = 'Explain how this repository shares agent sessions and accounts, and distinguish prompt cache reuse from sharing source files. Cite the relevant functions.'
p = len(enc.encode(prefix)); u = len(enc.encode(query)); o = a.output_tokens
(out/'prefix.txt').write_text(prefix)
# Official Anthropic list prices in USD / million tokens, checked 2026-11-05.
# Fixed historical model intentionally makes this benchmark stable (deprecated, still functional at audit date).
price = {'model':'claude-sonnet-4-5-20250929','input':3,'write_5m':3.75,'write_1h':6,'read':0.30,'output':15,
         'source':'https://platform.claude.com/docs/en/about-claude/pricing','checked':'2026-11-05'}
rows=[]
for n in [1,5,20]:
    prefix_costs = {
      'independent_no_cache':n*p*price['input'],
      'independent_cold_5m_domains':n*p*price['write_5m'],
      'shared_ideal_5m':p*price['write_5m']+(n-1)*p*price['read'],
      'independent_same_domain_ideal_5m':p*price['write_5m']+(n-1)*p*price['read'],
      'both_already_warm_5m':n*p*price['read'],
      'independent_cold_1h_domains':n*p*price['write_1h'],
      'shared_ideal_1h':p*price['write_1h']+(n-1)*p*price['read'],
    }
    for scenario, pc in prefix_costs.items():
        ic=(pc+n*u*price['input'])/1e6
        total=ic+n*o*price['output']/1e6
        rows.append(dict(n=n,scenario=scenario,prefix_proxy_tokens=p,query_proxy_tokens=u,assumed_output_tokens=o,
                         input_usd_total=round(ic,9),usd_total=round(total,9),usd_per_task=round(total/n,9),
                         measurement='tokenizer measured; API costs estimated; no API calls'))
with (out/'costs.csv').open('w') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
# Search exact fixed-revision tracked production source; count matching LINES, not occurrences.
exts={'.ts','.tsx','.js','.mjs','.rs','.py','.swift','.kt','.c','.h'}
paths=[x for x in git('ls-tree','-r','--name-only',rev).decode().splitlines() if pathlib.Path(x).suffix in exts]
station=[x for x in paths if x.startswith('station/src/')]
patterns=[r'embedding',r'vector',r'\bindex\b',r'cache',r'cache_control',r'prompt_cache_key',r'code[_ -]?index|codeIndex',r'RepoIndex',r'\bFAISS\b|\bHNSW\b|\bLanceDB\b|\bChromaDB\b|\bPinecone\b']
search=[]
for scope, members in [('tracked_source_all',paths),('station/src',station)]:
    texts={path:source(path) for path in members}
    for pattern in patterns:
        rx=re.compile(pattern,re.I)
        hits=[f'{path}:{i}:{line}' for path,txt in texts.items() for i,line in enumerate(txt.splitlines(),1) if rx.search(line)]
        search.append(dict(scope=scope,files=len(members),regex=pattern,matching_lines=len(hits)))
        safe=hashlib.sha256((scope+pattern).encode()).hexdigest()[:10]
        (out/f'search-{safe}.txt').write_text('\n'.join(hits)+'\n')
with (out/'search-counts.csv').open('w') as f:
    w=csv.DictWriter(f,fieldnames=list(search[0]));w.writeheader();w.writerows(search)
meta=dict(revision=rev,repository='AFK-surf/still.fail',tokenizer='tiktoken',version=importlib.metadata.version('tiktoken'),encoding='cl100k_base',
          tokenizer_status='proxy for Claude; official for this encoding only; no calibrated Claude error bound',
          prefix_tokens=p,prefix_bytes=len(prefix.encode()),prefix_sha256=hashlib.sha256(prefix.encode()).hexdigest(),query=query,query_tokens=u,
          output_tokens_assumed=o,manifest=manifest,pricing=price,api_calls=0,
          exclusions=['CLI system/tool overhead','message framing','tool turns','reasoning/output measurement','hosting and subscription fees'])
(out/'measurement.json').write_text(json.dumps(meta,indent=2)+'\n')
print(json.dumps(meta,indent=2));print((out/'costs.csv').read_text());print((out/'search-counts.csv').read_text())

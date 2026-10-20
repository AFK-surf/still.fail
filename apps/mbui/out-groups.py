# (scratch) the flows' tests grouped as scripts/rerecord.sh takes them: by mark and station; first starts apart
import re, sys, glob, os, collections
groups = collections.OrderedDict()
for test in sorted(glob.glob("src/sfreplay/flows/*/*_test.mbt")):
    n = os.path.basename(test)[:-9]
    words = open(test, encoding="utf-8").read()
    m = re.search(r"@sfreplay\.trace_([a-z0-9_]+)", words)
    if not m: continue
    ident = m.group(1); trace = None
    for t in glob.glob("e2e/traces/*.trace"):
        if re.sub(r"[^a-z0-9]", "_", os.path.basename(t)[:-6]) == ident: trace = t
    if not trace: continue
    tr = open(trace, encoding="utf-8").read()
    c = collections.Counter(x for x in re.findall(r"(?<!\d)(\d{6})(?!\d)", tr) if x in words)
    tag = c.most_common(1)[0][0] if c else ""
    st = collections.Counter(re.findall(r"/tmp/mb[A-Za-z0-9-]*", tr)).most_common(1)
    st = st[0][0] if st else ""
    first = '"call":"migrate"' in tr
    key = (tag, st, n if first else "")
    groups.setdefault(key, []).append(n)
for (tag, st, first), ns in groups.items():
    print(f"{st or '-'}|{'first' if first else 'base'}|{tag or '-'}|{' '.join(ns)}")

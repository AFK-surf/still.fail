#!/usr/bin/env python3
# One run of sfapp's tests (scripts/test.sh's: its files, or a file and `--index FROM-TO`) on a test program built
# elsewhere (APP_EXE: check-mbui's app-build job's), not through moon test: moon, finding the sources of a fresh
# checkout newer than what it built, compiles every package again (28 s on Studio for nothing). The program is asked
# as moon asks it (the native test driver's argument: file:from-to, joined by /) and says each test's start and result
# between its markers; said as moon says it: each failure, then "Total tests: N, passed: P, failed: F." A test that
# ended the program (an abort) is said by name, and every test asked of it that said no result is failed.
# APP_JOBS=N: the files in N programs side by side, each taking the next file when it is done with one (dealt out
# beforehand, by name round four, one process took 75 s while another took 21 on CI's four cores, 2026-11-01).
#   test_exe.py EXE INFO_JSON FILE… | FILE --index FROM-TO
import json, os, re, subprocess, sys, threading, time

exe, info, args = sys.argv[1], sys.argv[2], sys.argv[3:]
tests = json.load(open(info))["tests"]
asked = []
if "--index" in args:
    f = os.path.basename(args[0])
    a, b = (int(x) for x in args[args.index("--index") + 1].split("-"))
    asked.append((f, a, b))
else:
    for p in args:
        f = os.path.basename(p)
        n = len(tests.get(f, []))
        if n:
            asked.append((f, 0, n))
names = {(f, t["index"]): t["name"] for f, ts in tests.items() for t in ts}
if not asked:
    print("Total tests: 0, passed: 0, failed: 0.")
    sys.exit(0)
marks = re.compile(r"----- BEGIN MOON TEST RESULT -----\n(.*?)\n----- END MOON TEST RESULT -----\n?", re.S)


def run(part):
    """The program on part (files and their ranges): what it printed, the markers out, and its failures and skips."""
    s = time.time()
    arg = "/".join(f"{f}:{a}-{b}" for f, a, b in part)
    p = subprocess.run([exe, arg], cwd=os.environ.get("APP_EXE_DIR") or os.getcwd(), capture_output=True, text=True, errors="replace")
    said = p.stdout + p.stderr
    done, started, failed, skipped = {}, None, [], 0
    for m in marks.finditer(said):
        try:
            r = json.loads(m.group(1))
        except ValueError:
            continue
        key = (r.get("file"), r.get("index"))
        if r.get("type") == "start":
            started = key
        elif r.get("type") == "result":
            done[key] = r.get("message", "")
    for key in [(f, i) for f, a, b in part for i in range(a, b)]:
        msg = done.get(key)
        if msg is None:
            why = "the program ended in it" if key == started else "not run: the program ended before it"
            failed.append(f"[stillfail/sfapp] test {key[0]}:{key[1]} ({names.get(key, '?')}) failed: {why} (exit {p.returncode})")
        elif msg == "skipped test":
            skipped += 1
        elif msg != "":
            failed.append(f"[stillfail/sfapp] test {key[0]}:{key[1]} ({names.get(key, '?')}) failed: {msg}")
    return marks.sub("", said).strip(), failed, skipped, time.time() - s


jobs = max(1, int(os.environ.get("APP_JOBS") or 1))
parts = [[x] for x in asked] if jobs > 1 else [asked]
results = [None] * len(parts)
nxt = iter(range(len(parts)))
lock = threading.Lock()


def worker():
    while True:
        with lock:
            i = next(nxt, None)
        if i is None:
            return
        results[i] = run(parts[i])


ws = [threading.Thread(target=worker) for _ in range(min(jobs, len(parts)))]
for w in ws:
    w.start()
for w in ws:
    w.join()
failed, skipped = [], 0
for rest, f, k, _ in results:
    if rest:
        print(rest)
    failed += f
    skipped += k
if jobs > 1:
    slow = sorted(zip(parts, results), key=lambda x: -x[1][3])[:5]
    print("test_exe.py: the slowest files: " + ", ".join(f"{p[0][0]} {r[3]:.0f} s" for p, r in slow))
for f in failed:
    print(f)
total = sum(b - a for f, a, b in asked) - skipped
print(f"Total tests: {total}, passed: {total - len(failed)}, failed: {len(failed)}.")
sys.exit(1 if failed else 0)

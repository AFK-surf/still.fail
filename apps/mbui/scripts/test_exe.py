#!/usr/bin/env python3
# One run of sfapp's tests (scripts/test.sh's: its files, or a file and `--index FROM-TO`) on a test program built
# elsewhere (APP_EXE: check-mbui's app-build job's), not through moon test: moon, finding the sources of a fresh
# checkout newer than what it built, compiles every package again (28 s on Studio for nothing). The program is asked
# as moon asks it (the native test driver's argument: file:from-to, joined by /) and says each test's start and result
# between its markers; said as moon says it: each failure, then "Total tests: N, passed: P, failed: F." A test that
# ended the program (an abort) is said by name, and every test asked of it that said no result is failed.
#   test_exe.py EXE INFO_JSON FILE… | FILE --index FROM-TO
import json, os, re, subprocess, sys

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
want = [(f, i) for f, a, b in asked for i in range(a, b)]
if not want:
    print("Total tests: 0, passed: 0, failed: 0.")
    sys.exit(0)
arg = "/".join(f"{f}:{a}-{b}" for f, a, b in asked)
p = subprocess.run([exe, arg], cwd=os.environ.get("APP_EXE_DIR") or os.getcwd(), capture_output=True, text=True, errors="replace")
said = p.stdout + p.stderr
marks = re.compile(r"----- BEGIN MOON TEST RESULT -----\n(.*?)\n----- END MOON TEST RESULT -----\n?", re.S)
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
# what the tests themselves printed (moon passes it through), the markers taken out
rest = marks.sub("", said).strip()
if rest:
    print(rest)
for key in want:
    msg = done.get(key)
    if msg is None:
        why = "the program ended in it" if key == started else "not run: the program ended before it"
        failed.append(f"[stillfail/sfapp] test {key[0]}:{key[1]} ({names.get(key, '?')}) failed: {why} (exit {p.returncode})")
    elif msg == "skipped test":
        skipped += 1
    elif msg != "":
        failed.append(f"[stillfail/sfapp] test {key[0]}:{key[1]} ({names.get(key, '?')}) failed: {msg}")
for f in failed:
    print(f)
total = len(want) - skipped
print(f"Total tests: {total}, passed: {total - len(failed)}, failed: {len(failed)}.")
sys.exit(1 if failed or (p.returncode != 0 and not failed and len(done) < len(want)) else 0)

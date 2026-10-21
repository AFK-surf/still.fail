#!/usr/bin/env python3
# Every job of every workflow (.github/workflows/*.yml) that runs on a runner says how long it may take, and that is 10
# minutes at most: a job stuck on something (a flow waiting on what never comes, a simulator, a lock) fails within 10
# minutes instead of holding its PR for half an hour, or for GitHub's default of 6 hours. A job that needs longer is
# to be made faster or split, not given longer (2026-10-22: mbui-ios hung 25 minutes on a PR). A job that calls a workflow (`uses:`) is that
# workflow's jobs, checked there. Prints each one that does not, and fails then.
import glob, os, re, sys

LIMIT = 10
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
bad = []
for path in sorted(glob.glob(os.path.join(root, ".github/workflows/*.yml"))):
    name = os.path.relpath(path, root)
    jobs, job, in_jobs = [], None, False
    for line in open(path, encoding="utf-8"):
        if re.match(r"^jobs:\s*$", line):
            in_jobs = True
            continue
        if in_jobs and re.match(r"^\S", line):
            in_jobs = False
        if not in_jobs:
            continue
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*(#.*)?$", line)
        if m:
            job = {"name": m.group(1), "timeout": None, "runs": False}
            jobs.append(job)
            continue
        if job is None:
            continue
        m = re.match(r"^    timeout-minutes:\s*(\S+)", line)
        if m:
            job["timeout"] = m.group(1)
        if re.match(r"^    runs-on:", line):
            job["runs"] = True
    for j in jobs:
        if not j["runs"]:
            continue
        t = j["timeout"]
        if t is None:
            bad.append(f"{name}: {j['name']}: no timeout-minutes")
        elif not t.isdigit() or int(t) > LIMIT:
            bad.append(f"{name}: {j['name']}: timeout-minutes {t} (at most {LIMIT})")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)

#!/usr/bin/env python3
# Every job of every workflow (.github/workflows/*.yml) that runs on a runner says how long it may take, and that is 5
# minutes at most (2026-10-31, as asked: the aim is 3; 10 since 2026-10-22): a job stuck on something (a flow waiting on
# what never comes, a simulator, a lock) fails within 5 minutes instead of holding its PR for 10, or for GitHub's
# default of 6 hours. A job that needs longer is to be made faster, not given longer (2026-10-22: mbui-ios hung 25
# minutes on a PR). Only those in LONGER may take 10: runs of the day's or by hand, which hold no push back, and two
# not yet made faster. A job whose own runs differ says `${{ github.event_name == 'push' && A || B }}`: A for a push
# (5 at most), B for the others (its LONGER). A job that calls a workflow (`uses:`) is that workflow's jobs, checked
# there. Prints each one that does not, and fails then.
import glob, os, re, sys

LIMIT = 5
# (workflow, job): minutes. sfapp's pages in one process of the day's (mbui-check.yml native), the emulator's checks of the day's (2026-10-31: android-devices 430-575 s), the Windows
# app's end to end of the day's (mbui.yml windows' runs that are no push), prebuild's Windows shell (300-450 s) and
# TestFlight's release (330-550 s), both to be made faster
LONGER = {
    ("mbui-ci.yml", "android-devices"): 10,
    ("mbui-ci.yml", "android-oldest"): 10,
    ("mbui-ci.yml", "android-streams-real"): 10,
    ("mbui-render-android.yml", "offscreen"): 10,
    ("mbui-render-android.yml", "same"): 10,
    ("mbui-host-android.yml", "contracts"): 10,
    ("mbui-android-sdk.yml", "put"): 10,
    ("mbui.yml", "windows"): 10,
    ("mbui-check.yml", "native"): 10,
    ("mbui-check.yml", "app"): 10,
    ("prebuild.yml", "build"): 10,
    ("prebuild.yml", "again"): 10,
    ("mbui-testflight.yml", "release"): 10,
}
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
        m = re.match(r"^    timeout-minutes:\s*(.+?)\s*$", line)
        if m:
            job["timeout"] = m.group(1)
        if re.match(r"^    runs-on:", line):
            job["runs"] = True
    for j in jobs:
        if not j["runs"]:
            continue
        t = j["timeout"]
        most = LONGER.get((os.path.basename(path), j["name"]), LIMIT)
        m = re.match(r"^\$\{\{ *github\.event_name *== *'push' *&& *(\d+) *\|\| *(\d+) *\}\}$", t or "")
        if t is None:
            bad.append(f"{name}: {j['name']}: no timeout-minutes")
        elif m:
            if int(m.group(1)) > LIMIT or int(m.group(2)) > most:
                bad.append(f"{name}: {j['name']}: timeout-minutes {t} (a push's at most {LIMIT}, the others' {most})")
        elif not t.isdigit() or int(t) > most:
            bad.append(f"{name}: {j['name']}: timeout-minutes {t} (at most {most})")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)

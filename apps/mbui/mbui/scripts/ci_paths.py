#!/usr/bin/env python3
"""What a pull request's files touch, for a workflow's steps (a contract run when its files changed): FILTERS (in the
environment) names each set of globs, as paths-filter took them,

    host:
      - "src/ui/native.mbt"
      - "android/**"

and each name is said true or false (name=true in $GITHUB_OUTPUT) by the files the merge commit changes from its first
parent (the base it is made on: checkout's fetch-depth 2). Read from the checkout's own history, nothing asked of
GitHub's API (paths-filter's call broke off on a TLS error now and then, 2026-10-19). Globs: ** any directories, * and
? within a name."""
import os
import re
import subprocess
import sys


def regex(glob):
    out, i = "", 0
    while i < len(glob):
        if glob.startswith("**", i):
            out += ".*"
            i += 2
        elif glob[i] == "*":
            out += "[^/]*"
            i += 1
        elif glob[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(glob[i])
            i += 1
    return re.compile(out + r"\Z")


def main():
    sets, name = {}, None
    for line in os.environ["FILTERS"].splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.endswith(":") and not s.startswith("-"):
            name = s[:-1].strip()
            sets[name] = []
        elif s.startswith("-") and name is not None:
            sets[name].append(regex(s[1:].strip().strip('"').strip("'")))
        else:
            sys.exit(f"ci_paths: not a filter line: {line!r}")
    files = subprocess.run(["git", "diff", "--name-only", "HEAD^1", "HEAD"], check=True, capture_output=True,
                           text=True).stdout.split()
    out = os.environ.get("GITHUB_OUTPUT")
    with open(out, "a") if out else sys.stdout as f:
        for n, pats in sets.items():
            hit = any(p.match(path) for path in files for p in pats)
            f.write(f"{n}={'true' if hit else 'false'}\n")
            print(f"{n}: {'true' if hit else 'false'}", file=sys.stderr)


if __name__ == "__main__":
    main()

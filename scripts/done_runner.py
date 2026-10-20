#!/usr/bin/env python3
"""A scripted run's runner, for the host's contract (scripts/host_contract.sh HOST runner; src/host/done_watch.h): reads
the run's log as it comes (its stdin: the app's output, or adb logcat's), each line kept in LOG, and for each
`DRIVE LOG do: NAME` says it has done NAME as a runner does: NAME's file written in the run's directory as .NAME, then
renamed NAME, its words what WORDS gives for NAME ("ok" by default). Ends with the run (DRIVE PASS, FAIL or END).

  scripts/done_runner.py --log FILE (--dir DIR | --adb "ADB…" --app APP_ID) [--said NAME=WORDS …]

--dir: the directory on this machine; --adb and --app: the app's own files/done on the device, written as the app
(run-as). Nothing here waits on a time: a line comes or the run ends.
"""
import argparse
import os
import re
import subprocess
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--dir")
    ap.add_argument("--adb")
    ap.add_argument("--app")
    ap.add_argument("--said", action="append", default=[])
    a = ap.parse_args()
    said = dict(s.split("=", 1) for s in a.said)
    do = re.compile(r"DRIVE LOG do: (\S+)")
    end = re.compile(r"DRIVE (PASS|FAIL|END)")
    with open(a.log, "w", encoding="utf-8") as log:
        for raw in sys.stdin.buffer:
            line = raw.decode("utf-8", "replace").rstrip("\r\n")
            log.write(line + "\n")
            log.flush()
            m = do.search(line)
            if m:
                name, words = m.group(1), said.get(m.group(1), "ok")
                if a.dir:
                    tmp = os.path.join(a.dir, "." + name)
                    with open(tmp, "w", encoding="utf-8") as f:
                        f.write(words + "\n")
                    os.replace(tmp, os.path.join(a.dir, name))
                else:
                    q = words.replace("'", "'\\''")
                    sh = f"printf '%s\\n' '{q}' > files/done/.{name} && mv files/done/.{name} files/done/{name}"
                    subprocess.run(a.adb.split() + ["shell", f"run-as {a.app} sh -c \"{sh}\""], check=True)
                log.write(f"RUNNER did {name}: {words}\n")
                log.flush()
            if end.search(line):
                break


if __name__ == "__main__":
    main()

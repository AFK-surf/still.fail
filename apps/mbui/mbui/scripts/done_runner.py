#!/usr/bin/env python3
"""A scripted run's runner, for the host's contract (scripts/host_contract.sh HOST runner; src/host/done_watch.h): reads
the run's log as it comes, each line kept in LOG, and for each `DRIVE LOG do: NAME` says it has done NAME as a runner
does: NAME's file written in the run's directory as .NAME, then renamed NAME, its words what WORDS gives for NAME ("ok"
by default). Ends with the run (DRIVE PASS or END).

  scripts/done_runner.py --log FILE --dir DIR [--said NAME=WORDS …]           the log on its stdin (the app's output)
  scripts/done_runner.py --log FILE --adb "ADB…" --app APP_ID --file NAME [--said NAME=WORDS …]

--adb, --app, --file: the app's own log file on the device (files/NAME, MBUI_LOG_FILE), followed as it is written
(run-as tail -f; not logcat's stream, which can stop handing on lines while the app goes on); a follow that ends
before the run does is begun again from the next line, none lost; what is done written in the app's files/done.
Nothing here waits on a time: a line comes or the run ends.
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
    ap.add_argument("--file")
    a = ap.parse_args()
    said = dict(s.split("=", 1) for s in a.said)
    do = re.compile(r"DRIVE LOG do: (\S+)")
    end = re.compile(r"DRIVE (PASS|END)")

    def lines():
        """The log's lines as they come: stdin's, or the device's file followed, begun again where it stopped."""
        if not a.file:
            for raw in sys.stdin.buffer:
                yield raw.decode("utf-8", "replace").rstrip("\r\n")
            return
        read, follows = 0, 0
        while follows < 10:
            follows += 1
            p = subprocess.Popen(a.adb.split() + ["shell", f"run-as {a.app} tail -n +{read + 1} -f files/{a.file}"],
                                 stdout=subprocess.PIPE)
            try:
                for raw in p.stdout:
                    read += 1
                    yield raw.decode("utf-8", "replace").rstrip("\r\n")
            finally:
                p.kill()
                p.wait()

    with open(a.log, "w", encoding="utf-8") as log:
        for line in lines():
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

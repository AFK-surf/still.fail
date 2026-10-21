#!/usr/bin/env python3
"""scripts/logwait.py on this machine's own events (kqueue on macOS, inotify and a pidfd on Linux): a line found, a
failing line on another file, a process's end (one that ends as it is watched), a path gone."""
import os
import subprocess
import sys
import tempfile

D = os.path.dirname(os.path.abspath(__file__))
W = [sys.executable, os.path.join(D, "logwait.py")]


def run(args, then):
    p = subprocess.Popen(W + args + ["--deadline", "20"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    then()
    out, err = p.communicate()
    return p.returncode, out.strip(), err.strip()


def main():
    t = tempfile.mkdtemp()
    log, bad, flag = (os.path.join(t, n) for n in ("log", "bad", "flag"))
    # (what is there as the watch begins: found as it is read; what comes later is the same read again, as its event
    # says, and a process's end, below, is one that comes later)
    with open(log, "w") as f:
        f.write("starting\nios: launched\n")
    rc, out, _ = run(["--log", log, "--line", "^ios: launched"], lambda: None)
    assert (rc, out) == (0, "ios: launched"), (rc, out)
    with open(bad, "w") as f:
        f.write("An error was encountered\n")
    rc, _, err = run(["--log", log, "--line", "^never", "--fail-log", bad, "--fail-line", "An error"], lambda: None)
    assert rc == 1 and "An error" in err, (rc, err)
    # a process that ends of itself as it is watched: `cat` until its input is closed
    c = subprocess.Popen(["cat"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
    rc, _, _ = run(["--pid", str(c.pid)], lambda: c.stdin.close())
    c.wait()
    assert rc == 0, rc
    rc, _, _ = run(["--gone", flag], lambda: None)
    assert rc == 0, rc
    print("logwait: a line, a failing line, a process's end, a path gone")


if __name__ == "__main__":
    main()

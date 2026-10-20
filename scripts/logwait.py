#!/usr/bin/env python3
"""Waits for an event, not a time (detlint's script-wait): a line of a log another process writes, or a process's end.

  scripts/logwait.py [--log FILE --line REGEX] [--pid PID] [--deadline S]

--log/--line: until a line of FILE (as it is written: kqueue's vnode events, from the start) matches REGEX; that line
printed, exit 0. --pid: the process PID (any of this user's: a simulator's app, a child left running) watched for its
end (kqueue's NOTE_EXIT): with --line, its end without such a line is exit 1 (what was read gone over once more
first); alone, its end is exit 0. --deadline: how long at most (s, default 600; what a run that hangs is given before it
fails, not what it is expected to take): exit 2.
"""
import argparse
import os
import re
import select
import sys
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log")
    ap.add_argument("--line")
    ap.add_argument("--pid", type=int)
    ap.add_argument("--deadline", type=float, default=600.0)
    a = ap.parse_args()
    if bool(a.log) != bool(a.line) or not (a.log or a.pid):
        ap.error("--log with --line, and/or --pid")
    pat = re.compile(a.line) if a.line else None
    kq = select.kqueue()
    gone = False
    if a.pid:
        try:
            kq.control([select.kevent(a.pid, select.KQ_FILTER_PROC, select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                                      select.KQ_NOTE_EXIT)], 0)
        except ProcessLookupError:
            gone = True
    f = None
    buf = ""
    if a.log:
        f = open(a.log, "r", encoding="utf-8", errors="replace")
        kq.control([select.kevent(f.fileno(), select.KQ_FILTER_VNODE, select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                                  select.KQ_NOTE_WRITE | select.KQ_NOTE_EXTEND)], 0)

    def found():
        nonlocal buf
        buf += f.read()
        *lines, buf = buf.split("\n")
        for l in lines:
            if pat.search(l):
                print(l)
                return True
        return False

    end = time.monotonic() + a.deadline
    while True:
        if f and found():
            return 0
        if gone:
            if f:
                buf += "\n"
                return 0 if found() else 1
            return 0
        left = end - time.monotonic()
        if left <= 0:
            print(f"logwait: past the deadline ({a.deadline:g} s): "
                  + (f"no line /{a.line}/ in {a.log}" if f else f"process {a.pid} still running"), file=sys.stderr)
            return 2
        for ev in kq.control(None, 4, left):
            if ev.filter == select.KQ_FILTER_PROC:
                gone = True


if __name__ == "__main__":
    sys.exit(main())

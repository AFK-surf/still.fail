#!/usr/bin/env python3
"""Waits for an event, not a time (detlint's script-wait): a line of a log another process writes, or a process's end
(kqueue's on macOS, inotify's and a pidfd's on Linux).

  scripts/logwait.py [--log FILE --line REGEX] [--pid PID] [--gone PATH] [--fail-log FILE --fail-line REGEX]
                     [--deadline S]

--log/--line: until a line of FILE (as it is written: kqueue's vnode events, from the start) matches REGEX; that line
printed, exit 0. --pid: the process PID (any of this user's: a simulator's app, a child left running) watched for its
end (kqueue's NOTE_EXIT): with --line, its end without such a line is exit 1 (what was read gone over once more
first); alone, its end is exit 0. --gone: until PATH is no more (its directory's changes, kqueue's: a lock let go),
exit 0. --fail-log/--fail-line: a line of another FILE (as it is written) that says the event will not come (a launch
refused): that line printed, exit 1. --deadline: how long at most (s, default 600; what a run that hangs is given
before it fails, not what it is expected to take): exit 2.
"""
import argparse
import os
import re
import select
import sys
import time


class Events:
    """The system's word that a watched file was written, a directory changed or a process ended: kqueue on macOS,
    inotify and a pidfd on Linux (CI's runners). wait(s): until one of them, or s seconds; True when the process
    ended."""

    def __init__(self):
        self.linux = sys.platform.startswith("linux")
        if self.linux:
            import ctypes
            self.libc = ctypes.CDLL(None, use_errno=True)
            self.ino = self.libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
            if self.ino < 0:
                raise OSError(ctypes.get_errno(), "inotify_init1")
            self.poll = select.poll()
            self.poll.register(self.ino, select.POLLIN)
            self.pidfd = None
        else:
            self.kq = select.kqueue()

    def add(self, path, mask):
        import ctypes
        if self.libc.inotify_add_watch(self.ino, os.fsencode(path), mask) < 0:
            raise OSError(ctypes.get_errno(), "inotify_add_watch", path)

    def file(self, f, path):
        """Each write to the open file f (at path)."""
        if self.linux:
            # IN_MODIFY | IN_CLOSE_WRITE | IN_ATTRIB
            self.add(os.path.abspath(path), 0x2 | 0x8 | 0x4)
        else:
            self.kq.control([select.kevent(f.fileno(), select.KQ_FILTER_VNODE, select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                                           select.KQ_NOTE_WRITE | select.KQ_NOTE_EXTEND)], 0)

    def directory(self, path):
        """Each change of the directory's names."""
        if self.linux:
            # IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO
            self.add(path, 0x100 | 0x200 | 0x40 | 0x80)
        else:
            d = os.open(path, os.O_RDONLY)
            self.kq.control([select.kevent(d, select.KQ_FILTER_VNODE, select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                                           select.KQ_NOTE_WRITE)], 0)

    def process(self, pid):
        """The process's end; False when it is gone already."""
        try:
            if self.linux:
                self.pidfd = os.pidfd_open(pid)
                self.poll.register(self.pidfd, select.POLLIN)
            else:
                self.kq.control([select.kevent(pid, select.KQ_FILTER_PROC, select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                                               select.KQ_NOTE_EXIT)], 0)
            return True
        except ProcessLookupError:
            return False

    def wait(self, s):
        if self.linux:
            ended = False
            for fd, _ in self.poll.poll(max(0, int(s * 1000))):
                if fd == self.ino:
                    try:
                        os.read(self.ino, 65536)
                    except BlockingIOError:
                        pass
                elif fd == self.pidfd:
                    ended = True
            return ended
        return any(ev.filter == select.KQ_FILTER_PROC for ev in self.kq.control(None, 4, s))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log")
    ap.add_argument("--line")
    ap.add_argument("--pid", type=int)
    ap.add_argument("--gone")
    ap.add_argument("--fail-log")
    ap.add_argument("--fail-line")
    ap.add_argument("--deadline", type=float, default=600.0)
    a = ap.parse_args()
    if bool(a.log) != bool(a.line) or not (a.log or a.pid or a.gone):
        ap.error("--log with --line, and/or --pid, or --gone")
    pat = re.compile(a.line) if a.line else None
    ev = Events()
    gone = False
    if a.pid:
        gone = not ev.process(a.pid)
    if a.gone:
        ev.directory(os.path.dirname(os.path.abspath(a.gone)) or ".")
    f = None
    buf = ""
    if a.log:
        f = open(a.log, "r", encoding="utf-8", errors="replace")
        ev.file(f, a.log)

    def found():
        nonlocal buf
        buf += f.read()
        *lines, buf = buf.split("\n")
        for l in lines:
            if pat.search(l):
                print(l)
                return True
        return False

    ff, fbuf = None, ""
    if a.fail_log:
        fpat = re.compile(a.fail_line)
        open(a.fail_log, "a").close()
        ff = open(a.fail_log, "r", encoding="utf-8", errors="replace")
        ev.file(ff, a.fail_log)

    def failed():
        nonlocal fbuf
        fbuf += ff.read()
        *lines, fbuf = fbuf.split("\n")
        for l in lines:
            if fpat.search(l):
                print(l, file=sys.stderr)
                return True
        return False

    end = time.monotonic() + a.deadline
    while True:
        if a.gone and not os.path.exists(a.gone):
            return 0
        if f and found():
            return 0
        if ff and failed():
            return 1
        if gone:
            if f:
                buf += "\n"
                return 0 if found() else 1
            return 0
        left = end - time.monotonic()
        if left <= 0:
            print(f"logwait: past the deadline ({a.deadline:g} s): "
                  + (f"no line /{a.line}/ in {a.log}" if f else f"{a.gone} still there" if a.gone and not a.pid
                     else f"process {a.pid} still running"), file=sys.stderr)
            return 2
        if ev.wait(left):
            gone = True


if __name__ == "__main__":
    sys.exit(main())

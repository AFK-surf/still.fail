#!/usr/bin/env python3
"""Until the app on the emulator says its own end, or the system says it ended without one: what a contract's run
waits for (scripts/host_contract.sh android), by events, never a time.

  scripts/android_end.py --adb "ADB…" --app APP_ID --uid UID --file NAME --end REGEX

The app's own lines (its uid's, so another app's crash on the emulator, a Gmail's, is not taken for this one's) are
watched for REGEX: the first one that matches is printed and it exits 0 (the run's end as the app said it). The
system's events buffer for this app's process: died (am_proc_died: a crash that logged nothing of its own, a kill
under memory), not responding (am_anr), or its activity sent behind (wm_on_paused_called: no frame comes while it is,
so a run waiting on one would never end): unless the app's own log file (files/NAME, as Host.log writes it) has its end
already (an end said, then the app's exit: the two streams' order is not the app's), said, with what the window
manager has in front, and it exits 1. The events buffer is the run's own: cleared before the app starts
(host_contract.sh's run: logcat -b all -c)."""
import argparse
import re
import subprocess
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--adb", required=True)
    ap.add_argument("--app", required=True)
    ap.add_argument("--uid", required=True)
    ap.add_argument("--end", required=True)
    ap.add_argument("--file", required=True)
    a = ap.parse_args()
    adb = a.adb.split()
    end = re.compile(a.end)
    app = re.escape(a.app)
    # the system's word about this app's process or activity (the events buffer: the system's uid, not the app's)
    gone = re.compile(r"(am_proc_died|am_anr|wm_on_paused_called|am_on_paused_called)\b.*" + app)
    # two streams: the app's own (logcat --uid: its lines alone) and the system's events about it
    import queue
    import threading
    q = queue.Queue()
    procs = [
        ("app", subprocess.Popen(adb + ["logcat", "-v", "brief", "--uid=" + a.uid], stdout=subprocess.PIPE)),
        ("system", subprocess.Popen(adb + ["logcat", "-b", "events", "-v", "brief"], stdout=subprocess.PIPE)),
    ]

    def pump(kind, proc):
        for raw in proc.stdout:
            q.put((kind, raw.decode("utf-8", "replace").rstrip("\r\n")))
        q.put((kind, None))

    for kind, proc in procs:
        threading.Thread(target=pump, args=(kind, proc), daemon=True).start()
    ok, ended = None, 0
    try:
        while ok is None and ended < len(procs):
            kind, line = q.get()
            if line is None:
                ended += 1
            elif kind == "app" and end.search(line):
                print(line)
                ok = True
            elif kind == "system" and gone.search(line):
                # (its end said before it went, as its own file has it: the end)
                kept = subprocess.run(adb + ["exec-out", "run-as", a.app, "cat", "files/" + a.file],
                                      capture_output=True).stdout.decode("utf-8", "replace")
                said = [l for l in kept.splitlines() if end.search(l)]
                if said:
                    print(said[0])
                    ok = True
                else:
                    print(f"android_end: the system says, before the app's own end: {line}")
                    ok = False
    finally:
        for _, proc in procs:
            proc.kill()
            proc.wait()
    if ok is None:
        print("android_end: logcat ended before the app said its end")
        ok = False
    if not ok:
        w = subprocess.run(adb + ["shell", "dumpsys", "window"], capture_output=True, text=True).stdout
        for l in w.splitlines():
            if re.search(r"mCurrentFocus|mFocusedApp", l):
                print("android_end:", l.strip())
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

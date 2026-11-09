#!/usr/bin/python3
"""Exercise the GStreamer/XTest fallback on an isolated 800x600 X11 display, without ffmpeg or xdotool.

Run with DISPLAY set to a disposable Xvfb/Xvnc and Python GI, GTK 3 and GStreamer installed. This is an integration
check; it creates its own target window, decodes a captured JPEG and checks pointer, keyboard and Unicode text input.
"""
import json
import os
import pathlib
import struct
import subprocess
import sys
import tempfile
import threading
import time

import gi
gi.require_version("Gst", "1.0")
from gi.repository import Gst

station = pathlib.Path(__file__).resolve().parents[1]
target_code = r'''
import os, gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
events = open(os.environ["SF_X11_TEST_LOG"], "w", buffering=1)
window = Gtk.Window(title="still.fail X11 integration test")
window.connect("map-event", lambda *_args: events.write("ready\n") and False)
window.set_default_size(800, 600)
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
box.set_halign(Gtk.Align.CENTER)
box.set_valign(Gtk.Align.CENTER)
entry = Gtk.Entry()
entry.set_size_request(400, 80)
entry.connect("button-press-event", lambda _entry, event: events.write("button:%d\n" % event.button) and False)
entry.connect("changed", lambda field: events.write("text:%s\n" % field.get_text()))
box.pack_start(entry, False, False, 0)
window.add(box)
window.connect("destroy", Gtk.main_quit)
window.fullscreen()
window.show_all()
entry.grab_focus()
Gtk.main()
'''


def run():
    with tempfile.TemporaryDirectory(prefix="stillfail-x11-gst-") as scratch:
        log = pathlib.Path(scratch, "events")
        env = {**os.environ, "GDK_BACKEND": "x11", "SF_X11_TEST_LOG": str(log)}
        target = subprocess.Popen([sys.executable, "-c", target_code], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        helper = subprocess.Popen([sys.executable, "-u", str(station / "src/screens/linux-x11.py")], env=env,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        messages, last_jpeg = [], [None]

        def read_frames():
            while True:
                head = helper.stdout.read(5)
                if len(head) != 5:
                    return
                kind, length = struct.unpack(">BI", head)
                payload = helper.stdout.read(length)
                if len(payload) != length:
                    return
                if kind == 1:
                    messages.append(json.loads(payload))
                elif kind == 2 and payload[:2] == b"\xff\xd8":
                    last_jpeg[0] = payload

        def wait_for(predicate, seconds=15):
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                if predicate():
                    return True
                if helper.poll() is not None:
                    break
                time.sleep(.05)
            return False

        def send(item):
            helper.stdin.write((json.dumps(item, ensure_ascii=False) + "\n").encode())
            helper.stdin.flush()

        threading.Thread(target=read_frames, daemon=True).start()
        try:
            assert wait_for(lambda: any(message.get("type") == "ready" for message in messages)), messages
            assert wait_for(lambda: log.exists() and "ready\n" in log.read_text()), "target window did not map"
            send({"op": "start", "maxWidth": 800, "maxHeight": 600, "fps": 10})
            assert wait_for(lambda: last_jpeg[0] is not None), messages
            for event in [
                {"t": "pointer", "x": .5, "y": .5, "buttons": 1},
                {"t": "pointer", "x": .5, "y": .5, "buttons": 0},
                {"t": "key", "keycode": 30, "kind": "down"},
                {"t": "key", "keycode": 30, "kind": "up"},
                {"t": "text", "text": "你好"},
            ]:
                send({"op": "input", "event": event})

            def received():
                contents = log.read_text() if log.exists() else ""
                return "button:1" in contents and "text:a你好" in contents

            assert wait_for(received), log.read_text() if log.exists() else "target window did not open"
            jpeg = pathlib.Path(scratch, "screen.jpg")
            jpeg.write_bytes(last_jpeg[0])
            Gst.init(None)
            pipeline = Gst.parse_launch('filesrc name=source ! jpegdec ! fakesink')
            pipeline.get_by_name("source").set_property("location", str(jpeg))
            pipeline.set_state(Gst.State.PLAYING)
            result = pipeline.get_bus().timed_pop_filtered(10 * Gst.SECOND, Gst.MessageType.ERROR | Gst.MessageType.EOS)
            pipeline.set_state(Gst.State.NULL)
            assert result and result.type == Gst.MessageType.EOS, "the captured JPEG did not decode"
            print("X11 JPEG, pointer, keyboard and Unicode input passed")
        finally:
            helper.terminate()
            target.terminate()
            for process in (helper, target):
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            errors = helper.stderr.read().decode(errors="replace")
            if errors:
                print(errors[-3000:], file=sys.stderr)
            if target.returncode and target.returncode > 0:
                print(target.stderr.read().decode(errors="replace")[-1000:], file=sys.stderr)


if __name__ == "__main__":
    run()

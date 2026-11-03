#!/usr/bin/python3
"""X11 fallback for desktops with GStreamer but without ffmpeg and xdotool (e.g. CentOS GNOME)."""
import ctypes
import importlib.util
import os
import signal
import sys
import threading

spec = importlib.util.spec_from_file_location("stillfail_linux_portal", os.path.join(os.path.dirname(__file__), "linux-portal.py"))
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)
GLib, Gst = core.GLib, core.Gst


def function(library, name, result, args):
    call = getattr(library, name)
    call.restype, call.argtypes = result, args
    return call


class X11Input:
    def __init__(self):
        self.x = ctypes.CDLL("libX11.so.6")
        self.xtest = ctypes.CDLL("libXtst.so.6")
        pointer, integer, uint, ulong = ctypes.c_void_p, ctypes.c_int, ctypes.c_uint, ctypes.c_ulong
        function(self.x, "XInitThreads", integer, [])()
        self.open = function(self.x, "XOpenDisplay", pointer, [ctypes.c_char_p])
        self.close_display = function(self.x, "XCloseDisplay", integer, [pointer])
        self.flush = function(self.x, "XFlush", integer, [pointer])
        self.sync = function(self.x, "XSync", integer, [pointer, integer])
        screen = function(self.x, "XDefaultScreen", integer, [pointer])
        width = function(self.x, "XDisplayWidth", integer, [pointer, integer])
        height = function(self.x, "XDisplayHeight", integer, [pointer, integer])
        self.display_keycodes = function(self.x, "XDisplayKeycodes", integer, [pointer, ctypes.POINTER(integer), ctypes.POINTER(integer)])
        self.get_mapping = function(self.x, "XGetKeyboardMapping", ctypes.POINTER(ulong), [pointer, ctypes.c_ubyte, integer, ctypes.POINTER(integer)])
        self.change_mapping = function(self.x, "XChangeKeyboardMapping", integer, [pointer, integer, integer, ctypes.POINTER(ulong), integer])
        self.free = function(self.x, "XFree", integer, [pointer])
        self.motion = function(self.xtest, "XTestFakeMotionEvent", integer, [pointer, integer, integer, integer, ulong])
        self.button = function(self.xtest, "XTestFakeButtonEvent", integer, [pointer, uint, integer, ulong])
        self.key = function(self.xtest, "XTestFakeKeyEvent", integer, [pointer, uint, integer, ulong])
        self.display = self.open(None)
        if not self.display:
            raise RuntimeError("cannot open the station user's X11 display")
        display_screen = screen(self.display)
        self.size = (width(self.display, display_screen), height(self.display, display_screen))
        if min(self.size) < 2 or max(self.size) > 16384:
            self.close_display(self.display)
            self.display = None
            raise RuntimeError("invalid X11 display size")
        self.keys, self.buttons = set(), set()
        self.wheel = {"x": 0.0, "y": 0.0}
        self.spare, self.original, self.text_pressed, self.text_mapped = None, None, False, False

    def point(self, event):
        x = int(min(1.0, max(0.0, float(event.get("x", 0)))) * (self.size[0] - 1))
        y = int(min(1.0, max(0.0, float(event.get("y", 0)))) * (self.size[1] - 1))
        self.motion(self.display, -1, x, y, 0)

    def event(self, event):
        kind = event.get("t")
        if kind in ("pointer", "wheel"):
            self.point(event)
        if kind == "pointer":
            buttons = int(event.get("buttons", 0))
            for bit, code in ((1, 1), (2, 3), (4, 2)):
                down = bool(buttons & bit)
                if down != (code in self.buttons):
                    self.button(self.display, code, int(down), 0)
                    self.buttons.add(code) if down else self.buttons.discard(code)
        elif kind == "wheel":
            for axis in ("x", "y"):
                self.wheel[axis] += float(event.get("d" + axis, 0)) / 100
                whole = int(self.wheel[axis])
                count = min(20, abs(whole))
                self.wheel[axis] -= (1 if whole > 0 else -1) * count
                code = (5 if whole > 0 else 4) if axis == "y" else (7 if whole > 0 else 6)
                for _ in range(count):
                    self.button(self.display, code, 1, 0)
                    self.button(self.display, code, 0, 0)
        elif kind == "key":
            keycode = event.get("keycode")
            if isinstance(keycode, int) and 0 < keycode <= 247:
                code, down = keycode + 8, event.get("kind") == "down"
                self.key(self.display, code, int(down), 0)
                self.keys.add(code) if down else self.keys.discard(code)
        self.flush(self.display)

    def reserve_key(self):
        if self.spare is not None:
            return
        first, last, per = ctypes.c_int(), ctypes.c_int(), ctypes.c_int()
        self.display_keycodes(self.display, ctypes.byref(first), ctypes.byref(last))
        mapping = self.get_mapping(self.display, first.value, last.value - first.value + 1, ctypes.byref(per))
        if not mapping or per.value <= 0:
            raise RuntimeError("cannot inspect the X11 keyboard map")
        try:
            for code in range(last.value, first.value - 1, -1):
                current = [mapping[(code - first.value) * per.value + index] for index in range(per.value)]
                if not any(current):
                    self.spare, self.original = code, (ctypes.c_ulong * per.value)(*current)
                    return
        finally:
            self.free(mapping)
        raise RuntimeError("the X11 keyboard has no spare key for text")

    def text_press(self, keysym):
        self.reserve_key()
        replacement = (ctypes.c_ulong * len(self.original))(keysym, *([0] * (len(self.original) - 1)))
        self.change_mapping(self.display, self.spare, len(replacement), replacement, 1)
        self.text_mapped = True
        self.sync(self.display, 0)
        self.key(self.display, self.spare, 1, 0)
        self.text_pressed = True
        self.flush(self.display)

    def text_release(self):
        if self.text_pressed:
            self.key(self.display, self.spare, 0, 0)
            self.text_pressed = False
            self.flush(self.display)

    def restore_key(self):
        if self.text_mapped:
            self.change_mapping(self.display, self.spare, len(self.original), self.original, 1)
            self.sync(self.display, 0)
            self.text_mapped = False

    def close(self):
        if not self.display:
            return
        self.text_release()
        self.restore_key()
        for key in self.keys:
            self.key(self.display, key, 0, 0)
        for button in self.buttons:
            self.button(self.display, button, 0, 0)
        self.sync(self.display, 0)
        self.close_display(self.display)
        self.display = None


class X11(core.Portal):
    def __init__(self):
        super().__init__(session_bus=False)
        self.device = None

    def prepare(self):
        self.device = X11Input()
        self.logical = self.device.size
        signal.signal(signal.SIGTERM, lambda *_args: GLib.idle_add(self.stop))
        core.status("ready", width=self.logical[0], height=self.logical[1])

    def capture_source(self):
        return "ximagesrc name=source use-damage=false show-pointer=true"

    def configure_source(self, _source):
        pass

    def deliver_input(self, event):
        if self.started:
            self.device.event(event)

    def type_text(self, value):
        self.type_character(value, 0)

    def type_character(self, text, index, pressed=False):
        if not self.pipeline:
            self.typing = False
            return False
        if pressed:
            self.device.text_release()
            GLib.timeout_add(20, self.finish_character, text, index)
            return False
        if index >= len(text):
            self.typing = False
            self.drain_input()
            return False
        char = text[index]
        codepoint = ord(char)
        keysym = {"\n": 0xff0d, "\r": 0xff0d, "\t": 0xff09}.get(char, codepoint if codepoint < 256 else 0x01000000 | codepoint)
        self.device.text_press(keysym)
        GLib.timeout_add(20, self.type_character, text, index, True)
        return False

    def finish_character(self, text, index):
        self.device.restore_key()
        self.type_character(text, index + 1)
        return False

    def close(self):
        self.stop()
        if self.device:
            self.device.close()


def main():
    Gst.init(None)
    for element in ("ximagesrc", "queue", "identity", "videoconvert", "videoscale", "jpegenc", "appsink"):
        if not Gst.ElementFactory.find(element):
            raise RuntimeError("missing GStreamer component: " + element)
    desktop = X11()
    try:
        desktop.prepare()
        threading.Thread(target=desktop.commands, daemon=True).start()
        desktop.loop.run()
    finally:
        desktop.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        core.status("error", message=str(error))
        sys.exit(1)

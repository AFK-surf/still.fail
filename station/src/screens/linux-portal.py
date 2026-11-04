#!/usr/bin/python3
"""The station's desktop portal client. Its only stdout is framed JSON and JPEG for linux-portal.ts.

The portal owns both the capture and the virtual input devices; closing this process closes their session. The
station starts it only after someone opens the desktop, and a system dialog asks the desktop user to grant access.
"""
import json
import os
import re
import struct
import sys
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from collections import deque

try:
    import gi
    gi.require_version("Gst", "1.0")
    from gi.repository import Gio, GLib, Gst
except (ImportError, ValueError) as error:
    sys.stderr.write("Desktop portal dependencies unavailable: %s\n" % error)
    sys.exit(2)

BUS = "org.freedesktop.portal.Desktop"
PATH = "/org/freedesktop/portal/desktop"
REMOTE = "org.freedesktop.portal.RemoteDesktop"
CAST = "org.freedesktop.portal.ScreenCast"
REQUEST = "org.freedesktop.portal.Request"
SESSION = "org.freedesktop.portal.Session"
MAX_FRAME = 16 * 1024 * 1024
KEYSYM_DELAY_MS = 100
output_lock = threading.Lock()


def emit(kind, data):
    if isinstance(data, dict):
        data = json.dumps(data, separators=(",", ":")).encode()
    if len(data) > MAX_FRAME:
        raise ValueError("desktop frame is too large")
    with output_lock:
        sys.stdout.buffer.write(struct.pack(">BI", kind, len(data)))
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()


def status(kind, **values):
    emit(1, dict(type=kind, **values))


def insert_focused_text(value, stopped):
    """Insert composed Unicode into the focused accessible field, without reading its contents or changing the clipboard."""
    try:
        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi
        Atspi.init()
        Atspi.set_timeout(1000, 1000)
        queue = deque([Atspi.get_desktop(0)])
        deadline = time.monotonic() + 3
        seen = 0
        while queue and seen < 1500 and time.monotonic() < deadline and not stopped.is_set():
            element = queue.popleft()
            seen += 1
            try:
                state = element.get_state_set()
                if state and state.contains(Atspi.StateType.FOCUSED):
                    try:
                        # Terminal widgets accept keys rather than editable text operations. Restrict the fallback
                        # to a positively identified terminal so an inaccessible selection is never overwritten.
                        if element.get_role() == Atspi.Role.TERMINAL:
                            return "unavailable"
                        editable = element.get_editable_text_iface()
                        text = element.get_text_iface()
                        if editable and text:
                            # Replacing a selection needs an atomic edit; do not delete it with a separate call.
                            if text.get_n_selections() != 0:
                                return "unsafe"
                            caret = text.get_caret_offset()
                            if caret < 0 or stopped.is_set() or not element.get_state_set().contains(Atspi.StateType.FOCUSED):
                                return "unsafe"
                            # If this call times out, it may already have changed the target. Do not retry it via
                            # keyboard events and risk inserting the same text twice.
                            try:
                                inserted = editable.insert_text(caret, value, len(value.encode("utf-8")))
                            except GLib.Error:
                                return "unsafe"
                            if not inserted:
                                return "unsafe"
                            try:
                                text.set_caret_offset(caret + len(value))
                            except GLib.Error:
                                pass
                            return "inserted"
                    except (GLib.Error, AttributeError):
                        pass
                count = min(200, element.get_child_count())
                queue.extend(element.get_child_at_index(index) for index in range(count))
            except (GLib.Error, AttributeError):
                pass
    except (ImportError, ValueError, GLib.Error):
        pass
    return "unsafe"


class Portal:
    def __init__(self, session_bus=True):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None) if session_bus else None
        self.session = None
        self.stream = None
        self.logical = None
        self.fd = None
        self.loop = GLib.MainLoop()
        self.pipeline = None
        self.buttons = set()
        self.keys = set()
        self.picture = None
        self.started = False
        self.inputs = deque()
        self.typing = False
        self.text_parts = deque()
        self.keymap_display = None
        self.keymap = None
        self.input_active = False
        self.stopped = threading.Event()

    def request(self, interface, method, signature, values):
        # Subscribe before the call: a fast backend is allowed to answer immediately.
        token = "sf_" + uuid.uuid4().hex
        values[-1]["handle_token"] = GLib.Variant("s", token)
        sender = self.bus.get_unique_name()[1:].replace(".", "_")
        path = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender, token)
        loop = GLib.MainLoop()
        result = []

        def response(_bus, _sender, _path, _interface, _signal, parameters, _data):
            result.append(parameters.unpack())
            loop.quit()

        subscription = self.bus.signal_subscribe(BUS, REQUEST, "Response", path, None,
                                                  Gio.DBusSignalFlags.NONE, response, None)
        timer = None
        try:
            reply = self.bus.call_sync(BUS, PATH, interface, method, GLib.Variant(signature, tuple(values)),
                                       GLib.VariantType.new("(o)"), Gio.DBusCallFlags.NONE, 10000, None)
            if reply.unpack()[0] != path:
                raise RuntimeError("desktop portal returned an unexpected request")
            timer = GLib.timeout_add_seconds(120, lambda: (loop.quit(), False)[1])
            loop.run()
            if not result:
                self.bus.call(BUS, path, REQUEST, "Close", None, None, Gio.DBusCallFlags.NONE, -1, None, None, None)
                raise TimeoutError("desktop authorization timed out")
            code, data = result[0]
            if code:
                raise PermissionError("desktop authorization was cancelled" if code == 1 else "desktop authorization failed")
            return data
        finally:
            if timer is not None:
                GLib.source_remove(timer)
            self.bus.signal_unsubscribe(subscription)

    def prop(self, interface, name):
        reply = self.bus.call_sync(BUS, PATH, "org.freedesktop.DBus.Properties", "Get",
                                   GLib.Variant("(ss)", (interface, name)), GLib.VariantType.new("(v)"),
                                   Gio.DBusCallFlags.NONE, 5000, None)
        return reply.unpack()[0]

    def prepare(self):
        session_token = "sf_" + uuid.uuid4().hex
        created = self.request(REMOTE, "CreateSession", "(a{sv})", [
            {"session_handle_token": GLib.Variant("s", session_token)}])
        self.session = created["session_handle"]
        self.request(REMOTE, "SelectDevices", "(oa{sv})", [self.session, {"types": GLib.Variant("u", 3)}])
        options = {"types": GLib.Variant("u", 1), "multiple": GLib.Variant("b", False)}
        try:
            modes = self.prop(CAST, "AvailableCursorModes")
            if modes & 2:
                options["cursor_mode"] = GLib.Variant("u", 2)
        except GLib.Error:
            pass  # Older portals use their default cursor mode.
        self.request(CAST, "SelectSources", "(oa{sv})", [self.session, options])
        status("consent")
        started = self.request(REMOTE, "Start", "(osa{sv})", [self.session, "", {}])
        if started.get("devices", 0) & 3 != 3:
            raise PermissionError("desktop did not grant both keyboard and pointer (granted: %s)" % started.get("devices"))
        streams = started.get("streams", [])
        if len(streams) != 1:
            raise RuntimeError("desktop did not return a screen")
        self.stream, properties = streams[0]
        size = properties.get("size")
        if size and len(size) == 2 and size[0] > 0 and size[1] > 0:
            self.logical = tuple(size)
        reply, fds = self.bus.call_with_unix_fd_list_sync(
            BUS, PATH, CAST, "OpenPipeWireRemote", GLib.Variant("(oa{sv})", (self.session, {})),
            GLib.VariantType.new("(h)"), Gio.DBusCallFlags.NONE, 10000, None, None)
        self.fd = fds.get(reply.unpack()[0])
        self.bus.signal_subscribe(BUS, SESSION, "Closed", self.session, None, Gio.DBusSignalFlags.NONE,
                                  lambda *_args: self.stop(), None)
        status("ready", width=self.logical[0] if self.logical else 0, height=self.logical[1] if self.logical else 0)

    def start(self, command):
        if self.started:
            return
        self.started = True
        width = max(2, min(3840, int(command.get("maxWidth", 1920))))
        height = max(2, min(2160, int(command.get("maxHeight", 1080))))
        fps = max(1, min(15, int(command.get("fps", 15))))
        if self.logical:
            scale = min(1, width / self.logical[0], height / self.logical[1])
            width = max(2, int(self.logical[0] * scale) // 2 * 2)
            height = max(2, int(self.logical[1] * scale) // 2 * 2)
            caps = "video/x-raw,width=%d,height=%d,pixel-aspect-ratio=1/1" % (width, height)
        else:
            caps = "video/x-raw,pixel-aspect-ratio=1/1"
        # Screen streams can be damage-driven and advertise 0/1 fps. Keep the newest pending frame while
        # encoding is paced, so a final update is still delivered even if the desktop then becomes idle.
        self.pipeline = Gst.parse_launch(self.capture_source() +
                                         " ! queue leaky=downstream max-size-buffers=1 max-size-bytes=0 max-size-time=0"
                                         " ! identity sleep-time=%d ! videoconvert ! videoscale ! "
                                         "%s ! jpegenc quality=75 ! "
                                         "appsink name=sink emit-signals=true sync=false max-buffers=1 drop=true"
                                         % (1000000 // fps, caps))
        source = self.pipeline.get_by_name("source")
        self.configure_source(source)
        sink = self.pipeline.get_by_name("sink")
        sink.connect("new-sample", self.sample)
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self.message)
        if self.pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("could not start the desktop stream")

    def capture_source(self):
        return "pipewiresrc name=source do-timestamp=true"

    def configure_source(self, source):
        source.set_property("fd", self.fd)
        source.set_property("path", str(self.stream))

    def sample(self, sink):
        sample = sink.emit("pull-sample")
        if sample is None:
            return Gst.FlowReturn.EOS
        structure = sample.get_caps().get_structure(0)
        width, height = structure.get_value("width"), structure.get_value("height")
        if self.picture != (width, height):
            self.picture = (width, height)
            if not self.logical:
                self.logical = self.picture
            status("picture", width=width, height=height)
        buffer = sample.get_buffer()
        if buffer.get_size() > MAX_FRAME:
            GLib.idle_add(self.stop)
            return Gst.FlowReturn.ERROR
        try:
            emit(2, buffer.extract_dup(0, buffer.get_size()))
        except (BrokenPipeError, OSError):
            GLib.idle_add(self.stop)
            return Gst.FlowReturn.ERROR
        return Gst.FlowReturn.OK

    def message(self, _bus, message):
        if message.type == Gst.MessageType.ERROR:
            error, debug = message.parse_error()
            sys.stderr.write("desktop stream: %s (%s)\n" % (error, debug or "no details"))
            status("error", message=str(error))
            self.stop()
        elif message.type == Gst.MessageType.EOS:
            self.stop()

    def notify(self, method, signature, args, done=None):
        def completed(bus, result, _data):
            try:
                bus.call_finish(result)
                if done:
                    done()
            except GLib.Error as error:
                sys.stderr.write("desktop input: %s: %s\n" % (method, error))
                status("error", message="desktop input failed")
                self.stop()
        self.bus.call(BUS, PATH, REMOTE, method, GLib.Variant(signature, tuple([self.session, {}] + args)),
                      None, Gio.DBusCallFlags.NONE, -1, None, completed, None)

    def input(self, event):
        if (event.get("t") == "pointer" and event.get("kind") == "move" and self.inputs
                and self.inputs[-1].get("t") == "pointer" and self.inputs[-1].get("kind") == "move"
                and self.inputs[-1].get("buttons") == event.get("buttons")):
            self.inputs[-1] = event
        else:
            self.inputs.append(event)
        if not self.input_active:
            self.input_active = True
            self.drain_input()

    def drain_input(self):
        if self.typing:
            return False
        if not self.inputs:
            self.input_active = False
            return False
        event = self.inputs.popleft()
        if event.get("t") == "text" and event.get("text"):
            self.typing = True
            self.type_text(event["text"][:4096])
        else:
            self.deliver_input(event)
            # A compositor may otherwise see a queued press and release in the same dispatch and leave a key held.
            GLib.timeout_add(15, self.drain_input)
        return False

    def type_text(self, value):
        # A keysym is not necessarily delivered as the requested character: some compositors map "H" or "!"
        # to the unshifted physical key. Insert committed text through the focused accessible field instead.
        self.text_parts = deque(re.split(r"([\r\n\t])", value))
        self.type_next_part()

    def type_next_part(self):
        while self.text_parts:
            value = self.text_parts.popleft()
            if not value:
                continue
            if value in ("\r", "\n", "\t"):
                self.type_character(value, 0, done=self.type_next_part)
                return
            self.insert_text_part(value)
            return
        self.typing = False
        self.drain_input()

    def insert_text_part(self, value):
        def insert():
            try:
                result = insert_focused_text(value, self.stopped)
            except Exception as error:
                sys.stderr.write("desktop text input failed: %s\n" % type(error).__name__)
                result = "unsafe"

            def finished():
                if self.stopped.is_set():
                    return False
                if result == "inserted":
                    self.type_next_part()
                elif result == "unavailable" and (events := self.keymap_events(value)) is not None:
                    self.type_keymap_events(events, 0)
                else:
                    status("input_error", code="textUnsupported")
                    self.stop()
                return False

            GLib.idle_add(finished)

        threading.Thread(target=insert, daemon=True).start()

    def keymap_events(self, value):
        # Terminals and some other applications have no accessible editable field. Use their real keyboard layout
        # only when every character maps unambiguously in every keyboard group, including the current lock state.
        if self.keys.intersection({29, 42, 54, 56, 97, 100, 125, 126}):
            return None
        try:
            gi.require_version("Gdk", "3.0")
            from gi.repository import Gdk
            if self.keymap is None:
                Gdk.set_allowed_backends("wayland")
                self.keymap_display = Gdk.Display.open(os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
                if not self.keymap_display:
                    return None
                self.keymap = Gdk.Keymap.get_for_display(self.keymap_display)
            shift = int(Gdk.ModifierType.SHIFT_MASK)
            lock = int(Gdk.ModifierType.LOCK_MASK)
            num = int(Gdk.ModifierType.MOD2_MASK)
            modifiers = int(self.keymap.get_modifier_state())
            if modifiers & ~(lock | num):
                return None
            # A Wayland client without keyboard focus may receive no modifier state at all. GNOME exposes the
            # lock on its active remote desktop sessions; otherwise require the mapping to work with either state.
            caps = self.caps_lock_state()
            locks = [lock if caps else 0] if caps is not None else [0, lock]
            states = [locked | numlock for locked in locks for numlock in (0, num)]
            events = []
            for char in value:
                keyval = Gdk.unicode_to_keyval(ord(char))
                found, entries = self.keymap.get_entries_for_keyval(keyval)
                chosen = None
                for entry in entries if found else []:
                    code = entry.keycode - 8  # GDK/XKB codes include X11's offset; the portal takes evdev codes.
                    if not 0 < code < 768 or code in self.keys:
                        continue
                    for use_shift in (False, True):
                        translations = [self.keymap.translate_keyboard_state(entry.keycode, Gdk.ModifierType(state | (shift if use_shift else 0)), group)
                                        for state in states for group in range(4)]
                        if all(item[0] and item.keyval == keyval for item in translations):
                            chosen = code, use_shift
                            break
                    if chosen:
                        break
                if not chosen:
                    return None  # Preflight the whole string before sending any of it.
                code, use_shift = chosen
                if use_shift:
                    events.append((42, True))
                events.extend(((code, True), (code, False)))
                if use_shift:
                    events.append((42, False))
            return events
        except (ImportError, ValueError, GLib.Error, TypeError, AttributeError):
            return None

    def caps_lock_state(self):
        # This optional GNOME interface is private and may be absent on other compositors. Never rely on it unless
        # all visible sessions agree; the conservative keymap check above handles an unavailable result.
        service = "org.gnome.Mutter.RemoteDesktop"
        root = "/org/gnome/Mutter/RemoteDesktop/Session"
        try:
            reply = self.bus.call_sync(service, root, "org.freedesktop.DBus.Introspectable", "Introspect", None,
                                       GLib.VariantType.new("(s)"), Gio.DBusCallFlags.NONE, 1000, None)
            nodes = ET.fromstring(reply.unpack()[0]).findall("node")[:8]
            states = []
            for node in nodes:
                name = node.get("name", "")
                if not re.fullmatch(r"[A-Za-z0-9_]+", name):
                    continue
                reply = self.bus.call_sync(service, root + "/" + name, "org.freedesktop.DBus.Properties", "Get",
                                           GLib.Variant("(ss)", ("org.gnome.Mutter.RemoteDesktop.Session", "CapsLockState")),
                                           GLib.VariantType.new("(v)"), Gio.DBusCallFlags.NONE, 500, None)
                value = reply.unpack()[0]
                if isinstance(value, bool):
                    states.append(value)
            if states and all(state == states[0] for state in states):
                return states[0]
        except (GLib.Error, ET.ParseError, ValueError):
            pass
        return None

    def type_keymap_events(self, events, index):
        if self.stopped.is_set():
            return False
        if index == len(events):
            self.type_next_part()
            return False
        code, down = events[index]
        self.notify("NotifyKeyboardKeycode", "(oa{sv}iu)", [code, int(down)],
                    lambda: GLib.timeout_add(15, self.type_keymap_events, events, index + 1))
        self.keys.add(code) if down else self.keys.discard(code)
        return False

    def type_character(self, text, index, pressed=False, done=None):
        if not self.pipeline:
            self.typing = False
            return False
        if index >= len(text):
            if done:
                done()
            else:
                self.typing = False
                self.drain_input()
            return False
        char = text[index]
        codepoint = ord(char)
        keysym = {"\n": 0xff0d, "\r": 0xff0d, "\t": 0xff09}.get(char, codepoint if codepoint < 256 else 0x01000000 | codepoint)
        # Let the target read the press before releasing it and starting the next input.
        next_index = index + 1 if pressed else index
        self.notify("NotifyKeyboardKeysym", "(oa{sv}iu)", [keysym, 0 if pressed else 1],
                    lambda: GLib.timeout_add(KEYSYM_DELAY_MS, self.type_character, text, next_index, not pressed, done))
        return False

    def deliver_input(self, event):
        if not self.started or not self.logical:
            return
        kind = event.get("t")
        if kind in ("pointer", "wheel"):
            x = min(1.0, max(0.0, float(event.get("x", 0)))) * self.logical[0]
            y = min(1.0, max(0.0, float(event.get("y", 0)))) * self.logical[1]
            self.notify("NotifyPointerMotionAbsolute", "(oa{sv}udd)", [self.stream, x, y])
        if kind == "pointer":
            buttons = int(event.get("buttons", 0))
            for bit, code in ((1, 272), (2, 273), (4, 274)):
                down = bool(buttons & bit)
                if down != (code in self.buttons):
                    self.notify("NotifyPointerButton", "(oa{sv}iu)", [code, int(down)])
                    self.buttons.add(code) if down else self.buttons.discard(code)
        elif kind == "wheel":
            self.notify("NotifyPointerAxis", "(oa{sv}dd)", [float(event.get("dx", 0)), float(event.get("dy", 0))])
        elif kind == "key":
            keycode = event.get("keycode")
            if isinstance(keycode, int) and 0 < keycode < 768:
                down = event.get("kind") == "down"
                self.notify("NotifyKeyboardKeycode", "(oa{sv}iu)", [keycode, int(down)])
                self.keys.add(keycode) if down else self.keys.discard(keycode)

    def stop(self):
        self.stopped.set()
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None
        self.loop.quit()
        return False

    def close(self):
        self.stop()
        if self.session:
            # Release the virtual inputs this view held, even if it disconnected before the matching input arrived.
            for method, values in [
                *(("NotifyKeyboardKeycode", [key, 0]) for key in self.keys),
                *(("NotifyPointerButton", [button, 0]) for button in self.buttons),
            ]:
                try:
                    self.bus.call_sync(BUS, PATH, REMOTE, method,
                                       GLib.Variant("(oa{sv}iu)", tuple([self.session, {}] + values)),
                                       None, Gio.DBusCallFlags.NONE, 500, None)
                except GLib.Error:
                    pass
            try:
                self.bus.call_sync(BUS, self.session, SESSION, "Close", None, None, Gio.DBusCallFlags.NONE, 1000, None)
            except GLib.Error:
                pass
        if self.fd is not None:
            os.close(self.fd)
        if self.keymap_display:
            self.keymap_display.close()

    def commands(self):
        def handle(command):
            try:
                if command.get("op") == "start":
                    self.start(command)
                elif command.get("op") == "input":
                    self.input(command.get("event", {}))
                elif command.get("op") == "close":
                    self.stop()
            except Exception as error:
                status("error", message=str(error))
                self.stop()
            return False

        for line in sys.stdin:
            try:
                GLib.idle_add(handle, json.loads(line))
            except ValueError:
                continue
        GLib.idle_add(self.stop)


def main():
    Gst.init(None)
    for element in ("pipewiresrc", "queue", "identity", "videoconvert", "videoscale", "jpegenc", "appsink"):
        if not Gst.ElementFactory.find(element):
            raise RuntimeError("missing GStreamer component: " + element)
    portal = Portal()
    try:
        portal.prepare()
        threading.Thread(target=portal.commands, daemon=True).start()
        portal.loop.run()
    finally:
        portal.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        status("error", message=str(error))
        sys.exit(1)

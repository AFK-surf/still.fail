#!/usr/bin/python3
"""The station's desktop portal client. Its only stdout is framed JSON and JPEG for linux-portal.ts.

The portal owns both the capture and the virtual input devices; closing this process closes their session. The
station starts it only after someone opens the desktop, and a system dialog asks the desktop user to grant access.
"""
import json
import os
import struct
import sys
import threading
import uuid

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


class Portal:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
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
        # PipeWire can advertise a variable rate (0/1), which cannot be forced to a fixed rate by videorate on all
        # desktops. Keep only the newest pending buffer while spacing encoding work at the requested rate.
        self.pipeline = Gst.parse_launch("pipewiresrc name=source do-timestamp=true ! "
                                         "queue leaky=downstream max-size-buffers=1 max-size-bytes=0 max-size-time=0 ! "
                                         "identity sleep-time=%d ! videoconvert ! videoscale ! %s ! jpegenc quality=75 ! "
                                         "appsink name=sink emit-signals=true sync=false max-buffers=1 drop=true" % (1_000_000 // fps, caps))
        source = self.pipeline.get_by_name("source")
        source.set_property("fd", self.fd)
        source.set_property("path", str(self.stream))
        sink = self.pipeline.get_by_name("sink")
        sink.connect("new-sample", self.sample)
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self.message)
        if self.pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("could not start the desktop stream")

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

    def notify(self, method, signature, args):
        # A button press must reach the desktop before the key or release that follows it. Surface portal errors to
        # the view instead of silently dropping input when a session has been revoked.
        self.bus.call_sync(BUS, PATH, REMOTE, method, GLib.Variant(signature, tuple([self.session, {}] + args)),
                           None, Gio.DBusCallFlags.NONE, 3000, None)

    def input(self, event):
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
        elif kind == "text":
            for char in event.get("text", "")[:4096]:
                codepoint = ord(char)
                keysym = codepoint if codepoint < 256 else 0x01000000 | codepoint
                self.notify("NotifyKeyboardKeysym", "(oa{sv}iu)", [keysym, 1])
                self.notify("NotifyKeyboardKeysym", "(oa{sv}iu)", [keysym, 0])

    def stop(self):
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None
        self.loop.quit()
        return False

    def close(self):
        self.stop()
        if self.session:
            # These are this portal session's virtual devices. Release what the view held before closing the session.
            for method, signature, values in [
                *(('NotifyKeyboardKeycode', '(oa{sv}iu)', [key, 0]) for key in self.keys),
                *(('NotifyPointerButton', '(oa{sv}iu)', [button, 0]) for button in self.buttons),
            ]:
                try:
                    self.notify(method, signature, values)
                except GLib.Error:
                    pass  # The desktop may already have revoked the session.
            try:
                self.bus.call_sync(BUS, self.session, SESSION, "Close", None, None, Gio.DBusCallFlags.NONE, 3000, None)
            except GLib.Error:
                pass
        if self.fd is not None:
            os.close(self.fd)

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

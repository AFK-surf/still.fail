#!/usr/bin/python3
"""A damage-driven stream must deliver its last update, even when the desktop then stays still."""
import importlib.util
from pathlib import Path
import threading
import unittest

path = Path(__file__).resolve().parents[1] / "src/screens/linux-portal.py"
spec = importlib.util.spec_from_file_location("linux_portal_frames_test", path)
portal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portal)
Gst = portal.Gst
Gst.init(None)


class TestSource(portal.Portal):
    def __init__(self):
        super().__init__(session_bus=False)
        self.logical = (8, 8)
        self.frames = []
        self.changed = threading.Condition()

    def capture_source(self):
        return ("appsrc name=source is-live=true do-timestamp=true format=time "
                "caps=video/x-raw,format=RGB,width=8,height=8,framerate=0/1")

    def configure_source(self, source):
        self.source = source

    def sample(self, sink):
        sample = sink.emit("pull-sample")
        buf = sample.get_buffer()
        with self.changed:
            self.frames.append(buf.extract_dup(0, buf.get_size()))
            self.changed.notify_all()
        return Gst.FlowReturn.OK

    def push(self, color):
        data = bytes(color) * 64
        buf = Gst.Buffer.new_allocate(None, len(data), None)
        buf.fill(0, data)
        assert self.source.emit("push-buffer", buf) == Gst.FlowReturn.OK


def first_pixel(jpeg):
    pipeline = Gst.parse_launch("appsrc name=source caps=image/jpeg ! jpegdec ! videoconvert ! "
                                "video/x-raw,format=RGB ! appsink name=sink sync=false")
    try:
        pipeline.set_state(Gst.State.PLAYING)
        buf = Gst.Buffer.new_allocate(None, len(jpeg), None)
        buf.fill(0, jpeg)
        pipeline.get_by_name("source").emit("push-buffer", buf)
        pipeline.get_by_name("source").emit("end-of-stream")
        sample = pipeline.get_by_name("sink").emit("try-pull-sample", 5 * Gst.SECOND)
        if sample is None:
            raise AssertionError("the captured JPEG could not be decoded")
        return sample.get_buffer().extract_dup(0, 3)
    finally:
        pipeline.set_state(Gst.State.NULL)


class StreamFramesTest(unittest.TestCase):
    def test_the_final_damage_frame_is_delivered_after_pacing(self):
        view = TestSource()
        try:
            view.start({"maxWidth": 8, "maxHeight": 8, "fps": 2})
            view.push((255, 0, 0))
            with view.changed:
                self.assertTrue(view.changed.wait_for(lambda: len(view.frames) >= 1, timeout=5))
            # The next update arrives within the pacing interval and is the last one the source sends.
            view.push((0, 0, 255))
            with view.changed:
                self.assertTrue(view.changed.wait_for(lambda: len(view.frames) >= 2, timeout=5),
                                "the last screen update was lost while the source was idle")
                final = view.frames[-1]
            red, _green, blue = first_pixel(final)
            self.assertGreater(blue, red + 100)
        finally:
            if view.pipeline:
                view.pipeline.set_state(Gst.State.NULL)


if __name__ == "__main__":
    unittest.main()

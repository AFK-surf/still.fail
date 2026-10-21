///|
/// A remote screen's view, as still.fail's: the stream drawn when `on`, what it said shown and broken kept.
priv struct Screen {
  t : @ui.Tester
  s : @ui.Stream
  acks : Array[Double]
  broke : Ref[Int]
  on : Ref[Bool]
}

///|
fn screen(h264? : Bool = true) -> Screen {
  let cell : Ref[@ui.Stream?] = Ref::new(None)
  let on = Ref::new(true)
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        match cell.val {
          Some(s) if on.val => c.stream(s, h=Px(200.0)) |> ignore
          _ => ()
        }
      })
      |> ignore
    },
    h264~,
  )
  let acks = []
  let broke = Ref::new(0)
  let s = @ui.Stream::new(shown=fn(ts) { acks.push(ts) }, broken=fn() { broke.val += 1 })
  cell.val = Some(s)
  t.draw()
  { t, s, acks, broke, on }
}

///|
let avcc : Bytes = b"\x01\x42\xc0\x1f\xff\xe1\x00\x06\x67\x42\xc0\x1f\xda\x01\x01\x00\x04\x68\xce\x3c\x80"

///|
test "until a config and a key frame, frames are let go unseen, each said shown at the next frame" {
  let v = screen()
  // the host not asked for anything until a frame comes
  assert_eq(v.s.id(), 0)
  // no config yet: nothing decodes it
  v.s.frame(b"\x00\x00\x00\x01\x41", false, 10.0)
  assert_eq(v.s.id(), 1)
  assert_eq(v.t.stream_fed(v.s.id()), [])
  assert_eq(v.acks, [])
  v.t.draw()
  assert_eq(v.acks, [10.0])
  // a config: the frames before the next key frame let go
  v.s.h264(avcc, 1280, 800)
  v.s.frame(b"\x00\x00\x00\x01\x41", false, 20.0)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 30.0)
  v.s.frame(b"\x00\x00\x00\x01\x41", false, 40.0)
  assert_eq(v.t.stream_fed(v.s.id()), [
    "h264 1280x800 avcc=21", "frame key=true ts=30 bytes=5", "frame key=false ts=40 bytes=5",
  ])
  v.t.draw()
  assert_eq(v.acks, [10.0, 20.0])
  // nothing shows until a frame decodes
  assert_false(v.s.shown_any())
  assert_eq(v.s.size(), None)
  v.s.close()
}

///|
test "a frame decoded shows from the next frame, said shown once that frame is painted; its size the config's" {
  let v = screen()
  v.s.h264(avcc, 1280, 800)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 1234.0)
  // the host has it: not at rest, and said why
  v.t.draw()
  assert_false(v.t.at_rest())
  assert_true(v.t.rest_why().contains("stream 1 frame 1234"), msg=v.t.rest_why())
  assert_eq(v.acks, [])
  // decoded (its pixels the decoder's: the config's size is the picture's)
  v.t.stream_shows(v.s.id(), 1234.0, 1280, 816)
  v.t.draw()
  assert_eq(v.acks, [1234.0])
  assert_true(v.s.shown_any())
  assert_eq(v.s.shown_at(), Some(1234.0))
  assert_eq(v.s.size(), Some((1280, 800)))
  // the host told to show it
  assert_true(v.t.stream_fed(v.s.id()).contains("show ts=1234"))
  assert_true(v.t.at_rest(), msg=v.t.rest_why())
  // drawn as a picture, its frame named in the draw list
  assert_true(v.t.drawlist().contains("image 0 1280 \"stream 1280x800 ts=1234\""), msg=v.t.drawlist())
  v.s.close()
  v.t.assert_idle()
}

///|
test "frames the host let go are said shown, all up to the one it names; a JPEG's size is its own" {
  let v = screen(h264=false)
  v.s.jpeg(b"\xff\xd8", 1.0)
  v.s.jpeg(b"\xff\xd8", 2.0)
  v.s.jpeg(b"\xff\xd8", 3.0)
  v.t.draw()
  v.t.stream_drops(v.s.id(), 2.0)
  v.t.draw()
  assert_eq(v.acks, [2.0])
  // frame 3 still the host's
  assert_false(v.t.at_rest())
  assert_true(v.t.rest_why().contains("stream 1 frame 3"), msg=v.t.rest_why())
  assert_false(v.t.rest_why().contains("frame 1"), msg=v.t.rest_why())
  v.t.stream_shows(v.s.id(), 3.0, 640, 480)
  v.t.draw()
  assert_eq(v.acks, [2.0, 3.0])
  assert_eq(v.s.size(), Some((640, 480)))
  assert_true(v.t.at_rest(), msg=v.t.rest_why())
  v.s.close()
}

///|
test "a frame taken while the stream is not drawn is let go all the same: said shown" {
  let v = screen(h264=false)
  v.on.val = false
  v.s.jpeg(b"\xff\xd8", 7.0)
  v.t.stream_shows(v.s.id(), 7.0, 320, 200)
  v.t.draw()
  assert_eq(v.acks, [7.0])
  assert_false(v.t.drawlist().contains("stream"))
  // drawn again: the frame it took
  v.on.val = true
  v.t.draw()
  assert_true(v.t.drawlist().contains("\"stream 320x200 ts=7\""), msg=v.t.drawlist())
  v.s.close()
}

///|
test "a broken decoder is said at the next frame; frames are let go until a key frame" {
  let v = screen()
  v.s.h264(avcc, 640, 360)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  v.t.stream_shows(v.s.id(), 1.0, 640, 360)
  v.t.draw()
  v.t.stream_broken(v.s.id())
  assert_eq(v.broke.val, 0)
  v.t.draw()
  assert_eq(v.broke.val, 1)
  v.s.frame(b"\x00\x00\x00\x01\x41", false, 2.0)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 3.0)
  assert_eq(v.t.stream_fed(v.s.id()).filter(fn(l) { l.has_prefix("frame") }), [
    "frame key=true ts=1 bytes=5", "frame key=true ts=3 bytes=5",
  ])
  v.t.draw()
  assert_eq(v.acks, [1.0, 2.0])
  // still showing the last frame decoded
  assert_eq(v.s.shown_at(), Some(1.0))
  v.s.close()
}

///|
test "where the host decodes no H.264, frames are let go; JPEG still shows" {
  let v = screen(h264=false)
  assert_false(@ui.h264_here())
  v.s.h264(avcc, 640, 360)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 5.0)
  assert_eq(v.t.stream_fed(v.s.id()), ["h264 640x360 avcc=21"])
  v.t.draw()
  assert_eq(v.acks, [5.0])
  v.s.close()
}

///|
test "closed: the host told, its frames out no longer awaited, nothing more said or drawn" {
  let v = screen(h264=false)
  v.s.jpeg(b"\xff\xd8", 1.0)
  v.t.stream_shows(v.s.id(), 1.0, 100, 100)
  v.t.draw()
  v.s.jpeg(b"\xff\xd8", 2.0)
  v.t.draw()
  assert_false(v.t.at_rest())
  v.s.close()
  assert_eq(v.t.stream_fed(v.s.id())[v.t.stream_fed(v.s.id()).length() - 1], "close")
  v.t.stream_shows(v.s.id(), 2.0, 100, 100)
  v.t.draw()
  assert_eq(v.acks, [1.0])
  assert_false(v.t.drawlist().contains("stream"))
  v.s.jpeg(b"\xff\xd8", 3.0)
  v.t.assert_idle()
}

///|
test "a run's words of its streams, said again, show the same frames at the same frames" {
  let v = screen(h264=false)
  v.s.jpeg(b"\xff\xd8", 1500.0)
  v.t.draw()
  assert_true(v.t.view_said("{\"stream\":{\"id\":\{v.s.id()},\"e\":\"f 1500 800 600\"}}"))
  let before = v.t.frame_hash()
  v.t.draw()
  assert_eq(v.acks, [1500.0])
  assert_eq(v.s.size(), Some((800, 600)))
  // the frame shown is in what the frame drew
  assert_true(v.t.frame_hash() != before)
  assert_true(v.t.drawn_text().contains("stream 800x600 ts=1500"))
  assert_false(v.t.view_said("{\"stream\":{\"id\":\{v.s.id()}}}"))
  v.s.close()
}

///|
test "a run's tape replayed: its stream events taken at the frames they were taken at; its host's H.264 as it said" {
  // when each frame was said shown (the frame's time)
  let acks : Array[(Double, Double)] = []
  let cell : Ref[@ui.Stream?] = Ref::new(None)
  let view = fn(c : @ui.Ctx) {
    match cell.val {
      Some(s) => c.stream(s) |> ignore
      None => ()
    }
  }
  let period = @ui.frame_period_default
  let first = 1000.0 + period
  let run = "ENV {\"motion\":0,\"glass\":0,\"dark\":0,\"inset\":0,\"h264\":1}\nDRAWHASH 1 \{first} 390 844 2 0 0\n"
  let t = @ui.Tester::new(view, run~)
  assert_true(@ui.h264_here())
  let s = @ui.Stream::new(shown=fn(ts) { acks.push((ts, t.time())) }, broken=fn() {  })
  cell.val = Some(s)
  s.jpeg(b"\xff\xd8", 9.0)
  let at2 = first + period
  let at3 = first + 2.0 * period
  let tape = "DRAWHASH 2 \{at2} 390 844 2 0 0\nVIEWSAID {\"stream\":{\"id\":1,\"e\":\"f 9 64 48\"}}\nDRAWHASH 3 \{at3} 390 844 2 0 0\n"
  assert_eq(t.replay_frames(tape).length(), 2)
  // said between frames 2 and 3: taken at frame 3
  assert_eq(acks, [(9.0, at3)])
  assert_eq(s.size(), Some((64, 48)))
  s.close()
}

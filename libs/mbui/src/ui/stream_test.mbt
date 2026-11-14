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
  let cell : Ref[@ui.Stream?] = Ref(None)
  let on = Ref(true)
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
  let broke = Ref(0)
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
test "H.265: its config handed over and its frames decoded where the host decodes it; let go where it does not" {
  let v = screen()
  assert_false(@ui.h265_here())
  v.s.hevc(b"\x01\x01", 1920, 1080)
  v.s.frame(b"\x00\x00\x00\x01\x26", true, 5.0)
  // not here: nothing handed over, the frame let go
  assert_eq(v.t.stream_fed(v.s.id()), [])
  v.t.draw()
  assert_eq(v.acks, [5.0])
  v.t.set_h265(true)
  assert_true(@ui.h265_here())
  v.s.hevc(b"\x01\x01", 1920, 1080)
  v.s.frame(b"\x00\x00\x00\x01\x02", false, 6.0)
  v.s.frame(b"\x00\x00\x00\x01\x26", true, 7.0)
  assert_eq(v.t.stream_fed(v.s.id()), ["hevc 1920x1080 hvcc=2", "frame key=true ts=7 bytes=5"])
  v.t.stream_shows(v.s.id(), 7.0, 1920, 1088)
  v.t.draw()
  assert_eq(v.acks, [5.0, 6.0, 7.0])
  assert_eq(v.s.size(), Some((1920, 1080)))
  // H.264 again after it: as before
  v.s.h264(avcc, 640, 360)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 8.0)
  assert_eq(v.t.stream_fed(v.s.id()).last(), Some("frame key=true ts=8 bytes=5"))
  v.s.close()
}

///|
/// An av1C as an MP4's box holds it: marker and version, profile 0 level 8, 8-bit 4:2:0, then its sequence header OBU
/// (type 1, its size after it).
let av1c : Bytes = b"\x81\x08\x0c\x00\x0a\x0b\x00\x00\x00\x24\xc4\xff\xdf\x00\x68\x02\x10"

///|
test "AV1: asked before it is played; its config handed over and its frames decoded where the host decodes it, let go where it does not" {
  let v = screen()
  // (no AV1 decoder: an app plays it another way, and a stream given it lets its frames go)
  assert_false(@ui.av1_here())
  v.s.av1(av1c, 1280, 720)
  v.s.frame(b"\x12\x00\x32\x05\x10", true, 5.0)
  assert_eq(v.t.stream_fed(v.s.id()), [])
  v.t.draw()
  assert_eq(v.acks, [5.0])
  v.t.set_av1(true)
  assert_true(@ui.av1_here())
  // (not H.265's, nor H.264's: either may be had without it)
  assert_false(@ui.h265_here())
  v.s.av1(av1c, 1280, 720)
  v.s.frame(b"\x32\x03\x30\x00\x00", false, 6.0)
  v.s.frame(b"\x12\x00\x32\x05\x10", true, 7.0)
  v.s.frame(b"\x32\x03\x30\x00\x00", false, 8.0)
  assert_eq(v.t.stream_fed(v.s.id()), [
    "av1 1280x720 av1c=17", "frame key=true ts=7 bytes=5", "frame key=false ts=8 bytes=5",
  ])
  v.t.stream_shows(v.s.id(), 7.0, 1280, 720)
  v.t.stream_shows(v.s.id(), 8.0, 1280, 720)
  v.t.draw()
  assert_eq(v.acks, [5.0, 6.0, 7.0, 8.0])
  assert_eq(v.s.shown_at(), Some(8.0))
  assert_eq(v.s.size(), Some((1280, 720)))
  // a seek: emptied, and nothing taken till the next key frame
  v.s.flush()
  v.s.frame(b"\x32\x03\x30\x00\x00", false, 9.0)
  v.s.frame(b"\x12\x00\x32\x05\x10", true, 10.0)
  assert_eq(v.t.stream_fed(v.s.id()).filter(fn(l) { l.has_prefix("frame") }).last(), Some(
    "frame key=true ts=10 bytes=5",
  ))
  // H.264 again after it: as before, whether or not AV1 is decoded
  v.t.set_av1(false)
  v.s.h264(avcc, 640, 360)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 11.0)
  assert_eq(v.t.stream_fed(v.s.id()).last(), Some("frame key=true ts=11 bytes=5"))
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
  let cell : Ref[@ui.Stream?] = Ref(None)
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

///|
test "a host whose decoder is driven from here: told what to do, its words taken in their order, the frame shown" {
  let v = screen()
  v.t.set_stream_feeds(true)
  v.s.h264(avcc, 640, 360)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 100.0)
  let id = v.s.id()
  assert_eq(v.t.stream_fed(id), ["h264 640x360 avcc=21", "do start 1"])
  v.t.stream_codec_said(id, "up 1")
  v.t.stream_codec_said(id, "in 1 0")
  v.t.draw()
  v.t.stream_codec_said(id, "out 1 0 100 1")
  v.t.draw()
  assert_eq(v.acks, [])
  v.t.stream_codec_said(id, "arr 1")
  v.t.draw()
  assert_eq(v.t.stream_fed(id)[2:].to_owned(), [
    "do queue 1 0 100 1 bytes=5", "do release 1 0 100", "do latch 100 1 640 360",
  ])
  v.t.draw()
  assert_eq(v.acks, [100.0])
  assert_eq(v.s.shown_at(), Some(100.0))
}

///|
test "driven from here: a decoder that fails before its frame arrived, the frame's late arrival does not hold the stream" {
  let v = screen()
  v.t.set_stream_feeds(true)
  v.s.h264(avcc, 640, 360)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 100.0)
  let id = v.s.id()
  for e in ["up 1", "in 1 0", "out 1 0 100 1", "err 1", "arr 1", "up 2", "in 2 0"] {
    v.t.stream_codec_said(id, e)
  }
  v.t.draw()
  assert_eq(v.broke.val, 1)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 200.0)
  v.t.stream_codec_said(id, "out 2 0 200 1")
  v.t.stream_codec_said(id, "arr 1")
  v.t.draw()
  v.t.draw()
  assert_eq(v.acks, [100.0, 200.0])
  assert_eq(v.s.shown_at(), Some(200.0))
  let fed = v.t.stream_fed(id)
  assert_eq(fed[fed.length() - 3:].to_owned(), ["do drop 1", "do release 2 0 200", "do latch 200 1 640 360"])
}

///|
test "a frame not to be shown is handed over as such, its fate said shown, never latched; a host with nothing for it lets it go here" {
  let v = screen()
  v.s.h264(avcc, 640, 360)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  let id = v.s.id()
  v.t.stream_shows(id, 1.0, 640, 360)
  v.t.draw()
  assert_eq(v.s.shown_at(), Some(1.0))
  v.s.frame(b"\x00\x00\x00\x01\x41", false, 2.0, show=false)
  v.s.frame(b"\x00\x00\x00\x01\x41", false, 3.0, show=false)
  assert_eq(v.t.stream_fed(id).filter(fn(l) { l.has_prefix("frame") }), [
    "frame key=true ts=1 bytes=5", "frame key=false ts=2 bytes=5 hidden", "frame key=false ts=3 bytes=5 hidden",
  ])
  // the host's until its event: let go ("d"), or even said decoded ("f": a host that does), it is never shown
  v.t.draw()
  assert_false(v.t.at_rest())
  assert_true(v.t.rest_why().contains("stream 1 frame 2"), msg=v.t.rest_why())
  v.t.stream_drops(id, 2.0)
  v.t.stream_shows(id, 3.0, 640, 360)
  v.t.draw()
  assert_eq(v.acks, [1.0, 2.0, 3.0])
  assert_eq(v.s.shown_at(), Some(1.0))
  assert_false(v.t.stream_fed(id).contains("show ts=3"))
  assert_true(v.t.at_rest(), msg=v.t.rest_why())
  assert_true(v.t.drawlist().contains("\"stream 640x360 ts=1\""), msg=v.t.drawlist())
  // a frame shown after them shows as ever
  v.s.frame(b"\x00\x00\x00\x01\x41", false, 4.0)
  v.t.stream_shows(id, 4.0, 640, 360)
  v.t.draw()
  assert_eq(v.s.shown_at(), Some(4.0))
  // a host with nothing for one: not handed over, let go here, said shown at the next frame
  v.t.set_stream_hides(false)
  v.s.frame(b"\x00\x00\x00\x01\x41", false, 5.0, show=false)
  assert_false(v.t.stream_fed(id).any(fn(l) { l.contains("ts=5") }))
  v.t.draw()
  assert_eq(v.acks, [1.0, 2.0, 3.0, 4.0, 5.0])
  assert_eq(v.s.shown_at(), Some(4.0))
  v.s.close()
}

///|
test "a flush is handed over in its place among the frames; after it a frame not key is let go here till a key frame" {
  let v = screen()
  v.s.h264(avcc, 640, 360)
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  let id = v.s.id()
  v.t.stream_shows(id, 1.0, 640, 360)
  v.t.draw()
  v.s.frame(b"\x00\x00\x00\x01\x41", false, 2.0)
  v.s.flush()
  v.s.frame(b"\x00\x00\x00\x01\x41", false, 3.0)
  assert_eq(v.t.stream_fed(id)[1:].to_owned(), [
    "frame key=true ts=1 bytes=5", "show ts=1", "frame key=false ts=2 bytes=5", "flush drain=false",
  ])
  // what was in the decoder let go by the host; the one after it by the app; the picture shown stays
  v.t.stream_drops(id, 2.0)
  v.t.draw()
  assert_eq(v.acks, [1.0, 3.0, 2.0])
  assert_eq(v.s.shown_at(), Some(1.0))
  assert_true(v.t.at_rest(), msg=v.t.rest_why())
  // from a key frame on, as ever; drained, the same
  v.s.frame(b"\x00\x00\x00\x01\x65", true, 4.0)
  v.s.flush(drain=true)
  let fed = v.t.stream_fed(id)
  assert_eq(fed[fed.length() - 2:].to_owned(), ["frame key=true ts=4 bytes=5", "flush drain=true"])
  v.s.close()
}

///|
test "its sound's clock is the host's: samples played and milliseconds queued, 0 before it opens and once closed" {
  let v = screen()
  v.t.set_stream_audio(true)
  assert_eq(v.s.audio_played(), 0.0)
  assert_eq(v.s.audio_queued(), 0.0)
  v.s.audio(Bytes::make(3840, b'\x00'))
  let id = v.s.id()
  assert_eq(v.s.audio_played(), 0.0)
  v.t.set_stream_audio_clock(id, 96000.0, 60.0)
  assert_eq(v.s.audio_played(), 96000.0)
  assert_eq(v.s.audio_queued(), 60.0)
  v.s.close()
  assert_eq(v.s.audio_played(), 0.0)
  assert_eq(v.s.audio_queued(), 0.0)
}

///|
test "its sound's volume told the host: one asked before it opened as it opens, then as asked" {
  let v = screen()
  v.t.set_stream_audio(true)
  v.s.audio_volume(0.5)
  assert_eq(v.s.id(), 0)
  v.s.audio(Bytes::make(3840, b'\x00'))
  let id = v.s.id()
  assert_eq(v.t.stream_fed(id), ["volume 0.5", "audio bytes=3840"])
  v.s.audio_volume(0.0)
  assert_eq(v.t.stream_fed(id).last(), Some("volume 0"))
  v.s.close()
  v.s.audio_volume(1.0)
  assert_eq(v.t.stream_fed(id).last(), Some("close"))
}

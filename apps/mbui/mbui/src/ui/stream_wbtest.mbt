// Stream's frames let go here, against the frame that takes them (stream.mbt Stream::let_go).

///|
let wb_avcc : Bytes = b"\x01\x42\xc0\x1f\xff\xe1\x00\x06\x67\x42\xc0\x1f\xda\x01\x01\x00\x04\x68\xce\x3c\x80"

///|
test "a frame let go in a frame that took its events already: the next frame is owed, takes it and says it shown" {
  let cell : Ref[Stream?] = Ref::new(None)
  let feed : Ref[Bool] = Ref::new(false)
  let t = Tester::new(
    fn(c) {
      match cell.val {
        Some(s) => {
          c.stream(s, h=Px(200.0)) |> ignore
          if feed.val {
            feed.val = false
            // handed over while the frame builds, its events taken as it began: before any key frame, let go here
            s.frame(b"\x00\x00\x00\x01\x41", false, 7.0)
          }
        }
        None => ()
      }
    },
    h264=true,
  )
  let acks = []
  let s = Stream::new(shown=fn(ts) { acks.push(ts) }, broken=fn() {  })
  cell.val = Some(s)
  s.h264(wb_avcc, 640, 360)
  t.draw()
  feed.val = true
  // one frame only: the one that lets it go
  t.frame()
  assert_eq(acks, [])
  assert_false(t.at_rest())
  // the next is owed (else none would come and the frame would stay out for good)
  assert_true(t.owed_now())
  // drawn, it takes the "d" and says it shown once painted
  t.draw()
  assert_eq(acks, [7.0])
  assert_true(t.at_rest(), msg=t.rest_why())
  s.close()
}

///|
test "a frame handed to a stream by a message taken as it comes builds nothing for the message: the frame let go is taken, said shown" {
  let cell : Ref[Stream?] = Ref::new(None)
  let t = Tester::new(
    fn(c) {
      match cell.val {
        Some(s) => c.stream(s, h=Px(200.0)) |> ignore
        None => ()
      }
    },
    h264=true,
  )
  let acks = []
  let s = Stream::new(shown=fn(ts) { acks.push(ts) }, broken=fn() {  })
  cell.val = Some(s)
  s.h264(wb_avcc, 640, 360)
  // a remote screen's frame as the core's quiet value comes (still.fail's @core.quiet): handed to the decoder before
  // the frame is decided, nothing a build reads changed
  on_message_said("test.frame", fn(j, _) {
    if j == "frame" {
      s.frame(b"\x00\x00\x00\x01\x41", false, 9.0)
    }
    true
  })
  t.draw()
  // one that changes nothing: no frame built for it
  t.post("test.frame", "nothing")
  t.run_for(said_frame_ms)
  assert_eq(t.built_why(), "")
  // a frame, before any key frame: let go, taken by what the stream said itself, said shown
  t.post("test.frame", "frame")
  t.run_for(2.0 * said_frame_ms)
  assert_eq(acks, [9.0])
  t.draw()
  assert_true(t.at_rest(), msg=t.rest_why())
  s.close()
}

///|
test "a stream shown by its system video layer: its hole painted, a frame of its size taken as it comes, said shown, nothing built" {
  let cell : Ref[Stream?] = Ref::new(None)
  let layer : Ref[Bool] = Ref::new(true)
  let t = Tester::new(
    fn(c) {
      match cell.val {
        Some(s) => c.stream(s, w=Px(320.0), h=Px(180.0), layer=layer.val) |> ignore
        None => ()
      }
    },
    h264=true,
  )
  t.set_stream_layers(true)
  let acks = []
  let quiet : Ref[Bool] = Ref::new(true)
  let s = Stream::new(shown=fn(ts) { acks.push(ts) }, broken=fn() {  }, layer=true, quiet=Some(fn(_) { quiet.val }))
  cell.val = Some(s)
  s.h264(wb_avcc, 640, 360)
  t.draw()
  // its layer a native view of kind 4, the stream's
  assert_true(t.fake.views.iter().any(fn(l) { l == "open 1 4 1" }), msg="\{t.fake.views}")
  // the first frame: built, the view placed where the picture is
  s.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(s.id(), 1.0, 640, 360)
  t.draw()
  assert_eq(acks, [1.0])
  assert_true(t.fake.views.iter().any(fn(l) { l.has_prefix("place 1 0 0 320 180") && !l.contains("hidden") }), msg="\{t.fake.views}")
  // the next, of its size: taken as it comes, shown and said shown, nothing built for it
  s.frame(b"\x00\x00\x00\x01\x41", false, 2.0)
  t.stream_shows(s.id(), 2.0, 640, 360)
  t.frame_at(t.fake.time + said_frame_ms)
  assert_eq(acks, [1.0, 2.0])
  assert_eq(t.built_why(), "")
  assert_true(t.stream_fed(s.id()).contains("show ts=2"), msg="\{t.stream_fed(s.id())}")
  // between frames, as a host whose streams show themselves tells it (outside_streamed): taken then, no frame drawn
  s.frame(b"\x00\x00\x00\x01\x41", false, 2.2)
  t.stream_shows(s.id(), 2.2, 640, 360)
  let frames = t.frames
  on_outside(outside_streamed, s.id(), 0)
  assert_eq(acks, [1.0, 2.0, 2.2])
  assert_eq(t.frames, frames)
  // one the app says changes what it draws around it (Stream::new's `quiet`): built
  quiet.val = false
  s.frame(b"\x00\x00\x00\x01\x41", false, 2.5)
  t.stream_shows(s.id(), 2.5, 640, 360)
  t.frame_at(t.fake.time + said_frame_ms)
  assert_true(t.built_why() != "")
  assert_eq(acks, [1.0, 2.0, 2.2, 2.5])
  quiet.val = true
  // another size (a config of it): built, as before
  s.h264(wb_avcc, 1280, 720)
  s.frame(b"\x00\x00\x00\x01\x65", true, 3.0)
  t.stream_shows(s.id(), 3.0, 1280, 720)
  t.frame_at(t.fake.time + said_frame_ms)
  assert_true(t.built_why() != "")
  assert_eq(acks, [1.0, 2.0, 2.2, 2.5, 3.0])
  t.draw()
  // drawn by the app (faded, under the dark): its view hidden, its frames taken as the frame is built
  layer.val = false
  t.draw()
  assert_true(t.fake.views.last().unwrap().contains("hidden"), msg="\{t.fake.views}")
  s.frame(b"\x00\x00\x00\x01\x41", false, 4.0)
  t.stream_shows(s.id(), 4.0, 640, 360)
  t.draw()
  assert_eq(acks, [1.0, 2.0, 2.2, 2.5, 3.0, 4.0])
  assert_true(t.at_rest(), msg=t.rest_why())
  s.close()
  t.draw()
  assert_true(t.fake.views.last().unwrap() == "close 1", msg="\{t.fake.views}")
}

///|
test "a stream shown by its layer has its route's frames taken by the host while it shows itself: what came so said by one event, nothing built" {
  let cell : Ref[Stream?] = Ref::new(None)
  let layer : Ref[Bool] = Ref::new(true)
  let t = Tester::new(
    fn(c) {
      match cell.val {
        Some(s) => c.stream(s, w=Px(320.0), h=Px(180.0), layer=layer.val) |> ignore
        None => ()
      }
    },
    h264=true,
  )
  t.set_stream_layers(true)
  let acks = []
  let s = Stream::new(shown=fn(ts) { acks.push(ts) }, broken=fn() {  }, layer=true, quiet=Some(fn(_) { true }))
  cell.val = Some(s)
  s.h264(wb_avcc, 640, 360)
  t.draw()
  let routes = fn() { t.stream_fed(s.id()).filter(fn(l) { l.has_prefix("route") }) }
  // nothing shown yet: its sound alone
  s.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  s.route(7, 11.0, video=true, audio=true)
  assert_eq(routes(), ["route 7 after=11 video=false audio=true"])
  t.stream_shows(s.id(), 1.0, 640, 360)
  t.draw()
  // a frame of it shown on its layer: its frames too
  s.frame(b"\x00\x00\x00\x01\x41", false, 2.0)
  s.route(7, 12.0, video=true, audio=true)
  assert_eq(routes()[1:].to_array(), ["route 7 after=12 video=true audio=true"])
  t.stream_shows(s.id(), 2.0, 640, 360)
  t.frame_at(t.fake.time + said_frame_ms)
  assert_eq(acks, [1.0, 2.0])
  // what the host took (shown and said shown there): counted and shown from, as it comes; nothing built, none said
  // shown again
  fake_said(t.fake, s.id(), "D 5 3 3000")
  t.frame_at(t.fake.time + said_frame_ms)
  assert_eq(t.built_why(), "")
  assert_eq(s.shown_at(), Some(5.0))
  assert_eq(s.direct_count(), (3, 3000))
  assert_eq(acks, [1.0, 2.0])
  // none shown yet by the route (a config since): counted alone
  fake_said(t.fake, s.id(), "D -1 1 10")
  t.frame_at(t.fake.time + said_frame_ms)
  assert_eq((s.shown_at(), s.direct_count()), (Some(5.0), (4, 3010)))
  // drawn by the app now (not on its layer): its frames its own again as the next frame begins, its sound still routed
  layer.val = false
  t.draw()
  t.draw()
  assert_eq(routes()[2:].to_array(), ["route 7 after=-1 video=false audio=true"])
  // not asked again while nothing changes
  t.draw()
  assert_eq(routes().length(), 3)
  s.close()
}

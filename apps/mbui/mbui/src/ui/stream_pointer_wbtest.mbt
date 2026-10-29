// A pointer over a stream's picture drawn by its host on the stream's layer (stream_pointer.mbt).

///|
test "a pointer on a stream's layer: its picture told once, each move told at once, between frames too, nothing built" {
  let cell : Ref[Stream?] = Ref::new(None)
  let t = Tester::new(
    fn(c) {
      match cell.val {
        Some(s) => c.stream(s, w=Px(320.0), h=Px(180.0)) |> ignore
        None => ()
      }
    },
    h264=true,
  )
  t.set_stream_layers(true)
  let s = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true)
  cell.val = Some(s)
  s.h264(wb_avcc, 640, 360)
  t.draw()
  // not on its layer before a frame of it shows
  assert_false(s.layered())
  s.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(s.id(), 1.0, 640, 360)
  t.draw()
  assert_true(s.layered())
  let png_asked = Ref::new(0)
  let png = fn() {
    png_asked.val += 1
    b"png"
  }
  s.pointer_image("arrow", png, 20.0, 20.0, 1.0, 1.0)
  s.pointer_image("arrow", png, 20.0, 20.0, 1.0, 1.0)
  s.pointer_at(Some((0.5, 0.25)))
  // the same again: not told again
  s.pointer_at(Some((0.5, 0.25)))
  // between frames: told as it comes, no frame asked, nothing built
  let frames = t.frames
  s.pointer_at(Some((0.75, 0.5)))
  assert_eq(t.frames, frames)
  t.frame_at(t.fake.time + said_frame_ms)
  assert_eq(t.built_why(), "")
  s.pointer_at(None)
  s.pointer_image("text", png, 20.0, 20.0, 10.0, 10.0)
  let told = t.stream_fed(s.id()).filter(fn(l) { l.has_prefix("pointer") })
  assert_eq(told, [
    "pointer arrow 20x20 hot=1,1", "pointer at 0.5 0.25", "pointer at 0.75 0.5", "pointer none", "pointer text 20x20 hot=10,10",
  ])
  // (the fake keeps no picture: never made)
  assert_eq(png_asked.val, 0)
  assert_true(t.at_rest(), msg=t.rest_why())
  s.close()
}

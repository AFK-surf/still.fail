///|
/// A GIF 2 by 1 of two frames, 100 ms each: red, then blue (its two colours its table's; each frame's indices coded
/// with codes of 3 bits: clear, the index twice, end).
fn two_frames() -> Bytes {
  Bytes::from_array([
    b'G', b'I', b'F', b'8', b'9', b'a', b'\x02', b'\x00', b'\x01', b'\x00', b'\x80', b'\x00', b'\x00',
    // the colours: red, blue
    b'\xFF', b'\x00', b'\x00', b'\x00', b'\x00', b'\xFF',
    // a frame: its graphic control (100 ms), its place, its indices [0, 0]
    b'\x21', b'\xF9', b'\x04', b'\x00', b'\x0A', b'\x00', b'\x00', b'\x00', b'\x2C', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x02', b'\x00', b'\x01', b'\x00', b'\x00', b'\x02', b'\x02', b'\x04', b'\x0A', b'\x00',
    // the next: [1, 1]
    b'\x21', b'\xF9', b'\x04', b'\x00', b'\x0A', b'\x00', b'\x00', b'\x00', b'\x2C', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x02', b'\x00', b'\x01', b'\x00', b'\x00', b'\x02', b'\x02', b'\x4C', b'\x0A', b'\x00', b'\x3B',
  ])
}

///|
test "a GIF's frames: each as its canvas shows it, how long each stays" {
  let g = @ui.gif_frames(two_frames()).unwrap()
  assert_eq((g.w, g.h, g.frames.length()), (2, 1, 2))
  assert_eq(g.delays, [100.0, 100.0])
  assert_eq([g.frames[0][0], g.frames[0][1], g.frames[0][2], g.frames[0][3]], [b'\xFF', b'\x00', b'\x00', b'\xFF'])
  assert_eq([g.frames[1][4], g.frames[1][5], g.frames[1][6], g.frames[1][7]], [b'\x00', b'\x00', b'\xFF', b'\xFF'])
  assert_true(@ui.gif_frames(b"\x89PNG") is None)
}

///|
test "a GIF handed over moves: its frames in turn on the frames' clock; held still, its first" {
  @ui.add_image("mem:gif", two_frames())
  let still = Ref(false)
  let t = @ui.Tester::new(
    fn(c) { c.image("mem:gif", w=Px(20.0), h=Px(10.0), fade=false, still=still.val) |> ignore },
    w=100.0,
    h=100.0,
    images=[("mem:gif", 2, 1), ("mem:gif#0", 2, 1), ("mem:gif#1", 2, 1)],
  )
  // (handed over again: a Tester starts with no images)
  @ui.add_image("mem:gif", two_frames())
  t.draw()
  let shown = fn() {
    t.drawlist().split("\n").filter(fn(l) { l.has_prefix("image ") }).map(fn(l) { l.to_owned() }).to_array()
  }
  t.run_for(a_moment)
  assert_true(shown().iter().any(fn(l) { l.contains("\"mem:gif#0\"") }))
  t.run_for(gif_frame)
  assert_true(shown().iter().any(fn(l) { l.contains("\"mem:gif#1\"") }))
  t.run_for(gif_frame)
  assert_true(shown().iter().any(fn(l) { l.contains("\"mem:gif#0\"") }))
  still.val = true
  t.draw()
  t.run_for(a_moment)
  assert_true(shown().iter().any(fn(l) { l.contains("\"mem:gif\"") }))
}

///|
test "a GIF in a part kept moves with nothing else changing: built again as its next frame comes, the pointer away" {
  @ui.add_image("mem:gif", two_frames())
  let t = @ui.Tester::new(
    fn(c) {
      c.kept_part(c.id("part"), "", fn() {
        c.image("mem:gif", w=Px(20.0), h=Px(10.0), fade=false) |> ignore
      })
    },
    w=100.0,
    h=100.0,
    images=[("mem:gif", 2, 1), ("mem:gif#0", 2, 1), ("mem:gif#1", 2, 1)],
  )
  t.keep_parts(true)
  @ui.add_image("mem:gif", two_frames())
  t.draw()
  let shown = fn() {
    t.drawlist().split("\n").filter(fn(l) { l.has_prefix("image ") }).map(fn(l) { l.to_owned() }).to_array()
  }
  t.move(90.0, 90.0)
  t.run_for(a_moment)
  assert_true(shown().iter().any(fn(l) { l.contains("\"mem:gif#0\"") }))
  t.run_for(gif_frame)
  assert_true(shown().iter().any(fn(l) { l.contains("\"mem:gif#1\"") }))
  t.run_for(gif_frame)
  assert_true(shown().iter().any(fn(l) { l.contains("\"mem:gif#0\"") }))
}

///|
/// How long each frame of the GIF above stays, and a moment into one.
let gif_frame : Double = 100.0

///|
let a_moment : Double = 10.0

///|
test "an SVG handed over goes to the host drawn as a picture, at the size it is shown at" {
  let asked : Array[Int] = []
  @ui.set_vector_pictures(fn(data, px) {
    ignore(data)
    asked.push(px)
    Some((2, 1, FixedArray::make(8, b'\xFF')))
  })
  let svg = b"<svg xmlns='http://www.w3.org/2000/svg' width='2' height='1'/>"
  let t = @ui.Tester::new(
    fn(c) { c.image("mem:svg", w=Px(100.0), h=Px(50.0), fade=false) |> ignore },
    w=200.0,
    h=200.0,
  )
  // (handed over again: a Tester starts with no images)
  @ui.add_image("mem:svg", svg)
  t.draw()
  t.run_for(a_moment)
  // drawn at the decode's size (100 wide at the Tester's scale 2: 200 px, its bucket 256), handed to the host as a PNG,
  // not as the SVG's text
  assert_eq(asked, [256])
  let loads = t.image_loads()
  assert_true(loads.length() == 1 && loads[0].0 != "bytes:\{svg.length()}")
  // (the tests after this one draw no vector pictures)
  @ui.set_vector_pictures(fn(_, _) { None })
}

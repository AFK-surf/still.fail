// A node's own clip as it is painted (View::clip_drawn): what it holds cut to a rect said as each frame is painted,
// whether or not it clips to itself; said again, what it holds drawn again where it is.

///|
/// Under a 200 high band, a node 200 by 56 cutting what it holds to `rect` (in its own terms; it does not clip to
/// itself), holding a ground 300 by 100 (wider and taller than it).
fn clip_drawn_tester(rect : @signals.Signal[(Double, Double, Double, Double)?]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(200.0))).ground(Is(0x3366CCFFL)) |> ignore }) |> ignore
    root.box(fn(b) {
      b.width(Is(Some(200.0))).height(Is(Some(56.0))).clip_drawn(By(fn() { rect.get() })) |> ignore
      b.box(fn(k) {
        k.over(Is(true)) |> ignore
        k.box(fn(g) { g.width(Is(Some(300.0))).height(Is(Some(100.0))).ground(Is(0xFFFFFFFFL)) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  t
}

///|
/// The white ground's line in what was drawn (its clip with it, x0,y0,x1,y1 in the window).
fn white_line(t : Tester) -> String {
  t.frame_export().filter(fn(l) { l.contains("#ffffff") }).join("\n")
}

///|
test "a node's clip as painted (View::clip_drawn): what it holds cut to it, though it does not clip to itself; none, not cut" {
  let rect = @signals.signal(Some((10.0, 5.0, 50.0, 20.0)), same=fn(a, b) { a == b })
  let t = clip_drawn_tester(rect)
  assert_true(white_line(t).contains("clip=10,205,60,225"), msg=white_line(t))
  rect.set(None)
  t.frame()
  // (not cut by it: the ground whole, past the node's own box)
  assert_false(white_line(t).contains("clip=10,205,60,225"), msg=white_line(t))
  assert_true(white_line(t).contains(" 300 100 "), msg=white_line(t))
}

///|
test "a node's clip as painted said again: what it holds drawn again, where it is cut then" {
  let rect = @signals.signal(Some((10.0, 5.0, 50.0, 20.0)), same=fn(a, b) { a == b })
  let t = clip_drawn_tester(rect)
  let first = t.frame_export()
  t.record_host()
  rect.set(Some((40.0, 10.0, 100.0, 30.0)))
  t.frame()
  let frames = t.host_frames()
  // (drawn again where it was cut and where it is: within the white ground, under the band)
  let outside = frames.filter(fn(f) {
    f.damage.iter().any(fn(d) { d.2 < 0.0 || d.0 < -2.0 || d.1 < 200.0 - 2.0 || d.1 + d.3 > 300.0 + 2.0 || d.0 + d.2 > 300.0 + 2.0 })
  })
  assert_eq(outside.length(), 0, msg="\{frames}")
  assert_true(frames.iter().any(fn(f) { f.changed && f.layers_drawn > 0 }), msg="\{frames}")
  assert_true(t.frame_export() != first)
  assert_true(white_line(t).contains("clip=40,210,140,240"), msg=white_line(t))
}

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

///|
test "a node's clip as painted: what it cuts away is pressed nowhere, what it shows is" {
  let rect = @signals.signal(Some((10.0, 5.0, 50.0, 20.0)), same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(200.0))) |> ignore }) |> ignore
    root.box(fn(b) {
      b.width(Is(Some(200.0))).height(Is(Some(56.0))).clip_drawn(By(fn() { rect.get() })) |> ignore
      b.box(fn(k) {
        k
        .width(Is(Some(200.0)))
        .height(Is(Some(56.0)))
        .ground(Is(0xFFFFFFFFL))
        .presses(Is(true))
        .on_press(fn() { pressed.val += 1 })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  // (cut away: in the key's box, outside the rect it is cut to)
  t.tap(150.0, 240.0)
  t.frame()
  assert_eq(pressed.val, 0)
  // (shown: within the rect)
  t.tap(30.0, 215.0)
  t.frame()
  assert_eq(pressed.val, 1)
  // (none: all of it pressed)
  rect.set(None)
  t.frame()
  t.tap(150.0, 240.0)
  t.frame()
  assert_eq(pressed.val, 2)
}

///|
test "a node's clip as painted rounds its corners as its own are; square where it has none" {
  let radius = @signals.signal(8.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(200.0)))
      .height(Is(Some(56.0)))
      .radius(By(fn() { radius.get() }))
      .clip_drawn(Is(Some((10.0, 5.0, 50.0, 20.0))))
      |> ignore
      b.box(fn(g) { g.width(Is(Some(300.0))).height(Is(Some(100.0))).ground(Is(0xFFFFFFFFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  // (the white ground, the last drawn: its clip's corners' radii, 24 to 27)
  let corners = fn() {
    let all = t.drawn_instances()
    let a = all[all.length() - 1]
    (a[24], a[25], a[26], a[27])
  }
  let (tl, tr, br, bl) = corners()
  assert_true(tl > 0.0 && tl == tr && tr == br && br == bl, msg="\{corners()}")
  radius.set(0.0)
  t.frame()
  assert_eq(corners(), (0.0, 0.0, 0.0, 0.0))
}

///|
test "a node's clip as painted, round: what its round corners cut away pressed nowhere, as an old view's round clip; within them pressed; a still pointer worked out again as its corners alone are said again" {
  let radius = @signals.signal(8.0, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform=0)
  let key : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(200.0))) |> ignore }) |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(200.0)))
      .height(Is(Some(56.0)))
      .radius(By(fn() { radius.get() }))
      .clip_drawn(Is(Some((10.0, 5.0, 50.0, 20.0))))
      |> ignore
      b.box(fn(k) {
        key.val = Some(k)
        k
        .width(Is(Some(200.0)))
        .height(Is(Some(56.0)))
        .ground(Is(0xFFFFFFFFL))
        .presses(Is(true))
        .on_press(fn() { pressed.val += 1 })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  // (in its rect's corner, where its round corner cuts it away: not)
  t.tap(10.5, 205.5)
  t.frame()
  assert_eq(pressed.val, 0)
  // (within its round corners: pressed)
  t.tap(16.0, 211.0)
  t.frame()
  assert_eq(pressed.val, 1)
  // (the pointer still at the corner: over it once its corners are square, not once they are round again)
  let k = key.val.unwrap()
  t.move(10.5, 205.5)
  t.frame()
  assert_false(k.pointed())
  t.record_host()
  radius.set(0.0)
  t.frame_at(t.next_frame_time())
  assert_true(k.pointed(), msg="over it as its clip's corners are square")
  t.tap_once(10.5, 205.5)
  assert_eq(pressed.val, 2)
  t.move(10.5, 205.5)
  radius.set(8.0)
  t.frame_at(t.next_frame_time())
  assert_false(k.pointed(), msg="not as they are round")
}

// A node drawn at a size of its own as it is painted (View::drawn_size): its ground that big from where it is laid out,
// pressed where it is drawn; said again, its own layer drawn again where it was and is.

///|
/// Under a 200 high band, a node laid out 100 by 50, drawn `size`, a white ground, pressed into `pressed`.
fn drawn_size_tester(size : @signals.Signal[(Double, Double)?], pressed : Ref[Int]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(200.0))) |> ignore }) |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(100.0)))
      .height(Is(Some(50.0)))
      .ground(Is(0xFFFFFFFFL))
      .drawn_size(By(fn() { size.get() }))
      .presses(Is(true))
      .on_press(fn() { pressed.val += 1 })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  t
}

///|
/// The white ground's line in what was drawn.
fn white_ground(t : Tester) -> String {
  t.frame_export().filter(fn(l) { l.contains("#ffffff") }).join("\n")
}

///|
test "a node drawn at a size of its own (View::drawn_size): its ground that big from where it is laid out; none, as laid out" {
  let size = @signals.signal(Some((200.0, 80.0)), same=fn(a, b) { a == b })
  let t = drawn_size_tester(size, Ref(0))
  assert_true(white_ground(t).contains(" 0 200 200 80 "), msg=white_ground(t))
  size.set(None)
  t.frame()
  assert_true(white_ground(t).contains(" 0 200 100 50 "), msg=white_ground(t))
}

///|
test "a node's drawn size said again: its own layer drawn again, where it was and is drawn, nothing else" {
  let size = @signals.signal(Some((200.0, 80.0)), same=fn(a, b) { a == b })
  let t = drawn_size_tester(size, Ref(0))
  t.record_host()
  size.set(Some((60.0, 30.0)))
  t.frame()
  let frames = t.host_frames()
  let outside = frames.filter(fn(f) {
    f.damage.iter().any(fn(d) { d.2 < 0.0 || d.0 < -2.0 || d.1 < 200.0 - 2.0 || d.0 + d.2 > 200.0 + 2.0 || d.1 + d.3 > 280.0 + 2.0 })
  })
  assert_eq(outside.length(), 0, msg="\{frames}")
  assert_true(frames.iter().any(fn(f) { f.changed && f.layers_drawn > 0 }), msg="\{frames}")
  assert_true(white_ground(t).contains(" 0 200 60 30 "), msg=white_ground(t))
}

///|
test "a node's drawn size: pressed where it is drawn, not where it is laid out and not drawn" {
  let size = @signals.signal(Some((200.0, 80.0)), same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = drawn_size_tester(size, pressed)
  // (drawn, past where it is laid out)
  t.tap(150.0, 260.0)
  t.frame()
  assert_eq(pressed.val, 1)
  // (laid out there, drawn smaller: not there)
  size.set(Some((40.0, 20.0)))
  t.frame()
  t.tap(80.0, 240.0)
  t.frame()
  assert_eq(pressed.val, 1)
  t.tap(20.0, 210.0)
  t.frame()
  assert_eq(pressed.val, 2)
}

///|
test "a node's drawn size: a still pointer over it worked out again as it grows to it and shrinks from it, frame by frame as a host draws" {
  let size = @signals.signal(None, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform=0)
  let node : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(200.0))) |> ignore }) |> ignore
    root.box(fn(b) {
      node.val = Some(b)
      b
      .width(Is(Some(100.0)))
      .height(Is(Some(50.0)))
      .on_press(fn() {  })
      .drawn_size(By(fn() { size.get() }))
      .ground(By(fn() { if b.pointed() { 0x112233FFL } else { 0xFFFFFFFFL } }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  // (the pointer still, past where it is laid out)
  t.move(150.0, 220.0)
  t.frame()
  let b = node.val.unwrap()
  assert_false(b.pointed(), msg="not over it as laid out")
  t.record_host()
  size.set(Some((200.0, 80.0)))
  t.frame_at(t.next_frame_time())
  assert_true(b.pointed(), msg="over it as it is drawn bigger, the pointer still")
  size.set(Some((40.0, 20.0)))
  t.frame_at(t.next_frame_time())
  assert_false(b.pointed(), msg="not over it as it is drawn smaller")
}

///|
test "a node's drawn size where it bounds input: pressed where it is drawn past where it is laid out, as what it holds is; not where it is drawn smaller" {
  let size = @signals.signal(Some((200.0, 80.0)), same=fn(a, b) { a == b })
  let held = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(200.0))) |> ignore }) |> ignore
    root.box(fn(b) {
      b.width(Is(Some(100.0))).height(Is(Some(50.0))).bounds_input(Is(true)).drawn_size(By(fn() { size.get() })) |> ignore
      // (what it holds, laid out past it)
      b.box(fn(k) {
        k
        .over(Is(true))
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .presses(Is(true))
        .on_press(fn() { held.val += 1 })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  // (past where it is laid out, within where it is drawn: what it holds pressed there)
  t.tap(150.0, 260.0)
  t.frame()
  assert_eq(held.val, 1)
  // (past where it is drawn: not)
  t.tap(250.0, 260.0)
  t.frame()
  assert_eq(held.val, 1)
  // (drawn smaller: within where it is laid out, past where it is drawn: not)
  size.set(Some((40.0, 20.0)))
  t.frame()
  t.tap(80.0, 230.0)
  t.frame()
  assert_eq(held.val, 1)
  t.tap(20.0, 210.0)
  t.frame()
  assert_eq(held.val, 2)
}

///|
test "a node's drawn size as each frame is painted, at the frame's moment: frame by frame as a host draws it, drawn that big, a still pointer over it as it is drawn there, pressed there" {
  // (from 50 wide, 25 more each 20 ms, to 250: whole points, said by the frame's moment as it is painted)
  let from = @signals.signal(-1.0, same=fn(a, b) { a == b })
  let done = @signals.signal(false, same=fn(a, b) { a == b })
  let width = fn(d : Double) { dmin(250.0, 50.0 + 25.0 * (d / 20.0).floor()) }
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform=0)
  let node : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(200.0))) |> ignore }) |> ignore
    root.box(fn(b) {
      node.val = Some(b)
      b
      .width(Is(Some(100.0)))
      .height(Is(Some(50.0)))
      .presses(Is(true))
      .on_press(fn() { pressed.val += 1 })
      .drawn_size(
        Painted(fn(laid) {
          let s = from.get()
          if s < 0.0 {
            None
          } else if done.get() {
            Some((250.0, 50.0))
          } else {
            Some((width(laid.at() - s), 50.0))
          }
        }),
      )
      .ground(By(fn() { if b.pointed() { 0x112233FFL } else { 0xFFFFFFFFL } }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  // (the pointer still, past where it is laid out, within where it is drawn once 175 wide)
  t.move(150.0, 220.0)
  t.frame()
  let b = node.val.unwrap()
  assert_false(b.pointed())
  t.record_host()
  let s = t.next_frame_time()
  from.set(s)
  b.at_moment(s + 200.0, fn() { done.set(true) }) |> ignore
  let drawn = fn() -> (Double, Bool) {
    let lines = t.frame_export().filter(fn(l) { l.contains(" 0 200 ") && l.contains(" 50 #") })
    let mut w = -1.0
    let mut lit = false
    for k in 0..<9 {
      let at = 50 + 25 * k
      for l in lines {
        if l.contains(" 0 200 \{at} 50 #") {
          w = at.to_double()
          lit = l.contains("#112233")
        }
      }
    }
    (w, lit)
  }
  let mut last = 0.0
  let mut under = 0
  let mut over = 0
  for _ in 0..<20 {
    t.frame_at(t.next_frame_time())
    let (w, lit) = drawn()
    assert_true(w >= last, msg="drawn \{w} after \{last}: \{t.frame_export()}")
    last = w
    let covers = w > 150.0
    // (the pointer still: over it as it is drawn in this frame, drawn so)
    assert_eq(b.pointed(), covers, msg="drawn \{w} wide")
    assert_eq(lit, covers, msg="drawn \{w} wide")
    // (pressed there as it is drawn in this frame)
    let was = pressed.val
    t.tap_once(150.0, 220.0)
    assert_eq(pressed.val - was, if covers { 1 } else { 0 }, msg="drawn \{w} wide")
    t.move(150.0, 220.0)
    if covers { over += 1 } else { under += 1 }
  }
  assert_eq(last, 250.0)
  assert_true(under > 0 && over > 0, msg="\{under} frames short of the pointer, \{over} over it")
}

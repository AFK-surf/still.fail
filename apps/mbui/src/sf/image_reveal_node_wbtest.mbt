// A picture brushed in as it is decoded (image_reveal_node.mbt): from the moment its host said it was decoded, the same
// at any frame rate; nothing of the brushing left once it is over; a node given another picture as it shows another.

///|
let reveal_test_w : Double = 200.0

///|
let reveal_test_h : Double = 150.0

///|
/// How long the test runs before the picture is shown (any while: at rest by then).
let reveal_test_before : Double = 100.0

///|
/// A moment on the way in to look at, and a hair (a moment just before another).
let reveal_test_mid : Double = 400.0

///|
let reveal_test_hair : Double = 1.0

///|
/// The late picture's decode: on no frame rate's frames.
let reveal_test_late : Double = 137.0

///|
/// A picture node showing what `src` says (as it changes), from when `shown` says; and what of the window's tree is held
/// now (its nodes, its bindings).
fn reveal_tester(
  src : @signals.Signal[String],
  shown : @signals.Signal[Bool],
  held? : Bool = false,
  comes? : Bool = true,
) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) { @ui.old_views_here(c) },
    tree=fn(root) {
      root.show(fn() { shown.get() }, fn(v) {
        image_reveal_node(v, fn() { src.get() }, fn() { "" }, reveal_test_w, reveal_test_h, held=fn() { held }, comes=fn() {
          comes
        })
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
    platform=0,
  )
  for s in ["quick.png", "late.png", "other.png"] {
    t.add_image(s, 800, 600)
  }
  t.decode_after("late.png", reveal_test_late)
  t.decode_after("other.png", reveal_test_late)
  t
}

///|
fn reveal_held_now() -> (Int, Int) {
  let tree = @ui.view_tree().unwrap()
  (tree.alive(), tree.bindings_held())
}

///|
/// The picture's drawn width (its scale's: 1.04 at the start, its own at the end), none drawn: 0.
fn reveal_drawn_w(t : @ui.Tester) -> Double {
  t.drawn_images().fold(init=0.0, fn(m, i) { if i[2] > m { i[2] } else { m } })
}

///|
test "a picture brushed in from the moment its host says it is decoded, at once or 137 ms after it is asked for, the same at any frame rate" {
  for name in ["quick.png", "late.png"] {
    let src = @signals.signal(name)
    let shown = @signals.signal(false)
    let t = reveal_tester(src, shown)
    t.run_for(reveal_test_before)
    let asked = t.time()
    shown.set(true)
    let told = asked + (if name == "late.png" { reveal_test_late } else { 0.0 })
    // (before it is told: waiting, nothing of it drawn)
    if name == "late.png" {
      t.run_for(reveal_test_late - reveal_test_hair)
      assert_eq(reveal_drawn_w(t), 0.0, msg=name)
    }
    // at each moment of its way, its scale as reveal's: 1 + grow × (1 − ease-out of how far)
    // (looked at from a hair after the moment it was told on, never by a frame of the test's own drawn at it: a
    // `frame()` there is the display's next, past the moment, and the quick picture's decode, done at the frame after it
    // is asked for, was told at that one instead (the first try's 205.82 for 205.38 at 100 ms: its start 16.7 ms later,
    // the test's, not the reveal's))
    for at in [reveal_test_hair, 100.0, 400.0, 800.0] {
      t.run_for(told + at - t.time())
      let e = @ui.Out.at(at / reveal_ms)
      let want = reveal_test_w * (1.0 + reveal_grow * (1.0 - e))
      assert_true((reveal_drawn_w(t) - want).abs() < 0.01, msg="\{name} at \{at}: \{reveal_drawn_w(t)} wanted \{want}")
    }
    t.run_for(told + reveal_ms - t.time())
    assert_true((reveal_drawn_w(t) - reveal_test_w).abs() < 0.01, msg=name)
    assert_eq(t.audit(), [], msg=name)
  }
}

///|
test "brushed in, nothing of it left: the same nodes and bindings as a picture the device had, shown as it is" {
  let held_now = {
    let src = @signals.signal("quick.png")
    let shown = @signals.signal(false)
    let t = reveal_tester(src, shown, held=true)
    shown.set(true)
    t.run_for(reveal_ms + reveal_test_before)
    reveal_held_now()
  }
  let src = @signals.signal("late.png")
  let shown = @signals.signal(false)
  let t = reveal_tester(src, shown)
  shown.set(true)
  t.run_for(reveal_test_late + reveal_ms / 2.0)
  let going = reveal_held_now()
  assert_true(going.0 > held_now.0, msg="while it goes, what is laid over it: \{Repr(going)} \{Repr(held_now)}")
  t.run_for(reveal_ms)
  assert_eq(reveal_held_now(), held_now)
}

///|
test "a node given another picture as it shows another: one decoded shown as it is, one coming brushed in when it comes; what was brushing in let go at once" {
  // (to one decoded already)
  let src = @signals.signal("quick.png")
  let shown = @signals.signal(false)
  let t = reveal_tester(src, shown)
  shown.set(true)
  t.run_for(reveal_ms + reveal_test_before)
  let rest = reveal_held_now()
  src.set("late.png")
  t.run_for(reveal_test_late + reveal_ms / 2.0)
  assert_true(reveal_held_now().0 > rest.0)
  // (halfway in, given one decoded: there as it is, at once)
  src.set("quick.png")
  t.frame()
  assert_eq(reveal_held_now(), rest)
  assert_true((reveal_drawn_w(t) - reveal_test_w).abs() < 0.01)
  // (given one that comes 137 ms later: waiting, nothing of it drawn; then brushed in from the moment it comes)
  src.set("other.png")
  let given = t.time()
  t.run_for(reveal_test_late - reveal_test_hair)
  assert_eq(reveal_drawn_w(t), 0.0)
  let told = given + reveal_test_late
  t.run_for(told + reveal_test_mid - t.time())
  let want = reveal_test_w * (1.0 + reveal_grow * (1.0 - @ui.Out.at(reveal_test_mid / reveal_ms)))
  assert_true((reveal_drawn_w(t) - want).abs() < 0.01, msg="\{reveal_drawn_w(t)} wanted \{want}")
  t.run_for(told + reveal_ms - t.time())
  assert_eq(reveal_held_now(), rest)
  assert_eq(t.audit(), [])
}

///|
test "a tall picture cut to its top: covering its box from its top, the part of it the box shows its top's, brushed in about its box's middle" {
  let src = @signals.signal("tall.png")
  let shown = @signals.signal(false)
  // (300 × 3000 in a box 160 × 300: as wide as it, 300 / 1600 of its height shown, from its top)
  let (w, h) = (160.0, 300.0)
  let part = h / (w * 3000.0 / 300.0)
  let t = @ui.Tester::new(
    fn(c) { @ui.old_views_here(c) },
    tree=fn(root) {
      root.show(fn() { shown.get() }, fn(v) {
        image_reveal_node(v, fn() { src.get() }, fn() { "" }, w, h, top_crop=true) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
    platform=0,
    images=[("tall.png", 300, 3000)],
  )
  t.decode_after("tall.png", reveal_test_late)
  shown.set(true)
  // (half way in: grown about its box's middle)
  t.run_for(reveal_test_late + reveal_test_mid)
  let grow = 1.0 + reveal_grow * (1.0 - @ui.Out.at(reveal_test_mid / reveal_ms))
  let i = t.drawn_images()[0]
  assert_true((i[2] - w * grow).abs() < 0.01 && (i[3] - h * grow).abs() < 0.01, msg="\{Repr(i)}")
  assert_true((i[1] - (h / 2.0 - h / 2.0 * grow)).abs() < 0.01, msg="\{Repr(i)}")
  // (at rest: its box, the top of the picture as much of it as shows)
  t.run_for(reveal_ms)
  let i = t.drawn_images()[0]
  assert_eq((i[0], i[1], i[2], i[3]), (0.0, 0.0, w, h))
  // (as decoded: its part shown to a thousandth)
  assert_true(i[5] == 0.0 && (i[7] - part).abs() < 1.0e-3 && i[6] == 1.0, msg="\{Repr(i)}")
  assert_eq(t.audit(), [])
}

///|
test "a picture that does not come (of a message said before it was shown): waiting till its host says it is decoded, then whole from that moment, nothing laid over it" {
  let held_now = {
    let src = @signals.signal("quick.png")
    let shown = @signals.signal(false)
    let t = reveal_tester(src, shown, held=true)
    shown.set(true)
    t.run_for(reveal_ms + reveal_test_before)
    reveal_held_now()
  }
  let src = @signals.signal("late.png")
  let shown = @signals.signal(false)
  let t = reveal_tester(src, shown, comes=false)
  t.run_for(reveal_test_before)
  let asked = t.time()
  shown.set(true)
  // (before it is told: what it waits on, nothing of it drawn)
  t.run_for(reveal_test_late - reveal_test_hair)
  assert_eq(reveal_drawn_w(t), 0.0)
  // (a hair after: its own size, no frost, what it waited on gone: the same as one the device had)
  t.run_for(asked + reveal_test_late + reveal_test_hair - t.time())
  assert_true((reveal_drawn_w(t) - reveal_test_w).abs() < 0.01, msg="\{reveal_drawn_w(t)}")
  assert_eq(t.drawn_glass().length(), 0)
  t.run_for(reveal_test_mid)
  assert_true((reveal_drawn_w(t) - reveal_test_w).abs() < 0.01)
  assert_eq(t.drawn_glass().length(), 0)
  assert_eq(reveal_held_now(), held_now)
  assert_eq(t.audit(), [])
}

// The window as a tree made once (view_host.mbt): a bar before the old view's island (drawn under it), the island given
// a box of its own drawn off where it is laid out, a badge after it drawn over the island. The old view is built for
// the island's room and laid out, painted and pressed where the island is; what changes in the tree is drawn by its
// binding, the old view built no more for it; a press is for what the tree finds at its point.

///|
let island_blue : Int64 = 0x3366CCFFL

///|
let island_red : Int64 = 0xCC3333FFL

///|
let island_green : Int64 = 0x33AA55FFL

///|
/// What the window's parts counted: the old view's builds and presses, the bar's and the badge's presses.
priv struct Island {
  t : Tester
  builds : Ref[Int]
  old_taps : Ref[Int]
  bar_taps : Ref[Int]
  badge_taps : Ref[Int]
}

///|
/// The old view (a green box filling its room, pressed: `old_taps`, its words "old"); with `tree`, the window made once
/// around it: a bar 40 high (its words `label`), under it the island 200 by 300 drawn off (30, 20), after it a badge 60
/// by 30 drawn off (40, -200), over the island.
fn island(
  label : @signals.Signal[String],
  tree? : Bool = true,
  badge_off? : @signals.Signal[(Double, Double)] = @signals.signal((40.0, -200.0)),
) -> Island {
  let builds = Ref(0)
  let old_taps = Ref(0)
  let bar_taps = Ref(0)
  let badge_taps = Ref(0)
  let view = fn(c : Ctx) {
    builds.val = builds.val + 1
    let id = c.id("old")
    if c.clicked(id) {
      old_taps.val = old_taps.val + 1
    }
    c.box(w=Fill(1.0), h=Fill(1.0), bg=island_green, id~, fn() {
      // (the old way: the bar's words read as the old view is built)
      if !tree {
        c.text(label.get(), size=15.0) |> ignore
      }
      c.text("old", size=12.0) |> ignore
    })
    |> ignore
  }
  let t = Tester::new(view)
  if tree {
    set_view_app(fn(root) {
      root
      .box(fn(b) {
        b
        .height(Is(Some(40.0)))
        .ground(Is(island_blue))
        .words(By(fn() { label.get() }))
        .on_press(fn() { bar_taps.val = bar_taps.val + 1 })
        |> ignore
      })
      |> ignore
      old(root, view).width(Is(Some(200.0))).height(Is(Some(300.0))).offset(Is((30.0, 20.0))) |> ignore
      root.box(fn(b) {
        b
        .width(Is(Some(60.0)))
        .height(Is(Some(30.0)))
        .offset(By(fn() { badge_off.get() }))
        .ground(Is(island_red))
        .on_press(fn() { badge_taps.val = badge_taps.val + 1 })
        |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  // (a frame more: the old view built once more where the build before laid it out otherwise (its room given by
  // the tree from the second frame), frame_watch.mbt: settled)
  t.drawn_now()
  { t, builds, old_taps, bar_taps, badge_taps }
}

///|
/// A tap at (x, y), drawn as a host draws what it asks (not Tester::tap's draw, which counts as a change of the
/// test's: every old view built again for it).
fn tree_tap(t : Tester, x : Double, y : Double) -> Unit {
  finger(0, x, y)
  finger(2, x, y)
  t.drawn_now()
}

///|
/// Where in the frame's instances the rectangle `r` is drawn (-1: not drawn).
fn drawn_index(t : Tester, r : (Double, Double, Double, Double, Int64)) -> Int {
  match t.drawn_rects().search(r) {
    Some(i) => i
    None => -1
  }
}

///|
test "window tree: words of the old view changed: the whole old view built again (what the tree made once does without)" {
  let label = @signals.signal("first")
  let w = island(label, tree=false)
  w.t.check_looks(false)
  let was = w.builds.val
  label.set("second")
  w.t.drawn_now()
  assert_eq(w.builds.val, was + 1)
  assert_true(w.t.drawn_text().contains("second"))
}

///|
test "window tree: the old view in its island: laid out and cut there, the bar drawn under it and the badge over it" {
  let w = island(@signals.signal("bar"))
  let bar = drawn_index(w.t, (0.0, 0.0, 390.0, 40.0, island_blue))
  let old = drawn_index(w.t, (30.0, 60.0, 200.0, 300.0, island_green))
  let badge = drawn_index(w.t, (40.0, 140.0, 60.0, 30.0, island_red))
  assert_true(bar >= 0 && old >= 0 && badge >= 0, msg="\{w.t.drawn_rects()}")
  assert_true(bar < old && old < badge, msg="\{(bar, old, badge)}")
  let (x, y, _, _) = w.t.rect_of("old").unwrap()
  assert_true(x >= 30.0 && y >= 60.0 && x < 230.0 && y < 360.0, msg="\{(x, y)}")
}

///|
test "window tree: a press goes where the tree finds it: the badge over the island, the old view in it, nothing outside it" {
  let w = island(@signals.signal("bar"))
  // (each frame not built drawn as it is, not built whole once more to compare: what is built counted)
  w.t.check_looks(false)
  tree_tap(w.t, 100.0, 300.0)
  assert_eq((w.old_taps.val, w.bar_taps.val, w.badge_taps.val), (1, 0, 0))
  let built = w.builds.val
  tree_tap(w.t, 50.0, 150.0)
  assert_eq((w.old_taps.val, w.bar_taps.val, w.badge_taps.val), (1, 0, 1))
  tree_tap(w.t, 100.0, 20.0)
  assert_eq((w.old_taps.val, w.bar_taps.val, w.badge_taps.val), (1, 1, 1))
  // (right of the island, under nothing that is pressed: nobody's)
  tree_tap(w.t, 300.0, 300.0)
  assert_eq((w.old_taps.val, w.bar_taps.val, w.badge_taps.val), (1, 1, 1))
  // the old view saw none of them: never built for them
  assert_eq(w.builds.val, built, msg=w.t.built_why())
}

///|
test "window tree: the bar's words changed: its instances alone made again, the old view not built" {
  let label = @signals.signal("first")
  let w = island(label)
  let tree = view_tree().unwrap()
  w.t.check_looks(false)
  let was = w.builds.val
  let work = tree.work()
  let painted = view_painted()
  label.set("second")
  w.t.drawn_now()
  assert_eq(w.builds.val, was, msg=w.t.built_why())
  assert_eq(tree.work().bound - work.bound, 1)
  // (laid out again: its size given both ways, its words not measured for it)
  assert_eq(tree.work().computes - work.computes, 1)
  // (the bar's instances made, the badge's copied as kept)
  assert_eq(view_painted().made - painted.made, 1)
  let bar = tree.root().kids()[0]
  assert_eq(tree.drawn_of(bar.id()).unwrap().words, "second")
  assert_true(w.t.drawn_text().contains("old"))
  assert_true(drawn_index(w.t, (40.0, 140.0, 60.0, 30.0, island_red)) >= 0)
  // its words drawn in it as a window made with them from the start draws them, nothing of the words before left
  let bar_glyphs = fn(t : Tester) { t.drawn_glyphs().filter(fn(g) { g.1 < 40.0 }) }
  let changed = bar_glyphs(w.t)
  let fresh = island(@signals.signal("second"))
  assert_eq(changed, bar_glyphs(fresh.t))
  assert_true(changed.length() > 0)
}

///|
test "window tree: a run begun anew: the window's tree before it let go, its signals read by nothing" {
  let label = @signals.signal("bar")
  island(label) |> ignore
  assert_true(label.watched())
  Tester::new(fn(c) { c.text("next", size=12.0) |> ignore }) |> ignore
  assert_false(label.watched())
}

///|
test "window tree: the badge moved: drawn where it went, nothing of it made again, the old view not built" {
  let off = @signals.signal((40.0, -200.0), same=fn(a, b) { a == b })
  let w = island(@signals.signal("bar"), badge_off=off)
  w.t.check_looks(false)
  let tree = view_tree().unwrap()
  let was = w.builds.val
  let work = tree.work()
  let painted = view_painted()
  off.set((100.0, -200.0))
  w.t.drawn_now()
  assert_eq(w.builds.val, was, msg=w.t.built_why())
  assert_eq(tree.work().computes - work.computes, 0)
  assert_eq(tree.work().instances - work.instances, 0)
  assert_eq(tree.work().composed - work.composed, 1)
  assert_eq(view_painted().made - painted.made, 0)
  assert_true(drawn_index(w.t, (100.0, 140.0, 60.0, 30.0, island_red)) >= 0, msg="\{w.t.drawn_rects()}")
  // (pressed where it went)
  tree_tap(w.t, 110.0, 150.0)
  assert_eq(w.badge_taps.val, 1)
}

///|
test "window tree: a part leaving goes on as the host draws it, from when it was told, let go at its end, then at rest" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let view = fn(c : Ctx) { c.text("old", size=12.0) |> ignore }
  let t = Tester::new(view)
  set_view_app(fn(root) {
    root.show(
      fn() { on.get() },
      fn(v) {
        v.height(Is(Some(20.0))).ground(Is(island_red)).alpha(By(fn() { 1.0 - v.going() })) |> ignore
      },
      leave=part_leave_ms,
    )
    old(root, view).grow(Is(1.0)) |> ignore
  })
  t.draw()
  let base = view_blocks.length()
  on.set(false)
  t.run_for(part_leave_ms / 2.0)
  // (half gone: drawn half as opaque)
  let half = t.drawn_rects().filter(fn(r) { r.4 >> 8 == island_red >> 8 })
  assert_true(half.length() == 1 && (half[0].4 & 0xFFL) >= 126L && (half[0].4 & 0xFFL) <= 129L, msg="\{half}")
  assert_false(t.at_rest())
  t.run_for(part_leave_ms / 2.0 + part_leave_ms / 6.0)
  assert_false(t.drawn_rects().iter().any(fn(r) { r.4 >> 8 == island_red >> 8 }), msg="\{t.drawn_rects()}")
  assert_true(t.at_rest(), msg=t.rest_why())
  assert_eq(view_blocks.length(), base - 1)
}

///|
/// How long a part takes to leave, here.
let part_leave_ms : Double = 300.0

///|
/// A window whose one node takes a press only while the hand of the moment is a finger (its presses said by the current
/// input), on a machine with both (the host saying what each event comes from): after a press by `first`, one by
/// `then`, no frame between: whether each was taken.
fn pressed_by_hand(first : Bool, then : Bool) -> (Bool, Bool) {
  let taps = Ref(0)
  let t = Tester::new(fn(_c) {  }, platform=0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(100.0)))
      .height(Is(Some(100.0)))
      .presses(By(fn() { pointing() is Finger }))
      .on_press(fn() { taps.val = taps.val + 1 })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  let pressed = fn(finger_said : Bool) {
    let before = taps.val
    t.host_says_finger(Some(finger_said))
    t.advance(frame_period_default)
    finger(0, 50.0, 50.0)
    t.advance(frame_period_default)
    finger(2, 50.0, 50.0)
    taps.val > before
  }
  let a = pressed(first)
  let b = pressed(then)
  (a, b)
}

///|
test "a node taking presses by the hand of the moment: the first press of the other hand is routed by that hand, no frame between" {
  assert_eq(pressed_by_hand(false, true), (false, true))
  assert_eq(pressed_by_hand(true, false), (true, false))
}

///|
test "a finger told late, something due before it: what was due sees the hand before it; the press found by the finger's; what follows the hand told at the finger's moment" {
  let t = Tester::new(fn(_c) {  }, platform=0)
  let t0 = t.time()
  let due_saw : Ref[Pointing?] = Ref(None)
  let causes : Array[Double] = []
  let taps = Ref(0)
  set_view_app(fn(root) {
    root.at_moment(t0 + due_at_ms, fn() { due_saw.val = Some(pointing()) }) |> ignore
    root.reacts(fn() { pointing() }, fn(_) { causes.push(root.cause_at()) })
    root.box(fn(b) {
      b
      .width(Is(Some(100.0)))
      .height(Is(Some(100.0)))
      .presses(By(fn() { pointing() is Finger }))
      .on_press(fn() { taps.val = taps.val + 1 })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  let t0 = t.time()
  // (a mouse's hand till now; the host on to 80, no frame drawn; a finger down at 50 and up at 60 told then)
  t.advance(told_at_ms)
  t.touch_raw(0, 7, 50.0, 50.0, t0 + down_at_ms)
  t.touch_raw(2, 7, 50.0, 50.0, t0 + up_at_ms)
  assert_eq(due_saw.val, Some(Mouse))
  assert_eq(taps.val, 1)
  assert_eq(causes.last(), Some(t0 + down_at_ms))
}

///|
/// The late finger's (above): what is due at 30, the finger down at 50 and up at 60, told only as the host is at 80.
let due_at_ms : Double = 30.0

///|
let down_at_ms : Double = 50.0

///|
let up_at_ms : Double = 60.0

///|
let told_at_ms : Double = 80.0

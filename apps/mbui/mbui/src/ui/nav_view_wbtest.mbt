// A stack held by the window's tree (nav_view.mbt): where its pages are drawn at a moment is a function of what was told
// and when, whatever frames came between (none, or one each 16 ms); the window made narrower as a page slides moves it
// by the width it is laid out at in the frame drawing it, its end where its push said; a page waited for sets out at
// the moment what it shows came (or its wait is over); a page that went back is let go at its slide's end.

///|
/// A stack of pages named by letters in the window's tree, each page's old view its name; `ready` what a page waits for
/// (none: it waits for nothing), at most `most` ms. The pages it let go, in turn.
fn stacked(
  ready? : @signals.Signal[Bool],
  most? : Double = 0.0,
) -> (Tester, Nav[String], Array[String]) {
  let left : Array[String] = []
  let nav = Nav::new("a", on_leave=fn(p) { left.push(p) })
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    nav_view(
      root,
      nav,
      fn(c, p) { c.text(p, size=12.0) |> ignore },
      bg=fn() { 0xFFFFFFFFL },
      ready?=ready.map(fn(r) { fn(_p : String) { r.get() } }),
      most~,
    )
    |> ignore
  })
  t.draw()
  (t, nav, left)
}

///|
/// The old views of the pages as the window's tree draws them: where across and how wide, in the stack's order.
fn pages_drawn() -> Array[(Double, Double)] {
  match view_tree() {
    Some(tree) => tree.drawn().filter(fn(d) { d.hosted }).map(fn(d) { (d.x, d.w) })
    None => []
  }
}

///|
/// Told at `at` (between frames, at its own moment), as an input is.
fn told_at(t : Tester, at : Double, f : () -> Unit) -> Unit {
  t.fake.time = at
  view_event(f)
}

///|
/// Frames each 16 ms from `from` until before `to` (`frames`), or none.
fn frames_between(t : Tester, from : Double, to : Double, frames : Bool) -> Unit {
  if frames {
    let mut at = from + 16.0
    while at < to {
      t.frame_at(at)
      at = at + 16.0
    }
  }
}

///|
test "window tree: a page pushed between frames: where the pages are at a moment and when its slide ends, frames or none" {
  let run = fn(frames : Bool) {
    let (t, nav, _) = stacked()
    let t0 = t.time()
    told_at(t, t0 + 10.0, fn() { nav.push("b") })
    frames_between(t, t0 + 10.0, t0 + 160.0, frames)
    t.frame_at(t0 + 160.0)
    let at_160 = pages_drawn()
    let end = nav.rest() - t0
    t.frame_at(t0 + end)
    (at_160, end, pages_drawn())
  }
  let (at_160, end, after) = run(false)
  assert_eq(run(true), (at_160, end, after))
  // (the page under it off to the left by its width, edge to edge with it, partway; then the top alone, in place)
  assert_true(at_160.length() == 2, msg="\{at_160}")
  assert_eq(at_160[1].0 - at_160[0].0, 390.0)
  assert_true(at_160[1].0 > 0.0 && at_160[1].0 < 390.0, msg="\{at_160}")
  assert_eq(after, [(0.0, 390.0)])
}

///|
test "window tree: the window made narrower as a page slides: drawn by the width of the frame drawing it, its end its push's" {
  let run = fn(frames : Bool) {
    let (t, nav, _) = stacked()
    let t0 = t.time()
    told_at(t, t0 + 10.0, fn() { nav.push("b") })
    let end = nav.rest() - t0
    frames_between(t, t0 + 10.0, t0 + 100.0, frames)
    t.w = 300.0
    t.frame_at(t0 + 160.0)
    (pages_drawn(), end, nav.rest() - t0)
  }
  let (at_160, end, end_after) = run(false)
  assert_eq(run(true), (at_160, end, end_after))
  assert_eq(end_after, end)
  assert_true(at_160.length() == 2 && at_160[0].1 == 300.0 && at_160[1].1 == 300.0, msg="\{at_160}")
  assert_eq(at_160[1].0 - at_160[0].0, 300.0)
}

///|
test "window tree: a page waited for sets out as what it shows comes, or as its wait is over: as if pushed then" {
  // (pushed at 60 with nothing to wait for: where the pages are at 160)
  let plain = fn(at : Double, look : Double) {
    let (t, nav, _) = stacked()
    let t0 = t.time()
    told_at(t, t0 + at, fn() { nav.push("b") })
    t.frame_at(t0 + look)
    pages_drawn()
  }
  let came = fn(frames : Bool) {
    let ready = @signals.signal(false, same=fn(a, b) { a == b })
    let (t, nav, _) = stacked(ready~, most=300.0)
    let t0 = t.time()
    told_at(t, t0 + 10.0, fn() { nav.push("b") })
    frames_between(t, t0 + 10.0, t0 + 60.0, frames)
    told_at(t, t0 + 60.0, fn() { ready.set(true) })
    frames_between(t, t0 + 60.0, t0 + 160.0, frames)
    t.frame_at(t0 + 160.0)
    pages_drawn()
  }
  let waited = fn(frames : Bool) {
    let ready = @signals.signal(false, same=fn(a, b) { a == b })
    let (t, nav, _) = stacked(ready~, most=100.0)
    let t0 = t.time()
    told_at(t, t0 + 10.0, fn() { nav.push("b") })
    frames_between(t, t0 + 10.0, t0 + 210.0, frames)
    t.frame_at(t0 + 210.0)
    pages_drawn()
  }
  let at_60 = plain(60.0, 160.0)
  assert_true(at_60.length() == 2 && at_60[1].0 > 0.0 && at_60[1].0 < 390.0, msg="\{at_60}")
  assert_eq(came(false), at_60)
  assert_eq(came(true), at_60)
  let at_110 = plain(110.0, 210.0)
  assert_eq(waited(false), at_110)
  assert_eq(waited(true), at_110)
}

///|
test "window tree: a page gone back is let go at its slide's end, the one it covered kept all along" {
  let run = fn(frames : Bool) {
    let (t, nav, left) = stacked()
    let t0 = t.time()
    told_at(t, t0 + 10.0, fn() { nav.push("b") })
    told_at(t, t0 + 1000.0, fn() { nav.push("c") })
    let covered = left.copy()
    told_at(t, t0 + 2000.0, fn() { nav.pop() |> ignore })
    let end = nav.rest()
    frames_between(t, t0 + 2000.0, end, frames)
    t.frame_at(end - 1.0)
    let before = (left.copy(), pages_drawn().length())
    t.frame_at(end)
    (covered, before, left.copy(), pages_drawn())
  }
  let r = run(false)
  assert_eq(run(true), r)
  assert_eq(r, ([], ([], 2), ["c"], [(0.0, 390.0)]))
}

///|
/// A stack whose pages are each a button 100 by 100 at their top left, its presses counted by page, an old view over it.
fn buttoned() -> (Tester, Nav[String], Map[String, Int]) {
  let pressed : Map[String, Int] = Map([])
  let nav = Nav::new("a")
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    nav_view(
      root,
      nav,
      fn(c, p) {
        let id = c.id("button " + p)
        if c.clicked(id) {
          pressed[p] = pressed.get(p).unwrap_or(0) + 1
        }
        c.box(w=Px(100.0), h=Px(100.0), bg=0x3366CCFFL, id~, fn() { c.text(p, size=12.0) |> ignore }) |> ignore
      },
      bg=fn() { 0xFFFFFFFFL },
    )
    |> ignore
    // (an old view over the stack, as the narrow shell's: the stack's pages never the whole window)
    old(root, fn(c) { c.box(w=Px(1.0), h=Px(1.0), fn() {  }) |> ignore }).over(Is(true)) |> ignore
  })
  t.draw()
  (t, nav, pressed)
}

///|
/// A press at (x, y) at `at`, between frames (down and up at its moment).
fn pressed_at(t : Tester, at : Double, x : Double, y : Double) -> Unit {
  t.fake.time = at
  finger(0, x, y)
  finger(2, x, y)
}

///|
test "window tree: a press on the page going back, at once after back, no frame between: it takes none, frames or none" {
  let run = fn(frames : Bool) {
    let (t, nav, pressed) = buttoned()
    let t0 = t.time()
    told_at(t, t0 + 10.0, fn() { nav.push("b") })
    t.frame_at(t0 + 1000.0)
    told_at(t, t0 + 2000.0, fn() { nav.pop() |> ignore })
    frames_between(t, t0 + 2000.0, t0 + 2040.0, frames)
    // (where b's button was as it was last painted, and where it is as of the press: b is at most a little way off)
    pressed_at(t, t0 + 2040.0, 20.0, 50.0)
    t.frame_at(t0 + 2050.0)
    pressed.to_array()
  }
  assert_eq(run(false), [])
  assert_eq(run(true), [])
}

///|
/// Where page `k` of those drawn (in the stack's order: one going back over the one it leaves) is drawn across as of
/// `at` (the tree brought there, as an input is).
fn page_x_at(k : Int, at : Double) -> Double {
  match view_tree() {
    Some(tree) => {
      tree.bring_to(at)
      tree.drawn().filter(fn(d) { d.hosted }).map(fn(d) { d.x })[k]
    }
    None => 0.0
  }
}

///|
test "window tree: a press on the page sliding in, where its button is at the press's moment, frames or none" {
  // (at its button's left edge and its middle: the part no frame drew there, and the part of it past the window's edge
  // as it was first painted)
  let run = fn(frames : Bool, dx : Double) {
    let (t, nav, pressed) = buttoned()
    let t0 = t.time()
    told_at(t, t0 + 10.0, fn() { nav.push("b") })
    // (its first frame: b built and painted where it starts)
    t.frame_at(t0 + 16.0)
    frames_between(t, t0 + 16.0, t0 + 60.0, frames)
    let bx = page_x_at(1, t0 + 60.0)
    pressed_at(t, t0 + 60.0, bx + dx, 50.0)
    t.frame_at(t0 + 70.0)
    (bx, pressed.to_array())
  }
  let (bx, pressed) = run(false, 5.0)
  // (partway in)
  assert_true(bx > 100.0 && bx < 390.0, msg="\{bx}")
  assert_eq(pressed, [("b", 1)])
  assert_eq(run(true, 5.0), (bx, pressed))
  assert_eq(run(false, 50.0), (bx, pressed))
  assert_eq(run(true, 50.0), (bx, pressed))
}

///|
test "window tree: a press on the page come back to as the one over it goes, painted past the window's edge, frames or none" {
  let run = fn(frames : Bool) {
    let (t, nav, pressed) = buttoned()
    let t0 = t.time()
    told_at(t, t0 + 10.0, fn() { nav.push("b") })
    t.frame_at(t0 + 1000.0)
    told_at(t, t0 + 2000.0, fn() { nav.pop() |> ignore })
    // (its first frame: a built again and painted where it starts, off to the left, its button past the window's edge)
    t.frame_at(t0 + 2016.0)
    frames_between(t, t0 + 2016.0, t0 + 2150.0, frames)
    let ax = page_x_at(0, t0 + 2150.0)
    pressed_at(t, t0 + 2150.0, dmax(ax, 0.0) + 5.0, 50.0)
    t.frame_at(t0 + 2160.0)
    (ax, pressed.to_array())
  }
  let (ax, pressed) = run(false)
  // (still coming: part of its button off the window's left edge, part of it in)
  assert_true(ax < 0.0 && ax > -95.0, msg="\{ax}")
  assert_eq(pressed, [("a", 1)])
  assert_eq(run(true), (ax, pressed))
}

///|
test "window tree: a page covered, an input as it takes none, uncovered: it takes presses again, a frame between or none" {
  let run = fn(frame : Bool) {
    let (t, nav, pressed) = buttoned()
    let t0 = t.time()
    t.frame_at(t0 + 16.0)
    // (b pushed over it: a takes none; an input then, between frames, where a is)
    told_at(t, t0 + 20.0, fn() { nav.push("b") })
    pressed_at(t, t0 + 22.0, 300.0, 600.0)
    if frame {
      t.frame_at(t0 + 24.0)
    }
    // (b gone back: a takes them again, where it is; b put in place by the pop at once, then sliding off from there: a
    // nearly back by 300)
    told_at(t, t0 + 26.0, fn() { nav.pop() |> ignore })
    let ax = page_x_at(0, t0 + 300.0)
    pressed_at(t, t0 + 300.0, ax + 50.0, 50.0)
    t.frame_at(t0 + 310.0)
    (ax, pressed.to_array())
  }
  let (ax, pressed) = run(false)
  assert_true(ax < 0.0 && ax > -50.0, msg="\{ax}")
  assert_eq(pressed, [("a", 1)])
  assert_eq(run(true), (ax, pressed))
}

///|
test "window tree: a press between frames finds a node where it is at the press, the frame before drawn ahead of it" {
  // (a narrow button as far across as the moment it is drawn at, from when the test began: at 95, from 95 to 97)
  let presses = fn(ahead : Bool) {
    let n = Ref(0)
    let base = Ref(0.0)
    let t = Tester::new(fn(_c) {  })
    t.check_looks(false)
    set_view_app(fn(root) {
      root.box(fn(b) {
        b.width(Is(Some(2.0))).height(Is(Some(40.0))).ground(Is(0x3366CCFFL)) |> ignore
        b.offset(By(fn() { (b.drawn_at() - base.val, 100.0) })).on_press(fn() { n.val = n.val + 1 }) |> ignore
      })
      |> ignore
    })
    t.draw()
    let tree = view_tree().unwrap()
    let t0 = t.time()
    base.val = t0
    // (a frame to be shown at t0 + 100 drawn as the host has come to t0 + 90, or one at t0 + 90)
    tree.at(t0 + (if ahead { 100.0 } else { 90.0 }))
    tree.frame(390.0, 844.0, now=t0 + 90.0) |> ignore
    // (pressed at t0 + 95, between frames, as a host's pointer comes)
    pressed_at(t, t0 + 95.0, 96.0, 120.0)
    n.val
  }
  assert_eq(presses(false), 1)
  assert_eq(presses(true), 1)
}

///|
test "window tree: the top page become another: what follows the top told, the page's node and its old view the same" {
  let (t, nav, _) = stacked()
  let tops : Array[String] = []
  let stop = @signals.effect(fn() { tops.push(nav.top()) })
  let t0 = t.time()
  told_at(t, t0 + 10.0, fn() { nav.push("b") })
  t.frame_at(t0 + 1000.0)
  let before = match view_tree() {
    Some(tree) => tree.drawn().filter(fn(d) { d.hosted }).map(fn(d) { d.id })
    None => []
  }
  told_at(t, t0 + 1010.0, fn() { nav.become("c") })
  t.frame_at(t0 + 1020.0)
  let after = match view_tree() {
    Some(tree) => tree.drawn().filter(fn(d) { d.hosted }).map(fn(d) { d.id })
    None => []
  }
  stop()
  assert_eq(tops, ["a", "b", "c"])
  assert_eq(after, before)
  assert_true(t.find("c") is Some(_))
}

///|
test "window tree: a page pushed before the tree held the stack slides in from the tree's first moment, and ends" {
  let nav = Nav::new("a")
  nav.push("b")
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) { nav_view(root, nav, fn(c, p) { c.text(p, size=12.0) |> ignore }) |> ignore })
  t.draw()
  let end = nav.rest()
  assert_true(end > t.time() && end < t.time() + 1000.0, msg="\{end} \{t.time()}")
  t.frame_at(end)
  assert_eq((nav.moving(), pages_drawn()), (false, [(0.0, 390.0)]))
}

///|
test "window tree: the top page replaced in place, between frames: the one it was let go, the new one shown" {
  let (t, nav, left) = stacked()
  let t0 = t.time()
  told_at(t, t0 + 10.0, fn() { nav.replace("b") })
  t.frame_at(t0 + 20.0)
  assert_eq((left, nav.pages(), pages_drawn()), (["a"], ["b"], [(0.0, 390.0)]))
  assert_true(t.find("b") is Some(_))
}

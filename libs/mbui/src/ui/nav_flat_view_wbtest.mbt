// A stack drawn flat held by the window's tree (nav_flat_view.mbt), as Ctx::nav_flat draws one: the page on top in
// place, the one its owner keeps shown while that waits; what is pushed over it sliding in and taken off by back down to
// the page in place; a page become another, the same page; one left let go and told.

///|
/// A stack drawn flat in the window's tree, each page's old view its name; what is pushed over it waits for nothing.
/// The pages it let go, in turn.
fn flat_stack() -> (Tester, Nav[String], Array[String]) {
  let left : Array[String] = []
  let nav = Nav::new("a", on_leave=fn(p) { left.push(p) })
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    nav_flat_view(root, nav, fn(c, p) { c.text(p, size=12.0) |> ignore }, fn(_) { true }, 0.0, bg=fn() {
      0xFFFFFFFFL
    })
    |> ignore
  })
  t.draw()
  (t, nav, left)
}

///|
/// The pages' words drawn, and where across each is, left to right.
fn flat_drawn(t : Tester) -> Array[(String, Double)] {
  let out = t.words().filter(fn(w) { w.0.length() <= 2 }).map(fn(w) { (w.0, w.1) })
  out.sort_by(fn(a, b) { a.1.compare(b.1) })
  out
}

///|
test "flat stack on the tree: a page put in place shows at once, alone; one pushed over it slides in, taken off by back down to the page in place" {
  let (t, nav, left) = flat_stack()
  nav.push("b")
  t.draw()
  assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["b"])
  // (over it: sliding in, both drawn half way, then it alone)
  nav.push_over("c")
  t.draw()
  t.run_for(move_ms(390.0) / 2.0)
  let half = flat_drawn(t)
  assert_eq(half.map(fn(d) { d.0 }), ["b", "c"])
  assert_true(half[1].1 > 0.0 && half[1].1 < 390.0, msg="\{Repr(half)}")
  t.run_for(move_ms(390.0))
  assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["c"])
  // (back: off it, sliding, to the page in place; no further)
  assert_true(t.ctx().back())
  t.run_for(move_ms(390.0) * 2.0)
  assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["b"])
  assert_eq(left, ["c"])
  assert_false(t.ctx().back())
  assert_eq(nav.pages(), ["a", "b"])
}

///|
/// A stack drawn flat in the window's tree with an owner as the panes' (page_wait.mbt): as the stay on top changes, the
/// one shown before kept while the one come on top has not what it shows (`ready`), let go as it has it; said before
/// the stack's node or after it (`owner_first`). The stack, the readiness, the pages let go, in turn.
fn flat_owned(owner_first : Bool) -> (Tester, Nav[String], @signals.Signal[Bool], Array[String]) {
  let left : Array[String] = []
  let nav = Nav::new("a", on_leave=fn(p) { left.push(p) })
  let ready = @signals.signal(true)
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    let owner = fn() {
      nav.flat_owned(true)
      let shown = Ref(@signals.untracked(fn() { nav.top_stay() }))
      root.reacts(fn() { nav.top_stay() }, fn(stay) {
        if stay == shown.val {
          return
        }
        if ready.untracked() {
          shown.val = stay
          nav.flat_keep(None)
        } else {
          nav.flat_keep(Some(shown.val))
        }
      })
      root.reacts(fn() { (nav.top_stay(), ready.get()) }, fn(now) {
        if now.1 && now.0 != shown.val {
          shown.val = now.0
          nav.flat_keep(None)
        }
      })
    }
    if owner_first {
      owner()
    }
    nav_flat_view(root, nav, fn(c, p) { c.text(p, size=12.0) |> ignore }, fn(_) { true }, 0.0) |> ignore
    if !owner_first {
      owner()
    }
  })
  t.draw()
  (t, nav, ready, left)
}

///|
test "flat stack on the tree: the page shown kept as the one put in its place waits, said by its owner before or after the stack: never let go and made again, let go once as the other shows" {
  for owner_first in [false, true] {
    let (t, nav, ready, left) = flat_owned(owner_first)
    let node = view_tree().unwrap().drawn().filter(fn(d) { d.hosted }).map(fn(d) { d.id })
    ready.set(false)
    nav.replace("b")
    t.draw()
    assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["a"], msg="\{owner_first}")
    assert_eq(view_tree().unwrap().drawn().filter(fn(d) { d.hosted }).map(fn(d) { d.id }), node, msg="\{owner_first}")
    assert_eq(left, [], msg="\{owner_first}")
    ready.set(true)
    t.draw()
    assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["b"], msg="\{owner_first}")
    assert_eq(left, ["a"], msg="\{owner_first}")
  }
}

///|
test "flat stack on the tree: the page on top become another, the same page: its node, its stay" {
  let (t, nav, _) = flat_stack()
  nav.push("b")
  t.draw()
  let node = view_tree().unwrap().drawn().filter(fn(d) { d.hosted }).map(fn(d) { d.id })
  let stay = nav.top_stay()
  nav.become("d")
  t.draw()
  assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["d"])
  assert_eq(view_tree().unwrap().drawn().filter(fn(d) { d.hosted }).map(fn(d) { d.id }), node)
  assert_eq(nav.top_stay(), stay)
}

///|
test "flat stack on the tree, where what is pushed over is not so: one pushed over shown in place at once, no back of the stack's" {
  let left : Array[String] = []
  let nav = Nav::new("a", on_leave=fn(p) { left.push(p) })
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    nav_flat_view(root, nav, fn(c, p) { c.text(p, size=12.0) |> ignore }, fn(_) { true }, 0.0, stacks=fn() { false })
    |> ignore
  })
  t.draw()
  nav.push_over("c")
  t.draw()
  assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["c"])
  assert_false(t.ctx().back())
}

///|
test "flat stack on the tree: a page left while the stack is not shown (or before it is), let go of once as it shows again" {
  let left : Array[String] = []
  let nav = Nav::new("a", on_leave=fn(p) { left.push(p) })
  // (before the stack is shown at all)
  nav.replace("z")
  let shown = @signals.signal(true)
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(b) {
      nav_flat_view(b, nav, fn(c, p) { c.text(p, size=12.0) |> ignore }, fn(_) { true }, 0.0) |> ignore
    })
  })
  t.draw()
  assert_eq(left, ["a"])
  // (hidden: what is on the stack let go of none; one put in its place meanwhile)
  shown.set(false)
  t.draw()
  assert_eq(left, ["a"])
  nav.replace("b")
  t.draw()
  shown.set(true)
  t.draw()
  assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["b"])
  assert_eq(left, ["a", "z"])
  t.draw()
  assert_eq(left, ["a", "z"])
}

///|
test "flat stack on the tree: one pushed over it says when its slide rests, as a stack's, and rests then" {
  let (t, nav, _) = flat_stack()
  nav.push_over("c")
  t.draw()
  let end = nav_rest()
  assert_true(end > t.time() && end < 1.0e300, msg="\{end} at \{t.time()}")
  t.run_for(end - t.time())
  assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["c"])
  t.frame()
  // (over: its end as it was)
  assert_eq(nav_rest(), end)
}

///|
test "flat stack on the tree: shown again after the one shown was put away while hidden, its owner said after it: kept, not let go first, let go once as the other shows" {
  let left : Array[String] = []
  let nav = Nav::new("a", on_leave=fn(p) { left.push(p) })
  let ready = @signals.signal(true)
  let shown = @signals.signal(true)
  // (what its owner showed last, kept by it across the stack hidden and shown)
  let was = Ref(nav.top_stay())
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(b) {
      nav_flat_view(b, nav, fn(c, p) { c.text(p, size=12.0) |> ignore }, fn(_) { true }, 0.0) |> ignore
      // (its owner said after the stack, as it shows: what was shown kept while the one on top has not what it shows)
      nav.flat_owned(true)
      b.reacts(fn() { (nav.top_stay(), ready.get()) }, fn(now) {
        if now.1 {
          was.val = now.0
          nav.flat_keep(None)
        } else if now.0 != was.val {
          nav.flat_keep(Some(was.val))
        }
      })
    })
  })
  t.draw()
  shown.set(false)
  t.draw()
  ready.set(false)
  nav.replace("b")
  shown.set(true)
  t.draw()
  assert_eq(left, [])
  assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["a"])
  ready.set(true)
  t.draw()
  assert_eq(flat_drawn(t).map(fn(d) { d.0 }), ["b"])
  assert_eq(left, ["a"])
}

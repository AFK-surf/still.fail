// What the host is told covers a native view in an old view in the window's tree (view_tell 4) when what takes a press
// over it is a node of the tree's own: told as the tree takes a finger there (drawn over it, shown, taking presses,
// where it is placed, where it says it takes one), nothing else; under a modal layer of the tree's, all of it.

///|
priv struct TreeCover {
  t : Tester
  page : NativeView
  shown : @signals.Signal[Bool]
  on : @signals.Signal[Bool]
  at : @signals.Signal[(Double, Double)]
  modal : @signals.Signal[Bool]
  /// the button, as last made
  button : Ref[@view.View?]
}

///|
/// A native view filling an old view in the window's tree, and a button of the tree's own 80 by 40 at its corner (drawn
/// over the old view where `over`, else under it), shown, taking presses and placed as its signals say; taking a finger
/// where `areas` says (none: all of it); a modal layer of the tree's over all as `modal` says. Drawn.
fn tree_cover(
  over~ : Bool,
  areas? : ((Double, Double, Double) -> Array[(Double, Double, Double, Double)])? = None,
) -> TreeCover {
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let at = @signals.signal((0.0, 0.0), same=fn(a, b) { a == b })
  let modal = @signals.signal(false, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  // (opened of the Tester's host)
  let page = NativeView::page("<p>page</p>")
  let button = fn(v : @view.View) {
    v.show(fn() { shown.get() }, fn(s) {
      let b = s.box(fn(b) {
        b
        .over(Is(true))
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .offset(By(fn() { at.get() }))
        .presses(By(fn() { on.get() }))
        .on_press(fn() {  })
        |> ignore
      })
      match areas {
        Some(f) => b.takes(f) |> ignore
        None => ()
      }
      made.val = Some(b)
    })
  }
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      if !over {
        button(b)
      }
      old(b, fn(c) { c.native(page) |> ignore }).over(Is(true)) |> ignore
      if over {
        button(b)
      }
      b.show(fn() { modal.get() }, fn(m) {
        m.box(fn(d) { d.over(Is(true)).width(Is(Some(10.0))).height(Is(Some(10.0))).modal(Is(true)) |> ignore }) |> ignore
      })
    })
    |> ignore
  })
  t.draw()
  t.frame_at(t.time() + frame_period_default)
  { t, page, shown, on, at, modal, button: made }
}

///|
fn TreeCover::next(self : TreeCover) -> Array[Double] {
  self.t.frame_at(self.t.time() + frame_period_default)
  covers_of(self.page)
}

///|
/// All of the native view, as it is told where it is.
fn whole_of(v : NativeView) -> Array[Double] {
  [v.at[4], v.at[5], v.at[6], v.at[7]]
}

///|
test "a button of the tree's own over a native view in an old view: told the host as what covers it; under it, not" {
  assert_eq(covers_of(tree_cover(over=true).page), [0.0, 0.0, 80.0, 40.0])
  assert_eq(covers_of(tree_cover(over=false).page), [], msg="under it")
}

///|
test "a button of the tree's own over a native view: hidden, none told; shown again, again; moved, where it is drawn" {
  let k = tree_cover(over=true)
  k.shown.set(false)
  assert_eq(k.next(), [], msg="hidden")
  k.shown.set(true)
  assert_eq(k.next(), [0.0, 0.0, 80.0, 40.0], msg="shown again")
  k.at.set((100.0, 50.0))
  assert_eq(k.next(), [100.0, 50.0, 180.0, 90.0], msg="moved")
}

///|
test "a button of the tree's own over a native view: taking presses no more, none told; again, again" {
  let k = tree_cover(over=true)
  k.on.set(false)
  assert_eq(k.next(), [], msg="taking no presses")
  k.on.set(true)
  assert_eq(k.next(), [0.0, 0.0, 80.0, 40.0], msg="taking them again")
}

///|
test "a modal layer of the tree's over an old view with a native view in it: all of the native view covered; closed, as before" {
  let k = tree_cover(over=true)
  k.modal.set(true)
  assert_eq(k.next(), whole_of(k.page), msg="under the modal layer")
  k.modal.set(false)
  assert_eq(k.next(), [0.0, 0.0, 80.0, 40.0], msg="closed")
}

///|
test "a button of the tree's own over a native view taking a finger in its right half only: that half told, the left the native view's; taking none, nothing" {
  let half = tree_cover(over=true, areas=Some(fn(w, h, _) { [(w / 2.0, 0.0, w, h)] }))
  assert_eq(covers_of(half.page), [40.0, 0.0, 80.0, 40.0])
  let none = tree_cover(over=true, areas=Some(fn(_, _, _) { [] }))
  assert_eq(covers_of(none.page), [], msg="taking none")
}


///|
/// A native view filling an old view in the window's tree, another old view over it with a button 80 by 40 at its
/// corner, the node hosting that one made so by `take` (as it takes a finger); drawn: what covers the native view.
fn old_over_covers(take : (@view.View) -> @view.View) -> Array[Double] {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  let page = NativeView::page("<p>page</p>")
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      old(b, fn(c) { c.native(page) |> ignore }).over(Is(true)) |> ignore
      old(b, fn(c) {
        let id = c.id("over")
        c.clicked(id) |> ignore
        c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
      })
      .over(Is(true))
      |> take
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame_at(t.time() + frame_period_default)
  covers_of(page)
}

///|
test "an old view over another's native view: its button a cover; the node hosting it taking no finger, none; taking one only where its own take it, as before" {
  assert_eq(old_over_covers(fn(v) { v }), [0.0, 0.0, 80.0, 40.0])
  assert_eq(old_over_covers(old_takes_none), [], msg="taking no finger")
  assert_eq(old_over_covers(old_takes_own), [0.0, 0.0, 80.0, 40.0], msg="where its own take it")
  assert_eq(old_over_covers(fn(v) { v.takes(fn(w, h, _) { [(w - 20.0, 0.0, w, h)] }) }), [], msg="only away from it")
}

///|
test "a button of the tree's own over a native view, where it takes a finger changed alone (nothing pointing, nothing else of it): a frame asked for, the host told; back, again" {
  let right = @signals.signal(false, same=fn(a, b) { a == b })
  let k = tree_cover(over=true, areas=Some(fn(w, h, _) { if right.get() { [(w / 2.0, 0.0, w, h)] } else { [] } }))
  assert_eq(covers_of(k.page), [])
  right.set(true)
  // (the frames asked for drawn, none else: a change of the test's is no frame of its own, Tester::frames_owed)
  assert_eq(k.t.wanted_after(), 0.0, msg="a frame asked for")
  k.t.frames_owed()
  assert_eq(covers_of(k.page), [40.0, 0.0, 80.0, 40.0], msg="taking its right half")
  right.set(false)
  assert_eq(k.t.wanted_after(), 0.0, msg="a frame asked for again")
  k.t.frames_owed()
  assert_eq(covers_of(k.page), [], msg="taking none again")
}

///|
test "a button of the tree's own over a native view, where it takes a finger read of its own: followed while it is there; let go, at once no more, no frame drawn" {
  let src = @signals.signal(true, same=fn(a, b) { a == b })
  let k = tree_cover(over=true, areas=Some(fn(w, h, _) { if src.get() { [(0.0, 0.0, w, h)] } else { [] } }))
  assert_eq(covers_of(k.page), [0.0, 0.0, 80.0, 40.0])
  assert_true(src.watched(), msg="followed")
  k.shown.set(false)
  assert_false(src.watched(), msg="let go")
}

///|
test "a button of the tree's own over a native view, where it takes a finger said anew: what the first read no more followed at once, a frame asked for, the host told the new" {
  let first = @signals.signal(true, same=fn(a, b) { a == b })
  let next = @signals.signal(true, same=fn(a, b) { a == b })
  let k = tree_cover(over=true, areas=Some(fn(w, h, _) { if first.get() { [(0.0, 0.0, w, h)] } else { [] } }))
  assert_eq(covers_of(k.page), [0.0, 0.0, 80.0, 40.0])
  k.button.val.unwrap().takes(fn(w, h, _) { if next.get() { [(w / 2.0, 0.0, w, h)] } else { [] } }) |> ignore
  assert_false(first.watched(), msg="the first no more followed")
  assert_eq(k.t.wanted_after(), 0.0, msg="a frame asked for")
  k.t.frames_owed()
  assert_eq(covers_of(k.page), [40.0, 0.0, 80.0, 40.0], msg="the new told")
  assert_true(next.watched(), msg="the new followed")
}

///|
/// The tree's node the pointer is over now (Tree::pointed_now).
fn pointed_now() -> @view.NodeId? {
  view_app.val.unwrap().pointed_now()
}

///|
test "a button of the tree's own over a native view, pointed at, where it takes a finger read of its own: let go, at once followed no more; changed after, nothing woken" {
  let src = @signals.signal(true, same=fn(a, b) { a == b })
  let k = tree_cover(over=true, areas=Some(fn(w, h, _) { if src.get() { [(0.0, 0.0, w, h)] } else { [] } }))
  k.t.move(60.0, 20.0)
  assert_eq(pointed_now(), Some(k.button.val.unwrap().id()), msg="pointed at")
  assert_true(src.watched(), msg="followed")
  k.shown.set(false)
  assert_false(src.watched(), msg="let go")
  k.t.frames_owed()
  src.set(false)
  assert_eq(k.t.wanted_after(), @double.infinity, msg="nothing woken")
}

///|
test "a button of the tree's own over a native view, pointed at, where it takes a finger said anew: the first followed no more at once, changed after nothing woken; the new followed, what is pointed at and the host's covers as it says" {
  let first = @signals.signal(true, same=fn(a, b) { a == b })
  let next = @signals.signal(true, same=fn(a, b) { a == b })
  let k = tree_cover(over=true, areas=Some(fn(w, h, _) { if first.get() { [(0.0, 0.0, w, h)] } else { [] } }))
  k.t.move(60.0, 20.0)
  let id = k.button.val.unwrap().id()
  assert_eq(pointed_now(), Some(id), msg="pointed at")
  k.button.val.unwrap().takes(fn(w, h, _) { if next.get() { [(w / 2.0, 0.0, w, h)] } else { [] } }) |> ignore
  assert_false(first.watched(), msg="the first no more followed")
  k.t.frames_owed()
  assert_eq(pointed_now(), Some(id), msg="its right half pointed at still")
  assert_eq(covers_of(k.page), [40.0, 0.0, 80.0, 40.0], msg="the new told")
  first.set(false)
  assert_eq(k.t.wanted_after(), @double.infinity, msg="the first changed: nothing woken")
  next.set(false)
  assert_eq(k.t.wanted_after(), 0.0, msg="the new changed: a frame asked for")
  k.t.frames_owed()
  assert_eq(pointed_now(), None, msg="taking none: pointed at no more")
  assert_eq(covers_of(k.page), [], msg="none told")
}

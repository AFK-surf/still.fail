// A cover of the window's tree's over an old view, its hold going through (View::gesture's `through`): a finger held
// still on it is the old view's from then, as long held as since it went down.

///|
let through_later_ms : Double = 100.0

///|
/// A cover 80 by 40 over an old view's button the same size at its corner (named as `name` says at each build: what
/// is there, made anew by another name), a finger held still on it past a long press; `anew`: the button made anew by
/// another name before then; `frames`: frames drawn as it is held (else none between its down and its up). What each
/// was told, in order (the button: held long, clicked; `still`: as long held still as a long press, as what holds
/// still over words asks: Ctx::held_for).
fn old_through(anew : Bool, frames? : Bool = true, still? : Bool = false) -> Array[String] {
  let said : Array[String] = []
  let name = @signals.signal("a", same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=2)
  t.check_looks(false)
  let note = fn(s : String) {
    if said.last() != Some(s) {
      said.push(s)
    }
  }
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      old(b, fn(c) {
        let n = name.get()
        let id = c.id(n)
        if c.clicked(id) {
          note("\{n} clicked")
        }
        if c.held_long(id) {
          note("\{n} held")
        }
        if still && c.held_for(long_press_ms) {
          note("\{n} still")
        }
        c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
      })
      .over(Is(true))
      |> ignore
      b.box(fn(cv) {
        cv
        .over(Is(true))
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .gesture(
          touch_slop(),
          press=fn(_) { note("cover press") },
          tap=fn(_) { note("cover tap") },
          drag=fn(d) { note("cover drag \{d.kind}") },
          through=long_press_ms,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.touch(0, 20.0, 20.0)
  if !frames {
    // (held past a long press, let go, no frame between: drawn after)
    t.advance(long_press_ms + through_later_ms)
    t.touch(2, 20.0, 20.0)
    t.draw()
    return said
  }
  t.draw()
  if anew {
    t.run_for(through_later_ms)
    name.set("b")
    t.draw()
  }
  t.run_for(long_press_ms + through_later_ms)
  t.touch(2, 20.0, 20.0)
  t.draw()
  said
}

///|
test "a cover over an old view's button, held still past a long press: its own hold called off (Off, no tap), the button held long as a finger held on it is, then not clicked" {
  assert_eq(old_through(false), ["cover press", "cover drag Off", "a held"])
}

///|
test "a cover over an old view's button made anew by another name before a long press: nothing handed to the new one, the cover's a hold still (no tap)" {
  let said = old_through(true)
  assert_false(said.iter().any(fn(s) { s.has_prefix("a ") || s.has_prefix("b ") }), msg="\{said}")
  assert_false(said.contains("cover tap"), msg="\{said}")
}

///|
test "a cover over an old view's button, held past a long press and let go with no frame between: the button held long once, not clicked, as with frames" {
  assert_eq(old_through(false, frames=false), ["cover press", "cover drag Off", "a held"])
  assert_eq(old_through(false, frames=false), old_through(false), msg="frames or none")
}

///|
test "a cover over an old view's button, held still past a long press: the press the old view is handed held still as long as since the finger went down, at once (what a hold over words asks)" {
  assert_eq(old_through(false, still=true), ["cover press", "cover drag Off", "a held", "a still"])
}

///|
/// A cover 80 by 40 a finger drags only once held (View::gesture's `held_first`), over an old view's area the same size
/// that a finger drags across (Ctx::drag_on) and that says when it is held long or clicked; a finger down on it at 20,
/// moved past the slop at once to `to` and let go there, frames drawn between each (`frames`) or none: what each was
/// told, in order, how far the area was dragged, and the haptics felt.
fn old_moved_through(to : Double, frames : Bool) -> (Array[String], Double, Array[Haptic]) {
  let said : Array[String] = []
  let moved = Ref(0.0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=2)
  t.check_looks(false)
  let note = fn(s : String) {
    if said.last() != Some(s) {
      said.push(s)
    }
  }
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      old(b, fn(c) {
        let id = c.id("area")
        c.drag_on(id, axis=Horizontal)
        match c.drag_of(id) {
          Some(d) => moved.val = moved.val + d.take_move().0
          None => ()
        }
        if c.clicked(id) {
          note("area clicked")
        }
        if c.held_long(id) {
          note("area held")
        }
        c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
      })
      .over(Is(true))
      |> ignore
      b.box(fn(cv) {
        cv
        .over(Is(true))
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .gesture(
          touch_slop(),
          press=fn(_) { note("cover press") },
          tap=fn(_) { note("cover tap") },
          hold=(long_press_ms, fn(_) { note("cover held") }),
          drag=fn(d) { note("cover drag \{d.kind}") },
          held_first=fn(_) { true },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let t0 = t.time() + 10.0
  t.advance(t0 - t.time())
  t.touch_raw(0, 1, 20.0, 20.0, t0)
  if frames {
    t.frame_at(t0 + 8.0)
  }
  t.advance(t0 + 16.0 - t.time())
  t.touch_raw(1, 1, to, 20.0, t0 + 16.0)
  if frames {
    t.frame_at(t0 + 24.0)
  }
  t.advance(t0 + 32.0 - t.time())
  t.touch_raw(2, 1, to, 20.0, t0 + 32.0)
  t.run_for(long_press_ms * 2.0)
  (said, moved.val, t.haptics())
}

///|
test "a cover dragged only once held over an old view's area, moved past the slop at once and let go: the area dragged as far, not held long, not clicked, nothing felt; the cover's press called off, frames or none" {
  let want : (Array[String], Double, Array[Haptic]) = (["cover press", "cover drag Off"], 40.0, [])
  assert_eq(old_moved_through(60.0, true), want)
  assert_eq(old_moved_through(60.0, false), want)
}

///|
/// A cover 80 by 40 a finger drags only once held, over a node of the tree's that takes a drag (`under1`); its press
/// called off (Off) takes that node away (`off`: 1 it gone, 2 another made in its place, `under2`; 3 a modal layer
/// opened over it, the cover in it; 0 nothing). A finger
/// down on it at 20, moved past the slop at once to 60 (as a host hands them on, nothing else after): what each was told
/// as the move is handed on, before anything else (no up, no frame, the tree brought nowhere).
fn tree_moved_through(off : Int) -> Array[String] {
  let said : Array[String] = []
  let first = @signals.signal(true, same=fn(a, b) { a == b })
  let modal_on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=2)
  t.check_looks(false)
  let under = fn(name : String) {
    fn(u : @view.View) {
      u
      .over(Is(true))
      .gesture(
        touch_slop(),
        press=fn(d) { said.push("\{name} press at \{d.wx}") },
        tap=fn(_) { said.push("\{name} tap") },
        drag=fn(d) { said.push("\{name} drag \{d.kind} at \{d.wx}") },
      )
      |> ignore
    }
  }
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      b.show(fn() { first.get() }, under("under1"))
      if off == 2 {
        b.show(fn() { !first.get() }, under("under2"))
      }
      // (what a modal layer opened over all of it takes: nothing under it)
      if off == 3 {
        b.show(fn() { modal_on.get() }, fn(m) { m.over(Is(true)).modal(Is(true)) |> ignore })
      }
      b.box(fn(cv) {
        cv
        .over(Is(true))
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .gesture(
          touch_slop(),
          press=fn(_) { said.push("cover press") },
          tap=fn(_) { said.push("cover tap") },
          hold=(long_press_ms, fn(_) { said.push("cover held") }),
          drag=fn(d) {
            said.push("cover drag \{d.kind}")
            if d.kind == Off && off == 3 {
              modal_on.set(true)
            } else if d.kind == Off && off != 0 {
              first.set(false)
            }
          },
          held_first=fn(_) { true },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let t0 = t.time() + 10.0
  t.advance(t0 - t.time())
  t.touch_raw(0, 1, 20.0, 20.0, t0)
  t.advance(t0 + 16.0 - t.time())
  t.touch_raw(1, 1, 60.0, 20.0, t0 + 16.0)
  said.copy()
}

///|
test "a cover dragged only once held over a node of the tree's, moved past the slop at once: the node told it went down and moved by the time the move is handed on, no frame, nothing else after" {
  assert_eq(tree_moved_through(0), [
    "cover press", "cover drag Off", "under1 press at 20", "under1 drag Down at 60",
  ])
}

///|
test "a cover dragged only once held, its press called off taking the node under it away, or putting another there: neither handed the finger" {
  assert_eq(tree_moved_through(1), ["cover press", "cover drag Off"])
  assert_eq(tree_moved_through(2), ["cover press", "cover drag Off"])
}

///|
test "a cover dragged only once held, its press called off opening a modal layer over what is under it: nothing under it handed the finger" {
  assert_eq(tree_moved_through(3), ["cover press", "cover drag Off"])
}

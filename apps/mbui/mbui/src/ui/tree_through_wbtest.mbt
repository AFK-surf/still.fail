// A cover of the window's tree's over an old view, its hold going through (View::gesture's `through`): a finger held
// still on it is the old view's from then, as long held as since it went down.

///|
let through_later_ms : Double = 100.0

///|
/// A cover 80 by 40 over an old view's button the same size at its corner (named as `name` says at each build: what
/// is there, made anew by another name), a finger held still on it past a long press; `anew`: the button made anew by
/// another name before then; `frames`: frames drawn as it is held (else none between its down and its up). What each
/// was told, in order (the button: held long, clicked).
fn old_through(anew : Bool, frames? : Bool = true) -> Array[String] {
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

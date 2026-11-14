// A page's list of blocks made as they show (View::scrolls_window), a key come or gone in one change: that block alone
// is made or let go, the others in sight kept as they were (their drawing not made again, their words not drawn
// anew), however many passes measuring what shows takes. A key appended at its foot, never measured, had been all that
// showed for a pass: every block in sight let go and made again, for one row come.

///|
priv struct CauseCase {
  t : Tester
  keys : @signals.Signal[Array[Int]]
  /// how many times each key's block was made, and let go
  made : Map[Int, Int]
  gone : Map[Int, Int]
}

///|
/// How tall key `k`'s block is: 90 for 99, else 40 (all counted 40 before they are laid out).
fn cause_tall(k : Int) -> Double {
  if k == 99 {
    90.0
  } else {
    40.0
  }
}

///|
/// A list 300 tall in a window 300 by 400 of `keys`, following its foot where `follows`: each block a box as tall as
/// cause_tall says, its key's words on its own ground.
fn cause_case(keys : Array[Int], follows : Bool) -> CauseCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let made : Map[Int, Int] = Map([])
  let gone : Map[Int, Int] = Map([])
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(scroll, fn() { keys.get() }, est=40.0, follows=fn() { follows }, fn(b, k) {
        made[k] = made.get(k).unwrap_or(0) + 1
        b.owns(fn() { gone[k] = gone.get(k).unwrap_or(0) + 1 }) |> ignore
        b.box(fn(row) {
          row
          .height(Is(Some(cause_tall(k))))
          .ground(Is(0x40000000L + (k + 10).to_int64() * 0x100L + 0xFFL))
          .words(Is("row \{k}"))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  { t, keys, made, gone }
}

///|
/// The keys whose blocks are drawn now in sight (by their grounds, within the list's 300), top to bottom: one made
/// past its edge is drawn out of sight.
fn CauseCase::drawn(self : CauseCase) -> Array[Int] {
  let out = []
  for r in self.t.drawn_rects() {
    let c = r.4 - 0x40000000L - 0xFFL
    if r.1 < 300.0 && r.1 + r.3 > 0.0 && c >= 0L && c % 0x100L == 0L && c / 0x100L < 1000L {
      out.push(((c / 0x100L).to_int() - 10, r.1))
    }
  }
  out.sort_by(fn(a, b) { a.1.compare(b.1) })
  out.map(fn(d) { d.0 })
}

///|
/// The keys change to `then` (each change of `changes` said in turn, no frame between), then the list is drawn and run
/// to rest. Which keys were made, and let go, by it (each with how many times), and how many contents' drawings were made
/// again (view_paint_work's).
fn CauseCase::change(self : CauseCase, changes : Array[Array[Int]]) -> (Map[Int, Int], Map[Int, Int], Int) {
  let made0 = self.made.copy()
  let gone0 = self.gone.copy()
  let paint0 = view_paint_work.made
  for c in changes {
    self.keys.set(c)
  }
  self.t.draw()
  self.t.run_for(move_most_ms)
  let made : Map[Int, Int] = Map([])
  for k, n in self.made {
    if n != made0.get(k).unwrap_or(0) {
      made[k] = n - made0.get(k).unwrap_or(0)
    }
  }
  let gone : Map[Int, Int] = Map([])
  for k, n in self.gone {
    if n != gone0.get(k).unwrap_or(0) {
      gone[k] = n - gone0.get(k).unwrap_or(0)
    }
  }
  (made, gone, view_paint_work.made - paint0)
}

///|
/// What a change may let go: the blocks drawn before it and not after (scrolled out of sight by it, or gone with
/// their keys), none still drawn.
fn cause_let_go(before : Array[Int], after : Array[Int], gone : Map[Int, Int]) -> Array[String] {
  let faults = []
  for k, _ in gone {
    if after.contains(k) {
      faults.push("\{k}: let go and made again, still in sight")
    }
    if !before.contains(k) {
      faults.push("\{k}: let go, never drawn")
    }
  }
  faults
}

///|
test "following its foot, a key appended: its block alone made, none in sight let go" {
  let c = cause_case(Array::makei(30, fn(i) { i }), true)
  let before = c.drawn()
  let (made, gone, painted) = c.change([Array::makei(31, fn(i) { i })])
  assert_eq(made.to_array(), [(30, 1)])
  assert_eq(cause_let_go(before, c.drawn(), gone), [])
  assert_eq(painted, 1, msg="contents' drawings made again: \{painted}")
  assert_eq(c.drawn().last(), Some(30))
}

///|
test "following its foot, a key appended taller than counted (measured again, a pass more): its block alone made" {
  let c = cause_case(Array::makei(30, fn(i) { i }), true)
  let before = c.drawn()
  let (made, gone, painted) = c.change([[..Array::makei(30, fn(i) { i }), 99]])
  assert_eq(made.to_array(), [(99, 1)])
  assert_eq(cause_let_go(before, c.drawn(), gone), [])
  assert_eq(painted, 1, msg="contents' drawings made again: \{painted}")
}

///|
test "following its foot, two keys appended in one change: those two alone made" {
  let c = cause_case(Array::makei(30, fn(i) { i }), true)
  let before = c.drawn()
  let (made, gone, painted) = c.change([Array::makei(32, fn(i) { i })])
  let m = made.to_array()
  m.sort()
  assert_eq(m, [(30, 1), (31, 1)])
  assert_eq(cause_let_go(before, c.drawn(), gone), [])
  assert_eq(painted, 2, msg="contents' drawings made again: \{painted}")
}

///|
test "following its foot, two keys come one after another, the second before the first is measured: those two alone made" {
  let c = cause_case(Array::makei(30, fn(i) { i }), true)
  let before = c.drawn()
  let (made, gone, painted) = c.change([Array::makei(31, fn(i) { i }), Array::makei(32, fn(i) { i })])
  let m = made.to_array()
  m.sort()
  assert_eq(m, [(30, 1), (31, 1)])
  assert_eq(cause_let_go(before, c.drawn(), gone), [])
  assert_eq(painted, 2, msg="contents' drawings made again: \{painted}")
}

///|
test "at its top, a key put in the middle of what shows: its block alone made" {
  let c = cause_case(Array::makei(30, fn(i) { i }), false)
  let before = c.drawn()
  let (made, gone, painted) = c.change([[0, 1, 2, 50, ..Array::makei(27, fn(i) { i + 3 })]])
  assert_eq(made.to_array(), [(50, 1)])
  assert_eq(cause_let_go(before, c.drawn(), gone), [])
  assert_eq(painted, 1, msg="contents' drawings made again: \{painted}")
}

// These four held before this mend too: kept so the property is pinned whole, blocks coming and going, in sight and
// out of it (a mend to this fill is what could break them).

///|
test "a list opened at its foot: each block made once, none let go" {
  let c = cause_case(Array::makei(30, fn(i) { i }), true)
  let twice = c.made.iter().filter(fn(e) { e.1 != 1 }).collect()
  assert_eq(twice, [])
  assert_eq(c.gone.length(), 0)
  assert_true(c.drawn().contains(29) && !c.drawn().contains(0), msg="\{Repr(c.drawn())}")
}

///|
test "following its foot, its last key gone: that block alone let go, none made" {
  let c = cause_case(Array::makei(30, fn(i) { i }), true)
  let before = c.drawn()
  let (made, gone, _) = c.change([Array::makei(29, fn(i) { i })])
  // (one come into sight over what showed, the column at its foot: made, as it comes to show)
  let came = made.to_array().filter(fn(e) { before.contains(e.0) })
  assert_eq(came, [])
  assert_eq(gone.get(29), Some(1))
  assert_eq(cause_let_go(before, c.drawn(), gone), [])
}

///|
test "at its top, a key in the middle of what shows gone: that block alone let go, none in sight made again" {
  let c = cause_case(Array::makei(30, fn(i) { i }), false)
  let before = c.drawn()
  let (made, gone, painted) = c.change([Array::makei(30, fn(i) { i }).filter(fn(k) { k != 3 })])
  assert_eq(made.to_array().filter(fn(e) { before.contains(e.0) }), [])
  assert_eq(gone.get(3), Some(1))
  assert_eq(cause_let_go(before, c.drawn(), gone), [])
  // (the one come into sight at its foot, made: its drawing alone)
  assert_eq(painted, made.length(), msg="contents' drawings made again: \{painted}, blocks made \{Repr(made)}")
}

///|
test "scrolled up off its foot, a key appended out of sight: nothing made, none in sight let go" {
  let c = cause_case(Array::makei(30, fn(i) { i }), true)
  c.t.wheel_phase(100.0, 100.0, -200.0, 4)
  c.t.run_for(move_most_ms)
  let before = c.drawn()
  let (made, gone, painted) = c.change([Array::makei(31, fn(i) { i })])
  assert_eq(made.length(), 0, msg="\{Repr(made)}")
  // (one made past the list's edge, out of sight, may be let go as the list is laid out again: none in sight)
  assert_eq(gone.to_array().filter(fn(e) { before.contains(e.0) }), [], msg="\{Repr(gone)}, drawn \{Repr(before)}")
  assert_eq(painted, 0, msg="contents' drawings made again: \{painted}")
  assert_eq(c.drawn(), before)
}

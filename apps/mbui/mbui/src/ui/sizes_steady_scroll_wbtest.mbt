// Sizes steady (sizes_steady.mbt) in what a node of the window's tree scrolls (View::scrolls): what it holds measured
// where it stands in what scrolls, as a list's rows are in their list. Something come or gone at once over its rows is
// their jolt; the hand's scroll moving them all the same way is none of theirs.

///|
/// A column of the tree's 200 tall that scrolls, at the top of a window 400 by 300, holding (while `over` says so) a box
/// 100 tall over twelve rows of words 40 tall, each on a ground of its own (what sizes steady measures draws its own):
/// sizes steady said but not held (its faults read here, steady_faults).
fn steady_scroll_case(over : @signals.Signal[Bool]) -> (Tester, @view.Scroll) {
  let scroll = @view.Scroll::new()
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v
      .width(Is(Some(400.0)))
      .height(Is(Some(200.0)))
      .scrolls(scroll, fn(held) {
        held.show(at_once=true, fn() { over.get() }, fn(o) { o.box(fn(b) { b.height(Is(Some(100.0))) |> ignore }) |> ignore })
        for i in 0..<12 {
          held.box(fn(r) {
            r.width(Is(Some(160.0))).height(Is(Some(40.0))).ground(Is(0x336699FFL)).words(Is("第\{i}行")) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, scroll)
}

///|
/// `frames` frames drawn one at a time, the display's; what sizes steady finds in each, gathered.
fn steady_faults(t : Tester, frames : Int) -> Array[String] {
  let out = []
  for _ in 0..<frames {
    t.frame()
    out.append(g().sizes_steady_faults(t.fake.time, t.period))
  }
  out
}

///|
test "sizes steady in what a node of the tree's scrolls: a box gone at once over its rows a jolt of theirs; the same move by the wheel none" {
  // (gone at once, nobody scrolling: its rows 100 up in one frame)
  let over = @signals.signal(true, same=fn(a, b) { a == b })
  let (t, _) = steady_scroll_case(over)
  let before = steady_faults(t, 4)
  over.set(false)
  let gone = steady_faults(t, 4)
  // (the wheel 100 down over it, at once: its rows 100 up in one frame, by the hand)
  let still = @signals.signal(true, same=fn(a, b) { a == b })
  let (w, scroll) = steady_scroll_case(still)
  let rest = steady_faults(w, 4)
  w.wheel(80.0, 100.0, 100.0)
  let wheeled = steady_faults(w, 4)
  assert_eq((before, rest), ([], []))
  assert_true(gone.length() > 0, msg="gone at once over its rows: no jolt found")
  assert_eq((scroll.at(view_tree().unwrap()), wheeled), (100.0, []))
}

// An old list put elsewhere at once by the app (Ctx::list_scroll_to: put_at): what its rows hold at its top, a head
// stuck under its edge (Ctx::stick), steps in its row with the list's put, for no cause of its own; that same head
// stepping in its row with the list where it was is a jolt, as is a step of it a few frames after a put.

///|
/// An old list 300 tall in a window 400 by 300, ten rows 200 tall, each a head stuck at the list's top (`gap` over it
/// in its row) over its words; put at row `put` (its top 100 over the list's) as the next frame is built where `put` says
/// one: sizes steady said but not held (its faults read here, steady_faults).
fn steady_stuck_case(put : Ref[Int], gap : Ref[Double]) -> Tester {
  let t = Tester::new(
    fn(c) {
      c.list("stuck", 10, 200.0, fn(i) {
        c.column(h=Px(200.0), fn() {
          c.box(h=Px(gap.val), fn() {  }) |> ignore
          let head = c.column(fn() { c.text("第\{i}行的头", size=14.0, line=20.0) |> ignore })
          c.stick(head, 0.0)
          c.text("第\{i}行", size=14.0, line=20.0) |> ignore
        })
        |> ignore
      })
      |> ignore
      if put.val >= 0 {
        c.list_scroll_to("stuck", put.val, offset=100.0)
        put.val = -1
      }
    },
    w=400.0,
    h=300.0,
    words_over_held=false,
  )
  t.check_looks(false)
  t.draw()
  t
}

///|
test "sizes steady in an old list put elsewhere at once: its rows' stuck heads stepping with the put none; a head stepping with no put, or a few frames after one, a jolt" {
  // (put at row 0, its top 100 over the list's: row 0's head held at the list's top, 100 down in its row, in the put's
  // frame)
  let put = Ref(-1)
  let gap = Ref(0.0)
  let t = steady_stuck_case(put, gap)
  let rest = steady_faults(t, 4)
  put.val = 0
  t.stepped()
  let put_faults = steady_faults(t, 6)
  assert_eq((rest, put_faults), ([], []))
  // (the list where it was, a head 30 down in its row at once: its own step)
  let put = Ref(-1)
  let gap = Ref(0.0)
  let t = steady_stuck_case(put, gap)
  steady_faults(t, 4) |> ignore
  gap.val = 30.0
  t.stepped()
  let stepped = steady_faults(t, 4)
  assert_true(stepped.length() > 0, msg="a head stepping in its row with the list where it was: no jolt found")
  // (put, then four frames on a head 30 down in its row with no put: that one a jolt)
  let put = Ref(-1)
  let gap = Ref(0.0)
  let t = steady_stuck_case(put, gap)
  steady_faults(t, 4) |> ignore
  put.val = 0
  t.stepped()
  let after_put = steady_faults(t, 4)
  gap.val = 30.0
  t.stepped()
  let later = steady_faults(t, 4)
  assert_eq(after_put, [])
  assert_true(later.length() > 0, msg="a step a few frames after a put: no jolt found")
}

///|
/// A column 300 tall in a window 400 by 300: a box 150 tall over what scrolls (`open` showing it, making its way in),
/// and what scrolls taking the rest, holding six rows of words 40 tall on grounds of their own (the first while `first`
/// says so, gone at once): 240 in all, as much as it shows at first, more once the box over it has opened past 60. Its
/// Tester's sizes steady said but not held (steady_faults).
fn steady_squeezed_case(open : @signals.Signal[Bool], first : @signals.Signal[Bool]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
      col.show(fn() { open.get() }, fn(s) {
        s.box(fn(b) { b.height(Is(Some(150.0))).ground(Is(0x663399FFL)) |> ignore }) |> ignore
      })
      col.box(fn(v) {
        v.scrolls(@view.Scroll::new(), fn(held) {
          for i in 0..<6 {
            let row = fn(r : @view.View) {
              r.width(Is(Some(160.0))).height(Is(Some(40.0))).ground(Is(0x336699FFL)).words(Is("第\{i}行")) |> ignore
            }
            if i == 0 {
              held.show(at_once=true, fn() { first.get() }, fn(o) { o.box(row) |> ignore })
            } else {
              held.box(row) |> ignore
            }
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "sizes steady in what a node of the tree's scrolls: what it holds measured from its top all along, as what it holds comes to be taller than it; a row gone at once then still a jolt" {
  // (the box over it opening: what scrolls squeezed under it, its rows going down in the window with its top, what it
  // holds coming to be more than it shows half way; nothing of its rows' own)
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  let first = @signals.signal(true, same=fn(a, b) { a == b })
  let t = steady_squeezed_case(open, first)
  let rest = steady_faults(t, 4)
  open.set(true)
  let squeezed = steady_faults(t, 40).filter(fn(f) { f.contains("行") })
  // (the same, and its first row gone at once as the box over it is half way open: the rows under it up 40 in one frame)
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  let first = @signals.signal(true, same=fn(a, b) { a == b })
  let w = steady_squeezed_case(open, first)
  steady_faults(w, 4) |> ignore
  open.set(true)
  steady_faults(w, 10) |> ignore
  first.set(false)
  let jolted = steady_faults(w, 30).filter(fn(f) { f.contains("行") })
  assert_eq((rest, squeezed), ([], []))
  assert_true(jolted.length() > 0, msg="a row gone at once half way: no jolt found")
}

///|
test "sizes steady: at speed then at rest, and so the frame after, a dead stop; turned back through rest between two frames, none" {
  let p = 1000.0 / 60.0
  let at = fn(ys : Array[Double]) { ys.mapi(fn(i, y) { (i.to_double() * p, i.to_double() * p, y) }) }
  // (a sheet closed as it grows: up 29 a frame, then down, its turn between two frames)
  let turn = at([0.0, -30.0, -59.0, -56.2, -11.4])
  assert_true(sizes_steady_fault(turn, p, turned=-1.0e9).0 is None)
  let stop = at([0.0, -30.0, -59.0, -59.5, -59.5])
  assert_true(sizes_steady_fault(stop, p, turned=-1.0e9).0 is Some(_))
}

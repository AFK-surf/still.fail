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

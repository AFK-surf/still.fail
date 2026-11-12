// A page's list on the window's tree (View::scrolls with Scroll::list) where its host sets its rows on its pixels, as it
// does an old view's list's (Ctx::row_slot, Ctx::rows_on_pixels; a Tester's fake host as it is told to: Tester::set_rows_on_pixels): its
// rows each as tall as whole pixels, all moved alike so the first one's top is on one, where the list is laid out and
// where it is scrolled to; pressed where they are drawn. A Tester not told so lays them where they are laid out.

///|
/// A column of the window's tree, 10.3 under the window's top, scrolling as a page's list, holding 30 rows 20.3 high
/// (a ground each of its own; the one pressed said to `pressed`), at 2 pixels a point: its scroll.
fn rows_pixels_tree(pressed : Array[Int]) -> (Tester, @view.Scroll) {
  let s = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0, scale=2.0)
  set_view_app(fn(root) {
    root.box(fn(gap) { gap.height(Is(Some(10.3))) |> ignore }) |> ignore
    root.box(fn(col) {
      col
      .width(Is(Some(300.0)))
      .height(Is(Some(300.0)))
      .scrolls(s, fn(body) {
        for i in 0..<30 {
          body.box(fn(row) {
            row
            .height(Is(Some(20.3)))
            .ground(Is(0x10000000L + i.to_int64() * 0x100L + 0xFFL))
            .on_press(fn() { pressed.push(i) })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, s)
}

///|
/// Where row `i` is drawn down the window and how tall (its ground's).
fn rows_pixels_row(t : Tester, i : Int) -> (Double, Double) {
  let ink = 0x10000000L + i.to_int64() * 0x100L + 0xFFL
  match t.drawn_rects().search_by(fn(r) { r.4 == ink }) {
    Some(k) => (t.drawn_rects()[k].1, t.drawn_rects()[k].3)
    None => (-1.0, -1.0)
  }
}

///|
test "a page's list where its host sets its rows on its pixels: each as tall as whole pixels, the first one's top on one, scrolled too; pressed where drawn" {
  let pressed = []
  let (t, s) = rows_pixels_tree(pressed)
  t.set_rows_on_pixels(true)
  t.draw()
  // (laid out from 10.3, 20.3 each: on 2 pixels a point from 10.5, 20.5 each)
  assert_eq((0).until(4).map(fn(i) { rows_pixels_row(t, i) }).collect(), [
    (10.5, 20.5),
    (31.0, 20.5),
    (51.5, 20.5),
    (72.0, 20.5),
  ])
  // (a point under row 3's foot as laid out (10.3 + 4 × 20.3 = 91.5), within it as drawn: row 3's)
  t.tap(100.0, 91.8)
  assert_eq(pressed, [3])
  // (scrolled a part of a pixel: its first row's top on one again, from where it is scrolled to)
  t.wheel_phase(100.0, 100.0, 3.3, 4)
  t.run_for(move_most_ms)
  let at = s.at(view_tree().unwrap())
  assert_true(at > 0.0 && at * 2.0 != (at * 2.0).round(), msg="scrolled by a part of a pixel: \{at}")
  let top = 10.3 - at
  let first = (top * 2.0).round() / 2.0
  assert_eq(rows_pixels_row(t, 0), (first, 20.5))
  assert_eq(rows_pixels_row(t, 3), (first + 3.0 * 20.5, 20.5))
}

///|
test "a page's list where its host does not set its rows on its pixels: each where it is laid out, as tall" {
  let (t, _) = rows_pixels_tree([])
  assert_eq((0).until(3).map(fn(i) { rows_pixels_row(t, i) }).collect(), [(10.3, 20.3), (10.3 + 20.3, 20.3), (10.3 + 20.3 + 20.3, 20.3)])
}

///|
/// A column of the window's tree, 10.3 under the window's top, 300 tall, scrolling as a page's list holding the blocks
/// `keys` names (View::scrolls_window, each 20.3 high, counted so before it is laid out; a ground each of its own), at 2
/// pixels a point: its scroll.
fn rows_window_tree(keys : @signals.Signal[Array[Int]]) -> (Tester, @view.Scroll) {
  let s = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0, scale=2.0)
  set_view_app(fn(root) {
    root.box(fn(gap) { gap.height(Is(Some(10.3))) |> ignore }) |> ignore
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(s, fn() { keys.get() }, est=20.3, fn(b, k) {
        b.box(fn(row) {
          row.height(Is(Some(20.3))).ground(Is(0x20000000L + (k + 10).to_int64() * 0x100L + 0xFFL)) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, s)
}

///|
/// The rows of rows_window_tree drawn: each one's key, where it is drawn down the window and how tall, top to bottom.
fn rows_window_drawn(t : Tester) -> Array[(Int, Double, Double)] {
  let out = []
  for r in t.drawn_rects() {
    let c = r.4 - 0x20000000L - 0xFFL
    if c >= 0L && c % 0x100L == 0L && c / 0x100L < 1000L {
      out.push(((c / 0x100L).to_int() - 10, r.1, r.3))
    }
  }
  out.sort_by(fn(a, b) { a.1.compare(b.1) })
  out
}

///|
/// Each row drawn (rows_window_drawn) where a page's list's rows on 2 pixels a point are: 20.5 apart (each block's room
/// as tall as whole pixels, what it holds as tall as it is laid out, 20.3), the first one's top on a pixel from where it is laid out (10.3 under the window's top, `at` scrolled, row `i` 20.5 × i down);
/// and as many as fill the column's 300 down to its foot.
fn rows_window_faults(t : Tester, at : Double, first_key : Int) -> Array[String] {
  let faults = []
  let drawn = rows_window_drawn(t)
  let top = 10.3 - at
  let on = (top * 2.0).round() / 2.0
  for d in drawn {
    let i = (d.0 - first_key).to_double()
    let want = on + 20.5 * i
    // (where it is drawn summed down what holds it: the same sum but for its last bits, a billionth of a point)
    if (d.1 - want).abs() > 1.0e-9 || d.2 != 20.3 {
      faults.push("row \{d.0}: at \{d.1} \{d.2} tall, not \{want} 20.3")
    }
  }
  match drawn.last() {
    Some(l) => if l.1 + l.2 < 310.3 { faults.push("short of the foot: the last drawn ends at \{l.1 + l.2}") }
    None => faults.push("none drawn")
  }
  faults
}

///|
test "a page's list of blocks made as they show, where its host sets its rows on its pixels: what shows and where it is drawn one layout, scrolled away and back, one put in over what shows" {
  let keys = @signals.signal(Array::makei(200, fn(i) { i }))
  let (t, s) = rows_window_tree(keys)
  t.set_rows_on_pixels(true)
  t.draw()
  let tree = view_tree().unwrap()
  assert_eq(rows_window_faults(t, 0.0, 0), [])
  // (scrolled far down: what shows, where it is drawn and where it is counted as being the same)
  for _ in 0..<6 {
    t.wheel_phase(100.0, 100.0, 400.0, 4)
    t.run_for(move_most_ms)
  }
  let far = s.at(tree)
  assert_true(far > 1000.0, msg="scrolled far down: \{far}")
  assert_eq(rows_window_faults(t, far, 0), [])
  // (and back to its top)
  for _ in 0..<8 {
    t.wheel_phase(100.0, 100.0, -400.0, 4)
    t.run_for(move_most_ms)
  }
  assert_eq(s.at(tree), 0.0)
  assert_eq(rows_window_faults(t, 0.0, 0), [])
  // (scrolled a part of a pixel down, one put in over all: what showed stays where it was drawn)
  t.wheel_phase(100.0, 100.0, 103.3, 4)
  t.run_for(move_most_ms)
  let was = rows_window_drawn(t)
  keys.set([-1, ..keys.get()])
  // (laid out once with it: nothing of it moves by itself)
  t.draw()
  let now = rows_window_drawn(t)
  let row10 = fn(a : Array[(Int, Double, Double)]) { a.search_by(fn(d) { d.0 == 10 }).map(fn(i) { a[i] }).unwrap() }
  // (where it is drawn summed down what holds it: the same sum but for its last bits, a billionth of a point)
  assert_true((row10(now).1 - row10(was).1).abs() <= 1.0e-9 && row10(now).2 == row10(was).2, msg="row 10 moved: \{Repr(row10(was))} to \{Repr(row10(now))}")
  assert_eq(rows_window_faults(t, s.at(tree), -1), [])
}

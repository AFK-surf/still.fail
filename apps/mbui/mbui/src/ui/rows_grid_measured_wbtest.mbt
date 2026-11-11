// A frame measured (Tester::contrast_faults: whose each instance is; Tester::hand_moves: everything lit) where the host
// sets a list's rows on its pixels (Ctx::rows_on_grid) is the frame a device draws: its rows as tall as whole pixels,
// on them, as in the frame before it. So the frame drawn of its looks alone before the measure parts from nothing
// (frame_watch.mbt), and what the hand lights finds nothing moved but what it moves.

///|
/// Row `i`'s ground: its own, near white (words on it read).
fn rows_grid_ink(i : Int) -> Int64 {
  0xF8F8F8FFL - i.to_int64() * 0x100L
}

///|
/// An old view's list 300 tall, 10.3 under the window's top, of 30 rows 20.3 high (each a box with an id, its ground
/// its own, its words in it), at 2 pixels a point, its host setting the rows on its pixels.
fn rows_grid_old() -> Tester {
  let t = Tester::new(
    fn(c) {
      c.box(w=Px(300.0), h=Px(10.3), fn() {  }) |> ignore
      c.box(w=Px(300.0), h=Px(300.0), fn() {
        c.list("rows", 30, 20.3, fn(i) {
          c.box(w=Fill(1.0), h=Px(20.3), id=c.id("row"), bg=rows_grid_ink(i), fn() {
            c.text("第 \{i} 行", size=12.0, line=16.0, wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
    platform=0,
    scale=2.0,
  )
  t.set_rows_on_pixels(true)
  t.draw()
  t
}

///|
/// A press of the window's tree, 10.3 under the window's top, holding a page's list of four rows 20.3 high (their
/// grounds rows_grid_ink's) as tall as they are, at 2 pixels a point, its host setting the rows on its pixels: the
/// press as tall as its rows' rooms are.
fn rows_grid_tree() -> Tester {
  let s = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0, scale=2.0)
  set_view_app(fn(root) {
    root.box(fn(gap) { gap.height(Is(Some(10.3))) |> ignore }) |> ignore
    root.box(fn(card) {
      card
      .width(Is(Some(300.0)))
      .on_press(fn() {  })
      .says(Is(Some(@view.said(Button, label="四行"))))
      |> ignore
      card.box(fn(col) {
        col
        .width(Is(Some(300.0)))
        .scrolls(s, fn(body) {
          for i in 0..<4 {
            body.box(fn(row) { row.height(Is(Some(20.3))).ground(Is(rows_grid_ink(i))) |> ignore }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.set_rows_on_pixels(true)
  t.draw()
  t
}

///|
/// Where each row is drawn (its ground's top), by its number, top to bottom.
fn rows_grid_drawn(t : Tester) -> Array[(Int, Double)] {
  let out = []
  for r in t.drawn_rects() {
    for i in 0..<30 {
      if r.4 == rows_grid_ink(i) {
        out.push((i, r.1))
      }
    }
  }
  out.sort_by(fn(a, b) { a.1.compare(b.1) })
  out
}

///|
/// Each row drawn where a list on 2 pixels a point sets it: the first one's top on a pixel from where it is laid out
/// (10.3 under the window's top: 10.5), each 20.5 under the one before (its room as tall as whole pixels); and some.
fn rows_grid_faults(t : Tester) -> Array[String] {
  let drawn = rows_grid_drawn(t)
  let faults = []
  for d in drawn {
    let want = 10.5 + 20.5 * d.0.to_double()
    // (where it is drawn summed down what holds it: the same sum but for its last bits, a billionth of a point)
    if (d.1 - want).abs() > 1.0e-9 {
      faults.push("row \{d.0} at \{d.1}, not \{want}")
    }
  }
  if drawn.length() < 4 {
    faults.push("\{drawn.length()} rows drawn")
  }
  faults
}

///|
test "an old view's list on the device's pixels: its contrast measured on the frame a device draws, rows on the pixels; the hand moves none of them" {
  let t = rows_grid_old()
  t.run_for(move_most_ms)
  assert_eq(rows_grid_faults(t), [])
  // (the frame it draws of its looks alone, nothing changed, measured: the same frame built whole as well, compared)
  assert_eq(t.contrast_faults(), [])
  assert_eq(rows_grid_faults(t), [])
  assert_eq(t.hand_moves(), [])
  assert_eq(rows_grid_faults(t), [])
}

///|
test "a page's list on the device's pixels: its contrast measured on the frame a device draws, rows on the pixels; what holds them as tall lit" {
  let t = rows_grid_tree()
  t.run_for(move_most_ms)
  assert_eq(rows_grid_faults(t), [])
  assert_eq(t.contrast_faults(), [])
  assert_eq(rows_grid_faults(t), [])
  assert_eq(t.hand_moves(), [])
}

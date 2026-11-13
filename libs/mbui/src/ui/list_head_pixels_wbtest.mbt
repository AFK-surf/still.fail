// A page's list with a head (View::scrolls_window's `head`) where its host sets its rows on its pixels
// (Tester::set_rows_on_pixels), at 2.75 pixels a point, its head 50.3, 0 and 37 tall: at rest at its top, wheeled down
// step by step, keys put in over its first at its top, a key come on its way at its foot (each frame of the way): every
// row's top on a pixel, each under the one before with no seam (its slot as tall as whole pixels), the head's place
// ending where the first row's top is.

///|
/// The pixels a point.
let head_px_scale : Double = 2.75

///|
/// The ground of row `k`, and of the head.
fn head_px_ink(k : Int) -> Int64 {
  0x30000000L + (k + 10).to_int64() * 0x100L + 0xFFL
}

///|
let head_px_head_ink : Int64 = 0x30FFFF00L

///|
/// How tall each row is: 20.3.
let head_px_tall : Double = 20.3

///|
/// A list 300 by 300 of `keys`, its head `head` tall, following its foot where `follows`, at 2.75 pixels a point on a
/// host that sets its rows on its pixels: the Tester, its keys.
fn head_px_case(keys : Array[Int], head : Double, follows? : Bool = false) -> (Tester, @signals.Signal[Array[Int]]) {
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0, scale=head_px_scale)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(
        @view.Scroll::list(),
        fn() { keys.get() },
        est=head_px_tall,
        follows=fn() { follows },
        head=fn(h) {
          h.box(fn(b) { b.height(Is(Some(head))).ground(Is(head_px_head_ink)) |> ignore }) |> ignore
        },
        fn(b, k) { b.height(Is(Some(head_px_tall))).ground(Is(head_px_ink(k))) |> ignore },
      )
      |> ignore
    })
    |> ignore
  })
  t.set_rows_on_pixels(true)
  t.draw()
  (t, keys)
}

///|
/// What is wrong of the rows `keys` as drawn now: each drawn row's top off a pixel, a row drawn under the one before it
/// anywhere but where that one's slot ends, the first row's top anywhere but where the head's place ends. `head` the
/// head's height; none where nothing is wrong.
fn head_px_faults(t : Tester, keys : Array[Int], head : Double, at : String) -> Array[String] {
  let out = []
  let rects = t.drawn_rects()
  let y_of = fn(ink : Int64) {
    match rects.search_by(fn(r) { r.4 == ink }) {
      Some(i) => Some(rects[i].1)
      None => None
    }
  }
  let on_pixel = fn(v : Double) { (v * head_px_scale - (v * head_px_scale).round()).abs() < 1.0e-6 }
  let slot = @view.rows_slot_on(head_px_tall, head_px_scale)
  let mut before : (Int, Double)? = None
  for k in keys {
    match y_of(head_px_ink(k)) {
      Some(y) => {
        if !on_pixel(y) {
          out.push("\{at}: row \{k}'s top \{y} off a pixel")
        }
        match before {
          Some((b, yb)) if (y - yb - slot).abs() > 1.0e-6 =>
            out.push("\{at}: row \{k} at \{y} under row \{b} at \{yb}, not \{yb + slot}")
          _ => ()
        }
        before = Some((k, y))
      }
      None => before = None
    }
  }
  if before is None && !keys.iter().any(fn(k) { y_of(head_px_ink(k)) is Some(_) }) {
    out.push("\{at}: no row drawn")
  }
  // (the head's place, as tall as it is on the grid, ending at the first row's top)
  match (y_of(head_px_head_ink), keys.get(0).bind(fn(k) { y_of(head_px_ink(k)) })) {
    (Some(hy), Some(fy)) => {
      let place = @view.rows_slot_on(head, head_px_scale)
      if (hy + place - fy).abs() > 1.0e-6 {
        out.push("\{at}: the head's place from \{hy} ends at \{hy + place}, the first row's top at \{fy}")
      }
    }
    _ => ()
  }
  out
}

///|
test "a page's list with a head, its rows on its host's pixels: at rest, wheeled, keys put in over its first at its top, a key come at its foot on its way, every row's top on a pixel, no seam, the head's place ending at the first row's top" {
  let faults = []
  for head in [50.3, 0.0, 37.0] {
    let ks = Array::makei(30, fn(i) { i })
    // (at rest at its top, then wheeled down step by step)
    let (t, _) = head_px_case(ks, head)
    faults.append(head_px_faults(t, ks, head, "head \{head} at its top"))
    for i in 0..<5 {
      t.wheel_phase(100.0, 100.0, 23.7, 4)
      t.run_for(move_most_ms)
      faults.append(head_px_faults(t, ks, head, "head \{head} wheeled \{i + 1}"))
    }
    // (keys put in over its first at its top)
    let (t, keys) = head_px_case(ks, head)
    let more = Array::makei(5, fn(i) { i - 5 })
    more.append(ks)
    keys.set(more)
    t.run_for(move_most_ms)
    faults.append(head_px_faults(t, more, head, "head \{head}, keys put in over its first"))
    // (a key come at its foot, each frame of its way)
    let (t, keys) = head_px_case(ks, head, follows=true)
    let came = ks.copy()
    came.push(30)
    t.each_frame(Some(fn() { faults.append(head_px_faults(t, came, head, "head \{head}, 30 coming at \{t.time()}")) }))
    keys.set(came)
    t.run_for(move_most_ms)
    t.each_frame(None)
    faults.append(head_px_faults(t, came, head, "head \{head}, 30 come"))
  }
  assert_eq(faults, [])
}

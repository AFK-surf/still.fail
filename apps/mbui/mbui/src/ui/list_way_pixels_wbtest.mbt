// A page's list where its host sets its rows on its pixels (Tester::set_rows_on_pixels, as list_rows_pixels_wbtest), a
// row come by data at its foot on its way (View::scrolls_window): at every frame of that way each row's top on a pixel,
// each one's slot as tall as whole pixels, one under the next, the last at the list's foot, what is above going up with it.

///|
/// The ground of row `k`.
fn way_px_ink(k : Int) -> Int64 {
  0x10000000L + k.to_int64() * 0x100L + 0xFFL
}

///|
/// How tall row `k` is: 20.3, but the one that comes (99), 33.3.
fn way_px_tall(k : Int) -> Double {
  if k == 99 {
    33.3
  } else {
    20.3
  }
}

///|
test "a page's list where its host sets its rows on its pixels, a row come at its foot on its way: at every frame each row's top on a pixel, its slot as tall as whole pixels, one under the next, the last at the foot" {
  let s = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(30, fn(i) { i }), same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0, scale=2.0)
  set_view_app(fn(root) {
    root.box(fn(gap) { gap.height(Is(Some(10.3))) |> ignore }) |> ignore
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(s, fn() { keys.get() }, est=20.3, follows=fn() { true }, fn(b, k) {
        b.height(Is(Some(way_px_tall(k)))).ground(Is(way_px_ink(k))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.set_rows_on_pixels(true)
  t.draw()
  let row = fn(k : Int) {
    match t.drawn_rects().search_by(fn(r) { r.4 == way_px_ink(k) }) {
      Some(i) => Some((t.drawn_rects()[i].1, t.drawn_rects()[i].3))
      None => None
    }
  }
  let on_pixel = fn(v : Double) { v * 2.0 == (v * 2.0).round() }
  let was = row(29)
  // (where the list's last row ends at its foot, as it opened: its slot as tall as whole pixels, 20.5)
  let foot = match was {
    Some((y, _)) => y + 20.5
    None => -1.0
  }
  let faults = []
  // (each frame drawn as it comes: 28 and 29 each on a pixel, 20.5 apart, each drawn as tall as said; the one coming
  // drawn whole as its slot opens over it, on a pixel under 29, its foot no lower than the list's last ended)
  t.each_frame(Some(fn() {
    match (row(28), row(29), row(99)) {
      (Some((y28, h28)), Some((y29, h29)), come) => {
        if !on_pixel(y28) || !on_pixel(y29) || h28 != 20.3 || h29 != 20.3 || y28 + 20.5 != y29 {
          faults.push("at \{t.time()}: 28 \{y28} \{h28}, 29 \{y29} \{h29}")
        }
        match come {
          Some((y, h)) =>
            if !on_pixel(y) || h != 33.3 || y != y29 + 20.5 || y > foot {
              faults.push("at \{t.time()}: 99 \{y} \{h} under 29 at \{y29 + 20.5}")
            }
          None => ()
        }
      }
      _ => faults.push("at \{t.time()}: 28 or 29 not drawn")
    }
  }))
  let more = Array::makei(30, fn(i) { i })
  more.push(99)
  keys.set(more)
  // (half way: 29 gone up as 99 opens)
  let way = @flex.come_way_ms(0.0, 0.0, 33.5)
  t.run_for(way / 2.0)
  let half = row(29)
  t.run_for(way)
  t.each_frame(None)
  assert_eq(faults, [])
  assert_true(half != was, msg="29 gone up as 99 came: \{Repr(was)} \{Repr(half)}")
  // (at rest: 99's slot its whole 33.5 at the foot)
  assert_eq(row(99), Some((foot - 33.5, 33.3)))
}

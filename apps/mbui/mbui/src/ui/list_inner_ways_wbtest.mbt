// A page's list on a host that sets its rows on its pixels (Tester::set_rows_on_pixels), what a block holds opening in
// the list's one way with a key come by data (view's list_inner_ways_test, its scenes one and six): run on run_for's way,
// so at 60 and 120 a second judged (MBUI_TEST_MOTION) frame by frame, its sizes, rows and gaps steady; at rest where they
// end.

///|
/// The ground of block `k`'s words.
fn iw_px_ink(k : Int) -> Int64 {
  0x20000000L + k.to_int64() * 0x100L + 0xFFL
}

///|
/// Where block `k`'s words are drawn down the window, if they are.
fn iw_px_y(t : Tester, k : Int) -> Double? {
  match t.drawn_rects().search_by(fn(r) { r.4 == iw_px_ink(k) }) {
    Some(i) => Some(t.drawn_rects()[i].1)
    None => None
  }
}

///|
/// A list 300 by 300 at 2 pixels a point, its rows on them, of `keys` following its foot, each block its words 40 tall
/// and what `inner` gives it: what opens under the words as `opens` says (300), or a gap over them (16). `from_end`.
fn iw_px_case(
  keys : @signals.Signal[Array[Int]],
  opens : (Int) -> @signals.Signal[Bool]?,
  gap : Bool,
  from_end : Bool,
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0, scale=2.0)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(@view.Scroll::list(), fn() { keys.get() }, est=40.0, follows=fn() { true }, from_end~, fn(b, k) {
        if gap {
          b.box(fn(g) { g.height(Is(Some(16.0))) |> ignore }) |> ignore
        }
        b.box(fn(w) { w.height(Is(Some(40.0))).ground(Is(iw_px_ink(k))) |> ignore }) |> ignore
        match opens(k) {
          Some(on) => b.show(fn() { on.get() }, fn(s) { s.height(Is(Some(300.0))) |> ignore })
          None => ()
        }
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
test "a page's list on a host's pixels, its last block opening 300 inside as a key comes under it: one way, steady frame by frame, at rest each where it ends" {
  let keys = @signals.signal(Array::makei(10, fn(i) { i }), same=fn(a, b) { a == b })
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = iw_px_case(keys, fn(k) { if k == 9 { Some(on) } else { None } }, false, false)
  @signals.start_batch()
  on.set(true)
  keys.set(Array::makei(11, fn(i) { i }))
  @signals.end_batch()
  t.run_for(move_most_ms + 100.0)
  // (at its foot: 10 last, 40 over the foot of 300; 9's words 300 over it)
  assert_eq((iw_px_y(t, 10), iw_px_y(t, 9)), (Some(260.0), Some(-80.0)))
}

///|
test "a page's list on a host's pixels said from_end holding nothing, its first key come, its block a gap over its words: opening from the data's moment, steady frame by frame, at its foot at rest" {
  let keys = @signals.signal([], same=fn(a, b) { a == b })
  let t = iw_px_case(keys, fn(_) { None }, true, true)
  keys.set([0])
  t.run_for(move_most_ms + 100.0)
  assert_eq(iw_px_y(t, 0), Some(260.0))
}

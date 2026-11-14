// A key coming by data whose page says how it comes (View::scrolls_window `comes_way`: a length and a curve) sets the
// list's one way on that curve, not a Move: what is over it at its foot goes up as far as the curve says at each
// moment, all of its rise at the length's end and none after (one's own words sent rising with their flight: the
// coordinator of the migration, 2026-11-14). Looked at in one jump and at 60, 120, 24 and 7 a second (rc_walk).

///|
/// A page's list 300 by 400 of rows 0 to 9 (40 each, row 9 a part of 20 under it, a show) following its foot; key 70
/// (60 high) comes by data, its way said
/// by `way` (None: a Move). Drawn once, at 0.
fn cw_case(
  way : (Double, (Double) -> Double)?,
) -> (@view.Tree, @signals.Signal[Array[Int]], @signals.Signal[Bool]) {
  let keys = @signals.signal(rc_ten_and([]), same=fn(a, b) { a == b })
  let part = @signals.signal(true, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        follows=fn() { true },
        comes_way=fn(k) { if k == 70 { way } else { None } },
        fn(b, k) {
          if k == 70 {
            b.height(Is(Some(60.0))).words(Is("行70")) |> ignore
          } else if k == 9 {
            b.box(fn(w) { w.height(Is(Some(40.0))).shrink(Is(0.0)).words(Is("行9")) |> ignore }) |> ignore
            b.show(fn() { part.get() }, fn(p) { p.height(Is(Some(20.0))).shrink(Is(0.0)).words(Is("部9")) |> ignore })
          } else {
            b.height(Is(Some(40.0))).words(Is("行\{k}")) |> ignore
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  (tree, keys, part)
}

///|
test "a key coming whose page says its way (a length and a curve) takes what is over it up on that curve, not a Move, at every rate" {
  let ms = 400.0
  let linear = fn(x : Double) { x }
  // (the key alone; and with row 9's part closing in the same change: all of it one way, the key's)
  for closes in [false, true] {
    for rate in rc_rates {
      let at = "\{if closes { "with a part closing" } else { "alone" }}, at \{rate} a second"
      let (t, keys, part) = cw_case(Some((ms, linear)))
      let looks = [rc_at, rc_at + ms / 2.0, rc_at + ms, rc_at + ms + 200.0]
      let cause = fn() {
        keys.set(rc_ten_and([70]))
        if closes {
          part.set(false)
        }
      }
      let ys = rc_walk(t, [(rc_at, cause)], looks, rate, fn() { rc_y(t, "行8") })
      let rise = ys[0] - ys[3]
      let wanted = if closes { 40.0 } else { 60.0 }
      assert_true((rise - wanted).abs() < 1.0, msg="\{at}: 行8 up \{rise}, \{wanted} wanted")
      let half = (ys[0] - ys[1]) / rise
      assert_true((half - 0.5).abs() < 0.05, msg="\{at}: half way through its length, \{half} of its rise")
      assert_true((ys[2] - ys[3]).abs() < 0.5, msg="\{at}: not at rest at its length's end")
      // (a Move, said by nothing: further at half its length than the curve)
      let (m, mkeys, mpart) = cw_case(None)
      let mcause = fn() {
        mkeys.set(rc_ten_and([70]))
        if closes {
          mpart.set(false)
        }
      }
      let ms_ = rc_walk(m, [(rc_at, mcause)], looks, rate, fn() { rc_y(m, "行8") })
      let mhalf = (ms_[0] - ms_[1]) / (ms_[0] - ms_[3])
      assert_true(mhalf > half + 0.1, msg="\{at}: a Move \{mhalf} of its rise half way, the curve \{half}")
    }
  }
}

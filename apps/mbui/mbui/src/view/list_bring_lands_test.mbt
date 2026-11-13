// A page's list made with a block asked to be brought an offset under its top (ListPlace::bring) or to its middle
// (ListPlace::centre), said as the list is made, as a chat opens where the core says it was left: the list made by a
// structure switched on in a change, whose making reads where it is laid out as it is made (View::laid_window_now, a
// layout inside that change's open batch, its blocks not made in it: as the chat's page's first making on 大屏 does),
// the rows over the block other heights than they are counted (`est`). The block lands where it was asked, to within a
// pixel, at rest, on a host's grid of 2, 2.75 and 3 pixels a point, in one jump and at 60, 120, 24 and 7 a second.

///|
/// How many blocks, which is brought, how tall each is counted, how tall those over it come out (alternately), and
/// how tall what shows of the list is.
let bl_count : Int = 60

///|
let bl_key : Int = 30

///|
let bl_est : Double = 90.0

///|
let bl_short : Double = 57.1

///|
let bl_long : Double = 131.3

///|
let bl_shows : Double = 800.0

///|
/// The list on grid `g`, block bl_key asked (`ask`) as the list is made, made by a structure switched on at rc_at whose
/// making reads where it is laid out; drawn once at 0 without it, walked at `rate` to rest; where block bl_key's top
/// is drawn then.
fn bl_landed(g : Double, ask : (@view.ListPlace[Int]) -> Unit, rate : Double) -> Double {
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(bl_shows))) |> ignore
      o.show(fn() { on.get() }, fn(v) {
        v.height(Is(Some(bl_shows))) |> ignore
        ask(place)
        v.box(fn(l) {
          l.height(Is(Some(bl_shows))) |> ignore
          l.scrolls_window(scroll, fn() { Array::makei(bl_count, fn(i) { i }) }, est=bl_est, place~, fn(b, k) {
            let h = if k < bl_key { if k % 2 == 0 { bl_short } else { bl_long } } else { bl_est }
            b.height(Is(Some(h))).words(Is("行\{k}")) |> ignore
          })
          |> ignore
        })
        |> ignore
        // (where it is laid out, read as it is made: a layout in this change, as the chat's page's first making asks)
        v.laid_window_now() |> ignore
      })
    })
    |> ignore
  })
  tree.set_rows_grid(g)
  tree.frame(390.0, 844.0) |> ignore
  rc_walk(tree, [(rc_at, fn() { on.set(true) })], [rc_at + 1000.0], rate, fn() { rc_y(tree, "行\{bl_key}") })[0]
}

///|
test "a page's list made in a change that lays it out as it is made, a block brought an offset under its top, rows over it other heights than counted: the block's top where it was asked, to a pixel, at rest, at grids 2, 2.75 and 3, at every rate" {
  for rate in rc_rates {
    for g in [2.0, 2.75, 3.0] {
      for px in [120.0, 240.0, 360.0, 480.0] {
        let offset = px / g
        let y = bl_landed(g, fn(p) { p.bring(bl_key, offset=-offset) }, rate)
        assert_true(
          (y - offset).abs() <= 1.0 / g + 0.000001,
          msg="at \{rate} a second, grid \{g}, \{px} px: its top at \{y}, asked \{offset}",
        )
      }
    }
  }
}

///|
test "a page's list made in a change that lays it out as it is made, a block brought to its middle, rows over it other heights than counted: the block's middle at the middle of what shows, to a pixel, at rest, at grid 2.75, at every rate" {
  for rate in rc_rates {
    let g = 2.75
    let y = bl_landed(g, fn(p) { p.centre(bl_key) }, rate)
    let middle = y + bl_est / 2.0
    assert_true(
      (middle - bl_shows / 2.0).abs() <= 1.0 / g + 0.000001,
      msg="at \{rate} a second: its middle at \{middle}, the middle of what shows \{bl_shows / 2.0}",
    )
  }
}

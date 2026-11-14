// A page's list asked to bring a block with what it holds of a go-to's (ListPlace::bring's `sought`, View::sought):
// low in a block taller than what shows, that piece's middle comes to the middle of what shows; high in it, the block's
// top where it is asked, as without it; not asked so, the block's top alone.

///|
/// How far down block 15 the node it marks sought lies, how tall what shows of the list is.
let ls_shows : Double = 600.0

///|
/// The list (30 blocks 60 tall, but block 15: 900 tall over a line 20 tall marked sought at `low`, 900 under its top, or
/// 100 under it) drawn, then asked `ask`, drawn again: where the line marked sought is drawn, its top.
fn ls_brought(low : Bool, ask : (@view.ListPlace[Int]) -> Unit) -> Double {
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(l) {
      l.width(Is(Some(300.0))).height(Is(Some(ls_shows))) |> ignore
      l.scrolls_window(scroll, fn() { Array::makei(30, fn(i) { i }) }, est=60.0, place~, fn(b, k) {
        if k == 15 {
          b.box(fn(o) { o.height(Is(Some(if low { 900.0 } else { 100.0 }))).words(Is("长")) |> ignore }) |> ignore
          b.box(fn(o) {
            o.height(Is(Some(20.0))).words(Is("那里")).sought(fn() { Some(fn(w, h) { Some((0.0, 0.0, w, h)) }) })
            |> ignore
          })
          |> ignore
          if !low {
            b.box(fn(o) { o.height(Is(Some(800.0))) |> ignore }) |> ignore
          }
        } else {
          b.height(Is(Some(60.0))).words(Is("行\{k}")) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(300.0, ls_shows) |> ignore
  ask(place)
  tree.frame(300.0, ls_shows, now=16.0) |> ignore
  tree.frame(300.0, ls_shows, now=32.0) |> ignore
  rc_y(tree, "那里")
}

///|
test "a page's list asked to bring a block with what it holds of a go-to's, that low in it: its middle at the middle of what shows; high in it, the block's top as asked; not asked so, the block's top alone" {
  let low = ls_brought(true, fn(p) { p.bring(15, sought=true) })
  assert_true((low + 10.0 - ls_shows / 2.0).abs() < 1.0, msg="low: its top at \{low}")
  let high = ls_brought(false, fn(p) { p.bring(15, sought=true) })
  assert_true((high - 100.0).abs() < 1.0, msg="high: its top at \{high}")
  let plain = ls_brought(true, fn(p) { p.bring(15) })
  assert_true(plain == rc_none || plain >= ls_shows, msg="not asked: its top at \{plain}")
}

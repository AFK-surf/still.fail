// A list laid out first with no room to show anything in (a page pushed on, laid out before it is where it goes, its
// foot's room more than its height), then where it shows: its rows laid out then as if it had been there from the
// first, what it was asked to put put.

///|
fn late_case(put_first : (Int, Double)?) -> (@view.Tree, Map[Int, @view.View], @signals.Signal[Array[Int]], @signals.Signal[Double]) {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let live : Map[Int, @view.View] = Map([])
  let shown : @signals.Signal[Array[Int]] = @signals.signal([], same=fn(a, b) { a == b })
  let put : @signals.Signal[(Int, Double)?] = @signals.signal(put_first)
  let tall = @signals.signal(0.0, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(By(fn() { Some(tall.get()) })) |> ignore
      o.scrolls_anchored(scroll, fn() { keys.get() }, est=80.0, ahead=0.0, shown~, put~, foot_room=fn() { 44.0 }, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  (tree, live, shown, tall)
}

///|
test "scrolls_anchored: laid out first where it has no room, then where it shows: its last rows in sight" {
  let (tree, live, shown, tall) = late_case(None)
  tall.set(144.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(shown.get(), [97, 98, 99])
  assert_true(live.length() >= 3)
}

///|
test "scrolls_anchored: put while it has no room yet, put once it shows" {
  let (tree, _, shown, tall) = late_case(Some((10, 0.0)))
  tall.set(144.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(shown.get(), [10, 11, 12])
}

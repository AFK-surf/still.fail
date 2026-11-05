// A list laid out first with no room to show anything in (a page pushed on, laid out before it is where it goes, its
// foot's room more than its height), then where it shows: its rows laid out then as if it had been there from the
// first, what it was asked to put put.

///|
fn late_case(put_first : (Int, Double)?, outer? : Bool = false) -> (@view.Tree, Map[Int, @view.View], @signals.Signal[Array[Int]], @signals.Signal[Double]) {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let live : Map[Int, @view.View] = Map([])
  let shown : @signals.Signal[Array[Int]] = @signals.signal([], same=fn(a, b) { a == b })
  let put : @signals.Signal[(Int, Double)?] = @signals.signal(put_first)
  let tall = @signals.signal(0.0, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    let list = fn(o : @view.View) {
      o.scrolls_anchored(scroll, fn() { keys.get() }, est=80.0, ahead=0.0, shown~, put~, foot_room=fn() { 44.0 }, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    }
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(By(fn() { Some(tall.get()) })) |> ignore
      // (its own room the same, the box it is in given its height: its room comes from where it is)
      if outer {
        o.box(fn(i) { i.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore; list(i) }) |> ignore
      } else {
        list(o)
      }
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

///|
test "scrolls_anchored: its room given by the box it is in, nothing it reads changed: laid out again where it shows" {
  let (tree, _, shown, tall) = late_case(Some((10, 0.0)), outer=true)
  tall.set(144.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(shown.get(), [10, 11, 12])
}

///|
test "scrolls_anchored: the room under its rows given by what holds it as it measures it, a composer measured first: in sight as that leaves it, in the same layout" {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let shown : @signals.Signal[Array[Int]] = @signals.signal([], same=fn(a, b) { a == b })
  let composer_h = @signals.signal(100.0, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page
      .width(Is(Some(300.0)))
      .height(Is(Some(300.0)))
      .layout_box(Is(()), fn(l, _) {
        let list = l.child("list", fn(o) {
          o.scrolls_anchored(scroll, fn() { keys.get() }, est=40.0, ahead=0.0, shown~, fn(b, _) {
            b.height(Is(Some(40.0))) |> ignore
          })
          |> ignore
        })
        let composer = l.child("composer", fn(c) { c.height(By(fn() { Some(composer_h.get()) })) |> ignore })
        let (_, ch) = l.measure(composer, l.width)
        l.measure(list, l.width, height=l.height, foot=(ch, ch)) |> ignore
        l.place(list, 0.0, 0.0)
        l.place(composer, 0.0, l.height - ch)
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let tall = shown.get()
  let computes = tree.work().computes
  composer_h.set(20.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq((tall, shown.get()), ([95, 96, 97, 98, 99], [93, 94, 95, 96, 97, 98, 99]))
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  tree.dispose()
}

///|
test "scrolls_anchored: a part of a row asked to the window's middle: put there where it lies further down than asked, in the layout that brings it in; left where it lies otherwise" {
  let case = fn(part : (Double, Double)) {
    let scroll = @view.Scroll::list()
    let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
    let shown : @signals.Signal[Array[Int]] = @signals.signal([], same=fn(a, b) { a == b })
    let passage : @signals.Signal[(Int, String, Double)?] = @signals.signal(None)
    let tree = @view.Tree::new(fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
        o.scrolls_anchored(scroll, fn() { keys.get() }, est=300.0, ahead=0.0, shown~, put_passage=passage, fn(b, _) {
          b.layout_box(Is(()), sized=true, fn(l, _) {
            l.report_span("passage", part)
            l.size_to(300.0)
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    tree.frame(390.0, 844.0, now=0.0) |> ignore
    passage.set(Some((50, "passage", 0.8)))
    tree.frame(390.0, 844.0, now=16.0) |> ignore
    let at = shown.get()
    tree.dispose()
    at
  }
  // (its middle at 270 of 300, past 240: the row's top at 150 − 270, the next row in sight under it)
  assert_eq(case((250.0, 290.0)), [50, 51])
  // (its middle at 70: the row at the window's top, left there)
  assert_eq(case((60.0, 80.0)), [50])
}

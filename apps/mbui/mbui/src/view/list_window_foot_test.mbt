// A column from its end holding fewer blocks than fill it (View::scrolls_window's `from_end`: a chat's, short), at its
// foot: a block new to it come at its end while it follows takes the room over them, what was there glided up from
// where it was drawn, never there at once; the column itself laid out shorter meanwhile (the window, a keyboard) is no
// block come, nothing glided for it.

///|
priv struct FootCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  live : Map[Int, @view.View]
  /// how tall the column is
  tall : @signals.Signal[Double]
}

///|
fn foot_case(est? : Double = 40.0) -> FootCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal([0], same=fn(a, b) { a == b })
  let live : Map[Int, @view.View] = Map([])
  let tall = @signals.signal(200.0, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(By(fn() { Some(tall.get()) })) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est~, from_end=true, fresh=fn(_) { true }, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  { tree, scroll, keys, live, tall }
}

///|
fn FootCase::top(self : FootCase, k : Int) -> Double {
  let (_, y, _, _) = self.live[k].rect()
  y
}

///|
fn FootCase::frames(self : FootCase, now : Double) -> Unit {
  self.tree.frame(390.0, 844.0, now~) |> ignore
}

///|
test "scrolls_window from its end, short: a block come at its end, what was at its foot glided up from where it was" {
  let k = foot_case()
  // (at 1000 as the block comes: from then)
  k.frames(1000.0)
  assert_eq(k.top(0), 160.0)
  k.keys.set([0, 1])
  k.frames(1000.0)
  // (where it was as the block comes, not where it goes)
  assert_eq(k.top(0), 160.0)
  k.frames(1100.0)
  let between = k.top(0)
  assert_true(between < 160.0 && between > 120.0)
  k.frames(5000.0)
  assert_eq((k.top(0), k.top(1)), (120.0, 160.0))
}

///|
test "scrolls_window from its end, short: an arriving block smaller than estimated does not push the old row down" {
  let k = foot_case(est=90.0)
  k.frames(1000.0)
  assert_eq(k.top(0), 160.0)
  k.keys.set([0, 1])
  k.frames(1000.0)
  assert_eq(k.top(0), 160.0)
  k.frames(1100.0)
  assert_true(k.top(0) < 160.0 && k.top(0) > 120.0)
  k.frames(5000.0)
  assert_eq((k.top(0), k.top(1)), (120.0, 160.0))
}

///|
test "scrolls_window from its end, short: the column laid out shorter as what came glides up, nothing more glided for it" {
  let k = foot_case()
  k.frames(1000.0)
  k.keys.set([0, 1])
  k.frames(1000.0)
  k.frames(1040.0)
  assert_true(k.scroll.glides_till() is Some(_))
  let was = k.scroll.at(k.tree)
  k.tall.set(180.0)
  k.frames(1040.0)
  // (set out from under where it was no further: the column's own height no block come)
  assert_true(k.scroll.at(k.tree) >= was - 0.5)
  k.frames(5000.0)
  assert_eq((k.top(0), k.top(1)), (100.0, 140.0))
}

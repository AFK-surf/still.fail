// A column that holds its blocks only while they show, from its end (View::scrolls_window's `from_end`: a chat's): 100
// tall, blocks of 40 each; at its foot where they are fewer than fill it, shown at its end, kept there as blocks come
// while it is there, no longer once scrolled from it.

///|
priv struct EndCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  live : Map[Int, @view.View]
  follows : @signals.Signal[Bool]
  /// how tall the last block is: its words coming in
  last_h : @signals.Signal[Double]
}

///|
fn end_case(n : Int) -> EndCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { a == b })
  let live : Map[Int, @view.View] = Map([])
  let follows = @signals.signal(true, same=fn(a, b) { a == b })
  let last_h = @signals.signal(40.0, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=80.0, from_end=true, follows~, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(By(fn() { Some(if k == n - 1 { last_h.get() } else { 40.0 }) })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys, live, follows, last_h }
}

///|
fn EndCase::shown(self : EndCase) -> Array[Int] {
  let all = self.live.keys().collect()
  all.sort()
  all
}

///|
test "scrolls_window from its end: fewer blocks than fill it at its foot" {
  let k = end_case(2)
  let (_, y0, _, _) = k.live[0].rect()
  let (_, y1, _, _) = k.live[1].rect()
  assert_eq((y0, y1), (20.0, 60.0))
}

///|
test "scrolls_window from its end: shown at its end; a block come at its end while there, at the new end" {
  let k = end_case(10)
  // (the blocks out of sight over it as tall as they are counted, est: how far it can go so)
  let most = k.scroll.most()
  assert_eq((k.scroll.at(k.tree), k.shown().contains(9), k.follows.get()), (most, true, true))
  k.keys.set(Array::makei(11, fn(i) { i }))
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y10, _, _) = k.live[10].rect()
  assert_eq((k.scroll.at(k.tree), k.scroll.most(), y10), (most + 40.0, most + 40.0, 60.0))
}

///|
test "scrolls_window from its end: scrolled from its end, a block come stays out of sight under it; back at its end, followed again" {
  let k = end_case(10)
  k.tree.wheel_at(150.0, 50.0, 0.0, -100.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let at = k.scroll.at(k.tree)
  let most = k.scroll.most()
  assert_eq((at < most, k.follows.get()), (true, false))
  k.keys.set(Array::makei(11, fn(i) { i }))
  k.tree.frame(390.0, 844.0) |> ignore
  // (the block come out of sight under it, counted as est, 80)
  assert_eq((k.scroll.at(k.tree), k.scroll.most()), (at, most + 80.0))
  // (sent back to its end: followed from there)
  k.scroll.glide_to(k.scroll.most(), glide=false)
  k.tree.frame(390.0, 844.0) |> ignore
  assert_true(k.follows.get())
}

///|
test "scrolls_window from its end: its last block growing as its words come, followed while at its end, not once scrolled from it" {
  let k = end_case(10)
  let most = k.scroll.most()
  k.last_h.set(100.0)
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y9, _, h9) = k.live[9].rect()
  assert_eq((k.scroll.at(k.tree), k.scroll.most(), y9 + h9, k.follows.get()), (most + 60.0, most + 60.0, 100.0, true))
  k.tree.wheel_at(150.0, 50.0, 0.0, -100.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let at = k.scroll.at(k.tree)
  k.last_h.set(160.0)
  k.tree.frame(390.0, 844.0) |> ignore
  assert_eq((k.scroll.at(k.tree), k.follows.get()), (at, false))
}

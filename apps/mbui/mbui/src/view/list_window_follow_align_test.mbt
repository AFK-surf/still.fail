// Following the end and aligning short contents to the foot are independent choices.

///|
priv struct FollowAlignCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  follows : @signals.Signal[Bool]
  height : @signals.Signal[Double]
  first_h : @signals.Signal[Double]
  live : Map[Int, @view.View]
}

///|
fn follow_align_case(n : Int, height? : Double = 100.0) -> FollowAlignCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { a == b })
  let follows = @signals.signal(true, same=fn(a, b) { a == b })
  let height = @signals.signal(height, same=fn(a, b) { a == b })
  let first_h = @signals.signal(40.0, same=fn(a, b) { a == b })
  let live : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(Is(Some(300.0))).height(By(fn() { Some(height.get()) })) |> ignore
      list.scrolls_window(scroll, fn() { keys.get() }, est=40.0, from_end=true, align_end=false, follows~, fn(row, k) {
        live[k] = row
        row.owns(fn() { live.remove(k) }) |> ignore
        row.height(By(fn() { Some(if k == 0 { first_h.get() } else { 40.0 }) })) |> ignore
      }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  { tree, scroll, keys, follows, height, first_h, live }
}

///|
fn FollowAlignCase::top(self : FollowAlignCase, key : Int) -> Double {
  self.live[key].rect().1
}

///|
test "an empty following list fills from the top, then follows the end as it overflows" {
  let c = follow_align_case(0)
  assert_true(c.follows.get())
  c.keys.set([0, 1])
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  assert_eq((c.top(0), c.top(1), c.follows.get()), (0.0, 40.0, true))
  c.keys.set([0, 1, 2])
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_eq((c.top(0), c.top(2), c.follows.get()), (-20.0, 60.0, true))
  c.tree.dispose()
  assert_eq(c.live.length(), 0)
}

///|
test "a top-aligned short list follows a row growing beyond and shrinking within the viewport" {
  let c = follow_align_case(2)
  assert_eq((c.top(0), c.top(1)), (0.0, 40.0))
  c.first_h.set(70.0)
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  assert_eq((c.top(0), c.top(1), c.follows.get()), (-10.0, 60.0, true))
  c.first_h.set(30.0)
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_eq((c.top(0), c.top(1), c.follows.get()), (0.0, 30.0, true))
  c.tree.dispose()
}

///|
test "a top-aligned following list keeps its place after the hand leaves the end and resumes at the end" {
  let c = follow_align_case(10)
  assert_eq((c.top(9), c.follows.get()), (60.0, true))
  c.tree.wheel_at(150.0, 50.0, 0.0, -100.0, 0, 10.0) |> ignore
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  let before = c.top(7)
  assert_false(c.follows.get())
  c.keys.set(Array::makei(11, fn(i) { i }))
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_eq(c.top(7), before)
  assert_false(c.follows.get())
  c.scroll.glide_to(c.scroll.most(), glide=false)
  c.tree.frame(390.0, 844.0, now=30.0) |> ignore
  assert_eq((c.top(10), c.follows.get()), (60.0, true))
  c.tree.dispose()
}

///|
test "end-following with top alignment adapts when the viewport fills and is constrained" {
  let c = follow_align_case(2, height=80.0)
  assert_eq((c.top(0), c.top(1)), (0.0, 40.0))
  c.height.set(100.0)
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  assert_eq((c.top(0), c.top(1)), (0.0, 40.0))
  c.height.set(60.0)
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_eq((c.top(0), c.top(1), c.follows.get()), (-20.0, 20.0, true))
  c.tree.dispose()
}

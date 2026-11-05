// A column that holds its blocks only while they show (View::scrolls_window): 100 tall, blocks of 40 each (as their
// heights say, each its own), counted as 80 before they are first laid out; which are made, and where the column is.

///|
priv struct WindowCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  heights : Map[Int, @signals.Signal[Double]]
  made : Array[Int]
  live : Map[Int, @view.View]
}

///|
/// `put`: the column put that far down before it is first laid out (a list made again where it was left).
fn window_case(put? : Double) -> WindowCase {
  let scroll = @view.Scroll::list()
  match put {
    Some(x) => scroll.put(x)
    None => ()
  }
  let keys = @signals.signal(Array::makei(10, fn(i) { i }), same=fn(a, b) { a == b })
  let heights : Map[Int, @signals.Signal[Double]] = Map([])
  let made = []
  let live : Map[Int, @view.View] = Map([])
  let tall = fn(k : Int) {
    match heights.get(k) {
      Some(h) => h
      None => {
        let h = @signals.signal(40.0, same=fn(a, b) { a == b })
        heights[k] = h
        h
      }
    }
  }
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=80.0, fn(b, k) {
        made.push(k)
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        let h = tall(k)
        b.height(By(fn() { Some(h.get()) })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  for k in 0..<12 {
    tall(k) |> ignore
  }
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys, heights, made, live }
}

///|
/// The blocks made now, in order.
fn WindowCase::shown(self : WindowCase) -> Array[Int] {
  let all = self.live.keys().collect()
  all.sort()
  all
}

///|
test "scrolls_window: what does not show is not made; scrolled, what comes into it made as it does, what leaves let go" {
  let k = window_case()
  let first = (k.shown(), k.made.copy())
  k.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  // (at 100: block 2 from 80, 3 from 120, 4 from 160; 3 counted 80 till laid out, then 4 shows as well)
  assert_eq((first, k.scroll.at(k.tree), k.shown()), (([0, 1, 2], [0, 1, 2]), 100.0, [2, 3, 4]))
}

///|
test "scrolls_window: the column put down it before it is first laid out (made again where it was left): drawn there from its first frame, what shows of it from its top" {
  let k = window_case(put=100.0)
  let tops = k.shown().map(fn(i) { k.live[i].rect().1 })
  // (100 down, block 1 from 80 as it is counted: what shows covered from the column's top, not drawn as at its top)
  assert_eq(k.scroll.at(k.tree), 100.0)
  assert_true(tops.length() > 0 && tops[0] <= 0.0 && tops[0] > -40.0, msg="\{k.shown()} \{tops}")
}

///|
test "scrolls_window: a block come over what shows moves the column with it: what shows stays where it was" {
  let k = window_case()
  k.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y2, _, _) = k.live[2].rect()
  // (one more at the top, not shown: as tall as it is counted, 80, over all of them)
  let more = [-1]
  more.append(Array::makei(10, fn(i) { i }))
  k.keys.set(more)
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y2_now, _, _) = k.live[2].rect()
  assert_eq((k.scroll.at(k.tree), k.shown(), y2_now), (180.0, [2, 3, 4], y2))
}

///|
test "scrolls_window: a block laid out taller than it was counted as it comes back into sight over what shows: what showed moved as far as the hand moved it, the block grown over it" {
  let k = window_case()
  k.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y2_was, _, _) = k.live[2].rect()
  // (block 1, out of sight, comes to be 70 tall; scrolled back up by 30, it shows again, laid out so: block 2, in
  // sight before, 30 further down, as the wheel moved it, and the column on by the 30 block 1 grew over it)
  k.heights[1].set(70.0)
  k.tree.wheel_at(150.0, 50.0, 0.0, -30.0, 0, 20.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y1, _, h1) = k.live[1].rect()
  let (_, y2, _, _) = k.live[2].rect()
  assert_eq((y2_was, k.scroll.at(k.tree), k.shown(), y1, h1, y2), (-20.0, 100.0, [1, 2, 3, 4], -60.0, 70.0, 10.0))
}

///|
test "scrolls_window: all words measured anew: what shows kept and laid out again, what does not counted as before it was laid out, what shows staying where it was" {
  let k = window_case()
  k.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y2, _, _) = k.live[2].rect()
  // (blocks 0 and 1, out of sight, forgotten: 80 each as counted, 160 over block 2 where 80 was)
  k.tree.words_again()
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y2_now, _, _) = k.live[2].rect()
  assert_eq((k.scroll.at(k.tree), k.shown(), y2_now), (180.0, [2, 3, 4], y2))
}

///|
test "page list queries and scroll_to address the shown page while an earlier page keeps its list" {
  let next = @signals.signal(false)
  let home = @view.Scroll::list()
  let chat = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    for (scroll, second) in [(home, false), (chat, true)] {
      root.box(fn(page) {
        page.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(100.0)))
        .laid_nowhere(By(fn() { next.get() != second })) |> ignore
        page.scrolls_window(scroll, fn() { Array::makei(10, fn(i) { i }) }, est=40.0, fn(row, _) {
          row.height(Is(Some(40.0))) |> ignore
        }) |> ignore
      }) |> ignore
    }
  })
  tree.frame(300.0, 100.0) |> ignore
  assert_true(tree.list_to_row(2))
  tree.frame(300.0, 100.0) |> ignore
  assert_eq(home.at(tree), 80.0)
  next.set(true)
  tree.frame(300.0, 100.0) |> ignore
  assert_true(tree.list_to_row(4))
  tree.frame(300.0, 100.0) |> ignore
  assert_eq((home.at(tree), chat.at(tree)), (80.0, 160.0))
  assert_eq(tree.list_rows(), Some((4, 6)))
  assert_eq(tree.list_offset(), Some(0.0))
  assert_eq(tree.list_row(4), Some((0.0, 0.0, 300.0, 40.0)))
  assert_eq(tree.list_at_end(), Some(false))
  assert_true(tree.list_to_row(9))
  tree.frame(300.0, 100.0) |> ignore
  assert_eq(tree.list_at_end(), Some(true))
  next.set(false)
  tree.frame(300.0, 100.0) |> ignore
  assert_eq(tree.list_rows(), Some((2, 4)))
  assert_eq(tree.list_at_end(), Some(false))
}

///|
test "scrolls_window: its keys changed while it is laid out nowhere (a page under another): as it shows again, laid out as they are then" {
  let away = @signals.signal(false, same=fn(a, b) { a == b })
  let keys = @signals.signal(Array::makei(5, fn(i) { i }), same=fn(a, b) { a == b })
  let live : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(300.0))).height(Is(Some(100.0))).laid_nowhere(By(fn() { away.get() })) |> ignore
      page.scrolls_window(@view.Scroll::list(), fn() { keys.get() }, est=40.0, fn(row, k) {
        live[k] = row
        row.owns(fn() { live.remove(k) }) |> ignore
        row.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(300.0, 100.0) |> ignore
  let before = live.keys().collect()
  before.sort()
  away.set(true)
  tree.frame(300.0, 100.0) |> ignore
  // (one more after the first, while another page covers it)
  keys.set([0, 9, 1, 2, 3, 4])
  tree.frame(300.0, 100.0) |> ignore
  away.set(false)
  tree.frame(300.0, 100.0) |> ignore
  let shown = live.keys().collect()
  shown.sort()
  let tops = [0, 9, 1].map(fn(k) { live.get(k).map(fn(r) { r.rect().1 }) })
  assert_eq((before, shown, tops), ([0, 1, 2], [0, 1, 9], [Some(0.0), Some(40.0), Some(80.0)]))
}

///|
test "scrolls_window: what holds its blocks laid out as tall as they reach in the frame that lays them out, as their count changes (whether it scrolls, whether they end above its foot: the corner rule's)" {
  let keys = @signals.signal(Array::makei(10, fn(i) { i }), same=fn(a, b) { a == b })
  let column : Ref[@view.NodeId?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      column.val = Some(o.id())
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(@view.Scroll::list(), fn() { keys.get() }, est=80.0, fn(b, _) {
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let id = column.val.unwrap()
  let seen = []
  tree.frame(390.0, 844.0) |> ignore
  seen.push((tree.scrolls_now(id), tree.scroll_short(id)))
  // (two of 40: 80 of its 100, above its foot)
  keys.set([0, 1])
  tree.frame(390.0, 844.0) |> ignore
  seen.push((tree.scrolls_now(id), tree.scroll_short(id)))
  keys.set(Array::makei(10, fn(i) { i }))
  tree.frame(390.0, 844.0) |> ignore
  seen.push((tree.scrolls_now(id), tree.scroll_short(id)))
  assert_eq(seen, [(true, false), (false, true), (true, false)])
  assert_true(!tree.told_since(), msg="nothing owed")
}

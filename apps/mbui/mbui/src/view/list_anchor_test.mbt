// A list laid out from its anchor (View::scrolls_anchored), from its end: 100 tall, rows of 40 each (as their heights
// say, each its own); what is made, where it is, and that what a frame does is the same for 30 rows and for 3000.

///|
priv struct AnchoredCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  heights : Map[Int, @signals.Signal[Double]]
  live : Map[Int, @view.View]
  follows : @signals.Signal[Bool]
  shown : @signals.Signal[Array[Int]]
}

///|
fn anchored_case(n : Int, ahead? : Double = 0.0, from_end? : Bool = true, kept? : () -> Array[Int] = fn() { [] }) -> AnchoredCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let heights : Map[Int, @signals.Signal[Double]] = Map([])
  let live : Map[Int, @view.View] = Map([])
  let follows = @signals.signal(true, same=fn(a, b) { a == b })
  let shown : @signals.Signal[Array[Int]] = @signals.signal([], same=fn(a, b) { a == b })
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
      o.scrolls_anchored(scroll, fn() { keys.get() }, est=80.0, ahead~, from_end~, follows~, shown~, kept_keys=kept, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        let h = tall(k)
        b.height(By(fn() { Some(h.get()) })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  { tree, scroll, keys, heights, live, follows, shown }
}

///|
test "a kept tall row outside the prefetch brings the requested part into sight" {
  let c = anchored_case(100, kept=fn() { [0] })
  c.heights[0].set(200.0)
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  c.tree.show_in_sight(c.live[0].id(), within=fn() { Some((180.0, 190.0)) })
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_eq(c.top(0), Some(-180.0), msg="the requested part starts at the viewport's top")
}

///|
fn AnchoredCase::made(self : AnchoredCase) -> Array[Int] {
  let all = self.live.keys().collect()
  all.sort()
  all
}

///|
/// Where row `k` is drawn in the window, its top (none: not made).
fn AnchoredCase::top(self : AnchoredCase, k : Int) -> Double? {
  self.live.get(k).map(fn(v) { v.rect().1 })
}

///|
test "scrolls_anchored: shown at its end, the rows that fill the window made, none other" {
  let c = anchored_case(3000)
  assert_eq(c.made(), [2997, 2998, 2999])
  assert_eq(c.shown.get(), [2997, 2998, 2999])
  assert_eq(c.top(2999), Some(60.0))
  assert_eq(c.top(2997), Some(-20.0))
  assert_true(c.follows.get())
}

///|
test "scrolls_anchored: fewer than fill it, at its foot" {
  let c = anchored_case(2)
  assert_eq(c.made(), [0, 1])
  assert_eq((c.top(0), c.top(1)), (Some(20.0), Some(60.0)))
}

///|
test "scrolls_anchored: scrolled toward its start by the wheel: the rows over come in, it follows its end no more; back down, at its end again" {
  let c = anchored_case(3000)
  c.tree.wheel_at(150.0, 50.0, 0.0, -100.0, 0, 10.0) |> ignore
  c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
  assert_false(c.follows.get())
  assert_eq(c.top(2997), Some(80.0))
  assert_eq(c.top(2995), Some(0.0))
  assert_true(!c.live.contains(2999))
  c.tree.wheel_at(150.0, 50.0, 0.0, 400.0, 0, 2000.0) |> ignore
  c.tree.frame(390.0, 844.0, now=3000.0) |> ignore
  assert_eq(c.top(2999), Some(60.0))
  assert_true(c.follows.get())
}

///|
test "scrolls_anchored: history come over what is read moves nothing in sight" {
  let c = anchored_case(100)
  c.tree.wheel_at(150.0, 50.0, 0.0, -100.0, 0, 10.0) |> ignore
  c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
  let before = (c.top(97), c.top(96))
  c.keys.set(Array::makei(50, fn(i) { -50 + i }) + Array::makei(100, fn(i) { i }))
  c.tree.frame(390.0, 844.0, now=1100.0) |> ignore
  assert_eq((c.top(97), c.top(96)), before)
}

///|
test "scrolls_anchored: a row come at its end while it is there is at its end" {
  let c = anchored_case(100)
  c.keys.set(Array::makei(101, fn(i) { i }))
  c.tree.frame(390.0, 844.0, now=100.0) |> ignore
  assert_eq(c.top(100), Some(60.0))
  assert_true(!c.live.contains(97))
}

///|
test "scrolls_anchored: a row in sight laid out taller: what is under the anchor's foot stays, the rows over it go up" {
  let c = anchored_case(100)
  c.heights[98].set(60.0)
  c.tree.frame(390.0, 844.0, now=100.0) |> ignore
  assert_eq((c.top(99), c.top(98)), (Some(60.0), Some(0.0)))
}

///|
test "scrolls_anchored: what a frame does is the same with 30 rows and with 3000, scrolled the same" {
  let work = fn(n : Int) {
    let c = anchored_case(n, ahead=40.0)
    let before = c.tree.work.made + c.tree.work.measured + c.tree.work.bound + c.tree.work.visited
    c.tree.wheel_at(150.0, 50.0, 0.0, -60.0, 0, 10.0) |> ignore
    c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
    c.tree.wheel_at(150.0, 50.0, 0.0, -60.0, 0, 1100.0) |> ignore
    c.tree.frame(390.0, 844.0, now=2000.0) |> ignore
    c.tree.work.made + c.tree.work.measured + c.tree.work.bound + c.tree.work.visited - before
  }
  assert_eq(work(30), work(3000))
}


///|
test "scrolls_anchored from its start: the rows that fill the window from the first; fewer, at its top; scrolled down by the wheel, the next come in" {
  let c = anchored_case(3000, from_end=false)
  assert_eq(c.made(), [0, 1, 2])
  assert_eq((c.top(0), c.top(2)), (Some(0.0), Some(80.0)))
  let short = anchored_case(2, from_end=false)
  assert_eq((short.top(0), short.top(1)), (Some(0.0), Some(40.0)))
  c.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 10.0) |> ignore
  c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
  assert_eq((c.top(3), c.top(4)), (Some(20.0), Some(60.0)))
  assert_true(!c.live.contains(0))
}

///|
test "scrolls_anchored: what it says of itself after a wheel and a row come is the same whichever frames came between" {
  let run = fn(step : Double) {
    let c = anchored_case(100)
    c.tree.wheel_at(150.0, 50.0, 0.0, -100.0, 0, 10.0) |> ignore
    c.keys.set(Array::makei(101, fn(i) { i }))
    // (frames every `step` on the way, or none: straight to the moment looked at)
    if step > 0.0 {
      let mut t = 10.0 + step
      while t < 1000.0 {
        c.tree.frame(390.0, 844.0, now=t) |> ignore
        t = t + step
      }
    }
    c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
    (c.follows.get(), c.shown.get(), c.top(97), c.top(96), c.scroll.at(c.tree))
  }
  assert_eq(run(0.0), run(16.0))
}

///|
test "scrolls_anchored: where the hand has it put where it is counted to be as the hand comes to it; to its start by the wheel, its first row at its top and it there as counted" {
  let c = anchored_case(100)
  // (laid out at its end, its rows counted 40 each where 80 was said before they were measured)
  assert_eq(c.scroll.at(c.tree), 3900.0)
  c.tree.wheel_at(150.0, 50.0, 0.0, -60.0, 0, 10.0) |> ignore
  c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
  assert_eq(c.scroll.at(c.tree), 3840.0)
  assert_eq(c.top(98), Some(80.0))
  c.tree.wheel_at(150.0, 50.0, 0.0, -100000.0, 0, 1100.0) |> ignore
  c.tree.frame(390.0, 844.0, now=3000.0) |> ignore
  assert_eq(c.top(0), Some(0.0))
  assert_eq(c.scroll.at(c.tree), 0.0)
}

///|
test "scrolls_anchored: flung to its start and to its end from where it was counted otherwise than the hand had it: at each end as counted, its rows there" {
  let c = anchored_case(100)
  let fling = fn(from : Double, to : Double, at : Double) {
    let id = match c.tree.claimer_of(c.tree.claimers_at(150.0, from), 0.0, to - from) {
      Some(id) => id
      // (at that end already: it is not its to take)
      None => return
    }
    c.tree.drag_at(id, Down, 150.0, from, at) |> ignore
    c.tree.drag_at(id, Moved, 150.0, (from + to) / 2.0, at + 5.0) |> ignore
    c.tree.drag_at(id, Moved, 150.0, to, at + 10.0) |> ignore
    c.tree.drag_at(id, Up, 150.0, to, at + 10.0) |> ignore
  }
  // (toward its start, hard, again and again: its first row at its top, it at 0 as counted)
  for i in 0..<12 {
    fling(10.0, 95.0, 100.0 + i.to_double() * 3000.0)
    c.tree.frame(390.0, 844.0, now=100.0 + i.to_double() * 3000.0 + 2900.0) |> ignore
  }
  assert_eq((c.top(0), c.scroll.at(c.tree)), (Some(0.0), 0.0))
  // (and back to its end: its last row at its foot, at its end again)
  for i in 0..<12 {
    fling(95.0, 10.0, 40000.0 + i.to_double() * 3000.0)
    c.tree.frame(390.0, 844.0, now=40000.0 + i.to_double() * 3000.0 + 2900.0) |> ignore
  }
  assert_eq((c.top(99), c.follows.get(), c.scroll.at(c.tree)), (Some(60.0), true, 3900.0))
}

///|
test "scrolls_anchored on iOS: pulled past its end, drawn past it, and back at its end let go; its rows as they were" {
  let c = anchored_case(100)
  c.tree.lists_feel(fn() { (@view.ListFeel::Ios, 2.0) })
  // (at its end; a finger up on it, past its end by 60)
  let id = match c.tree.claimer_of(c.tree.claimers_at(150.0, 90.0), 0.0, -30.0) {
    Some(id) => id
    None => fail("not taken over at its end")
  }
  c.tree.drag_at(id, Down, 150.0, 90.0, 100.0) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 60.0, 110.0) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 30.0, 120.0) |> ignore
  c.tree.frame(390.0, 844.0, now=120.0) |> ignore
  let pulled = c.scroll.past(c.tree)
  c.tree.drag_at(id, Up, 150.0, 30.0, 400.0) |> ignore
  c.tree.frame(390.0, 844.0, now=3000.0) |> ignore
  assert_true(pulled.abs() > 1.0, msg="drawn past its end as it is pulled: \{pulled}")
  assert_eq((c.scroll.past(c.tree), c.top(99), c.follows.get()), (0.0, Some(60.0), true))
}

///|
test "scrolls_anchored: a row half out over its top brought into sight (the focus come to it), from where it was counted otherwise than the hand had it: by as much as it was out, no more" {
  let c = anchored_case(100)
  // (at its end: row 97 from -20 to 20, half out over the top; it at 3900 as counted, the hand's place 0)
  assert_eq((c.top(97), c.scroll.at(c.tree)), (Some(-20.0), 3900.0))
  c.tree.show_in_sight(c.live[97].id())
  c.tree.frame(390.0, 844.0, now=100.0) |> ignore
  c.tree.frame(390.0, 844.0, now=2000.0) |> ignore
  assert_eq((c.top(97), c.top(98), c.scroll.at(c.tree)), (Some(0.0), Some(40.0), 3880.0))
}

///|
test "scrolls_anchored: glided from outside to where it is counted less 40, from where it was counted otherwise than the hand had it: there, its rows 40 lower" {
  let c = anchored_case(100)
  let at = c.scroll.at(c.tree)
  c.tree.event(10.0, fn() { c.scroll.glide_to(at - 40.0) })
  c.tree.frame(390.0, 844.0, now=3000.0) |> ignore
  assert_eq((at, c.scroll.at(c.tree), c.top(98)), (3900.0, 3860.0, Some(60.0)))
}

///|
test "scrolls_anchored: a part of a row asked into sight that is in sight already: nothing moved; a part under its foot: by as much as brings it in" {
  let c = anchored_case(100)
  // (row 97 from -20 to 20: its part from 20 to 30 of it, 0 to 10 in the window, in sight)
  c.tree.show_in_sight(c.live[97].id(), within=fn() { Some((20.0, 30.0)) })
  c.tree.frame(390.0, 844.0, now=100.0) |> ignore
  assert_eq((c.top(97), c.scroll.at(c.tree)), (Some(-20.0), 3900.0))
  // (its part from 0 to 10 of it, -20 to -10 in the window, over its top: down 20)
  c.tree.show_in_sight(c.live[97].id(), within=fn() { Some((0.0, 10.0)) })
  c.tree.frame(390.0, 844.0, now=200.0) |> ignore
  assert_eq((c.top(97), c.scroll.at(c.tree)), (Some(0.0), 3880.0))
}

///|
test "scrolls_anchored: the last row grown taller and its start asked into sight in the same change: its start in sight in that frame, as it is measured then" {
  let c = anchored_case(100)
  c.tree.event(10.0, fn() {
    c.heights[99].set(200.0)
    c.tree.show_in_sight(c.live[99].id(), within=fn() { Some((0.0, 10.0)) })
  })
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_eq(c.top(99), Some(0.0))
}

///|
test "a kept row under what shows, part of it asked into sight: that part's foot at the window's foot; taller than the window, its top at the top" {
  let c = anchored_case(100, from_end=false, kept=fn() { [99] })
  c.heights[99].set(200.0)
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  c.tree.show_in_sight(c.live[99].id(), within=fn() { Some((10.0, 20.0)) })
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_eq(c.top(99), Some(80.0))
  let d = anchored_case(100, from_end=false, kept=fn() { [99] })
  d.heights[99].set(200.0)
  d.tree.frame(390.0, 844.0, now=10.0) |> ignore
  d.tree.show_in_sight(d.live[99].id(), within=fn() { Some((30.0, 180.0)) })
  d.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_eq(d.top(99), Some(-30.0))
}


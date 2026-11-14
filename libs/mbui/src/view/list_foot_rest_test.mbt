// A page's list's foot at rest (View::scrolls_window): said `from_end`, a list shorter than what shows sits at its
// foot, the room left over its blocks, and grows from there up, the same layout as it comes to fill what shows and
// goes past it; whether it is at its foot (Scroll::at_foot_now) told as that comes to be so or stops, in the layout
// that makes it so, and never as it scrolls on either side of that (a fling's frames).

///|
/// How far a finger's drag goes each step, and how long a step is, as a fling is given (the finger let go at speed).
let fr_drag_step : Double = 20.0

///|
let fr_drag_ms : Double = 10.0

///|
/// The moment the finger goes down on the list, and how long after it is let go the frames are looked at.
let fr_down_at : Double = 100.0

///|
let fr_frames_ms : Double = 1000.0

///|
/// How far apart the frames are drawn as the fling goes: 60 a second.
let fr_frame_ms : Double = 1000.0 / 60.0

///|
priv struct RestCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  live : Map[Int, @view.View]
  /// how tall each block is, by its key (40 till said)
  more : Map[Int, @signals.Signal[Double]]
  /// each time it was told whether it is at its foot, as told
  told : Array[Bool]
  now : Ref[Double]
}

///|
/// A page's list 300 by 200 of `n` blocks 40 tall, following its foot, said `from_end` or not; what it tells of
/// being at its foot read by a binding of what holds it.
fn rest_case(n : Int, from_end : Bool) -> RestCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { a == b })
  let live : Map[Int, @view.View] = Map([])
  let more : Map[Int, @signals.Signal[Double]] = Map([])
  let tall = fn(k : Int) {
    match more.get(k) {
      Some(h) => h
      None => {
        let h = @signals.signal(40.0, same=fn(a, b) { a == b })
        more[k] = h
        h
      }
    }
  }
  for k in 0..<(n + 4) {
    tall(k) |> ignore
  }
  let told = []
  let now = Ref(0.0)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
        o.scrolls_window(scroll, fn() { keys.get() }, est=40.0, follows=fn() { true }, from_end~, fn(b, k) {
          live[k] = b
          b.owns(fn() { live.remove(k) }) |> ignore
          let h = tall(k)
          b.height(By(fn() { Some(h.get()) })) |> ignore
        })
        |> ignore
        o.reacts(fn() { scroll.at_foot_now() }, fn(foot) { told.push(foot) })
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys, live, more, told, now }
}

///|
/// Where block `k`'s top is drawn, in the list's box; none where it is not made.
fn RestCase::y(self : RestCase, k : Int) -> Double? {
  self.live.get(k).map(fn(v) { v.rect().1 })
}

///|
test "scrolls_window from_end: a short list sits at its foot; a block at a time, to just fill what shows and past it, each opening along its way from its moment, what was over it going up with it, its last at its foot at rest, no jump at either" {
  let c = rest_case(3, true)
  // (three of 40 in 200: 80 of room over them)
  let first = (c.y(0), c.y(2), c.scroll.at(c.tree))
  let each = []
  let mut at = 1000.0
  // (a 40's way, from rest: where it has got half way, and its end)
  let ends = @flex.come_way_ms(0.0, 0.0, 40.0)
  let half = @flex.come_way(0.0, 0.0, 40.0, ends / 2.0).0
  for n in [4, 5, 6] {
    c.now.val = at
    c.tree.advance(at)
    c.keys.set(Array::makei(n, fn(i) { i }))
    let look = fn(t : Double) {
      c.now.val = at + t
      c.tree.advance(at + t)
      c.tree.frame(390.0, 844.0) |> ignore
      (c.y(0), c.y(n - 2), c.y(n - 1), c.scroll.at(c.tree))
    }
    each.push((look(0.0), look(ends / 2.0), look(ends)))
    at = at + ends * 2.0
  }
  assert_eq(first, (Some(80.0), Some(160.0), 0.0))
  let up = fn(y : Double?, by : Double) { y.map(fn(y) { y - by }) }
  // (four: 40 over them; five fill it; six go 40 past it, the first wholly over the top at rest: not made then)
  assert_eq(each, [
    (
      (Some(80.0), Some(160.0), Some(200.0), 0.0),
      (up(Some(80.0), half), up(Some(160.0), half), up(Some(200.0), half), 0.0),
      (Some(40.0), Some(120.0), Some(160.0), 0.0),
    ),
    (
      (Some(40.0), Some(160.0), Some(200.0), 0.0),
      (up(Some(40.0), half), up(Some(160.0), half), up(Some(200.0), half), 0.0),
      (Some(0.0), Some(120.0), Some(160.0), 0.0),
    ),
    (
      (Some(0.0), Some(160.0), Some(200.0), 0.0),
      (up(Some(0.0), half), up(Some(160.0), half), up(Some(200.0), half), half),
      (None, Some(120.0), Some(160.0), 40.0),
    ),
  ])
  // (at its foot all the while, told so once)
  assert_eq(c.told, [true])
}

///|
test "scrolls_window from_end: a short list at its foot, a block in it grown: what is over it goes up in that frame, its foot where it was" {
  let c = rest_case(3, true)
  c.more[1].set(70.0)
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq((c.y(0), c.y(1), c.y(2)), (Some(50.0), Some(90.0), Some(160.0)))
}

///|
test "scrolls_window: not said from_end, a short list at its top, as ever" {
  let c = rest_case(3, false)
  assert_eq((c.y(0), c.y(2)), (Some(0.0), Some(80.0)))
}

///|
test "Scroll::at_foot_now: at its foot as it opens; a block at its foot grown, still, told nothing; moved off it by the wheel, told so in that frame; back to it, told so" {
  let c = rest_case(20, false)
  let opened = c.told.copy()
  c.more[19].set(90.0)
  c.tree.frame(390.0, 844.0) |> ignore
  let grown = c.told.copy()
  c.tree.wheel_at(150.0, 100.0, 0.0, -12.0, 0, 10.0) |> ignore
  c.tree.frame(390.0, 844.0) |> ignore
  let off = c.told.copy()
  c.tree.wheel_at(150.0, 100.0, 0.0, 400.0, 0, 20.0) |> ignore
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq((opened, grown, off, c.told), ([true], [true], [true, false], [true, false, true]))
}

///|
test "Scroll::at_foot_now: flung up off its foot: told once it leaves it, nothing as the fling goes on" {
  let c = rest_case(40, false)
  let tree = c.tree
  let id = tree.claimer_of(tree.claimers_at(150.0, 50.0), 0.0, fr_drag_step).unwrap()
  // (the finger down and drawn down three steps, let go at speed: the list goes up off its foot, on by itself)
  c.now.val = fr_down_at
  tree.drag_at(id, Down, 150.0, 50.0, fr_down_at) |> ignore
  let mut y = 50.0
  let mut at = fr_down_at
  while y < 50.0 + 3.0 * fr_drag_step {
    y = y + fr_drag_step
    at = at + fr_drag_ms
    c.now.val = at
    tree.drag_at(id, Moved, 150.0, y, at) |> ignore
    tree.frame(390.0, 844.0) |> ignore
  }
  tree.drag_at(id, Up, 150.0, y, at) |> ignore
  let let_go = c.scroll.at(tree)
  let mut moved = false
  while at < fr_down_at + fr_frames_ms {
    at = at + fr_frame_ms
    c.now.val = at
    tree.advance(at)
    tree.frame(390.0, 844.0) |> ignore
    if c.scroll.at(tree) != let_go {
      moved = true
    }
  }
  assert_eq((moved, c.told), (true, [true, false]))
}

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
fn window_case(
  holds? : (Int) -> Bool = fn(_) { true },
  follows? : () -> Bool = fn() { false },
  centres? : () -> Int? = fn() { None },
  near_foot? : (Double, () -> Bool, () -> Unit),
  tucks? : Int,
) -> WindowCase {
  let scroll = @view.Scroll::list()
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
      o.scrolls_window(scroll, fn() { keys.get() }, est=80.0, holds~, follows~, centres~, near_foot?, fn(b, k) {
        made.push(k)
        if tucks == Some(k) {
          scroll.tucks(b, fn() { 0.0 })
        }
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
test "scrolls_window: a block laid out taller than it was as it comes back into sight over what shows: what showed stays where the scroll put it, the column moved with what came over it" {
  let k = window_case()
  k.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  // (block 1, out of sight, comes to be 70 tall; scrolled back up by 30, it shows again, laid out so: block 2, seen at
  // -20, at 10 as the wheel put it, block 1 over it 30 taller than it was counted, the column at 100 for it)
  k.heights[1].set(70.0)
  k.tree.wheel_at(150.0, 50.0, 0.0, -30.0, 0, 20.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y1, _, h1) = k.live[1].rect()
  let (_, y2, _, _) = k.live[2].rect()
  assert_eq((k.scroll.at(k.tree), k.shown(), y1, h1, y2), (100.0, [1, 2, 3, 4], -60.0, 70.0, 10.0))
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
test "scrolls_window: following its foot, made there (nothing at its top made) and kept there as blocks come at its end; moved off it, left where it is" {
  let k = window_case(follows=fn() { true })
  let made_at = (k.scroll.at(k.tree), k.scroll.most(), k.shown().contains(9) && !k.made.contains(0))
  k.keys.set(Array::makei(12, fn(i) { i }))
  k.tree.frame(390.0, 844.0) |> ignore
  let grown = (k.scroll.at(k.tree) == k.scroll.most(), k.shown().contains(11))
  // (up by 100 off its foot: a block come at its end leaves it where it is)
  k.tree.wheel_at(150.0, 50.0, 0.0, -100.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let off = k.scroll.at(k.tree)
  k.keys.set(Array::makei(13, fn(i) { i }))
  k.tree.frame(390.0, 844.0) |> ignore
  assert_eq((made_at.0 == made_at.1, made_at.2, grown, k.scroll.at(k.tree)), (true, true, (true, true), off))
  assert_true(k.scroll.at(k.tree) < k.scroll.most())
}

///|
test "scrolls_window: a block come under a head that does not hold what shows: what shows under it stays where it was" {
  let k = window_case(holds=fn(b) { b != 0 })
  let (_, y1, _, _) = k.live[1].rect()
  let more = [0, 100]
  more.append(Array::makei(9, fn(i) { i + 1 }))
  k.keys.set(more)
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y1_now, _, _) = k.live[1].rect()
  // (block 100 laid out 40 over block 1: the column moved down by as much, the head gone up out of sight with it)
  assert_eq((k.scroll.at(k.tree), k.shown(), y1_now), (40.0, [1, 2, 100], y1))
}

///|
test "scrolls_window: a block brought to its middle as it is named, held there as what is over it is laid out" {
  let to : @signals.Signal[Int?] = @signals.signal(None)
  let k = window_case(centres=fn() { to.get() })
  to.set(Some(7))
  k.tree.frame(390.0, 844.0) |> ignore
  // (7 measured as it is brought there, 40 tall, its middle at 50 of the 100 that shows: 30 down; what is over it
  // measured as it shows (6, 40) and counted (3 to 5, 80 each), 7 at 400 and the column at 370)
  let (_, y7, _, _) = k.live[7].rect()
  assert_eq((k.scroll.at(k.tree), k.shown(), y7), (370.0, [6, 7, 8], 30.0))
}

///|
test "scrolls_window: following its foot, scrolled up to its top, blocks come over what shows: moved down with them, not taken to its foot" {
  let k = window_case(follows=fn() { true })
  k.tree.wheel_at(150.0, 50.0, 0.0, -1000.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y0, _, _) = k.live[0].rect()
  // (five over block 0, 80 each as counted: 400 over it, further down than the column went as it was laid out, 300)
  let more = [-5, -4, -3, -2, -1]
  more.append(Array::makei(10, fn(i) { i }))
  k.keys.set(more)
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y0_now, _, _) = k.live[0].rect()
  assert_eq((k.scroll.at(k.tree), k.shown(), y0_now), (400.0, [0, 1, 2], y0))
}

///|
test "scrolls_window near_foot: asked as it is scrolled to within so many of its heights of its foot while it wants, and again as its keys change there" {
  let asked = Ref(0)
  let wants = @signals.signal(true)
  let c = window_case(near_foot=(1.5, fn() { wants.get() }, fn() { asked.val = asked.val + 1 }))
  // (ten in 100, those not laid out yet counted 80: far from its foot at its top)
  assert_eq(asked.val, 0, msg="at its top: far from its foot")
  c.scroll.put(10000.0)
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.val, 1, msg="near its foot")
  c.keys.set(Array::makei(11, fn(i) { i }))
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.val, 2, msg="more came, still near: asked again")
  wants.set(false)
  c.keys.set(Array::makei(12, fn(i) { i }))
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.val, 2, msg="wanting no more: not asked")
}

///|
test "scrolls_window near_foot: a page more come in as it is asked (a source that answers at once) is far from its foot by its own blocks, not asked again before it is laid out" {
  let asked = Ref(0)
  let on = @signals.signal(false)
  let keys : Ref[@signals.Signal[Array[Int]]?] = Ref(None)
  let c = window_case(
    near_foot=(
      1.5,
      fn() { on.get() && keys.val.map_or(false, fn(k) { k.get().length() < 60 }) },
      fn() {
        asked.val = asked.val + 1
        match keys.val {
          Some(k) => {
            let n = @signals.untracked(fn() { k.get().length() })
            k.set(Array::makei(n + 10, fn(i) { i }))
          }
          None => ()
        }
      },
    ),
  )
  keys.val = Some(c.keys)
  // (at its foot, its last laid out; then left where it is, as a hand leaves it: not put past its foot, which keeps it
  // there as that goes on)
  c.scroll.put(10000.0)
  c.tree.frame(390.0, 844.0) |> ignore
  c.scroll.put(c.scroll.at(c.tree))
  c.tree.frame(390.0, 844.0) |> ignore
  on.set(true)
  c.tree.frame(390.0, 844.0) |> ignore
  // (ten more, counted 80 each till laid out: 800 past where it shows, more than a screen and a half of 100)
  assert_eq((asked.val, @signals.untracked(fn() { c.keys.get().length() })), (1, 20))
}

///|
test "Scroll::tucks: put as the block is first laid out so its foot is at the top, its foot keeping the room to go there with fewer than it is tall" {
  let c = window_case(tucks=1)
  c.keys.set([0, 1])
  c.tree.frame(390.0, 844.0) |> ignore
  // (two of 40 in 100: the second's foot 80 down, room kept under them to go there)
  assert_eq(c.scroll.at(c.tree), 80.0)
  assert_eq(c.scroll.most(), 80.0)
}

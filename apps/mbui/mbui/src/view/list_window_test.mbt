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
  place? : @view.ListPlace[Int],
  near_foot? : (Double, () -> Bool, () -> Unit),
  tucks? : Int,
  cover? : Double = 0.0,
  presses? : Bool = false,
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
      o.scrolls_window(scroll, fn() { keys.get() }, est=80.0, holds~, follows~, place?, near_foot?, fn(b, k) {
        made.push(k)
        if tucks == Some(k) {
          scroll.tucks(b, fn() { cover })
        }
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        let h = tall(k)
        b.height(By(fn() { Some(h.get()) })) |> ignore
        if presses {
          b.on_press(fn() {  }) |> ignore
        }
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
test "scrolls_window: a block brought to its middle as it is asked, held there as what is over it is laid out" {
  let place = @view.ListPlace::new()
  let k = window_case(place~)
  place.centre(7)
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
  // (at rest, what went closed: as long as a Move takes at most on)
  c.tree.frame(390.0, 844.0, now=@flex.move_most_ms) |> ignore
  // (two of 40 in 100: the second's foot 80 down, room kept under them to go there)
  assert_eq(c.scroll.at(c.tree), 80.0)
  assert_eq(c.scroll.most(), 80.0)
}

///|
test "Scroll::tucks: what is tucked under what covers the top is out of sight and takes no press there; scrolled down into sight, it does below what covers the top alone" {
  // (block 0 tucked under a bar 30 over the top: its foot put 30 down, 10 of it scrolled past the top)
  let c = window_case(tucks=0, cover=30.0, presses=true)
  let (b0, b1) = (c.live[0].id(), c.live[1].id())
  let (_, y0, _, h0) = c.live[0].rect()
  assert_eq((c.scroll.at(c.tree), y0 + h0), (10.0, 30.0))
  assert_true(!(c.tree.target_at(150.0, 15.0) is Pressed(t) && t == b0), msg="under the bar, tucked")
  assert_true(!(c.tree.target_at(150.0, 29.5) is Pressed(t) && t == b0), msg="under the bar's foot, tucked")
  assert_true(c.tree.target_at(150.0, 30.5) is Pressed(t) && t == b1, msg="the block after it, past the bar")
  // (scrolled to the top: drawn 0 to 40, under the bar to 30, in sight past it)
  c.tree.wheel_at(150.0, 50.0, 0.0, -100.0, 0, 10.0) |> ignore
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq(c.scroll.at(c.tree), 0.0)
  assert_true(!(c.tree.target_at(150.0, 15.0) is Pressed(t) && t == b0), msg="under the bar, in the top")
  assert_true(c.tree.target_at(150.0, 35.0) is Pressed(t) && t == b0, msg="in sight past the bar")
}

///|
test "ListPlace::bring: a block brought to the top of where it shows (an offset over it), what is over it counted as it is" {
  let place = @view.ListPlace::new()
  let k = window_case(place~)
  place.bring(7)
  k.tree.frame(390.0, 844.0) |> ignore
  // (0 to 2 laid out 40 each, 3 to 6 counted 80: 7's top at 440)
  let (_, y7, _, _) = k.live[7].rect()
  assert_eq((k.scroll.at(k.tree), k.shown(), y7), (440.0, [7, 8, 9], 0.0))
  // (10 over it: its top 10 over the list's)
  place.bring(7, offset=10.0)
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y7, _, _) = k.live[7].rect()
  assert_eq((k.scroll.at(k.tree), y7), (450.0, -10.0))
}

///|
test "ListPlace::bring: asked before the block is among its keys, brought there as it comes" {
  let place = @view.ListPlace::new()
  let k = window_case(place~)
  place.bring(10)
  k.tree.frame(390.0, 844.0) |> ignore
  assert_eq(k.scroll.at(k.tree), 0.0)
  k.keys.set(Array::makei(15, fn(i) { i }))
  k.tree.frame(390.0, 844.0) |> ignore
  let (_, y10, _, _) = k.live[10].rect()
  assert_eq(y10, 0.0)
}

///|
test "ListPlace::to_end: at once at its foot; one that follows it kept there from then as blocks come" {
  let place = @view.ListPlace::new()
  let k = window_case(place~, follows=fn() { true })
  k.tree.wheel_at(150.0, 50.0, 0.0, -1000.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let up = k.scroll.at(k.tree)
  place.to_end(glide=false)
  k.tree.frame(390.0, 844.0) |> ignore
  let back = k.scroll.at(k.tree) == k.scroll.most()
  k.keys.set(Array::makei(12, fn(i) { i }))
  k.tree.frame(390.0, 844.0) |> ignore
  assert_eq((up, back, k.scroll.at(k.tree) == k.scroll.most(), k.shown().contains(11)), (0.0, true, true, true))
}

///|
test "ListPlace::to_end: near it, glides there from the moment it is asked, the same whatever frames come; far, at once" {
  let now = Ref(0.0)
  let place = @view.ListPlace::new()
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        o.scrolls_window(scroll, fn() { Array::makei(10, fn(i) { i }) }, est=40.0, place~, fn(b, _) {
          b.height(Is(Some(40.0))) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  // (400 tall, 100 shown: its foot 300 down; 150 from it, less than twice what shows)
  scroll.put(150.0)
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  now.val = 100.0
  place.to_end()
  now.val = 116.0
  tree.frame(390.0, 844.0, now=116.0) |> ignore
  let midway = scroll.at(tree)
  now.val = 2000.0
  tree.frame(390.0, 844.0, now=2000.0) |> ignore
  assert_true(midway > 150.0 && midway < 300.0)
  assert_eq(scroll.at(tree), 300.0)
  // (back at its top, 300 from its foot: there at once)
  scroll.put(0.0)
  tree.frame(390.0, 844.0, now=2000.0) |> ignore
  place.to_end()
  tree.frame(390.0, 844.0, now=2000.0) |> ignore
  assert_eq(scroll.at(tree), 300.0)
}

///|
test "ListPlace::follow_from: its foot followed no further than the block's top; held there, then followed no more" {
  let place = @view.ListPlace::new()
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(10, fn(i) { i }), same=fn(a, b) { a == b })
  let live : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=40.0, follows=fn() { true }, place~, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  place.follow_from(Some(10))
  // (each change looked at once what it brought is at rest: as long as a Move takes at most on)
  let rest = @flex.move_most_ms
  // (two come at its end: its foot at 380, 10's top at 400 under it: followed)
  keys.set(Array::makei(12, fn(i) { i }))
  tree.frame(390.0, 844.0, now=rest) |> ignore
  let followed = scroll.at(tree) == scroll.most()
  // (five more: its foot at 580, past 10's top; held with 10 at the top of what shows)
  keys.set(Array::makei(17, fn(i) { i }))
  tree.frame(390.0, 844.0, now=rest * 2.0) |> ignore
  let (_, y10, _, _) = live[10].rect()
  let held = scroll.at(tree)
  keys.set(Array::makei(18, fn(i) { i }))
  tree.frame(390.0, 844.0, now=rest * 3.0) |> ignore
  assert_eq((followed, y10, held, scroll.at(tree)), (true, 0.0, 400.0, 400.0))
}

///|
/// Twenty blocks of 40 (100 one of 60) in 100, as they are counted, following its foot or not, put at its foot and
/// moved up to 300 by `by` ("put", or "the wheel"): moved there nothing is laid out, the anchor still its foot's. The
/// tree, its keys, and where each block's top is.
fn in_sight_case(
  follows : Bool,
  by : String,
) -> (@view.Tree, @view.Scroll, @signals.Signal[Array[Int]], (Int) -> Double?) {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(20, fn(i) { i }), same=fn(a, b) { a == b })
  let live : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=40.0, follows=fn() { follows }, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(if k == 100 { 60.0 } else { 40.0 }))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  scroll.put(700.0)
  tree.frame(390.0, 844.0) |> ignore
  if by == "put" {
    scroll.put(300.0)
  } else {
    tree.wheel_at(150.0, 50.0, 0.0, -400.0, 0, 10.0) |> ignore
  }
  tree.frame(390.0, 844.0) |> ignore
  (tree, scroll, keys, fn(k : Int) { live.get(k).map(fn(v) { v.rect().1 }) })
}

///|
test "scrolls_window: scrolled up off its foot by the hand or put there, nothing laid out since, a key put in among what shows: what is over it stays where it was, to the bit, what is under it pushed down by it" {
  for follows in [true, false] {
    for by in ["put", "the wheel"] {
      let (tree, scroll, keys, y) = in_sight_case(follows, by)
      // (at 300: 7 from 20 over the top, 8 at 20, 9 at 60)
      let was = (scroll.at(tree), y(7), y(8), y(9))
      // (one 60 tall put in after 7: 7 where it was, it at 20, 8 under it at 80)
      let put_in = Array::makei(8, fn(i) { i })
      put_in.push(100)
      put_in.append(Array::makei(12, fn(i) { i + 8 }))
      keys.set(put_in)
      // (looked at once it is at rest: as long as a Move takes at most on from the wheel's moment)
      tree.frame(390.0, 844.0, now=10.0 + @flex.move_most_ms) |> ignore
      assert_eq(
        (was, (scroll.at(tree), y(7), y(100), y(8))),
        ((300.0, Some(-20.0), Some(20.0), Some(60.0)), (300.0, Some(-20.0), Some(20.0), Some(80.0))),
        msg="moved by \{by}, following its foot \{follows}",
      )
    }
  }
}

///|
test "scrolls_window: scrolled up off its foot by the hand or put there, nothing laid out since, a key taken out under what shows: what shows stays where it was, to the bit" {
  for follows in [true, false] {
    for by in ["put", "the wheel"] {
      let (tree, scroll, keys, y) = in_sight_case(follows, by)
      // (12, out of sight under what shows, over the foot it was opened at, taken out)
      keys.set(Array::makei(20, fn(i) { i }).filter(fn(k) { k != 12 }))
      tree.frame(390.0, 844.0) |> ignore
      assert_eq(
        (scroll.at(tree), y(7), y(8), y(9)),
        (300.0, Some(-20.0), Some(20.0), Some(60.0)),
        msg="moved by \{by}, following its foot \{follows}",
      )
    }
  }
}

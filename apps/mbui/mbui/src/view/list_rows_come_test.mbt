// A page's list's keys changed by data (View::scrolls_window): what comes or goes down its column at one moment makes
// its way as one, as a plain column's rows do (View::comes, flex's ComeGroup), from the data's moment, whatever frames
// are drawn; at its foot what is above goes up by the same way, the list kept there; scrolled up, what is read stays
// where it is and a change within sight moves in place; keys the page says are caught up (View::scrolls_window's
// `comes`), and blocks brought in by scrolling, at once. A short list sits at its foot. Each scene is looked at at moments it declares, the frames between
// drawn at none (one jump), 60, 120, 24 and 7 a second, on a grid from 0 that the data's moment is not on.

///|
/// The moment the data comes in these scenes: between two frames at every rate here.
let rc_at : Double = 100.5

///|
/// How long a second is (ms): what the rates' frames are apart by.
let rc_second : Double = 1000.0

///|
/// The rates frames are drawn at between the moments looked at: none (one jump), then 60, 120, 24 and 7 a second.
let rc_rates : Array[Double] = [0.0, 60.0, 120.0, 24.0, 7.0]

///|
/// How long after the first change the second comes, in the scenes of two (a way still going then).
let rc_again_ms : Double = 120.0

///|
/// How far apart the moments are looked at where a way is followed whole.
let rc_look_ms : Double = 10.0

///|
/// What is not drawn: its place read as this.
let rc_none : Double = -1.0e9

///|
/// How tall block `k` is: 40, but the few these scenes bring (a message 60, a working row 44, its reply 70, two more).
fn rc_tall(k : Int) -> Double {
  match k {
    70 => 60.0
    71 => 40.0
    72 => 20.0
    50 => 44.0
    51 => 70.0
    100 => 60.0
    _ => 40.0
  }
}

///|
/// Keys 0 to 9, then `more`.
fn rc_ten_and(more : Array[Int]) -> Array[Int] {
  let all = Array::makei(10, fn(i) { i })
  all.append(more)
  all
}

///|
/// The words drawn `w`'s top, as the tree is drawn now; rc_none where none is.
fn rc_y(t : @view.Tree, w : String) -> Double {
  match t.drawn().filter(fn(d) { d.words == w }) {
    [d, ..] => d.y
    _ => rc_none
  }
}

///|
priv struct RcCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
}

///|
/// A page's list 300 by 200 of `keys`, each block as tall as rc_tall says with words 行k, following its foot; drawn
/// once, at 0. `comes`, `goes`: what its page says of a key that comes and of one that goes (the list's own default:
/// it does). `from_end`: short of what shows, at its foot (View::scrolls_window's). `reduced`: its motion reduced.
fn rc_case(
  keys : Array[Int],
  comes? : (Int) -> Bool = fn(_) { true },
  goes? : (Int) -> Bool = fn(_) { true },
  from_end? : Bool = false,
  reduced? : Bool = false,
) -> RcCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=40.0, follows=fn() { true }, comes~, goes~, from_end~, fn(b, k) {
        b.height(Is(Some(rc_tall(k)))).words(Is("行\{k}")) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  if reduced {
    tree.reduces_motion(fn() { true })
  }
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys }
}

///|
/// A plain column (no scroll) of the same blocks by `keys`, its rows made and let go by an each, 下 under them: what
/// the list is held to (View::comes, flex's ComeGroup, come_group_test). Drawn once, at 0.
fn rc_column(keys : Array[Int]) -> (@view.Tree, @signals.Signal[Array[Int]]) {
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))) |> ignore
      col.each(fn() { keys.get() }, fn(k) { k }, fn(r, k) {
        r.height(Is(Some(rc_tall(k.get())))).words(Is("行\{k.get()}")) |> ignore
      })
      col.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  (tree, keys)
}

///|
/// How far it is off its foot.
fn RcCase::off_foot(self : RcCase) -> Double {
  self.scroll.most() - self.scroll.at(self.tree)
}

///|
/// `tree` walked to each of `looks` (in order), `events` told at their moments on the way (each between frames: before
/// the frame of a look at the same moment), frames drawn between at `rate` a second (on its grid from 0; none at 0 nor
/// at `from` or before, where it was walked to already), a frame at each look; what `read` says at each. `inputs`: the
/// events told as inputs from outside are (Tree::input).
fn[T] rc_walk(
  tree : @view.Tree,
  events : Array[(Double, () -> Unit)],
  looks : Array[Double],
  rate : Double,
  read : () -> T,
  from? : Double = 0.0,
  inputs? : Bool = false,
) -> Array[T] {
  let out = []
  let step = if rate > 0.0 { rc_second / rate } else { 0.0 }
  let last = Ref(from)
  let frames_to = fn(to : Double) {
    if step > 0.0 {
      let mut f = (last.val / step).floor() + 1.0
      while f * step < to {
        let at = f * step
        if at > last.val {
          tree.at(at)
          tree.frame(390.0, 844.0) |> ignore
          last.val = at
        }
        f = f + 1.0
      }
    }
  }
  let mut e = 0
  for at in looks {
    while e < events.length() && events[e].0 <= at {
      frames_to(events[e].0)
      if inputs {
        tree.input(events[e].0, events[e].1)
      } else {
        tree.event(events[e].0, events[e].1)
      }
      e = e + 1
    }
    frames_to(at)
    tree.at(at)
    tree.frame(390.0, 844.0) |> ignore
    last.val = at
    out.push(read())
  }
  out
}

///|
/// The moments from rc_at to `to`, rc_look_ms apart.
fn rc_looks(to : Double) -> Array[Double] {
  let out = []
  let mut at = rc_at
  while at <= to {
    out.push(at)
    at = at + rc_look_ms
  }
  out
}

///|
/// How many times `ys` turns back (by more than a hundredth of a point).
fn rc_turns(ys : Array[Double]) -> Int {
  let mut turns = 0
  let mut dir = 0
  for i in 1..<ys.length() {
    let d = ys[i] - ys[i - 1]
    let s = if d > 0.01 {
      1
    } else if d < -0.01 {
      -1
    } else {
      0
    }
    if s != 0 && dir != 0 && s != dir {
      turns = turns + 1
    }
    if s != 0 {
      dir = s
    }
  }
  turns
}

///|
/// Whether `a` and `b` are the same, each to a millionth of a point.
fn rc_near(a : Array[Double], b : Array[Double]) -> Bool {
  guard a.length() == b.length() else { return false }
  for i, x in a {
    if !((x - b[i]).abs() < 1.0e-6) {
      return false
    }
  }
  true
}

///|
/// The list of `keys` and the plain column of them, each walked by `events` (of its keys) to `looks` at `rate`: how far
/// what is above the last of the list's `above` has gone up, and how far 下 under the column has gone down.
fn rc_against_column(
  keys : Array[Int],
  above : Int,
  events : Array[(Double, Array[Int])],
  looks : Array[Double],
  rate : Double,
) -> (Array[Double], Array[Double]) {
  let c = rc_case(keys)
  let was = rc_y(c.tree, "行\{above}")
  let list = rc_walk(c.tree, events.map(fn(e) { (e.0, fn() { c.keys.set(e.1) }) }), looks, rate, fn() {
    was - rc_y(c.tree, "行\{above}")
  })
  let (t, ks) = rc_column(keys)
  let under = rc_y(t, "下")
  let column = rc_walk(t, events.map(fn(e) { (e.0, fn() { ks.set(e.1) }) }), looks, rate, fn() {
    rc_y(t, "下") - under
  })
  (list, column)
}

///|
test "a page's list at its foot, a key appended by data between two frames: its block opens along a Move from that moment, what is above going up by as much, at its foot all the way, there at its moment and the length, the same at every rate" {
  let tall = rc_tall(70)
  let ends = rc_at + @flex.come_way_ms(0.0, 0.0, tall)
  let looks = [rc_at, rc_at + 16.0, rc_at + 50.0, rc_at + 125.0, rc_at + 200.0, ends - 0.5, ends, ends + 100.0]
  // (the Move a block opens on alone, at each of those moments)
  let want = looks.map(fn(at) { @flex.come_way(0.0, 0.0, tall, at - rc_at).0 })
  let by_rate = rc_rates.map(fn(rate) {
    let c = rc_case(Array::makei(10, fn(i) { i }))
    let (y8, y9) = (rc_y(c.tree, "行8"), rc_y(c.tree, "行9"))
    rc_walk(c.tree, [(rc_at, fn() { c.keys.set(rc_ten_and([70])) })], looks, rate, fn() {
      (y9 - rc_y(c.tree, "行9"), y8 - rc_y(c.tree, "行8"), c.off_foot())
    })
  })
  for i, rate in rc_rates {
    let got = by_rate[i]
    assert_true(rc_near(got.map(fn(r) { r.0 }), want), msg="9 gone up at \{rate} a second: \{Repr(got)} for \{Repr(want)}")
    assert_true(rc_near(got.map(fn(r) { r.1 }), want), msg="8 gone up at \{rate} a second: \{Repr(got)}")
    assert_true(got.iter().all(fn(r) { r.2 == 0.0 }), msg="at its foot at \{rate} a second: \{Repr(got)}")
    // (the same to the bit as drawn in one jump)
    assert_eq(got, by_rate[0], msg="at \{rate} a second")
  }
  // (there at its moment and the length: all of it up)
  assert_eq(by_rate[0][6].0, tall)
}

///|
test "a page's list at its foot, one block going and another coming at one moment (a working row and its reply): one way, as a column's, what is above going one way only, the same at every rate" {
  let keys = Array::makei(9, fn(i) { i })
  keys.push(50)
  let then = Array::makei(9, fn(i) { i })
  then.push(51)
  let looks = rc_looks(rc_at + @flex.move_most_ms + 100.0)
  let runs = rc_rates.map(fn(rate) { rc_against_column(keys, 8, [(rc_at, then)], looks, rate) })
  for i, rate in rc_rates {
    let (list, column) = runs[i]
    assert_true(rc_near(list, column), msg="at \{rate} a second, the list \{Repr(list)}, the column \{Repr(column)}")
    assert_eq(rc_turns(list), 0, msg="at \{rate} a second: \{Repr(list)}")
    assert_eq(list, runs[0].0, msg="at \{rate} a second")
  }
  // (taller by the reply's less the working row's: 70 - 44)
  assert_eq(runs[0].0[runs[0].0.length() - 1], rc_tall(51) - rc_tall(50))
}

///|
test "a page's list at its foot, a second block come while the first is on its way: joined, one way as a column's, speed going on, the same at every rate" {
  let keys = Array::makei(10, fn(i) { i })
  let looks = rc_looks(rc_at + rc_again_ms + @flex.move_most_ms + 100.0)
  let first = rc_ten_and([70])
  let both = rc_ten_and([70, 71])
  let runs = rc_rates.map(fn(rate) {
    rc_against_column(keys, 9, [(rc_at, first), (rc_at + rc_again_ms, both)], looks, rate)
  })
  for i, rate in rc_rates {
    let (list, column) = runs[i]
    assert_true(rc_near(list, column), msg="at \{rate} a second, the list \{Repr(list)}, the column \{Repr(column)}")
    assert_eq(rc_turns(list), 0, msg="at \{rate} a second: \{Repr(list)}")
    assert_eq(list, runs[0].0, msg="at \{rate} a second")
  }
}

///|
test "a page's list at its foot, the block on its way taken back as a shorter one comes: the whole turned once, as a column's, the same at every rate" {
  let keys = Array::makei(10, fn(i) { i })
  let looks = rc_looks(rc_at + rc_again_ms + @flex.move_most_ms * 2.0 + 100.0)
  let first = rc_ten_and([70])
  let other = Array::makei(10, fn(i) { i })
  other.push(72)
  let runs = rc_rates.map(fn(rate) {
    rc_against_column(keys, 9, [(rc_at, first), (rc_at + rc_again_ms, other)], looks, rate)
  })
  for i, rate in rc_rates {
    let (list, column) = runs[i]
    assert_true(rc_near(list, column), msg="at \{rate} a second, the list \{Repr(list)}, the column \{Repr(column)}")
    assert_true(rc_turns(list) <= 1, msg="at \{rate} a second: \{Repr(list)}")
    assert_eq(list, runs[0].0, msg="at \{rate} a second")
  }
  assert_eq(runs[0].0[runs[0].0.length() - 1], rc_tall(72))
}

///|
test "a page's list scrolled up, a key appended at its foot out of sight: what is read stays where it is at every moment (already so)" {
  for rate in rc_rates {
    let c = rc_case(Array::makei(20, fn(i) { i }))
    c.scroll.put(300.0)
    c.tree.frame(390.0, 844.0) |> ignore
    let read = fn() { [rc_y(c.tree, "行7"), rc_y(c.tree, "行9"), rc_y(c.tree, "行12")] }
    let was = read()
    let got = rc_walk(c.tree, [(rc_at, fn() { c.keys.set(Array::makei(21, fn(i) { i })) })], rc_looks(rc_at + 600.0), rate, read)
    assert_true(got.iter().all(fn(r) { r == was }), msg="at \{rate} a second: \{Repr(was)} \{Repr(got)}")
  }
}

///|
test "a page's list scrolled up, a key put in within sight: what is over it stays, what is under it moves down along a Move from the data's moment, the same at every rate" {
  let tall = rc_tall(100)
  let ends = rc_at + @flex.come_way_ms(0.0, 0.0, tall)
  let looks = [rc_at, rc_at + 16.0, rc_at + 50.0, rc_at + 125.0, ends - 0.5, ends, ends + 100.0]
  let want = looks.map(fn(at) { @flex.come_way(0.0, 0.0, tall, at - rc_at).0 })
  let keys = Array::makei(20, fn(i) { i })
  let put_in = Array::makei(10, fn(i) { i })
  put_in.push(100)
  put_in.append(Array::makei(10, fn(i) { i + 10 }))
  let by_rate = rc_rates.map(fn(rate) {
    let c = rc_case(keys)
    // (300 down: 7 from 20 over the top of what shows, 10 at 100)
    c.scroll.put(300.0)
    c.tree.frame(390.0, 844.0) |> ignore
    let was = (rc_y(c.tree, "行7"), rc_y(c.tree, "行9"), rc_y(c.tree, "行10"))
    let got = rc_walk(c.tree, [(rc_at, fn() { c.keys.set(put_in) })], looks, rate, fn() {
      (rc_y(c.tree, "行7"), rc_y(c.tree, "行9"), rc_y(c.tree, "行10"))
    })
    (was, got)
  })
  for i, rate in rc_rates {
    let (was, got) = by_rate[i]
    assert_true(got.iter().all(fn(r) { r.0 == was.0 && r.1 == was.1 }), msg="over it at \{rate} a second: \{Repr(got)}")
    assert_true(rc_near(got.map(fn(r) { r.2 - was.2 }), want), msg="under it at \{rate} a second: \{Repr(got)} for \{Repr(want)}")
    assert_eq(got, by_rate[0].1, msg="at \{rate} a second")
  }
}

///|
test "a page's list at its foot, thirty keys come in one change of which the page says the last comes, the rest caught up: twenty-nine there at once, the last along its way, what is above going up with it, at its foot all the way, the same at every rate" {
  let tall = rc_tall(49)
  let ends = rc_at + @flex.come_way_ms(0.0, 0.0, tall)
  let looks = [rc_at, rc_at + 50.0, rc_at + 125.0, ends - 0.5, ends, ends + 100.0]
  let by_rate = rc_rates.map(fn(rate) {
    let c = rc_case(Array::makei(20, fn(i) { i }), comes=fn(k) { k == 49 })
    rc_walk(c.tree, [(rc_at, fn() { c.keys.set(Array::makei(50, fn(i) { i })) })], looks, rate, fn() {
      (rc_y(c.tree, "行47"), rc_y(c.tree, "行48"), c.off_foot())
    })
  })
  for i, rate in rc_rates {
    let got = by_rate[i]
    // (the twenty-nine there as the change is told, 48 at its foot; then up as far as 49's way has got)
    for j, at in looks {
      let up = @flex.come_way(0.0, 0.0, tall, at - rc_at).0
      assert_true((got[j].0 - (120.0 - up)).abs() < 1.0e-6, msg="47 at \{at}, \{rate} a second: \{Repr(got)}")
      assert_true((got[j].1 - (160.0 - up)).abs() < 1.0e-6, msg="48 at \{at}, \{rate} a second: \{Repr(got)}")
      assert_eq(got[j].2, 0.0, msg="at its foot at \{at}, \{rate} a second")
    }
    assert_eq(got, by_rate[0], msg="at \{rate} a second")
  }
  // (at rest at its moment and the way's length: 48 a block up, 49 at its foot)
  assert_eq(by_rate[0][4], (80.0, 120.0, 0.0))
}

///|
test "a page's list scrolled up to where blocks never made show: each there at once, whole (already so)" {
  for rate in rc_rates {
    let c = rc_case(Array::makei(20, fn(i) { i }))
    let got = rc_walk(c.tree, [(rc_at, fn() { c.scroll.put(300.0) })], [rc_at, rc_at + 100.0], rate, fn() {
      (rc_y(c.tree, "行7"), rc_y(c.tree, "行8"), rc_y(c.tree, "行12"))
    })
    assert_eq(got, [(-20.0, 20.0, 180.0), (-20.0, 20.0, 180.0)], msg="at \{rate} a second: \{Repr(got)}")
  }
}

///|
test "a short page's list sits at its foot; grown by a block at a time past what shows, at rest each time its last at its foot, what was over it as far up, no jump as it comes to fill what shows or more" {
  let c = rc_case([0, 1, 2], from_end=true)
  let rows = fn(n : Int) { (rc_y(c.tree, "行\{n - 2}"), rc_y(c.tree, "行\{n - 1}"), c.off_foot()) }
  // (three of 40 in 200: at its foot, 80 of ground over them)
  assert_eq((rc_y(c.tree, "行0"), rows(3)), (80.0, (120.0, 160.0, 0.0)))
  let mut at = rc_at
  let mut n = 3
  // (to 160 of 200, all of it, and past it)
  while n < 6 {
    let was = rc_y(c.tree, "行\{n - 1}")
    let more = Array::makei(n + 1, fn(i) { i })
    let got = rc_walk(c.tree, [(at, fn() { c.keys.set(more) })], [at, at + @flex.move_most_ms], 0.0, fn() {
      (rc_y(c.tree, "行\{n - 1}"), rows(n + 1))
    })
    // (as it comes, what was last where it was; at rest, up by the block's height, the new one at its foot)
    assert_eq(got[0].0, was, msg="as \{n} come")
    assert_eq(got[1].1, (120.0, 160.0, 0.0), msg="at rest, \{n + 1} of them")
    n = n + 1
    at = at + @flex.move_most_ms * 2.0
  }
}

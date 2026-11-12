// A page's list's head and foot (View::scrolls_window's `head` and `foot`): two places the list holds itself, the page
// building into them, how tall each is known to the tree in the same layout. The head over its keys' blocks in what
// scrolls, never the anchor: what is read is held by the keys' blocks alone, and how far the keys start is read under
// it (bring, near_top). The foot pinned at the foot of what shows, over what scrolls, as wide as the list, taking its own
// presses; as tall as it is laid out, the room kept under the last block. Each scene looked at at moments it declares
// (rc_walk, list_rows_come_test's), in one jump and at 60, 120, 24 and 7 a second where a way goes.

///|
/// How tall the head is as it is first made, and as it is said to grow.
let lh_head : Double = 50.0

///|
let lh_head_grown : Double = 90.0

///|
/// How tall the foot is as it is first made, and as it is said to grow.
let lh_foot : Double = 30.0

///|
let lh_foot_grown : Double = 60.0

///|
/// A page's list 300 by 200 of `keys`, each block 40 tall (rc_tall) with words 行k and a press of its own counted; a
/// head of `head` tall with words 头 and a foot of `foot` tall with words 脚 and a press of its own counted, where each
/// is given (none: not said). `follows`, `from_end`, `place`, `near_top` the list's. Drawn once, at 0.
priv struct LhCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  head : @signals.Signal[Double]
  foot : @signals.Signal[Double]
  pressed : Ref[Array[String]]
  rows : Map[Int, @view.View]
}

///|
fn lh_case(
  keys : Array[Int],
  head? : Double,
  foot? : Double,
  follows? : Bool = false,
  from_end? : Bool = false,
  place? : @view.ListPlace[Int],
  near_top? : (Double, () -> Bool, () -> Unit),
  foot_holds? : (@view.View, Ref[Array[String]]) -> Unit,
) -> LhCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let head_h = @signals.signal(head.unwrap_or(0.0), same=fn(a, b) { a == b })
  let foot_h = @signals.signal(foot.unwrap_or(0.0), same=fn(a, b) { a == b })
  let pressed : Ref[Array[String]] = Ref([])
  let rows : Map[Int, @view.View] = Map([])
  let head_of = match head {
    Some(_) =>
      Some(fn(v : @view.View) {
        v.box(fn(h) { h.height(By(fn() { Some(head_h.get()) })).shrink(Is(0.0)).words(Is("头")) |> ignore })
        |> ignore
      })
    None => None
  }
  let foot_of = match (foot, foot_holds) {
    (Some(_), Some(holds)) =>
      Some(fn(v : @view.View) {
        v.box(fn(f) {
          f.height(By(fn() { Some(foot_h.get()) })).shrink(Is(0.0)) |> ignore
          holds(f, pressed)
        })
        |> ignore
      })
    (Some(_), None) =>
      Some(fn(v : @view.View) {
        v.box(fn(f) {
          f
          .height(By(fn() { Some(foot_h.get()) }))
          .shrink(Is(0.0))
          .words(Is("脚"))
          .on_press(fn() { pressed.val.push("脚") })
          .says(Is(Some(@view.said(Button, label="foot"))))
          |> ignore
        })
        |> ignore
      })
    (None, _) => None
  }
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        follows=fn() { follows },
        from_end~,
        place?,
        near_top?,
        head?=head_of,
        foot?=foot_of,
        fn(b, k) {
          rows[k] = b
          b
          .height(Is(Some(rc_tall(k))))
          .words(Is("行\{k}"))
          .on_press(fn() { pressed.val.push("行\{k}") })
          .says(Is(Some(@view.said(Button, label="row \{k}"))))
          |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys, head: head_h, foot: foot_h, pressed, rows }
}

///|
/// The words drawn `w`'s foot (its top and height), as the tree is drawn now; rc_none where none is.
fn lh_foot_of(t : @view.Tree, w : String) -> Double {
  match t.drawn().filter(fn(d) { d.words == w }) {
    [d, ..] => d.y + d.h
    _ => rc_none
  }
}

///|
/// Within a millionth of a point.
fn lh_near(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-6
}

///|
test "a page's list at its top, its head showing, a page of keys put in over its first: the first stays where it was at every moment, the head gone out of sight above, the same at every rate" {
  let looks = rc_looks(rc_at + 600.0)
  let by_rate = rc_rates.map(fn(rate) {
    let c = lh_case(rc_ten_and([]), head=lh_head)
    let was = (rc_y(c.tree, "头"), rc_y(c.tree, "行0"))
    let older = Array::makei(5, fn(i) { i - 5 })
    let got = rc_walk(c.tree, [(rc_at, fn() { c.keys.set(older + c.keys.untracked()) })], looks, rate, fn() {
      (rc_y(c.tree, "行0"), lh_foot_of(c.tree, "头"))
    })
    (was, got)
  })
  for i, rate in rc_rates {
    let (was, got) = by_rate[i]
    assert_eq(was, (0.0, lh_head), msg="at \{rate} a second: the head at its top, its first key under it")
    assert_true(
      got.iter().all(fn(g) { lh_near(g.0, lh_head) && (g.1 == rc_none || g.1 <= 0.0) }),
      msg="at \{rate} a second: \{Repr(got)}",
    )
    assert_eq(got, by_rate[0].1, msg="at \{rate} a second")
  }
}

///|
test "a page's list's head grown, nothing declaring it: scrolled, what is read stays; at its very top, at its top, what is under the head moving with it, in the frame of the change" {
  // (scrolled: key 10 brought to the top of what shows)
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let c = lh_case(Array::makei(30, fn(i) { i }), head=lh_head, place~)
  place.bring(10)
  c.tree.frame(390.0, 844.0) |> ignore
  let read_was = rc_y(c.tree, "行10")
  c.tree.at(rc_at)
  c.head.set(lh_head_grown)
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq(read_was, 0.0, msg="scrolled: brought to the top")
  assert_eq(rc_y(c.tree, "行10"), 0.0, msg="scrolled: what is read stays")
  // (at its very top)
  let t = lh_case(Array::makei(30, fn(i) { i }), head=lh_head)
  let top_was = (rc_y(t.tree, "头"), rc_y(t.tree, "行0"))
  t.tree.at(rc_at)
  t.head.set(lh_head_grown)
  t.tree.frame(390.0, 844.0) |> ignore
  assert_eq(top_was, (0.0, lh_head), msg="at its top")
  assert_eq((rc_y(t.tree, "头"), rc_y(t.tree, "行0"), t.scroll.at(t.tree)), (0.0, lh_head_grown, 0.0), msg="at its top still")
}

///|
test "a page's list said from_end, short of what shows, with a head: the head at the top of what shows, its blocks at its foot, the room between them" {
  let c = lh_case([0, 1], head=lh_head, from_end=true)
  assert_eq((rc_y(c.tree, "头"), rc_y(c.tree, "行0"), rc_y(c.tree, "行1")), (0.0, 120.0, 160.0))
}

///|
test "a page's list's foot grown, nothing declaring it: at its foot its last block's foot at the foot's top in the frame of the change and every one after; scrolled up, what is read stays at every moment and it reaches as much further, the same at every rate" {
  let looks = rc_looks(rc_at + 600.0)
  let by_rate = rc_rates.map(fn(rate) {
    // (at its foot, following it)
    let c = lh_case(rc_ten_and([]), foot=lh_foot, follows=true)
    let was = (lh_foot_of(c.tree, "行9"), rc_y(c.tree, "脚"))
    let at_foot = rc_walk(c.tree, [(rc_at, fn() { c.foot.set(lh_foot_grown) })], looks, rate, fn() {
      (lh_foot_of(c.tree, "行9"), rc_y(c.tree, "脚"))
    })
    // (scrolled up: key 2 brought to the top of what shows)
    let place : @view.ListPlace[Int] = @view.ListPlace::new()
    let u = lh_case(rc_ten_and([]), foot=lh_foot, place~)
    place.bring(2)
    u.tree.frame(390.0, 844.0) |> ignore
    let most_was = u.scroll.most()
    let up = rc_walk(u.tree, [(rc_at, fn() { u.foot.set(lh_foot_grown) })], looks, rate, fn() {
      (rc_y(u.tree, "行2"), u.scroll.most() - most_was)
    })
    (was, at_foot, up)
  })
  for i, rate in rc_rates {
    let (was, at_foot, up) = by_rate[i]
    assert_eq(was, (200.0 - lh_foot, 200.0 - lh_foot), msg="at \{rate} a second: at its foot")
    assert_true(
      at_foot.iter().all(fn(g) { lh_near(g.0, 200.0 - lh_foot_grown) && lh_near(g.1, 200.0 - lh_foot_grown) }),
      msg="at \{rate} a second, at its foot: \{Repr(at_foot)}",
    )
    assert_true(
      up.iter().all(fn(g) { lh_near(g.0, 0.0) && lh_near(g.1, lh_foot_grown - lh_foot) }),
      msg="at \{rate} a second, scrolled up: \{Repr(up)}",
    )
    assert_eq((at_foot, up), (by_rate[0].1, by_rate[0].2), msg="at \{rate} a second")
  }
}

///|
test "a page's list at its foot with a foot, a key come by data making its way: its last block's foot at the foot's top all the way, the same at every rate" {
  let looks = rc_looks(rc_at + 600.0)
  let by_rate = rc_rates.map(fn(rate) {
    let c = lh_case(rc_ten_and([]), foot=lh_foot, follows=true)
    // (its last block's foot read as the list's: at its foot (nothing past what shows), its blocks' room ending at the
    // foot's top; the block on its way drawn whole from its slot's top, under 9's foot, as tall as it comes to)
    rc_walk(c.tree, [(rc_at, fn() { c.keys.set(c.keys.untracked() + [10]) })], looks, rate, fn() {
      (c.scroll.most() - c.scroll.at(c.tree), rc_y(c.tree, "脚"), rc_y(c.tree, "行10") - lh_foot_of(c.tree, "行9"))
    })
  })
  for i, rate in rc_rates {
    let got = by_rate[i]
    assert_true(
      got.iter().all(fn(g) { lh_near(g.0, 0.0) && lh_near(g.1, 200.0 - lh_foot) && lh_near(g.2, 0.0) }),
      msg="at \{rate} a second: \{Repr(got)}",
    )
    assert_eq(got, by_rate[0], msg="at \{rate} a second")
  }
}

///|
test "a page's list's head: a key brought puts its top at the top of what shows, whatever the head's height" {
  for head in [lh_head, 130.0] {
    let place : @view.ListPlace[Int] = @view.ListPlace::new()
    let c = lh_case(Array::makei(30, fn(i) { i }), head~, place~)
    assert_eq(rc_y(c.tree, "头"), 0.0, msg="head \{head}: shown")
    place.bring(12)
    c.tree.frame(390.0, 844.0) |> ignore
    assert_eq(rc_y(c.tree, "行12"), 0.0, msg="head \{head}")
    assert_true(lh_near(c.scroll.at(c.tree), head + 12.0 * 40.0), msg="head \{head}: \{c.scroll.at(c.tree)}")
  }
}

///|
test "a page's list's head: near_top asked by how far its keys start, not by how far it is scrolled" {
  // (a head 150 tall, a screen 200: key 3's top is 270 down what scrolls, the keys' start 120 over what shows: asked;
  // key 9's top 510 down, the keys' start 360 over: not)
  for (k, wanted) in [(9, false), (3, true)] {
    let asked = Ref(0)
    let place : @view.ListPlace[Int] = @view.ListPlace::new()
    let c = lh_case(Array::makei(30, fn(i) { i }), head=150.0, place~, near_top=(1.0, fn() { true }, fn() {
      asked.val = asked.val + 1
    }))
    assert_eq(rc_y(c.tree, "头"), 0.0, msg="the head shown")
    place.bring(k)
    c.tree.frame(390.0, 844.0) |> ignore
    asked.val = 0
    c.tree.at(rc_at)
    c.keys.set(c.keys.untracked() + [30])
    c.tree.frame(390.0, 844.0) |> ignore
    assert_true(lh_near(c.scroll.at(c.tree), 150.0 + k.to_double() * 40.0), msg="key \{k} brought")
    assert_eq(asked.val > 0, wanted, msg="key \{k}: asked \{asked.val}")
  }
}

///|
test "a page's list's foot takes its own presses: one on it reaches no block behind it" {
  let c = lh_case(rc_ten_and([]), foot=lh_foot, follows=true)
  assert_eq(rc_y(c.tree, "脚"), 200.0 - lh_foot, msg="the foot at the foot of what shows")
  // (in the foot, where block 9 is drawn behind it)
  c.tree.at(rc_at)
  c.tree.press(150.0, 200.0 - lh_foot / 2.0) |> ignore
  assert_eq(c.pressed.val, ["脚"])
}

///|
test "a page's list of 1,500 with a head and a foot scrolled: lays out and measures as many as one without, the same rows coming into sight" {
  // (without a head scrolled to 300, with one scrolled to 300 and its height: the same rows in sight; then the same
  // wheel of 60 in both, a row coming into sight in each)
  let work = fn(head : Double?, foot : Double?) {
    let c = lh_case(Array::makei(1500, fn(i) { i }), head?, foot?)
    c.tree.wheel_at(150.0, 100.0, 0.0, 300.0 + head.unwrap_or(0.0), 0, 10.0) |> ignore
    c.tree.at(1000.0)
    c.tree.frame(390.0, 844.0) |> ignore
    let shown = rc_y(c.tree, "行8")
    let w0 = c.tree.work()
    let f0 = @flex.computes()
    c.tree.wheel_at(150.0, 100.0, 0.0, 60.0, 0, 1010.0) |> ignore
    c.tree.at(2000.0)
    c.tree.frame(390.0, 844.0) |> ignore
    let w1 = c.tree.work()
    (shown, rc_y(c.tree, "行13"), [w1.laid - w0.laid, w1.visited - w0.visited, w1.computes - w0.computes, @flex.computes() - f0])
  }
  let without = work(None, None)
  let with_both = work(Some(lh_head), Some(lh_foot))
  assert_eq((without.0, without.1), (20.0, 160.0), msg="without: the rows in sight")
  assert_eq((with_both.0, with_both.1), (20.0, 160.0), msg="with: the same rows in sight")
  assert_eq(with_both.2, without.2)
}

///|
test "a page's list said from_end, short of what shows, with a foot, and with a head and a foot: its last block's foot at the foot's top, not under it; the head at the top of what shows" {
  let c = lh_case([0, 1], foot=lh_foot, from_end=true)
  assert_eq((lh_foot_of(c.tree, "行1"), rc_y(c.tree, "脚")), (200.0 - lh_foot, 200.0 - lh_foot), msg="a foot")
  let b = lh_case([0, 1], head=lh_head, foot=lh_foot, from_end=true)
  assert_eq(
    (rc_y(b.tree, "头"), lh_foot_of(b.tree, "行1"), rc_y(b.tree, "脚")),
    (0.0, 200.0 - lh_foot, 200.0 - lh_foot),
    msg="a head and a foot",
  )
}

///|
test "a page's list's foot drawn over what scrolls: a block lying half behind it drawn whole, its words where they are, the foot drawn after it" {
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let c = lh_case(Array::makei(30, fn(i) { i }), foot=lh_foot, place~)
  // (key 2 at the top: key 6's top at 160, half of it behind the foot, whose top is at 170)
  place.bring(2)
  c.tree.frame(390.0, 844.0) |> ignore
  let drawn = c.tree.drawn()
  let block = drawn.search_by(fn(d) { d.words == "行6" })
  let foot = drawn.search_by(fn(d) { d.words == "脚" })
  match (block, foot) {
    (Some(b), Some(f)) => {
      assert_eq((drawn[b].y, drawn[b].h, drawn[f].y), (160.0, 40.0, 200.0 - lh_foot))
      assert_true(f > b, msg="the foot drawn after the block behind it")
    }
    _ => fail("drawn: \{Repr(drawn.map(fn(d) { d.words }))}")
  }
}

///|
/// A foot holding nothing that takes the hand: its room alone.
fn lh_foot_room(_f : @view.View, _pressed : Ref[Array[String]]) -> Unit {

}

///|
/// A foot holding a button 100 wide at its left, with words 钮, the rest of it its room.
fn lh_foot_button(f : @view.View, pressed : Ref[Array[String]]) -> Unit {
  f.row(Is(true)) |> ignore
  f.box(fn(b) {
    b
    .width(Is(Some(100.0)))
    .words(Is("钮"))
    .on_press(fn() { pressed.val.push("钮") })
    .says(Is(Some(@view.said(Button, label="foot's button"))))
    |> ignore
  })
  |> ignore
}

///|
test "a page's list's foot holding nothing that takes the hand is nothing to it: scrolled off its foot, a press in its strip reaches the block drawn behind it, a wheel there scrolls the list, a pointer resting there is over that block, a drag started there drags the list" {
  // (key 2 at the top of what shows: key 6 drawn 160 to 200, behind the foot's strip, 170 to 200)
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let c = lh_case(Array::makei(30, fn(i) { i }), foot=lh_foot, place~, foot_holds=lh_foot_room)
  place.bring(2)
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq(rc_y(c.tree, "行6"), 160.0, msg="key 6 behind the foot")
  // (a press there)
  c.tree.at(rc_at)
  c.tree.press(150.0, 185.0) |> ignore
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq(c.pressed.val, ["行6"], msg="the press")
  // (a pointer resting there)
  c.tree.point_at(150.0, 185.0)
  assert_eq(c.tree.pointed_now(), Some(c.rows[6].id()), msg="the pointer")
  // (a wheel there)
  let was = c.scroll.at(c.tree)
  c.tree.wheel_at(150.0, 185.0, 0.0, 40.0, 0, rc_at + 100.0) |> ignore
  c.tree.at(rc_at + 1000.0)
  c.tree.frame(390.0, 844.0) |> ignore
  assert_true(lh_near(c.scroll.at(c.tree), was + 40.0), msg="the wheel: \{was} to \{c.scroll.at(c.tree)}")
  // (a drag started there, up past the slop: taken over by the list, as one over the blocks is, and the list dragged)
  let claims = c.tree.claimer_of(c.tree.claimers_at(150.0, 185.0), 0.0, -20.0)
  assert_eq(claims, c.tree.claimer_of(c.tree.claimers_at(150.0, 100.0), 0.0, -20.0), msg="the strip and over the blocks")
  match claims {
    Some(id) => {
      let was = c.scroll.at(c.tree)
      c.tree.drag_at(id, Down, 150.0, 185.0, rc_at + 2000.0) |> ignore
      c.tree.drag_at(id, Moved, 150.0, 165.0, rc_at + 2010.0) |> ignore
      c.tree.drag_at(id, Moved, 150.0, 145.0, rc_at + 2020.0) |> ignore
      c.tree.frame(390.0, 844.0) |> ignore
      assert_true(c.scroll.at(c.tree) > was, msg="the drag: \{was} to \{c.scroll.at(c.tree)}")
    }
    None => fail("a drag in the strip taken over by nothing")
  }
}

///|
test "a page's list's foot holding a button beside its room: the button takes its press, the room passes it to the block behind" {
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let c = lh_case(Array::makei(30, fn(i) { i }), foot=lh_foot, place~, foot_holds=lh_foot_button)
  place.bring(2)
  c.tree.frame(390.0, 844.0) |> ignore
  c.tree.at(rc_at)
  c.tree.press(50.0, 185.0) |> ignore
  c.tree.frame(390.0, 844.0) |> ignore
  c.tree.at(rc_at + 100.0)
  c.tree.press(250.0, 185.0) |> ignore
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq(c.pressed.val, ["钮", "行6"])
}

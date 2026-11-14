// What a page's list reports of a key coming by data on its way in (ListPlace::on_sight): not seen whole, nor the list
// at its end with all of it there whole (`foot_whole`), till that key is drawn whole, at its way's end, told once then
// and nothing on the frames between; where it comes at once (what an answer tells, an `at_once` list, motion reduced),
// whole and at its end in the change. Where the list lays out and is (`at_foot`, `from_foot`) is as ever. Scrolled up,
// a key come out of sight changes nothing of it. In one jump and at 60, 120, 24 and 7 a second (the coordinator of the
// migration, 2026-11-14: the chat told a message read before its words were drawn whole).

///|
priv struct ScoCase {
  tree : @view.Tree
  place : @view.ListPlace[Int]
  keys : @signals.Signal[Array[Int]]
  /// each sight told, in order, with the moment of the cause it was told in (Tree::moment; -1 in none)
  told : Array[(Double, @view.Sight[Int])]
}

///|
/// A page's list 300 by 200 of `n` blocks 40 tall (words 行k), following its foot where `follows`, told what is in sight;
/// said `at_once` where it is, its motion reduced where `reduced`, the keys `whole` says said to come whole. Drawn once,
/// at 0.
fn sco_case(
  n : Int,
  follows? : Bool = true,
  at_once? : Bool = false,
  reduced? : Bool = false,
  whole? : (Int) -> Bool = fn(_) { false },
) -> ScoCase {
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { a == b })
  let told : Array[(Double, @view.Sight[Int])] = []
  let made : Ref[@view.Tree?] = Ref(None)
  place.on_sight(fn(s) {
    let at = match made.val {
      Some(t) => t.moment().unwrap_or(-1.0)
      None => -1.0
    }
    told.push((at, s))
  })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(sg_shows))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=sg_tall,
        follows=fn() { follows },
        comes_whole=whole,
        at_once~,
        place~,
        fn(b, k) { b.height(Is(Some(sg_tall))).words(Is("行\{k}")) |> ignore },
      )
      |> ignore
    })
    |> ignore
  })
  made.val = Some(tree)
  if reduced {
    tree.reduces_motion(fn() { true })
  }
  tree.frame(390.0, 844.0) |> ignore
  { tree, place, keys, told }
}

///|
/// Case `c` walked to `to` at `rate`, frames between, from `from`.
fn sco_walk(c : ScoCase, from : Double, to : Double, rate : Double) -> Unit {
  rc_walk(c.tree, [], [to], rate, from~, fn() { () }) |> ignore
}

///|
/// Where key `k`'s words are drawn (y, height), none where they are not.
fn sco_drawn(c : ScoCase, k : Int) -> (Double, Double)? {
  match c.tree.drawn().filter(fn(d) { d.words == "行\{k}" && d.alpha > 0.0 }) {
    [d, ..] => Some((d.y, d.h))
    _ => None
  }
}

///|
/// Keys `come` come at the foot of case `c` at its end at rc_at in one change (inside an answer where `answer`), walked
/// at `rate` till all is at rest: what was told from then on, and when the ways set off then end (none: -1).
fn sco_come(c : ScoCase, come : Array[Int], rate : Double, answer? : Bool = false) -> (Array[(Double, @view.Sight[Int])], Double) {
  let n = c.told.length()
  let at = rc_at
  c.tree.event(at, fn() {
    if answer {
      @view.answering(fn() { c.keys.set(c.keys.untracked() + come) })
    } else {
      c.keys.set(c.keys.untracked() + come)
    }
  })
  let ends = c.tree.ways_end()
  sco_walk(c, at, at + @flex.move_most_ms + 200.0, rate)
  (c.told[n:].to_owned(), ends)
}

///|
test "a key coming by data at the foot of a list at its end: at the change the key before it the last seen whole, not at its end whole; nothing on its way; once at its way's end, the new key whole and at its end, the same at every rate" {
  for rate in rc_rates {
    let c = sco_case(30)
    let (told, ends) = sco_come(c, [30], rate)
    assert_true(ends > rc_at, msg="at \{rate} a second: its way's end \{ends}")
    assert_eq(told.length(), 2, msg="at \{rate} a second: \{Repr(told)}")
    assert_eq(told[0].0, rc_at, msg="at \{rate} a second: told at the change")
    assert_eq(
      told[0].1,
      { first: 26, into: 0.0, last: 30, whole: Some(29), from_foot: 0.0, shows: sg_shows, at_foot: true, foot_whole: false },
      msg="at \{rate} a second",
    )
    assert_eq(told[1].0, ends, msg="at \{rate} a second: told at its way's end")
    assert_eq(told[1].1, { ..told[0].1, whole: Some(30), foot_whole: true }, msg="at \{rate} a second")
    // (and its words drawn whole by then: where they rest, as tall)
    assert_eq(sco_drawn(c, 30), Some((160.0, sg_tall)), msg="at \{rate} a second")
  }
}

///|
test "a key coming: what is told of it is as it is drawn, its words not whole on any frame before what tells it seen whole" {
  let c = sco_case(30)
  let at = rc_at
  c.tree.event(at, fn() { c.keys.set(c.keys.untracked() + [30]) })
  let ends = c.tree.ways_end()
  let mut t = at
  while t < ends {
    c.tree.at(t)
    c.tree.frame(390.0, 844.0) |> ignore
    let told = c.told[c.told.length() - 1]
    let drawn = sco_drawn(c, 30)
    if told.1.whole == Some(30) || told.1.foot_whole {
      assert_eq(drawn, Some((160.0, sg_tall)), msg="at \{t}: told \{Repr(told)}, drawn \{Repr(drawn)}")
    }
    t = t + 1000.0 / 120.0
  }
}

///|
test "two keys come at its foot in one change: neither seen whole nor at its end whole till their way ends, told once then, the same at every rate" {
  for rate in rc_rates {
    let c = sco_case(30)
    let (told, ends) = sco_come(c, [30, 31], rate)
    assert_eq(told.length(), 2, msg="at \{rate} a second: \{Repr(told)}")
    assert_eq(told[0].0, rc_at, msg="at \{rate} a second")
    assert_eq((told[0].1.last, told[0].1.whole, told[0].1.at_foot, told[0].1.foot_whole), (31, Some(29), true, false), msg="at \{rate} a second")
    assert_eq(told[1].0, ends, msg="at \{rate} a second")
    assert_eq((told[1].1.last, told[1].1.whole, told[1].1.at_foot, told[1].1.foot_whole), (31, Some(31), true, true), msg="at \{rate} a second")
  }
}

///|
test "a key said to come whole is on its way all the same: seen whole and at its end whole once its way ends, the same at every rate" {
  for rate in rc_rates {
    let c = sco_case(30, whole=fn(k) { k == 30 })
    let (told, ends) = sco_come(c, [30], rate)
    assert_eq(told.length(), 2, msg="at \{rate} a second: \{Repr(told)}")
    assert_eq((told[0].1.whole, told[0].1.foot_whole), (Some(29), false), msg="at \{rate} a second")
    assert_eq(told[1].0, ends, msg="at \{rate} a second")
    assert_eq((told[1].1.whole, told[1].1.foot_whole), (Some(30), true), msg="at \{rate} a second")
  }
}

///|
test "a key come at once (what an answer tells, an at_once list, motion reduced): whole and at its end whole in the change, told once, the same at every rate" {
  for how in ["answer", "at_once", "reduced"] {
    for rate in rc_rates {
      let c = sco_case(30, at_once=how == "at_once", reduced=how == "reduced")
      let (told, _) = sco_come(c, [30], rate, answer=how == "answer")
      assert_eq(told.length(), 1, msg="\{how}, at \{rate} a second: \{Repr(told)}")
      assert_eq(told[0].0, rc_at, msg="\{how}, at \{rate} a second")
      assert_eq(
        told[0].1,
        { first: 26, into: 0.0, last: 30, whole: Some(30), from_foot: 0.0, shows: sg_shows, at_foot: true, foot_whole: true },
        msg="\{how}, at \{rate} a second",
      )
    }
  }
}

///|
test "scrolled up, a key coming at its end out of sight: what is seen whole and its end as before it, further from its foot by as tall, the same at every rate" {
  for rate in rc_rates {
    let c = sco_case(30, follows=false)
    c.tree.event(50.0, fn() { c.place.bring(2) })
    c.tree.at(50.0)
    c.tree.frame(390.0, 844.0) |> ignore
    let was = c.place.sight_now().unwrap()
    let (told, _) = sco_come(c, [30], rate)
    assert_eq(told.length(), 1, msg="at \{rate} a second: \{Repr(told)}")
    assert_eq(told[0].1, { ..was, from_foot: was.from_foot + sg_tall }, msg="at \{rate} a second")
    assert_true(!told[0].1.at_foot && !told[0].1.foot_whole, msg="at \{rate} a second")
  }
}

///|
test "a key that comes and goes before its way ends: never seen whole; at its end whole again as it goes, nothing told after, the same at every rate" {
  for rate in rc_rates {
    let c = sco_case(30)
    let n = c.told.length()
    let at = rc_at
    let gone = at + 50.0
    rc_walk(
      c.tree,
      [(at, fn() { c.keys.set(c.keys.untracked() + [30]) }), (gone, fn() { c.keys.set(Array::makei(30, fn(i) { i })) })],
      [at + @flex.move_most_ms + 200.0],
      rate,
      from=0.0,
      fn() { () },
    )
    |> ignore
    let told = c.told[n:].to_owned()
    assert_true(told.iter().all(fn(s) { s.1.whole != Some(30) }), msg="at \{rate} a second: \{Repr(told)}")
    assert_eq(told.length(), 2, msg="at \{rate} a second: \{Repr(told)}")
    assert_eq((told[0].0, told[0].1.whole, told[0].1.foot_whole), (at, Some(29), false), msg="at \{rate} a second")
    assert_eq(told[1].0, gone, msg="at \{rate} a second")
    assert_eq((told[1].1.last, told[1].1.whole, told[1].1.at_foot, told[1].1.foot_whole), (29, Some(29), true, true), msg="at \{rate} a second")
  }
}
